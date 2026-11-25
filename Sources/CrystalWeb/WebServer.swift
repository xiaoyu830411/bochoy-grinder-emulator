import Foundation
import Network
import CrystalCore

private struct ControlEnvelope: Encodable {
    let ok: Bool
    let message: String
    let attStatus: UInt8?
    let faultID: String?
    let snapshot: SimulatorSnapshot
}

private struct MessageEnvelope: Encodable {
    let ok: Bool
    let message: String
}

public final class WebServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.bocai.crystal-web.network")
    private let endpoint: WebEndpoint
    private let security: WebSecurityPolicy
    private let eventHub: WebEventHub
    private let snapshotProvider: @MainActor @Sendable () -> SimulatorSnapshot
    private let controlHandler: @MainActor @Sendable (ControlCommand) -> ControlResult
    private let onReady: @Sendable (String) -> Void
    private let onFailure: @Sendable (String) -> Void
    private var listener: NWListener?
    private var connections: [UUID: WebClientConnection] = [:]

    public init(
        endpoint: WebEndpoint,
        token: String?,
        eventHub: WebEventHub,
        snapshotProvider: @escaping @MainActor @Sendable () -> SimulatorSnapshot,
        controlHandler: @escaping @MainActor @Sendable (ControlCommand) -> ControlResult,
        onReady: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.endpoint = endpoint
        security = WebSecurityPolicy(bindHost: endpoint.host, token: token)
        self.eventHub = eventHub
        self.snapshotProvider = snapshotProvider
        self.controlHandler = controlHandler
        self.onReady = onReady
        self.onFailure = onFailure
    }

    public func start() {
        queue.async { [self] in
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(
                    host: NWEndpoint.Host(endpoint.host),
                    port: NWEndpoint.Port(rawValue: endpoint.port)!
                )
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [onReady, onFailure, endpoint] state in
                    switch state {
                    case .ready:
                        onReady(endpoint.description)
                    case .failed(let error):
                        onFailure(error.localizedDescription)
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] networkConnection in
                    guard let self else { return }
                    let id = UUID()
                    let client = WebClientConnection(
                        id: id,
                        connection: networkConnection,
                        queue: self.queue,
                        security: self.security,
                        eventHub: self.eventHub,
                        snapshotProvider: self.snapshotProvider,
                        controlHandler: self.controlHandler,
                        onClose: { [weak self] in self?.connections.removeValue(forKey: id) }
                    )
                    self.connections[id] = client
                    client.start()
                }
                listener.start(queue: queue)
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }
}

private final class WebClientConnection: @unchecked Sendable {
    private enum Mode {
        case receiving
        case response
        case events
    }

    private let id: UUID
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let security: WebSecurityPolicy
    private let eventHub: WebEventHub
    private let snapshotProvider: @MainActor @Sendable () -> SimulatorSnapshot
    private let controlHandler: @MainActor @Sendable (ControlCommand) -> ControlResult
    private let onClose: @Sendable () -> Void

    private var buffer = Data()
    private var mode = Mode.receiving
    private var closed = false
    private var closeAfterFlush = false
    private var sending = false
    private var outgoing = BoundedSendQueue(maximumBytes: 1_048_576)
    private var subscriptionID: UUID?
    private var heartbeat: DispatchSourceTimer?
    private var requestTimeout: DispatchWorkItem?

