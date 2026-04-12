#!/usr/bin/env swift
import AppKit

/// Renders a single 1024×1024 master PNG for macOS AppIcon (Coolify / deploy / branch motif).
func renderMaster() -> NSImage {
    let s: CGFloat = 1024
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let outer = NSRect(x: 0, y: 0, width: s, height: s)
    let inset: CGFloat = s * 0.11
    let plate = outer.insetBy(dx: inset, dy: inset)
    let corner = s * 0.22

    NSGraphicsContext.current?.imageInterpolation = .high

    // Plate shadow
    NSColor.black.withAlphaComponent(0.28).setFill()
    let shadowOffset: CGFloat = s * 0.018
    let shadowPlate = plate.offsetBy(dx: 0, dy: -shadowOffset)
    NSBezierPath(roundedRect: shadowPlate, xRadius: corner, yRadius: corner).fill()

    // Gradient plate (Coolify-adjacent blues / teal)
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.06, green: 0.52, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.42, alpha: 1),
        ],
        atLocations: [0, 0.55, 1],
        colorSpace: NSColorSpace.genericRGB
    )!
    let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)
    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    gradient.draw(in: plate, angle: 128)
    NSGraphicsContext.restoreGraphicsState()

    // Inner gloss (subtle)
    let gloss = NSBezierPath(roundedRect: plate.insetBy(dx: s * 0.02, dy: s * 0.02), xRadius: corner * 0.92, yRadius: corner * 0.92)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    gloss.lineWidth = s * 0.006
    gloss.stroke()

    // Branch + deploy chevron (vector paths, centered)
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSColor.white.withAlphaComponent(0.95).setStroke()

    let cx = s / 2
    let cy = s / 2 + s * 0.02
    let scale = s / 1024

    // Git-like branch: vertical bar + two arcs
    let lineW = 52 * scale
    let path = NSBezierPath()
    path.lineWidth = lineW
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    // main stem
    path.move(to: NSPoint(x: cx, y: cy - 140 * scale))
    path.line(to: NSPoint(x: cx, y: cy + 120 * scale))

    // left branch up
    path.move(to: NSPoint(x: cx, y: cy - 20 * scale))
    path.curve(
        to: NSPoint(x: cx - 150 * scale, y: cy - 130 * scale),
        controlPoint1: NSPoint(x: cx - 40 * scale, y: cy - 40 * scale),
        controlPoint2: NSPoint(x: cx - 130 * scale, y: cy - 110 * scale)
    )

    // right branch down
    path.move(to: NSPoint(x: cx, y: cy + 40 * scale))
    path.curve(
        to: NSPoint(x: cx + 155 * scale, y: cy + 145 * scale),
        controlPoint1: NSPoint(x: cx + 45 * scale, y: cy + 70 * scale),
        controlPoint2: NSPoint(x: cx + 120 * scale, y: cy + 130 * scale)
    )

    path.stroke()

    // Small rocket / deploy triangle on top-right of stem
    let tri = NSBezierPath()
    let tx = cx + 95 * scale
    let ty = cy - 95 * scale
    tri.move(to: NSPoint(x: tx, y: ty + 55 * scale))
    tri.line(to: NSPoint(x: tx + 70 * scale, y: ty))
    tri.line(to: NSPoint(x: tx, y: ty - 55 * scale))
    tri.close()
    NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.85, alpha: 1).setFill()
    tri.fill()

    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        fputs("Failed to get bitmap representation.\n", stderr)
        exit(1)
    }
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG.\n", stderr)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    do {
        try data.write(to: url)
    } catch {
        fputs("Write error: \(error)\n", stderr)
        exit(1)
    }
}

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon_1024.png"
let master = renderMaster()
writePNG(master, path: out)
print("Wrote \(out)")
