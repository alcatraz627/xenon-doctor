import Foundation
import AppKit

/// Keeps the app current from the GitHub releases of alcatraz627/xenon-doctor. Checks at
/// launch and every six hours; when a newer tag exists the menu grows one row, and that
/// row downloads the zip, swaps the app bundle in place, and relaunches. A file the app
/// downloads itself carries no quarantine flag, so the new copy opens without the
/// right-click dance the first install needed.
final class Updater {
    struct Release: Equatable {
        let tag: String
        let version: String
        let zipURL: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, downloading
        case available(Release)
        case failed(String)
    }

    static let repo = "alcatraz627/xenon-doctor"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private(set) var state: State = .idle {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var lastCheck: Date?

    func startPolling() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    /// Asks GitHub for the latest release. `force` ignores the ten-minute cool-down.
    func check(force: Bool = false, completion: ((State) -> Void)? = nil) {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 600 { completion?(state); return }
        if case .downloading = state { completion?(state); return }
        state = .checking
        lastCheck = Date()
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("XenonDoctor/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let next: State
            if let error = error {
                next = .failed(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                next = .failed("GitHub answered \(http.statusCode)")
            } else if let data = data, let rel = Updater.parse(data) {
                next = Updater.isNewer(rel.version, than: Updater.currentVersion) ? .available(rel) : .upToDate
            } else {
                next = .failed("could not read the release list")
            }
            DispatchQueue.main.async {
                self?.state = next
                completion?(next)
            }
        }.resume()
    }

    static func parse(_ data: Data) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        guard let urlString = zip?["browser_download_url"] as? String, let url = URL(string: urlString) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(tag: tag, version: version, zipURL: url)
    }

    /// Dotted numeric compare: 0.10.0 is newer than 0.9.1; a missing part counts as zero.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The bundle to replace: the running app when it is a real .app, else Applications.
    static func installTarget() -> URL {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" { return bundle }
        return URL(fileURLWithPath: "/Applications/XenonDoctor.app")
    }

    func installAvailable() {
        guard case .available(let rel) = state else { return }
        install(rel) { result in
            if case .success(let target) = result { Updater.relaunch(target) }
        }
    }

    /// Downloads the zip, unpacks it beside the target, swaps the bundles, and reports the
    /// new bundle's path. The old bundle is kept in the temp folder until the next reboot.
    func install(_ rel: Release, completion: @escaping (Result<URL, Error>) -> Void) {
        state = .downloading
        let task = URLSession.shared.downloadTask(with: rel.zipURL) { [weak self] tmp, response, error in
            let result: Result<URL, Error>
            do {
                if let error = error { throw error }
                guard let tmp = tmp else { throw UpdateError.message("no file arrived") }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw UpdateError.message("download answered \(http.statusCode)")
                }
                result = .success(try Updater.swapIn(zipAt: tmp, version: rel.version))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                switch result {
                case .success: self?.state = .upToDate
                case .failure(let e): self?.state = .failed(String(describing: e))
                }
                completion(result)
            }
        }
        task.resume()
    }

    enum UpdateError: Error, CustomStringConvertible {
        case message(String)
        var description: String {
            switch self { case .message(let m): return m }
        }
    }

    private static func swapIn(zipAt tmp: URL, version: String) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("xenondoctor-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("XenonDoctor-\(version).zip")
        try fm.moveItem(at: tmp, to: zip)
        let (status, out) = Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard status == 0 else { throw UpdateError.message("could not unpack: \(out)") }
        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.message("the zip held no app")
        }
        _ = Shell.run("/usr/bin/xattr", ["-cr", newApp.path])
        let target = installTarget()
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.message("cannot write to \(parent.path)")
        }
        if fm.fileExists(atPath: target.path) {
            let old = work.appendingPathComponent("XenonDoctor-old.app")
            try fm.moveItem(at: target, to: old)
        }
        try fm.moveItem(at: newApp, to: target)
        return target
    }

    /// Starts the new copy, then quits this one. `open -n` forces a fresh instance even
    /// though the bundle id matches the process that is still running.
    static func relaunch(_ target: URL) {
        Shell.run("/usr/bin/open", ["-n", target.path])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp?.terminate(nil)
            exit(0)
        }
    }
}
