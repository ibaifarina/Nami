import Foundation
import Testing
@testable import Nami

private actor MockStreamProbe: StreamProbing {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    private var stubs: [Stub]
    private let error: StreamProbeError?
    private(set) var requests: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
        error = nil
    }

    init(error: StreamProbeError) {
        stubs = []
        self.error = error
    }

    func probe(_ request: URLRequest) async throws -> StreamProbeResponse {
        requests.append(request)
        if let error {
            throw error
        }
        guard !stubs.isEmpty else {
            throw StreamProbeError.transport("No stub response queued")
        }
        let stub = stubs.removeFirst()
        return StreamProbeResponse(
            statusCode: stub.statusCode,
            headers: stub.headers,
            bodyPrefix: stub.body
        )
    }
}

struct StreamValidationServiceTests {
    private func stream(_ url: String = "https://cdn.example/video.mp4") -> ResolvedStream {
        ResolvedStream(
            url: testURL(url),
            filename: "video.mp4",
            sizeBytes: 1_400_000_000,
            streamable: true,
            fileID: 1
        )
    }

    private func makeService(
        probe: MockStreamProbe,
        durationProbe: @escaping StreamValidationService.DurationProbe = { _ in nil }
    ) -> StreamValidationService {
        StreamValidationService(probe: probe, durationProbe: durationProbe)
    }

    private func expectIssue(
        _ verdict: StreamValidationVerdict,
        kind: StreamValidationIssue.Kind,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        switch verdict {
        case .candidateInvalid(let issue), .transient(let issue), .accountIssue(let issue):
            #expect(issue.kind == kind, sourceLocation: sourceLocation)
        case .playable, .uncertain:
            Issue.record("Expected an issue verdict, got \(verdict)", sourceLocation: sourceLocation)
        }
    }

