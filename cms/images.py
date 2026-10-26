"""Uploads and the small previews shown in the editor.

An upload is checked to really be an image (by Pillow, not by its name),
turned the right way up, stripped of its metadata (phone photos carry
the GPS position of where they were taken), and stored at most
MAX_STORED_SIDE pixels on its longest side: that copy is what the site's
zoom view shows, so full-resolution originals never go online."""

from __future__ import annotations

import hashlib
import re
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

from . import config

ALLOWED = {"JPEG", "PNG", "WEBP", "TIFF", "MPO", "HEIF", "GIF"}
PREVIEW_DIR = config.INSTANCE / "previews"
PREVIEW_SIDE = 480


class NotAnImage(ValueError):
    pass


def safe_name(name: str) -> str:
    stem = Path(name).stem
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-.") or "image"
    return stem[:80]


def store_upload(data: bytes, original_name: str, folder: Path) -> str:
    """Save an uploaded image into folder; returns the file name used."""
    try:
        img = Image.open(BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as e:
        raise NotAnImage(f"{original_name} isn't an image the site can use") from e
    if img.format not in ALLOWED:
        raise NotAnImage(f"{original_name}: {img.format} images aren't supported, use JPEG or PNG")

    img = ImageOps.exif_transpose(img)          # phones store "rotate me" in metadata
    keep_png = img.format == "PNG" or img.mode in ("RGBA", "LA", "P") and "transparency" in img.info
    if max(img.size) > config.MAX_STORED_SIDE:
        img.thumbnail((config.MAX_STORED_SIDE, config.MAX_STORED_SIDE), Image.LANCZOS)

    folder.mkdir(parents=True, exist_ok=True)
    ext = ".png" if keep_png else ".jpg"
    base = safe_name(original_name)
    name, n = base + ext, 2
    while (folder / name).exists():
        name, n = f"{base}-{n}{ext}", n + 1

    out = folder / name
    # saving a fresh copy without exif/icc/xmp drops all metadata
    if keep_png:
        img.save(out, "PNG", optimize=True)
    else:
        img.convert("RGB").save(out, "JPEG", quality=90, optimize=True, progressive=True)
    return name


def preview(site_path: str) -> Path | None:
    """A small JPEG of an image under site/, cached by file and mtime."""
    src = (config.SITE / site_path.lstrip("/")).resolve()
    if config.SITE not in src.parents or not src.is_file():
        return None
    key = hashlib.sha1(f"{src}:{src.stat().st_mtime_ns}".encode()).hexdigest()
    out = PREVIEW_DIR / f"{key}.jpg"
    if not out.exists():
        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        try:
            with Image.open(src) as img:
                img = ImageOps.exif_transpose(img)
                img.thumbnail((PREVIEW_SIDE, PREVIEW_SIDE))
                img.convert("RGB").save(out, "JPEG", quality=80)
        except (UnidentifiedImageError, OSError):
            return None
    return out
