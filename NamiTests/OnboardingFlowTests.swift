import Foundation
import Testing
@testable import Nami

struct OnboardingFlowTests {
    @Test func startsAtWelcome() {
        let flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        #expect(flow.isFirst)
        #expect(!flow.isLast)
        #expect(flow.stepNumber == 1)
        #expect(flow.stepCount == 5)
        #expect(flow.progress == 0)
    }

    @Test func advancesThroughEveryStep() {
        var flow = OnboardingFlow()
        let expected: [OnboardingFlow.Step] = [.realDebrid, .addons, .preferences, .ready]
        for step in expected {
            flow.advance()
            #expect(flow.step == step)
        }
        #expect(flow.isLast)
        #expect(flow.stepNumber == 5)
        #expect(flow.progress == 1)

        flow.advance()
        #expect(flow.step == .ready)
    }

    @Test func backStopsAtWelcome() {
        var flow = OnboardingFlow()
        flow.back()
        #expect(flow.step == .welcome)

        flow.advance()
        flow.advance()
        #expect(flow.step == .addons)
        flow.back()
        #expect(flow.step == .realDebrid)
        flow.back()
        #expect(flow.step == .welcome)
    }

    @Test func setupStepsCoverConfigurationOnly() {
        #expect(OnboardingFlow.setupSteps == [.realDebrid, .addons, .preferences])

        var flow = OnboardingFlow()
        #expect(flow.setupIndex == nil)
        flow.advance()
        #expect(flow.setupIndex == 0)
        flow.go(to: .preferences)
        #expect(flow.setupIndex == 2)
        flow.go(to: .ready)
        #expect(flow.setupIndex == nil)
    }

    @Test func tracksVisitedStepsForBackwardNavigation() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.advance()
        #expect(flow.visited == [.welcome, .realDebrid, .addons])
        #expect(flow.canJump(to: .welcome))
        #expect(flow.canJump(to: .realDebrid))
        #expect(!flow.canJump(to: .preferences))
        #expect(!flow.canJump(to: .ready))

        flow.go(to: .preferences)
        #expect(flow.step == .preferences)
        #expect(flow.canJump(to: .addons))
    }

    @Test func everyStepHasDisplayCopy() {
        for step in OnboardingFlow.Step.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.subtitle.isEmpty)
            #expect(!step.shortTitle.isEmpty)
            #expect(!step.systemImage.isEmpty)
        }
    }
}
