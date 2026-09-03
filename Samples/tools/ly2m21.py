"""Minimal converter: absolute-pitch LilyPond subset (English note names) -> music21 -> MusicXML.
Written for Mutopia's Clair de Lune source after flattening \\parallelMusic and rel2abs."""
import re, sys
from fractions import Fraction
from music21 import stream, note, chord, pitch, duration, key, meter, clef, tie, spanner, dynamics, layout, metadata, bar, tempo

# usage: python3 ly2m21.py <abs.ly> <out.musicxml>
src = open(sys.argv[1], encoding='utf-8').read()

VOICES = ['rhUpRed', 'rhDownGreen', 'lhUpBlue', 'lhDownGrey']
BAR = Fraction(9, 2)  # 9/8 in quarter lengths

ACC = {'': 0, 'f': -1, 's': 1, 'ff': -2, 'ss': 2, 'x': 2}
ACC_STR = {0: '', -1: '-', 1: '#', -2: '--', 2: '##'}

tok_re = re.compile(r'''
    (?P<ws>\s+)
  | (?P<comment>%[^\n]*)
  | (?P<str>"[^"]*")
  | (?P<hairpin>\\[<>!])
  | (?P<times>\\times\s*(?P<tn>\d+)/(?P<td>\d+)\s*\{)
  | (?P<grace>\\grace\s*\{)
  | (?P<key>\\key\s+(?P<kp>[a-g](?:f|s)?)\s*\\(?P<km>major|minor))
  | (?P<clef>\\clef\s+"?(?P<cl>[a-zA-Z]+)"?)
  | (?P<cmd>\\[a-zA-Z]+)
  | (?P<simopen><<)
  | (?P<simclose>>>)
  | (?P<chordopen><)
  | (?P<chordclose>>)
  | (?P<open>\{)
  | (?P<close>\})
  | (?P<bar>\|)
  | (?P<tie>~)
  | (?P<slur>[\^_-]?[()])
  | (?P<phr>\\[()])
  | (?P<beam>[\[\]])
  | (?P<art>[\^_-](?:[-.>_^+!]|\\[a-zA-Z]+))
  | (?P<dur>(?P<dn>\d+)(?P<dots>\.*)(?P<scale>\*\d+(?:/\d+)?)?)
  | (?P<scaleonly>\*\d+(?:/\d+)?)
  | (?P<rest>[rs](?![a-z]))
  | (?P<note>(?P<nl>[a-g])(?P<na>ff|ss|f|s|x)?(?P<oct>[',]*)(?P<force>[!?]?))
  | (?P<other>.)
''', re.X)


def dur_ql(dn, dots, scale):
    ql = Fraction(4, int(dn))
    d = ql
    for _ in range(len(dots)):
        d = d / 2
        ql += d
    if scale:
        s = scale[1:]
        ql *= Fraction(s) if '/' in s else Fraction(int(s))
    return ql


def make_pitch(nl, na, octs):
    o = 3 + octs.count("'") - octs.count(',')
    p = pitch.Pitch(nl.upper() + ACC_STR[ACC[na or '']] + str(o))
    return p


class Ev:
    def __init__(self, off, obj, voice):
        self.off = off; self.obj = obj; self.voice = voice


