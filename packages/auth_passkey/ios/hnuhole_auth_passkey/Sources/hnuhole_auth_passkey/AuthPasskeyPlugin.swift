import AuthenticationServices
import Flutter
import Foundation
import UIKit

public class AuthPasskeyPlugin: NSObject, FlutterPlugin {
    private weak var viewController: UIViewController?
    private var active: NSObject?
    private init(viewController: UIViewController?) { self.viewController = viewController; super.init() }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "hnuhole/auth_passkey", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(AuthPasskeyPlugin(viewController: registrar.viewController()), channel: channel)
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if #available(iOS 16.0, *), let operation = active as? PasskeyAuthorization { operation.cancel() }
        active = nil
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handle(call, result: result) }; return
        }
        if call.method == "cancel" {
            if #available(iOS 16.0, *), let operation = active as? PasskeyAuthorization { operation.cancel() }
            result(nil); return
        }
        guard call.method == "create" || call.method == "get" else { result(FlutterMethodNotImplemented); return }
        guard #available(iOS 16.0, *), let window = viewController?.viewIfLoaded?.window,
              window.windowScene?.activationState == .foregroundActive else {
            result(Self.failure("PASSKEY_UNAVAILABLE")); return
        }
        guard active == nil else { result(Self.failure("PASSKEY_BUSY")); return }
        let create = call.method == "create"
        let options: PasskeyCodec.Options
        do {
            guard let arguments = call.arguments as? [String: Any], Set(arguments.keys) == ["publicKey"],
                  let raw = arguments["publicKey"] as? String else { throw PasskeyCodec.Invalid.value }
            options = try PasskeyCodec.options(raw, create: create)
        } catch { result(Self.failure("PASSKEY_INVALID_OPTIONS")); return }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpID)
        let request: ASAuthorizationRequest
        if create {
            guard let userID = options.userID, let name = options.userName else { result(Self.failure("PASSKEY_INVALID_OPTIONS")); return }
            let registration = provider.createCredentialRegistrationRequest(challenge: options.challenge, name: name, userID: userID)
            registration.displayName = "Hnuhole account"
            registration.userVerificationPreference = .required
            registration.attestationPreference = .none
            // Platform passkeys are discoverable and use ES256. Preserve the
            // exclusion list rather than silently replacing a provider's key.
            if #available(iOS 17.4, *) {
                registration.excludedCredentials = options.excludes.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
            } else if !options.excludes.isEmpty {
                result(Self.failure("PASSKEY_UNAVAILABLE")); return
            }
            request = registration
        } else {
            let assertion = provider.createCredentialAssertionRequest(challenge: options.challenge)
            assertion.userVerificationPreference = .required
            assertion.allowedCredentials = [] // Discoverable recovery, no username.
            request = assertion
        }
        let operation = PasskeyAuthorization(request: request, create: create, window: window) { [weak self] operation, value in
            guard self?.active === operation else { return }
            self?.active = nil
            result(value)
        }
        active = operation
        operation.start()
    }
    fileprivate static func failure(_ code: String) -> FlutterError {
        FlutterError(code: code, message: "Passkey operation unavailable or incomplete", details: nil)
    }
}

@available(iOS 16.0, *)
private final class PasskeyAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let controller: ASAuthorizationController
    private let create: Bool
    private let window: UIWindow
    private let complete: (PasskeyAuthorization, Any?) -> Void
    private let pending = PendingOperation<PasskeyAuthorization>()
    private var deadline: DispatchWorkItem?
    private var backgroundObserver: NSObjectProtocol?
    init(request: ASAuthorizationRequest, create: Bool, window: UIWindow,
         complete: @escaping (PasskeyAuthorization, Any?) -> Void) {
        controller = ASAuthorizationController(authorizationRequests: [request])
        self.create = create
        self.window = window
        self.complete = complete
        super.init()
        controller.delegate = self
        controller.presentationContextProvider = self
    }
    func start() {
        guard pending.begin(self) else { return }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel() }
        let timer = DispatchWorkItem { [weak self] in self?.cancel() }
        deadline = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timer)
        controller.performRequests()
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }
    func cancel() {
        guard pending.cancel() != nil else { return }
        release()
        controller.cancel()
        complete(self, AuthPasskeyPlugin.failure("PASSKEY_CANCELLED"))
    }
    private func release() {
        deadline?.cancel()
        deadline = nil
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
        backgroundObserver = nil
    }
    private func finish(_ value: Any?) {
        guard pending.take(self) != nil else { return }
        release()
        complete(self, value)
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        do {
            let value: String
            if create, let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
               let attestation = registration.rawAttestationObject {
                value = try PasskeyCodec.registration(id: registration.credentialID,
                    clientData: registration.rawClientDataJSON, attestation: attestation)
            } else if !create, let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                value = try PasskeyCodec.assertion(id: assertion.credentialID, clientData: assertion.rawClientDataJSON,
                    authenticatorData: assertion.rawAuthenticatorData, signature: assertion.signature, userID: assertion.userID)
            } else { throw PasskeyCodec.Invalid.value }
            finish(value)
        } catch { finish(AuthPasskeyPlugin.failure("PASSKEY_INVALID_RESPONSE")) }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard controller === self.controller else { return }
        let native = error as NSError
        let cancelled = native.domain == ASAuthorizationError.errorDomain && native.code == ASAuthorizationError.Code.canceled.rawValue
        finish(AuthPasskeyPlugin.failure(cancelled ? "PASSKEY_CANCELLED" : "PASSKEY_FAILED"))
    }
    deinit { release() }
}
