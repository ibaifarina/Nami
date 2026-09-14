import Foundation

struct TorrentFileSelection: Hashable, Sendable {
    let file: DebridFileInfo
    let reason: String
}

enum TorrentFileSelector {
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "mov", "webm", "m4v", "ts", "m2ts", "mpg", "mpeg", "wmv", "flv",
    ]

    static func selectFile(
        from files: [DebridFileInfo],
        targetEpisode: Int?
    ) throws -> TorrentFileSelection {
        let videoFiles = files.filter { isVideo($0.filename) }
        guard !videoFiles.isEmpty else {
            throw DebridError.fileSelectionFailed(String(localized: "No video files were found in this torrent."))
        }

        let candidates = playableFiles(from: files)

        if let targetEpisode {
            let matches = candidates.compactMap { file -> (file: DebridFileInfo, episode: Int)? in
                guard let episode = ReleaseParser.episode(from: file.filename).episode else { return nil }
                return episode == targetEpisode ? (file, episode) : nil
            }
            if let best = matches.max(by: { $0.file.bytes < $1.file.bytes }) {
                return TorrentFileSelection(
                    file: best.file,
                    reason: String(localized: "Matched episode \(targetEpisode)")
                )
            }
            if videoFiles.count == 1, !isExtra(videoFiles[0].filename) {
                return TorrentFileSelection(
                    file: videoFiles[0],
                    reason: String(localized: "Only one video file in this torrent")
                )
            }
            throw DebridError.fileSelectionFailed(
                String(localized: "Episode \(targetEpisode) was not found inside this torrent.")
            )
        }

        guard let largest = candidates.max(by: { $0.bytes < $1.bytes }) else {
            throw DebridError.fileSelectionFailed(String(localized: "No playable files were found in this torrent."))
        }
        return TorrentFileSelection(file: largest, reason: String(localized: "Largest playable file"))
    }

    /// The video files a user can meaningfully pick between: extras such as
    /// samples and creditless openings are hidden when normal files exist.
    static func playableFiles(from files: [DebridFileInfo]) -> [DebridFileInfo] {
        let videoFiles = files.filter { isVideo($0.filename) }
        let mainFiles = videoFiles.filter { !isExtra($0.filename) }
        return mainFiles.isEmpty ? videoFiles : mainFiles
    }

    static func isVideo(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    static func isExtra(_ filename: String) -> Bool {
        let lowered = filename.lowercased()
        let markers = [
            "sample", "ncop", "nced", "trailer", "preview", "creditless",
            "menu", "op1", "ed1", "pv1", "pv2",
        ]
        return markers.contains { lowered.contains($0) }
    }
}
