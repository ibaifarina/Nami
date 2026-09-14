import Foundation

struct OnboardingFlow: Equatable {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case realDebrid
        case addons
        case preferences
        case ready

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: String(localized: "Welcome to Nami")
            case .realDebrid: String(localized: "Connect Real-Debrid")
            case .addons: String(localized: "Add Your Addons")
            case .preferences: String(localized: "Set Your Preferences")
            case .ready: String(localized: "You're All Set")
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: String(localized: "Your anime, one clean Play button.")
            case .realDebrid: String(localized: "Unlock instant, cached, high-quality streams.")
            case .addons: String(localized: "Addons are where your sources come from.")
            case .preferences: String(localized: "Tell Nami how you like to watch. Change it anytime.")
            case .ready: String(localized: "Review your setup and start watching.")
            }
        }

        var systemImage: String {
            switch self {
            case .welcome: "sparkles"
            case .realDebrid: "bolt.fill"
            case .addons: "puzzlepiece.extension.fill"
            case .preferences: "slider.horizontal.3"
            case .ready: "checkmark.seal.fill"
            }
        }

        /// Short label used in the setup progress rail.
        var shortTitle: String {
            switch self {
            case .welcome: String(localized: "Welcome")
            case .realDebrid: String(localized: "Real-Debrid")
            case .addons: String(localized: "Addons")
            case .preferences: String(localized: "Preferences")
            case .ready: String(localized: "Ready")
            }
        }

        /// Steps that collect setup. Welcome and Ready frame the flow.
        var isSetup: Bool {
            switch self {
            case .realDebrid, .addons, .preferences: true
            case .welcome, .ready: false
            }
        }
    }

    private(set) var step: Step = .welcome
    private(set) var visited: Set<Step> = [.welcome]

    static let setupSteps: [Step] = Step.allCases.filter(\.isSetup)

    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == .ready }
    var stepNumber: Int { step.rawValue + 1 }
    var stepCount: Int { Step.allCases.count }

    /// Index of the current step within the setup steps, when it is one.
    var setupIndex: Int? {
        Self.setupSteps.firstIndex(of: step)
    }

    /// Overall completion from 0 (welcome) to 1 (ready).
    var progress: Double {
        guard Step.allCases.count > 1 else { return 1 }
        return Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    func canJump(to target: Step) -> Bool {
        target == step || visited.contains(target)
    }

    mutating func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        go(to: next)
    }

    mutating func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    mutating func go(to target: Step) {
        step = target
        visited.insert(target)
    }
}
