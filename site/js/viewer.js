/* ─── Image Investigation Tool ─────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', init);

function init() {
  document.querySelectorAll('main img').forEach(function (img) {
    if (img.closest('.tile-grid')) return; // tile-grid.js opens these itself
    img.style.cursor = 'pointer';
    img.addEventListener('click', function () { openViewer(img); });
  });
}

/* ── state ─────────────────────────────────────────────────────────────── */
var overlay, canvas, ctx, navImg, loupe, fullImg, viewerEl, fullView;
var images = [], captions = [], currentIndex = 0;
// loupe side as a fraction of the image's shorter side; remembered per visitor
var LOUPE_MIN = 0.1, LOUPE_MAX = 0.8;
var loupeSize = readLoupeSize();
var loupeX = null, loupeY = null;  // last loupe centre, kept while resizing
var isMobile = false;

function openViewer(clickedImg) {
  images = [];
  captions = [];

  var gallery = clickedImg.closest('.gallery');
  if (gallery) {
    gallery.querySelectorAll('.gallery-item').forEach(function (item) {
      var img = item.querySelector('img');
      var cap = item.querySelector('figcaption');
      if (img) {
        images.push(img.src);
        captions.push(cap ? cap.textContent : '');
      }
    });
  } else {
    var fig = clickedImg.closest('figure');
    var cap = fig ? fig.querySelector('figcaption') : null;
    images.push(clickedImg.src);
    captions.push(cap ? cap.textContent : '');
  }

  currentIndex = images.indexOf(clickedImg.src);
  if (currentIndex < 0) currentIndex = 0;

  isMobile = window.matchMedia('(max-width: 768px)').matches;

  if (isMobile) {
    buildMobileModal();
  } else {
    buildModal();
  }

  loadImage(currentIndex);
  document.addEventListener('keydown', onKey);
  document.body.style.overflow = 'hidden';
}

/* ═══════════════════════════════════════════════════════════════════════ */
/* ── DESKTOP: inspector mode ──────────────────────────────────────────── */
/* ═══════════════════════════════════════════════════════════════════════ */

function buildModal() {
  overlay = document.createElement('div');
  overlay.className = 'viewer-overlay';
  overlay.addEventListener('click', function () {
    if (viewerEl.classList.contains('viewer--expanded')) {
      viewerEl.classList.remove('viewer--expanded');
    } else {
      closeViewer();
    }
  });

  viewerEl = document.createElement('div');
  viewerEl.className = 'viewer';

  // ── detail panel (left) ──
  var detailPanel = document.createElement('div');
  detailPanel.className = 'viewer-detail';
  canvas = document.createElement('canvas');
  fullView = document.createElement('img');
  fullView.className = 'viewer-fullview';
  fullView.alt = 'Full view';
  detailPanel.appendChild(canvas);
  detailPanel.appendChild(fullView);
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

  var expandBtn = document.createElement('button');
  expandBtn.className = 'viewer-btn viewer-expand';
  expandBtn.innerHTML = '&#x26F6; Full view';
  expandBtn.addEventListener('click', toggleExpand);

  // loupe size slider
  var sizeLabel = document.createElement('label');
  sizeLabel.className = 'viewer-loupe-size';
  var sizeText = document.createElement('span');
  sizeText.textContent = 'Loupe size';
  var sizeInput = document.createElement('input');
  sizeInput.type = 'range';
  sizeInput.min = String(LOUPE_MIN * 100);
  sizeInput.max = String(LOUPE_MAX * 100);
  sizeInput.step = '1';
  sizeInput.value = String(Math.round(loupeSize * 100));
  sizeInput.addEventListener('input', function () {
    setLoupeSize(sizeInput.value / 100);
  });
  sizeLabel.appendChild(sizeText);
  sizeLabel.appendChild(sizeInput);

  // scrolling over the navigator resizes the loupe too
  navWrap.addEventListener('wheel', function (e) {
    e.preventDefault();
    setLoupeSize(loupeSize + (e.deltaY < 0 ? -0.03 : 0.03));
    sizeInput.value = String(Math.round(loupeSize * 100));
  }, { passive: false });

  navPanel.appendChild(navWrap);
  navPanel.appendChild(captionEl);
  navPanel.appendChild(navButtons);
  navPanel.appendChild(sizeLabel);
  navPanel.appendChild(expandBtn);

  var stopBubble = function (e) { e.stopPropagation(); };
  detailPanel.addEventListener('click', stopBubble);
  navPanel.addEventListener('click', stopBubble);

  viewerEl.appendChild(detailPanel);
  viewerEl.appendChild(navPanel);
  overlay.appendChild(closeBtn);
  overlay.appendChild(viewerEl);
  document.body.appendChild(overlay);

  navWrap.addEventListener('mousemove', updateLoupe);
  navWrap.addEventListener('mousedown', function (e) { e.preventDefault(); updateLoupe(e); });
  navWrap.addEventListener('touchmove', function (e) {
    e.preventDefault();
    updateLoupe(e.touches[0]);
  }, { passive: false });
  navWrap.addEventListener('touchstart', function (e) {
    e.preventDefault();
    updateLoupe(e.touches[0]);
  }, { passive: false });
}

