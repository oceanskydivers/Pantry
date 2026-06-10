import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let supportedDomains = [
        "tiktok.com", "instagram.com", "youtube.com", "youtu.be",
        "facebook.com", "fb.watch"
    ]

    private var extractedURL: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.01)

        Task {
            let urlString = await extractURL()
            await MainActor.run {
                if let urlString, isSupportedURL(urlString) {
                    extractedURL = urlString
                    showConfirmation()
                } else {
                    showError()
                }
            }
        }
    }

    // MARK: - URL Extraction

    private func extractURL() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Try public.url first
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let result = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let url = result as? URL {
                        return url.absoluteString
                    }
                }

                // Fall back to plain text — Instagram often shares URLs this way
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let result = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let text = result as? String {
                        return extractURLFromText(text)
                    }
                }
            }
        }

        return nil
    }

    /// Extracts the first HTTP/HTTPS URL from a block of text using NSDataDetector.
    private func extractURLFromText(_ text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)
        for match in matches {
            if let url = match.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return url.absoluteString
            }
        }
        return nil
    }

    private func isSupportedURL(_ urlString: String) -> Bool {
        let lowered = urlString.lowercased()
        return supportedDomains.contains { lowered.contains($0) }
    }

    // MARK: - Deep link URL

    private func buildDeepLink() -> URL? {
        guard let socialURL = extractedURL,
              let encoded = socialURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "pantry://import?url=\(encoded)")
    }

    // MARK: - UI

    private func showConfirmation() {
        let view = ShareConfirmationView(
            onOpenPantry: {
                self.extensionContext?.completeRequest(returningItems: nil)
            },
            onDismiss: {
                self.extensionContext?.completeRequest(returningItems: nil)
            },
            deepLinkURL: buildDeepLink()
        )
        embed(view)
    }

    private func showError() {
        let view = ShareErrorView {
            self.extensionContext?.cancelRequest(withError: NSError(
                domain: "com.spisea.pantry.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported URL"]
            ))
        }
        embed(view)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "com.spisea.pantry.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported URL"]
            ))
        }
    }

    private func embed<Content: View>(_ swiftUIView: Content) {
        let hosting = UIHostingController(rootView: swiftUIView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
