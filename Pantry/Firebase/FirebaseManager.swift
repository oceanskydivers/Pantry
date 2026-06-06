import Foundation
import FirebaseCore
import FirebaseAuth
import AuthenticationServices
import GoogleSignIn
import CryptoKit
import SwiftUI

@Observable
@MainActor
final class FirebaseManager {
    static let shared = FirebaseManager()

    private(set) var currentUser: User?
    private(set) var isLoading = false

    var isSignedIn: Bool { currentUser != nil }
    var isAnonymous: Bool { currentUser?.isAnonymous ?? true }
    var userId: String? { currentUser?.uid }
    var displayEmail: String { currentUser?.email ?? "Guest" }
    var displayName: String {
        if let name = currentUser?.displayName, !name.isEmpty { return name }
        if let email = currentUser?.email { return email }
        return "Guest"
    }

    private var nonce: String?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.currentUser = user
            }
        }
    }

    nonisolated func cleanup() {
        // Call on app teardown if needed; deinit on @MainActor class is nonisolated by default
    }

    // MARK: - Anonymous

    func ensureSignedIn() async {
        guard Auth.auth().currentUser == nil else { return }
        _ = try? await Auth.auth().signInAnonymously()
    }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let prevUID = currentUser?.isAnonymous == true ? currentUser?.uid : nil
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        if let anon = prevUID, anon != result.user.uid {
            await SyncService.shared.migrateData(from: anon, to: result.user.uid)
        }
        currentUser = Auth.auth().currentUser
    }

    func createAccount(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await linkOrSignIn(with: credential, displayName: displayName)
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let n = randomNonceString()
        nonce = n
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(n)
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async throws {
        isLoading = true
        defer { isLoading = false }
        switch result {
        case .failure(let e): throw e
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let raw = nonce,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else { throw AuthError.invalidCredential }

            let firebaseCred = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: raw,
                fullName: cred.fullName
            )
            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            try await linkOrSignIn(with: firebaseCred, displayName: name)
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        isLoading = true
        defer { isLoading = false }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingConfig
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController
        else { throw AuthError.missingConfig }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.invalidCredential
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let name = result.user.profile?.name ?? ""
        try await linkOrSignIn(with: credential, displayName: name)
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Account Linking (anonymous → real)

    private func linkOrSignIn(with credential: AuthCredential, displayName: String) async throws {
        if let user = Auth.auth().currentUser, user.isAnonymous {
            do {
                let result = try await user.link(with: credential)
                await updateDisplayName(displayName, for: result.user)
                currentUser = Auth.auth().currentUser
            } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                // Credential belongs to a different account — migrate local data then sign in
                let anonUID = user.uid
                let newResult = try await Auth.auth().signIn(with: credential)
                await SyncService.shared.migrateData(from: anonUID, to: newResult.user.uid)
                await updateDisplayName(displayName, for: newResult.user)
                currentUser = Auth.auth().currentUser
            }
        } else {
            let result = try await Auth.auth().signIn(with: credential)
            await updateDisplayName(displayName, for: result.user)
            currentUser = Auth.auth().currentUser
        }
    }

    private func updateDisplayName(_ name: String, for user: User) async {
        guard !name.isEmpty, user.displayName != name else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum AuthError: LocalizedError {
    case invalidCredential
    case missingConfig

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Invalid sign-in credential."
        case .missingConfig: return "Firebase not configured. Add GoogleService-Info.plist."
        }
    }
}
