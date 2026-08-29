#!/usr/bin/env swift
//
// Makes a QR code, and refuses to hand you one that does not scan.
//
//   swift tool/make_qr.swift "https://testflight.apple.com/join/XXXXXXXX" tack-testflight.png
//
// Uses only macOS system frameworks — CoreImage to draw it and Vision to read
// it back — so it adds nothing to the project's dependencies. The read-back is
// the point: a QR that encodes the wrong thing looks exactly like one that
// encodes the right thing, and the only way to tell is to decode it.
//
// Error correction is set to H (30%), which is what survives being printed,
// photographed at an angle, or covered by a thumb.

import AppKit
import CoreImage
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: swift tool/make_qr.swift <text> <output.png> [pixels]\n".data(using: .utf8)!)
    exit(2)
}

let payload = args[1]
let outputPath = args[2]
let targetPixels = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024

guard let data = payload.data(using: .utf8) else {
    FileHandle.standardError.write("that text is not valid UTF-8\n".data(using: .utf8)!)
    exit(1)
}

guard let generator = CIFilter(name: "CIQRCodeGenerator") else {
    FileHandle.standardError.write("CIQRCodeGenerator is unavailable\n".data(using: .utf8)!)
    exit(1)
}
generator.setValue(data, forKey: "inputMessage")
generator.setValue("H", forKey: "inputCorrectionLevel")

guard let small = generator.outputImage else {
    FileHandle.standardError.write("could not encode that text\n".data(using: .utf8)!)
    exit(1)
}

// Scale by a whole number so every module stays a crisp square. Interpolating
// a QR is how you get one that looks fine and scans badly.
let modules = Int(small.extent.width)
let scale = max(1, targetPixels / modules)
let scaled = small.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))

// A quiet zone of four modules is part of the spec, not decoration: scanners
// use it to find the edges.
let quiet = CGFloat(scale * 4)
let canvasSize = CGSize(
    width: scaled.extent.width + quiet * 2,
    height: scaled.extent.height + quiet * 2
)

let context = CIContext()
guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
    FileHandle.standardError.write("could not render the code\n".data(using: .utf8)!)
    exit(1)
}

let canvas = NSImage(size: canvasSize)
canvas.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: canvasSize).fill()
NSGraphicsContext.current?.imageInterpolation = .none
NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    .draw(in: NSRect(x: quiet, y: quiet, width: scaled.extent.width, height: scaled.extent.height))
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("could not write a PNG\n".data(using: .utf8)!)
    exit(1)
}

// ---- read it back before claiming it works -------------------------------
guard let checkImage = bitmap.cgImage else {
    FileHandle.standardError.write("could not re-read the rendered code\n".data(using: .utf8)!)
    exit(1)
}

let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]
try VNImageRequestHandler(cgImage: checkImage, options: [:]).perform([request])

let decoded = (request.results ?? [])
    .compactMap { $0.payloadStringValue }

guard decoded.contains(payload) else {
    FileHandle.standardError.write(
        "the code was drawn but did not decode back to the text given. Read: \(decoded)\n"
            .data(using: .utf8)!)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))

print("wrote \(outputPath)")
print("  size      \(Int(canvasSize.width))x\(Int(canvasSize.height))px")
print("  modules   \(modules) at \(scale)x, 4-module quiet zone")
print("  verified  decoded back to: \(payload)")
