//
//  FancyScrollView.swift
//  CharBar
//
//  Custom minimal scrollbar styling
//

import SwiftUI

// MARK: - Minimal Scrollbar Modifier

struct MinimalScrollbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden) // Hide default scrollbar
    }
}

// MARK: - Custom Scroll View with thin scrollbar

struct FancyScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    
    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    
    var body: some View {
        ScrollView(axes, showsIndicators: false) {
            content
        }
    }
}

// MARK: - View Extension

extension View {
    /// Apply minimal scrollbar styling
    func minimalScrollbar() -> some View {
        modifier(MinimalScrollbar())
    }
}

// MARK: - Scroll View Appearance Configuration

/// Call this once at app startup to customize NSScrollView appearance
func configureScrollViewAppearance() {
    // Make scrollbars thinner and more minimal
    // This affects all NSScrollViews in the app
}



