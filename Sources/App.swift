import AppKit
import SwiftUI
import ServiceManagement
import SystemConfiguration
import Network
import CoreImage.CIFilterBuiltins

final class AppModel: ObservableObject {
    let pairing = PairingManager()
    let input = InputController()
    lazy var server = RemoteServer(pairing: pairing, input: input, webRoot: Bundle.main.resourceURL!.appendingPathComponent("Web"))
    @Published var url = ""
    @Published var addresses: [String] = []
    @Published var status = "Iniciando…"
    @Published var connected = "Ninguno"
    @Published var permitted = false
    @Published var devices: [Device] = []
    @Published var pin = ""
    @Published var remaining = 0
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var error = ""
    var timer: Timer?
    private var ticks = 0
    let monitor = NWPathMonitor()
    func start() {
        pairing.changed = { [weak self] in self?.refresh() }
        server.onChange = { [weak self] in self?.refresh() }
        networkChanged(); server.start(); refresh()
        monitor.pathUpdateHandler = { [weak self] _ in DispatchQueue.main.async { self?.networkChanged(); self?.server.start() } }; monitor.start(queue: DispatchQueue(label: "network-monitor"))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.refresh(); self.ticks += 1
            if self.ticks % 5 == 0 { self.networkChanged(); self.server.start() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.server.disconnect() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.server.disconnect() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.networkChanged(); self?.server.start() }
    }
    func networkChanged() {
        let local = (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
        url = "http://\(local).local:\(server.port)"
        var found: [String] = []; var pointer: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&pointer) == 0 {
            var item = pointer
            while let current = item {
                let interface = current.pointee
                if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), interface.ifa_flags & UInt32(IFF_UP) != 0, interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0, String(cString: interface.ifa_name).hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { found.append(String(cString:host)) }
                }; item = interface.ifa_next
            }; freeifaddrs(pointer)
        }
        addresses = found.sorted().map { "http://\($0):\(server.port)" }
        server.hosts = Set((["localhost", "127.0.0.1", "\(local).local"] + found).map { "\($0.lowercased()):\(server.port)" })
    }
    func refresh() {
        status = server.status; connected = server.clients.values.compactMap { $0.device?.name }.joined(separator: ", "); if connected.isEmpty { connected = "Ninguno" }
        permitted = input.permitted; devices = pairing.devices; remaining = max(0,Int(pairing.expires.timeIntervalSinceNow)); pin = remaining > 0 ? pairing.pin : "------"
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refresh() } catch { self.error = "Inicio automático: \(error.localizedDescription). Coloca primero la app en Aplicaciones." }
    }
    func revoke(_ id: String?) { do { try pairing.revoke(id); server.revoked(); refresh() } catch { self.error = error.localizedDescription } }
    func qr(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX:8,y:8)), let cg = CIContext().createCGImage(output, from:output.extent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:220,height:220))
    }
}
struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var useIP = false
    var connectionURL: String { useIP ? model.addresses.first ?? model.url : model.url }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:18) {
                HStack { Image(systemName:"computermouse.fill").font(.largeTitle); VStack(alignment:.leading) { Text("iPhone Remote").font(.title.bold()); Text("Tu iPhone, el trackpad de tu Mac").foregroundColor(.secondary) } }
                HStack { Label(model.status,systemImage:"network"); Spacer(); Text(model.connected).foregroundColor(.secondary) }
                GroupBox {
                    VStack(alignment:.leading,spacing:10) {
                        Text(model.permitted ? "Accesibilidad: ✓ Permitido" : "Accesibilidad: ⚠ Requerido").font(.headline)
                        Text("Autoriza esta app para mover el cursor e introducir texto. No se captura ni transmite la pantalla.")
                        if !model.permitted { Button("Abrir ajustes de Accesibilidad") { model.input.requestPermission() } }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
                }
                GroupBox("Conectar el iPhone") {
                    HStack(alignment:.top,spacing:20) {
                        if let image = model.qr(connectionURL) { Image(nsImage:image).interpolation(.none).resizable().frame(width:190,height:190).padding(8).background(Color.white).cornerRadius(10) }
                        VStack(alignment:.leading,spacing:12) {
                            Text("1. Conecta el iPhone al Wi-Fi de la misma red que el Ethernet del Mac.\n2. Escanea el QR con Cámara y abre Safari.\n3. Introduce este PIN.")
                            Text(model.pin).font(.system(size:32,weight:.medium,design:.monospaced)).textSelection(.enabled)
                            Text(model.remaining > 0 ? "Caduca en \(model.remaining) s · un solo uso" : "PIN caducado o utilizado").font(.caption).foregroundColor(.secondary)
                            Button("Generar nuevo PIN") { model.pairing.begin() }
                        }
                    }.padding(8)
                    Toggle("Usar IP como respaldo en el QR",isOn:$useIP)
                    Text(connectionURL).font(.system(.body,design:.monospaced)).textSelection(.enabled)
                    Button("Copiar dirección") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(connectionURL,forType:.string) }
                    Text("Safari → Compartir → Añadir a pantalla de inicio. Usa la dirección .local para conservar la conexión cuando cambie la IP.").font(.caption).foregroundColor(.secondary).padding(.top,6)
                }
                GroupBox("Configuración") {
                    VStack(alignment:.leading,spacing:10) {
                        Toggle("Iniciar al iniciar sesión",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
                        if model.loginNeedsApproval { Button("Aprobar inicio en Ajustes del Sistema") { SMAppService.openSystemSettingsLoginItems() } }
                        Text("Actívalo después de colocar iPhone Remote.app en Aplicaciones.").font(.caption).foregroundColor(.secondary)
                        ForEach(model.addresses,id:\.self) { Text($0).textSelection(.enabled).font(.caption.monospaced()) }
                        Text("Servidor HTTP local: utiliza una red de confianza; el tráfico no está cifrado.").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
                }
                GroupBox("Dispositivos autorizados") {
                    VStack(alignment:.leading,spacing:10) {
                        if model.devices.isEmpty { Text("Ninguno. Empareja tu iPhone con el PIN.").foregroundColor(.secondary) }
                        ForEach(model.devices) { device in HStack { Text(device.name); Spacer(); Button("Revocar") { model.revoke(device.id) } } }
                        HStack { Button("Desconectar dispositivos") { model.server.disconnect() }; Button("Revocar todos") { model.revoke(nil) } }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
                }
                if !model.error.isEmpty { Text(model.error).foregroundColor(.red).textSelection(.enabled) }
            }.padding(24)
        }.frame(width:640,height:760)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    var statusItem: NSStatusItem!
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName:"computermouse",accessibilityDescription:"iPhone Remote")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        model.start()
        if !UserDefaults.standard.bool(forKey:"didLaunch") { UserDefaults.standard.set(true,forKey:"didLaunch"); showSetup() }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refresh(); menu.removeAllItems()
        func add(_ title: String,_ action: Selector? = nil) { let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item) }
        add("iPhone Remote"); add("Estado: \(model.status)"); add("Dispositivo conectado: \(model.connected)"); add(model.permitted ? "Accesibilidad: ✓ Permitido" : "Accesibilidad: ⚠ Requerido",#selector(accessibility))
        menu.addItem(.separator()); add("Abrir control",#selector(openControl)); add("Mostrar código QR",#selector(showSetup)); add("Dirección de conexión: \(model.url)",#selector(copyAddress))
        add("Iniciar al iniciar sesión",#selector(toggleLogin)); menu.items.last?.state = model.loginEnabled ? .on : .off
        add("Desconectar dispositivos",#selector(disconnect)); add("Dispositivos autorizados",#selector(showSettings)); add("Configuración",#selector(showSettings)); menu.addItem(.separator()); add("Salir",#selector(quit))
    }
    @objc func showSetup() { model.pairing.begin(); showSettings() }
    @objc func showSettings() {
        if window == nil { let window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:760),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false); window.title = "iPhone Remote"; window.contentView = NSHostingView(rootView:SetupView(model:model)); window.isReleasedWhenClosed = false; window.center(); self.window = window }
        NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
    @objc func accessibility() { model.input.requestPermission() }
    @objc func openControl() { if let url = URL(string:model.url) { NSWorkspace.shared.open(url) } }
    @objc func copyAddress() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.url,forType:.string) }
    @objc func toggleLogin() { model.setLogin(!model.loginEnabled); if !model.error.isEmpty { showSettings() } }
    @objc func disconnect() { model.server.disconnect() }
    @objc func quit() { model.server.disconnect(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.server.disconnect() }
}
@main struct Main {
    static func main() { let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
}
