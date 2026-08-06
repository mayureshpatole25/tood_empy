import Foundation

/// Polar's customer-portal license-key endpoints. These are the
/// customer-facing (not organization-admin) endpoints — no secret API key
/// needed, safe to call directly from a distributed app. `organizationID`
/// is a public identifier, not a secret.
/// https://polar.sh/docs/features/benefits/license-keys
enum PolarLicenseService {
    private static let organizationID = "d0ce61a2-1dec-49dc-a11a-27b10e877b16"
    private static let base = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys")!

    enum LicenseError: LocalizedError {
        case invalidKey
        case network

        var errorDescription: String? {
            switch self {
            case .invalidKey: return "That license key doesn't look right. Double-check and try again."
            case .network: return "Couldn't reach the store — check your connection and try again."
            }
        }
    }

    private struct ActivateResponse: Decodable {
        let id: String
    }

    /// Activates this Mac against a license key, returning an activation ID
    /// worth keeping around for a future re-validation. Throws
    /// `.invalidKey` for a bad/exhausted key, `.network` for connectivity.
    static func activate(key: String) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("activate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "organization_id": organizationID,
            "label": Host.current().localizedName ?? "Mac",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.network
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LicenseError.invalidKey
        }

        // The activation ID is nice-to-have (for a future re-validation
        // pass); a 200 with an unparseable body still counts as a valid
        // redemption rather than failing the purchase over it.
        let decoded = try? JSONDecoder().decode(ActivateResponse.self, from: data)
        return decoded?.id ?? key
    }
}
