import Foundation

/// Runtime HTTP diagnostics for development builds.
/// Captures request start/end, status codes, payload sizes and failures without logging secrets.
enum NetworkDiagnostics {
    private static let lock = NSLock()
    private static var installed = false

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        URLProtocol.registerClass(DiagnosticsURLProtocol.self)
        godLog("🌐 Network diagnostics installed (HTTP/HTTPS requests)", level: .diagnostic)
    }

    static func logTask(_ message: String, level: LogLevel = .diagnostic) {
        godLog("🌐 NET: \(message)", level: level)
    }
}

private final class DiagnosticsURLProtocol: URLProtocol {
    private static let handledKey = "ForexScalperApp.DiagnosticsURLProtocol.handled"
    private var task: URLSessionDataTask?
    private var startTime = Date()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return !property(forKey: handledKey, in: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        startTime = Date()
        let url = request.url?.absoluteString ?? "<unknown>"
        let method = request.httpMethod ?? "GET"
        let bodyBytes = request.httpBody?.count ?? 0
        NetworkDiagnostics.logTask("→ \(method) \(url) body=\(bodyBytes)b")

        var forwarded = request
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: &forwarded)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        let session = URLSession(configuration: configuration)
        task = session.dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.startTime) * 1000)
            let bytes = data?.count ?? 0

            if let error {
                NetworkDiagnostics.logTask("✖ \(method) \(url) FAILED after \(elapsed)ms: \(error.localizedDescription)", level: .error)
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let http = response as? HTTPURLResponse {
                let level: LogLevel = (200..<400).contains(http.statusCode) ? .diagnostic : .warning
                NetworkDiagnostics.logTask("← \(http.statusCode) \(method) \(url) \(elapsed)ms bytes=\(bytes)", level: level)
            } else {
                NetworkDiagnostics.logTask("← response \(method) \(url) \(elapsed)ms bytes=\(bytes)")
            }

            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task?.resume()
    }

    override func stopLoading() {
        task?.cancel()
        task = nil
    }
}
