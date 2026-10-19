#!/usr/bin/env python3
"""Extract content from Flask SQLite DB and generate Pollen .pm files."""

import sqlite3
import shutil
import re
import os
from pathlib import Path
from html.parser import HTMLParser

DB_PATH = Path(__file__).resolve().parent.parent.parent / "piniu2" / "flask-piniu" / "app.db"
UPLOADS = Path(__file__).resolve().parent.parent.parent / "piniu2" / "flask-piniu" / "app" / "static" / "uploads"
SITE = Path(__file__).resolve().parent.parent

# page_id -> section info
SECTIONS = {
    1: {"dir": "", "slug": "index", "title": "Homepage"},
    8: {"dir": "paintings", "slug": "index", "title": "Paintings"},
    11: {"dir": "generative", "slug": "index", "title": "Generative"},
    13: {"dir": "drawings", "slug": "index", "title": "Drawings"},
    15: {"dir": "highland-series", "slug": "index", "title": "Highland Series"},
    16: {"dir": "textiles", "slug": "index", "title": "Textiles"},
}


class HTMLStripper(HTMLParser):
    """Strip HTML tags, decode entities."""
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_entityref(self, name):
        from html import unescape
        self.parts.append(unescape(f"&{name};"))

    def handle_charref(self, name):
        from html import unescape
        self.parts.append(unescape(f"&#{name};"))

    def get_text(self):
        return "".join(self.parts)


def strip_html(html_str):
    """Remove HTML tags and decode entities."""
    if not html_str:
        return ""
    s = HTMLStripper()
    s.feed(html_str)
    text = s.get_text()
    # Clean up whitespace
    text = re.sub(r"\xa0", " ", text)
    text = text.strip()
    return text


def get_posts_for_page(cursor, page_id):
    """Get ordered posts for a page, respecting sortables order."""
    # Get sortables order
    cursor.execute("SELECT data FROM sortables WHERE id = ?", (page_id,))
    row = cursor.fetchone()
    if row and row[0]:
        order = [int(x) for x in row[0].strip(",").split(",") if x.strip()]
    else:
        order = []

    cursor.execute(
        "SELECT id, body, images FROM post WHERE page_id = ? ORDER BY timestamp",
        (page_id,),
    )
    posts = {r[0]: {"body": r[1] or "", "images": r[2] or ""} for r in cursor.fetchall()}

    # Return in sortables order, then any remaining
    ordered = []
    seen = set()
    for pid in order:
        if pid in posts:
            ordered.append(posts[pid])
            seen.add(pid)
    for pid, post in posts.items():
        if pid not in seen:
            ordered.append(post)
    return ordered


def copy_image(img_name, dest_dir):
    """Copy non-thumbnail image to destination."""
    if img_name.startswith("thumb-"):
        return
    src = UPLOADS / img_name
    if src.exists():
        dest_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest_dir / img_name)


def write_homepage(cursor):
    """Generate index.html.pm from homepage posts."""
    posts = get_posts_for_page(cursor, 1)
    img_dir = SITE / "images"

    lines = ['#lang pollen\n']
    lines.append('£(define-meta title "Dominik Zarzycki")\n')

    # Find the main text post (post 41)
    for post in posts:
        body = strip_html(post["body"])
        if body and len(body) > 50:
            # This is the artist statement
            paragraphs = [p.strip() for p in re.split(r"\n\s*\n|\n", body) if p.strip()]
            lines.append("\n£section-intro{")
            for p in paragraphs:
                if p.startswith("This site"):
                    continue
                lines.append(f"\n{p}\n")
            lines.append("}\n")
            break

    # Collect homepage images
    img_names = []
    for post in posts:
        if post["images"]:
            img = post["images"].strip()
            if img and not img.startswith("thumb-"):
                copy_image(img, img_dir)
                img_names.append(img)

    if img_names:
        lines.append("\n£gallery{\n")
        for img in img_names:
            lines.append(f'£fig["/images/{img}"]{{}}\n')
        lines.append("}\n")

    (SITE / "index.html.pm").write_text("".join(lines), encoding="utf-8")
    print("  wrote index.html.pm")


