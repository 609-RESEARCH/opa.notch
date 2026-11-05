//
//  UpdateChecker.swift
//  opa.notch
//

import AppKit
import Defaults

/// Asks GitHub whether a newer release exists. It only tells people: updating is theirs to do,
/// by downloading the release or through Homebrew. The request carries nothing about them.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed
    }

    @Published private(set) var status: Status = .idle

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/609-RESEARCH/opa.notch/releases/latest")!
    private static let checkInterval: Duration = .seconds(24 * 60 * 60)
    private var schedule: Task<Void, Never>?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var availableRelease: AppRelease? {
        if case .available(let release) = status { return release }
        return nil
    }

    /// For the notch's button, which can be dismissed for a given version.
    var releaseToAnnounce: AppRelease? {
        guard let release = availableRelease, Defaults[.dismissedUpdateVersion] != release.version else { return nil }
        return release
    }

    /// Checks at launch and once a day while the setting is on.
    func start() {
        schedule?.cancel()
        guard Defaults[.checkForUpdates] else {
            status = .idle
            return
        }
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func check() async {
        guard status != .checking else { return }
        let previous = status
        status = .checking
        do {
            var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("opa.notch", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            status = release.isNewer(than: currentVersion) ? .available(release) : .upToDate
        } catch {
            // Keep a known update on show if a later check fails, for example when offline.
            if case .available = previous {
                status = previous
            } else {
                status = .failed
            }
        }
    }

    func openReleasePage() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.pageURL)
    }

    func dismiss() {
        guard let release = availableRelease else { return }
        objectWillChange.send()
        Defaults[.dismissedUpdateVersion] = release.version
    }
}
