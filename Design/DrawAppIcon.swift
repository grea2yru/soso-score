import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024×1024 앱 아이콘: 피아노 치는 귀여운 여자아이 — 얼굴과 건반 클로즈업 (플랫 파스텔)
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
}
func fill(_ path: CGPath, _ color: CGColor) { ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath() }
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotate: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotate)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
}
func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
}
func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
    let p = CGMutablePath(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
}

// 배경
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF7E8), rgb(0xFFD6E3)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])
fill(circle(470, 520, 470), rgb(0xFFFFFF, 0.30))

// 음표·반짝이 (위쪽 여백)
let ink = rgb(0x3D3B6E)
func note(_ x: CGFloat, _ y: CGFloat, scale s: CGFloat) {
    fill(ellipse(x, y, 26 * s, 18 * s, rotate: -0.35), ink)
    let stemX = x + 22 * s
    stroke(line(stemX, y - 4 * s, stemX, y - 95 * s), ink, 10 * s)
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: stemX, y: y - 95 * s))
    flag.addQuadCurve(to: CGPoint(x: stemX + 42 * s, y: y - 50 * s), control: CGPoint(x: stemX + 48 * s, y: y - 100 * s))
    stroke(flag, ink, 10 * s)
}
note(855, 215, scale: 1.05)
note(945, 130, scale: 0.8)
func sparkle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: y - r)); p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * 0.15, y: y - r * 0.15))
    p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x + r * 0.15, y: y + r * 0.15))
    p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * 0.15, y: y + r * 0.15))
    p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x - r * 0.15, y: y - r * 0.15))
    fill(p, c)
}
sparkle(110, 170, 30, rgb(0xFFB3C6))
sparkle(190, 95, 18, rgb(0xFFC9A8))
sparkle(80, 300, 16, rgb(0xFFC9A8))

// 색상
let skin = rgb(0xFFE2CC), hair = rgb(0x4A2B20), dress = rgb(0xB9A7EE), dressDark = rgb(0xA08CE0)
let bow = rgb(0xF25C7A)

// 머리: 뒷머리 → 양갈래 → 얼굴 → 앞머리
let cx: CGFloat = 470, cy: CGFloat = 400, R: CGFloat = 250
fill(circle(cx, cy, R + 20), hair)
fill(circle(165, 480, 92), hair)
fill(circle(775, 480, 92), hair)
fill(circle(cx, cy + 10, R), skin)
let bangs = CGMutablePath()
let top = cy - R - 20
bangs.move(to: CGPoint(x: cx - R - 18, y: cy - 10))
bangs.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx - R - 10, y: top + 20))
bangs.addQuadCurve(to: CGPoint(x: cx + R + 18, y: cy - 10), control: CGPoint(x: cx + R + 10, y: top + 20))
// 스캘럽(앞머리 끝) 5개
let scallops: [CGFloat] = [cx + R + 18, cx + 150, cx + 75, cx, cx - 75, cx - 150, cx - R - 18]
for i in 0..<(scallops.count - 1) {
    let x0 = scallops[i], x1 = scallops[i + 1]
    let mid = (x0 + x1) / 2
    let edgeY: CGFloat = (i == 0 || i == scallops.count - 2) ? cy - 60 : cy - 40
    bangs.addQuadCurve(to: CGPoint(x: x1, y: edgeY), control: CGPoint(x: mid, y: cy - 110))
}
fill(bangs, hair)
// 리본
func ribbon(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
    fill(ellipse(x - 30 * s, y, 30 * s, 20 * s, rotate: -0.3), bow)
    fill(ellipse(x + 30 * s, y, 30 * s, 20 * s, rotate: 0.3), bow)
    fill(circle(x, y, 13 * s), rgb(0xD94A66))
}
ribbon(180, 395, 1.7); ribbon(760, 395, 1.7)

// 얼굴
let eye = rgb(0x2B2438)
fill(ellipse(385, 440, 34, 48), eye); fill(ellipse(555, 440, 34, 48), eye)
fill(circle(374, 424, 12), rgb(0xFFFFFF)); fill(circle(544, 424, 12), rgb(0xFFFFFF))
fill(circle(396, 458, 6), rgb(0xFFFFFF)); fill(circle(566, 458, 6), rgb(0xFFFFFF))
fill(circle(300, 525, 44), rgb(0xFFA9B8, 0.85)); fill(circle(640, 525, 44), rgb(0xFFA9B8, 0.85))
let smile = CGMutablePath()
smile.move(to: CGPoint(x: 425, y: 545))
smile.addQuadCurve(to: CGPoint(x: 515, y: 545), control: CGPoint(x: 470, y: 600))
stroke(smile, rgb(0xC85B6E), 12)

// 목·옷 (건반 위로 살짝 보임)
fill(rrect(420, 640, 100, 90, 40), skin)
let torso = CGMutablePath()
torso.move(to: CGPoint(x: 300, y: 760))
torso.addQuadCurve(to: CGPoint(x: 640, y: 760), control: CGPoint(x: 470, y: 660))
torso.addLine(to: CGPoint(x: 660, y: 800))
torso.addLine(to: CGPoint(x: 280, y: 800))
torso.closeSubpath()
fill(torso, dress)
fill(rrect(430, 705, 80, 40, 20), rgb(0xFFFFFF))   // 카라

// 건반 (화면 폭 전체)
fill(rrect(-20, 735, 1064, 60, 0), rgb(0x553426))            // 건반 덮개(펄보드)
fill(CGPath(rect: CGRect(x: -20, y: 790, width: 1064, height: 250), transform: nil), rgb(0xFFFFFF))
let keyW: CGFloat = 93
for i in 0...11 { stroke(line(CGFloat(i) * keyW, 792, CGFloat(i) * keyW, 1040), rgb(0xD9D4E3), 4) }
for i in [1, 2, 4, 5, 6, 8, 9, 11] { fill(rrect(CGFloat(i) * keyW - 28, 788, 56, 150, 8), rgb(0x2E2B3F)) }
// 건반 아래 그림자 라인
stroke(line(-20, 793, 1044, 793), rgb(0xC9C3D6), 6)

// 팔·손 (건반 위)
stroke(line(330, 780, 285, 880), skin, 76)
stroke(line(610, 780, 655, 880), skin, 76)
fill(circle(285, 892, 50), skin); fill(circle(655, 892, 50), skin)
// 손가락 느낌
for dx in [-30, -10, 10, 30] {
    fill(circle(285 + CGFloat(dx), 930, 13), skin)
    fill(circle(655 + CGFloat(dx), 930, 13), skin)
}
// 소매
fill(ellipse(335, 790, 46, 30, rotate: 0.6), dressDark)
fill(ellipse(605, 790, 46, 30, rotate: -0.6), dressDark)

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written", out.path)
