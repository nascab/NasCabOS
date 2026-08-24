import Foundation

struct APIResponse<T> {
    let success: Bool
    let data: T?
    let message: String?
    let code: Int?
    let rawResponse: [String: Any]?

    static func success(_ data: T, message: String? = nil, code: Int? = nil, raw: [String: Any]? = nil) -> APIResponse {
        APIResponse(success: true, data: data, message: message, code: code, rawResponse: raw)
    }

    static func failure(_ message: String, code: Int? = nil, raw: [String: Any]? = nil) -> APIResponse {
        APIResponse(success: false, data: nil, message: message, code: code, rawResponse: raw)
    }

    static func fromJSON(
        httpCode: Int,
        json: [String: Any],
        dataParser: (([String: Any], Int) -> T)? = nil
    ) -> APIResponse {
        let apiSuccess = (json["success"] as? Bool) == true || (json["code"] as? Int) == 0
        var message = json["message"] as? String
        let rawCode = stringValue(json["code"])

        if rawCode == "service.NASCAB_SESSION_EXPIRED" {
            message = L10n.serviceSessionExpired
        }

        var data: T?
        if apiSuccess, let parser = dataParser {
            let rawData = json["data"] as? [String: Any] ?? [:]
            data = parser(rawData, httpCode)
        } else {
            data = json["data"] as? T
        }

        return APIResponse(
            success: apiSuccess,
            data: data,
            message: message,
            code: httpCode,
            rawResponse: json
        )
    }

    private static func stringValue(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        return "\(v)"
    }
}
