/* ─── Tile Grid ────────────────────────────────────────────────────────── */
/* Pan/zoom grid for tile subpages, ported from blog-tile's grid-public.js.
   Tiles are rendered by lib/tiles.rkt; this script positions them, adds the
   empty neighbour cells, and handles pan, zoom and the tile viewers.       */
(function () {
  'use strict';

  const CELL_SPACING = 260;
  const BASE_MIN_ZOOM = 0.6;
  const ABSOLUTE_MIN_ZOOM = 0.05;
  const MAX_ZOOM = 1.8;
  const DRAG_THRESHOLD = 10;
  const FIT_PADDING = 0.5; // in cells, around the content when fitting
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.tile-grid').forEach(function (root) {
      new TileGrid(root);
    });
  });

  function clamp(v, min, max) { return Math.min(max, Math.max(min, v)); }
  function key(x, y) { return x + ',' + y; }

  /* ── grid ──────────────────────────────────────────────────────────── */

  function TileGrid(root) {
    this.root = root;
    this.viewport = root.querySelector('.tile-grid__viewport');
    this.plane = root.querySelector('.tile-grid__plane');
    this.pan = { x: 0, y: 0 };
    this.scale = 1;
    this.current = null;
    this.drag = null;
    this.pointers = new Map();
    this.momentumRaf = null;
    this.animRaf = null;
    this.suppressClick = false;
    this.viewMoved = false; // set once the visitor pans or zooms

    this.nodes = [];
    this.byKey = new Map();
    this.plane.querySelectorAll('.grid-cell').forEach((el) => {
      const node = { el, x: parseInt(el.dataset.x, 10), y: parseInt(el.dataset.y, 10) };
      this.nodes.push(node);
      this.byKey.set(key(node.x, node.y), node);
    });
    if (!this.nodes.length) return;

    this.addEmptyNeighbours();
    this.computeExtents();
    this.bind();
    root.classList.add('is-ready');
    this.layout();
    this.fit(false);
    this.markOverflowingText();
  }

  // Faint vacant squares next to every tile, as on blog-tile's public grid.
  TileGrid.prototype.addEmptyNeighbours = function () {
    const offsets = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    const occupied = this.nodes.slice();
    occupied.forEach((n) => {
      offsets.forEach(([dx, dy]) => {
        const k = key(n.x + dx, n.y + dy);
        if (this.byKey.has(k)) return;
        const el = document.createElement('div');
        el.className = 'grid-cell grid-cell--empty';
        el.setAttribute('aria-hidden', 'true');
        this.plane.insertBefore(el, this.plane.firstChild);
        this.byKey.set(k, { el, x: n.x + dx, y: n.y + dy, empty: true });
      });
    });
  };

  TileGrid.prototype.computeExtents = function () {
    const xs = this.nodes.map((n) => n.x);
    const ys = this.nodes.map((n) => n.y);
    this.extents = {
      minX: Math.min(...xs), maxX: Math.max(...xs),
      minY: Math.min(...ys), maxY: Math.max(...ys)
    };
  };

  TileGrid.prototype.layout = function () {
    this.vpW = this.viewport.clientWidth;
    this.vpH = this.viewport.clientHeight;
    const ox = this.vpW / 2;
    const oy = this.vpH / 2;
    this.byKey.forEach((n) => {
      n.el.style.left = (ox + n.x * CELL_SPACING) + 'px';
      n.el.style.top = (oy - n.y * CELL_SPACING) + 'px';
    });
    this.applyTransform();
  };

  TileGrid.prototype.applyTransform = function () {
    this.plane.style.transform =
      'translate3d(' + this.pan.x + 'px, ' + this.pan.y + 'px, 0) scale(' + this.scale + ')';
  };

  /* ── view maths ────────────────────────────────────────────────────── */

  TileGrid.prototype.fitScale = function () {
    const e = this.extents;
    const w = (e.maxX - e.minX + 1 + FIT_PADDING * 2) * CELL_SPACING;
    const h = (e.maxY - e.minY + 1 + FIT_PADDING * 2) * CELL_SPACING;
    return Math.min(this.vpW / w, this.vpH / h);
  };

  TileGrid.prototype.minZoom = function () {
    return clamp(Math.min(BASE_MIN_ZOOM, this.fitScale() * 0.8), ABSOLUTE_MIN_ZOOM, BASE_MIN_ZOOM);
  };

  // Keep the view centre inside the tiles' bounding box.
  TileGrid.prototype.applyBounds = function () {
    const e = this.extents;
    const s = this.scale;
    this.pan.x = clamp(this.pan.x, -e.maxX * CELL_SPACING * s, -e.minX * CELL_SPACING * s);
    this.pan.y = clamp(this.pan.y, e.minY * CELL_SPACING * s, e.maxY * CELL_SPACING * s);
  };

  TileGrid.prototype.panBy = function (dx, dy) {
    this.pan.x += dx;
    this.pan.y += dy;
    this.applyBounds();
    this.applyTransform();
  };

  TileGrid.prototype.setScale = function (next, anchor) {
    const s = clamp(next, this.minZoom(), MAX_ZOOM);
    const rect = this.viewport.getBoundingClientRect();
    const ax = (anchor ? anchor.x - rect.left : rect.width / 2) - rect.width / 2;
    const ay = (anchor ? anchor.y - rect.top : rect.height / 2) - rect.height / 2;
    const wx = (ax - this.pan.x) / this.scale;
    const wy = (ay - this.pan.y) / this.scale;
    this.scale = s;
    this.pan.x = ax - wx * s;
    this.pan.y = ay - wy * s;
    this.applyBounds();
    this.applyTransform();
  };

  TileGrid.prototype.animateTo = function (targetPan, targetScale) {
    this.cancelMotion();
    if (reducedMotion.matches) {
      this.scale = targetScale;
      this.pan = { x: targetPan.x, y: targetPan.y };
      this.applyBounds();
      this.applyTransform();
      return;
    }
    const start = { x: this.pan.x, y: this.pan.y, s: this.scale };
    const t0 = performance.now();
    const duration = 240;
    const tick = (now) => {
      const t = Math.min((now - t0) / duration, 1);
      const k = 1 - (1 - t) * (1 - t); // ease-out quad
      this.scale = start.s + (targetScale - start.s) * k;
      this.pan.x = start.x + (targetPan.x - start.x) * k;
      this.pan.y = start.y + (targetPan.y - start.y) * k;
      this.applyBounds();
      this.applyTransform();
      this.animRaf = t < 1 ? requestAnimationFrame(tick) : null;
    };
    this.animRaf = requestAnimationFrame(tick);
  };

  TileGrid.prototype.zoomBy = function (direction, anchor) {
    this.viewMoved = true;
    const target = clamp(this.scale * (direction > 0 ? 1.15 : 1 / 1.15), this.minZoom(), MAX_ZOOM);
    if (!anchor) {
      // button/keyboard zoom: animate around the view centre
      const ratio = target / this.scale;
      this.animateTo({ x: this.pan.x * ratio, y: this.pan.y * ratio }, target);
      return;
    }
    this.setScale(target, anchor);
  };

  // Whole map on screen, as blog-tile opens it (never above 1:1)
  TileGrid.prototype.fit = function (animate) {
    this.viewMoved = false;
    const e = this.extents;
    const s = clamp(this.fitScale(), this.minZoom(), 1);
    const cx = (e.minX + e.maxX) / 2 * CELL_SPACING;
    const cy = -(e.minY + e.maxY) / 2 * CELL_SPACING;
    const pan = { x: -cx * s, y: -cy * s };
    if (animate) {
      this.animateTo(pan, s);
    } else {
      this.scale = s;
      this.pan = pan;
      this.applyTransform();
    }
  };

  TileGrid.prototype.centerOn = function (node) {
    this.animateTo({ x: -node.x * CELL_SPACING * this.scale, y: node.y * CELL_SPACING * this.scale }, this.scale);
  };

  TileGrid.prototype.cancelMotion = function () {
    if (this.momentumRaf) cancelAnimationFrame(this.momentumRaf);
    if (this.animRaf) cancelAnimationFrame(this.animRaf);
    this.momentumRaf = this.animRaf = null;
  };

  TileGrid.prototype.startMomentum = function (vx, vy) {
    if (reducedMotion.matches) return;
    let last = performance.now();
    const tick = (now) => {
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      vx *= 0.92;
      vy *= 0.92;
      if (Math.hypot(vx, vy) < 15) { this.momentumRaf = null; return; }
      this.panBy(vx * dt, vy * dt);
      this.momentumRaf = requestAnimationFrame(tick);
    };
    this.momentumRaf = requestAnimationFrame(tick);
  };

  /* ── input ─────────────────────────────────────────────────────────── */

  TileGrid.prototype.bind = function () {
    const vp = this.viewport;
    vp.addEventListener('pointerdown', (e) => this.onPointerDown(e));
    // move/up on window so a drag continues outside the viewport; no pointer
    // capture, so the click still lands on the tile under the pointer
    window.addEventListener('pointermove', (e) => this.onPointerMove(e));
    window.addEventListener('pointerup', (e) => this.onPointerUp(e));
    window.addEventListener('pointercancel', (e) => this.onPointerUp(e));
    vp.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.cancelMotion();
      // trackpad pinch arrives as ctrl+wheel with small deltas
      this.viewMoved = true;
      const factor = Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015));
      this.setScale(this.scale * factor, { x: e.clientX, y: e.clientY });
    }, { passive: false });
    vp.addEventListener('keydown', (e) => this.onKey(e));
    // iOS Safari: a pinch on the grid zooms the grid, not the whole page
    vp.addEventListener('gesturestart', (e) => e.preventDefault());

    this.plane.addEventListener('click', (e) => {
      const el = e.target.closest('.grid-cell');
      if (!el || el.classList.contains('grid-cell--empty')) return;
      if (this.suppressClick) { this.suppressClick = false; return; }
      this.select(this.byKey.get(key(el.dataset.x, el.dataset.y)));
      openTile(el);
    });

    this.root.querySelectorAll('[data-tile-action]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const action = btn.dataset.tileAction;
        if (action === 'zoom-in') this.zoomBy(1);
        else if (action === 'zoom-out') this.zoomBy(-1);
        else this.fit(true);
      });
    });

    // The grid's size changes on rotation, browser toolbars and late
    // layout. Until the visitor moves the view, keep the whole map fitted
    // (as blog-tile does); after that, keep their view.
    let resizeRaf = null;
    new ResizeObserver(() => {
      if (resizeRaf) cancelAnimationFrame(resizeRaf);
      resizeRaf = requestAnimationFrame(() => {
        this.layout();
        if (this.viewMoved) {
          this.applyBounds();
          this.applyTransform();
        } else {
          this.fit(false);
        }
      });
    }).observe(this.viewport);
  };

  TileGrid.prototype.onPointerDown = function (e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    if (e.target.closest('button')) return;
    this.cancelMotion();
    this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    this.viewport.focus({ preventScroll: true });

    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      this.drag = {
        type: 'pinch',
        dist: Math.hypot(b.x - a.x, b.y - a.y),
        scale: this.scale,
        midX: (a.x + b.x) / 2,
        midY: (a.y + b.y) / 2,
        moved: true
      };
      return;
    }
    this.drag = {
      type: 'pan', id: e.pointerId, moved: false,
      startX: e.clientX, startY: e.clientY, lastX: e.clientX, lastY: e.clientY,
      vx: 0, vy: 0, lastTime: performance.now()
    };
  };

  TileGrid.prototype.onPointerMove = function (e) {
    if (!this.drag) return;
    if (this.pointers.has(e.pointerId)) {
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    }
    const d = this.drag;

    if (d.type === 'pinch') {
      if (this.pointers.size < 2) return;
      this.viewMoved = true;
      const [a, b] = [...this.pointers.values()];
      const midX = (a.x + b.x) / 2;
      const midY = (a.y + b.y) / 2;
      this.setScale(d.scale * Math.hypot(b.x - a.x, b.y - a.y) / d.dist, { x: midX, y: midY });
      this.panBy(midX - d.midX, midY - d.midY);
      d.midX = midX;
      d.midY = midY;
      return;
    }

    if (e.pointerId !== d.id) return;
    const dx = e.clientX - d.lastX;
    const dy = e.clientY - d.lastY;
    if (!d.moved && Math.hypot(e.clientX - d.startX, e.clientY - d.startY) > DRAG_THRESHOLD) {
      d.moved = true;
      this.viewport.classList.add('is-panning');
    }
    if (d.moved) {
      this.viewMoved = true;
      this.panBy(dx, dy);
      const now = performance.now();
      const dt = now - d.lastTime;
      if (dt > 0 && dt < 100) {
        d.vx = d.vx * 0.6 + (dx / dt) * 1000 * 0.4;
        d.vy = d.vy * 0.6 + (dy / dt) * 1000 * 0.4;
      }
      d.lastTime = now;
    }
    d.lastX = e.clientX;
    d.lastY = e.clientY;
  };

  TileGrid.prototype.onPointerUp = function (e) {
    this.pointers.delete(e.pointerId);
    const d = this.drag;
    if (!d) return;
    if (d.type === 'pinch') {
      if (this.pointers.size < 2) {
        this.drag = null;
        this.suppressClick = true;
        setTimeout(() => { this.suppressClick = false; }, 300);
      }
      return;
    }
    if (e.pointerId !== d.id) return;
    this.drag = null;
    this.viewport.classList.remove('is-panning');
    if (d.moved) {
      this.suppressClick = true;
      setTimeout(() => { this.suppressClick = false; }, 140);
      if (e.pointerType === 'touch' && performance.now() - d.lastTime < 80 && Math.hypot(d.vx, d.vy) > 100) {
        this.startMomentum(d.vx, d.vy);
      }
    }
  };

  TileGrid.prototype.onKey = function (e) {
    if (document.querySelector('dialog[open], .viewer-overlay')) return;
    const steps = { ArrowUp: [0, 1], ArrowDown: [0, -1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] };
    if (steps[e.key]) {
      e.preventDefault();
      this.step(steps[e.key][0], steps[e.key][1]);
    } else if (e.key === '+' || e.key === '=') {
      e.preventDefault();
      this.zoomBy(1);
    } else if (e.key === '-' || e.key === '_') {
      e.preventDefault();
      this.zoomBy(-1);
    } else if ((e.key === 'Enter' || e.key === ' ') && this.current) {
      e.preventDefault();
      openTile(this.current.el);
    } else if (e.key === '0') {
      this.fit(true);
    }
  };

  // Move the selection to the nearest tile in a direction (or the one
  // nearest the view centre when nothing is selected yet).
  TileGrid.prototype.step = function (dx, dy) {
    const from = this.current || this.nearestToCenter();
    let best = null;
    let bestScore = Infinity;
    if (this.current) {
      this.nodes.forEach((n) => {
        const ax = (n.x - from.x) * dx + (n.y - from.y) * dy; // along direction
        if (ax <= 0) return;
        const off = Math.abs((n.x - from.x) * dy) + Math.abs((n.y - from.y) * dx);
        const score = ax + off * 2;
        if (score < bestScore) { bestScore = score; best = n; }
      });
    } else {
      best = from;
    }
    if (best) {
      this.viewMoved = true;
      this.select(best);
      this.centerOn(best);
      best.el.focus({ preventScroll: true });
    }
  };

  TileGrid.prototype.nearestToCenter = function () {
    const cx = -this.pan.x / this.scale / CELL_SPACING;
    const cy = this.pan.y / this.scale / CELL_SPACING;
    let best = this.nodes[0];
    let bestDist = Infinity;
    this.nodes.forEach((n) => {
      const d = Math.hypot(n.x - cx, n.y - cy);
      if (d < bestDist) { bestDist = d; best = n; }
    });
    return best;
  };

  TileGrid.prototype.select = function (node) {
    if (this.current) this.current.el.classList.remove('is-current');
    this.current = node || null;
    if (node) node.el.classList.add('is-current');
  };

  TileGrid.prototype.markOverflowingText = function () {
    this.plane.querySelectorAll('.grid-cell--text').forEach((el) => {
      const body = el.querySelector('.grid-cell__text-body');
      if (body && body.scrollHeight > body.clientHeight + 1) el.classList.add('is-overflowing');
    });
  };

  /* ── tile presentation ─────────────────────────────────────────────── */

  function openTile(el) {
    const type = el.dataset.type;
    if (type === 'image') {
      const img = el.querySelector('.grid-cell__image');
      if (!img) return;
      // as in blog-tile: tiles with text get the side-by-side preview,
      // plain image tiles go straight to the lightbox
      if (el.querySelector('.grid-cell__description')) openImagePreview(el, img);
      else openLightbox(viewSrc(img), el.dataset.title || '', null, img.dataset.full);
    } else if (type === 'sketchbook') {
      openBook(el);
    } else {
      openText(el);
    }
  }

  function coordLabel(el) { return el.dataset.x + ', ' + el.dataset.y; }

  // viewers show the 1600px copy made by lib/thumbs.rkt, not the thumbnail
  function viewSrc(img) { return img.dataset.large || img.dataset.full || img.src; }

  /* ── image + text preview (blog-tile #image-preview-dialog) ─────────── */

  function openImagePreview(el, img) {
    const dialog = makeDialog('image-preview-dialog');
    dialog.innerHTML =
      '<article class="image-preview-window" tabindex="-1">' +
      '<section class="image-preview-media">' +
      '<img alt="">' +
      '<button type="button" class="image-preview-expand" aria-label="View full screen">⤢</button>' +
      '</section>' +
      '<section class="image-preview-text">' +
      '<h3></h3><p class="image-preview-caption"></p><div class="image-preview-content"></div>' +
      '</section>' +
      '<button type="button" class="image-preview-close" aria-label="Close">×</button>' +
      '</article>';
    const em = el.querySelector('.grid-cell__overlay em');
    dialog.querySelector('h3').textContent = el.dataset.title || '';
    dialog.querySelector('.image-preview-caption').textContent = (em && em.textContent) || '';
    dialog.querySelector('.image-preview-content').innerHTML =
      el.querySelector('.grid-cell__description').innerHTML;
    const big = dialog.querySelector('.image-preview-media img');
    big.src = viewSrc(img);
    big.alt = img.alt;
    dialog.querySelector('.image-preview-close').addEventListener('click', () => dialog.close());
    // the image (or ⤢) opens the lightbox; closing it comes back here
    const toLightbox = () => {
      dialog.close();
      openLightbox(viewSrc(img), el.dataset.title || '', () => openImagePreview(el, img), img.dataset.full);
    };
    big.addEventListener('click', toLightbox);
    dialog.querySelector('.image-preview-expand').addEventListener('click', toLightbox);
    show(dialog, dialog.querySelector('.image-preview-window'));
  }

  /* ── lightbox (blog-tile #mobile-image-dialog) ─────────────────────── */

  // full: the original file, swapped in for the 1:1 view
  function openLightbox(src, title, onClose, full) {
    const dialog = makeDialog('lightbox-dialog');
    dialog.innerHTML =
      '<article class="lightbox-window" tabindex="-1">' +
      '<button type="button" class="lightbox-close" aria-label="Close">×</button>' +
      '<img class="lightbox-image" alt="" draggable="false">' +
      '<div class="lightbox-footer">' +
      '<p class="lightbox-title"></p>' +
      '<div class="lightbox-toolbar">' +
      '<button type="button" data-action="zoom-out" title="Zoom out">−</button>' +
      '<button type="button" data-action="zoom-in" title="Zoom in">+</button>' +
      '<button type="button" data-action="one-to-one" title="Original size">1:1</button>' +
      '<button type="button" data-action="reset" title="Fit to screen">⟲</button>' +
      '</div></div></article>';
    const win = dialog.querySelector('.lightbox-window');
    const img = dialog.querySelector('.lightbox-image');
    img.src = src;
    img.alt = title;
    dialog.querySelector('.lightbox-title').textContent = title;

    const z = { scale: 1, x: 0, y: 0, velX: 0, velY: 0, lastMove: 0, raf: null };
    const apply = () => {
      img.style.transform = 'translate3d(' + z.x + 'px, ' + z.y + 'px, 0) scale(' + z.scale + ')';
    };
    const panBy = (dx, dy) => { z.x += dx; z.y += dy; apply(); };
    const stopMomentum = () => {
      if (z.raf) cancelAnimationFrame(z.raf);
      z.raf = null;
    };
    const zoom = (delta) => {
      stopMomentum();
      z.scale = clamp(z.scale + delta, 0.1, 10);
      apply();
    };
    const reset = () => {
      stopMomentum();
      z.scale = 1; z.x = 0; z.y = 0;
      img.style.transform = '';
    };
    const oneToOne = () => {
      if (full && img.getAttribute('src') !== full) {
        img.addEventListener('load', oneToOne, { once: true });
        img.src = full;
        return;
      }
      if (!img.naturalWidth || !img.clientWidth) return;
      stopMomentum();
      z.scale = img.naturalWidth / img.clientWidth;
      z.x = 0; z.y = 0;
      apply();
    };
    const track = (dx, dy) => {
      const now = performance.now();
      const dt = now - z.lastMove;
      if (dt > 0 && dt < 80) {
        z.velX = z.velX * 0.4 + (dx / dt) * 1000 * 0.6;
        z.velY = z.velY * 0.4 + (dy / dt) * 1000 * 0.6;
      } else {
        z.velX = z.velY = 0;
      }
      z.lastMove = now;
    };
    // fast flicks glide longer, slow drags stop quickly
    const glide = () => {
      stopMomentum();
      let vx = z.velX, vy = z.velY;
      const speed = Math.hypot(vx, vy);
      if (speed < 20 || reducedMotion.matches) return;
      const friction = speed > 800 ? 0.96 : speed > 400 ? 0.94 : 0.91;
      let last = performance.now();
      const tick = (now) => {
        const dt = Math.min((now - last) / 1000, 0.05);
        last = now;
        vx *= friction; vy *= friction;
        if (Math.hypot(vx, vy) < 10) { z.raf = null; return; }
        panBy(vx * dt, vy * dt);
        z.raf = requestAnimationFrame(tick);
      };
      z.raf = requestAnimationFrame(tick);
    };

    dialog.querySelector('.lightbox-close').addEventListener('click', () => dialog.close());
    dialog.querySelector('.lightbox-toolbar').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-action]');
      if (!btn) return;
      const action = btn.dataset.action;
      if (action === 'zoom-in') zoom(0.25);
      else if (action === 'zoom-out') zoom(-0.25);
      else if (action === 'one-to-one') oneToOne();
      else reset();
    });
    // clicking the dark area around the image closes
    win.addEventListener('click', (e) => { if (e.target === win) dialog.close(); });
    win.addEventListener('wheel', (e) => {
      e.preventDefault();
      zoom(e.deltaY < 0 ? 0.15 : -0.15);
    }, { passive: false });

    // mouse: drag to pan once zoomed in
    let dragging = false, lastX = 0, lastY = 0;
    win.addEventListener('mousedown', (e) => {
      if (z.scale <= 1) return;
      stopMomentum();
      dragging = true;
      lastX = e.clientX; lastY = e.clientY;
      z.lastMove = performance.now();
      e.preventDefault();
    });
    const onMouseMove = (e) => {
      if (!dragging) return;
      const dx = e.clientX - lastX, dy = e.clientY - lastY;
      lastX = e.clientX; lastY = e.clientY;
      track(dx, dy);
      panBy(dx, dy);
    };
    const onMouseUp = () => {
      if (!dragging) return;
      dragging = false;
      glide();
    };
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);

    // touch: pinch zoom, pan when zoomed, swipe vertically to dismiss at 1x
    let pinchDist = 0, pinchScale = 1, midX = 0, midY = 0;
    let swipe = null;
    win.addEventListener('touchstart', (e) => {
      stopMomentum();
      const t = e.touches;
      if (t.length === 2) {
        pinchDist = Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
        pinchScale = z.scale;
        midX = (t[0].clientX + t[1].clientX) / 2;
        midY = (t[0].clientY + t[1].clientY) / 2;
        swipe = null;
      } else if (t.length === 1 && z.scale > 1.05) {
        lastX = t[0].clientX; lastY = t[0].clientY;
        z.lastMove = performance.now();
        dragging = true;
      } else if (t.length === 1) {
        swipe = { x: t[0].clientX, y: t[0].clientY, dx: 0, dy: 0 };
        win.style.transition = 'none';
      }
    }, { passive: true });
    win.addEventListener('touchmove', (e) => {
      const t = e.touches;
      if (t.length === 2 && pinchDist) {
        e.preventDefault();
        const dist = Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
        const mx = (t[0].clientX + t[1].clientX) / 2;
        const my = (t[0].clientY + t[1].clientY) / 2;
        z.scale = clamp(pinchScale * dist / pinchDist, 0.1, 10);
        track(mx - midX, my - midY);
        panBy(mx - midX, my - midY);
        midX = mx; midY = my;
      } else if (t.length === 1 && dragging) {
        e.preventDefault();
        const dx = t[0].clientX - lastX, dy = t[0].clientY - lastY;
        lastX = t[0].clientX; lastY = t[0].clientY;
        track(dx, dy);
        panBy(dx, dy);
      } else if (t.length === 1 && swipe) {
        swipe.dx = t[0].clientX - swipe.x;
        swipe.dy = t[0].clientY - swipe.y;
        if (Math.abs(swipe.dy) <= Math.abs(swipe.dx)) return;
        e.preventDefault();
        const dy = clamp(swipe.dy, -240, 240);
        win.style.transform = 'translate3d(0, ' + dy + 'px, 0)';
        win.style.opacity = String(Math.max(0.45, 1 - Math.abs(dy) / 340));
      }
    }, { passive: false });
    win.addEventListener('touchend', (e) => {
      if (e.touches.length < 2 && pinchDist) { pinchDist = 0; glide(); }
      if (e.touches.length) return;
      if (dragging) { dragging = false; glide(); }
      if (swipe) {
        const close = Math.abs(swipe.dy) > 110 && Math.abs(swipe.dy) > Math.abs(swipe.dx);
        swipe = null;
        win.style.transition = '';
        win.style.transform = '';
        win.style.opacity = '';
        if (close) dialog.close();
      }
    }, { passive: true });

    // keyboard: + / - zoom, 1 actual size, 0 fit
    dialog.addEventListener('keydown', (e) => {
      if (e.key === '+' || e.key === '=') zoom(0.25);
      else if (e.key === '-' || e.key === '_') zoom(-0.25);
      else if (e.key === '1') oneToOne();
      else if (e.key === '0') reset();
    });

    dialog.addEventListener('close', () => {
      stopMomentum();
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
      if (onClose) onClose();
    });
    show(dialog, win);
  }

  // Open modally with focus on the dialog's window rather than its first
  // button; Tab still reaches the buttons and Esc closes.
  function show(dialog, focusEl) {
    dialog.showModal();
    if (focusEl) focusEl.focus({ preventScroll: true });
  }

  function makeDialog(className) {
    const dialog = document.createElement('dialog');
    dialog.className = className;
    // click on the backdrop closes
    dialog.addEventListener('click', (e) => { if (e.target === dialog) dialog.close(); });
    dialog.addEventListener('close', () => dialog.remove());
    document.body.appendChild(dialog);
    return dialog;
  }

  function openText(el) {
    const dialog = makeDialog('tile-dialog');
    dialog.innerHTML =
      '<div class="tile-dialog__window" tabindex="-1">' +
      '<button type="button" class="tile-dialog__close" aria-label="Close">×</button>' +
      '<span class="tile-dialog__coord"></span>' +
      '<h3 class="tile-dialog__title"></h3>' +
      '<div class="tile-dialog__body"></div>' +
      '</div>';
    dialog.querySelector('.tile-dialog__coord').textContent = coordLabel(el);
    dialog.querySelector('.tile-dialog__title').textContent = el.dataset.title || 'Text tile';
    const body = el.querySelector('.grid-cell__text-body');
    dialog.querySelector('.tile-dialog__body').innerHTML = body ? body.innerHTML : '';
    dialog.querySelector('.tile-dialog__close').addEventListener('click', () => dialog.close());
    show(dialog, dialog.querySelector('.tile-dialog__window'));
  }

  // Cover alone on the right, then pages in pairs — as in blog-tile.
  function buildSpreads(count) {
    if (!count) return [];
    const spreads = [[null, 0]];
    for (let i = 1; i < count; i += 2) spreads.push([i, i + 1 < count ? i + 1 : null]);
    return spreads;
  }

  function openBook(el) {
    const pages = [...el.querySelectorAll('[data-sketch-src]')].map((p) => ({
      src: p.dataset.sketchSrc,
      full: p.dataset.full,
      alt: p.dataset.alt || ''
    }));
    if (!pages.length) return;
    const mobile = window.matchMedia('(max-width: 768px)').matches;
    const spreads = mobile ? [pages.map((_, i) => i)] : buildSpreads(pages.length);
    let index = 0;

    const dialog = makeDialog('book-dialog');
    dialog.innerHTML =
      '<button type="button" class="book-viewer__close" aria-label="Close">×</button>' +
      '<button type="button" class="book-viewer__nav book-viewer__nav--prev" aria-label="Previous pages">‹</button>' +
      '<button type="button" class="book-viewer__nav book-viewer__nav--next" aria-label="Next pages">›</button>' +
      '<div class="book-viewer" tabindex="-1">' +
      '<h3 class="book-viewer__title"></h3>' +
      '<div class="book-viewer__spread"></div>' +
      '<div class="book-viewer__indicator"></div>' +
      '</div>';
    dialog.querySelector('.book-viewer__title').textContent = el.dataset.title || 'Sketchbook';
    const spreadEl = dialog.querySelector('.book-viewer__spread');
    const prev = dialog.querySelector('.book-viewer__nav--prev');
    const next = dialog.querySelector('.book-viewer__nav--next');
    const indicator = dialog.querySelector('.book-viewer__indicator');

    function pageEl(idx, side) {
      const page = document.createElement('div');
      page.className = 'book-viewer__page' + (side ? ' book-viewer__page--' + side : '');
      if (idx === null) {
        page.classList.add('book-viewer__page--empty');
        return page;
      }
      const img = document.createElement('img');
      img.src = pages[idx].src;
      img.alt = pages[idx].alt || 'Page ' + (idx + 1);
      // enlarge a page in the lightbox, on top of the book
      img.addEventListener('click', () => openLightbox(pages[idx].src, 'Page ' + (idx + 1), null, pages[idx].full));
      page.appendChild(img);
      return page;
    }

    function render() {
      const spread = spreads[index];
      spreadEl.innerHTML = '';
      if (mobile) {
        spread.forEach((i) => spreadEl.appendChild(pageEl(i, null)));
      } else {
        spreadEl.appendChild(pageEl(spread[0], 'left'));
        spreadEl.appendChild(pageEl(spread[1], 'right'));
      }
      prev.disabled = index <= 0;
      next.disabled = index >= spreads.length - 1;
      const shown = spread.filter((i) => i !== null).map((i) => i + 1);
      indicator.textContent = shown.join('–') + ' / ' + pages.length;
    }

    function go(dir) {
      const n = index + dir;
      if (n < 0 || n >= spreads.length) return;
      index = n;
      render();
    }

    prev.addEventListener('click', () => go(-1));
    next.addEventListener('click', () => go(1));
    dialog.querySelector('.book-viewer__close').addEventListener('click', () => dialog.close());
    dialog.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowLeft') go(-1);
      if (e.key === 'ArrowRight') go(1);
    });
    dialog.addEventListener('click', (e) => { if (e.target.classList.contains('book-viewer')) dialog.close(); });
    // swipe left/right to turn the page on touch screens
    let touchX = null;
    spreadEl.addEventListener('touchstart', (e) => {
      touchX = e.touches.length === 1 ? e.touches[0].clientX : null;
    }, { passive: true });
    spreadEl.addEventListener('touchend', (e) => {
      if (touchX === null || mobile) return;
      const dx = e.changedTouches[0].clientX - touchX;
      if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
      touchX = null;
    }, { passive: true });

    render();
    show(dialog, dialog.querySelector('.book-viewer'));
  }
})();
