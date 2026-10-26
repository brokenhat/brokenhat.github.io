"""The CMS for the portfolio site: a Flask app under /admin.

    python -m cms.manage init        # once: your login and 2FA
    flask --app cms run              # on your computer: http://localhost:5000/admin/
    gunicorn 'cms:create_app()'      # on the server (behind nginx)
"""

from __future__ import annotations

import logging
from datetime import timedelta

from flask import Flask, redirect
from flask_wtf.csrf import CSRFProtect
from werkzeug.middleware.proxy_fix import ProxyFix

from . import config

csrf = CSRFProtect()

# only the admin's own files; no inline scripts, nothing from elsewhere
CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; "
       "connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'none'; object-src 'none'")
# the preview is the real site: its own small inline script and styles,
# and the YouTube embed on the example page
PREVIEW_CSP = ("default-src 'self'; img-src 'self' data:; frame-src https://www.youtube-nocookie.com https://www.youtube.com; "
               "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; "
               "frame-ancestors 'none'; base-uri 'none'; object-src 'none'")


def create_app() -> Flask:
    app = Flask(__name__, static_url_path="/admin/static")
    app.config.update(
        SECRET_KEY=config.secret_key(),
        MAX_CONTENT_LENGTH=config.MAX_UPLOAD_MB * 1024 * 1024 * 20,   # a batch of photos
        SESSION_COOKIE_NAME="cms_session",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        SESSION_COOKIE_SECURE=config.SECURE_COOKIES,
        SESSION_COOKIE_PATH="/admin",
        PERMANENT_SESSION_LIFETIME=timedelta(hours=12),
        WTF_CSRF_TIME_LIMIT=None,          # tied to the session instead
    )
    # behind nginx: the real visitor address (rate limits, fail2ban)
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
    csrf.init_app(app)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")

    from . import auth, content, views
    app.register_blueprint(auth.bp)
    app.register_blueprint(views.bp)
    app.jinja_env.globals["nav_pages"] = content.pages

    @app.route("/admin")
    def admin_root():
        return redirect("/admin/")

    @app.after_request
    def headers(resp):
        h = resp.headers
        h.setdefault("X-Content-Type-Options", "nosniff")
        h.setdefault("Referrer-Policy", "same-origin")
        h.setdefault("X-Frame-Options", "DENY")
        h.setdefault("Cross-Origin-Opener-Policy", "same-origin")
        if resp.mimetype == "text/html":
            h.setdefault("Content-Security-Policy", PREVIEW_CSP if h.pop("X-Preview", None) else CSP)
            h["Cache-Control"] = "no-store"
        return resp

    return app
