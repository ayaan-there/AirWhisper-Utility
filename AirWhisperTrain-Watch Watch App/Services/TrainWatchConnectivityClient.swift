import Foundation
import WatchConnectivity
import Combine

/// Watch-side WatchConnectivity client for AirWhisper training and testing.
///
/// This class manages communication with the iPhone companion app:
/// - Receiving letter selection and expected index from iPhone
/// - Sending recorded IMU samples to iPhone (train mode)
/// - Requesting current state on app launch/foreground
/// - Message acknowledgment and retry with exponential backoff
/// - Delivery confirmation callbacks
///
/// Thread Safety: All public methods and callbacks run on MainActor.
/// WCSessionDelegate methods are marked `nonisolated` and dispatch to MainActor.
@MainActor
final class TrainWatchConnectivityClient: NSObject, ObservableObject {

    static let shared = TrainWatchConnectivityClient()

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isCompanionAppInstalled: Bool = true
    @Published private(set) var currentLetter: String?
    @Published private(set) var expectedIndex: Int = 1

    var onDeliveryConfirmed: (@MainActor (UUID, Bool) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingMessages: [UUID: PendingMessage] = [:]
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 0.5

    private struct PendingMessage {
        let id: UUID
        let data: Data
        let retryCount: Int
        let payloadType: TrainPayloadType
        var task: Task<Void, Never>?
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func setReachableState() {
        guard WCSession.isSupported() else { return }
        isReachable = WCSession.default.isReachable
        applyApplicationContext(WCSession.default.receivedApplicationContext)
    }

    func sendRecording(_ recording: IMURecording) {
        let payload = TrainRecordingPayload(type: .recordingPayload, recording: recording)
        send(payload)
    }

    func sendRecordings(_ recordings: [IMURecording]) {
        for recording in recordings {
            let payload = TrainRecordingPayload(type: .recordingPayload, recording: recording)
            send(payload)
        }
    }

    func requestCurrentState() {
        let payload = TrainPayload(type: .requestState)
        send(payload)
    }

    private func send(_ payload: Encodable) {
        guard WCSession.isSupported() else { return }
        do {
            let data = try encoder.encode(payload)
            let session = WCSession.default
            isReachable = session.isReachable

            let payloadType: TrainPayloadType
            if let envelope = try? decoder.decode(TrainPayload.self, from: data) {
                payloadType = envelope.type
            } else {
                payloadType = .requestState
            }

            if session.isReachable {
                let messageId = UUID()
                let pending = PendingMessage(
                    id: messageId,
                    data: data,
                    retryCount: 0,
                    payloadType: payloadType
                )
                pendingMessages[messageId] = pending

                session.sendMessageData(data, replyHandler: { [weak self] replyData in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handleReply(messageId: messageId, replyData: replyData)
                    }
                }) { [weak self] error in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handleSendFailure(messageId: messageId, error: error)
                    }
                }
            } else {
                queueFallback(data)
            }
        } catch {
            print("TrainWatchConnectivity: send failed \(error)")
        }
    }

    private func handleReply(messageId: UUID, replyData: Data) {
        guard let pending = pendingMessages.removeValue(forKey: messageId) else { return }
        pending.task?.cancel()

        if let envelope = try? decoder.decode(TrainPayload.self, from: replyData) {
            switch envelope.type {
            case .letterSelected:
                if let payload = try? decoder.decode(TrainLetterSelectedPayload.self, from: replyData) {
                    print("TrainWatch: delivery confirmed for \(pending.payloadType) letter=\(payload.letter) expectedIndex=\(payload.expectedIndex)")
                    onDeliveryConfirmed?(messageId, true)
                }
            case .recordingAccepted:
                if let payload = try? decoder.decode(TrainRecordingAcceptedPayload.self, from: replyData) {
                    print("TrainWatch: delivery confirmed for \(pending.payloadType) letter=\(payload.letter) nextIndex=\(payload.nextIndex)")
                    onDeliveryConfirmed?(messageId, true)
                }
            case .stateResponse:
                if let payload = try? decoder.decode(TrainStateResponsePayload.self, from: replyData) {
                    print("TrainWatch: delivery confirmed for stateResponse letter=\(payload.letter ?? "nil") count=\(payload.count)")
                    onDeliveryConfirmed?(messageId, true)
                }
            default:
                print("TrainWatch: unexpected reply type \(envelope.type) for message \(messageId)")
                onDeliveryConfirmed?(messageId, false)
            }
        } else {
            print("TrainWatch: failed to decode reply for message \(messageId)")
            onDeliveryConfirmed?(messageId, false)
        }
    }

