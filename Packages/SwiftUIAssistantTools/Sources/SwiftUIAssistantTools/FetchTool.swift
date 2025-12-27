import Foundation
import SwiftUIAssistant

/// Tool for making HTTP requests to fetch data from URLs
public struct FetchTool: AssistantTool, Sendable {
    public let id = "fetch"
    public let name = "fetch"
    public let description = "Makes HTTP requests to fetch data from a URL. Supports GET, POST, PUT, PATCH, and DELETE methods."

    public var parameters: [ToolParameter] {
        [
            .string("url", description: "The URL to fetch data from"),
            .enumParameter(
                "method",
                description: "The HTTP method to use",
                values: ["GET", "POST", "PUT", "PATCH", "DELETE"],
                required: false
            ),
            .optionalString("body", description: "The request body for POST/PUT/PATCH requests (JSON string)"),
            ToolParameter(
                name: "headers",
                type: .object,
                description: "Optional HTTP headers as key-value pairs",
                required: false
            ),
            ToolParameter(
                name: "timeout",
                type: .number,
                description: "Request timeout in seconds (default: 30)",
                required: false,
                defaultValue: .number(30.0)
            )
        ]
    }

    public init() {}

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        guard let urlString = arguments["url"]?.stringValue else {
            return .failure("Missing required parameter: url")
        }

        guard let url = URL(string: urlString) else {
            return .failure("Invalid URL: \(urlString)")
        }

        let method = arguments["method"]?.stringValue?.uppercased() ?? "GET"
        let body = arguments["body"]?.stringValue
        let headers = arguments["headers"]?.objectValue?.compactMapValues { $0.stringValue }
        let timeout = arguments["timeout"]?.doubleValue ?? 30.0

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Apply custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set body for methods that support it
        if let body = body, ["POST", "PUT", "PATCH"].contains(method) {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Invalid response type")
            }

            let statusCode = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

            // Try to parse response as JSON
            var responseData: JSONValue?
            var responseText: String?

            if contentType.contains("application/json"),
               let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let jsonDict = jsonObject as? [String: Any],
               let jsonValue = [String: JSONValue](fromAny: jsonDict) {
                responseData = .object(jsonValue)
            } else if contentType.contains("application/json"),
                      let jsonObject = try? JSONSerialization.jsonObject(with: data),
                      let jsonArray = jsonObject as? [Any] {
                // Handle JSON arrays
                responseData = JSONValue.fromAny(jsonArray)
            }

            if responseData == nil {
                responseText = String(data: data, encoding: .utf8)
            }

            let isSuccess = (200..<300).contains(statusCode)
            let message = isSuccess
                ? "Successfully fetched \(url.absoluteString) (HTTP \(statusCode))"
                : "Request failed with HTTP \(statusCode)"

            var resultData: [String: JSONValue] = [
                "statusCode": .integer(statusCode),
                "contentType": .string(contentType),
                "url": .string(url.absoluteString),
                "method": .string(method)
            ]

            if let responseData = responseData {
                resultData["data"] = responseData
            } else if let responseText = responseText {
                // Truncate very long responses
                let maxLength = 10000
                if responseText.count > maxLength {
                    resultData["text"] = .string(String(responseText.prefix(maxLength)) + "... (truncated)")
                    resultData["truncated"] = .bool(true)
                    resultData["originalLength"] = .integer(responseText.count)
                } else {
                    resultData["text"] = .string(responseText)
                }
            }

            // Include response headers
            var responseHeaders: [String: JSONValue] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = .string(valueString)
                }
            }
            resultData["headers"] = .object(responseHeaders)

            return ToolExecutionResult(
                success: isSuccess,
                message: message,
                data: resultData
            )
        } catch let error as URLError {
            let errorMessage: String
            switch error.code {
            case .timedOut:
                errorMessage = "Request timed out after \(timeout) seconds"
            case .notConnectedToInternet:
                errorMessage = "No internet connection"
            case .cannotFindHost:
                errorMessage = "Cannot find host: \(url.host ?? urlString)"
            case .cannotConnectToHost:
                errorMessage = "Cannot connect to host: \(url.host ?? urlString)"
            case .secureConnectionFailed:
                errorMessage = "Secure connection failed (SSL/TLS error)"
            default:
                errorMessage = "Network error: \(error.localizedDescription)"
            }
            return .failure(errorMessage)
        } catch {
            return .failure("Request failed: \(error.localizedDescription)")
        }
    }
}
