import SwiftUI

struct DrawingView: View {

    let letter: String
    let onSubmitted: (String, DrawingPattern?) -> Void

    @StateObject private var session = DrawingSession()
    @State private var showReplay = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            guideRow
            canvasArea
            toolbar
            if showReplay {
                replayCard
            }
            submitButton
        }
        .navigationTitle("Draw \(letter)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var replayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replay — how you drew \(letter)")
                .font(.subheadline.weight(.semibold))
            if let pattern = session.makePattern() {
                DrawingReplayView(pattern: pattern)
            } else {
                Text("Draw something to replay it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var header: some View {
        HStack {
            Text("Draw the letter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if session.hasStrokes {
                Button {
                    showReplay.toggle()
                } label: {
                    Label(showReplay ? "Hide" : "Replay", systemImage: "play.circle")
                        .font(.subheadline)
                }
            }
            Button {
                session.clear()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
            }
            .disabled(!session.hasStrokes)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var guideRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.brandBlue.opacity(0.12))
                Text(letter)
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(AppTheme.brandBlue)
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("How to draw")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(LetterGuide.instruction(for: letter))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private var canvasArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.brandBlue.opacity(0.25), lineWidth: 1.5)

            if !session.hasStrokes && !session.isEraser {
                Text("Draw \(letter) here")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }

            DrawCanvasRepresentable(session: session)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // Constants for drawing toolbar
private enum DrawingConstants {
    static let minWidth: CGFloat = 2
    static let maxWidth: CGFloat = 30
    static let widthStep: CGFloat = 2
}

private var toolbar: some View {
        HStack(spacing: 12) {
            toolButton(icon: "pencil.tip", isActive: !session.isEraser, accessibilityLabel: "Pen") {
                session.isEraser = false
            }

            toolButton(icon: "eraser", isActive: session.isEraser, accessibilityLabel: "Eraser") {
                session.isEraser = true
            }

            Spacer()

            Button {
                session.width = max(DrawingConstants.minWidth, session.width - DrawingConstants.widthStep)
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Decrease stroke width")

            Text(String(format: "%.0f", session.width))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            Button {
                session.width = min(DrawingConstants.maxWidth, session.width + DrawingConstants.widthStep)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Increase stroke width")

            Spacer()

            toolButton(icon: "arrow.uturn.backward", isActive: false, accessibilityLabel: "Undo") {
                session.undo()
            }
            .disabled(session.strokeCount == 0)

            toolButton(icon: "arrow.uturn.forward", isActive: false, accessibilityLabel: "Redo") {
                session.redo()
            }
            .disabled(session.redoCount == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func toolButton(icon: String, isActive: Bool, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(isActive ? AppTheme.brandBlue : Color(.secondarySystemBackground))
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var submitButton: some View {
        Button {
            onSubmitted(letter, session.makePattern())
        } label: {
            Text("Submit")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(session.hasStrokes ? Color.white : Color.gray.opacity(0.5))
                .foregroundStyle(session.hasStrokes ? AppTheme.brandBlue : .white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.brandBlue, lineWidth: session.hasStrokes ? 2 : 0))
        }
        .buttonStyle(.plain)
        .disabled(!session.hasStrokes)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }
}
