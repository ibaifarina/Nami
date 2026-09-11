import Foundation
import Observation

@MainActor
@Observable
final class RealDebridAuthService {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(DebridAccount)
        case failed(String)
    }

    private let service: any DebridService
    private let tokenStore: SecureTokenStore

    private(set) var state: State = .disconnected

    init(service: any DebridService, tokenStore: SecureTokenStore) {
        self.service = service
        self.tokenStore = tokenStore
    }

    var account: DebridAccount? {
        if case .connected(let account) = state { return account }
        return nil
    }

    var isConnected: Bool { account != nil }

    var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func restore() async {
        guard await tokenStore.token() != nil else {
            state = .disconnected
            return
        }
        await verify()
    }

    func connect(token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Enter your Real-Debrid API token.")
            return
        }
        state = .connecting
        do {
            let account = try await service.validateAccount(token: trimmed)
            guard account.isPremium else {
                state = .failed("This Real-Debrid account has no active premium time.")
                return
            }
            try await tokenStore.save(trimmed)
            state = .connected(account)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func verify() async {
        state = .connecting
        do {
            let account = try await service.validateAccount()
            state = .connected(account)
        } catch let error as DebridError where error == .unauthorized {
            await tokenStore.clear()
            state = .disconnected
        } catch let error as DebridError where error == .notConfigured {
            state = .disconnected
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func disconnect() async {
        await tokenStore.clear()
        state = .disconnected
    }

    private static func message(for error: Error) -> String {
        if let debridError = error as? DebridError {
            return debridError.errorDescription ?? "The Real-Debrid request failed."
        }
        return error.localizedDescription
    }
}