def parse_voice(text):
    """Return list of Ev (offset in quarterLength, music21 object, voice_index)."""
    toks = [m for m in tok_re.finditer(text)]
    i = 0
    events = []
    pending_slur = []      # notes waiting for ')' closure
    pending_phr = []
    last_dur = (Fraction(1), None)   # (ql, tuplet)
    open_slur_start = []   # stack of start notes for slurs
    open_phr_start = []
    state = {'grace': False}

    def parse_seq(off, voice, stop_on_close, scale=Fraction(1), tuplet=None, stop_on_sim=False):
        nonlocal i, last_dur
        cur = off
        last_obj = None
        while i < len(toks):
            m = toks[i]; k = m.lastgroup
            if stop_on_sim and k in ('open', 'simclose'):
                return cur
            i += 1
            if k in ('ws', 'comment', 'beam', 'other', 'str', 'hairpin'):
                continue
            if k == 'bar':
                # bar check: snap to nearest bar boundary (source has a few irregular bars)
                snapped = round(cur / BAR) * BAR
                if abs(snapped - cur) <= Fraction(1, 2) and snapped != cur:
                    cur = snapped
                continue
            if k == 'close':
                if stop_on_close:
                    return cur
                continue
            if k == 'open':
                cur = parse_seq(cur, voice, True, scale, tuplet)
                continue
            if k == 'times':
                tn, td = int(m.group('tn')), int(m.group('td'))
                # \times n/d : durations multiplied by n/d
                tp = duration.Tuplet(numberNotesActual=td, numberNotesNormal=tn)
                cur = parse_seq(cur, voice, True, scale * Fraction(tn, td), tp)
                continue
            if k == 'grace':
                state['grace'] = True
                cur = parse_seq(cur, voice, True, scale, tuplet)
                state['grace'] = False
                continue
            if k == 'simopen':
                # << {A} {B} ... >> : A in this voice, B.. in aux voices; advance by max
                ends = []; sub = 0
                while True:
                    while i < len(toks) and toks[i].lastgroup == 'ws': i += 1
                    if toks[i].lastgroup == 'simclose':
                        i += 1; break
                    v = voice if sub == 0 else voice + 2 * sub
                    if toks[i].lastgroup == 'open':
                        i += 1
                        ends.append(parse_seq(cur, v, True, scale, tuplet))
                    else:
                        ends.append(parse_seq(cur, v, False, scale, tuplet, stop_on_sim=True))
                    sub += 1
                cur = max(ends)
                continue
            if k == 'key':
                kp = m.group('kp'); km = m.group('km')
                tonic = kp[0].upper() + ACC_STR[ACC[kp[1:] or '']]
                events.append(Ev(cur, key.Key(tonic, km), voice))
                continue
            if k == 'clef':
                cl = m.group('cl')
                events.append(Ev(cur, clef.TrebleClef() if cl == 'treble' else clef.BassClef(), voice))
                continue
            if k == 'cmd':
                c = m.group()[1:]
                if c in ('pp', 'ppp', 'p', 'mp', 'mf', 'f', 'ff', 'fff', 'sf', 'sfz', 'fp'):
                    events.append(Ev(cur, dynamics.Dynamic(c), voice))
                continue
            if k == 'tie':
                if last_obj is not None:
                    last_obj.tie = tie.Tie('start')
                continue
            if k == 'slur':
                s = m.group()[-1]
                if s == '(':
                    open_slur_start.append(last_obj)
                elif open_slur_start:
                    st = open_slur_start.pop()
                    if st is not None and last_obj is not None and st is not last_obj:
                        events.append(Ev(None, spanner.Slur(st, last_obj), voice))
                continue
            if k == 'phr':
                s = m.group()[-1]
                if s == '(':
                    open_phr_start.append(last_obj)
                elif open_phr_start:
                    st = open_phr_start.pop()
                    if st is not None and last_obj is not None and st is not last_obj:
                        events.append(Ev(None, spanner.Slur(st, last_obj), voice))
                continue
            if k == 'art':
                continue
            if k == 'scaleonly':
                # e.g. "s4*9/6" handled in dur; a bare scaler after chord duration
                if last_obj is not None:
                    s = m.group()[1:]
                    f = Fraction(s) if '/' in s else Fraction(int(s))
                    ql = Fraction(last_obj.duration.quarterLength) * f
                    cur = cur - Fraction(last_obj.duration.quarterLength) + ql
                    last_obj.duration = duration.Duration(ql)
                continue
            if k == 'dur':
                # duration after a chord ">" or standalone (applies to last obj if it was a chord without duration)
                ql = dur_ql(m.group('dn'), m.group('dots'), m.group('scale'))
                last_dur = (ql, None)
                if last_obj is not None and getattr(last_obj, '_needs_dur', False):
                    real = ql * scale
                    last_obj.duration = duration.Duration(real)
                    if tuplet is not None:
                        last_obj.duration = duration.Duration(ql); last_obj.duration.appendTuplet(duration.Tuplet(numberNotesActual=tuplet.numberNotesActual, numberNotesNormal=tuplet.numberNotesNormal))
                    last_obj._needs_dur = False
                    cur = last_obj._off + Fraction(last_obj.duration.quarterLength)
                continue
            if k == 'rest':
                r = m.group()
                ql, sc = last_dur[0], None
                # look ahead for duration
                j = i
                while j < len(toks) and toks[j].lastgroup == 'ws': j += 1
                if j < len(toks) and toks[j].lastgroup == 'dur':
                    d = toks[j]; i = j + 1
                    ql = dur_ql(d.group('dn'), d.group('dots'), d.group('scale')); last_dur = (ql, None)
                real = ql * scale
                if real == 0:
                    continue
                if r == 'r':
                    obj = note.Rest()
                    set_dur(obj, ql, real, tuplet)
                    obj._off = cur
                    events.append(Ev(cur, obj, voice)); last_obj = obj
                else:
                    last_obj = None  # spacer: just advance
                cur += real
                continue
            if k == 'chordopen':
                pitches = []
                while i < len(toks):
                    t = toks[i]; i += 1
                    if t.lastgroup == 'chordclose':
                        break
                    if t.lastgroup == 'note':
                        pitches.append(make_pitch(t.group('nl'), t.group('na'), t.group('oct')))
                    # ignore other tokens inside chord (articulations etc.)
                ql = last_dur[0]
                j = i
                while j < len(toks) and toks[j].lastgroup == 'ws': j += 1
                if j < len(toks) and toks[j].lastgroup == 'dur':
                    d = toks[j]; i = j + 1
                    ql = dur_ql(d.group('dn'), d.group('dots'), d.group('scale')); last_dur = (ql, None)
                real = ql * scale
                obj = chord.Chord(pitches) if len(pitches) > 1 else note.Note(pitches[0])
                set_dur(obj, ql, real, tuplet)
                obj._off = cur
                if state['grace']:
                    obj = obj.getGrace(); obj._off = cur; real = Fraction(0)
                events.append(Ev(cur, obj, voice)); last_obj = obj
                cur += real
                continue
            if k == 'note':
                p = make_pitch(m.group('nl'), m.group('na'), m.group('oct'))
                ql = last_dur[0]
                j = i
                while j < len(toks) and toks[j].lastgroup == 'ws': j += 1
                if j < len(toks) and toks[j].lastgroup == 'dur':
                    d = toks[j]; i = j + 1
                    ql = dur_ql(d.group('dn'), d.group('dots'), d.group('scale')); last_dur = (ql, None)
                real = ql * scale
                obj = note.Note(p)
                if m.group('force') == '!':
                    obj.pitch.accidental = obj.pitch.accidental or pitch.Accidental('natural')
                    obj.pitch.accidental.displayStatus = True
                set_dur(obj, ql, real, tuplet)
                obj._off = cur
                if state['grace']:
                    obj = obj.getGrace(); obj._off = cur; real = Fraction(0)
                events.append(Ev(cur, obj, voice)); last_obj = obj
                cur += real
                continue
        return cur

    end = parse_seq(Fraction(0), 1, False)
    return events, end


