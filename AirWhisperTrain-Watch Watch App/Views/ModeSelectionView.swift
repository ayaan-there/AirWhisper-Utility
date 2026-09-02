import SwiftUI

struct ModeSelectionView: View {
    let onSelect: (WatchMode) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "hand.draw")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("AirWhisper")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Choose a mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            VStack(spacing: 16) {
                // Train Button
                Button {
                    onSelect(.train)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Train")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Record samples for a letter")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Train mode - Record samples for a letter")
                .accessibilityHint("Tap to start recording training samples")
                
                // Test Button
                Button {
                    onSelect(.test)
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Write in air, get prediction")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Test mode - Write in air to get prediction")
                .accessibilityHint("Tap to start inference mode")
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
    }
}
