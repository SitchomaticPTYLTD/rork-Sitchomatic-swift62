import SwiftUI

/// A 1–7 slider that directly controls the TaskGroup concurrency limit.
///
/// Each slider unit corresponds to 1 concurrent session per platform
/// (×2 for dual-site = 2–14 total WebView instances).
///
/// The slider visually communicates the Jetsam risk level:
/// - 1–3: Safe (green)
/// - 4–5: Moderate (yellow)
/// - 6–7: Maximum throughput / high memory pressure (red)
struct ConcurrencySlider: View {

    @Binding var value: Double

    private var intValue: Int { Int(value) }

    private var totalSessions: Int { intValue * 2 }

    private var riskColor: Color {
        switch intValue {
        case 1...3: .green
        case 4...5: .yellow
        default: .red
        }
    }

    private var riskLabel: String {
        switch intValue {
        case 1...3: "Safe"
        case 4...5: "Moderate"
        default: "Maximum"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Concurrency", systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack {
                Text("1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $value, in: 1...7, step: 1)
                    .tint(riskColor)
                Text("7")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(intValue) per site · \(totalSessions) total WebViews")
                    .font(.caption)
                Spacer()
                Text(riskLabel)
                    .font(.caption.bold())
                    .foregroundStyle(riskColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
