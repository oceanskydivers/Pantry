import SwiftUI

struct ShareConfirmationView: View {
    let onOpenPantry: () -> Void
    let onDismiss: () -> Void
    let deepLinkURL: URL?

    private let accentColor = Color(red: 133.5 / 255, green: 171.5 / 255, blue: 120 / 255)

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(accentColor)

                Text("Recipe Link Saved!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Open Pantry now to import this recipe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let deepLinkURL {
                    Button("Open Pantry") {
                        openURL(deepLinkURL)
                        onOpenPantry()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .padding(.top, 4)
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
        }
    }
}
