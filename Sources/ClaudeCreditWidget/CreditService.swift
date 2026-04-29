import Foundation

enum CreditServiceError: LocalizedError {
    case unauthorized
    case http(Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired"
        case .http(let code): return "HTTP \(code)"
        case .decoding(let e): return "Decode error: \(e.localizedDescription)"
        case .transport(let e): return "Network: \(e.localizedDescription)"
        }
    }
}

actor CreditService {
    private static let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fetchBalance(orgId: String, sessionKey: String) async throws -> CreditResponse {
        try await get(path: "prepaid/credits", orgId: orgId, sessionKey: sessionKey)
    }

    func fetchSpend(orgId: String, sessionKey: String) async throws -> SpendResponse {
        try await get(path: "current_spend", orgId: orgId, sessionKey: sessionKey)
    }

    func fetchRateLimits(orgId: String, sessionKey: String) async throws -> RateLimitsResponse {
        try await get(path: "rate_limits", orgId: orgId, sessionKey: sessionKey)
    }

    private func get<T: Decodable>(path: String, orgId: String, sessionKey: String) async throws -> T {
        guard let url = URL(string: "https://platform.claude.com/api/organizations/\(orgId)/\(path)") else {
            throw CreditServiceError.http(0)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("web_console", forHTTPHeaderField: "anthropic-client-platform")
        req.setValue("https://platform.claude.com/settings/billing", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw CreditServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CreditServiceError.http(0)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CreditServiceError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CreditServiceError.http(http.statusCode)
        }
        do {
            return try Self.isoDecoder.decode(T.self, from: data)
        } catch {
            throw CreditServiceError.decoding(error)
        }
    }
}
