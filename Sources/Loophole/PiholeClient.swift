import Foundation

struct BlockingStatus: Equatable, Sendable {
    var isEnabled: Bool
    /// Seconds until Pi-hole flips back to the opposite state, if a timer is running.
    var secondsRemaining: Double?
}

struct PiholeSummary: Equatable, Sendable {
    var totalQueries: Int
    var blockedQueries: Int
    var percentBlocked: Double
    /// Size of the blocklists ("gravity"); absent if the Pi-hole doesn't report it.
    var domainsOnLists: Int?
    var queriesPerMinute: Double?
}

/// Health of the machine Pi-hole runs on.
struct PiholeSystem: Equatable, Sendable {
    /// Load averages over 1, 5 and 15 minutes.
    var load: [Double]
    var memoryUsedPercent: Double?
}

enum PiholeError: LocalizedError, Equatable {
    case wrongPassword
    case passwordRequired
    case totpRequired
    case http(Int, String?)
    case unexpectedResponse
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword:
            "Pi-hole rejected the password."
        case .passwordRequired:
            "This Pi-hole needs a password. Add it in Settings."
        case .totpRequired:
            "This Pi-hole uses two-factor login. Create an app password in Pi-hole (Settings → Web interface / API) and use that instead."
        case .http(let code, let message):
            message.map { "Pi-hole error \(code): \($0)" } ?? "Pi-hole returned HTTP \(code)."
        case .unexpectedResponse:
            "Pi-hole sent a response this app doesn't understand. It needs Pi-hole v6 or newer."
        case .unreachable(let reason):
            reason
        }
    }
}

/// Talks to the Pi-hole v6 REST API (`/api/auth`, `/api/dns/blocking`, `/api/stats/summary`,
/// `/api/info/system`).
actor PiholeClient {
    private let baseURL: URL
    private let password: String
    private let session: URLSession
    private var sid: String?

    init(
        baseURL: URL,
        password: String,
        allowSelfSigned: Bool,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.baseURL = baseURL
        self.password = password
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        session = URLSession(
            configuration: configuration,
            delegate: TrustDelegate(trustedHost: allowSelfSigned ? baseURL.host() : nil),
            delegateQueue: nil
        )
    }

    /// Turns user input like `pi.hole`, `192.168.1.2/admin` or `https://pi.hole:8443/` into a base URL.
    static func normalizedBaseURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/admin", "/api"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func blockingStatus() async throws -> BlockingStatus {
        try decodeStatus(try await request("GET", "api/dns/blocking"))
    }

    /// - Parameter seconds: how long the new state should last before Pi-hole reverts it; `nil` means indefinitely.
    func setBlocking(_ enabled: Bool, for seconds: Int? = nil) async throws -> BlockingStatus {
        let body: [String: Any] = ["blocking": enabled, "timer": seconds.map { $0 as Any } ?? NSNull()]
        return try decodeStatus(try await request("POST", "api/dns/blocking", body: body))
    }

    /// Query totals as shown on the Pi-hole dashboard.
    func summary() async throws -> PiholeSummary {
        guard let decoded = try? JSONDecoder().decode(SummaryResponse.self, from: try await request("GET", "api/stats/summary"))
        else { throw PiholeError.unexpectedResponse }
        return PiholeSummary(
            totalQueries: decoded.queries.total,
            blockedQueries: decoded.queries.blocked,
            percentBlocked: decoded.queries.percent_blocked,
            domainsOnLists: decoded.gravity?.domains_being_blocked,
            // The API reports queries per second; the admin page shows per minute.
            queriesPerMinute: decoded.queries.frequency.map { $0 * 60 }
        )
    }

    /// Load and memory use, as in the Status box of the admin page.
    func systemInfo() async throws -> PiholeSystem {
        guard let decoded = try? JSONDecoder().decode(SystemResponse.self, from: try await request("GET", "api/info/system"))
        else { throw PiholeError.unexpectedResponse }
        return PiholeSystem(
            load: decoded.system.cpu?.load?.raw ?? [],
            memoryUsedPercent: decoded.system.memory?.ram?.percentUsed
        )
    }

    /// Frees the API session seat on the Pi-hole. Best effort.
    func logout() async {
        guard let sid else { return }
        self.sid = nil
        _ = try? await send("DELETE", "api/auth", sid: sid)
    }

    // MARK: - Plumbing

    private func request(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        if sid == nil, !password.isEmpty { try await login() }
        var (data, response) = try await send(method, path, body: body, sid: sid)
        if response.statusCode == 401 {
            // Session expired (or was never valid): log in again and retry once.
            guard !password.isEmpty else { throw PiholeError.passwordRequired }
            sid = nil
            try await login()
            (data, response) = try await send(method, path, body: body, sid: sid)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PiholeError.http(response.statusCode, Self.errorMessage(in: data))
        }
        return data
    }

    private func login() async throws {
        let (data, response) = try await send("POST", "api/auth", body: ["password": password])
        if response.statusCode == 401 { throw PiholeError.wrongPassword }
        guard (200..<300).contains(response.statusCode) else {
            throw PiholeError.http(response.statusCode, Self.errorMessage(in: data))
        }
        guard let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            throw PiholeError.unexpectedResponse
        }
        guard auth.session.valid, let sid = auth.session.sid else {
            throw auth.session.totp == true ? PiholeError.totpRequired : PiholeError.wrongPassword
        }
        self.sid = sid
    }

    private func send(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        sid: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let sid { request.setValue(sid, forHTTPHeaderField: "X-FTL-SID") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PiholeError.unexpectedResponse }
            return (data, http)
        } catch let error as URLError {
            throw PiholeError.unreachable(error.localizedDescription)
        }
    }

    private func decodeStatus(_ data: Data) throws -> BlockingStatus {
        guard let decoded = try? JSONDecoder().decode(BlockingResponse.self, from: data) else {
            throw PiholeError.unexpectedResponse
        }
        return BlockingStatus(isEnabled: decoded.isEnabled, secondsRemaining: decoded.timer)
    }

    private static func errorMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
    }
}

