import Foundation

enum LoadingState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(CatalogError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: CatalogError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}
