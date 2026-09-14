import Foundation
import Observation

@MainActor
@Observable
final class AddonRegistry {
    enum MoveDirection {
        case up
        case down
    }

    private let persistence: any AddonPersistence

    private(set) var installed: [InstalledAddon] = []
    private(set) var lastError: String?

    private(set) var revision = 0

    var onConfigurationChange: (() -> Void)?

    init(persistence: any AddonPersistence) {
        self.persistence = persistence
        if let loaded = try? persistence.load() {
            installed = loaded
        } else {
            AppLogger.persistence.error("Failed to load installed addons")
        }
    }

    var enabledAddons: [InstalledAddon] {
        installed
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }
    }

    func install(_ preview: AddonInstallPreview) throws -> InstalledAddon {
        guard !installed.contains(where: { $0.id == preview.id }) else {
            throw AddonError.alreadyInstalled(preview.name)
        }
        let nextPriority = (installed.map(\.priority).max() ?? -1) + 1
        let addon = preview.makeInstalledAddon(priority: nextPriority)
        installed.append(addon)
        configurationDidChange()
        try persist()
        return addon
    }

    func remove(id: String) throws {
        guard installed.contains(where: { $0.id == id }) else { return }
        installed.removeAll { $0.id == id }
        normalizePriorities()
        configurationDidChange()
        try persist()
    }

    func setEnabled(id: String, isEnabled: Bool) throws {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].isEnabled = isEnabled
        configurationDidChange()
        try persist()
    }

    func updateHealth(id: String, status: AddonHealthStatus) throws {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].lastHealthStatus = status
        installed[index].lastCheckedAt = Date()
        try persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) throws {
        let moving = fromOffsets.compactMap { installed.indices.contains($0) ? installed[$0] : nil }
        let removed = fromOffsets.sorted(by: >)
        for index in removed {
            installed.remove(at: index)
        }
        let shift = removed.filter { $0 < toOffset }.count
        let insertionIndex = min(max(toOffset - shift, 0), installed.count)
        installed.insert(contentsOf: moving, at: insertionIndex)
        normalizePriorities()
        configurationDidChange()
        try persist()
    }

    func move(id: String, direction: MoveDirection) throws {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        let target = direction == .up ? index - 1 : index + 1
        guard installed.indices.contains(target) else { return }
        installed.swapAt(index, target)
        normalizePriorities()
        configurationDidChange()
        try persist()
    }

    func configurationDidChange() {
        revision += 1
        onConfigurationChange?()
    }

    private func normalizePriorities() {
        for index in installed.indices {
            installed[index].priority = index
        }
    }

    private func persist() throws {
        do {
            try persistence.replaceAll(installed)
            lastError = nil
        } catch {
            AppLogger.persistence.error("Failed to persist addons")
            lastError = String(localized: "Addon changes could not be saved.")
            throw error
        }
    }
}