    @Test func playableMediaResponseIsAccepted() async {
        let probe = MockStreamProbe([
            .init(
                statusCode: 206,
                headers: [
                    "content-type": "video/mp4",
                    "content-range": "bytes 0-1023/1400000000",
                ]
            ),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .playable)
    }

    @Test func octetStreamBodyWithFtypIsAccepted() async {
        var body = Data([0x00, 0x00, 0x00, 0x18])
        body.append(contentsOf: Array("ftypisom".utf8))
        let probe = MockStreamProbe([
            .init(
                statusCode: 206,
                headers: ["content-type": "application/octet-stream"],
                body: body
            ),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .playable)
    }

    @Test func infringingJSONBodyIsRejected() async {
        let body = Data(#"{"error":"infringing_file","error_code":35}"#.utf8)
        let probe = MockStreamProbe([
            .init(statusCode: 200, headers: ["content-type": "application/json"], body: body),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .infringing)
    }

    @Test func copyrightHTMLPageIsRejected() async {
        let body = Data("""
        <!DOCTYPE html><html><head><title>Error</title></head>
        <body>File was removed from debrid service due to copyright infringement.</body></html>
        """.utf8)
        let probe = MockStreamProbe([
            .init(statusCode: 200, headers: ["content-type": "text/html"], body: body),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .candidateInvalid(StreamValidationIssue(kind: .infringing)))
    }

    @Test func notFoundIsCandidateInvalid() async {
        let probe = MockStreamProbe([.init(statusCode: 404)])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        if case .candidateInvalid(let issue) = verdict {
            #expect(issue.kind == .unavailableFile)
        } else {
            Issue.record("Expected a candidate-invalid verdict, got \(verdict)")
        }
    }

    @Test func status451IsInfringing() async {
        let probe = MockStreamProbe([.init(statusCode: 451)])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .infringing)
    }

    @Test func rateLimitIsTransient() async {
        let probe = MockStreamProbe([.init(statusCode: 429)])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .rateLimited)
    }

    @Test func lockedAccountIsGlobal() async {
        let body = Data(#"{"error":"Account locked","error_code":14}"#.utf8)
        let probe = MockStreamProbe([
            .init(statusCode: 403, headers: ["content-type": "application/json"], body: body),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .accountIssue)
    }

    @Test func fairUseIsGlobal() async {
        let body = Data(#"{"error":"Fair Usage Limit","error_code":36}"#.utf8)
        let probe = MockStreamProbe([
            .init(statusCode: 200, headers: ["content-type": "application/json"], body: body),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .fairUseLimit)
    }

    @Test func redirectToErrorPageIsRejected() async {
        let probe = MockStreamProbe([
            .init(statusCode: 302, headers: ["location": "https://real-debrid.com/error/35"]),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .errorPage)
    }

    @Test func redirectToMediaIsFollowed() async {
        let probe = MockStreamProbe([
            .init(statusCode: 302, headers: ["location": "https://cdn.example/real.mp4"]),
            .init(
                statusCode: 206,
                headers: [
                    "content-type": "video/mp4",
                    "content-range": "bytes 0-1023/1400000000",
                ]
            ),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .playable)
    }

    @Test func redirectToFilenameContainingErrorWordIsFollowed() async {
        let probe = MockStreamProbe([
            .init(
                statusCode: 302,
                headers: ["location": "https://cdn.example/The.Expired.2024.mkv"]
            ),
            .init(
                statusCode: 206,
                headers: [
                    "content-type": "video/x-matroska",
                    "content-range": "bytes 0-1023/1400000000",
                ]
            ),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .playable)
    }

    @Test func tooManyRedirectsIsRejected() async {
        let probe = MockStreamProbe([
            .init(statusCode: 302, headers: ["location": "https://cdn.example/1"]),
            .init(statusCode: 302, headers: ["location": "https://cdn.example/2"]),
            .init(statusCode: 302, headers: ["location": "https://cdn.example/3"]),
            .init(statusCode: 302, headers: ["location": "https://cdn.example/4"]),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        if case .candidateInvalid(let issue) = verdict {
            #expect(issue.kind == .errorPage)
        } else {
            Issue.record("Expected a candidate-invalid verdict, got \(verdict)")
        }
    }

    @Test func htmlPageWithoutKnownReasonIsRejected() async {
        let body = Data("<!DOCTYPE html><html><body>Something went wrong</body></html>".utf8)
        let probe = MockStreamProbe([
            .init(statusCode: 200, headers: ["content-type": "text/html"], body: body),
        ])
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        expectIssue(verdict, kind: .errorPage)
    }

    @Test func shortSlateVideoIsRejectedUsingDurationProbe() async {
        let probe = MockStreamProbe([
            .init(
                statusCode: 206,
                headers: [
                    "content-type": "video/mp4",
                    "content-range": "bytes 0-1023/3000000",
                ]
            ),
        ])
        let service = makeService(probe: probe) { _ in 31 }
        let verdict = await service.validate(
            stream(),
            context: .init(expectedSizeBytes: 1_400_000_000, expectedDurationMinutes: 24)
        )

        if case .candidateInvalid(let issue) = verdict {
            #expect(issue.kind == .slateVideo)
        } else {
            Issue.record("Expected a candidate-invalid verdict, got \(verdict)")
        }
    }

    @Test func shortFeatureDoesNotTriggerSlateCheck() async {
        let probe = MockStreamProbe([
            .init(
                statusCode: 206,
                headers: [
                    "content-type": "video/mp4",
                    "content-range": "bytes 0-1023/18000000",
                ]
            ),
        ])
        let service = makeService(probe: probe) { _ in 110 }
        let verdict = await service.validate(
            stream(),
            context: .init(expectedSizeBytes: 18_000_000, expectedDurationMinutes: 2)
        )

        #expect(verdict == .playable)
    }

    @Test func networkFailureIsUncertain() async {
        let probe = MockStreamProbe(error: .timedOut)
        let verdict = await makeService(probe: probe).validate(stream(), context: .init())

        #expect(verdict == .uncertain)
    }

    @Test func invalidSchemeIsCandidateInvalid() async {
        let probe = MockStreamProbe([])
        let verdict = await makeService(probe: probe).validate(
            stream("ftp://cdn.example/video.mp4"),
            context: .init()
        )

        #expect(verdict == .candidateInvalid(StreamValidationIssue(kind: .nonMedia, detail: "Unsupported URL")))
    }
}
