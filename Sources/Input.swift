import AppKit
import ApplicationServices
import CoreAudio

final class InputController {
    private var dragging = false
    private var held = Set<CGKeyCode>()
    private var lastInput = Date()
    private var watchdog: Timer?
    var permitted: Bool { AXIsProcessTrusted() }
    init() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastInput) > 3 { self.releaseAll() }
        }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func releaseAll() {
        if dragging { mouse(.leftMouseUp); dragging = false }
        for key in held { CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap) }
        held.removeAll()
    }
    private func mouse(_ type: CGEventType, clicks: Int64 = 1) {
        guard let point = CGEvent(source: nil)?.location else { return }
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: type == .rightMouseDown || type == .rightMouseUp ? .right : .left)
        e?.setIntegerValueField(.mouseEventClickState, value: clicks)
        e?.post(tap: .cghidEventTap)
    }
    private func flags(_ names: [String]) -> CGEventFlags {
        names.reduce(CGEventFlags()) { result, name in
            var result = result
            switch name { case "meta": result.insert(.maskCommand); case "ctrl": result.insert(.maskControl); case "alt": result.insert(.maskAlternate); case "shift": result.insert(.maskShift); default: break }
            return result
        }
    }
    static let keyCodes: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"enter":36,"l":37,"j":38,"\u{0027}":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"tab":48,"space":49,"`":50,"delete":51,"esc":53,"left":123,"right":124,"down":125,"up":126]
    func handle(_ object: [String: Any]) throws {
        guard let type = object["type"] as? String else { return }
        if type == "release_all" { releaseAll(); return }
        if type == "heartbeat" { lastInput = Date(); return }
        guard permitted else { throw Failure.message("Accesibilidad requerida en el Mac.") }
        lastInput = Date()
        let modifiers = flags(object["modifiers"] as? [String] ?? [])
        func number(_ key: String, limit: Double = 400) -> Double { let v = (object[key] as? NSNumber)?.doubleValue ?? 0; return v.isFinite ? max(-limit,min(limit,v)) : 0 }
        switch type {
        case "mouse_move":
            guard var p = CGEvent(source: nil)?.location else { return }
            p.x += number("dx"); p.y += number("dy")
            var displays = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
            CGGetActiveDisplayList(32, &displays, &count)
            let rects = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
            if !rects.contains(where: { $0.contains(p) }), let nearest = rects.map({ r -> CGPoint in CGPoint(x: max(r.minX,min(r.maxX-1,p.x)), y: max(r.minY,min(r.maxY-1,p.y))) }).min(by: { hypot($0.x-p.x,$0.y-p.y) < hypot($1.x-p.x,$1.y-p.y) }) { p = nearest }
            let e = CGEvent(mouseEventSource: nil, mouseType: dragging ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
            e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(number("dx")))
            e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(number("dy")))
            e?.post(tap: .cghidEventTap)
        case "mouse_down": if !dragging { dragging = true; mouse(.leftMouseDown) }
        case "mouse_up": if dragging { mouse(.leftMouseUp); dragging = false }
        case "left_click", "right_click", "double_click":
            let right = type == "right_click"
            for n in 1...(type == "double_click" ? 2 : 1) { mouse(right ? .rightMouseDown : .leftMouseDown, clicks: Int64(n)); mouse(right ? .rightMouseUp : .leftMouseUp, clicks: Int64(n)) }
        case "scroll": CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(number("dy")), wheel2: Int32(number("dx")), wheel3: 0)?.post(tap: .cghidEventTap)
        case "key_down", "key_up", "key_press":
            guard let name = object["key"] as? String, let code = Self.keyCodes[name.lowercased()] else { return }
            let states = type == "key_press" ? [true,false] : [type == "key_down"]
            for down in states { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down); e?.flags = modifiers; e?.post(tap: .cghidEventTap); if down { held.insert(code) } else { held.remove(code) } }
        case "text_input":
            guard let text = object["text"] as? String, text.utf16.count <= 2048 else { return }
            // Iterate extended graphemes so neither surrogate pairs nor combining accents are split.
            for character in text {
                let units = Array(String(character).utf16)
                for down in [true,false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down); units.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }; e?.post(tap: .cghidEventTap) }
            }
        case "media_command": try volume(object["command"] as? String ?? "")
        case "heartbeat": break
        default: break
        }
    }
    private func volume(_ command: String) throws {
        var device = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { throw Failure.message("No hay salida de audio disponible.") }
        let mute = command == "mute"
        guard mute || command == "volume_up" || command == "volume_down" else { throw Failure.message("Reproducción multimedia global no disponible mediante una API pública estable.") }
        address = AudioObjectPropertyAddress(mSelector: mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var writable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address), AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue else { throw Failure.message("Esta salida de audio no permite ajustar volumen por software.") }
        var status: OSStatus
        if mute { var value: UInt32 = 0; size = 4; status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value); guard status == noErr else { throw Failure.message("No se pudo leer el volumen.") }; value = value == 0 ? 1 : 0; status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) }
        else { var value: Float32 = 0; size = 4; status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value); guard status == noErr else { throw Failure.message("No se pudo leer el volumen.") }; value = max(0,min(1,value + (command == "volume_up" ? 0.0625 : -0.0625))); status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) }
        if status != noErr { throw Failure.message("No se pudo ajustar el volumen.") }
    }
}
