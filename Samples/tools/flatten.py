"""Mutopia #1778 (debussy_Ste_Bergamesq_Clair.ly)의 \\parallelMusic 블록을 4개 성부의 선형 시퀀스로 푼다.
usage: python3 flatten.py <in.ly> <out.ly>   (이후 `ly -o abs.ly rel2abs out.ly` 로 절대 음높이 변환)"""
import re,sys
src=open(sys.argv[1],encoding='utf-8').read()
# strip block comments and line comments
src=re.sub(r'%\{.*?%\}','',src,flags=re.S)
src=re.sub(r'%[^\n]*','',src)
voices=['rhUpRed','rhDownGreen','lhUpBlue','lhDownGrey']
acc={v:[] for v in voices}
pos=0
pat=re.compile(r"\\parallelMusic\s*#'\([^)]*\)\s*\{")
def clean(bar):
    b=bar
    b=re.sub(r'\\tempo\s*"[^"]*"','',b)
    b=re.sub(r'\\barNumberCheck\s*#\s*\d+','',b)
    b=re.sub(r'\\once\s*\\override\s+[A-Za-z.]+\s*#\'[A-Za-z-]+\s*=\s*#(\'\([^)]*\)|[#A-Za-z0-9.-]+)','',b)
    b=re.sub(r'\\override\s+[A-Za-z.]+\s*#\'[A-Za-z-]+\s*=\s*#(\'\([^)]*\)|[#A-Za-z0-9.-]+)','',b)
    b=re.sub(r'\\set\s+[A-Za-z.]+\s*=\s*#[#A-Za-z0-9\'.-]+','',b)
    b=re.sub(r'[_^-]?\\markup\s*\\italic\s*"[^"]*"','',b)
    b=re.sub(r'[_^-]?\\markup\s*\{[^{}]*\}','',b)
    b=re.sub(r'[_^-]?\\markup\s*"[^"]*"','',b)
    b=re.sub(r'\\ottava\s*#-?\d+','',b)
    b=re.sub(r'\\(cu|cl|lu|oflat|myExplicitBreak|myExplicitPageBreak|pageBreak|break|newSpacingSection|mergeDifferentlyDottedOn|mergeDifferentlyHeadedOn|hideNotes|unHideNotes|dimTextDim|whiteout|slurUp|slurDown|slurNeutral|phrasingSlurUp|phrasingSlurDown|tieUp|tieDown|tieNeutral|stemUp|stemDown|stemNeutral|dynamicUp|dynamicDown)\b','',b)
    b=re.sub(r'\\s[duv]\b','s8',b)   # sustain spacer shortcuts
    b=re.sub(r'\\sustainOn|\\sustainOff','',b)
    b=re.sub(r'\\arpeggio','',b)
    b=re.sub(r'\\acciaccatura',lambda m: '\\grace',b)
    b=re.sub(r'\\dynamic\s*"[^"]*"','',b)
    return b.strip()
for m in pat.finditer(src):
    # find matching close brace
    i=m.end(); depth=1
    while depth:
        c=src[i]
        if c=='{': depth+=1
        elif c=='}': depth-=1
        i+=1
    body=src[m.end():i-1]
    bars=[b for b in body.split('|')]
    # last element after final '|' is whitespace
    if bars and not clean(bars[-1]).strip(): bars=bars[:-1]
    assert len(bars)%4==0, (len(bars), m.start())
    # relative bases from following assignments
    tail=src[i:i+400]
    rels=re.findall(r'\\relative\s+([a-g][\',]*)\s*\\(rhUpRed|rhDownGreen|lhUpBlue|lhDownGrey)',tail)
    base={v:p for p,v in rels}
    for k,v in enumerate(voices):
        vb=[clean(bars[j]) for j in range(k,len(bars),4)]
        acc[v].append('\\relative %s { %s }' % (base[v], ' | '.join(vb)+' |'))
out=['\\version "2.18.2"','\\language "english"',
     '\\header { title = "Clair de Lune" subtitle = "Suite bergamasque, L.75 No.3" composer = "Claude Debussy" copyright = "Public Domain (Mutopia Project #1778, Keith OHara)" }']
for v in voices:
    out.append('%s = { %s }' % (v, '\n'.join(acc[v])))
out.append(r'''
\score {
  \new PianoStaff <<
    \new Staff = "upper" << \key df \major \time 9/8
      \new Voice = "one" { \voiceOne \rhUpRed }
      \new Voice = "two" { \voiceTwo \rhDownGreen }
    >>
    \new Staff = "lower" << \key df \major \time 9/8 \clef bass
      \new Voice = "three" { \voiceOne \lhUpBlue }
      \new Voice = "four" { \voiceTwo \lhDownGrey \bar "|." }
    >>
  >>
  \layout { }
}''')
open(sys.argv[2],'w').write('\n'.join(out))
print('blocks per voice',[len(acc[v]) for v in voices]); print('bars',[sum(x.count('|') for x in acc[v]) for v in voices])
