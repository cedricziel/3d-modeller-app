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
                defaultValue: 30.0
            )
        ]
    }

    public init() {}

    public func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        guard let urlString = arguments["url"] as? String else {
            return .failure("Missing required parameter: url")
        }

        guard let url = URL(string: urlString) else {
            return .failure("Invalid URL: \(urlString)")
        }

        let method = (arguments["method"] as? String)?.uppercased() ?? "GET"
        let body = arguments["body"] as? String
        let headers = arguments["headers"] as? [String: String]
        let timeout = arguments["timeout"] as? Double ?? 30.0

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
            var responseData: Any?
            var responseText: String?

            if contentType.contains("application/json") {
                responseData = try? JSONSerialization.jsonObject(with: data)
            }

            if responseData == nil {
                responseText = String(data: data, encoding: .utf8)
            }

            let isSuccess = (200..<300).contains(statusCode)
            let message = isSuccess
                ? "Successfully fetched \(url.absoluteString) (HTTP \(statusCode))"
                : "Request failed with HTTP \(statusCode)"

            var resultData: [String: Any] = [
                "statusCode": statusCode,
                "contentType": contentType,
                "url": url.absoluteString,
                "method": method
            ]

            if let responseData = responseData {
                resultData["data"] = responseData
            } else if let responseText = responseText {
                // Truncate very long responses
                let maxLength = 10000
                if responseText.count > maxLength {
                    resultData["text"] = String(responseText.prefix(maxLength)) + "... (truncated)"
                    resultData["truncated"] = true
                    resultData["originalLength"] = responseText.count
                } else {
                    resultData["text"] = responseText
                }
            }

            // Include response headers
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
            resultData["headers"] = responseHeaders

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
