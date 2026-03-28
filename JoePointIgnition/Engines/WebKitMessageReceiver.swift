import Foundation
import WebKit

/// Modern WebKit message handler using `WKScriptMessageHandlerWithReply`.
///
/// Replaces all legacy `WKScriptMessageHandler` delegate callbacks and JSON
/// stringification bridges. All JS↔Swift interactions become native
/// `async/await` calls directly into the WebKit kernel.
@MainActor
final class WebKitMessageReceiver: NSObject, WKScriptMessageHandlerWithReply {

    /// Known message types the receiver can process.
    enum MessageType: String, Sendable {
        case loginResult = "loginResult"
        case domState = "domState"
        case fingerprintDetected = "fingerprintDetected"
        case pageReady = "pageReady"
        case errorBanner = "errorBanner"
    }

    /// Callback invoked when a fingerprint/2FA is detected in the DOM.
    var onFingerprintDetected: (@Sendable () async -> Void)?

    /// Callback invoked when a login result is received.
    var onLoginResult: (@Sendable (LoginEvaluation) async -> Void)?

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let messageType = MessageType(rawValue: message.name) else {
            replyHandler(nil, "Unknown message type: \(message.name)")
            return
        }

        let body = message.body

        Task {
            switch messageType {
            case .loginResult:
                let evaluation = parseLoginResult(body)
                await onLoginResult?(evaluation)
                replyHandler(["status": "acknowledged"], nil)

            case .domState:
                replyHandler(["status": "received"], nil)

            case .fingerprintDetected:
                await onFingerprintDetected?()
                replyHandler(["action": "burn_and_rotate"], nil)

            case .pageReady:
                replyHandler(["status": "ready"], nil)

            case .errorBanner:
                replyHandler(["status": "logged"], nil)
            }
        }
    }

    // MARK: - Registration

    /// Registers all message handlers on a `WKWebViewConfiguration`.
    func register(on configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        for type in MessageType.allCases {
            controller.addScriptMessageHandler(self, contentWorld: .page, name: type.rawValue)
        }
    }

    /// Removes all registered message handlers.
    func unregister(from configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        for type in MessageType.allCases {
            controller.removeScriptMessageHandler(forName: type.rawValue)
        }
    }

    // MARK: - Parsing

    private func parseLoginResult(_ body: Any) -> LoginEvaluation {
        guard let dict = body as? [String: Any] else {
            return LoginEvaluation(
                isSuccess: false,
                isDisabled: false,
                isFingerprinted: false,
                isNoAccount: false,
                rawPageContent: String(describing: body)
            )
        }

        return LoginEvaluation(
            isSuccess: dict["success"] as? Bool ?? false,
            isDisabled: dict["disabled"] as? Bool ?? false,
            isFingerprinted: dict["fingerprinted"] as? Bool ?? false,
            isNoAccount: dict["noAccount"] as? Bool ?? false,
            rawPageContent: dict["pageContent"] as? String ?? ""
        )
    }
}

// MARK: - CaseIterable for MessageType

extension WebKitMessageReceiver.MessageType: CaseIterable {}
