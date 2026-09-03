import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024×1024 앱 아이콘 — 애플 스타일 미니멀: 건반 위로 얼굴을 내민 여자아이 (얼굴 + 피아노만)
// 렌더링: swiftc -O -o drawicon Design/DrawAppIcon.swift && ./drawicon App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
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
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
}
func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
    let p = CGMutablePath(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
}

// 배경: 대각선 그라데이션 (코랄 핑크 → 살구)
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xFF7A9C), rgb(0xFFB47A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

// 색상
let skin = rgb(0xFFEBDD)
let hair = rgb(0x3A2833)
let ink = rgb(0x3A2833)
let blush = rgb(0xFF9DB0, 0.85)

// 머리: 단순한 실루엣 — 뒷머리 원 + 양쪽 동그란 머리
let cx: CGFloat = 512, cy: CGFloat = 430
fill(circle(cx, cy, 322), hair)
fill(circle(196, 262, 96), hair)
fill(circle(828, 262, 96), hair)

// 얼굴
fill(circle(cx, cy + 12, 300), skin)

// 앞머리: 한 번의 곡선으로 마무리한 둥근 앞머리
let bangs = CGMutablePath()
bangs.move(to: CGPoint(x: cx - 300, y: cy + 12))
bangs.addArc(center: CGPoint(x: cx, y: cy + 12), radius: 300, startAngle: .pi, endAngle: 0, clockwise: false)
bangs.addQuadCurve(to: CGPoint(x: cx - 300, y: cy + 12), control: CGPoint(x: cx, y: cy - 60))
fill(bangs, hair)

// 눈: 점 두 개 + 작은 하이라이트
for x in [cx - 105, cx + 105] {
    fill(circle(x, cy + 105, 30), ink)
    fill(circle(x - 10, cy + 93, 9), rgb(0xFFFFFF))
}
// 볼터치
fill(ellipse(cx - 190, cy + 175, 58, 32), blush)
fill(ellipse(cx + 190, cy + 175, 58, 32), blush)
// 미소
let smile = CGMutablePath()
smile.move(to: CGPoint(x: cx - 48, y: cy + 188))
smile.addQuadCurve(to: CGPoint(x: cx + 48, y: cy + 188), control: CGPoint(x: cx, y: cy + 240))
stroke(smile, ink, 12)

// 피아노: 얇은 어두운 띠(펄보드) + 건반
fill(CGPath(rect: CGRect(x: -20, y: 748, width: 1064, height: 62), transform: nil), rgb(0x2B2430))
fill(CGPath(rect: CGRect(x: -20, y: 806, width: 1064, height: 260), transform: nil), rgb(0xFFFFFF))
let keyW: CGFloat = 1024 / 9
for i in 1...8 { stroke(line(CGFloat(i) * keyW, 808, CGFloat(i) * keyW, 1040), rgb(0xE3DDE8), 4) }
for i in [1, 2, 4, 5, 6, 8] { fill(rrect(CGFloat(i) * keyW - 34, 800, 68, 160, 12), rgb(0x2B2430)) }
// 건반 윗면 얇은 그림자
fill(CGPath(rect: CGRect(x: -20, y: 806, width: 1064, height: 10), transform: nil), rgb(0x2B2430, 0.18))

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written", out.path)
