// MEI 문서에서 음표 id → MIDI 피치 표를 한 번에 만든다.
// Verovio의 getMIDIValuesForElement는 호출마다 악보 전체를 훑어 음표 수의 제곱에 비례해 느려지므로,
// getMEI() 한 번의 결과를 파싱해 같은 값을 얻는다. (브라우저·Node 공용)
(function (root) {
  const STEP = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };
  // MEI data.ACCIDENTAL.GESTURAL / WRITTEN → 반음 변화량 (미분음은 가까운 반음으로)
  const ALTER = {
    s: 1, f: -1, ss: 2, x: 2, ff: -2, xs: 3, sx: 3, ts: 3, tf: -3, n: 0,
    nf: -1, ns: 1, su: 1, sd: 1, fu: -1, fd: -1, nu: 0, nd: 0,
    '1qf': -1, '3qf': -1, '1qs': 1, '3qs': 1,
  };
  const NOTE_TAG = /<note\b([^>]*?)(\/?)>/g;

  function attr(source, name) {
    const m = new RegExp(`(?:^|\\s)${name.replace('.', '\\.')}="([^"]*)"`).exec(source);
    return m ? m[1] : null;
  }

  /** MEI 문자열 → { xml:id: midiPitch } */
  function pitchIndexFromMEI(mei) {
    const out = {};
    NOTE_TAG.lastIndex = 0;
    let m;
    while ((m = NOTE_TAG.exec(mei))) {
      const attrs = m[1];
      const id = attr(attrs, 'xml:id');
      const pname = attr(attrs, 'pname');
      const oct = attr(attrs, 'oct');
      if (!id || !(pname in STEP) || oct === null) continue;
      // 실제 소리(accid.ges)가 적힌 임시표(accid)보다 우선. 속성에 없으면 자식 <accid> 요소를 본다.
      let accid = attr(attrs, 'accid.ges') || attr(attrs, 'accid');
      if (!accid && m[2] !== '/') {
        const end = mei.indexOf('</note>', NOTE_TAG.lastIndex);
        const child = /<accid\b([^>]*)>/.exec(mei.slice(NOTE_TAG.lastIndex, end < 0 ? undefined : end));
        if (child) accid = attr(child[1], 'accid.ges') || attr(child[1], 'accid');
      }
      const alter = accid && accid in ALTER ? ALTER[accid] : 0;
      out[id] = 12 * (parseInt(oct, 10) + 1) + STEP[pname] + alter;
    }
    return out;
  }

  /** 타임맵 id로 조회. 반복 전개로 붙는 "-rend2" 같은 접미사는 원본 음표로 되돌린다. */
  function lookupPitch(index, id) {
    if (id in index) return index[id];
    const base = id.replace(/-rend\d+$/, '');
    return base in index ? index[base] : undefined;
  }

  const api = { pitchIndexFromMEI, lookupPitch };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.PitchIndex = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
