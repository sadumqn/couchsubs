// SPDX-License-Identifier: AGPL-3.0-only

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// Firebase Auth ile hesap: Apple ile giriş, Google, e-posta/şifre. Yalnız GoogleService-Info.plist varken kurulur.
@MainActor
final class FirebaseAccounts: AccountService {
    var onChange: ((AccountUser?) -> Void)?
    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.onChange?(user.map(Self.account)) }
        }
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    var isAvailable: Bool { true }
    var canUseGoogle: Bool { GIDSignIn.sharedInstance.configuration != nil }
    var user: AccountUser? { Auth.auth().currentUser.map(Self.account) }

    private static func account(_ user: User) -> AccountUser {
        AccountUser(uid: user.uid, name: user.displayName, email: user.email, providers: user.providerData.map(\.providerID),
                    emailVerified: user.isEmailVerified)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> Bool {
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        return try await signIn(with: credential)
    }

    func signInWithGoogle() async throws -> Bool {
        guard let presenter = Self.topViewController() else { throw AccountError.unavailable }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw AccountError.canceled
        }
        guard let idToken = result.user.idToken?.tokenString else { throw AccountError.other(String(localized: "Sign-in did not complete. Please try again.")) }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        return try await signIn(with: credential)
    }

    private func signIn(with credential: AuthCredential) async throws -> Bool {
        do {
            let result = try await Auth.auth().signIn(with: credential)
            return result.additionalUserInfo?.isNewUser ?? false
        } catch {
            throw Self.map(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        do { _ = try await Auth.auth().signIn(withEmail: email, password: password) } catch { throw Self.map(error) }
    }

    func signUp(name: String, email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try await change.commitChanges()
                onChange?(user)
            }
        } catch {
            throw Self.map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do { try await Auth.auth().sendPasswordReset(withEmail: email) } catch { throw Self.map(error) }
    }

    func updateName(_ name: String) async throws {
        guard let current = Auth.auth().currentUser else { throw AccountError.userNotFound }
        let change = current.createProfileChangeRequest()
        change.displayName = name.trimmingCharacters(in: .whitespaces)
        do { try await change.commitChanges() } catch { throw Self.map(error) }
        onChange?(user)
    }

    func updateEmail(_ email: String) async throws {
        guard let current = Auth.auth().currentUser else { throw AccountError.userNotFound }
        do { try await current.sendEmailVerification(beforeUpdatingEmail: email) } catch { throw Self.map(error) }
    }

    func updatePassword(_ password: String) async throws {
        guard let current = Auth.auth().currentUser else { throw AccountError.userNotFound }
        do { try await current.updatePassword(to: password) } catch { throw Self.map(error) }
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        do { try Auth.auth().signOut() } catch { throw Self.map(error) }
    }

    func deleteAccount() async throws {
        guard let current = Auth.auth().currentUser else { throw AccountError.userNotFound }
        do { try await current.delete() } catch { throw Self.map(error) }
        GIDSignIn.sharedInstance.signOut()
    }

    func idToken() async throws -> String? {
        guard let current = Auth.auth().currentUser else { return nil }
        return try await current.getIDToken()
    }

    static func map(_ error: Error) -> AccountError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return .other(error.localizedDescription) }
        switch AuthErrorCode(rawValue: nsError.code) {
        case .wrongPassword, .invalidCredential: return .wrongPassword
        case .userNotFound: return .userNotFound
        case .emailAlreadyInUse, .credentialAlreadyInUse: return .emailInUse
        case .weakPassword: return .weakPassword
        case .invalidEmail: return .invalidEmail
        case .requiresRecentLogin: return .requiresRecentLogin
        case .networkError: return .network
        default: return .other(error.localizedDescription)
        }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
