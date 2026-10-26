import AppKit
let root = CommandLine.arguments[1]
func draw(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor(calibratedRed:0.065,green:0.075,blue:0.105,alpha:1).setFill()
    NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
    let s = CGFloat(size)
    let pad = NSBezierPath(roundedRect:NSRect(x:s*0.22,y:s*0.18,width:s*0.56,height:s*0.64),xRadius:s*0.11,yRadius:s*0.11)
    NSColor(calibratedRed:0.63,green:0.73,blue:1,alpha:1).setStroke();pad.lineWidth=s*0.035;pad.stroke()
    let line = NSBezierPath();line.move(to:NSPoint(x:s*0.5,y:s*0.64));line.line(to:NSPoint(x:s*0.5,y:s*0.73));line.lineWidth=s*0.03;line.lineCapStyle = .round;line.stroke()
    let arrow=NSBezierPath();arrow.move(to:NSPoint(x:s*0.41,y:s*0.36));arrow.line(to:NSPoint(x:s*0.59,y:s*0.54));arrow.move(to:NSPoint(x:s*0.43,y:s*0.54));arrow.line(to:NSPoint(x:s*0.59,y:s*0.54));arrow.line(to:NSPoint(x:s*0.59,y:s*0.38));arrow.lineWidth=s*0.032;arrow.lineJoinStyle = .round;arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
let fm=FileManager.default
for (name,size) in [("icon-192.png",192),("icon-512.png",512),("apple-touch-icon.png",180)] { try draw(size).write(to:URL(fileURLWithPath:root+"/Resources/Web/icons/"+name)) }
let dir=root+"/build/AppIcon.iconset"
try fm.createDirectory(atPath:dir,withIntermediateDirectories:true)
for size in [16,32,128,256,512] { try draw(size).write(to:URL(fileURLWithPath:dir+"/icon_\(size)x\(size).png")); try draw(size*2).write(to:URL(fileURLWithPath:dir+"/icon_\(size)x\(size)@2x.png")) }
