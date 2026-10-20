/* ─── Woven Automata: Prolog worker ───────────────────────────────────── */
/* Runs woven_automata.pl (unchanged) in SWI-Prolog compiled to WebAssembly,
   off the main thread so long searches don't freeze the page.
   Message in:  { settings }   Message out: { type: 'result' | 'error', … } */
'use strict';

const SWIPL_BASE = 'https://cdn.jsdelivr.net/npm/swipl-wasm@8.2.0/dist/swipl/';
const PROLOG_BASE = '/woven-automata/prolog/';

importScripts(SWIPL_BASE + 'swipl-web.js');

const ready = (async () => {
  const swipl = await SWIPL({
    arguments: ['-q'],
    locateFile: (file) => SWIPL_BASE + file,
    print: () => {},
    printErr: () => {}
  });
  const files = ['woven_automata.pl', 'web.pl'];
  const sources = await Promise.all(files.map((f) =>
    fetch(PROLOG_BASE + f).then((r) => {
      if (!r.ok) throw new Error('could not load ' + f);
      return r.text();
    })));
  files.forEach((f, i) => swipl.FS.writeFile('/' + f, sources[i]));
  swipl.prolog.query("consult('/woven_automata.pl'), consult('/web.pl')").once();
  return swipl.prolog;
})();

ready.then(
  () => postMessage({ type: 'ready' }),
  (err) => postMessage({ type: 'error', message: String(err && err.message || err) })
);

const MODES = ['random', 'good', 'crystalline', 'life', 'uniform'];

function int(v, lo, hi, fallback) {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : fallback;
}

onmessage = async (e) => {
  try {
    const prolog = await ready;
    const s = e.data.settings;
    const mode = MODES.includes(s.mode) ? s.mode : 'random';
    const border = s.border === 'interlock' ? 'interlock' : 'slit';
    const goal = 'wa_generate(settings(' + [
      mode,
      int(s.width, 20, 200, 80),
      int(s.picks, 20, 1000, 500),
      int(s.bobbins, 3, 20, 8),
      int(s.max, 3, 40, 20),
      border,
      int(s.seed, 1, 999999, 1)
    ].join(', ') + '), result(Rows, Lanes, Text, Score))';
    const started = performance.now();
    const r = prolog.query(goal).once();
    if (!r || !r.Rows) throw new Error('the program found no design for these settings');
    postMessage({
      type: 'result',
      rows: r.Rows,
      lanes: r.Lanes.map((pick) => pick.map(([id, l, r2, color, pass]) =>
        ({ id, left: l, right: r2, color: String(color), pass: String(pass) }))),
      text: String(r.Text),
      score: Number(r.Score),
      ms: Math.round(performance.now() - started)
    });
  } catch (err) {
    postMessage({ type: 'error', message: String(err && err.message || err) });
  }
};