def set_dur(obj, ql, real, tuplet):
    if tuplet is not None:
        d = duration.Duration(ql)
        try:
            d.appendTuplet(duration.Tuplet(numberNotesActual=tuplet.numberNotesActual, numberNotesNormal=tuplet.numberNotesNormal))
            obj.duration = d
            if abs(Fraction(obj.duration.quarterLength) - real) > Fraction(1, 1000):
                obj.duration = duration.Duration(real)
        except Exception:
            obj.duration = duration.Duration(real)
    else:
        obj.duration = duration.Duration(real)


def extract_var(name):
    m = re.search(r'^%s\s*=\s*\{' % name, src, re.M)
    i = m.end(); depth = 1
    while depth:
        c = src[i]; depth += (c == '{') - (c == '}'); i += 1
    return src[m.end():i - 1]


def build():
    sc = stream.Score()
    sc.metadata = metadata.Metadata()
    sc.metadata.title = 'Clair de Lune'
    sc.metadata.movementName = 'Clair de Lune (Suite bergamasque, L.75 No.3)'
    sc.metadata.composer = 'Claude Debussy'
    parts = {}
    staff_voices = {'upper': ['rhUpRed', 'rhDownGreen'], 'lower': ['lhUpBlue', 'lhDownGrey']}
    nbars_total = 0
    all_events = {}
    for staff, vnames in staff_voices.items():
        for vi, vn in enumerate(vnames):
            evs, end = parse_voice(extract_var(vn))
            nb = int(end / BAR + Fraction(1, 2))
            nbars_total = max(nbars_total, nb)
            all_events[(staff, vi)] = evs
            print(vn, 'end', float(end), 'bars', float(end / BAR), 'events', len(evs), file=sys.stderr)
    for staff, vnames in staff_voices.items():
        p = stream.Part(id=staff)
        p.partName = ' '
        p.partAbbreviation = ' '
        measures = []
        for b in range(nbars_total):
            mm = stream.Measure(number=b + 1)
            if b == 0:
                mm.timeSignature = meter.TimeSignature('9/8')
                mm.keySignature = key.Key('D-', 'major')
                mm.clef = clef.TrebleClef() if staff == 'upper' else clef.BassClef()
                if staff == 'upper':
                    mm.insert(0, tempo.MetronomeMark(text='Andante très expressif', number=None))
            measures.append(mm)
        voices_per_measure = {}
        spanners = []
        for vi, vn in enumerate(vnames):
            for ev in all_events[(staff, vi)]:
                if ev.off is None:
                    spanners.append(ev.obj); continue
                vid = 1 + vi if ev.voice == 1 else ev.voice + vi  # aux voices
                obj = ev.obj
                if isinstance(obj, (note.GeneralNote,)) and not obj.duration.isGrace:
                    # split across barlines if needed
                    off = ev.off
                    remaining = obj
                    while True:
                        b = int(off / BAR)
                        inbar = off - b * BAR
                        ql = Fraction(remaining.duration.quarterLength)
                        if inbar + ql <= BAR + Fraction(1, 10000) or ql == 0:
                            place(measures, voices_per_measure, b, inbar, vid, remaining)
                            break
                        first, second = split_note(remaining, BAR - inbar)
                        place(measures, voices_per_measure, b, inbar, vid, first)
                        off = (b + 1) * BAR
                        remaining = second
                else:
                    b = int(ev.off / BAR)
                    inbar = ev.off - b * BAR
                    if isinstance(obj, (key.Key, clef.Clef)):
                        dup = [x for x in measures[b].getElementsByClass(obj.__class__) if x.offset == inbar]
                        if not dup:
                            measures[b].insert(inbar, obj)
                    else:
                        place(measures, voices_per_measure, b, inbar, vid, obj)
        for mm in measures:
            p.append(mm)
        for s in spanners:
            p.insert(0, s)
        parts[staff] = p
        sc.insert(0, p)
    sc.insert(0, layout.StaffGroup([parts['upper'], parts['lower']], name='Piano', abbreviation='Pno.', symbol='brace'))
    return sc


