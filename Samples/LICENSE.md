# 기본 샘플 악보 출처

모든 곡은 작곡가 사후 70년이 지난 퍼블릭 도메인 작품이며, 각 조판본(악보 파일)의 라이선스는 아래와 같다.
모든 악보는 4페이지 이상(앱 기본 조판 기준)이고, 널리 알려진 대중적인 클래식 곡으로 골랐다.

- Mutopia Project 조판본은 Public Domain 또는 Creative Commons(CC BY / CC BY-SA)로 공개되어 있다.
- music21 corpus 수록본은 퍼블릭 도메인 작품의 자유 재배포 가능한 인코딩이다 (music21: BSD 라이선스).
- OpenScore(Lieder Corpus, String Quartets)는 MuseScore 커뮤니티가 CC0 1.0(퍼블릭 도메인 헌정)으로 공개한 전사본이다.

## PDF (Mutopia Project, https://www.mutopiaproject.org)

| 파일 | 곡 | 쪽 | Mutopia # | 라이선스 |
|---|---|---|---|---|
| debussy-clair-de-lune.pdf | 드뷔시, 베르가마스크 모음곡 3곡 「달빛」 (Keith OHara 조판, 1905 Fromont 초판 기반) | 4 | 1778 | Public Domain |
| beethoven-op27-no2-moonlight.pdf | 베토벤, 피아노 소나타 14번 「월광」 Op.27 No.2 (전 악장) | 23 | 276 | CC BY-SA 2.5 |
| beethoven-op13-pathetique-2.pdf | 베토벤, 피아노 소나타 8번 「비창」 Op.13 2악장 Adagio cantabile | 5 | 295 | Public Domain |
| chopin-fantaisie-impromptu-op66.pdf | 쇼팽, 환상 즉흥곡 Op.66 | 13 | 1693 | Public Domain |
| chopin-prelude-op28-no15-raindrop.pdf | 쇼팽, 전주곡 Op.28 No.15 「빗방울」 | 5 | 471 | Public Domain |
| mozart-k331-3-alla-turca.pdf | 모차르트, 피아노 소나타 K.331 3악장 「터키 행진곡」 | 5 | 108 | Public Domain |
| schubert-impromptu-op90-no3.pdf | 슈베르트, 즉흥곡 Op.90 No.3 D.899 | 8 | 1193 | Public Domain |
| rachmaninoff-prelude-op3-no2.pdf | 라흐마니노프, 전주곡 c♯단조 Op.3 No.2 | 4 | 2033 | CC BY-SA 4.0 |
| joplin-the-entertainer.pdf | 스콧 조플린, 엔터테이너 (1902) | 4 | 263 | Public Domain |
| bach-bwv971-italian-concerto.pdf | 바흐, 이탈리아 협주곡 BWV 971 (전 악장) | 18 | 1826 | CC BY-SA 3.0 |

각 곡의 원본 페이지는 `https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=<Mutopia #>` 이다.

## MusicXML

| 파일 | 곡 | 쪽 | 출처 | 라이선스 |
|---|---|---|---|---|
| debussy-clair-de-lune.mxl | 드뷔시, 「달빛」 | 5 | Mutopia #1778(Keith OHara, LilyPond 소스)을 `tools/`의 스크립트로 MusicXML 변환 | Public Domain |
| schubert-erlkoenig.mxl | 슈베르트, 「마왕」 D.328 | 8 | OpenScore Lieder `scores/Schubert,_Franz/_/Der_Erlkönig,_D.328` | CC0 1.0 |
| schubert-gretchen-am-spinnrade.mxl | 슈베르트, 「물레 감는 그레트헨」 D.118 | 8 | OpenScore Lieder `scores/Schubert,_Franz/_/Gretchen_am_Spinnrade,_D.118` (MuseScore 4로 MusicXML 내보내기) | CC0 1.0 |
| schubert-lindenbaum.xml | 슈베르트, 「보리수」 (겨울 나그네 D.911 No.5) | 6 | music21 corpus `schubert/Lindenbaum.xml` | music21 corpus |
| beethoven-op18-no1-1.mxl | 베토벤, 현악 4중주 1번 Op.18 No.1 1악장 | 19 | music21 corpus `beethoven/opus18no1/movement1.mxl` | music21 corpus |
| mozart-k458-1.mxl | 모차르트, 현악 4중주 17번 「사냥」 K.458 1악장 | 17 | music21 corpus `mozart/k458/movement1.mxl` | music21 corpus |
| haydn-op74-no1-1.mxl | 하이든, 현악 4중주 Op.74 No.1 1악장 | 12 | music21 corpus `haydn/opus74no1/movement1.mxl` | music21 corpus |
| dvorak-op96-american.mxl | 드보르자크, 현악 4중주 12번 「아메리카」 Op.96 (전 악장) | 51 | OpenScore String Quartets `scores/Dvořák,_Antonín/String_Quartet_No.12,_Op.96_(“American”)` | CC0 1.0 |
| borodin-quartet-no2.mxl | 보로딘, 현악 4중주 2번 D장조 (전 악장, 3악장 「녹턴」 포함) | 72 | OpenScore String Quartets `scores/Borodin,_Alexander/String_Quartet_No.2` | CC0 1.0 |
| weber-clarinet-concertino.mxl | 베버, 클라리넷 콘체르티노 Op.26 (피아노 반주) | 15 | music21 corpus `weber/concertino_clarinet.mxl` (Oliver Seely 1998, 퍼블릭 도메인 헌정) | music21 corpus |

쪽수는 앱의 Verovio 기본 설정(A4, scale 40)으로 조판한 값이다.

- music21 corpus: https://github.com/cuthbertLab/music21 — `music21/corpus/`
- OpenScore Lieder: https://github.com/OpenScore/Lieder (CC0 1.0)
- OpenScore String Quartets: https://github.com/OpenScore/StringQuartets (CC0 1.0)

### 드뷔시 「달빛」 MusicXML 변환 (tools/)

퍼블릭 도메인으로 공개된 MusicXML 원본을 찾지 못해 Mutopia의 LilyPond 소스에서 직접 변환했다.

1. `tools/flatten.py` — Mutopia 소스의 `\parallelMusic` 블록을 4개 성부의 선형 시퀀스로 풀고 레이아웃 명령을 제거한다.
2. `ly rel2abs` (python-ly) — 상대 음높이를 절대 음높이로 바꾼다.
3. `tools/ly2m21.py` — LilyPond 부분 문법(음표·화음·쉼표·잇단음·붙임줄·이음줄·셈여림·음자리표)을 music21 객체로 옮겨 MusicXML로 저장한다.