def write_section_index(cursor, page_id, info):
    """Generate section index page."""
    section_dir = SITE / info["dir"] if info["dir"] else SITE
    section_dir.mkdir(parents=True, exist_ok=True)
    img_dir = section_dir / "images" if info["dir"] else SITE / "images"

    posts = get_posts_for_page(cursor, page_id)

    lines = ['#lang pollen\n']
    lines.append(f'£(define-meta title "{info["title"]}")\n')

    # Extract intro text
    for post in posts:
        body = strip_html(post["body"])
        if body and len(body) > 20:
            paragraphs = [p.strip() for p in re.split(r"\n\s*\n|\n", body) if p.strip()]
            meaningful = [p for p in paragraphs if p != "." and len(p) > 5]
            if meaningful:
                lines.append("\n£section-intro{")
                for p in meaningful:
                    lines.append(f"\n{p}\n")
                lines.append("}\n")

    # Collect images into gallery
    img_names = []
    for post in posts:
        if post["images"]:
            img = post["images"].strip()
            if img and not img.startswith("thumb-"):
                copy_image(img, img_dir)
                img_names.append(img)

    if img_names:
        lines.append("\n£gallery{\n")
        for img in img_names:
            img_path = f"images/{img}" if info["dir"] else f"/images/{img}"
            lines.append(f'£fig["{img_path}"]{{}}\n')
        lines.append("}\n")

    out_path = section_dir / "index.html.pm"
    out_path.write_text("".join(lines), encoding="utf-8")
    print(f"  wrote {out_path.relative_to(SITE)}")


def write_highland_pieces(cursor):
    """Generate individual highland series piece pages."""
    posts = get_posts_for_page(cursor, 15)
    hs_dir = SITE / "highland-series"
    img_dir = hs_dir / "images"
    img_dir.mkdir(parents=True, exist_ok=True)

    # Group posts into pieces by text posts
    pieces = [
        {
            "slug": "rannoch-moor-swings",
            "title": "When Rannoch Moor Swings",
            "medium": "watercolour on fabriano paper",
            "dimensions": "h:114 w:141",
            "award": "Alexander Graham Munro Travel Award 2023",
            "exhibition": "RSW 142nd Annual Exhibition, Royal Scottish Academy, Edinburgh",
            "images": ["rannoch.jpg", "detail-rannoch1-small.JPG", "detail_rannoch2-small.JPG"],
        },
        {
            "slug": "buachaille-etive-mor",
            "title": "Buachaille Etive Mor",
            "medium": "watercolour on fabriano paper",
            "dimensions": "h:115 w:130",
            "images": ["buchaille.jpg", "buchie-general-res.JPG", "det1.JPG"],
        },
        {
            "slug": "lost-on-criese",
            "title": "Lost on Criese",
            "medium": "watercolour on paper",
            "dimensions": "h:132 w:115",
            "images": ["lost_on_criese.jpg", "det1.jpg", "det2.jpg"],
        },
    ]

    for piece in pieces:
        for img in piece["images"]:
            copy_image(img, img_dir)

        lines = ['#lang pollen\n']
        lines.append('£(define-meta template "template-piece.html.p")\n')
        lines.append(f'£(define-meta title "{piece["title"]}")\n')
        lines.append(f'\n£piece[#:title "{piece["title"]}"')
        lines.append(f'\n      #:medium "{piece["medium"]}"')
        lines.append(f'\n      #:dimensions "{piece["dimensions"]}"')
        if piece.get("award"):
            lines.append(f'\n      #:award "{piece["award"]}"')
        if piece.get("exhibition"):
            lines.append(f'\n      #:exhibition "{piece["exhibition"]}"')
        lines.append("]{\n")

        # Hero image
        lines.append(f'\n£image["images/{piece["images"][0]}" #:alt "{piece["title"]}" #:class "hero"]{{}}\n')

        # Detail images
        if len(piece["images"]) > 1:
            lines.append("\n£gallery{\n")
            for img in piece["images"][1:]:
                lines.append(f'£fig["images/{img}" #:alt "detail"]{{}}\n')
            lines.append("}\n")

        lines.append("}\n")

        out = hs_dir / f"{piece['slug']}.html.pm"
        out.write_text("".join(lines), encoding="utf-8")
        print(f"  wrote {out.relative_to(SITE)}")


