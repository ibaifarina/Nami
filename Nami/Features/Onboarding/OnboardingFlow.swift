import Foundation

struct OnboardingFlow: Equatable {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case realDebrid
        case addons
        case preferences

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .realDebrid: "Connect Real-Debrid"
            case .addons: "Add Streaming Addons"
            case .preferences: "Choose Preferences"
            }
        }
    }

    private(set) var step: Step = .welcome

    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == .preferences }
    var stepNumber: Int { step.rawValue + 1 }
    var stepCount: Int { Step.allCases.count }

    mutating func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    mutating func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
