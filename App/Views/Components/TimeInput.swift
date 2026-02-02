import SwiftUI

/// Reusable time input component that displays and accepts MM:SS:FF or decimal seconds
struct TimeInput: View {
    @Binding var seconds: Double
    let label: String
    let sourceDuration: Double
    var frameRate: Double = 30.0
    var compact: Bool = true

    @State private var textValue: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TextField("", text: $textValue)
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: compact ? 52 : 64)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isFocused ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .focused($isFocused)
                .onAppear {
                    textValue = formatTime(seconds)
                }
                .onChange(of: seconds) { newValue in
                    if !isEditing {
                        textValue = formatTime(newValue)
                    }
                }
                .onChange(of: isFocused) { focused in
                    if focused {
                        isEditing = true
                    } else {
                        isEditing = false
                        commitValue()
                    }
                }
                .onSubmit {
                    commitValue()
                    isFocused = false
                }
        }
    }

    // MARK: - Formatting

    private func formatTime(_ time: Double) -> String {
        let clampedTime = max(0, min(time, sourceDuration))
        let totalSeconds = Int(clampedTime)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let frames = Int((clampedTime - Double(totalSeconds)) * frameRate)
        return String(format: "%d:%02d:%02d", minutes, secs, frames)
    }

    // MARK: - Parsing

    private func commitValue() {
        if let parsedSeconds = parseTimeInput(textValue) {
            let clamped = max(0, min(parsedSeconds, sourceDuration))
            seconds = clamped
            textValue = formatTime(clamped)
        } else {
            // Invalid input - revert to current value
            textValue = formatTime(seconds)
        }
    }

    /// Parse time input in various formats:
    /// - MM:SS:FF (e.g., "1:30:15" = 1 minute, 30 seconds, 15 frames)
    /// - MM:SS (e.g., "1:30" = 1 minute, 30 seconds)
    /// - Decimal seconds (e.g., "90.5" = 90.5 seconds)
    private func parseTimeInput(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Check for colon-separated format
        let components = trimmed.split(separator: ":")

        if components.count == 3 {
            // MM:SS:FF format
            guard let minutes = Int(components[0]),
                  let secs = Int(components[1]),
                  let frames = Int(components[2]) else {
                return nil
            }
            return Double(minutes * 60 + secs) + Double(frames) / frameRate

        } else if components.count == 2 {
            // MM:SS format
            guard let minutes = Int(components[0]),
                  let secs = Int(components[1]) else {
                return nil
            }
            return Double(minutes * 60 + secs)

        } else if components.count == 1 {
            // Plain seconds (decimal)
            return Double(trimmed)
        }

        return nil
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var time: Double = 65.5

        var body: some View {
            VStack(spacing: 20) {
                HStack {
                    TimeInput(seconds: $time, label: "START", sourceDuration: 300.0)
                    TimeInput(seconds: $time, label: "END", sourceDuration: 300.0)
                }

                Text("Current: \(time, specifier: "%.2f") seconds")
                    .foregroundStyle(.secondary)

                Slider(value: $time, in: 0...300)
                    .frame(width: 200)
            }
            .padding()
            .background(Color(white: 0.1))
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
