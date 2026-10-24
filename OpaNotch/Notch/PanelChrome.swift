//
//  PanelChrome.swift
//  opa.notch
//
//  Shared pieces for the two panels in the open notch.
//

import SwiftUI

/// An opaque inset container: one solid step up from the notch's black, so blocks read
/// as separate without anything showing through. Its radius is concentric with the notch's
/// bottom corners.
struct PanelSurface<Content: View>: View {
    @ViewBuilder let content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.panelSpacing) {
            content
        }
        .padding(.top, Metrics.panelTopInset)
        .padding(.bottom, Metrics.panelBottomInset)
        .padding(.horizontal, Metrics.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(Palette.panel))
    }
}

/// Asks for access at the moment it's needed, says exactly why, and offers a way out when denied.
struct AccessPrompt: View {
    let symbol: String
    let title: String
    let message: String
    let status: EventKitAccess.Status
    let request: () async -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.secondary)
            VStack(spacing: 3) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.primary)
                Text(status == .denied ? "Access is off. Turn it on in System Settings → Privacy." : message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if status == .denied {
                    openSettings()
                } else {
                    Task { await request() }
                }
            } label: {
                Text(status == .denied ? "Open Settings" : "Allow Access")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(Capsule().fill(Palette.accent))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyPanelState: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.tertiary)
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Palette.secondary)
            if let detail {
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 10)
    }
}
