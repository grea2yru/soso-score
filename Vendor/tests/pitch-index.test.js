// pitch-index.js가 Verovio getMIDIValuesForElement와 같은 피치를 내는지 샘플 악보로 검증한다.
// 실행: node Vendor/tests/pitch-index.test.js   (저장소 루트에서)
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
const verovio = require(path.join(root, 'Vendor/verovio/verovio-toolkit-wasm.js'));
const { pitchIndexFromMEI, lookupPitch } = require(path.join(root, 'Vendor/verovio/pitch-index.js'));

// 큰 4중주는 기준값(getMIDIValuesForElement) 계산만 수십 초라 제외
const SAMPLES = [
  'debussy-clair-de-lune.mxl', 'schubert-erlkoenig.mxl', 'schubert-gretchen-am-spinnrade.mxl',
  'schubert-lindenbaum.xml', 'weber-clarinet-concertino.mxl', 'haydn-op74-no1-1.mxl', 'mozart-k458-1.mxl',
];

verovio.module.onRuntimeInitialized = () => {
  const tk = new verovio.toolkit();
  tk.setOptions({ breaks: 'auto', scale: 40, pageWidth: 2100, pageHeight: 2970 });
  let failed = false;
  for (const name of SAMPLES) {
    const file = path.join(root, 'Samples', name);
    const bytes = fs.readFileSync(file);
    const ok = name.endsWith('.mxl')
      ? tk.loadZipDataBuffer(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength))
      : tk.loadData(bytes.toString('utf8'));
    if (!ok) { console.error(`FAIL ${name}: load`); failed = true; continue; }

    const ids = [...new Set(tk.renderToTimemap({ includeMeasures: true, includeRests: false }).flatMap(e => e.on || []))];
    const index = pitchIndexFromMEI(tk.getMEI({ removeIds: false }));
    let wrong = 0, missing = 0, checked = 0;
    for (const id of ids) {
      const truth = tk.getMIDIValuesForElement(id);
      if (!truth || !(truth.pitch > 0)) continue;
      checked++;
      const got = lookupPitch(index, id);
      if (got === undefined) missing++;
      else if (got !== truth.pitch) wrong++;
    }
    const status = wrong || missing || !checked ? 'FAIL' : 'ok  ';
    if (status === 'FAIL') failed = true;
    console.log(`${status} ${name.padEnd(36)} notes=${String(checked).padStart(5)} wrong=${wrong} missing=${missing}`);
  }
  process.exit(failed ? 1 : 0);
};