    init(
        id: UUID,
        connection: NWConnection,
        queue: DispatchQueue,
        security: WebSecurityPolicy,
        eventHub: WebEventHub,
        snapshotProvider: @escaping @MainActor @Sendable () -> SimulatorSnapshot,
        controlHandler: @escaping @MainActor @Sendable (ControlCommand) -> ControlResult,
        onClose: @escaping @Sendable () -> Void
    ) {
        self.id = id
        self.connection = connection
        self.queue = queue
        self.security = security
        self.eventHub = eventHub
        self.snapshotProvider = snapshotProvider
        self.controlHandler = controlHandler
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
        }
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .receiving else { return }
            self.close()
        }
        requestTimeout = timeout
        queue.asyncAfter(deadline: .now() + 10, execute: timeout)
        receive()
    }

    private func receive() {
        guard !closed, mode == .receiving else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let error {
                _ = error
                self.close()
                return
            }
            if let data { self.buffer.append(data) }
            do {
                if let request = try HTTPRequestParser.parse(self.buffer) {
                    self.mode = .response
                    self.requestTimeout?.cancel()
                    self.route(request)
                } else if complete {
                    self.close()
                } else {
                    self.receive()
                }
            } catch let error as HTTPParseError {
                self.mode = .response
                self.requestTimeout?.cancel()
                self.sendMessage(status: error.status, message: error.message)
            } catch {
                self.mode = .response
                self.requestTimeout?.cancel()
                self.sendMessage(status: 400, message: "Malformed HTTP request")
            }
        }
    }

    private func route(_ request: HTTPRequest) {
        do {
            if ["/", "/index.html", "/app.js", "/sim-client.js", "/styles.css"].contains(request.path) {
                try security.validate(request: request, requiresAuthentication: false)
                guard request.method == "GET" else {
                    sendMessage(status: 405, message: "Method Not Allowed")
                    return
                }
                guard let asset = WebAssets.asset(forPath: request.path) else {
                    sendMessage(status: 404, message: "Web asset unavailable")
                    return
                }
                send(status: 200, contentType: asset.contentType, body: asset.data)
                return
            }

            if request.path == "/api/events" {
                try security.validate(request: request, allowsQueryToken: true)
                guard request.method == "GET" else {
                    sendMessage(status: 405, message: "Method Not Allowed")
                    return
                }
                try beginEvents(lastEventIDText: request.header("last-event-id"))
                return
            }

            if request.path == "/api/snapshot" || request.path == "/api/control" {
                try security.validate(request: request)
                if request.path == "/api/snapshot" {
                    guard request.method == "GET" else {
                        sendMessage(status: 405, message: "Method Not Allowed")
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snapshot = self.snapshotProvider()
                        self.queue.async { self.sendJSON(status: 200, value: snapshot) }
                    }
                } else {
                    guard request.method == "POST" else {
                        sendMessage(status: 405, message: "Method Not Allowed")
                        return
                    }
                    let command = try ControlRequest.decode(request.body)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let result = self.controlHandler(command)
                        let snapshot = self.snapshotProvider()
                        self.queue.async {
                            self.sendJSON(
                                status: result.httpStatus,
                                value: ControlEnvelope(
                                    ok: result.ok,
                                    message: result.message,
                                    attStatus: result.attStatus,
                                    faultID: result.faultID,
                                    snapshot: snapshot
                                )
                            )
                        }
                    }
                }
                return
            }

            try security.validate(request: request, requiresAuthentication: false)
            sendMessage(status: 404, message: "Not Found")
        } catch let error as WebSecurityError {
            sendMessage(status: error.status, message: error.message)
        } catch let error as ControlValidationError {
            sendMessage(status: 400, message: error.message)
        } catch let error as HTTPParseError {
            sendMessage(status: error.status, message: error.message)
        } catch {
            sendMessage(status: 400, message: "Invalid request")
        }
    }

    private func beginEvents(lastEventIDText: String?) throws {
        let lastEventID: UInt64?
        if let lastEventIDText, !lastEventIDText.isEmpty {
            guard let parsed = UInt64(lastEventIDText) else {
                throw HTTPParseError(status: 400, message: "Invalid Last-Event-ID")
            }
            lastEventID = parsed
        } else {
            lastEventID = nil
        }
        mode = .events
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream; charset=utf-8\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        X-Content-Type-Options: nosniff\r
        \r

        """
        enqueue(Data(headers.utf8), closeAfter: false)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.enqueue(Data(SSEFrame.heartbeat.utf8), closeAfter: false)
        }
        heartbeat = timer
        timer.resume()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let subscriptionID = self.eventHub.subscribe(lastEventID: lastEventID) { [weak self] data in
                guard let self else { return }
                self.queue.async { self.enqueue(data, closeAfter: false) }
            }
            self.queue.async {
                guard !self.closed else {
                    Task { @MainActor in self.eventHub.unsubscribe(subscriptionID) }
                    return
                }
                self.subscriptionID = subscriptionID
            }
        }
    }

    private func sendMessage(status: Int, message: String) {
        sendJSON(status: status, value: MessageEnvelope(ok: false, message: message))
    }

    private func sendJSON<T: Encodable>(status: Int, value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(value)
            send(status: status, contentType: "application/json; charset=utf-8", body: body)
        } catch {
            sendMessage(status: 500, message: "JSON encoding failed")
        }
    }

    private func send(status: Int, contentType: String, body: Data) {
        let headers = """
        HTTP/1.1 \(status) \(Self.reason(status))\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        X-Content-Type-Options: nosniff\r
        \r

        """
        var response = Data(headers.utf8)
        response.append(body)
        enqueue(response, closeAfter: true)
    }

    private func enqueue(_ data: Data, closeAfter: Bool) {
        guard !closed else { return }
        if closeAfter { closeAfterFlush = true }
        guard outgoing.enqueue(data) else {
            close()
            return
        }
        flush()
    }

    private func flush() {
        guard !closed, !sending else { return }
        let chunks = outgoing.drain()
        guard !chunks.isEmpty else {
            if closeAfterFlush { close() }
            return
        }
        let data = chunks.reduce(into: Data()) { $0.append($1) }
        sending = true
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.sending = false
            if error != nil {
                self.close()
            } else {
                self.flush()
            }
        })
    }

    private func close() {
        guard !closed else { return }
        closed = true
        requestTimeout?.cancel()
        heartbeat?.cancel()
        connection.stateUpdateHandler = nil
        connection.cancel()
        if let subscriptionID {
            Task { @MainActor [eventHub] in eventHub.unsubscribe(subscriptionID) }
        }
        onClose()
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Content Too Large"
        case 422: return "Unprocessable Content"
        case 431: return "Request Header Fields Too Large"
        default: return "Error"
        }
    }
}
