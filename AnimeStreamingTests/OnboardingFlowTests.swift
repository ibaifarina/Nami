import Foundation
import Testing
@testable import AnimeStreaming

struct OnboardingFlowTests {
    @Test func startsAtWelcome() {
        let flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        #expect(flow.isFirst)
        #expect(!flow.isLast)
        #expect(flow.stepNumber == 1)
        #expect(flow.stepCount == 4)
    }

    @Test func advancesThroughEveryStep() {
        var flow = OnboardingFlow()
        let expected: [OnboardingFlow.Step] = [.realDebrid, .addons, .preferences]
        for step in expected {
            flow.advance()
            #expect(flow.step == step)
        }
        #expect(flow.isLast)
        #expect(flow.stepNumber == 4)

        flow.advance()
        #expect(flow.step == .preferences)
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

    @Test func everyStepHasATitle() {
        for step in OnboardingFlow.Step.allCases {
            #expect(!step.title.isEmpty)
        }
    }
}
