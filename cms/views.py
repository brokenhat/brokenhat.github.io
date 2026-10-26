"""The admin's pages: dashboard, editors, uploads, preview, publish."""

from __future__ import annotations

import mimetypes
import re

from flask import (Blueprint, Response, abort, flash, jsonify, redirect,
                   render_template, request, send_file, url_for)
from markupsafe import Markup

from . import ai, config, content, images, publish
from .auth import login_required

bp = Blueprint("main", __name__, url_prefix="/admin")


def saved(message: str = "Saved.") -> None:
    changed = publish.regenerate()
    flash(message + (" Not online yet: Publish when you're ready." if changed or publish.unpublished() else ""))


# ─── dashboard ───────────────────────────────────────────────────────────

@bp.route("/")
@login_required
def dashboard():
    return render_template("dashboard.html", pages=content.pages(), issues=content.issues(),
                           pending=publish.unpublished(), job=publish.job)


# ─── form helpers ────────────────────────────────────────────────────────

def form_str(name: str) -> str:
    return (request.form.get(name) or "").replace("\r\n", "\n").strip()


def form_text(name: str) -> str:
    """Multi-line text ends with a newline, like the files it came from."""
    t = form_str(name)
    return t + "\n" if t else ""


def form_images(prefix: str) -> list[dict]:
    """Image cards in their order on the page: prefix-file/alt/caption lists."""
    files = request.form.getlist(f"{prefix}-file")
    alts = request.form.getlist(f"{prefix}-alt")
    caps = request.form.getlist(f"{prefix}-caption")
    out = []
    for i, f in enumerate(files):
        if not f or "/" in f or f.startswith("."):
            continue
        img = {"file": f, "alt": (alts[i] if i < len(alts) else "").strip()}
        cap = (caps[i] if i < len(caps) else "").strip()
        if cap:
            img["caption"] = cap
        out.append(img)
    return out


SEO = ["seo_title", "description"]


# ─── home page ───────────────────────────────────────────────────────────

@bp.route("/home", methods=["GET", "POST"])
@login_required
def home():
    d = content.home()
    if request.method == "POST":
        for k in ["title", "heading", "heading_pl", *SEO]:
            d[k] = form_str(k)
        d["text"] = form_text("text")
        d["text_pl"] = form_text("text_pl")
        content.save_home(d)
        saved()
        return redirect(url_for(".home"))
    return render_template("home.html", d=d)


# ─── section pages ───────────────────────────────────────────────────────

def get_page(slug: str) -> content.Page:
    try:
        return content.page(slug)
    except KeyError:
        abort(404)


@bp.route("/pages/<slug>", methods=["GET", "POST"])
@login_required
def page(slug: str):
    p = get_page(slug)
    template = {"exhibition": "exhibition.html", "works": "works.html",
                "gallery": "gallery.html", "cv": "cv.html"}[p.type]
    if request.method == "POST":
        d = p.data
        for k in ["title", *SEO]:
            d[k] = form_str(k)
        if p.type == "exhibition":
            for k in ["subtitle", "start", "end", "venue", "street", "locality", "postcode", "country"]:
                d[k] = form_str(k)
            d["text"] = form_text("text")
            imgs = form_images("image")
            d["image"] = imgs[0] if imgs else None
        elif p.type == "works":
            d["intro"] = form_text("intro")
            order = [s for s in request.form.getlist("piece") if content.SLUG.match(s)]
            if sorted(order) == sorted(d.get("pieces", [])):
                d["pieces"] = order
        elif p.type == "gallery":
            d["intro"] = form_text("intro")
            groups = []
            for gi in range(int(request.form.get("groups", "0"))):
                g = {"heading": form_str(f"g{gi}-heading"), "images": form_images(f"g{gi}")}
                if g["images"] or g["heading"]:
                    groups.append(content.clean(g))
            d["groups"] = groups or [{"images": []}]
        elif p.type == "cv":
            d["intro"] = form_text("intro")
            sections = []
            for si in range(int(request.form.get("sections", "0"))):
                heading = form_str(f"s{si}-heading")
                whens = request.form.getlist(f"s{si}-when")
                texts = request.form.getlist(f"s{si}-text")
                entries = [{"when": w.strip(), "text": t.strip()} for w, t in zip(whens, texts)
                           if w.strip() or t.strip()]
                if heading or entries:
                    sections.append({"heading": heading, "entries": entries})
            d["sections"] = sections
        content.save_page(p)
        saved()
        return redirect(url_for(".page", slug=slug))
    extra = {}
    if p.type == "works":
        extra["pieces"] = content.pieces(p)
    return render_template(template, p=p, d=p.data, **extra)


