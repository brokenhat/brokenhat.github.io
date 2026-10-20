/* ─── Woven Automata page ──────────────────────────────────────────────── */
/* Settings form → Prolog worker (js/woven-worker.js) → the design, shown as
   a scrollable cloth (pick 1 at the bottom) with the pick to follow
   highlighted, a left-to-right recipe for that pick, the program's own
   instructions, and a plain PDF of all of it.                              */
(function () {
  'use strict';

  const JSPDF_URL = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';
  const RULER_TOP = 22;   // px band for thread numbers
  const RULER_LEFT = 44;  // px band for pick numbers
  const ZOOMS = [2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32];
  const PALETTE = {        // same colours as the program's .ppm export
    0: [210, 200, 185], 1: [20, 20, 20], 2: [240, 240, 235], 3: [80, 80, 80], 4: [200, 200, 195]
  };
  const VALUE = { 'black full': 1, 'white full': 2, 'black half': 3, 'white half': 4 };
  const FIELDS = ['mode', 'width', 'picks', 'bobbins', 'max', 'border', 'ca', 'seed'];

  document.addEventListener('DOMContentLoaded', () => {
    const root = document.querySelector('.wa');
    if (root) new App(root);
  });

  function App(root) {
    this.root = root;
    this.form = root.querySelector('.wa-controls');
    this.status = root.querySelector('.wa-status');
    this.stage = root.querySelector('.wa-stage');
    this.canvas = root.querySelector('.wa-canvas');
    this.scroller = root.querySelector('.wa-scroller');
    this.spacer = root.querySelector('.wa-spacer');
    this.slider = root.querySelector('.wa-slider');
    this.hover = root.querySelector('.wa-hover');
    this.design = null;
    this.pick = 1;
    this.cell = 0;
    this.busy = false;

    this.readUrl();
    this.bind();
    this.updateLimits();
    this.startWorker();
  }

  /* ── settings ─────────────────────────────────────────────────────── */

  // ca: auto | none | a rule number 0–255 (the select, or "other" + rule no.)
  App.prototype.settings = function () {
    const f = this.form.elements;
    const out = {};
    FIELDS.forEach((k) => { out[k] = f[k].value; });
    if (out.ca === 'other') out.ca = f.rule.value;
    return out;
  };

  App.prototype.readUrl = function () {
    const q = new URLSearchParams(location.search);
    const f = this.form.elements;
    FIELDS.forEach((k) => {
      if (k !== 'ca' && q.has(k)) f[k].value = q.get(k);
    });
    const ca = q.get('ca');
    if (ca === null) return;
    if ([...f.ca.options].some((o) => o.value === ca && o.value !== 'other')) {
      f.ca.value = ca;
    } else if (/^\d+$/.test(ca)) {
      f.ca.value = 'other';
      f.rule.value = ca;
    }
  };

  App.prototype.writeUrl = function (s) {
    const q = new URLSearchParams(s);
    history.replaceState(null, '', location.pathname + '?' + q.toString());
  };

  // a bobbin needs about 3 threads; the cap can't be below the start count
  App.prototype.updateLimits = function () {
    const f = this.form.elements;
    f.bobbins.max = String(Math.max(2, Math.floor(Number(f.width.value) / 3) || 2));
    f.max.min = f.bobbins.value || '2';
    const other = f.ca.value === 'other';
    this.root.querySelector('[data-rule]').hidden = !other;
    f.rule.disabled = !other;
  };

  /* ── worker ───────────────────────────────────────────────────────── */

  App.prototype.startWorker = function () {
    this.ready = false;
    this.setStatus('Loading the Prolog engine (about 4 MB, the first time only)…');
    this.worker = new Worker('/js/woven-worker.js');
    this.worker.onmessage = (e) => this.onWorker(e.data);
    this.worker.onerror = () => this.fail('The Prolog engine could not start in this browser.');
  };

  App.prototype.onWorker = function (msg) {
    if (msg.type === 'ready') {
      this.ready = true;
      this.setStatus('Ready.');
      if (!this.design || this.pending) this.generate();
      return;
    }
    if (msg.type === 'error') {
      this.fail('Something went wrong: ' + msg.message);
      return;
    }
    this.finish(msg);
  };

  App.prototype.generate = function () {
    if (!this.form.reportValidity()) return;
    const s = this.settings();
    this.writeUrl(s);
    if (!this.ready) {
      this.pending = true;
      return;
    }
    this.pending = false;
    this.busy = true;
    this.lastSettings = s;
    this.setBusy(true);
    const t0 = performance.now();
    const tick = () => {
      this.setStatus('Generating… ' + ((performance.now() - t0) / 1000).toFixed(1) + ' s');
    };
    tick();
    this.timer = setInterval(tick, 100);
    this.worker.postMessage({ settings: s });
  };

  App.prototype.cancel = function () {
    if (!this.busy) return;
    this.worker.terminate();
    this.stopTimer();
    this.busy = false;
    this.setBusy(false);
    this.startWorker();
    this.setStatus('Cancelled. Loading the engine again…');
  };

  App.prototype.finish = function (msg) {
    this.stopTimer();
    this.busy = false;
    this.setBusy(false);
    const s = this.lastSettings;
    this.design = {
      settings: s,
      rows: msg.rows,
      lanes: msg.lanes,
      text: msg.text.split('\n').filter((l) => !l.includes('.ppm image')).join('\n').trim(),
      score: msg.score,
      width: msg.rows[0].length,
      picks: msg.rows.length
    };
    this.buildImage();
    this.root.querySelector('.wa-rules-text').textContent = this.design.text;
    this.root.querySelector('[data-act="pdf"]').disabled = false;
    this.slider.max = String(this.design.picks);
    this.cell = 0;  // fit on first draw
    this.layout();
    this.select(1, { scroll: true });
    this.setStatus((msg.ms / 1000).toFixed(1) + ' s · ' + this.design.picks + '×' +
      this.design.width + ' · rule ' + caName(s.ca) + ' · score ' + msg.score.toFixed(3));
  };

  App.prototype.fail = function (text) {
    this.stopTimer();
    this.busy = false;
    this.setBusy(false);
    this.setStatus(text);
  };

  App.prototype.stopTimer = function () {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  };

  App.prototype.setBusy = function (busy) {
    this.form.querySelector('[type="submit"]').disabled = busy;
    this.form.querySelector('[data-act="cancel"]').hidden = !busy;
    this.root.classList.toggle('is-busy', busy);
  };

  App.prototype.setStatus = function (text) {
    this.status.textContent = text;
  };

  /* ── events ───────────────────────────────────────────────────────── */

  App.prototype.bind = function () {
    this.form.addEventListener('submit', (e) => {
      e.preventDefault();
      this.generate();
    });
    this.form.addEventListener('input', () => this.updateLimits());

    this.root.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-act]');
      if (!btn) return;
      const act = btn.dataset.act;
      if (act === 'seed') this.form.elements.seed.value = String(1 + Math.floor(Math.random() * 999999));
      else if (act === 'cancel') this.cancel();
      else if (act === 'pdf') this.downloadPdf(btn);
      else if (!this.design) return;
      else if (act === 'prev') this.select(this.pick - 1, { scroll: true });
      else if (act === 'next') this.select(this.pick + 1, { scroll: true });
      else if (act === 'zoom-in') this.zoom(1);
      else if (act === 'zoom-out') this.zoom(-1);
      else if (act === 'zoom-fit') this.zoom(0);
    });

    this.slider.addEventListener('input', () => this.select(Number(this.slider.value), { scroll: true }));

    this.scroller.addEventListener('scroll', () => this.requestDraw());
    this.scroller.addEventListener('click', (e) => {
      const hit = this.hit(e);
      if (hit) this.select(hit.pick);
    });
    this.scroller.addEventListener('mousemove', (e) => this.showHover(this.hit(e)));
    this.scroller.addEventListener('mouseleave', () => this.showHover(null));
    this.scroller.addEventListener('keydown', (e) => {
      if (!this.design) return;
      const steps = { ArrowUp: 1, ArrowDown: -1, PageUp: 10, PageDown: -10 };
      if (e.key in steps) {
        e.preventDefault();
        this.select(this.pick + steps[e.key], { scroll: true });
      } else if (e.key === 'Home') {
        e.preventDefault();
        this.select(1, { scroll: true });
      } else if (e.key === 'End') {
        e.preventDefault();
        this.select(this.design.picks, { scroll: true });
      }
    });

    new ResizeObserver(() => this.layout()).observe(this.stage);
  };

  /* ── cloth view ───────────────────────────────────────────────────── */

  // One pixel per cell, last pick on the top row; drawn scaled with no smoothing.
  App.prototype.buildImage = function () {
    const d = this.design;
    const img = document.createElement('canvas');
    img.width = d.width;
    img.height = d.picks;
    const ctx = img.getContext('2d');
    const data = ctx.createImageData(d.width, d.picks);
    for (let p = 0; p < d.picks; p++) {
      const y = d.picks - 1 - p;
      const row = d.rows[p];
      for (let x = 0; x < d.width; x++) {
        const c = PALETTE[row[x]] || [255, 0, 255];
        const i = (y * d.width + x) * 4;
        data.data[i] = c[0]; data.data[i + 1] = c[1]; data.data[i + 2] = c[2]; data.data[i + 3] = 255;
      }
    }
    ctx.putImageData(data, 0, 0);
    this.image = img;
  };

  App.prototype.fitCell = function () {
    const avail = this.scroller.clientWidth - RULER_LEFT - 8;
    const fit = Math.floor(avail / this.design.width);
    return Math.max(ZOOMS[0], Math.min(ZOOMS[ZOOMS.length - 1], fit));
  };

  App.prototype.layout = function () {
    if (!this.design) return;
    if (!this.cell) this.cell = this.fitCell();
    this.spacer.style.width = (RULER_LEFT + this.design.width * this.cell + 8) + 'px';
    this.spacer.style.height = (RULER_TOP + this.design.picks * this.cell + 8) + 'px';
    this.draw();
  };

  App.prototype.zoom = function (dir) {
    const keepPick = this.pick;
    if (dir === 0) {
      this.cell = this.fitCell();
    } else {
      const i = ZOOMS.findIndex((z) => z >= this.cell);
      const next = dir > 0 ? ZOOMS.find((z) => z > this.cell) : [...ZOOMS].reverse().find((z) => z < this.cell);
      this.cell = next || ZOOMS[Math.max(0, Math.min(ZOOMS.length - 1, i))];
    }
    this.layout();
    this.scrollToPick(keepPick, true);
  };

  // content y (in spacer coordinates) of the top of a pick's row
  App.prototype.pickY = function (pick) {
    return RULER_TOP + (this.design.picks - pick) * this.cell;
  };

  App.prototype.scrollToPick = function (pick, center) {
    const top = this.pickY(pick);
    const sc = this.scroller;
    const viewTop = sc.scrollTop + RULER_TOP;
    const viewBottom = sc.scrollTop + sc.clientHeight - this.cell;
    if (center || top < viewTop || top > viewBottom) {
      sc.scrollTop = top - (sc.clientHeight - RULER_TOP) / 2;
    }
  };

  App.prototype.requestDraw = function () {
    if (this.raf) return;
    this.raf = requestAnimationFrame(() => {
      this.raf = null;
      this.draw();
    });
  };

  App.prototype.draw = function () {
    const d = this.design;
    const cv = this.canvas;
    const w = this.scroller.clientWidth;
    const h = this.scroller.clientHeight;
    const dpr = window.devicePixelRatio || 1;
    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
      cv.width = Math.round(w * dpr);
      cv.height = Math.round(h * dpr);
      cv.style.width = w + 'px';
      cv.style.height = h + 'px';
    }
    const ctx = cv.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#f5f2ed';
    ctx.fillRect(0, 0, w, h);
    if (!d) return;

    const cell = this.cell;
    const sx = this.scroller.scrollLeft;
    const sy = this.scroller.scrollTop;
    const ox = RULER_LEFT - sx;  // screen x of thread 1's left edge
    const oy = RULER_TOP - sy;   // screen y of the top image row (last pick)

    // visible image region
    const c0 = Math.max(0, Math.floor((RULER_LEFT - ox) / cell));
    const c1 = Math.min(d.width, Math.ceil((w - ox) / cell));
    const r0 = Math.max(0, Math.floor((RULER_TOP - oy) / cell));
    const r1 = Math.min(d.picks, Math.ceil((h - oy) / cell));
    ctx.imageSmoothingEnabled = false;
    if (c1 > c0 && r1 > r0) {
      ctx.drawImage(this.image, c0, r0, c1 - c0, r1 - r0,
        ox + c0 * cell, oy + r0 * cell, (c1 - c0) * cell, (r1 - r0) * cell);
    }

    // thread / pick grid when cells are big enough to read
    if (cell >= 8) {
      ctx.strokeStyle = 'rgba(0,0,0,0.12)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let c = c0; c <= c1; c++) {
        const x = Math.round(ox + c * cell) + 0.5;
        ctx.moveTo(x, oy + r0 * cell); ctx.lineTo(x, oy + r1 * cell);
      }
      for (let r = r0; r <= r1; r++) {
        const y = Math.round(oy + r * cell) + 0.5;
        ctx.moveTo(ox + c0 * cell, y); ctx.lineTo(ox + c1 * cell, y);
      }
      ctx.stroke();
    }

    const selTop = oy + (d.picks - this.pick) * cell;
    // already-woven picks (below the one to follow)
    if (this.pick > 1) {
      ctx.fillStyle = 'rgba(245,242,237,0.6)';
      ctx.fillRect(ox, selTop + cell, d.width * cell, (this.pick - 1) * cell);
    }
    // the pick to follow
    ctx.strokeStyle = '#c04000';
    ctx.lineWidth = 2;
    ctx.strokeRect(ox - 3, selTop - 2, d.width * cell + 6, cell + 4);

    // rulers (drawn last so the cloth scrolls under them)
    ctx.fillStyle = '#f5f2ed';
    ctx.fillRect(0, 0, w, RULER_TOP);
    ctx.fillRect(0, 0, RULER_LEFT, h);
    ctx.font = '10px ui-monospace, Menlo, Consolas, monospace';
    ctx.fillStyle = '#1a1a1a';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    const tStep = cell >= 16 ? 5 : 10;
    for (let t = 1; t <= d.width; t++) {
      if (t !== 1 && t % tStep !== 0) continue;
      const x = ox + (t - 0.5) * cell;
      if (x < RULER_LEFT || x > w) continue;
      ctx.fillText(String(t), x, RULER_TOP / 2);
    }
    ctx.textAlign = 'right';
    const pStep = cell >= 10 ? 5 : cell >= 5 ? 10 : 25;
    for (let p = 1; p <= d.picks; p++) {
      if (p !== 1 && p % pStep !== 0) continue;
      const y = oy + (d.picks - p + 0.5) * cell;
      if (y < RULER_TOP || y > h) continue;
      ctx.fillText(String(p), RULER_LEFT - 8, y);
    }
    // current pick number, marked in the left ruler
    const midY = selTop + cell / 2;
    if (midY >= RULER_TOP && midY <= h) {
      ctx.fillStyle = '#c04000';
      ctx.fillRect(0, midY - 8, RULER_LEFT - 3, 16);
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 10px ui-monospace, Menlo, Consolas, monospace';
      ctx.fillText(String(this.pick), RULER_LEFT - 8, midY);
    }
  };

  App.prototype.hit = function (e) {
    if (!this.design) return null;
    const r = this.scroller.getBoundingClientRect();
    const x = e.clientX - r.left + this.scroller.scrollLeft - RULER_LEFT;
    const y = e.clientY - r.top + this.scroller.scrollTop - RULER_TOP;
    if (x < 0 || y < 0) return null;
    const thread = Math.floor(x / this.cell) + 1;
    const pick = this.design.picks - Math.floor(y / this.cell);
    if (thread < 1 || thread > this.design.width || pick < 1 || pick > this.design.picks) return null;
    return { thread, pick };
  };

  App.prototype.showHover = function (h) {
    if (!h) {
      this.hover.textContent = ' ';
      return;
    }
    const seg = this.segments(h.pick).find((s) => h.thread >= s.from && h.thread <= s.to);
    this.hover.textContent = 'Pick ' + h.pick + ' · thread ' + h.thread + ' · ' + segLabel(seg);
  };

  /* ── the pick to follow ───────────────────────────────────────────── */

  // Left to right: runs of threads woven by the same bobbin in the same
  // yarn, and runs left bare.
  App.prototype.segments = function (pick) {
    const d = this.design;
    const row = d.rows[pick - 1];
    const lane = d.lanes[pick - 1];
    const out = [];
    for (let t = 1; t <= d.width; t++) {
      const v = row[t - 1];
      let owner = null;
      if (v) {
        const covering = lane.filter((b) => t >= b.left && t <= b.right);
        owner = covering.find((b) => VALUE[b.color + ' ' + b.pass] === v) || covering[0] || null;
      }
      const key = v ? (owner ? owner.id : '?') + ':' + v : '0';
      const last = out[out.length - 1];
      if (last && last.key === key) last.to = t;
      else out.push({ key, from: t, to: t, v, owner });
    }
    return out;
  };

  function caName(ca) {
    return ca === 'auto' ? 'auto' : ca === 'none' ? 'none' : ca;
  }

  function yarnName(v) {
    return ({ 1: 'black full', 2: 'white full', 3: 'black half', 4: 'white half' })[v] || 'bare';
  }

  function segLabel(seg) {
    if (!seg) return '';
    if (!seg.v) return 'bare';
    return (seg.owner ? '#' + seg.owner.id + ' ' : '') + yarnName(seg.v);
  }

  function rangeText(seg, dash) {
    return seg.from === seg.to ? String(seg.from) : seg.from + dash + seg.to;
  }

  App.prototype.select = function (pick, opts) {
    const d = this.design;
    if (!d) return;
    this.pick = Math.max(1, Math.min(d.picks, pick));
    this.slider.value = String(this.pick);
    this.root.querySelector('.wa-pickno').textContent = this.pick + '/' + d.picks;
    if (opts && opts.scroll) this.scrollToPick(this.pick, false);
    this.renderPick();
    this.draw();
  };

  App.prototype.renderPick = function () {
    const d = this.design;
    const segs = this.segments(this.pick);
    const bobbins = new Set(segs.filter((s) => s.owner).map((s) => s.owner.id));
    this.root.querySelector('.wa-pick-title').textContent =
      'pick ' + this.pick + ' · ' + bobbins.size + ' bobbin' + (bobbins.size === 1 ? '' : 's') + ' · left → right';
    const list = this.root.querySelector('.wa-steps');
    list.innerHTML = '';
    segs.forEach((seg) => {
      const li = document.createElement('li');
      li.className = seg.v ? 'wa-step' : 'wa-step wa-step--bare';
      const sw = document.createElement('span');
      sw.className = 'wa-swatch';
      sw.dataset.v = String(seg.v);
      const range = document.createElement('span');
      range.className = 'wa-step-range';
      const n = seg.to - seg.from + 1;
      range.textContent = rangeText(seg, '–');
      const what = document.createElement('span');
      what.className = 'wa-step-what';
      what.textContent = segLabel(seg) + (n > 1 ? ' ×' + n : '');
      li.append(sw, range, what);
      list.appendChild(li);
    });
  };

  /* ── PDF ──────────────────────────────────────────────────────────── */

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error('could not load the PDF library'));
      document.head.appendChild(s);
    });
  }

  App.prototype.downloadPdf = async function (btn) {
    if (!this.design) return;
    btn.disabled = true;
    const label = btn.textContent;
    btn.textContent = '…';
    try {
      if (!window.jspdf) await loadScript(JSPDF_URL);
      const doc = this.buildPdf(new window.jspdf.jsPDF({ unit: 'mm', format: 'a4', compress: true }));
      const s = this.design.settings;
      doc.save('woven-automata-' + s.mode + '-seed' + s.seed + '.pdf');
    } catch (err) {
      this.setStatus('PDF failed: ' + err.message);
    } finally {
      btn.disabled = false;
      btn.textContent = label;
    }
  };

  // A canvas of picks fromPick..toPick and threads fromT..toT (inclusive),
  // cellPx per cell, optionally with a grid.
  App.prototype.chartCanvas = function (fromPick, toPick, cellPx, grid, fromT, toT) {
    const d = this.design;
    fromT = fromT || 1;
    toT = toT || d.width;
    const n = toPick - fromPick + 1;
    const m = toT - fromT + 1;
    const c = document.createElement('canvas');
    c.width = m * cellPx;
    c.height = n * cellPx;
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    // image rows: top row = last pick
    ctx.drawImage(this.image, fromT - 1, d.picks - toPick, m, n, 0, 0, c.width, c.height);
    if (grid) {
      ctx.strokeStyle = 'rgba(0,0,0,0.25)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let x = 0; x <= m; x++) { ctx.moveTo(x * cellPx + 0.5, 0); ctx.lineTo(x * cellPx + 0.5, c.height); }
      for (let y = 0; y <= n; y++) { ctx.moveTo(0, y * cellPx + 0.5); ctx.lineTo(c.width, y * cellPx + 0.5); }
      ctx.stroke();
    }
    return c;
  };

  App.prototype.buildPdf = function (doc) {
    const d = this.design;
    const s = d.settings;
    const M = 15;
    const PW = 210 - 2 * M;
    const PH = 297 - 2 * M;
    let y = M;

    const lines = (text, size, font) => {
      doc.setFont(font || 'courier', 'normal');
      doc.setFontSize(size);
      const lh = size * 0.42;
      text.split('\n').forEach((raw) => {
        doc.splitTextToSize(raw === '' ? ' ' : raw, PW).forEach((l) => {
          if (y + lh > M + PH) { doc.addPage(); y = M; }
          doc.text(l, M, y + lh * 0.8);
          y += lh;
        });
      });
    };

    // 1. settings + overview
    lines('Woven Automata', 14, 'helvetica');
    y += 2;
    lines([
      'Kind: ' + s.mode + '   CA rule: ' + caName(s.ca),
      'Warp: ' + d.width + ' threads   Picks: ' + d.picks + '   Borders: ' + s.border,
      'Starting bobbins: ' + s.bobbins + '   Most bobbins: ' + Math.max(Number(s.max), Number(s.bobbins)),
      'Seed: ' + s.seed + '   Score: ' + d.score.toFixed(3),
      'Link: ' + location.href,
      'Pick 1 is the bottom row. Yarn: black / white, full or half pass; bare = warp left showing.'
    ].join('\n'), 9, 'helvetica');
    y += 3;
    const availH = M + PH - y;
    const scale = Math.min(PW / d.width, availH / d.picks);  // mm per cell
    const px = Math.max(1, Math.min(4, Math.round(scale * 8)));  // ~200 dpi, capped
    const overview = this.chartCanvas(1, d.picks, px, false);
    doc.addImage(overview, 'PNG', M, y, d.width * scale, d.picks * scale, 'overview', 'FAST');

    // 2. the program's instructions
    doc.addPage(); y = M;
    lines(this.design.text, 8);

    // 3. every pick, left to right
    doc.addPage(); y = M;
    lines('PICK BY PICK (left to right; #n = bobbin, bare = leave the warp showing)', 8);
    y += 1;
    let text = '';
    for (let p = 1; p <= d.picks; p++) {
      text += 'Pick ' + p + ': ' + this.segments(p).map((seg) =>
        rangeText(seg, '-') + ' ' + (seg.v ? (seg.owner ? '#' + seg.owner.id + ' ' : '') + yarnName(seg.v) : 'bare')
      ).join(' | ') + '\n';
    }
    lines(text.trimEnd(), 8);

    // 4. numbered chart: cells big enough to read at the loom; a band of
    //    picks per page (lowest pick at the bottom), wide warps split into
    //    bands of threads
    const cellMm = Math.max(2.5, Math.min(5, PW / (d.width + 3)));
    const threadsPerPage = Math.max(1, Math.floor(PW / cellMm) - 3);
    const rowsPerPage = Math.max(1, Math.floor((PH - 12) / cellMm));
    const chartX = M + 3 * cellMm;
    for (let from = 1; from <= d.picks; from += rowsPerPage) {
      const to = Math.min(d.picks, from + rowsPerPage - 1);
      for (let t0 = 1; t0 <= d.width; t0 += threadsPerPage) {
        const t1 = Math.min(d.width, t0 + threadsPerPage - 1);
        doc.addPage();
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(8);
        doc.text('Chart: picks ' + from + '-' + to + ', threads ' + t0 + '-' + t1 +
          ' (pick ' + from + ' at the bottom)', M, M + 3);
        const top = M + 10;
        const img = this.chartCanvas(from, to, 8, true, t0, t1);
        doc.addImage(img, 'PNG', chartX, top, (t1 - t0 + 1) * cellMm, (to - from + 1) * cellMm, 'chart-' + from + '-' + t0, 'FAST');
        doc.setFontSize(Math.min(7, cellMm * 2.2));
        for (let t = t0; t <= t1; t++) {
          if (t === t0 || t % 5 === 0) doc.text(String(t), chartX + (t - t0 + 0.5) * cellMm, top - 1, { align: 'center' });
        }
        for (let p = from; p <= to; p++) {
          if (p === from || p % 5 === 0) {
            doc.text(String(p), chartX - 1, top + (to - p + 0.75) * cellMm, { align: 'right' });
          }
        }
      }
    }
    return doc;
  };
})();
