import SwiftUI

struct ShareErrorView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("Unsupported Link")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Pantry can import recipes from Instagram, TikTok, Facebook, and YouTube links.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("OK") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .padding(.top, 4)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
        }
    }
}
