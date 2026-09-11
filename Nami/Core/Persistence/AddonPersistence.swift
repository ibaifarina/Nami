import Foundation
import SwiftData

@MainActor
protocol AddonPersistence {
    func load() throws -> [InstalledAddon]
    func replaceAll(_ addons: [InstalledAddon]) throws
}

@MainActor
final class InMemoryAddonPersistence: AddonPersistence {
    private var addons: [InstalledAddon]

    init(addons: [InstalledAddon] = []) {
        self.addons = addons
    }

    func load() throws -> [InstalledAddon] {
        addons
    }

    func replaceAll(_ addons: [InstalledAddon]) throws {
        self.addons = addons
    }
}

@MainActor
final class SwiftDataAddonPersistence: AddonPersistence {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func load() throws -> [InstalledAddon] {
        let descriptor = FetchDescriptor<StoredAddon>(
            sortBy: [SortDescriptor(\StoredAddon.priority)]
        )
        return try context.fetch(descriptor).compactMap { $0.toDomain() }
    }

    func replaceAll(_ addons: [InstalledAddon]) throws {
        let existing = try context.fetch(FetchDescriptor<StoredAddon>())
        var byID = Dictionary(
            existing.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for addon in addons {
            if let stored = byID.removeValue(forKey: addon.id) {
                stored.update(from: addon)
            } else {
                context.insert(StoredAddon(addon))
            }
        }
        for stored in byID.values {
            context.delete(stored)
        }
        try context.save()
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer? {
        SwiftDataStack.makeContainer(inMemory: inMemory)
    }
}
