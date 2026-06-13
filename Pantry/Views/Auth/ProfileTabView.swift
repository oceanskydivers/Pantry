import SwiftUI

struct ProfileTabView: View {
    @Environment(FirebaseManager.self) private var auth

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAnonymous {
                    SignInPromptView()
                        .environment(auth)
                } else {
                    AccountView()
                }
            }
            .navigationTitle(auth.isAnonymous ? "Sign In" : "Account")
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