    private func handleSendFailure(messageId: UUID, error: Error) {
        guard var pending = pendingMessages[messageId] else { return }

        print("TrainWatch: send failed (attempt \(pending.retryCount + 1)/\(maxRetries)): \(error)")

        if pending.retryCount < maxRetries {
            let nextRetryCount = pending.retryCount + 1
            let delay = baseRetryDelay * pow(2.0, Double(pending.retryCount))

            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.retrySend(messageId: messageId, retryCount: nextRetryCount)
            }

            pendingMessages[messageId] = PendingMessage(
                id: pending.id,
                data: pending.data,
                retryCount: nextRetryCount,
                payloadType: pending.payloadType,
                task: task
            )
        } else {
            print("TrainWatch: max retries exceeded for message \(messageId), falling back to transferUserInfo")
            pendingMessages.removeValue(forKey: messageId)
            pending.task?.cancel()
            queueFallback(pending.data)
            onDeliveryConfirmed?(messageId, false)
        }
    }

    private func retrySend(messageId: UUID, retryCount: Int) async {
        guard var pending = pendingMessages[messageId] else { return }
        let session = WCSession.default

        guard session.isReachable else {
            print("TrainWatch: session not reachable for retry \(messageId), falling back")
            pendingMessages.removeValue(forKey: messageId)
            pending.task?.cancel()
            queueFallback(pending.data)
            onDeliveryConfirmed?(messageId, false)
            return
        }

        session.sendMessageData(pending.data, replyHandler: { [weak self] replyData in
            guard let self else { return }
            Task { @MainActor in
                self.handleReply(messageId: messageId, replyData: replyData)
            }
        }) { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.handleSendFailure(messageId: messageId, error: error)
            }
        }
    }

    private func queueFallback(_ data: Data) {
        WCSession.default.transferUserInfo(["payload": data])
        print("TrainWatch: queued fallback via transferUserInfo")
    }

    private func handleIncoming(_ data: Data) {
        guard let envelope = try? decoder.decode(TrainPayload.self, from: data) else { return }
        switch envelope.type {
        case .letterSelected:
            if let payload = try? decoder.decode(TrainLetterSelectedPayload.self, from: data) {
                currentLetter = payload.letter
                expectedIndex = payload.expectedIndex
            }
        case .recordingAccepted:
            if let payload = try? decoder.decode(TrainRecordingAcceptedPayload.self, from: data) {
                currentLetter = payload.letter
                expectedIndex = payload.nextIndex
            }
        case .stateResponse:
            if let payload = try? decoder.decode(TrainStateResponsePayload.self, from: data),
               let letter = payload.letter {
                currentLetter = letter
                expectedIndex = payload.count + 1
            }
        case .recordingPayload, .requestState:
            break
        }
    }

    private var contextKey = "airWhisperState"

    private func applyApplicationContext(_ ctx: [String: Any]) {
        guard let state = ctx[contextKey] as? [String: Any] else { return }
        if let letter = state["letter"] as? String {
            currentLetter = letter
        }
        if let count = state["count"] as? Int {
            expectedIndex = max(1, count + 1)
        }
        print("TrainWatch: applied context letter=\(currentLetter ?? "nil") index=\(expectedIndex)")
    }
}

extension TrainWatchConnectivityClient: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.isCompanionAppInstalled = session.isCompanionAppInstalled
            if activationState == .activated {
                self.applyApplicationContext(session.receivedApplicationContext)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isCompanionAppInstalled = session.isCompanionAppInstalled
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.handleIncoming(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Task { @MainActor in
            self.handleIncoming(data)
        }
    }
}

private struct TrainPayload: Codable {
    let type: TrainPayloadType
}