import Foundation
import WatchConnectivity
import Combine

/// Manages WatchConnectivity communication between iPhone and Apple Watch for training mode.
///
/// This class handles:
/// - Sending letter selection and expected index to Watch
/// - Receiving recorded IMU samples from Watch
/// - Reliable state synchronization via `applicationContext`
/// - Message acknowledgment and retry with exponential backoff
/// - Delivery confirmation callbacks
///
/// Thread Safety: All public methods and callbacks run on MainActor.
/// WCSessionDelegate methods are marked `nonisolated` and dispatch to MainActor.
@MainActor
final class TrainPhoneConnectivityManager: NSObject, ObservableObject {

    static let shared = TrainPhoneConnectivityManager()

    @Published private(set) var isReachable: Bool = false
    @Published var currentLetter: String?

    var onReceivedRecording: (@MainActor (IMURecording) -> Void)?
    var onStateRequested: (() -> TrainStateResponsePayload)?
    var onDeliveryConfirmed: (@MainActor (UUID, Bool) -> Void)?

    private var latestContextCount: Int = 0

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

    func selectLetter(_ letter: String, expectedIndex: Int) {
        currentLetter = letter
        latestContextCount = max(0, expectedIndex - 1)
        tryUpdateContext()
        send(TrainLetterSelectedPayload(type: .letterSelected, letter: letter, expectedIndex: expectedIndex))
    }

    func sendAccepted(letter: String, nextIndex: Int) {
        currentLetter = letter
        latestContextCount = max(0, nextIndex - 1)
        tryUpdateContext()
        send(TrainRecordingAcceptedPayload(type: .recordingAccepted, letter: letter, nextIndex: nextIndex))
    }

    private var contextKey = "airWhisperState"

    private func tryUpdateContext() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("TrainPhone: context skipped (session not activated), will resend on activation")
            return
        }
        var ctx: [String: Any] = [self.contextKey: ["letter": currentLetter as Any, "count": latestContextCount]]
        do {
            try session.updateApplicationContext(ctx)
            print("TrainPhone: pushed context letter=\(currentLetter ?? "nil") count=\(latestContextCount)")
        } catch {
            print("TrainPhone: updateApplicationContext error \(error)")
        }
    }

    private func resendLatestState() {
        guard currentLetter != nil else { return }
        tryUpdateContext()
    }

    func send<T: Encodable>(_ payload: T) {
        guard WCSession.isSupported() else { return }
        do {
            let data = try encoder.encode(payload)
            let session = WCSession.default
            isReachable = session.isReachable

            let payloadType: TrainPayloadType
            if let envelope = try? decoder.decode(TrainPayload.self, from: data) {
                payloadType = envelope.type
            } else {
                payloadType = .stateResponse
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
            print("TrainPhoneConnectivity: send failed \(error)")
        }
    }

    private func handleReply(messageId: UUID, replyData: Data) {
        guard let pending = pendingMessages.removeValue(forKey: messageId) else { return }
        pending.task?.cancel()

        if let envelope = try? decoder.decode(TrainPayload.self, from: replyData),
           envelope.type == .recordingAccepted {
            if let acceptedPayload = try? decoder.decode(TrainRecordingAcceptedPayload.self, from: replyData) {
                print("TrainPhone: delivery confirmed for \(pending.payloadType) letter=\(acceptedPayload.letter) nextIndex=\(acceptedPayload.nextIndex)")
                onDeliveryConfirmed?(pending.id, true)
            }
        } else {
            print("TrainPhone: unexpected reply type for message \(messageId)")
            onDeliveryConfirmed?(messageId, false)
        }
    }

    private func handleSendFailure(messageId: UUID, error: Error) {
        guard var pending = pendingMessages[messageId] else { return }

        print("TrainPhone: send failed (attempt \(pending.retryCount + 1)/\(maxRetries)): \(error)")

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
            print("TrainPhone: max retries exceeded for message \(messageId), falling back to transferUserInfo")
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
            print("TrainPhone: session not reachable for retry \(messageId), falling back")
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
        print("TrainPhone: queued fallback via transferUserInfo")
    }

    private func handleIncoming(_ data: Data) {
        guard let envelope = try? decoder.decode(TrainPayload.self, from: data) else { return }
        switch envelope.type {
        case .recordingPayload:
            guard let payload = try? decoder.decode(TrainRecordingPayload.self, from: data) else { return }
            let recording = payload.recording
            print("TrainPhone: received recording \(recording.id) letter=\(recording.letter) index=\(recording.index)")

            onReceivedRecording?(recording)

            let acceptedPayload = TrainRecordingAcceptedPayload(
                type: .recordingAccepted,
                letter: recording.letter,
                nextIndex: recording.index + 1
            )
            send(acceptedPayload)

        case .requestState:
            let response = onStateRequested?() ?? TrainStateResponsePayload(type: .stateResponse, letter: currentLetter, count: 0)
            send(response)

        case .letterSelected, .recordingAccepted, .stateResponse:
            break
        }
    }
}

extension TrainPhoneConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if activationState == .activated {
                self.resendLatestState()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
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

private struct TrainPayload: Decodable {
    let type: TrainPayloadType
}