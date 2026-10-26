import Foundation
import Security
@main struct Harness {
    static func main() throws {
        let service = "local.iphoneremote.tests.\(UUID().uuidString)"
        let pairing = PairingManager(service:service)
        // Verify rate limiting and persistent revocation against an isolated Keychain item.
        pairing.begin()
        let originalPIN = pairing.pin
        for _ in 0..<5 { do { _ = try pairing.pair("invalid",name:"Test"); fatalError("Wrong PIN accepted") } catch {} }
        do { _ = try pairing.pair(originalPIN,name:"Test"); fatalError("Lockout bypassed") } catch {}
        pairing.begin()
        assert(pairing.expires < Date(), "Regenerating PIN must not bypass lockout")
        let persistence = PairingManager(service:service)
        persistence.begin()
        let (testToken,device) = try persistence.pair(persistence.pin,name:"Persistence test")
        let restored = PairingManager(service:service)
        assert(restored.authenticate(testToken)?.id == device.id)
        try restored.revoke(device.id)
        assert(PairingManager(service:service).authenticate(testToken) == nil)
        print("PASS Native PIN lockout, Keychain persistence and revocation")
        let freshPairing = PairingManager(service:service)
        let input = InputController()
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let server = RemoteServer(pairing:freshPairing,input:input,webRoot:root.appendingPathComponent("Resources/Web"))
        server.hosts = ["127.0.0.1:8765","localhost:8765"]
        freshPairing.begin()
        // A transient fixture communicates only the temporary test PIN, never production credentials.
        try freshPairing.pin.write(to:root.appendingPathComponent("build/test-pin"),atomically:true,encoding:.utf8)
        signal(SIGTERM,SIG_IGN)
        let source=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
        source.setEventHandler { server.disconnect(); SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service] as [String:Any] as CFDictionary); exit(0) };source.resume()
        server.start()
        withExtendedLifetime((server,source)) { RunLoop.main.run() }
    }
}
