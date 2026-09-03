import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024×1024 앱 아이콘 — 애플 스타일 미니멀: 여자아이 얼굴 + 건반
// 원칙: 외곽선 없음, 은은한 단색 계열 그라데이션, 형태 최소화(원·곡선·직사각형), 넉넉한 여백
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
func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.strokePath()
}

// 배경: 위→아래 은은한 핑크 그라데이션 (한 가지 색조)
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xFFB9C8), rgb(0xFF8FA8)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])

// 색상
let skin = rgb(0xFFEADF)
let hair = rgb(0x46323D)
let ink = rgb(0x46323D)
let blush = rgb(0xFFA9BA)

// 머리(단발 실루엣): 얼굴보다 위쪽에 중심을 둔 큰 원 → 얼굴 위·옆만 감싸고 턱은 드러남
let hx: CGFloat = 512, hy: CGFloat = 400, hr: CGFloat = 300
fill(circle(hx, hy, hr), hair)
// 양갈래 머리: 좌우 작은 원
fill(circle(232, 330, 72), hair)
fill(circle(792, 330, 72), hair)

// 얼굴
let fx: CGFloat = 512, fy: CGFloat = 480, fr: CGFloat = 250
fill(circle(fx, fy, fr), skin)

// 앞머리: 얼굴 윗부분을 덮는 한 장의 곡선 (가운데가 살짝 내려온 둥근 앞머리)
let bangs = CGMutablePath()
let br: CGFloat = fr + 4                                // 얼굴 가장자리 안티앨리어싱 선이 비치지 않게 살짝 크게 덮음
let dy: CGFloat = 50                                    // 앞머리 양끝은 얼굴 중심보다 50 위
let dx: CGFloat = (br * br - dy * dy).squareRoot()      // 그 높이에서의 반폭
let a0 = atan2(-dy, -dx), a1 = atan2(-dy, dx)
bangs.move(to: CGPoint(x: fx - dx, y: fy - dy))
bangs.addArc(center: CGPoint(x: fx, y: fy), radius: br, startAngle: a0, endAngle: a1, clockwise: false)
bangs.addQuadCurve(to: CGPoint(x: fx - dx, y: fy - dy), control: CGPoint(x: fx, y: fy + 30))
fill(bangs, hair)

// 눈: 점 두 개 + 작은 하이라이트
for x in [fx - 92, fx + 92] {
    fill(circle(x, fy + 70, 22), ink)
    fill(circle(x - 7, fy + 62, 7), rgb(0xFFFFFF))
}
// 볼터치
fill(circle(fx - 168, fy + 122, 36), blush)
fill(circle(fx + 168, fy + 122, 36), blush)
// 미소
let smile = CGMutablePath()
smile.move(to: CGPoint(x: fx - 34, y: fy + 138))
smile.addQuadCurve(to: CGPoint(x: fx + 34, y: fy + 138), control: CGPoint(x: fx, y: fy + 176))
stroke(smile, ink, 11)

// 건반: 하단 흰 띠 + 흑건 5개 (한 옥타브), 펄보드 없이 얇은 그림자만
let keyTop: CGFloat = 784
fill(CGPath(rect: CGRect(x: 0, y: keyTop, width: 1024, height: 1024 - keyTop), transform: nil), rgb(0xFFFFFF))
let keyW: CGFloat = 1024 / 7
for i in 1...6 {
    fill(CGPath(rect: CGRect(x: CGFloat(i) * keyW - 2, y: keyTop, width: 4, height: 1024 - keyTop), transform: nil), rgb(0xEAE3EC))
}
// 흑건: 띠 윗변에서 시작해 아래쪽 모서리만 둥글게 (윗부분은 띠 영역으로 클리핑)
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: keyTop, width: 1024, height: 1024 - keyTop))
for i in [1, 2, 4, 5, 6] {
    fill(rrect(CGFloat(i) * keyW - 32, keyTop - 20, 64, 166, 10), rgb(0x2E2530))
}
ctx.restoreGState()
// 건반 윗면 그림자 (얼굴이 건반 위에 얹힌 느낌)
let shadow = CGGradient(colorsSpace: cs, colors: [rgb(0x46323D, 0.16), rgb(0x46323D, 0)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: keyTop, width: 1024, height: 22))
ctx.drawLinearGradient(shadow, start: CGPoint(x: 0, y: keyTop), end: CGPoint(x: 0, y: keyTop + 22), options: [])
ctx.restoreGState()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written", out.path)
