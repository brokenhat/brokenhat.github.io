"""Generate the site's Pollen pages from the content files.

content/ holds what the CMS edits (YAML, one file per page or piece);
this writes the .pm pages and index.ptree that Pollen renders. Generated
files start with a "do not edit" line and are listed in
site/.generated, so pages removed from content/ are removed from site/.

Text fields use a small markup: a blank line starts a paragraph, a
single line break stays a line break, **bold**, *italic*, and
[text](/path/ or https://...). Anything Pollen would read as a command
(£ and braces) is escaped.

    python -m cms.sitegen            # from the repository root
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

# the repository to work on: this one, unless the CMS says otherwise
DEFAULT_ROOT = Path(__file__).resolve().parent.parent
HEADER = "£; generated from content/ by the CMS (cms/sitegen.py), edit it there\n"


# ─── text → Pollen ───────────────────────────────────────────────────────

def esc_text(s: str) -> str:
    """Plain text inside a Pollen body: £ and braces become literals."""
    return (s.replace("£", "\0P").replace("{", "\0L").replace("}", "\0R")
             .replace("\0P", '£(values "£")')
             .replace("\0L", '£(values "{")')
             .replace("\0R", '£(values "}")'))


def esc_str(s: str) -> str:
    """A Racket string literal, quotes included."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


INLINE = re.compile(
    r"\[(?P<ltext>[^\]]+)\]\((?P<url>[^)\s]+)\)"   # [text](url)
    r"|\*\*(?P<bold>.+?)\*\*"                       # **bold**
    r"|\*(?P<em>[^*\n]+?)\*"                        # *italic*
)


def page_href(url: str) -> str:
    """Site links are written clean (/textiles/x/); Pollen's dev server
    needs index.html, and the published build cleans them again."""
    if url.startswith("/") and url.endswith("/") and url != "/":
        return url + "index.html"
    if url == "/":
        return "/index.html"
    return url


def inline(s: str) -> str:
    out, pos = [], 0
    for m in INLINE.finditer(s):
        out.append(esc_text(s[pos:m.start()]))
        if m.group("ltext") is not None:
            url = m.group("url")
            tag = "link" if url.startswith("/") else "ext-link"
            out.append(f"£{tag}[{esc_str(page_href(url))}]{{{inline(m.group('ltext'))}}}")
        elif m.group("bold") is not None:
            out.append(f"£strong{{{inline(m.group('bold'))}}}")
        else:
            out.append(f"£em{{{inline(m.group('em'))}}}")
        pos = m.end()
    out.append(esc_text(s[pos:]))
    return "".join(out)


def text(s: str | None) -> str:
    """Multi-paragraph text: paragraphs kept apart by one blank line."""
    if not s:
        return ""
    paras = [p.strip("\n") for p in re.split(r"\n\s*\n", s.strip()) if p.strip()]
    return "\n\n".join(inline(p) for p in paras)


# ─── pieces of markup ────────────────────────────────────────────────────

def metas(**kv) -> str:
    lines = []
    for k, v in kv.items():
        if v not in (None, ""):
            lines.append(f"£(define-meta {k.replace('_', '-')} {esc_str(str(v))})")
    return "\n".join(lines)


def fig(path: str, img: dict) -> str:
    alt = img.get("alt") or ""
    cap = inline(img.get("caption") or "")
    return f"£fig[{esc_str(path)} #:alt {esc_str(alt)}]{{{cap}}}"


def gallery(folder: str, images: list[dict]) -> str:
    figs = "\n".join(fig(f"{folder}/{i['file']}", i) for i in images)
    return f"£gallery{{\n{figs}\n}}"


def attrs(**kv) -> str:
    parts = [f"#:{k} {esc_str(str(v))}" for k, v in kv.items() if v not in (None, "")]
    return ("\n       ".join(parts))


# ─── page types ──────────────────────────────────────────────────────────

def home(d: dict) -> str:
    out = [metas(title=d.get("title"), seo_title=d.get("seo_title"),
                 description=d.get("description")), ""]
    if d.get("heading"):
        out += [f'£h1[#:class "visually-hidden"]{{{inline(d["heading"])}}}', ""]
    out += [f"£section-intro{{\n{text(d.get('text'))}\n}}"]
    if d.get("text_pl"):
        out += ["", '£div[#:class "section-intro" #:lang "pl"]{',
                f"£h2{{{inline(d.get('heading_pl') or 'Po polsku')}}}", "",
                text(d["text_pl"]), "}"]
    return "\n".join(out) + "\n"


def exhibition(slug: str, d: dict) -> str:
    folder = f"/{slug}/images"
    out = ['£(define-meta layout "piece")',
           metas(title=d["title"], seo_title=d.get("seo_title"), description=d.get("description"),
                 event_start=d.get("start"), event_end=d.get("end"), event_venue=d.get("venue"),
                 event_street=d.get("street"), event_locality=d.get("locality"),
                 event_postcode=d.get("postcode"), event_country=d.get("country")),
           "",
           f"£piece[{attrs(title=d['title'], exhibition=d.get('subtitle'))}]{{",
           ""]
    if d.get("image"):
        img = d["image"]
        out += [f"£image[{esc_str(folder + '/' + img['file'])} #:alt {esc_str(img.get('alt') or d['title'])} "
                f'#:class "hero"]{{}}', ""]
    out += [text(d.get("text")), "}"]
    return "\n".join(out) + "\n"


PIECE_FIELDS = ["year", "technique", "fibre", "warp", "weft", "medium",
                "dimensions", "exhibition", "award", "status"]