// MARK: - Wire formats

private struct AuthResponse: Decodable {
    struct Session: Decodable {
        let valid: Bool
        let totp: Bool?
        let sid: String?
    }
    let session: Session
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail
}

private struct SummaryResponse: Decodable {
    struct Queries: Decodable {
        let total: Int
        let blocked: Int
        let percent_blocked: Double
        let frequency: Double?
    }
    struct Gravity: Decodable {
        let domains_being_blocked: Int?
    }
    let queries: Queries
    let gravity: Gravity?
}

private struct SystemResponse: Decodable {
    struct System: Decodable {
        struct CPU: Decodable {
            struct Load: Decodable { let raw: [Double]? }
            let load: Load?
        }
        struct Memory: Decodable {
            struct RAM: Decodable {
                let percentUsed: Double?
                enum CodingKeys: String, CodingKey { case percentUsed = "%used" }
            }
            let ram: RAM?
        }
        let cpu: CPU?
        let memory: Memory?
    }
    let system: System
}

private struct BlockingResponse: Decodable {
    let isEnabled: Bool
    let timer: Double?

    enum CodingKeys: String, CodingKey { case blocking, timer }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // FTL reports "enabled"/"disabled" (or "failed"/"unknown"); the docs also show a plain boolean.
        if let flag = try? container.decode(Bool.self, forKey: .blocking) {
            isEnabled = flag
        } else {
            switch try container.decode(String.self, forKey: .blocking) {
            case "enabled": isEnabled = true
            case "disabled": isEnabled = false
            default: throw PiholeError.unexpectedResponse
            }
        }
        timer = try? container.decodeIfPresent(Double.self, forKey: .timer)
    }
}

// MARK: - Self-signed certificates

/// Pi-hole v6 serves HTTPS with a self-signed certificate by default. When the user opts in,
/// accept whatever certificate the configured host presents — and only that host.
private final class TrustDelegate: NSObject, URLSessionDelegate {
    private let trustedHost: String?

    init(trustedHost: String?) {
        self.trustedHost = trustedHost
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trustedHost, space.host == trustedHost,
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
