//
//  SlidingText.swift
//  opa.notch
//

import SwiftUI

/// One line of text that truncates at rest and, while `isActive`, slides sideways so all of it
/// can be read. Text that fits never moves. Font, colour and strikethrough come from outside,
/// as they would for a `Text`.
struct SlidingText: View {
    private let string: String
    private let isActive: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0
    /// How far along the text has moved.
    @State private var position: CGFloat = 0
    @State private var isSliding = false

    /// Long enough that a pointer just passing over the list sets nothing in motion.
    private static let startDelay: Duration = .milliseconds(450)
    /// A comfortable reading pace, in points per second.
    private static let speed: CGFloat = 45
    /// Time to take in the text at each end before it moves again.
    private static let hold: Duration = .milliseconds(1400)
    /// Long enough for the spring back to the start to finish.
    private static let returnTime: Duration = .milliseconds(450)
    private static let edgeFade: CGFloat = 14

    init(_ string: String, isActive: Bool) {
        self.string = string
        self.isActive = isActive
    }

    var body: some View {
        Text(string)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isSliding ? 0 : 1)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { visibleWidth = $0 })
            .background(alignment: .leading) {
                line
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { fullWidth = $0 })
            }
            .overlay(alignment: .leading) {
                if isSliding {
                    slidingLine
                }
            }
            .task(id: shouldSlide) {
                try? await (shouldSlide ? slide() : settle())
            }
    }

    private var line: some View {
        Text(string)
            .lineLimit(1)
            .fixedSize()
    }

    private var slidingLine: some View {
        ZStack(alignment: .leading) {
            line
                .offset(x: -position)
                // With Reduce Motion each stop is a new view, so the text cross-fades instead of travelling.
                .id(Motion.reduceMotion ? position : 0)
                .transition(.opacity)
        }
        .frame(width: visibleWidth, alignment: .leading)
        .mask(edgeMask)
        .accessibilityHidden(true)
    }

    /// Text fades out wherever more of it lies beyond the edge, like a scroll edge.
    private var edgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: position > 0 ? Self.edgeFade : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: position < overflow ? Self.edgeFade : 0)
        }
    }

    // MARK: - Motion

    private var overflow: CGFloat {
        max(0, fullWidth - visibleWidth)
    }

    private var shouldSlide: Bool {
        isActive && overflow >= 1
    }

    /// Where the text pauses on its way to the end. Reduce Motion replaces the travel with
    /// a cross-fade, so it steps a screenful at a time to keep every word on screen once.
    private var stops: [CGFloat] {
        guard Motion.reduceMotion else { return [overflow] }
        let page = max(visibleWidth - Self.edgeFade * 2, 40)
        return Array(stride(from: page, to: overflow, by: page)) + [overflow]
    }

    /// Runs until cancelled, which the sleeps surface by throwing.
    private func slide() async throws {
        try await Task.sleep(for: Self.startDelay)
        isSliding = true
        while true {
            var from: CGFloat = 0
            for stop in stops {
                let seconds = max(Double((stop - from) / Self.speed), 0.3)
                // Close to linear so the pace stays readable, with soft ends so it doesn't jolt.
                withAnimation(Motion.adaptive(.timingCurve(0.15, 0, 0.85, 1, duration: seconds))) {
                    position = stop
                }
                try await Task.sleep(for: .seconds(seconds) + Self.hold)
                from = stop
            }
            withAnimation(Motion.adaptive(Motion.standard)) { position = 0 }
            try await Task.sleep(for: Self.returnTime + Self.hold)
        }
    }

    /// Springs back from wherever the text is, then the ellipsis returns.
    private func settle() async throws {
        guard isSliding else { return }
        withAnimation(Motion.adaptive(Motion.standard)) { position = 0 }
        try await Task.sleep(for: Self.returnTime)
        isSliding = false
    }
}
