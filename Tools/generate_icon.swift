#!/usr/bin/env swift
import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let cornerRadius = size * 0.22
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: cornerRadius, yRadius: cornerRadius)
bgPath.addClip()

let gradient = NSGradient(colorsAndLocations:
    (NSColor(red: 0.96, green: 0.65, blue: 0.36, alpha: 1.0), 0.0),
    (NSColor(red: 0.86, green: 0.42, blue: 0.20, alpha: 1.0), 1.0)
)!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 270)

let inset = size * 0.12
let circleRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor(white: 1.0, alpha: 0.18).setFill()
NSBezierPath(ovalIn: circleRect).fill()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.62, weight: .heavy),
    .foregroundColor: NSColor.white
]
let str = NSAttributedString(string: "$", attributes: attrs)
let textSize = str.size()
let textOrigin = NSPoint(x: (size - textSize.width) / 2.0,
                         y: (size - textSize.height) / 2.0 - size * 0.02)
str.draw(at: textOrigin)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath)")
} catch {
    FileHandle.standardError.write("Failed to write: \(error)\n".data(using: .utf8)!)
    exit(1)
}
