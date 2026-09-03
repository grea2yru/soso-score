import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 1024×1024 앱 아이콘 — 애플 스타일 미니멀: 양갈래 여자아이(얼굴 + 단색 몸통) + 건반
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

// 머리 색 보조: 머리끈
let tie = rgb(0xFF6F8F)

// 얼굴 기준값
let fx: CGFloat = 512, fy: CGFloat = 480, fr: CGFloat = 250

// 캐릭터(몸·머리·얼굴)를 위로 올려 얼굴과 건반 사이에 몸통이 드러날 공간을 확보
ctx.saveGState()
ctx.translateBy(x: 0, y: -44)

// 몸통: 팔 없이 어깨선만 보이는 둥근 실루엣, 단색 한 가지. 건반 뒤에 놓여 "건반 앞에 앉은" 느낌을 만든다
let shirt = rgb(0xB9E2D8)
fill(rrect(fx - 236, 700, 472, 260, 118), shirt)

// 양갈래(트윈테일): 얼굴 양옆 뒤에서 아래로 늘어지는 긴 타원 — 머리카락이 "흘러내리는" 인상을 준다
for sx in [-1.0, 1.0] as [CGFloat] {
    let tx = fx + sx * 292
    let tail = CGPath(ellipseIn: CGRect(x: tx - 68, y: 476, width: 136, height: 268), transform: nil)
    fill(tail, hair)
}

// 뒷머리(단발 실루엣): 정수리를 감싸는 큰 원 + 뺨 옆으로 내려오는 옆머리
// 원만 있으면 헬멧/모자처럼 보이므로, 옆머리가 얼굴 아래쪽까지 내려와 얼굴을 감싸게 한다
let hx: CGFloat = 512, hy: CGFloat = 440, hr: CGFloat = 292
fill(circle(hx, hy, hr), hair)
fill(rrect(hx - hr, hy, hr * 2, 200, 96), hair)      // 옆머리: 원 아래쪽을 y≈640까지 연장, 끝은 둥글게

// 얼굴
fill(circle(fx, fy, fr), skin)

// 앞머리: 세 갈래로 나뉜 둥근 앞머리(스캘럽). 한 장짜리 곡선은 모자 챙처럼 보이므로 갈래 사이를 살짝 파서 머리결을 표현
let bangs = CGMutablePath()
let br: CGFloat = fr + 4                                // 얼굴 가장자리 안티앨리어싱 선이 비치지 않게 살짝 크게 덮음
let dy: CGFloat = 40                                    // 앞머리 양끝은 얼굴 중심보다 40 위
let dx: CGFloat = (br * br - dy * dy).squareRoot()      // 그 높이에서의 반폭
let a0 = atan2(-dy, -dx), a1 = atan2(-dy, dx)
bangs.move(to: CGPoint(x: fx - dx, y: fy - dy))
bangs.addArc(center: CGPoint(x: fx, y: fy), radius: br, startAngle: a0, endAngle: a1, clockwise: false)
// 오른쪽 끝 → 왼쪽 끝으로 세 개의 둥근 갈래를 그리며 돌아온다 (갈래 사이 골은 fy-70, 갈래 끝은 fy+20 근처)
let j1 = CGPoint(x: fx + 88, y: fy - 68), j2 = CGPoint(x: fx - 88, y: fy - 68)
bangs.addQuadCurve(to: j1, control: CGPoint(x: fx + 180, y: fy + 40))
bangs.addQuadCurve(to: j2, control: CGPoint(x: fx, y: fy + 28))
bangs.addQuadCurve(to: CGPoint(x: fx - dx, y: fy - dy), control: CGPoint(x: fx - 180, y: fy + 40))
fill(bangs, hair)

// 머리끈: 양갈래가 시작되는 지점에 포인트 컬러 한 점 — 머리를 묶은 것임을 알려준다
fill(circle(fx - 292 + 6, 514, 24), tie)
fill(circle(fx + 292 - 6, 514, 24), tie)

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

ctx.restoreGState()

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
