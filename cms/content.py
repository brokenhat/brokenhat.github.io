"""Reading and writing content/: the pages, the pieces, their images,
and the checks shown under "Needs attention"."""

from __future__ import annotations

import os
import re
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import yaml

from . import config

SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

TITLE_MAX = 60        # Google shows about this many characters
DESCRIPTION_MAX = 160


# ─── YAML with readable multi-line text ──────────────────────────────────

class _Dumper(yaml.SafeDumper):
    pass


def _str(dumper, s):
    return dumper.represent_scalar("tag:yaml.org,2002:str", s, style="|" if "\n" in s else None)


_Dumper.add_representer(str, _str)


def read(path: Path) -> dict:
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def write(path: Path, data: dict) -> None:
    """Atomic: a crash mid-save never leaves half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = yaml.dump(data, Dumper=_Dumper, allow_unicode=True, sort_keys=False, width=100000)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".yaml")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def clean(d: dict) -> dict:
    """Drop empty fields so the files stay short."""
    return {k: v for k, v in d.items() if v not in (None, "", [], {})}


def slugify(title: str) -> str:
    s = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s or "untitled"


# ─── what's in the site ──────────────────────────────────────────────────

PAGE_TYPES = {"exhibition": "Exhibition", "works": "Works", "gallery": "Gallery", "cv": "CV"}


@dataclass
class Page:
    slug: str
    data: dict

    @property
    def type(self) -> str:
        return self.data.get("type", "")

    @property
    def title(self) -> str:
        return self.data.get("title") or self.slug

    @property
    def path(self) -> Path:
        return config.CONTENT / "pages" / f"{self.slug}.yaml"

    @property
    def url(self) -> str:
        return f"/{self.slug}.html" if self.type == "cv" else f"/{self.slug}/"

    @property
    def image_folder(self) -> Path:
        return config.SITE / self.slug / "images"

    @property
    def image_url(self) -> str:
        return f"/{self.slug}/images"


@dataclass
class Piece:
    section: str
    slug: str
    data: dict

    @property
    def title(self) -> str:
        return self.data.get("title") or self.slug

    @property
    def path(self) -> Path:
        return config.CONTENT / self.section / f"{self.slug}.yaml"

    @property
    def url(self) -> str:
        return f"/{self.section}/{self.slug}/"

    @property
    def image_folder(self) -> Path:
        return config.SITE / self.section / self.slug / "images"

    @property
    def image_url(self) -> str:
        return f"/{self.section}/{self.slug}/images"


def site() -> dict:
    return read(config.CONTENT / "site.yaml")


def home() -> dict:
    return read(config.CONTENT / "home.yaml")


def save_home(data: dict) -> None:
    write(config.CONTENT / "home.yaml", clean(data))


def pages() -> list[Page]:
    return [page(s) for s in site().get("menu", [])]


def page(slug: str) -> Page:
    check_slug(slug)
    p = Page(slug, {})
    if not p.path.exists():
        raise KeyError(slug)
    p.data = read(p.path)
    return p


def save_page(p: Page) -> None:
    write(p.path, clean(p.data))


def pieces(section: Page) -> list[Piece]:
    return [piece(section.slug, s) for s in section.data.get("pieces", [])]


def piece(section: str, slug: str) -> Piece:
    check_slug(section)
    check_slug(slug)
    p = Piece(section, slug, {})
    if not p.path.exists():
        raise KeyError(slug)
    p.data = read(p.path)
    return p


def save_piece(p: Piece) -> None:
    write(p.path, clean(p.data))


def new_piece(section: Page, title: str) -> Piece:
    """A new piece, first in its section (newest first)."""
    base = slugify(title)
    slug, n = base, 2
    taken = set(section.data.get("pieces", []))
    while slug in taken or (config.CONTENT / section.slug / f"{slug}.yaml").exists():
        slug, n = f"{base}-{n}", n + 1
    p = Piece(section.slug, slug, {"title": title})
    save_piece(p)
    section.data["pieces"] = [slug] + section.data.get("pieces", [])
    save_page(section)
    return p


def delete_piece(section: Page, slug: str) -> None:
    """Out of the section and its file removed (git keeps the history;
    its photos stay on disk until the folder is tidied)."""
    section.data["pieces"] = [s for s in section.data.get("pieces", []) if s != slug]
    save_page(section)
    f = config.CONTENT / section.slug / f"{slug}.yaml"
    if f.exists():
        f.unlink()


def check_slug(s: str) -> None:
    if not SLUG.match(s or ""):
        raise KeyError(s)


# ─── needs attention ─────────────────────────────────────────────────────

@dataclass
class Issue:
    where: str      # what to show: "Thawing"
    link: str       # the editor to fix it in
    text: str


def _seo_issues(name: str, link: str, d: dict, out: list[Issue]) -> None:
    title = d.get("seo_title") or f"{d.get('title', '')} — Dominik Zarzycki"
    desc = d.get("description") or ""
    if not desc:
        out.append(Issue(name, link, "no search description"))
    elif len(desc) > DESCRIPTION_MAX:
        out.append(Issue(name, link, f"search description is {len(desc)} characters (Google shows about {DESCRIPTION_MAX})"))
    if len(title) > TITLE_MAX:
        out.append(Issue(name, link, f"search title is {len(title)} characters (Google shows about {TITLE_MAX})"))


def _image_issues(name: str, link: str, images: list[dict], out: list[Issue]) -> None:
    missing = sum(1 for i in images if not (i.get("alt") or "").strip())
    if missing:
        out.append(Issue(name, link, f"{missing} image{'s' if missing > 1 else ''} without a description"))


def issues() -> list[Issue]:
    out: list[Issue] = []
    _seo_issues("Home page", "/admin/home", home(), out)
    for p in pages():
        link = f"/admin/pages/{p.slug}"
        _seo_issues(p.title, link, p.data, out)
        if p.type == "gallery":
            _image_issues(p.title, link, [i for g in p.data.get("groups", []) for i in g.get("images", [])], out)
        if p.type == "exhibition" and p.data.get("image"):
            _image_issues(p.title, link, [p.data["image"]], out)
        if p.type == "works":
            for pc in pieces(p):
                plink = f"/admin/pages/{p.slug}/{pc.slug}"
                _seo_issues(pc.title, plink, pc.data, out)
                if not pc.data.get("image"):
                    out.append(Issue(pc.title, plink, "no main image (it won't show on the index)"))
                _image_issues(pc.title, plink,
                              ([pc.data["image"]] if pc.data.get("image") else []) + pc.data.get("details", []), out)
    return out
