//
//  ReusableViews.swift
//  Pantry
//
//  Created by Kylee Davis on 6/6/26.
//

import SwiftUI

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
