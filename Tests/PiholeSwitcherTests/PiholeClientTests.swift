import Foundation
import Testing

@testable import PiholeSwitcher

/// Answers requests from a scripted fake Pi-hole and records what was asked.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Call: Equatable {
        var method: String
        var path: String
        var sid: String?
    }

    nonisolated(unsafe) static var handler: (@Sendable (Call) -> (Int, String))?
    nonisolated(unsafe) static var calls: [Call] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let call = Call(
            method: request.httpMethod ?? "",
            path: request.url?.path() ?? "",
            sid: request.value(forHTTPHeaderField: "X-FTL-SID")
        )
        Self.calls.append(call)
        let (status, body) = Self.handler?(call) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct PiholeClientTests {
    private func makeClient(password: String = "secret") -> PiholeClient {
        StubProtocol.calls = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return PiholeClient(
            baseURL: URL(string: "http://pi.hole")!,
            password: password,
            allowSelfSigned: false,
            configuration: configuration
        )
    }

    private static func authBody(sid: String) -> String {
        #"{"session":{"valid":true,"totp":false,"sid":"\#(sid)","csrf":"x","validity":300},"took":0.1}"#
    }

    @Test func logsInThenReadsStatus() async throws {
        let client = makeClient()
        StubProtocol.handler = { call in
            call.path == "/api/auth"
                ? (200, Self.authBody(sid: "SID1"))
                : (200, #"{"blocking":"disabled","timer":42.5,"took":0.1}"#)
        }
        let status = try await client.blockingStatus()
        #expect(status == BlockingStatus(isEnabled: false, secondsRemaining: 42.5))
        #expect(StubProtocol.calls == [
            .init(method: "POST", path: "/api/auth", sid: nil),
            .init(method: "GET", path: "/api/dns/blocking", sid: "SID1"),
        ])
    }

    @Test func reauthenticatesWhenSessionExpires() async throws {
        let client = makeClient()
        StubProtocol.handler = { call in
            call.path == "/api/auth" ? (200, Self.authBody(sid: "OLD")) : (200, #"{"blocking":true}"#)
        }
        _ = try await client.blockingStatus()

        StubProtocol.calls = []
        StubProtocol.handler = { call in
            if call.path == "/api/auth" { return (200, Self.authBody(sid: "NEW")) }
            return call.sid == "NEW"
                ? (200, #"{"blocking":"disabled","timer":300}"#)
                : (401, #"{"error":{"key":"unauthorized","message":"Unauthorized","hint":null}}"#)
        }
        let status = try await client.setBlocking(false, for: 300)
        #expect(status == BlockingStatus(isEnabled: false, secondsRemaining: 300))
        #expect(StubProtocol.calls.map(\.sid) == ["OLD", nil, "NEW"])
    }

    @Test func reportsWrongPassword() async {
        let client = makeClient()
        StubProtocol.handler = { _ in
            (401, #"{"error":{"key":"unauthorized","message":"Unauthorized","hint":null}}"#)
        }
        await #expect(throws: PiholeError.wrongPassword) { try await client.blockingStatus() }
    }

    @Test func skipsLoginWithoutPassword() async throws {
        let client = makeClient(password: "")
        StubProtocol.handler = { _ in (200, #"{"blocking":"enabled","timer":null}"#) }
        let status = try await client.blockingStatus()
        #expect(status == BlockingStatus(isEnabled: true, secondsRemaining: nil))
        #expect(StubProtocol.calls.map(\.path) == ["/api/dns/blocking"])
    }

    @Test func surfacesServerErrorMessage() async {
        let client = makeClient(password: "")
        StubProtocol.handler = { _ in
            (429, #"{"error":{"key":"rate_limiting","message":"Rate-limiting login attempts","hint":null}}"#)
        }
        await #expect(throws: PiholeError.http(429, "Rate-limiting login attempts")) {
            try await client.blockingStatus()
        }
    }

    @Test func readsSummary() async throws {
        let client = makeClient(password: "")
        StubProtocol.handler = { _ in
            (200, #"{"queries":{"total":7497,"blocked":3465,"percent_blocked":46.2,"unique_domains":445,"frequency":1.5},"gravity":{"domains_being_blocked":104756,"last_update":1},"took":0.1}"#)
        }
        let summary = try await client.summary()
        #expect(summary == PiholeSummary(
            totalQueries: 7497, blockedQueries: 3465, percentBlocked: 46.2, domainsOnLists: 104_756,
            queriesPerMinute: 90
        ))
        #expect(StubProtocol.calls.map(\.path) == ["/api/stats/summary"])
    }

    @Test func readsSystemInfo() async throws {
        let client = makeClient(password: "")
        StubProtocol.handler = { _ in
            (200, #"""
            {"system":{"uptime":67906,"memory":{"ram":{"total":10317877,"used":4526544,"%used":43.87},"swap":{"total":1}},
             "procs":1452,"cpu":{"nprocs":8,"%cpu":3.1,"load":{"raw":[0.58,0.74,0.76],"percent":[7.3,9.2,9.5]}},
             "ftl":{"%mem":0.4,"%cpu":0.1}},"took":0.1}
            """#)
        }
        let system = try await client.systemInfo()
        #expect(system == PiholeSystem(load: [0.58, 0.74, 0.76], memoryUsedPercent: 43.87))
        #expect(StubProtocol.calls.map(\.path) == ["/api/info/system"])
    }

    @Test(arguments: [
        ("pi.hole", "http://pi.hole"),
        (" 192.168.1.2/admin/ ", "http://192.168.1.2"),
        ("https://pi.hole:8443/api", "https://pi.hole:8443"),
        ("http://nas.local/pihole/admin", "http://nas.local/pihole"),
    ])
    func normalizesAddresses(input: String, expected: String) {
        #expect(PiholeClient.normalizedBaseURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://pi.hole"])
    func rejectsInvalidAddresses(input: String) {
        #expect(PiholeClient.normalizedBaseURL(from: input) == nil)
    }
}