def split_note(obj, at):
    """Split a note/chord/rest at quarterLength `at`, tying notes."""
    total = Fraction(obj.duration.quarterLength)
    first = obj.__class__() if isinstance(obj, note.Rest) else obj.__deepcopy__()
    second = obj.__class__() if isinstance(obj, note.Rest) else obj.__deepcopy__()
    first.duration = duration.Duration(at); second.duration = duration.Duration(total - at)
    if not isinstance(obj, note.Rest):
        first.tie = tie.Tie('start') if obj.tie is None or obj.tie.type == 'start' else tie.Tie('continue')
        second.tie = obj.tie if obj.tie is not None else tie.Tie('stop')
        if obj.tie is not None and obj.tie.type == 'start':
            second.tie = tie.Tie('continue')
        else:
            second.tie = tie.Tie('stop')
        # transfer spanner membership
        for sp in obj.getSpannerSites():
            sp.replaceSpannedElement(obj, first if sp.isFirst(obj) else second)
    return first, second


def place(measures, vpm, b, inbar, vid, obj):
    mm = measures[b]
    if b not in vpm:
        vpm[b] = {}
    if vid not in vpm[b]:
        v = stream.Voice(id=str(vid))
        vpm[b][vid] = v
        mm.insert(0, v)
    vpm[b][vid].insert(inbar, obj)


def fix_ties(sc):
    """Set tie 'stop' on notes following a tie 'start' with matching pitch."""
    for p in sc.parts:
        for v_id in set(v.id for m in p.getElementsByClass('Measure') for v in m.voices):
            seq = []
            for m in p.getElementsByClass('Measure'):
                for v in m.voices:
                    if v.id == v_id:
                        for n in v.notesAndRests:
                            seq.append(n)
            for a, bnote in zip(seq, seq[1:]):
                if isinstance(a, note.Rest) or isinstance(bnote, note.Rest):
                    continue
                if a.tie is not None and a.tie.type in ('start', 'continue'):
                    if isinstance(a, chord.Chord) and isinstance(bnote, chord.Chord):
                        pa = {x.nameWithOctave for x in a.pitches}
                        for n in bnote.notes:
                            if n.pitch.nameWithOctave in pa:
                                n.tie = tie.Tie('stop') if (n.tie is None) else tie.Tie('continue')
                        for n in a.notes:
                            if n.tie is None and n.pitch.nameWithOctave in {x.nameWithOctave for x in bnote.pitches}:
                                n.tie = tie.Tie('start')
                    elif isinstance(a, note.Note) and isinstance(bnote, note.Note):
                        if a.pitch.nameWithOctave == bnote.pitch.nameWithOctave:
                            bnote.tie = tie.Tie('stop') if bnote.tie is None else tie.Tie('continue')
                        else:
                            a.tie = None
                    elif isinstance(a, note.Note) and isinstance(bnote, chord.Chord):
                        for n in bnote.notes:
                            if n.pitch.nameWithOctave == a.pitch.nameWithOctave:
                                n.tie = tie.Tie('stop') if n.tie is None else tie.Tie('continue')
                    elif isinstance(a, chord.Chord) and isinstance(bnote, note.Note):
                        pa = {x.nameWithOctave for x in a.pitches}
                        if bnote.pitch.nameWithOctave in pa:
                            bnote.tie = tie.Tie('stop') if bnote.tie is None else tie.Tie('continue')
                        for n in a.notes:
                            if n.pitch.nameWithOctave != bnote.pitch.nameWithOctave:
                                n.tie = None


if __name__ == '__main__':
    sc = build()
    fix_ties(sc)
    for p in sc.parts:
        p.makeAccidentals(inPlace=True, cautionaryPitchClass=False, cautionaryNotImmediateRepeat=False)
    out = sys.argv[2]
    sc.write('musicxml', fp=out)
    print('written', out)
