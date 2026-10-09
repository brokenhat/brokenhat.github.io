/* ─── Image Investigation Tool ─────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', init);

function init() {
  document.querySelectorAll('.gallery-item img').forEach(function (img) {
    img.style.cursor = 'pointer';
    img.addEventListener('click', function () { openViewer(img); });
  });
}

/* ── state ─────────────────────────────────────────────────────────────── */
var overlay, canvas, ctx, navImg, loupe, fullImg;
var images = [], captions = [], currentIndex = 0;
var loupeSize = 0.25; // fraction of navigator dimension

function openViewer(clickedImg) {
  var gallery = clickedImg.closest('.gallery');
  if (!gallery) return;

  images = [];
  captions = [];
  gallery.querySelectorAll('.gallery-item').forEach(function (item) {
    var img = item.querySelector('img');
    var cap = item.querySelector('figcaption');
    if (img) {
      images.push(img.src);
      captions.push(cap ? cap.textContent : '');
    }
  });
  currentIndex = images.indexOf(clickedImg.src);
  if (currentIndex < 0) currentIndex = 0;

  buildModal();
  loadImage(currentIndex);
  document.addEventListener('keydown', onKey);
  document.body.style.overflow = 'hidden';
}

function buildModal() {
  overlay = document.createElement('div');
  overlay.className = 'viewer-overlay';
  overlay.addEventListener('click', function (e) {
    if (e.target === overlay) closeViewer();
  });

  var viewer = document.createElement('div');
  viewer.className = 'viewer';

  // ── detail panel (left) ──
  var detailPanel = document.createElement('div');
  detailPanel.className = 'viewer-detail';
  canvas = document.createElement('canvas');
  detailPanel.appendChild(canvas);
  ctx = canvas.getContext('2d');

  // ── nav panel (right) ──
  var navPanel = document.createElement('div');
  navPanel.className = 'viewer-nav-panel';

  var navWrap = document.createElement('div');
  navWrap.className = 'viewer-navigator';
  navImg = document.createElement('img');
  navImg.alt = 'Navigator';
  loupe = document.createElement('div');
  loupe.className = 'viewer-loupe';
  navWrap.appendChild(navImg);
  navWrap.appendChild(loupe);

  var captionEl = document.createElement('div');
  captionEl.className = 'viewer-caption';

  // nav buttons
  var navButtons = document.createElement('div');
  navButtons.className = 'viewer-buttons';

  var prevBtn = document.createElement('button');
  prevBtn.className = 'viewer-btn viewer-prev';
  prevBtn.textContent = '\u2190';
  prevBtn.addEventListener('click', function () { navigate(-1); });

  var nextBtn = document.createElement('button');
  nextBtn.className = 'viewer-btn viewer-next';
  nextBtn.textContent = '\u2192';
  nextBtn.addEventListener('click', function () { navigate(1); });

  var closeBtn = document.createElement('button');
  closeBtn.className = 'viewer-btn viewer-close';
  closeBtn.textContent = '\u00d7';
  closeBtn.addEventListener('click', closeViewer);

  navButtons.appendChild(prevBtn);
  navButtons.appendChild(nextBtn);

  navPanel.appendChild(navWrap);
  navPanel.appendChild(captionEl);
  navPanel.appendChild(navButtons);

  // ── scale comparison (if piece has dimensions) ──
  var piece = document.querySelector('.piece[data-w][data-h]');
  if (piece) {
    var pw = parseFloat(piece.getAttribute('data-w'));
    var ph = parseFloat(piece.getAttribute('data-h'));
    if (pw > 0 && ph > 0) {
      var scaleWrap = document.createElement('div');
      scaleWrap.className = 'viewer-scale-wrap';

      var toggle = document.createElement('button');
      toggle.className = 'viewer-btn viewer-scale-toggle';
      toggle.textContent = 'Scale';
      toggle.addEventListener('click', function () {
        scaleWrap.classList.toggle('open');
      });

      scaleWrap.appendChild(buildScaleSVG(pw, ph));
      navPanel.appendChild(toggle);
      navPanel.appendChild(scaleWrap);
    }
  }

  viewer.appendChild(detailPanel);
  viewer.appendChild(navPanel);
  overlay.appendChild(closeBtn);
  overlay.appendChild(viewer);
  document.body.appendChild(overlay);

  // ── pointer / touch on navigator ──
  navWrap.addEventListener('mousemove', updateLoupe);
  navWrap.addEventListener('mousedown', function (e) { e.preventDefault(); updateLoupe(e); });
  navWrap.addEventListener('touchmove', function (e) {
    e.preventDefault();
    var t = e.touches[0];
    updateLoupe(t);
  }, { passive: false });
  navWrap.addEventListener('touchstart', function (e) {
    e.preventDefault();
    var t = e.touches[0];
    updateLoupe(t);
  }, { passive: false });
}

