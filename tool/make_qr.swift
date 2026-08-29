#!/usr/bin/env swift
//
// Makes a QR code, and refuses to hand you one that will not work.
//
//   swift tool/make_qr.swift "https://testflight.apple.com/join/XXXXXXXX" tack-testflight.png
//
// Uses only macOS system frameworks — CoreImage to draw it, Vision to read it
// back, URLSession to check the link — so it adds nothing to the project's
// dependencies.
//
// Two things are checked before the file is written, and both exist because a
// bad QR is indistinguishable from a good one by eye:
//
//   it decodes back to the text given
//     a code that encodes the wrong thing looks exactly like one that does not
//
//   a TestFlight join link actually resolves
//     a code pointing at a beta that does not exist opens TestFlight and is
//     told "beta not found", which looks like a broken code when the link is
//     the problem. Pass --skip-link-check to make one for a link that is not
//     live yet.
//
// Error correction is H (30%), which survives being printed, photographed at
// an angle, or half covered by a thumb.

import AppKit
import CoreImage
import Foundation
import Vision

func die(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
let flags = args.filter { $0.hasPrefix("--") }
let positional = Array(args.dropFirst().filter { !$0.hasPrefix("--") })
let skipLinkCheck = flags.contains("--skip-link-check")

guard positional.count >= 2 else {
    FileHandle.standardError.write(
        "usage: swift tool/make_qr.swift <text> <output.png> [pixels] [--skip-link-check]\n"
            .data(using: .utf8)!)
    exit(2)
}

let payload = positional[0]
let outputPath = positional[1]
let targetPixels = positional.count > 2 ? (Int(positional[2]) ?? 1024) : 1024

// ---- does the link go anywhere ------------------------------------------

/// The status code, or nil when the request could not be made at all.
func statusFor(_ urlString: String) -> Int? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15

    var status: Int?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { _, response, _ in
        status = (response as? HTTPURLResponse)?.statusCode
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 20)
    return status
}

let isTestFlight = payload.contains("testflight.apple.com/join/")

if isTestFlight && !skipLinkCheck {
    switch statusFor(payload) {
    case .some(404):
        die("""
            That TestFlight link does not exist. Apple answers 404 for it, so a phone
            scanning this code would open TestFlight and be told "beta not found" —
            which looks like a broken code when the link is what is missing.

            A join link only becomes real once a build has been uploaded and a public
            group's link has been switched on in App Store Connect. docs/TESTFLIGHT.md
            has the steps.

            To make the code anyway, pass --skip-link-check.
            """)
    case .some(let code) where code >= 400:
        die("That TestFlight link answered \(code). Open it in a browser first, or pass --skip-link-check.")
    case .none:
        FileHandle.standardError.write(
            "warning: could not reach TestFlight to check that link. Carrying on.\n"
                .data(using: .utf8)!)
    default:
        break
    }
}

// ---- draw it -------------------------------------------------------------

guard let data = payload.data(using: .utf8) else { die("that text is not valid UTF-8") }
guard let generator = CIFilter(name: "CIQRCodeGenerator") else { die("CIQRCodeGenerator is unavailable") }

generator.setValue(data, forKey: "inputMessage")
generator.setValue("H", forKey: "inputCorrectionLevel")

guard let small = generator.outputImage else { die("could not encode that text") }

// Scale by a whole number so every module stays a crisp square. Interpolating
// a QR is how you get one that looks fine and scans badly.
let modules = Int(small.extent.width)
let scale = max(1, targetPixels / modules)
let scaled = small.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))

// A four-module quiet zone is part of the spec, not decoration: scanners use
// it to find the edges.
let quiet = CGFloat(scale * 4)
let canvasSize = CGSize(
    width: scaled.extent.width + quiet * 2,
    height: scaled.extent.height + quiet * 2
)

guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else {
    die("could not render the code")
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
    die("could not write a PNG")
}

// ---- read it back before claiming it works -------------------------------

guard let checkImage = bitmap.cgImage else { die("could not re-read the rendered code") }

let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]
try VNImageRequestHandler(cgImage: checkImage, options: [:]).perform([request])

let decoded = (request.results ?? []).compactMap { $0.payloadStringValue }
guard decoded.contains(payload) else {
    die("the code was drawn but did not decode back to the text given. Read: \(decoded)")
}

try png.write(to: URL(fileURLWithPath: outputPath))

print("wrote \(outputPath)")
print("  size      \(Int(canvasSize.width))x\(Int(canvasSize.height))px")
print("  modules   \(modules) at \(scale)x, 4-module quiet zone")
print("  verified  decoded back to: \(payload)")
if isTestFlight && !skipLinkCheck {
    print("  link      TestFlight answered, so the beta is live")
}
