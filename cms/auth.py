"""Login: password (argon2), then a 6-digit code from an authenticator
app (TOTP). One admin, stored in instance/admin.json, set up with
`python -m cms.manage init`.

Failed attempts are logged ("cms auth failure from <ip>") for fail2ban,
and limited here too: 5 failures from an address lock it out for 15
minutes."""

from __future__ import annotations

import json
import logging
import threading
import time
from functools import wraps

import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from flask import (Blueprint, current_app, flash, redirect, render_template,
                   request, session, url_for)

from . import config

bp = Blueprint("auth", __name__, url_prefix="/admin")
log = logging.getLogger("cms.auth")
hasher = PasswordHasher()

ADMIN_FILE = config.INSTANCE / "admin.json"
SESSION_HOURS = 12        # log in again after this long
IDLE_MINUTES = 120        # or after this long without doing anything
MAX_FAILURES = 5
LOCK_SECONDS = 15 * 60


# ─── the admin's details ─────────────────────────────────────────────────

def load_admin() -> dict | None:
    if not ADMIN_FILE.exists():
        return None
    return json.loads(ADMIN_FILE.read_text())


def save_admin(data: dict) -> None:
    config.INSTANCE.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = ADMIN_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.chmod(0o600)
    tmp.replace(ADMIN_FILE)


# ─── rate limiting ───────────────────────────────────────────────────────

_failures: dict[str, list[float]] = {}
_lock = threading.Lock()


def _client_ip() -> str:
    return request.remote_addr or "?"


def locked_out(ip: str) -> bool:
    now = time.time()
    with _lock:
        recent = [t for t in _failures.get(ip, []) if now - t < LOCK_SECONDS]
        _failures[ip] = recent
        return len(recent) >= MAX_FAILURES


def record_failure(ip: str, what: str) -> None:
    with _lock:
        _failures.setdefault(ip, []).append(time.time())
    log.warning("cms auth failure from %s (%s)", ip, what)


def clear_failures(ip: str) -> None:
    with _lock:
        _failures.pop(ip, None)


# ─── guarding pages ──────────────────────────────────────────────────────

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        now = time.time()
        if not session.get("user"):
            return redirect(url_for("auth.login", next=request.path))
        if (now - session.get("auth_time", 0) > SESSION_HOURS * 3600
                or now - session.get("seen", 0) > IDLE_MINUTES * 60):
            session.clear()
            flash("You were logged out after a while without activity. Please log in again.")
            return redirect(url_for("auth.login", next=request.path))
        session["seen"] = now
        return view(*args, **kwargs)
    return wrapped


def _safe_next(target: str | None) -> str:
    """Only send people back to places inside the admin."""
    if target and target.startswith("/admin/") and "//" not in target and "\\" not in target:
        return target
    return url_for("main.dashboard")


# ─── login, step 1: password ─────────────────────────────────────────────

@bp.route("/login", methods=["GET", "POST"])
def login():
    admin = load_admin()
    if admin is None:
        return render_template("not_set_up.html"), 503
    ip = _client_ip()
    if request.method == "POST":
        if locked_out(ip):
            log.warning("cms auth locked out %s", ip)
            flash("Too many attempts. Wait 15 minutes and try again.")
            return render_template("login.html"), 429
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        ok = False
        try:
            ok = hasher.verify(admin["password_hash"], password) and username == admin["username"]
        except (VerificationError, InvalidHashError):
            ok = False
        if not ok:
            record_failure(ip, "password")
            flash("Wrong username or password.")
            return render_template("login.html"), 401
        if hasher.check_needs_rehash(admin["password_hash"]):
            admin["password_hash"] = hasher.hash(password)
            save_admin(admin)
        session.clear()
        session["password_ok"] = time.time()
        session["next"] = _safe_next(request.args.get("next"))
        return redirect(url_for("auth.second_step"))
    return render_template("login.html")


# ─── login, step 2: the 6-digit code ─────────────────────────────────────

@bp.route("/login/code", methods=["GET", "POST"])
def second_step():
    admin = load_admin()
    started = session.get("password_ok")
    if admin is None or not started or time.time() - started > 300:
        session.clear()
        return redirect(url_for("auth.login"))
    ip = _client_ip()
    if request.method == "POST":
        if locked_out(ip):
            flash("Too many attempts. Wait 15 minutes and try again.")
            return render_template("code.html"), 429
        code = request.form.get("code", "").replace(" ", "")
        step = code_step(admin["totp_secret"], code)
        # a code works once: replaying one already used fails
        if step is not None and step > admin.get("last_code_step", 0):
            admin["last_code_step"] = step
            save_admin(admin)
            nxt = session.get("next") or url_for("main.dashboard")
            session.clear()
            session.permanent = True
            now = time.time()
            session.update(user=admin["username"], auth_time=now, seen=now)
            clear_failures(ip)
            log.info("cms login ok from %s", ip)
            return redirect(_safe_next(nxt))
        record_failure(ip, "code")
        flash("That code didn't work. Codes change every 30 seconds — try the current one.")
        return render_template("code.html"), 401
    return render_template("code.html")


def code_step(secret: str, code: str) -> int | None:
    """The 30-second window a code belongs to: the current one or a
    neighbour (phone clocks drift). None if it matches none."""
    if not (len(code) == 6 and code.isdigit()):
        return None
    totp = pyotp.TOTP(secret)
    now = int(time.time() // 30)
    for s in (now, now - 1, now + 1):
        if totp.at(s * 30) == code:
            return s
    return None


@bp.route("/logout", methods=["POST"])
def logout():
    session.clear()
    flash("Logged out.")
    return redirect(url_for("auth.login"))