function loadImage(idx) {
  fullImg = new Image();
  fullImg.onload = function () {
    sizeCanvas();
    // centre loupe initially
    var rect = navImg.getBoundingClientRect();
    updateLoupeAt(rect.width / 2, rect.height / 2);
  };
  fullImg.src = images[idx];
  navImg.src = images[idx];

  var cap = overlay.querySelector('.viewer-caption');
  cap.textContent = captions[idx] || '';

  // show/hide nav buttons
  overlay.querySelector('.viewer-prev').style.visibility = images.length > 1 ? 'visible' : 'hidden';
  overlay.querySelector('.viewer-next').style.visibility = images.length > 1 ? 'visible' : 'hidden';
}

function sizeCanvas() {
  var panel = canvas.parentElement;
  var maxW = panel.clientWidth || 600;
  var maxH = panel.clientHeight || 600;
  // canvas resolution matches available space (capped at image size)
  canvas.width = Math.min(fullImg.naturalWidth, maxW * devicePixelRatio);
  canvas.height = Math.min(fullImg.naturalHeight, maxH * devicePixelRatio);
  canvas.style.width = Math.min(fullImg.naturalWidth / devicePixelRatio, maxW) + 'px';
  canvas.style.height = Math.min(fullImg.naturalHeight / devicePixelRatio, maxH) + 'px';
}

/* ── loupe logic ───────────────────────────────────────────────────────── */
function updateLoupe(e) {
  var rect = navImg.getBoundingClientRect();
  var x = (e.clientX || e.pageX) - rect.left;
  var y = (e.clientY || e.pageY) - rect.top;
  updateLoupeAt(x, y);
}

