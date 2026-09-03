# 설치 파일 (dist)

`SoSoScore.ipa`는 iPadOS 18 이상용 **서명되지 않은(unsigned)** Release 빌드입니다.
빌드한 Mac에 Apple 개발자 서명 인증서가 없어 서명을 생략했으므로, 기기에 설치할 때
Apple ID로 재서명하는 도구가 필요합니다.

## 설치 방법

- **Sideloadly / AltStore**: `.ipa`를 불러오고 Apple ID로 로그인하면 자동으로 재서명 후 설치됩니다.
  무료 Apple ID는 7일마다 갱신이 필요합니다.
- **Xcode**: 소스에서 직접 빌드해 설치하는 편이 간단합니다.
  `project.yml`의 `DEVELOPMENT_TEAM` 주석을 해제하고 팀 ID를 넣은 뒤
  `xcodegen generate` → Xcode에서 기기를 선택해 Run.

## 다시 만들기

```bash
xcodegen generate
xcodebuild -project SoSoScore.xcodeproj -scheme SoSoScore -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
rm -rf /tmp/ipa && mkdir -p /tmp/ipa/Payload
cp -R build/Build/Products/Release-iphoneos/SoSoScore.app /tmp/ipa/Payload/
(cd /tmp/ipa && zip -qr -y SoSoScore.ipa Payload) && cp /tmp/ipa/SoSoScore.ipa dist/
```

## 빌드 정보

| 항목 | 값 |
|---|---|
| 번들 ID | `com.yru.SoSoScore` |
| 표시 이름 | SoSo Score |
| 버전 | 1.0 (1) |
| 최소 OS | iPadOS 18.0 |
| 아키텍처 | arm64 |
| 서명 | 없음 (재서명 필요) |
