import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct AuthView: View {
    @Environment(FirebaseManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showEmailAuth = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAnonymous {
                    signInContent
                } else {
                    accountContent
                }
            }
            .navigationTitle(auth.isAnonymous ? "Sign In" : "Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sign-in screen

    private var signInContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.appAccent)
                Text("Sync Your Pantry")
                    .font(.title2).fontWeight(.bold)
                Text("Sign in to share recipes, inventory, and\nshopping lists across your household.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            VStack(spacing: 12) {
                // Sign in with Apple
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

                // Sign in with Google
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }

                // Email
                Button {
                    showEmailAuth = true
                } label: {
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

            Text("Your data stays on this device if you skip sign-in.\nSign in to share with your household.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
                .environment(auth)
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

    // MARK: - Account screen

    private var accountContent: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.appAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.displayName)
                            .font(.headline)
                        if !auth.isAnonymous {
                            Text(auth.displayEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Sharing") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share Access")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Share your sign-in credentials with your household members so everyone sees the same data in real time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(role: .destructive) {
                    try? auth.signOut()
                    dismiss()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
}

// MARK: - Email Auth View

struct EmailAuthView: View {
    @Environment(FirebaseManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field { case email, password, name }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)

                    SecureField("Password", text: $password)
                        .focused($focusedField, equals: .password)

                    if isCreating {
                        TextField("Display Name (optional)", text: $displayName)
                            .focused($focusedField, equals: .name)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isCreating ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Button(isCreating ? "Create" : "Sign In") {
                            Task { await submit() }
                        }
                        .disabled(email.isEmpty || password.count < 6)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(isCreating ? "Already have an account? Sign in" : "Don't have an account? Create one") {
                        withAnimation { isCreating.toggle() }
                        errorMessage = nil
                    }
                    .font(.footnote)
                }
            }
            .onAppear { focusedField = .email }
        }
    }

    private func submit() async {
        errorMessage = nil
        do {
            if isCreating {
                try await auth.createAccount(email: email, password: password, displayName: displayName)
            } else {
                try await auth.signIn(email: email, password: password)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
