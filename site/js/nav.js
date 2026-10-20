/* ─── Menu button ──────────────────────────────────────────────────────── */
/* Below 1240px, and on touch-only screens, the nav links collapse into a
   panel (css/site.css, under .js). This only opens and closes it.          */
document.addEventListener('DOMContentLoaded', function () {
  var nav = document.querySelector('.site-nav');
  var toggle = nav && nav.querySelector('.nav-toggle');
  if (!toggle) return;
  var label = toggle.querySelector('.nav-toggle__label');

  function isOpen() { return toggle.getAttribute('aria-expanded') === 'true'; }

  function setOpen(open) {
    toggle.setAttribute('aria-expanded', String(open));
    if (label) label.textContent = open ? 'Close' : 'Menu';
    document.documentElement.classList.toggle('menu-open', open);
  }

  toggle.addEventListener('click', function () { setOpen(!isOpen()); });

  // ⌄ buttons expand a section's subpages (only shown in the collapsed menu)
  nav.querySelectorAll('.submenu-toggle').forEach(function (btn) {
    btn.addEventListener('click', function () {
      btn.setAttribute('aria-expanded', String(btn.getAttribute('aria-expanded') !== 'true'));
    });
  });

  // close on Esc, a click outside, or when focus leaves the menu
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && isOpen()) {
      setOpen(false);
      toggle.focus();
    }
  });
  document.addEventListener('click', function (e) {
    if (isOpen() && !nav.contains(e.target)) setOpen(false);
  });
  nav.addEventListener('focusout', function (e) {
    if (isOpen() && e.relatedTarget && !nav.contains(e.relatedTarget)) setOpen(false);
  });

  // back to the full row (same query as css/site.css)
  window.matchMedia('(max-width: 1240px), (hover: none) and (pointer: coarse)')
    .addEventListener('change', function (e) {
      if (!e.matches) setOpen(false);
    });
});
