import Foundation
import WebKit

/// Evaluates page state natively via `evaluateJavaScript` async calls.
///
/// Replaces legacy JSON bridge callbacks with direct DOM inspection using
/// the native WebKit API. Runs DOM queries directly and returns strictly
/// `Sendable` results.
@MainActor
final class DOMParserService {

    // MARK: - Fingerprint Detection Keywords

    /// Keywords in the DOM that indicate SMS/2FA fingerprint detection (Burn trigger).
    private static let fingerprintKeywords: [String] = [
        "sms", "text message", "verification code", "verify your phone",
        "send code", "sent a code", "enter the code", "phone verification",
        "mobile verification", "confirm your number", "code sent",
        "enter code", "security code sent", "check your phone",
        "two-factor", "2fa", "two factor"
    ]

    /// Keywords indicating a disabled account.
    private static let disabledKeywords: [String] = [
        "has been disabled", "account disabled", "permanently disabled",
        "account is disabled", "temporarily disabled"
    ]

    /// Keywords indicating a successful login.
    private static let successKeywords: [String] = [
        "balance", "wallet", "my account", "logout", "log out",
        "welcome", "dashboard", "deposit"
    ]

    /// Keywords indicating no account exists.
    private static let noAccountKeywords: [String] = [
        "no account", "incorrect", "invalid", "not found",
        "doesn't exist", "does not exist"
    ]

    // MARK: - DOM Evaluation

    /// Evaluates the current DOM state of a WKWebView after a login attempt.
    /// Returns a strictly `Sendable` `LoginEvaluation`.
    func evaluateLoginResult(webView: WKWebView) async -> LoginEvaluation {
        let pageTextJS = """
        (function(){
            return document.body ? document.body.innerText.toLowerCase() : '';
        })()
        """

        guard let pageText = await webView.evaluateJSString(pageTextJS) else {
            return LoginEvaluation(
                isSuccess: false,
                isDisabled: false,
                isFingerprinted: false,
                isNoAccount: false,
                rawPageContent: ""
            )
        }

        let lowered = pageText.lowercased()

        let isFingerprinted = Self.fingerprintKeywords.contains { lowered.contains($0) }
        let isDisabled = Self.disabledKeywords.contains { lowered.contains($0) }
        let isSuccess = Self.successKeywords.contains { lowered.contains($0) }
        let isNoAccount = Self.noAccountKeywords.contains { lowered.contains($0) }

        return LoginEvaluation(
            isSuccess: isSuccess && !isDisabled && !isFingerprinted,
            isDisabled: isDisabled,
            isFingerprinted: isFingerprinted,
            isNoAccount: isNoAccount && !isSuccess,
            rawPageContent: String(pageText.prefix(500))
        )
    }

    /// Checks if a specific error banner is visible on the page.
    func checkForErrorBanner(webView: WKWebView) async -> String? {
        let bannerJS = """
        (function(){
            var selectors = ['.error-banner', '.alert-danger', '.alert-error',
                             '.login-error', '.notification-error', "[role='alert']"];
            for (var i = 0; i < selectors.length; i++) {
                var el = document.querySelector(selectors[i]);
                if (el && el.offsetParent !== null) {
                    return el.innerText.trim();
                }
            }
            return null;
        })()
        """

        return await webView.evaluateJSString(bannerJS)
    }

    /// Returns the current page URL from the DOM.
    func currentPageURL(webView: WKWebView) async -> String? {
        await webView.evaluateJSString("window.location.href")
    }
}
