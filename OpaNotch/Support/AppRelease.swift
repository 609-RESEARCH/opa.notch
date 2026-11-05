//
//  AppRelease.swift
//  opa.notch
//

import Foundation

/// The parts of GitHub's "latest release" response the update check needs.
struct AppRelease: Decodable, Equatable {
    let tag: String
    let pageURL: URL

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case pageURL = "html_url"
    }

    /// "v0.3.0" as shown to people: "0.3.0".
    var version: String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compares numbers rather than text, so 0.10.0 is newer than 0.9.0 and 0.2 equals 0.2.0.
    /// A version that isn't plain numbers is never treated as newer.
    func isNewer(than current: String) -> Bool {
        guard let new = Self.numbers(in: version), let old = Self.numbers(in: current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(in version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