def piece(section: str, slug: str, d: dict) -> str:
    folder = f"/{section}/{slug}/images"
    fields = {k: d.get(k) for k in PIECE_FIELDS}
    out = ['£(define-meta layout "piece")',
           metas(title=d["title"], seo_title=d.get("seo_title"), description=d.get("description")),
           "",
           f"£piece[{attrs(title=d.get('full_title') or d['title'], **fields)}]{{",
           ""]
    if d.get("image"):
        img = d["image"]
        out += [f"£image[{esc_str(folder + '/' + img['file'])} #:alt {esc_str(img.get('alt') or d['title'])} "
                f'#:class "hero"]{{}}', ""]
    if d.get("text"):
        out += [text(d["text"]), ""]
    if d.get("details"):
        out += ['£h2[#:class "section-label"]{Process & details}', "",
                gallery(folder, d["details"]), ""]
    if d.get("journal"):
        out += [f'£git-timeline[{esc_str(section + "/" + slug)}]', ""]
    out.append("}")
    return "\n".join(out) + "\n"


def works(section: str, d: dict, pieces: dict[str, dict]) -> str:
    out = [metas(title=d["title"], seo_title=d.get("seo_title"), description=d.get("description")), "",
           f"£title{{{inline(d['title'])}}}", ""]
    if d.get("intro"):
        out += [f"£section-intro{{\n{text(d['intro'])}\n}}", ""]
    out.append("£works{")
    for slug in d.get("pieces", []):
        p = pieces[slug]
        if not p.get("image"):
            continue
        out.append(f"£work[{esc_str(f'/{section}/{slug}/index.html')} "
                   f"#:image {esc_str(f'/{section}/{slug}/images/' + p['image']['file'])} "
                   f"#:title {esc_str(p.get('card_title') or p['title'])} "
                   f"#:year {esc_str(str(p.get('card_year') or year_of(p.get('year'))))}]")
    out.append("}")
    return "\n".join(out) + "\n"


def year_of(y) -> str:
    m = re.search(r"\d{4}", str(y or ""))
    return m.group(0) if m else ""


def gallery_page(slug: str, d: dict) -> str:
    folder = f"/{slug}/images"
    out = [metas(title=d["title"], seo_title=d.get("seo_title"), description=d.get("description")), "",
           f"£title{{{inline(d['title'])}}}", ""]
    if d.get("intro"):
        out += [f"£section-intro{{\n{text(d['intro'])}\n}}", ""]
    for g in d.get("groups", []):
        if g.get("heading"):
            out += [f"£h2{{{inline(g['heading'])}}}", ""]
        out += [gallery(folder, g.get("images", [])), ""]
    return "\n".join(out).rstrip("\n") + "\n"


def cv(d: dict) -> str:
    out = [metas(title=d["title"], seo_title=d.get("seo_title"), description=d.get("description")), "",
           f"£title{{{inline(d['title'])}}}", ""]
    if d.get("intro"):
        out += [f"£section-intro{{\n{text(d['intro'])}\n}}", ""]
    for sec in d.get("sections", []):
        out.append(f"£cv-section[{esc_str(sec['heading'])}]{{")
        for e in sec.get("entries", []):
            out.append(f"£cv-entry[#:year {esc_str(str(e.get('when') or ''))}]{{{inline(e.get('text') or '')}}}")
        out += ["}", ""]
    return "\n".join(out).rstrip("\n") + "\n"


# ─── the whole site ──────────────────────────────────────────────────────

def load(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def build(root: Path = DEFAULT_ROOT) -> dict[str, str]:
    """{site-relative path: file text} for every generated file."""
    content = root / "content"
    files: dict[str, str] = {}
    site = load(content / "site.yaml")
    files["index.html.pm"] = home(load(content / "home.yaml"))
    tree = ["index.html"]
    for slug in site.get("menu", []):
        d = load(content / "pages" / f"{slug}.yaml")
        kind = d.get("type")
        if kind == "exhibition":
            files[f"{slug}/index.html.pm"] = exhibition(slug, d)
            tree.append(f"{slug}/index.html")
        elif kind == "works":
            pieces = {p: load(content / slug / f"{p}.yaml") for p in d.get("pieces", [])}
            files[f"{slug}/index.html.pm"] = works(slug, d, pieces)
            tree.append(f"{slug}/index.html")
            for p, pd in pieces.items():
                files[f"{slug}/{p}/index.html.pm"] = piece(slug, p, pd)
                tree.append(f"  {slug}/{p}/index.html")
        elif kind == "gallery":
            files[f"{slug}/index.html.pm"] = gallery_page(slug, d)
            tree.append(f"{slug}/index.html")
        elif kind == "cv":
            files[f"{slug}.html.pm"] = cv(d)
            tree.append(f"{slug}.html")
        else:
            raise ValueError(f"content/pages/{slug}.yaml: unknown type {kind!r}")
    files = {k: "#lang pollen\n" + HEADER + v for k, v in files.items()}
    files["index.ptree"] = "#lang pollen\n" + HEADER + "\n" + "\n".join(tree) + "\n"
    return files


def write(files: dict[str, str], root: Path = DEFAULT_ROOT) -> list[str]:
    """Write changed files, remove ones no longer generated. Returns what changed."""
    site = root / "site"
    manifest = site / ".generated"
    old = set(manifest.read_text().split()) if manifest.exists() else set()
    changed = []
    for rel, body in files.items():
        p = site / rel
        if not p.exists() or p.read_text(encoding="utf-8") != body:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
            changed.append(rel)
    for rel in sorted(old - set(files)):
        p = site / rel
        if p.exists() and p.read_text(encoding="utf-8").startswith("#lang pollen\n" + HEADER):
            p.unlink()
            changed.append(f"(removed) {rel}")
    manifest.write_text("\n".join(sorted(files)) + "\n")
    return changed


if __name__ == "__main__":
    changed = write(build())
    print("\n".join(changed) if changed else "nothing changed")
    sys.exit(0)
