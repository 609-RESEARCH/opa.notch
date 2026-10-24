//
//  DebugCapture.swift
//  opa.notch
//

#if DEBUG
import AppKit

/// Captures one of the app's own windows exactly as the window server draws it
/// (glass, scroll views, text fields included), for layout review without
/// Screen Recording permission.
enum DebugCapture {
    static func write(_ window: NSWindow, name: String) {
        // CGWindowListCreateImage is unavailable to Swift on macOS 15+ SDKs but still works
        // for an app's own windows; look it up dynamically for this debug-only capture.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // .optionIncludingWindow = 8, .boundsIgnoreFraming = 1
        guard let image = create(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        NSLog("opa.notch capture: \(url.path)")

        // Glass is composited by the window server and may be missing from a capture,
        // so also report which material views are actually installed.
        func materials(in view: NSView) -> [String] {
            let type = String(describing: Swift.type(of: view))
            let own = (type.contains("Glass") || type.contains("VisualEffect")) ? ["\(type) \(Int(view.frame.width))x\(Int(view.frame.height))"] : []
            return own + view.subviews.flatMap(materials)
        }
        // SwiftUI's glassEffect draws with layers rather than views.
        func glassLayers(in layer: CALayer) -> [String] {
            let type = String(describing: Swift.type(of: layer))
            let isGlass = ["Glass", "Backdrop", "Portal", "SDF"].contains { type.contains($0) }
            let own = isGlass ? ["\(type) \(Int(layer.bounds.width))x\(Int(layer.bounds.height))"] : []
            return own + (layer.sublayers ?? []).flatMap(glassLayers)
        }
        if let root = window.contentView?.superview {
            NSLog("opa.notch \(name) materials: \(materials(in: root)) layers: \(root.layer.map(glassLayers) ?? [])")
        }
    }
}
#endif
