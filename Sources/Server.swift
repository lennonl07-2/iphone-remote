import Foundation
import Network
import CryptoKit

// One bounded HTTP/1.1 request per TCP connection; RFC 6455 text frames after upgrade.
// All state is confined to the main queue, including native input delivery.
final class RemoteServer {
    let pairing: PairingManager
    let input: InputController
    var listener: NWListener?
    var clients: [UUID: Peer] = [:]
    var controller: UUID?
    var onChange: (() -> Void)?
    var status = "Iniciando…"
    var hosts: Set<String> = ["localhost", "127.0.0.1"]
    let port: UInt16 = 8765
    let webRoot: URL
    init(pairing: PairingManager, input: InputController, webRoot: URL) { self.pairing = pairing; self.input = input; self.webRoot = webRoot }
    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            parameters.prohibitedInterfaceTypes = [.cellular, .other]
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "iPhone Remote", type: "_iphoneremote._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state { case .ready: self.status = "Activo"; case .failed(let error): self.status = "Error: \(error.localizedDescription)"; self.listener?.cancel(); self.listener = nil; default: break }; self.onChange?()
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self, self.clients.count < 32, Self.isLocal(connection.endpoint) else { connection.cancel(); return }
                let peer = Peer(connection: connection, server: self); self.clients[peer.id] = peer; peer.start()
            }
            listener.start(queue: .main)
        } catch { status = "Error: \(error.localizedDescription)"; onChange?() }
    }
    static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        if case .ipv4(let ip) = host { let b = Array(ip.rawValue); return b[0] == 10 || b[0] == 127 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 169 && b[1] == 254) }
        if case .ipv6(let ip) = host { let b = Array(ip.rawValue); return ip == .loopback || b[0] & 0xfe == 0xfc || (b[0] == 0xfe && b[1] & 0xc0 == 0x80) }
        return false
    }
    func disconnect() { for client in Array(clients.values) { client.close() }; input.releaseAll() }
    func revoked() { for client in Array(clients.values) where client.device != nil && !pairing.devices.contains(where: { $0.id == client.device?.id }) { client.close() } }
}
final class Peer {
    let id = UUID()
    let connection: NWConnection
    unowned let server: RemoteServer
    var device: Device?
    private var buffer = Data()
    private var websocket = false
    private var closed = false
    private var closing = false
    private var timeout: DispatchWorkItem?
    private var count = 0
    private var epoch = Date()
    private var pendingBytes = 0
    init(connection: NWConnection, server: RemoteServer) { self.connection = connection; self.server = server }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.close() }; if case .cancelled = state { self?.close() } }
        connection.start(queue: .main); deadline(10); receive()
    }
    private func deadline(_ seconds: Double) {
        timeout?.cancel(); let job = DispatchWorkItem { [weak self] in self?.close() }; timeout = job; DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: job)
    }
    func close() {
        guard !closed else { return }; closed = true; timeout?.cancel(); connection.cancel()
        server.clients.removeValue(forKey: id)
        if server.controller == id { server.controller = nil; server.input.releaseAll() }
        server.onChange?()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            if let data = data { self.buffer.append(data); if self.buffer.count > 65536 { self.close(); return }; if self.websocket { self.frames() } else { self.http() } }
            if complete || error != nil { self.close() } else if !self.closed { self.receive() }
        }
    }
    private func send(_ data: Data, thenClose: Bool = false) {
        guard !closed, pendingBytes + data.count < 262144 else { close(); return }
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed { [weak self] error in guard let self = self else { return }; self.pendingBytes -= data.count; if thenClose || error != nil { self.close() } })
    }
    private func response(_ code: Int, _ body: Data, mime: String = "application/json") {
        let headers = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src \u{0027}self\u{0027}; script-src \u{0027}self\u{0027}; style-src \u{0027}self\u{0027}; connect-src \u{0027}self\u{0027}; img-src \u{0027}self\u{0027} data:; frame-ancestors \u{0027}none\u{0027}; base-uri \u{0027}none\u{0027}; form-action \u{0027}none\u{0027}\r\n\r\n"
        send(Data(headers.utf8) + body, thenClose: true)
    }
    private func jsonResponse(_ code: Int, _ value: [String: Any]) { response(code, (try? JSONSerialization.data(withJSONObject: value)) ?? Data()) }
    private func http() {
        guard let delimiter = buffer.range(of: Data([13,10,13,10])) else { if buffer.count > 8192 { close() }; return }
        guard delimiter.lowerBound <= 8192, let header = String(data: buffer[..<delimiter.lowerBound], encoding: .utf8) else { close(); return }
        let lines = header.components(separatedBy: "\r\n"); let request = lines[0].split(separator: " ")
        guard request.count == 3, request[2] == "HTTP/1.1" else { close(); return }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() { guard let colon = line.firstIndex(of: ":") else { close(); return }; let key = line[..<colon].lowercased(); guard headers[key] == nil else { close(); return }; headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
        guard headers["transfer-encoding"] == nil, let host = headers["host"], server.hosts.contains(host.lowercased()) else { jsonResponse(403,["error":"Host no permitido"]); return }
        let origin = "http://" + host
        if let supplied = headers["origin"], supplied != origin { jsonResponse(403,["error":"Origen no permitido"]); return }
        guard let length = Int(headers["content-length"] ?? "0"), (0...4096).contains(length) else { close(); return }
        let bodyStart = delimiter.upperBound
        guard buffer.count >= bodyStart + length else { return }
        let body = buffer.subdata(in: bodyStart..<(bodyStart+length)); buffer.removeSubrange(0..<(bodyStart+length))
        let path = String(request[1].split(separator: "?", maxSplits: 1)[0]); let method = String(request[0])
        if path == "/ws", method == "GET" {
            guard headers["origin"] == origin, headers["upgrade"]?.lowercased() == "websocket", headers["connection"]?.lowercased().split(separator: ",").map({$0.trimmingCharacters(in: .whitespaces)}).contains("upgrade") == true, headers["sec-websocket-version"] == "13", let key = headers["sec-websocket-key"], Data(base64Encoded: key)?.count == 16, length == 0 else { jsonResponse(400,["error":"WebSocket inválido"]); return }
            let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
            send(Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(Data(digest).base64EncodedString())\r\n\r\n".utf8)); websocket = true; deadline(5); frames(); return
        }
        if path == "/pair", method == "POST" {
            guard headers["origin"] == origin, headers["content-type"]?.hasPrefix("application/json") == true, let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let pin = value["pin"] as? String else { jsonResponse(400,["error":"Solicitud inválida"]); return }
            do { let (token, _) = try server.pairing.pair(pin, name: value["name"] as? String ?? "iPhone"); jsonResponse(200,["token":token]) } catch { jsonResponse(403,["error":error.localizedDescription]) }; return
        }
        guard method == "GET" else { jsonResponse(405,["error":"Método no permitido"]); return }
        let assets: [String: (String,String)] = ["/":("index.html","text/html; charset=utf-8"),"/index.html":("index.html","text/html; charset=utf-8"),"/styles.css":("styles.css","text/css"),"/app.js":("app.js","text/javascript; charset=utf-8"),"/manifest.json":("manifest.json","application/manifest+json"),"/icons/icon-192.png":("icons/icon-192.png","image/png"),"/icons/icon-512.png":("icons/icon-512.png","image/png"),"/icons/apple-touch-icon.png":("icons/apple-touch-icon.png","image/png")]
        guard let asset = assets[path], let data = try? Data(contentsOf: server.webRoot.appendingPathComponent(asset.0)) else { jsonResponse(404,["error":"No encontrado"]); return }; response(200,data,mime:asset.1)
    }
    private func frames() {
        while !closed && !closing && buffer.count >= 2 {
            let bytes = [UInt8](buffer.prefix(14)); let opcode = bytes[0] & 0x0f
            guard bytes[0] & 0x70 == 0, bytes[0] & 0x80 != 0, bytes[1] & 0x80 != 0, [1,8,9,10].contains(opcode) else { close(); return }
            var length = Int(bytes[1] & 0x7f); var offset = 2
            if length == 127 { close(); return }
            if length == 126 { guard buffer.count >= 4 else { return }; length = Int(bytes[2]) * 256 + Int(bytes[3]); offset = 4 }
            guard length <= 16384, opcode < 8 || length <= 125 else { close(); return }
            guard buffer.count >= offset + 4 + length else { return }
            let mask = Array(buffer[offset..<(offset+4)]); offset += 4
            let payload = Data(buffer[offset..<(offset+length)].enumerated().map { $0.element ^ mask[$0.offset % 4] }); buffer.removeSubrange(0..<(offset+length))
            if opcode == 8 { close(); return }; if opcode == 9 { frame(payload,opcode:10); continue }; if opcode == 10 { continue }
            if Date().timeIntervalSince(epoch) >= 1 { epoch = Date(); count = 0 }; count += 1
            guard count <= 240 else { close(); return }
            guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String:Any], let type = object["type"] as? String else { close(); return }
            if device == nil {
                guard type == "auth", let token = object["token"] as? String, let device = server.pairing.authenticate(token) else { message(["type":"auth_error"]); closeAfterFlush(); return }
                guard server.controller == nil else { message(["type":"busy","message":"Otro dispositivo está controlando el Mac."]); closeAfterFlush(); return }
                self.device = device; server.controller = id; deadline(35); server.onChange?()
                message(["type":"ready","name":Host.current().localizedName ?? "Mac","accessibility":server.input.permitted]); continue
            }
            deadline(35)
            do { try server.input.handle(object); if type == "heartbeat" { message(["type":"status","accessibility":server.input.permitted]) } } catch { message(["type":"error","message":error.localizedDescription]) }
        }
    }
    private func closeAfterFlush() { closing = true; deadline(0.1) }
    private func message(_ value: [String:Any]) { if let data = try? JSONSerialization.data(withJSONObject: value) { frame(data) } }
    private func frame(_ payload: Data, opcode: UInt8 = 1) { var data = Data([0x80 | opcode]); if payload.count < 126 { data.append(UInt8(payload.count)) } else { data.append(contentsOf:[126,UInt8(payload.count >> 8),UInt8(payload.count & 255)]) }; data.append(payload); send(data) }
}
