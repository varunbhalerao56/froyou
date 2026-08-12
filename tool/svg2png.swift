// Rasterizes an SVG at an exact pixel size using WebKit.
//
// The SVG in `assets/brand/` is the source of truth for the app icon, and every
// PNG in the asset catalog is generated from it. macOS ships no SVG rasterizer
// that both honours `feGaussianBlur` + gradient masks *and* lets you name the
// output size: ImageMagick has no librsvg delegate here (its internal MSVG
// renderer drops masks outright), and `qlmanage` renders correctly but scales
// to its own thumbnail box. WebKit does both, so we drive it directly.
//
//   swift tool/svg2png.swift <in.svg> <out.png> <pixels>
//
// Square output only — that's all an app icon needs.

import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[3]) else {
    FileHandle.standardError.write("usage: svg2png <in.svg> <out.png> <size>\n".data(using: .utf8)!)
    exit(2)
}

let inputPath = args[1]
let outputPath = args[2]

guard let svg = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
    FileHandle.standardError.write("cannot read \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

// The page is laid out at the requested size in points and the snapshot is
// resampled to exactly that many pixels afterwards, because a WKWebView inherits
// the host screen's backing scale factor and would otherwise hand back a 2x
// bitmap on a retina Mac and a 1x one over ssh.
let points = Double(size)

let html = """
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:transparent;}
  svg{display:block;width:\(Int(points))px;height:\(Int(points))px;}
</style></head><body>\(svg)</body></html>
"""

// Top-level `let`s in a Swift script are locals, not globals — a type declared
// alongside them cannot close over them, so everything the delegate needs is a
// stored property.
final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let points: Double
    let size: Int
    let outputPath: String

    init(points: Double, size: Int, outputPath: String) {
        self.points = points
        self.size = size
        self.outputPath = outputPath
        let config = WKWebViewConfiguration()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: points, height: points),
            configuration: config
        )
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // One runloop turn past `didFinish` — the DOM is parsed but the first
        // paint of a filtered subtree has not necessarily landed, and
        // snapshotting too early yields the shapes without their blur.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: points, height: points)
            config.snapshotWidth = NSNumber(value: size)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, error == nil else {
                    FileHandle.standardError.write(
                        "snapshot failed: \(error?.localizedDescription ?? "unknown")\n"
                            .data(using: .utf8)!)
                    exit(1)
                }
                guard
                    let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil, pixelsWide: self.size, pixelsHigh: self.size,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
                else {
                    FileHandle.standardError.write("bitmap alloc failed\n".data(using: .utf8)!)
                    exit(1)
                }
                bitmap.size = NSSize(width: self.size, height: self.size)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(
                    in: NSRect(x: 0, y: 0, width: self.size, height: self.size),
                    from: .zero, operation: .copy, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()

                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write("encode failed\n".data(using: .utf8)!)
                    exit(1)
                }
                do {
                    try png.write(to: URL(fileURLWithPath: outputPath))
                } catch {
                    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
                    exit(1)
                }
                exit(0)
            }
        }
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        FileHandle.standardError.write("load failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let renderer = Renderer(points: points, size: size, outputPath: outputPath)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: points, height: points),
    styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = renderer.webView
window.orderBack(nil)

renderer.webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: inputPath))

app.run()
