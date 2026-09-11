import Foundation
import Testing
@testable import Nami

enum DebridFixtures {
    static func userJSON(type: String = "premium", premium: Int = 1_000_000) -> Data {
        Data("""
        {
          "id": 42,
          "username": "tester",
          "email": "t@example.com",
          "points": 120,
          "type": "\(type)",
          "premium": \(premium),
          "expiration": "2032-06-06T04:42:42.000Z"
        }
        """.utf8)
    }

    static func addMagnetJSON(id: String) -> Data {
        Data("{\"id\":\"\(id)\",\"uri\":\"https://api.real-debrid.com/torrents/\(id)\"}".utf8)
    }

    static func errorJSONString(_ message: String, code: Int?) -> String {
        if let code {
            return "{\"error\":\"\(message)\",\"error_code\":\(code)}"
        }
        return "{\"error\":\"\(message)\"}"
    }

    static func torrentInfoJSON(
        id: String,
        status: String,
        links: [String] = [],
        files: [(id: Int, path: String, bytes: Int64, selected: Int)] = []
    ) -> Data {
        let filesJSON = files
            .map { "{\"id\":\($0.id),\"path\":\"\($0.path)\",\"bytes\":\($0.bytes),\"selected\":\($0.selected)}" }
            .joined(separator: ",")
        let linksJSON = links.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("""
        {
          "id": "\(id)",
          "hash": "aabbccddeeff00112233445566778899aabbccdd",
          "filename": "Show",
          "status": "\(status)",
          "progress": 0,
          "links": [\(linksJSON)],
          "files": [\(filesJSON)]
        }
        """.utf8)
    }

    static func torrentListJSON(_ items: [(id: String, hash: String, status: String)]) -> Data {
        let itemsJSON = items
            .map { "{\"id\":\"\($0.id)\",\"hash\":\"\($0.hash)\",\"status\":\"\($0.status)\"}" }
            .joined(separator: ",")
        return Data("[\(itemsJSON)]".utf8)
    }

    static func unrestrictJSON(
        download: String = "https://download.real-debrid.com/file.mkv",
        filename: String = "Show - 07.mkv",
        filesize: Int64 = 1_400_000_000
    ) -> Data {
        Data("""
        {
          "id": "UN1",
          "filename": "\(filename)",
          "filesize": \(filesize),
          "download": "\(download)",
          "streamable": 1
        }
        """.utf8)
    }
}

