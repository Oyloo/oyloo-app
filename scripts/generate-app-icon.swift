#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

struct IconSlot {
    let filename: String
    let pixels: Int
}

let slots = [
    IconSlot(filename: "iphone-notification-20@2x.png", pixels: 40),
    IconSlot(filename: "iphone-notification-20@3x.png", pixels: 60),
    IconSlot(filename: "iphone-settings-29@2x.png", pixels: 58),
    IconSlot(filename: "iphone-settings-29@3x.png", pixels: 87),
    IconSlot(filename: "iphone-spotlight-40@2x.png", pixels: 80),
    IconSlot(filename: "iphone-spotlight-40@3x.png", pixels: 120),
    IconSlot(filename: "iphone-app-60@2x.png", pixels: 120),
    IconSlot(filename: "iphone-app-60@3x.png", pixels: 180),
    IconSlot(filename: "ipad-notification-20.png", pixels: 20),
    IconSlot(filename: "ipad-notification-20@2x.png", pixels: 40),
    IconSlot(filename: "ipad-settings-29.png", pixels: 29),
    IconSlot(filename: "ipad-settings-29@2x.png", pixels: 58),
    IconSlot(filename: "ipad-spotlight-40.png", pixels: 40),
    IconSlot(filename: "ipad-spotlight-40@2x.png", pixels: 80),
    IconSlot(filename: "ipad-app-76.png", pixels: 76),
    IconSlot(filename: "ipad-app-76@2x.png", pixels: 152),
    IconSlot(filename: "ipad-pro-83.5@2x.png", pixels: 167),
    IconSlot(filename: "ios-marketing-1024.png", pixels: 1024)
]

let outputDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for slot in slots {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: slot.pixels,
        pixelsHigh: slot.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: Double(slot.pixels) / 1024.0, y: Double(slot.pixels) / 1024.0)
    drawIcon(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [.compressionFactor: 0.95])!
    let output = outputDir.appendingPathComponent(slot.filename)
    try data.write(to: output, options: .atomic)
    try stripAlphaIfImageMagickIsAvailable(output)
}

func drawIcon(in ctx: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.setFillColor(color(0x06111F).cgColor)
    ctx.fill(canvas)

    linearGradient(
        in: ctx,
        rect: canvas,
        colors: [color(0x07131F), color(0x123B82), color(0x0FB7C7)],
        locations: [0.0, 0.55, 1.0],
        start: CGPoint(x: 80, y: 980),
        end: CGPoint(x: 980, y: 40)
    )

    ctx.saveGState()
    ctx.setBlendMode(.screen)
    radialGradient(in: ctx, center: CGPoint(x: 250, y: 775), radius: 390, colors: [color(0x53F2FF, alpha: 0.70), color(0x53F2FF, alpha: 0.0)])
    radialGradient(in: ctx, center: CGPoint(x: 810, y: 235), radius: 460, colors: [color(0x7B61FF, alpha: 0.48), color(0x7B61FF, alpha: 0.0)])
    radialGradient(in: ctx, center: CGPoint(x: 765, y: 815), radius: 310, colors: [color(0xFFFFFF, alpha: 0.34), color(0xFFFFFF, alpha: 0.0)])
    ctx.restoreGState()

    let glassRect = CGRect(x: 112, y: 112, width: 800, height: 800)
    let glassPath = CGPath(roundedRect: glassRect, cornerWidth: 224, cornerHeight: 224, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 46, color: color(0x00112B, alpha: 0.45).cgColor)
    ctx.addPath(glassPath)
    ctx.clip()
    linearGradient(
        in: ctx,
        rect: glassRect,
        colors: [color(0xFFFFFF, alpha: 0.38), color(0xD9FFFF, alpha: 0.10), color(0x083968, alpha: 0.16)],
        locations: [0.0, 0.48, 1.0],
        start: CGPoint(x: 210, y: 870),
        end: CGPoint(x: 820, y: 150)
    )
    ctx.restoreGState()

    ctx.addPath(glassPath)
    ctx.setLineWidth(12)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.50).cgColor)
    ctx.strokePath()

    ctx.addPath(CGPath(roundedRect: glassRect.insetBy(dx: 24, dy: 24), cornerWidth: 198, cornerHeight: 198, transform: nil))
    ctx.setLineWidth(5)
    ctx.setStrokeColor(color(0x71F6FF, alpha: 0.28).cgColor)
    ctx.strokePath()

    let outer = CGRect(x: 238, y: 238, width: 548, height: 548)
    let inner = CGRect(x: 366, y: 366, width: 292, height: 292)
    ctx.saveGState()
    ctx.addEllipse(in: outer)
    ctx.addEllipse(in: inner)
    ctx.clip(using: .evenOdd)
    linearGradient(
        in: ctx,
        rect: outer,
        colors: [color(0xFFFFFF, alpha: 0.76), color(0xBFFFFF, alpha: 0.34), color(0x3D8DFF, alpha: 0.18)],
        locations: [0.0, 0.52, 1.0],
        start: CGPoint(x: 325, y: 775),
        end: CGPoint(x: 735, y: 260)
    )
    ctx.restoreGState()

    ctx.addEllipse(in: outer)
    ctx.setLineWidth(9)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.58).cgColor)
    ctx.strokePath()

    ctx.addEllipse(in: inner)
    ctx.setLineWidth(6)
    ctx.setStrokeColor(color(0xEFFFFF, alpha: 0.36).cgColor)
    ctx.strokePath()

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(28)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.80).cgColor)
    ctx.addArc(center: CGPoint(x: 512, y: 512), radius: 232, startAngle: .pi * 0.58, endAngle: .pi * 0.92, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    let bead = CGRect(x: 614, y: 616, width: 132, height: 132)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: color(0x002B48, alpha: 0.42).cgColor)
    ctx.addEllipse(in: bead)
    ctx.clip()
    radialGradient(in: ctx, center: CGPoint(x: 658, y: 714), radius: 112, colors: [color(0xFFFFFF, alpha: 0.82), color(0xAEFFFF, alpha: 0.34), color(0x1677FF, alpha: 0.16)])
    ctx.restoreGState()

    ctx.addEllipse(in: bead)
    ctx.setLineWidth(5)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.45).cgColor)
    ctx.strokePath()
}

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: alpha)
}

func linearGradient(in ctx: CGContext, rect: CGRect, colors: [NSColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map { $0.cgColor } as CFArray,
        locations: locations
    )!
    ctx.saveGState()
    ctx.addRect(rect)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
    ctx.restoreGState()
}

func radialGradient(in ctx: CGContext, center: CGPoint, radius: CGFloat, colors: [NSColor]) {
    let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map { $0.cgColor } as CFArray,
        locations: locations
    )!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
}

func stripAlphaIfImageMagickIsAvailable(_ file: URL) throws {
    let temp = file.deletingLastPathComponent()
        .appendingPathComponent(".\(file.deletingPathExtension().lastPathComponent)-rgb.png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["magick", file.path, "-alpha", "off", "PNG24:\(temp.path)"]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        try? FileManager.default.removeItem(at: temp)
        return
    }

    _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
}
