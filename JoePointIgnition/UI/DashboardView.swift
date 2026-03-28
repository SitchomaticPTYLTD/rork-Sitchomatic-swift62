import SwiftUI
import Observation

/// Main dashboard view for the JoePointIgnition automation engine.
///
/// Displays real-time progress of the 3-Password Vertical Matrix,
/// found logins, disabled email count, and the concurrency slider.
struct DashboardView: View {

    @State private var engine = DualFindEngine()
    @State private var emailInput: String = ""
    @State private var password1: String = ""
    @State private var password2: String = ""
    @State private var password3: String = ""
    @State private var concurrentLimit: Double = 3
    @State private var isRunning: Bool = false
    @State private var foundLogins: [FoundLogin] = []
    @State private var completedTests: Int = 0
    @State private var totalTests: Int = 0

    private var parsedEmails: [String] {
        emailInput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("@") }
    }

    private var canStart: Bool {
        !parsedEmails.isEmpty
        && !password1.trimmingCharacters(in: .whitespaces).isEmpty
        && !password2.trimmingCharacters(in: .whitespaces).isEmpty
        && !password3.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var progressFraction: Double {
        guard totalTests > 0 else { return 0 }
        return Double(completedTests) / Double(totalTests)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    emailSection
                    passwordSection
                    ConcurrencySlider(value: $concurrentLimit)
                    controlSection
                    if isRunning || completedTests > 0 {
                        progressSection
                    }
                    if !foundLogins.isEmpty {
                        resultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("JoePoint Ignition")
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sections

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Email List", systemImage: "envelope.fill")
                .font(.headline)
            TextEditor(text: $emailInput)
                .frame(minHeight: 120)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("\(parsedEmails.count) emails parsed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("3-Password Matrix", systemImage: "key.fill")
                .font(.headline)
            SecureField("Password 1", text: $password1)
                .textFieldStyle(.roundedBorder)
            SecureField("Password 2", text: $password2)
                .textFieldStyle(.roundedBorder)
            SecureField("Password 3", text: $password3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var controlSection: some View {
        HStack(spacing: 16) {
            Button {
                startMatrix()
            } label: {
                Label("Start Matrix", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canStart || isRunning)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: progressFraction)
                .tint(.blue)
            HStack {
                Text("\(completedTests)/\(totalTests) tests")
                    .font(.caption)
                Spacer()
                Text("Pass \(Int(engine.currentPasswordIndex) + 1)/3")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Found Logins (\(foundLogins.count))", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)

            ForEach(foundLogins) { login in
                HStack {
                    VStack(alignment: .leading) {
                        Text(login.email)
                            .font(.system(.body, design: .monospaced))
                        Text(login.platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = login.exportText
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func startMatrix() {
        let emails = parsedEmails
        let passwords = [password1, password2, password3]
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let limit = Int(concurrentLimit)

        isRunning = true
        totalTests = emails.count * passwords.count * TargetPlatform.allCases.count

        Task {
            await engine.runMatrix(
                emails: emails,
                passwords: passwords,
                concurrentLimit: limit,
                onProgress: { @Sendable completed, total, _ in
                    Task { @MainActor in
                        completedTests = completed
                        totalTests = total
                    }
                }
            )

            await MainActor.run {
                foundLogins = engine.foundLogins
                isRunning = false
            }
        }
    }
}
