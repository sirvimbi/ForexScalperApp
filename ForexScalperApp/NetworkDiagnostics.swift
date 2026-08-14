import Foundation

/// Runtime HTTP diagnostics for development builds.
/// Captures request start/end, status codes, payload sizes and failures without logging secrets.
enum NetworkDiagnostics {
    private static let lock = NSLock()
    private static var installed = false

    static func install() {
        lock.lock()
        guard !installed else {
            lock.unlock()
            return
        }
        installed = true
        lock.unlock()

        URLProtocol.registerClass(DiagnosticsURLProtocol.self)
        godLog("🌐 Network diagnostics installed (HTTP/HTTPS requests)", level: .diagnostic)
    }

    static func logTask(_ message: String, level: LogLevel = .diagnostic) {
        godLog("🌐 NET: \(message)", level: level)
    }
}

private final class DiagnosticsURLProtocol: URLProtocol {
    private static let handledKey = "ForexScalperApp.DiagnosticsURLProtocol.handled"
    private var session: URLSession?
    // URLProtocol already exposes an inherited `task` property. Do not declare a
    // stored property with that name; keep our concrete data task separately.
    private var dataTask: URLSessionDataTask?
    private var startTime = Date()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        // URLProtocol.property(forKey:in:) returns Any?, so explicitly test for nil.
        return URLProtocol.property(forKey: handledKey, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        startTime = Date()
        let url = request.url?.absoluteString ?? "<unknown>"
        let method = request.httpMethod ?? "GET"
        let bodyBytes = request.httpBody?.count ?? 0
        NetworkDiagnostics.logTask("→ \(method) \(url) body=\(bodyBytes)b")

        // URLProtocol.setProperty(_:forKey:in:) requires NSMutableURLRequest.
        // Make a mutable copy so the original request remains untouched.
        guard let forwarded = request.mutableCopy() as? NSMutableURLRequest else {
            let error = NSError(
                domain: "ForexScalperApp.NetworkDiagnostics",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create mutable URLRequest for diagnostics"]
            )
            NetworkDiagnostics.logTask("✖ \(method) \(url) FAILED before request: \(error.localizedDescription)", level: .error)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: forwarded)

        let configuration = URLSessionConfiguration.ephemeral
        // Prevent this URLProtocol from recursively intercepting its own request.
        configuration.protocolClasses = []
        let session = URLSession(configuration: configuration)
        self.session = session
        dataTask = session.dataTask(with: forwarded as URLRequest) { [weak self] data, response, error in
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

            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
