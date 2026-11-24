// Renders the 1024px app icon PNG. Usage: swift scripts/make-icon.swift <out.png>
import AppKit
import SwiftUI

struct Wave: Shape {
    var level: Double, phase: Double, amp: Double, freq: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let base = r.maxY - r.height * level
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for x in stride(from: 0.0, through: r.width, by: 4) {
            p.addLine(to: CGPoint(x: x, y: base + sin(x / r.width * .pi * 2 * freq + phase) * amp))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Icon: View {
    var body: some View {
        let aqua = Color(red: 0.36, green: 0.84, blue: 1.0), deep = Color(red: 0.10, green: 0.38, blue: 0.98)
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.40), Color(red: 0.02, green: 0.05, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [aqua.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 600)
            Wave(level: 0.40, phase: 0.6, amp: 26, freq: 1.2).fill(aqua.opacity(0.35))
            Wave(level: 0.36, phase: 2.4, amp: 22, freq: 1.5)
                .fill(LinearGradient(colors: [aqua, deep], startPoint: .top, endPoint: .bottom))
            Image(systemName: "drop.fill")
                .font(.system(size: 470, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.75, green: 0.93, blue: 1)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
                .offset(y: -40)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render(to path: String) {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}
MainActor.assumeIsolated { render(to: CommandLine.arguments[1]) }
