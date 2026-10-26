import Foundation
import Security
import CryptoKit

struct Device: Codable, Identifiable {
    let id: String
    let name: String
    let digest: String
    let created: Date
}
final class PairingManager {
    private(set) var devices: [Device] = []
    private(set) var pin = ""
    private(set) var expires = Date.distantPast
    private var attempts = 0
    private var blockedUntil = Date.distantPast
    private let service: String
    var changed: (() -> Void)?
    init(service: String = "local.iphoneremote.devices") {
        self.service = service
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            devices = (try? JSONDecoder().decode([Device].self, from: data)) ?? []
        }
    }
    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "authorized-devices"]
    }
    private func save() throws {
        let data = try JSONEncoder().encode(devices)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw Failure.message("No se pudo guardar el dispositivo en el Llavero.") }
        } else if status != errSecSuccess { throw Failure.message("Llavero no disponible (\(status)).") }
        changed?()
    }
    func begin() {
        guard Date() >= blockedUntil else { return }
        pin = String(format: "%06d", Int.random(in: 0...999999))
        expires = Date().addingTimeInterval(120)
        changed?()
    }
    func pair(_ candidate: String, name: String) throws -> (String, Device) {
        guard Date() >= blockedUntil else { throw Failure.message("Demasiados intentos. Espera 5 minutos.") }
        guard Date() < expires, !pin.isEmpty else { throw Failure.message("Abre Mostrar código QR en el Mac para generar un PIN.") }
        guard candidate == pin else {
            attempts += 1
            if attempts >= 5 { blockedUntil = Date().addingTimeInterval(300); expires = .distantPast; attempts = 0; changed?() }
            throw Failure.message("PIN incorrecto.")
        }
        guard devices.count < 20 else { throw Failure.message("Revoca un dispositivo antes de añadir otro.") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.message("No se pudo generar una credencial segura.") }
        let token = Data(bytes).base64EncodedString()
        let device = Device(id: UUID().uuidString, name: String(name.prefix(60)), digest: hash(token), created: Date())
        devices.append(device)
        do { try save() } catch { devices.removeLast(); throw error }
        expires = .distantPast; pin = ""; attempts = 0; changed?()
        return (token, device)
    }
    func authenticate(_ token: String) -> Device? {
        guard token.utf8.count < 128 else { return nil }
        let digest = hash(token)
        return devices.first { constantEqual($0.digest, digest) }
    }
    func revoke(_ id: String?) throws {
        let previous = devices
        devices.removeAll { id == nil || $0.id == id }
        do { try save() } catch { devices = previous; throw error }
    }
    private func hash(_ token: String) -> String { SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func constantEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x,y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