function loadImage(idx) {
  if (isMobile) {
    loadMobileImage(idx);
    return;
  }

  fullImg = new Image();
  fullImg.onload = function () {
    sizeCanvas();
    var rect = navImg.getBoundingClientRect();
    updateLoupeAt(rect.width / 2, rect.height / 2);
  };
  fullImg.src = images[idx];
  navImg.src = images[idx];
  fullView.src = images[idx];

  var cap = overlay.querySelector('.viewer-caption');
  cap.textContent = captions[idx] || '';

  overlay.querySelector('.viewer-prev').style.visibility = images.length > 1 ? 'visible' : 'hidden';
  overlay.querySelector('.viewer-next').style.visibility = images.length > 1 ? 'visible' : 'hidden';
}

function sizeCanvas() {
  var panel = canvas.parentElement;
  var side = Math.min(panel.clientWidth, panel.clientHeight) || 600;
  var res = Math.round(side * devicePixelRatio);
  canvas.width = res;
  canvas.height = res;
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
  loupeX = x;
  loupeY = y;

  // square, to match the square detail canvas (no stretching)
  var lw = Math.min(w, h) * loupeSize;
  var lh = lw;

  x = Math.max(lw / 2, Math.min(x, w - lw / 2));
  y = Math.max(lh / 2, Math.min(y, h - lh / 2));

  loupe.style.width = lw + 'px';
  loupe.style.height = lh + 'px';
  loupe.style.left = (x - lw / 2) + 'px';
  loupe.style.top = (y - lh / 2) + 'px';

  var scaleX = fullImg.naturalWidth / w;
  var scaleY = fullImg.naturalHeight / h;
  var sx = (x - lw / 2) * scaleX;
  var sy = (y - lh / 2) * scaleY;
  var sw = lw * scaleX;
  var sh = lh * scaleY;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(fullImg, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
}

function setLoupeSize(size) {
  loupeSize = Math.max(LOUPE_MIN, Math.min(LOUPE_MAX, size));
  try { localStorage.setItem('viewer-loupe-size', String(loupeSize)); } catch (e) { /* private mode */ }
  if (loupeX !== null) updateLoupeAt(loupeX, loupeY);
}

function readLoupeSize() {
  var saved = null;
  try { saved = parseFloat(localStorage.getItem('viewer-loupe-size')); } catch (e) { /* private mode */ }
  return saved >= LOUPE_MIN && saved <= LOUPE_MAX ? saved : 0.35;
}

function toggleExpand() {
  viewerEl.classList.toggle('viewer--expanded');
}

/* ═══════════════════════════════════════════════════════════════════════ */
/* ── MOBILE: lightbox with pinch/drag ─────────────────────────────────── */
/* ═══════════════════════════════════════════════════════════════════════ */

var mobileImg, mobileCaption;
var mScale = 1, mX = 0, mY = 0;           // current transform
var pinchStartDist = 0, pinchStartScale = 1;
var dragStartX = 0, dragStartY = 0, dragStartMX = 0, dragStartMY = 0;
var isDragging = false;
var swipeStartX = 0, swipeStartY = 0, swipeStartTime = 0;

function buildMobileModal() {
  overlay = document.createElement('div');
  overlay.className = 'viewer-overlay viewer-overlay--mobile';

  var closeBtn = document.createElement('button');
  closeBtn.className = 'viewer-btn viewer-close';
  closeBtn.textContent = '\u00d7';
  closeBtn.addEventListener('click', closeViewer);

  mobileImg = document.createElement('img');
  mobileImg.className = 'viewer-mobile-img';
  mobileImg.alt = '';

  mobileCaption = document.createElement('div');
  mobileCaption.className = 'viewer-mobile-caption';

  var navButtons = document.createElement('div');
  navButtons.className = 'viewer-mobile-nav';

  if (images.length > 1) {
    var prevBtn = document.createElement('button');
    prevBtn.className = 'viewer-btn viewer-prev';
    prevBtn.textContent = '\u2190';
    prevBtn.addEventListener('click', function (e) { e.stopPropagation(); navigate(-1); });

    var nextBtn = document.createElement('button');
    nextBtn.className = 'viewer-btn viewer-next';
    nextBtn.textContent = '\u2192';
    nextBtn.addEventListener('click', function (e) { e.stopPropagation(); navigate(1); });

    navButtons.appendChild(prevBtn);
    navButtons.appendChild(nextBtn);
  }

  overlay.appendChild(closeBtn);
  overlay.appendChild(mobileImg);
  overlay.appendChild(mobileCaption);
  overlay.appendChild(navButtons);
  document.body.appendChild(overlay);

  // ── touch gestures ──
  overlay.addEventListener('touchstart', mTouchStart, { passive: false });
  overlay.addEventListener('touchmove', mTouchMove, { passive: false });
  overlay.addEventListener('touchend', mTouchEnd, { passive: false });
}

function loadMobileImage(idx) {
  mScale = 1; mX = 0; mY = 0;
  mobileImg.src = images[idx];
  mobileImg.style.transform = '';
  mobileCaption.textContent = captions[idx] || '';
}

function mApplyTransform() {
  mobileImg.style.transform = 'translate(' + mX + 'px,' + mY + 'px) scale(' + mScale + ')';
}

function mTouchStart(e) {
  if (e.target.closest('.viewer-btn')) return;

  if (e.touches.length === 2) {
    // pinch start
    e.preventDefault();
    isDragging = false;
    pinchStartDist = mTouchDist(e);
    pinchStartScale = mScale;
  } else if (e.touches.length === 1) {
    e.preventDefault();
    var t = e.touches[0];
    swipeStartX = t.clientX;
    swipeStartY = t.clientY;
    swipeStartTime = Date.now();

    if (mScale > 1.05) {
      // drag/pan when zoomed
      isDragging = true;
      dragStartX = t.clientX;
      dragStartY = t.clientY;
      dragStartMX = mX;
      dragStartMY = mY;
    } else {
      isDragging = false;
    }
  }
}

function mTouchMove(e) {
  if (e.target.closest('.viewer-btn')) return;
  e.preventDefault();

  if (e.touches.length === 2) {
    // pinch zoom
    var dist = mTouchDist(e);
    mScale = Math.max(1, Math.min(pinchStartScale * (dist / pinchStartDist), 8));
    if (mScale <= 1.05) { mX = 0; mY = 0; }
    mApplyTransform();
  } else if (e.touches.length === 1 && isDragging) {
    // drag pan
    var t = e.touches[0];
    mX = dragStartMX + (t.clientX - dragStartX);
    mY = dragStartMY + (t.clientY - dragStartY);
    mApplyTransform();
  }
}

function mTouchEnd(e) {
  if (e.target.closest('.viewer-btn')) return;

  if (e.touches.length === 0 && !isDragging && mScale <= 1.05) {
    var elapsed = Date.now() - swipeStartTime;
    var dx = (e.changedTouches[0] ? e.changedTouches[0].clientX : swipeStartX) - swipeStartX;
    var dy = (e.changedTouches[0] ? e.changedTouches[0].clientY : swipeStartY) - swipeStartY;

    if (elapsed < 300 && Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) {
      // swipe
      navigate(dx < 0 ? 1 : -1);
    } else if (elapsed < 200 && Math.abs(dx) < 15 && Math.abs(dy) < 15) {
      // tap → close
      closeViewer();
    }
  }

  if (e.touches.length < 2) {
    isDragging = false;
  }

  // snap back to 1 if nearly there
  if (mScale <= 1.05) {
    mScale = 1; mX = 0; mY = 0;
    mApplyTransform();
  }
}

function mTouchDist(e) {
  var a = e.touches[0], b = e.touches[1];
  return Math.hypot(b.clientX - a.clientX, b.clientY - a.clientY);
}

/* ═══════════════════════════════════════════════════════════════════════ */
/* ── shared ───────────────────────────────────────────────────────────── */
/* ═══════════════════════════════════════════════════════════════════════ */

function navigate(dir) {
  currentIndex = (currentIndex + dir + images.length) % images.length;
  loadImage(currentIndex);
}

function onKey(e) {
  // arrow keys on the slider adjust it instead of changing image
  if (e.target && e.target.tagName === 'INPUT' && e.key !== 'Escape') return;
  if (e.key === 'Escape') {
    if (!isMobile && viewerEl && viewerEl.classList.contains('viewer--expanded')) {
      viewerEl.classList.remove('viewer--expanded');
    } else {
      closeViewer();
    }
  }
  else if (e.key === 'ArrowLeft') navigate(-1);
  else if (e.key === 'ArrowRight') navigate(1);
}

function closeViewer() {
  document.removeEventListener('keydown', onKey);
  document.body.style.overflow = '';
  if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
  overlay = null;
}
