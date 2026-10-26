# Validación — 16 de septiembre de 2026

Entorno: macOS 14.8.9 (23J631), Intel x86_64, Swift 5.8.1, SDK macOS 13.3, Command Line Tools. Xcode completo no instalado.

## Resultado observado

- Compilación optimizada de los cuatro archivos Swift: correcta.
- App autocontenida generada en `build/iPhone Remote.app` (aproximadamente 580 KiB).
- Firma ad hoc: `codesign --verify --deep --strict` correcta.
- Dependencias dinámicas inspeccionadas con `otool -L`: únicamente frameworks/librerías del sistema y runtime Swift de macOS. Sin Python, Node ni Homebrew.
- `Info.plist` y `project.pbxproj`: `plutil -lint` correcto.
- JavaScript del cliente: comprobación sintáctica correcta.
- Harness Swift: bloqueo tras cinco PIN incorrectos, regeneración sin evadir bloqueo, persistencia en Llavero y revocación verificadas con una entrada temporal aislada.
- Integración: **28 comprobaciones pasaron**, incluyendo WebSocket real sobre TCP.
- Interfaz en Chrome headless a 393 × 852: **15 comprobaciones pasaron**. Gestos, clic simple/doble, arrastre equilibrado, scroll, Unicode, composición, backspace y modificadores. Sin excepciones JS. Captura en `build/iphone-preview.png`.
- La prueba de interfaz detectó y permitió corregir un primer toque identificado incorrectamente como doble toque durante los primeros 280 ms desde la carga.
- App final abierta mediante Launch Services: proceso escuchando en TCP 8765.
- Petición a `http://mac.local:8765/`: **HTTP 200**. El contenido servido coincide byte por byte con `Resources/Web/index.html`.

## No verificado en hardware

No se simularon eventos nativos sobre aplicaciones del usuario. Quedan pendientes la concesión manual de Accesibilidad, control real desde Safari/iPhone, latencia percibida en la LAN, volumen de la salida seleccionada y arranque tras cerrar/iniciar sesión. La configuración de SMAppService está implementada, pero no se activó automáticamente por el usuario. Tampoco se realizó una compilación dentro de Xcode ni notarización.

Las pruebas del navegador usan WebSocket simulado para no controlar el Mac. Las pruebas de integración usan el servidor Swift real y una credencial independiente. Ninguna prueba equivale a una prueba física de Safari iOS.