# ─── pieces ──────────────────────────────────────────────────────────────

FIELDS = [("year", "Year", "e.g. 2025 or 07.2025"),
          ("technique", "Technique", "e.g. tapestry, wet-felted"),
          ("fibre", "Fibre", "e.g. wool on cotton"),
          ("medium", "Medium", "e.g. watercolour, wool, silk on cotton warp"),
          ("warp", "Warp", "e.g. cotton (20/12), 10 EPI"),
          ("dimensions", "Dimensions", "e.g. 46cm x 75cm"),
          ("exhibition", "Exhibited", "where and when it was shown"),
          ("award", "Award", "")]


@bp.route("/pages/<slug>/new", methods=["POST"])
@login_required
def new_piece(slug: str):
    p = get_page(slug)
    title = form_str("title")
    if p.type != "works" or not title:
        flash("Give the new piece a title.")
        return redirect(url_for(".page", slug=slug))
    pc = content.new_piece(p, title)
    saved("Created. Add its photos and details, then Save.")
    return redirect(url_for(".piece", slug=slug, piece_slug=pc.slug))


@bp.route("/pages/<slug>/<piece_slug>", methods=["GET", "POST"])
@login_required
def piece(slug: str, piece_slug: str):
    section = get_page(slug)
    try:
        pc = content.piece(slug, piece_slug)
    except KeyError:
        abort(404)
    if request.method == "POST":
        d = pc.data
        for k in ["title", "full_title", "card_title", *SEO, *[f[0] for f in FIELDS]]:
            d[k] = form_str(k)
        d["text"] = form_text("text")
        main = form_images("image")
        d["image"] = main[0] if main else None
        d["details"] = form_images("details")
        d["journal"] = request.form.get("journal") == "on" or None
        content.save_piece(pc)
        saved()
        return redirect(url_for(".piece", slug=slug, piece_slug=piece_slug))
    return render_template("piece.html", section=section, pc=pc, d=pc.data, fields=FIELDS)


@bp.route("/pages/<slug>/<piece_slug>/delete", methods=["POST"])
@login_required
def delete_piece(slug: str, piece_slug: str):
    section = get_page(slug)
    content.delete_piece(section, piece_slug)
    saved("Deleted. It disappears from the site when you publish.")
    return redirect(url_for(".page", slug=slug))


# ─── images ──────────────────────────────────────────────────────────────

def folder_for(owner: str) -> tuple:
    """owner is "page:<slug>" or "piece:<section>/<slug>"."""
    try:
        kind, _, rest = owner.partition(":")
        if kind == "page":
            p = content.page(rest)
            return p.image_folder, p.image_url
        if kind == "piece":
            section, _, slug = rest.partition("/")
            pc = content.piece(section, slug)
            return pc.image_folder, pc.image_url
    except KeyError:
        pass
    abort(400)


@bp.route("/upload", methods=["POST"])
@login_required
def upload():
    folder, url = folder_for(request.form.get("owner", ""))
    prefix = request.form.get("prefix", "")
    if not re.match(r"^[a-z0-9-]+$", prefix):
        abort(400)
    cards, errors = [], []
    for f in request.files.getlist("files"):
        try:
            name = images.store_upload(f.read(), f.filename or "image", folder)
            cards.append(render_template("_image_card.html", prefix=prefix, img={"file": name, "alt": ""},
                                         url=url, captions=request.form.get("captions") == "1"))
        except images.NotAnImage as e:
            errors.append(str(e))
    html = "".join(cards)
    if errors:
        html += "".join(f'<p class="upload-error">{Markup.escape(e)}</p>' for e in errors)
    return Response(html, mimetype="text/html")


