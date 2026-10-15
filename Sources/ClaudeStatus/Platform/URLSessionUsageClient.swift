import ClaudeStatusCore
import Foundation

struct URLSessionUsageClient: UsageFetching {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetchUsage(token: String) async throws -> UsageResponseDTO {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageFetchError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.network("odpověď není HTTP") }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw UsageFetchError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageFetchError.rateLimited(retryAfter: retryAfter)
        default:
            throw UsageFetchError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageResponseDTO.self, from: data)
        } catch {
            throw UsageFetchError.decoding
        }
    }
}