def write_textile_pieces(cursor):
    """Generate textile piece pages in subfolders."""
    pieces = [
        {
            "slug": "sofreh-interlace",
            "title": "Sofreh Interlace",
            "year": "2023",
            "technique": "mixed media tapestry",
            "fibre": "wool, silk on cotton warp",
            "medium": "watercolour, pigments, paper, wool, silk",
            "dimensions": "100cm x 110cm",
            "exhibition": "RSW 143rd Annual Exhibition, Royal Scottish Academy, 2024",
            "body": "Reflections on persian dining-cloths.\n\nThe end piece of the project created with the help of RSW in Edinburgh.",
            "images": ["Sofreh_Interlaceresi.png"],
        },
        {
            "slug": "blue-stem",
            "title": "Blue Stem",
            "year": "2024",
            "technique": "handwoven tapestry",
            "fibre": "wool on wool",
            "dimensions": "approx 200cm high",
            "body": "Woven in one long strip and then stitched together to create spatial form of riband.\n\nIt was made like that to highlight the technique of stitching together multiple strips of kilim to create larger one \u2014 usually used as floor covering or wrap for other more precious textiles in persian culture and within tribes of Caucasus.\n\nThis one is especially inspired by mazandaran and jajim kilims.",
            "images": ["PXL_20240219_175905460.jpg"],
        },
        {
            "slug": "untitled-2024",
            "title": "Untitled, 2024",
            "year": "2024",
            "technique": "interwoven warp tapestry with pile knots",
            "body": "2 sets of interwoven warp \u2014 woven from the back and from the front, constantly rotating the frame back and forth and by 90 degree angle. The frame itself was just regular stretcher used for paintings.\n\nApart from interplay between the warps this tapestry uses also pile knotted parts (using only persian knots) and then trimmed into sculptural form to match abstract whole.",
            "images": [
                "PXL_20240219_1758503232.jpg",
                "PXL_20240227_184821884.MP.jpg",
                "PXL_20240228_150243480.jpg",
                "PXL_20240313_1025208852.jpg",
                "PXL_20240314_165529286.PORTRAIT.ORIGINAL.jpg",
                "PXL_20240314_172955229.jpg",
                "PXL_20240315_125448530.jpg",
            ],
        },
    ]

    for piece in pieces:
        piece_dir = SITE / "textiles" / piece["slug"]
        img_dir = piece_dir / "images"
        img_dir.mkdir(parents=True, exist_ok=True)

        for img in piece["images"]:
            copy_image(img, img_dir)

        lines = ['#lang pollen\n']
        lines.append('£(define-meta template "template-piece.html.p")\n')
        lines.append(f'£(define-meta title "{piece["title"]}")\n')
        lines.append(f'\n£piece[#:title "{piece["title"]}"')
        lines.append(f'\n      #:year "{piece["year"]}"')
        if piece.get("technique"):
            lines.append(f'\n      #:technique "{piece["technique"]}"')
        if piece.get("fibre"):
            lines.append(f'\n      #:fibre "{piece["fibre"]}"')
        if piece.get("medium"):
            lines.append(f'\n      #:medium "{piece["medium"]}"')
        if piece.get("dimensions"):
            lines.append(f'\n      #:dimensions "{piece["dimensions"]}"')
        if piece.get("exhibition"):
            lines.append(f'\n      #:exhibition "{piece["exhibition"]}"')
        lines.append("]{\n")

        # Hero image
        lines.append(f'\n£image["images/{piece["images"][0]}" #:alt "{piece["title"]}" #:class "hero"]{{}}\n')

        # Body text
        if piece.get("body"):
            lines.append(f'\n{piece["body"]}\n')

        # Process images gallery
        if len(piece["images"]) > 1:
            lines.append("\n£gallery{\n")
            for img in piece["images"][1:]:
                lines.append(f'£fig["images/{img}" #:alt "process"]{{}}\n')
            lines.append("}\n")

        # Git timeline for sofreh-interlace
        if piece["slug"] == "sofreh-interlace":
            lines.append('\n£git-timeline["textiles/sofreh-interlace"]\n')

        lines.append("}\n")

        out = piece_dir / "index.html.pm"
        out.write_text("".join(lines), encoding="utf-8")
        print(f"  wrote {out.relative_to(SITE)}")


def main():
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.cursor()

    print("Migrating content from Flask DB...")

    # Homepage
    write_homepage(cursor)

    # Section indexes (skip homepage which is handled above)
    for page_id, info in SECTIONS.items():
        if page_id == 1:
            continue
        write_section_index(cursor, page_id, info)

    # Highland Series individual pieces
    write_highland_pieces(cursor)

    # Textile pieces
    write_textile_pieces(cursor)

    conn.close()
    print("\nDone. Review generated .pm files and refine metadata.")


if __name__ == "__main__":
    main()