function updateLoupeAt(x, y) {
  var rect = navImg.getBoundingClientRect();
  var w = rect.width, h = rect.height;
  if (!w || !h || !fullImg.naturalWidth) return;

  // loupe square dimensions
  var lw = w * loupeSize;
  var lh = h * loupeSize;

  // clamp
  x = Math.max(lw / 2, Math.min(x, w - lw / 2));
  y = Math.max(lh / 2, Math.min(y, h - lh / 2));

  loupe.style.width = lw + 'px';
  loupe.style.height = lh + 'px';
  loupe.style.left = (x - lw / 2) + 'px';
  loupe.style.top = (y - lh / 2) + 'px';

  // source crop in natural image coords
  var scaleX = fullImg.naturalWidth / w;
  var scaleY = fullImg.naturalHeight / h;
  var sx = (x - lw / 2) * scaleX;
  var sy = (y - lh / 2) * scaleY;
  var sw = lw * scaleX;
  var sh = lh * scaleY;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(fullImg, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
}

/* ── navigation ────────────────────────────────────────────────────────── */
function navigate(dir) {
  currentIndex = (currentIndex + dir + images.length) % images.length;
  loadImage(currentIndex);
}

function onKey(e) {
  if (e.key === 'Escape') closeViewer();
  else if (e.key === 'ArrowLeft') navigate(-1);
  else if (e.key === 'ArrowRight') navigate(1);
}

function closeViewer() {
  document.removeEventListener('keydown', onKey);
  document.body.style.overflow = '';
  if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
  overlay = null;
}

/* ── scale SVG ─────────────────────────────────────────────────────────── */
function buildScaleSVG(cmW, cmH) {
  var humanH = 170; // cm
  var maxPx = 200;  // SVG height budget
  var pxPerCm = maxPx / Math.max(humanH, cmH);

  var svgH = Math.max(humanH, cmH) * pxPerCm + 20;
  var personPx = humanH * pxPerCm;
  var pieceHpx = cmH * pxPerCm;
  var pieceWpx = cmW * pxPerCm;

  // cap piece width so SVG doesn't get absurdly wide
  var totalW = 40 + pieceWpx + 30;
  if (totalW > 320) {
    var scale = 320 / totalW;
    pieceWpx *= scale;
    pieceHpx *= scale;
    personPx *= scale;
    pxPerCm *= scale;
    svgH = Math.max(personPx, pieceHpx) + 20;
    totalW = 320;
  }

  var ns = 'http://www.w3.org/2000/svg';
  var svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('class', 'viewer-scale-svg');
  svg.setAttribute('viewBox', '0 0 ' + totalW + ' ' + svgH);
  svg.setAttribute('width', totalW);
  svg.setAttribute('height', svgH);

  // human silhouette — simple stick figure / outline
  var personX = 20;
  var personBase = svgH - 10;
  var headR = personPx * 0.06;
  var bodyPath = [
    // head
    'M', personX, personBase - personPx + headR,
    // body line
    'M', personX, personBase - personPx + headR * 2,
    'L', personX, personBase - personPx * 0.4,
    // legs
    'M', personX, personBase - personPx * 0.4,
    'L', personX - personPx * 0.08, personBase,
    'M', personX, personBase - personPx * 0.4,
    'L', personX + personPx * 0.08, personBase,
    // arms
    'M', personX, personBase - personPx * 0.7,
    'L', personX - personPx * 0.12, personBase - personPx * 0.5,
    'M', personX, personBase - personPx * 0.7,
    'L', personX + personPx * 0.12, personBase - personPx * 0.5
  ].join(' ');

  var head = document.createElementNS(ns, 'circle');
  head.setAttribute('cx', personX);
  head.setAttribute('cy', personBase - personPx + headR);
  head.setAttribute('r', headR);
  head.setAttribute('fill', 'none');
  head.setAttribute('stroke', '#999');
  head.setAttribute('stroke-width', '1.5');

  var body = document.createElementNS(ns, 'path');
  body.setAttribute('d', bodyPath);
  body.setAttribute('fill', 'none');
  body.setAttribute('stroke', '#999');
  body.setAttribute('stroke-width', '1.5');

  // piece rectangle
  var pieceX = 40;
  var pieceY = personBase - pieceHpx;
  var rect = document.createElementNS(ns, 'rect');
  rect.setAttribute('x', pieceX);
  rect.setAttribute('y', pieceY);
  rect.setAttribute('width', pieceWpx);
  rect.setAttribute('height', pieceHpx);
  rect.setAttribute('fill', 'none');
  rect.setAttribute('stroke', '#ccc');
  rect.setAttribute('stroke-width', '1');
  rect.setAttribute('stroke-dasharray', '4 2');

  // dimension labels
  var labelW = document.createElementNS(ns, 'text');
  labelW.setAttribute('x', pieceX + pieceWpx / 2);
  labelW.setAttribute('y', pieceY - 4);
  labelW.setAttribute('text-anchor', 'middle');
  labelW.setAttribute('fill', '#999');
  labelW.setAttribute('font-size', '10');
  labelW.textContent = cmW + 'cm';

  var labelH = document.createElementNS(ns, 'text');
  labelH.setAttribute('x', pieceX + pieceWpx + 6);
  labelH.setAttribute('y', pieceY + pieceHpx / 2);
  labelH.setAttribute('text-anchor', 'start');
  labelH.setAttribute('fill', '#999');
  labelH.setAttribute('font-size', '10');
  labelH.textContent = cmH + 'cm';

  svg.appendChild(head);
  svg.appendChild(body);
  svg.appendChild(rect);
  svg.appendChild(labelW);
  svg.appendChild(labelH);
  return svg;
}
