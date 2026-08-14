// NetworkDiagnostics.swift - FIXED
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
    private var dataTask: URLSessionDataTask?
    private var startTime = Date()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return property(forKey: handledKey, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        startTime = Date()
        let url = request.url?.absoluteString ?? "<unknown>"
        let method = request.httpMethod ?? "GET"
        let bodyBytes = request.httpBody?.count ?? 0
        NetworkDiagnostics.logTask("→ \(method) \(url) body=\(bodyBytes)b")

        // Create a mutable copy manually instead of using mutableCopy()
        var forwarded = request

        // Check if this is a file upload or large body that we shouldn't intercept
        if let body = request.httpBody, body.count > 1024 * 1024 {
            NetworkDiagnostics.logTask("⚠️ \(method) \(url) large body (\(body.count) bytes) - skipping diagnostics", level: .warning)
            // Forward the original request without diagnostics for large bodies
            let originalRequest = request
            let task = URLSession.shared.dataTask(with: originalRequest) { [weak self] data, response, error in
                guard let self = self else { return }
                let elapsed = Int(Date().timeIntervalSince(self.startTime) * 1000)

                if let error = error {
                    NetworkDiagnostics.logTask("✖ \(method) \(url) FAILED after \(elapsed)ms: \(error.localizedDescription)", level: .error)
                    self.client?.urlProtocol(self, didFailWithError: error)
                    return
                }

                if let http = response as? HTTPURLResponse {
                    let level: LogLevel = (200..<400).contains(http.statusCode) ? .diagnostic : .warning
                    NetworkDiagnostics.logTask("← \(http.statusCode) \(method) \(url) \(elapsed)ms", level: level)
                }

                if let response = response {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
            task.resume()
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: &forwarded)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        let session = URLSession(configuration: configuration)
        self.session = session

        dataTask = session.dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.startTime) * 1000)
            let bytes = data?.count ?? 0

            if let error = error {
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

            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data {
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

// Extension to allow setting property on URLRequest
extension URLProtocol {
    static func setProperty(_ value: Any, forKey key: String, in request: inout URLRequest) {
        // Create a mutable copy of the request using NSMutableURLRequest
        if let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
            URLProtocol.setProperty(value, forKey: key, in: mutableRequest)
            request = mutableRequest as URLRequest
        }
    }
}