@bp.route("/img/<path:site_path>")
@login_required
def img(site_path: str):
    f = images.preview(site_path)
    if not f:
        abort(404)
    return send_file(f, mimetype="image/jpeg", max_age=3600)


# ─── preview: the working copy, as visitors will see it ──────────────────

PREVIEW_TYPES = {".html", ".css", ".js", ".jpg", ".jpeg", ".png", ".svg", ".ico", ".gif", ".webp", ".xml"}
_URL_ATTR = re.compile(r'(\s(?:href|src|data-full|data-large|data-sketch-src)=")/(?!/)')
_SRCSET = re.compile(r'(\ssrcset=")([^"]*)"')


def _prefix_html(html: str) -> str:
    """Site links point at the live site's root; keep them in the preview."""
    html = _URL_ATTR.sub(r"\1/admin/preview/", html)
    return _SRCSET.sub(lambda m: m.group(1) + re.sub(r"(^|,\s*)/", r"\1/admin/preview/", m.group(2)) + '"', html)


@bp.route("/preview/render", methods=["POST"])
@login_required
def render_preview():
    try:
        publish.render_preview()
    except publish.PublishError as e:
        return jsonify(ok=False, error=str(e)[-2000:]), 500
    return jsonify(ok=True)


@bp.route("/preview/", defaults={"path": ""})
@bp.route("/preview/<path:path>")
@login_required
def preview(path: str):
    target = (config.SITE / path).resolve()
    if config.SITE != target and config.SITE not in target.parents:
        abort(404)
    if target.is_dir():
        target = target / "index.html"
    if target.suffix.lower() not in PREVIEW_TYPES or not target.is_file():
        abort(404)
    if target.suffix == ".html":
        html = target.read_text(encoding="utf-8")
        banner = ('<div style="position:fixed;bottom:12px;left:12px;z-index:9999;background:#c04000;color:#fff;'
                  'font:13px/1.4 sans-serif;padding:6px 10px;border-radius:4px">Preview · not published</div>')
        html = _prefix_html(html).replace("</body>", banner + "</body>", 1)
        return Response(html, mimetype="text/html", headers={"X-Preview": "1"})
    return send_file(target, mimetype=mimetypes.guess_type(target.name)[0], max_age=0)


# ─── suggestions from Claude ─────────────────────────────────────────────

@bp.route("/suggest/alt", methods=["POST"])
@login_required
def suggest_alt():
    data = request.get_json(silent=True) or {}
    try:
        return jsonify(ok=True, text=ai.alt_text(str(data.get("path", "")), str(data.get("context", ""))[:300]))
    except ai.Unavailable as e:
        return jsonify(ok=False, error=str(e))


@bp.route("/suggest/description", methods=["POST"])
@login_required
def suggest_description():
    data = request.get_json(silent=True) or {}
    try:
        return jsonify(ok=True, text=ai.page_description(str(data.get("title", ""))[:300],
                                                         str(data.get("details", ""))))
    except ai.Unavailable as e:
        return jsonify(ok=False, error=str(e))


# ─── publish, history, undo ──────────────────────────────────────────────

@bp.route("/publish", methods=["POST"])
@login_required
def start_publish():
    if not publish.start_publish(form_str("note")):
        flash("A publish is already running.")
    return redirect(url_for(".dashboard"))


@bp.route("/publish/status")
@login_required
def publish_status():
    resp = Response(render_template("_publish_status.html", job=publish.job))
    if publish.job.state != "running" and request.headers.get("HX-Request"):
        resp.headers["HX-Refresh"] = "true"     # finished: show the page as it is now
    return resp


@bp.route("/history")
@login_required
def history():
    return render_template("history.html", changes=publish.history(), job=publish.job,
                           pending=publish.unpublished())


@bp.route("/history/<commit>/undo", methods=["POST"])
@login_required
def undo(commit: str):
    if not re.match(r"^[0-9a-f]{40}$", commit):
        abort(400)
    if not publish.start_undo(commit):
        flash("A publish is already running.")
    return redirect(url_for(".history"))
