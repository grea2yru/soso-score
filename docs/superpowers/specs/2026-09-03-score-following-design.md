# 2B. 오디오 악보 따라가기(Score Following) — 설계

- 날짜: 2026-09-03
- 상태: 승인됨
- 선행: `2026-09-03-musicxml-viewer-design.md` (2A)

## 목표

디지털 악보(MusicXML) 뷰어에서 마이크로 피아노 연주를 듣고 **현재 연주 위치의 음표를 하이라이트**하며,
위치가 보이는 마지막 페이지의 마지막 줄에 들어오면 **자동으로 다음 페이지(펼침)로 넘긴다**.
템포는 자유(연주자 속도에 맞춤). PDF 악보에는 적용하지 않는다(음표 데이터가 없음).

## 기대 정확도와 한계 (명시)

- 단순~중간 난이도 곡에서 마디 단위로 안정적으로 따라가는 것을 목표로 한다.
- 페달을 많이 쓰는 빠른 곡, 매우 큰 잔향, 다른 악기 소음에서는 흔들릴 수 있다.
- 도돌이·반복·건너뛰기는 자동 감지하지 않는다. 어긋나면 사용자가 악보의 마디를 탭해 위치를 재지정한다.

## 알고리즘

### 입력 특징: 크로마(chroma)

- `AVAudioEngine` 입력 탭 → 모노 44.1kHz(기기 기본 샘플레이트에 맞춤) → 프레임 4096 샘플, 홉 2048(~46ms)
- Hann 창 + FFT(Accelerate vDSP) → 진폭 스펙트럼 → 55Hz~2kHz 구간의 각 빈을 가장 가까운 MIDI 음에 매핑 →
  12 피치 클래스 합산 → L2 정규화 → 12차원 크로마 벡터
- 무음 게이트: 프레임 RMS가 임계값(기본 -50 dBFS) 미만이면 위치를 진행시키지 않는다.

### 악보 템플릿

- 2A `VerovioEngine.timemap()`의 항목(`qstamp`, `on: [noteID]`, `off`, `measureOn`)에서 **onset 이벤트**를 만든다:
  각 onset 시점에 울리고 있는 모든 음(지속 중인 음 포함)의 MIDI 피치 집합 → 배음(1·2·3배, 가중치 1, 0.5, 0.33)을
  더한 12차원 템플릿 → L2 정규화.
- 이벤트 = `{ index, qstamp, noteIDs(onset), soundingPitches, template, page }`. 페이지는 `getPageWithElement`로 얻는다.
- 이벤트 간 길이는 악보의 `qstamp` 차이(박 단위)로 두고, 정렬은 템포 불변이므로 절대 시간을 쓰지 않는다.

### 정렬: 온라인 DTW (Dixon 2005)

- 비용 = 1 − 코사인 유사도(입력 크로마, 이벤트 템플릿). 입력 프레임과 이벤트 사이의 누적 비용 행렬을
  대각/수평/수직 이동으로 확장하며, 탐색 창(기본 c = 200 프레임)과 최대 연속 같은 방향 이동(기본 3)을 둔다.
- 매 입력 프레임마다 현재 최적 이벤트 인덱스를 낸다. **단조 증가만 허용**(뒤로 가지 않음).
- 안정화: 이벤트 인덱스가 바뀌려면 같은 결정이 연속 2프레임 유지되어야 한다(깜빡임 방지).
- 재지정: 사용자가 마디를 탭하면 그 마디의 첫 이벤트로 상태를 초기화하고 그 지점부터 다시 정렬한다.

## 구성 요소

- **`Packages/ScoreFollowCore`**(순수 Swift + Accelerate, macOS에서 `swift test`):
  - `ChromaExtractor(sampleRate:frameSize:)` — `func process(_ samples: [Float]) -> Chroma?`(무음이면 nil)
  - `ScoreTemplateBuilder` — 타임맵 JSON → `[ScoreEvent]`
  - `OnlineDTW(events:settings:)` — `mutating func step(_ chroma: Chroma) -> Int`(현재 이벤트 인덱스),
    `mutating func reset(to eventIndex: Int)`
- **앱**:
  - `MicrophoneSource` — `AVAudioEngine` 입력 탭, 권한 요청, 프레임을 `ChromaExtractor`에 공급, 레벨(RMS) 발행
  - `ScoreFollower`(`ObservableObject`) — 소스·추출기·DTW를 묶고 `@Published currentEvent`, `isListening`, `level`
  - `MusicXMLScoreViewer` 연동: 툴바 "따라가기" 토글(귀 아이콘) → 권한 → 듣는 중 인디케이터(레벨 미터).
    `currentEvent` 변경 시 `SVGPageView.highlight(noteIDs)`(이전 하이라이트 해제) 및 페이지 자동 넘김.
  - 자동 넘김 규칙: 현재 이벤트의 페이지가 **현재 보이는 펼침의 마지막 페이지**이고, 그 페이지 안에서 이벤트의
    세로 위치가 마지막 시스템(줄)에 속하면 다음 펼침으로 넘긴다. 이벤트 → 시스템 판별은 SVG에서 음표 요소의
    조상 `g.system`을 찾아 페이지 내 순번을 얻는다(JS). 넘긴 뒤 같은 페이지로 되돌아가지 않는다.
  - 위치 재지정: 따라가기 중 화면 탭은 페이지 넘김 대신 **탭한 위치의 마디**(SVG `g.measure` 히트 테스트)로 재지정.
    따라서 따라가기 중 수동 넘김은 얼굴 제스처 또는 툴바 화살표로 한다.

## 데이터 흐름

```
마이크 → MicrophoneSource → ChromaExtractor → OnlineDTW ─┐
Verovio timemap → ScoreTemplateBuilder → [ScoreEvent] ──┘ → currentEvent → 하이라이트 · 자동 넘김
```

## 오류 처리

- 마이크 권한 거부: 안내 배너, 따라가기 버튼 비활성. 기존 넘김 수단은 유지.
- 오디오 세션 중단(전화·백그라운드): 따라가기 일시정지, 복귀 시 사용자가 다시 켬.
- 타임맵이 비어 있는 악보(음표 없음): 따라가기 버튼 비활성 + 안내.

## 테스트

- `ChromaExtractor`: 합성 사인파(예: C4+E4+G4) → C·E·G 빈이 상위 3개인지, 무음 → nil
- `ScoreTemplateBuilder`: 소형 타임맵 JSON → 이벤트 수·지속음 포함·배음 가중 확인
- `OnlineDTW`: 템플릿 시퀀스에서 (1) 정상 속도, (2) 2배 속도, (3) 0.5배 속도로 생성한 크로마 스트림(잡음 추가)을
  넣어 최종 인덱스가 마지막 이벤트에 도달하고 중간 경로가 단조 증가함을 확인; 무음 구간 삽입 시 정지 확인
- 시뮬레이터(Mac 마이크)로 실제 소리 반응 확인, 실피아노 검증은 아이패드에서