actor DebridStubBackend {
    enum AddMagnetOutcome {
        case success(id: String)
        case apiError(httpStatus: Int, code: Int?, message: String)
    }

    private(set) var requests: [(method: String, path: String)] = []
    private(set) var requestURLs: [String] = []
    private(set) var formBodies: [String] = []

    var userType: String
    var userPremiumSeconds: Int
    var userError: (status: Int, code: Int?, message: String)?
    var addMagnetResult: AddMagnetOutcome
    var infoStatuses: [String]
    var infoFiles: [(id: Int, path: String, bytes: Int64, selected: Int)]
    var infoLinks: [String]
    var torrentList: [(id: String, hash: String, status: String)]
    var unrestrictDownload: String

    private var infoCalls = 0

    init(
        userType: String = "premium",
        userPremiumSeconds: Int = 1_000_000,
        userError: (status: Int, code: Int?, message: String)? = nil,
        addMagnetResult: AddMagnetOutcome = .success(id: "T1"),
        infoStatuses: [String] = ["downloaded"],
        infoFiles: [(id: Int, path: String, bytes: Int64, selected: Int)] = [],
        infoLinks: [String] = [],
        torrentList: [(id: String, hash: String, status: String)] = [],
        unrestrictDownload: String = "https://download.real-debrid.com/file.mkv"
    ) {
        self.userType = userType
        self.userPremiumSeconds = userPremiumSeconds
        self.userError = userError
        self.addMagnetResult = addMagnetResult
        self.infoStatuses = infoStatuses
        self.infoFiles = infoFiles
        self.infoLinks = infoLinks
        self.torrentList = torrentList
        self.unrestrictDownload = unrestrictDownload
    }

    func respond(to request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        guard let url = request.url else {
            throw HTTPError.transport("missing url")
        }
        let path = url.path.replacingOccurrences(of: "/rest/1.0", with: "")
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        requests.append((method, path))
        requestURLs.append(url.absoluteString)
        if !body.isEmpty {
            formBodies.append(body)
        }

        switch (method, path) {
        case ("GET", "/user"):
            if let userError {
                throw HTTPError.httpStatus(
                    code: userError.status,
                    body: DebridFixtures.errorJSONString(userError.message, code: userError.code)
                )
            }
            return DebridFixtures.userJSON(type: userType, premium: userPremiumSeconds)

        case ("POST", "/torrents/addMagnet"):
            switch addMagnetResult {
            case .success(let id):
                return DebridFixtures.addMagnetJSON(id: id)
            case .apiError(let status, let code, let message):
                throw HTTPError.httpStatus(
                    code: status,
                    body: DebridFixtures.errorJSONString(message, code: code)
                )
            }

        case ("POST", let path) where path.hasPrefix("/torrents/selectFiles/"):
            return Data()

        case ("GET", let path) where path.hasPrefix("/torrents/info/"):
            let index = min(infoCalls, max(infoStatuses.count - 1, 0))
            let status = infoStatuses.isEmpty ? "downloaded" : infoStatuses[index]
            infoCalls += 1
            return DebridFixtures.torrentInfoJSON(
                id: "T1",
                status: status,
                links: infoLinks,
                files: infoFiles
            )

        case ("GET", "/torrents"):
            return DebridFixtures.torrentListJSON(torrentList)

        case ("DELETE", let path) where path.hasPrefix("/torrents/delete/"):
            return Data()

        case ("POST", "/unrestrict/link"):
            return DebridFixtures.unrestrictJSON(download: unrestrictDownload)

        default:
            throw HTTPError.httpStatus(
                code: 404,
                body: DebridFixtures.errorJSONString("unknown path \(path)", code: nil)
            )
        }
    }
}

struct RealDebridModelsTests {
    @Test func decodesAccountAndExpiration() throws {
        let user = try JSONDecoder().decode(RealDebridUser.self, from: DebridFixtures.userJSON())
        let account = DebridAccount(realDebrid: user)

        #expect(account.id == 42)
        #expect(account.username == "tester")
        #expect(account.type == .premium)
        #expect(account.isPremium)
        #expect(account.points == 120)
        #expect(account.expiration != nil)
    }

    @Test func freeAccountIsNotPremium() throws {
        let user = try JSONDecoder().decode(
            RealDebridUser.self,
            from: DebridFixtures.userJSON(type: "free", premium: 0)
        )
        let account = DebridAccount(realDebrid: user)
        #expect(!account.isPremium)
    }

    @Test func decodesTorrentInfoFiles() throws {
        let data = DebridFixtures.torrentInfoJSON(
            id: "T1",
            status: "downloaded",
            links: ["https://real-debrid.com/dl/1"],
            files: [(1, "/Show - 07.mkv", 1_400_000_000, 1), (2, "/Show - 07.srt", 10_000, 0)]
        )
        let info = try JSONDecoder().decode(RealDebridTorrentInfo.self, from: data)
        #expect(info.fileInfos.count == 2)
        #expect(info.fileInfos.first?.filename == "Show - 07.mkv")
        #expect(info.fileInfos.first?.selected == true)
        #expect(info.fileInfos.last?.selected == false)
    }

    @Test func parsesErrorBody() {
        let body = DebridFixtures.errorJSONString("infringing_file", code: 35)
        #expect(RealDebridModels.parseErrorCode(body) == 35)
        #expect(RealDebridModels.parseErrorMessage(body) == "infringing_file")
    }

    @Test func mapsErrorCodes() {
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 401, error: nil, code: 8)) == .unauthorized)
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 403, error: "locked", code: 14)) == .accountLocked)
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 403, error: nil, code: 9)) == .notPremium)
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 429, error: nil, code: 34)) == .rateLimited)
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 451, error: "infringing", code: 35)) == .infringingContent)
        #expect(DebridError.map(RealDebridAPIError(httpStatus: 400, error: "Torrent too big", code: 29)) == .torrentTooBig)
    }
}
