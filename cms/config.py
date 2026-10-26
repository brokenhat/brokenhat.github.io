"""Where the CMS finds things. Every path can be set by an environment
variable (the server's systemd unit sets them); the defaults suit
running it from this repository on your own computer."""

import os
import secrets
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _path(var: str, default: Path) -> Path:
    return Path(os.environ.get(var, default)).resolve()


# the git checkout the CMS edits: content/ and site/
REPO = _path("CMS_REPO", HERE.parent)
CONTENT = REPO / "content"
SITE = REPO / "site"

# private files: login details, secret key, caches (never in git)
INSTANCE = _path("CMS_INSTANCE", HERE / "instance")
# a second checkout where the published site is built
BUILD = _path("CMS_BUILD", INSTANCE / "build")
# published sites: releases/<time>/ and current -> the live one
WWW = _path("CMS_WWW", INSTANCE / "www")

RACO = os.environ.get("CMS_RACO", "raco")
# git author of commits made by the CMS
AUTHOR = os.environ.get("CMS_AUTHOR", "Dominik Zarzycki (CMS) <domino.zarzycki@gmail.com>")
# on the server: after a publish, push the commit to the repository the
# checkout came from (where code updates arrive too)
PUSH = os.environ.get("CMS_PUSH", "0") == "1"
# https in production: cookies only over https
SECURE_COOKIES = os.environ.get("CMS_SECURE_COOKIES", "0") == "1"
# Claude, for suggested alt text and descriptions (optional)
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# uploads: phone photos are big; stored copies are at most this many
# pixels on the longest side (the site's zoom view uses them)
MAX_UPLOAD_MB = 60
MAX_STORED_SIDE = 3000


def secret_key() -> str:
    """Signs the login cookie; made once, kept in instance/."""
    INSTANCE.mkdir(parents=True, exist_ok=True, mode=0o700)
    f = INSTANCE / "secret_key"
    if not f.exists():
        f.write_text(secrets.token_hex(32))
        f.chmod(0o600)
    return f.read_text().strip()
