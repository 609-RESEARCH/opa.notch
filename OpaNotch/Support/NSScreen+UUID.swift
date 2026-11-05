//
//  NSScreen+UUID.swift
//  opa.notch (ported from boring.notch, GPL-3.0)
//
//  Created by Alexander on 2025-11-21.
//

import AppKit
import CoreGraphics

extension NSScreen {
    /// Identifies this display while it's connected. Unlike the UUID, every connected display
    /// is guaranteed its own: two identical monitors can report the same UUID, or none.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Returns a persistent UUID for this display
    var displayUUID: String? {
        guard let displayID else {
            return nil
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        return uuidString
    }
}
