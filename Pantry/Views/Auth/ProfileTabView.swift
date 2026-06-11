import SwiftUI
import AuthenticationServices

struct ProfileTabView: View {
    @Environment(FirebaseManager.self) private var auth

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAnonymous {
                    SignInPromptView()
                } else {
                    AccountView()
                }
            }
            .navigationTitle(auth.isAnonymous ? "Sign In" : "Account")
        }
    }
}

// MARK: - Sign-in prompt (anonymous users)

private struct SignInPromptView: View {
    @Environment(FirebaseManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    @State private var showEmailAuth = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.appAccent)
                    .padding(.bottom, 8)
                Text("Sync Your Pantry")
                    .font(.title2).fontWeight(.bold)
                Text("Sign in to share recipes, inventory, and\nshopping lists across your household.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task {
                        do { try await auth.handleAppleResult(result) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    Task {
                        do { try await auth.signInWithGoogle() }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Image("google-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Sign in with Google")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
                }

                Button { showEmailAuth = true } label: {
                    Text("Continue with Email")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 24)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("Your data stays on this device without an account.\nSign in to share with your household.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView().environment(auth)
        }
        .overlay {
            if auth.isLoading {
                ZStack {
                    Color(.systemBackground).opacity(0.6)
                    ProgressView("Signing in…")
                        .padding(24)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Account info (signed-in users)

private struct AccountView: View {
    @Environment(FirebaseManager.self) private var auth
    @State private var showSignOutConfirmation = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.appAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.displayName)
                            .font(.headline)
                        Text(auth.displayEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Household Sharing") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How to share with your household")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Anyone who signs in with the same account (Apple ID, Google account, or email + password) will see and edit the same recipes, inventory, and shopping list in real time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Preferences") {
                Toggle(isOn: Binding(
                    get: { SyncService.shared.autoAddToInventory },
                    set: { SyncService.shared.autoAddToInventory = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-Add to Inventory")
                        Text("Automatically update your inventory when you check off shopping list items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                try? auth.signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Any recipes or changes you make while signed out won't be saved to your account.\n\nIf you get a new phone or device, you'll only be able to access the recipes that were synced to your account before signing out. Sign back in at any time to resume syncing.")
        }
    }
}
