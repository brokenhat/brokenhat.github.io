/* ─── CMS editor behaviour ─────────────────────────────────────────────
   Drag to reorder (SortableJS), drop photos to upload, add/remove groups
   and CV lines, "Save & preview", counters for the Google fields, and a
   warning before leaving with unsaved changes. No inline scripts: the
   admin's Content-Security-Policy only allows this file.              */
(function () {
  'use strict';

  const csrf = document.querySelector('meta[name="csrf-token"]').content;
  let dirty = false;

  document.addEventListener('DOMContentLoaded', function () {
    init(document);
    bindEditor();
    bindConfirm();
  });

  // everything that can appear later (new groups, uploaded cards) goes
  // through init(root)
  function init(root) {
    root.querySelectorAll('[data-sortable]').forEach(function (el) {
      if (el._sortable) return;
      el._sortable = Sortable.create(el, {
        handle: '.handle', animation: 150, ghostClass: 'ghost',
        onEnd: function () { dirty = true; }
      });
    });
    root.querySelectorAll('.images').forEach(bindUploads);
    root.querySelectorAll('input[name="seo_title"], textarea[name="description"]').forEach(counter);
  }

  /* ── uploads ─────────────────────────────────────────────────────── */

  function bindUploads(box) {
    if (box._bound) return;
    box._bound = true;
    const input = box.querySelector('[data-upload]');
    const drop = box.querySelector('.drop');
    input.addEventListener('change', function () {
      if (input.files.length) upload(box, input.files);
      input.value = '';
    });
    ['dragenter', 'dragover'].forEach(function (t) {
      drop.addEventListener(t, function (e) {
        if (!hasFiles(e)) return;
        e.preventDefault();
        drop.classList.add('over');
      });
    });
    ['dragleave', 'drop'].forEach(function (t) {
      drop.addEventListener(t, function () { drop.classList.remove('over'); });
    });
    drop.addEventListener('drop', function (e) {
      if (!hasFiles(e)) return;
      e.preventDefault();
      upload(box, e.dataTransfer.files);
    });
  }

  function hasFiles(e) {
    return e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types, 'Files') >= 0;
  }

  function upload(box, files) {
    const max = Number(box.dataset.max || 0);
    const list = box.querySelector('.img-list');
    const status = box.querySelector('.drop > span');
    const label = status.innerHTML;
    const form = new FormData();
    const chosen = max === 1 ? [files[0]] : Array.from(files);
    chosen.forEach(function (f) { form.append('files', f); });
    form.append('owner', box.dataset.owner);
    form.append('prefix', box.dataset.prefix);
    form.append('captions', box.dataset.captions);
    box.classList.add('busy');
    status.textContent = 'Uploading ' + chosen.length + ' photo' + (chosen.length === 1 ? '' : 's') + '…';
    fetch('/admin/upload', { method: 'POST', body: form, headers: { 'X-CSRFToken': csrf } })
      .then(function (r) {
        if (!r.ok) throw new Error(r.status === 413 ? 'too big' : 'status ' + r.status);
        return r.text();
      })
      .then(function (html) {
        const tmp = document.createElement('div');
        tmp.innerHTML = html;
        box.querySelectorAll('.upload-error').forEach(function (e) { e.remove(); });
        tmp.querySelectorAll('.upload-error').forEach(function (e) { box.appendChild(e); });
        const cards = tmp.querySelectorAll('.img-card');
        if (max === 1 && cards.length) list.innerHTML = '';
        cards.forEach(function (c) { list.appendChild(c); });
        if (cards.length) {
          dirty = true;
          flash('Uploaded. Describe ' + (cards.length === 1 ? 'the photo' : 'the photos') + ', then Save.');
          const first = cards[0].querySelector('[data-alt]');
          if (first) first.focus();
        }
      })
      .catch(function (err) { flash('Upload failed (' + err.message + '). Try again, or fewer photos at once.'); })
      .finally(function () {
        box.classList.remove('busy');
        status.innerHTML = label;
      });
  }

  /* ── editing ─────────────────────────────────────────────────────── */

  function bindEditor() {
    const form = document.querySelector('[data-editor]');
    if (!form) return;

    form.addEventListener('input', function () { dirty = true; });
    form.addEventListener('submit', function () { dirty = false; });
    window.addEventListener('beforeunload', function (e) {
      if (dirty) { e.preventDefault(); e.returnValue = ''; }
    });
    document.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        dirty = false;
        form.requestSubmit();
      }
    });

    form.addEventListener('click', function (e) {
      const t = e.target;
      if (t.closest('[data-remove]')) {
        t.closest('.img-card').remove();
        dirty = true;
      } else if (t.closest('[data-remove-entry]')) {
        t.closest('.entry').remove();
        dirty = true;
      } else if (t.closest('[data-add-entry]')) {
        const section = t.closest('[data-section]');
        const tpl = form.querySelector('[data-entry-template]');
        add(section.querySelector('.entries'), tpl, section.dataset.section).querySelector('input, textarea').focus();
      } else if (t.closest('[data-add-section]')) {
        addNumbered(form, 'sections', '[data-sections]', '[data-section-template]');
      } else if (t.closest('[data-add-group]')) {
        addNumbered(form, 'groups', '[data-groups]', '[data-group-template]');
      } else if (t.closest('[data-suggest-alt]')) {
        suggestAlt(t.closest('[data-suggest-alt]'));
      } else if (t.closest('[data-suggest-desc]')) {
        suggestDescription(form, t.closest('[data-suggest-desc]'));
      } else if (t.closest('[data-preview]')) {
        saveAndPreview(form, t.closest('[data-preview]').dataset.preview);
      }
    });
  }

  // a copy of a <template>, with __N__ replaced
  function add(parent, tpl, n) {
    const tmp = document.createElement('div');
    tmp.innerHTML = tpl.innerHTML.replace(/__N__/g, n);
    const el = tmp.firstElementChild;
    parent.appendChild(el);
    init(el);
    dirty = true;
    return el;
  }

  // a new numbered block (gallery group, CV section) and its count field
  function addNumbered(form, countName, parentSel, tplSel) {
    const count = form.querySelector('[data-count-of="' + countName + '"]');
    const n = Number(count.value);
    count.value = String(n + 1);
    const el = add(form.querySelector(parentSel), form.querySelector(tplSel), n);
    const first = el.querySelector('input:not([type="hidden"])');
    if (first) first.focus();
  }

  function saveAndPreview(form, url) {
    // opened now, while the click still counts, or browsers block it
    const win = window.open('', '_blank');
    if (win) win.document.write('Building the preview…');
    flash('Saving and building the preview…');
    fetch(form.action || location.href, { method: 'POST', body: new FormData(form), headers: { 'X-CSRFToken': csrf } })
      .then(function (r) {
        if (!r.ok) throw new Error('save failed (' + r.status + ')');
        dirty = false;
        return fetch('/admin/preview/render', { method: 'POST', headers: { 'X-CSRFToken': csrf } });
      })
      .then(function (r) { return r.json(); })
      .then(function (res) {
        if (!res.ok) throw new Error(res.error || 'preview failed');
        const target = '/admin/preview' + url;
        if (win) win.location = target; else location = target;
        flash('Saved. The preview opened in a new tab.');
      })
      .catch(function (err) {
        if (win) win.close();
        flash('Something went wrong: ' + err.message);
      });
  }

  /* ── suggestions from Claude ────────────────────────────────────── */

  function ask(url, body, button, done) {
    const label = button.textContent;
    button.textContent = 'Thinking…';
    button.classList.add('thinking');
    fetch(url, { method: 'POST', body: JSON.stringify(body),
                 headers: { 'X-CSRFToken': csrf, 'Content-Type': 'application/json' } })
      .then(function (r) { return r.json(); })
      .then(function (res) {
        if (!res.ok) throw new Error(res.error);
        done(res.text);
        dirty = true;
      })
      .catch(function (err) { flash(err.message || 'No suggestion this time.'); })
      .finally(function () {
        button.textContent = label;
        button.classList.remove('thinking');
      });
  }

  // fill a field, but ask before replacing something already written
  function fill(field, text) {
    if (field.value.trim() && field.value.trim() !== text &&
        !window.confirm('Replace what is there with:\n\n' + text)) return;
    field.value = text;
    field.dispatchEvent(new Event('input', { bubbles: true }));
    field.focus();
  }

  function pageTitle() {
    const t = document.querySelector('[data-editor] input[name="title"]');
    return t ? t.value : document.title;
  }

  function suggestAlt(button) {
    const card = button.closest('.img-card');
    ask('/admin/suggest/alt', { path: button.dataset.suggestAlt, context: pageTitle() }, button,
        function (text) { fill(card.querySelector('[data-alt]'), text); });
  }

  function suggestDescription(form, button) {
    // the page's own words: its text fields, details and picture descriptions
    const parts = [];
    form.querySelectorAll('textarea[name="text"], textarea[name="text_pl"], textarea[name="intro"], ' +
                          '.grid2 input, input[name="subtitle"], [data-alt]').forEach(function (f) {
      const v = f.value.trim();
      if (!v) return;
      const label = f.closest('label');
      parts.push((label ? label.firstChild.textContent.trim() + ': ' : '') + v);
    });
    ask('/admin/suggest/description', { title: pageTitle(), details: parts.join('\n') }, button,
        function (text) { fill(form.querySelector('textarea[name="description"]'), text); });
  }

  /* ── small things ────────────────────────────────────────────────── */

  function counter(field) {
    if (field._counter) return;
    const max = field.name === 'seo_title' ? 60 : 160;
    const out = document.createElement('span');
    out.className = 'counter';
    field.insertAdjacentElement('afterend', out);
    field._counter = out;
    const update = function () {
      const n = field.value.length;
      out.textContent = n ? n + ' / ' + max : '';
      out.classList.toggle('over', n > max);
    };
    field.addEventListener('input', update);
    update();
  }

  function bindConfirm() {
    document.querySelectorAll('form[data-confirm]').forEach(function (f) {
      f.addEventListener('submit', function (e) {
        if (!window.confirm(f.dataset.confirm)) e.preventDefault();
        else dirty = false;
      });
    });
  }

  function flash(text) {
    let box = document.querySelector('.flash');
    if (!box) {
      box = document.createElement('div');
      box.className = 'flash';
      box.setAttribute('role', 'status');
      document.querySelector('main').prepend(box);
    }
    box.innerHTML = '';
    const p = document.createElement('p');
    p.textContent = text;
    box.appendChild(p);
  }
})();
