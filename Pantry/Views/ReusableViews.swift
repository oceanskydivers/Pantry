//
//  ReusableViews.swift
//  Pantry
//
//  Created by Kylee Davis on 6/6/26.
//

import SwiftUI
import UIKit

struct GlassBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 32))
        } else {
            content // No modifier for older iOS versions
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension View {
    func glassBackground() -> some View {
        modifier(GlassBackground())
    }
}

// MARK: - FloatingSearchBar

struct FloatingSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 32))
            .shadow(color: .secondary, radius: 5)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassBackground()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { isFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if text.isEmpty { onDismiss() }
        }
    }
}

// MARK: - PantryItemTextField
// Shared UITextView wrapper used by ShoppingListView and ManageCategoriesView.
// Supports single-line entry with Return-key submission and focus management.

struct PantryItemTextField: UIViewRepresentable {
    @Binding var text: String
    let shouldBeFocused: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.returnKeyType = .next
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        if shouldBeFocused && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, 22))
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PantryItemTextField
        var submitHandled = false

        init(_ parent: PantryItemTextField) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                submitHandled = true
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if submitHandled {
                submitHandled = false
                return
            }
            parent.onEndEditing()
        }
    }
}
