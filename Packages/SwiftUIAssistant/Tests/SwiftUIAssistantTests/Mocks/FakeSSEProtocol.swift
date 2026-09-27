import Foundation
import Synchronization

/// Serves scripted HTTP responses to a `URLSession`, one script per request, keyed by the request's host
final class FakeSSEProtocol: URLProtocol, @unchecked Sendable {
    enum Step: Sendable {
        case data(String)
        case bytes(Data)
        case fail(URLError.Code)
        /// Send nothing for a while
        case pause(TimeInterval)
        /// Stop sending without finishing the response
        case stall
    }

    struct Script: Sendable {
        var status = 200
        var headers: [String: String] = ["Content-Type": "text/event-stream"]
        var steps: [Step]
    }

    private static let scripts = Mutex<[String: [Script]]>([:])

    /// A session and base URL that serve `scripts` in order, one per request
    static func serving(_ scripts: [Script]) -> (session: URLSession, baseURL: URL) {
        let host = "fake-\(UUID().uuidString.lowercased()).invalid"
        self.scripts.withLock { $0[host] = scripts }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeSSEProtocol.self]
        return (URLSession(configuration: configuration), URL(string: "https://\(host)")!)
    }

    static func serving(_ steps: Step...) -> (session: URLSession, baseURL: URL) {
        serving([Script(steps: steps)])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url, let host = url.host,
            let script = Self.scripts.withLock({ $0[host]?.isEmpty == false ? $0[host]?.removeFirst() : nil })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: script.headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        deliver(script.steps[...], to: client)
    }

    private func deliver(_ steps: ArraySlice<Step>, to client: any URLProtocolClient) {
        guard let step = steps.first else {
            client.urlProtocolDidFinishLoading(self)
            return
        }
        switch step {
        case .data(let text):
            client.urlProtocol(self, didLoad: Data(text.utf8))
            deliver(steps.dropFirst(), to: client)
        case .bytes(let data):
            client.urlProtocol(self, didLoad: data)
            deliver(steps.dropFirst(), to: client)
        case .fail(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        case .pause(let seconds):
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                self.deliver(steps.dropFirst(), to: client)
            }
        case .stall:
            break
        }
    }

    override func stopLoading() {}
}
