"""Saving, previewing and publishing.

- After every save the .pm pages are regenerated (cms/sitegen.py).
- Preview renders the working copy (site/) with Pollen.
- Publish commits content/ and site/ to git, builds that commit in a
  separate checkout (config.BUILD) with clean URLs, copies the result
  into a new release folder and switches www/current to it in one step,
  so visitors never see a half-updated site. The last few releases are
  kept for an instant rollback.
- History is the git log; undoing a publish is a git revert, published.
"""

from __future__ import annotations

import contextlib
import fcntl
import logging
import os
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import config, sitegen

log = logging.getLogger("cms.publish")

KEEP_RELEASES = 5
TRACKED = ["content", "site"]        # what the CMS commits


class PublishError(RuntimeError):
    pass


def run(cmd: list[str], cwd: Path, env: dict | None = None, timeout: int = 900) -> str:
    p = subprocess.run(cmd, cwd=cwd, env={**os.environ, **(env or {})}, timeout=timeout,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        raise PublishError(f"{' '.join(cmd[:3])} failed:\n{p.stdout[-3000:]}")
    return p.stdout


_git_lock = threading.Lock()


def git(*args: str, cwd: Path | None = None) -> str:
    """One git command at a time (the dashboard checks for changes while
    a publish commits); reads never take git's index lock."""
    name, _, email = config.AUTHOR.partition(" <")
    with _git_lock:
        return run(["git", "--no-optional-locks", "-c", f"user.name={name}",
                    "-c", f"user.email={email.rstrip('>')}", *args],
                   cwd or config.REPO)


# ─── after a save ────────────────────────────────────────────────────────

def regenerate() -> list[str]:
    return sitegen.write(sitegen.build(config.REPO), config.REPO)


def unpublished() -> list[str]:
    """Changed files not yet published (committed)."""
    out = git("status", "--porcelain", "--untracked-files=all", "--", *TRACKED)
    files = []
    for line in out.splitlines():
        path = line[3:].strip().strip('"')
        if path.endswith((".html", ".xml")) or "/compiled/" in path or path.startswith("site/thumbs"):
            continue
        files.append(path)
    return files


# ─── preview ─────────────────────────────────────────────────────────────

_preview_lock = threading.Lock()


def render_preview() -> None:
    """Render the working copy as it is now (links keep index.html)."""
    with _preview_lock:
        regenerate()
        env = {"SITE_CLEAN_URLS": "0"}
        try:
            _render(config.SITE, env)
        except PublishError:
            run([config.RACO, "pollen", "reset"], config.SITE, env)
            _render(config.SITE, env)


# ─── publish (in the background; the page polls the status) ──────────────

@dataclass
class Job:
    state: str = "idle"          # idle | running | done | failed
    step: str = ""
    message: str = ""
    started: float = 0.0
    log: list[str] = field(default_factory=list)


job = Job()
_job_lock = threading.Lock()


def start_publish(note: str) -> bool:
    """False if a publish is already running."""
    with _job_lock:
        if job.state == "running":
            return False
        job.state, job.step, job.message, job.started, job.log = "running", "Saving", "", time.time(), []
    threading.Thread(target=_publish, args=(note,), daemon=True).start()
    return True


def start_undo(commit: str) -> bool:
    with _job_lock:
        if job.state == "running":
            return False
        job.state, job.step, job.message, job.started, job.log = "running", "Undoing", "", time.time(), []
    threading.Thread(target=_undo, args=(commit,), daemon=True).start()
    return True


def _set(step: str) -> None:
    job.step = step
    job.log.append(f"{time.strftime('%H:%M:%S')} {step}")


@contextlib.contextmanager
def build_lock():
    """One build at a time, also across processes (a code update arriving
    by git push runs `cms.manage update` next to the web app)."""
    config.INSTANCE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(config.INSTANCE / "build.lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def sync() -> None:
    """Bring in code pushed to the origin, send our commits back."""
    if not config.PUSH:
        return
    git("pull", "-q", "--rebase", "--autostash", "origin", "main")
    git("push", "-q", "origin", "HEAD:main")


def _publish(note: str) -> None:
    try:
        with build_lock():
            _set("Saving the changes")
            regenerate()
            commit_changes(note or "Update from the CMS")
            sync()
            _release(git("rev-parse", "HEAD").strip())
    except Exception as e:  # shown in the admin; the live site is untouched
        log.exception("publish failed")
        job.state, job.message = "failed", str(e)


def _undo(commit: str) -> None:
    try:
        with build_lock():
            _set("Undoing the change")
            if unpublished():
                raise PublishError("Publish or discard the unsaved changes first.")
            git("revert", "--no-edit", commit)
            regenerate()
            if unpublished():   # regenerated pages of the reverted content
                commit_changes("Regenerate pages")
            sync()
            _release(git("rev-parse", "HEAD").strip())
    except Exception as e:
        try:
            git("revert", "--abort")
        except PublishError:
            pass
        log.exception("undo failed")
        job.state, job.message = "failed", str(e)


def commit_changes(note: str) -> str:
    git("add", "-A", "--", *TRACKED)
    if git("diff", "--cached", "--name-only").strip():
        git("commit", "-q", "-m", note)
    return git("rev-parse", "HEAD").strip()


def _release(commit: str) -> None:
    _set("Building the site")
    build_site = _checkout(commit)
    env = {"SITE_CLEAN_URLS": "1"}
    try:
        _render(build_site, env)
    except PublishError:
        # Pollen's cache can trip over pages that changed since the last
        # build: start it afresh once (resized images are kept)
        _set("Building the site (from scratch)")
        run([config.RACO, "pollen", "reset"], build_site, env)
        _render(build_site, env)

    _set("Putting it online")
    releases = config.WWW / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    target = releases / f"{time.strftime('%Y%m%d-%H%M%S')}-{commit[:7]}"
    _collect(build_site, target)
    _switch(target)
    _prune(releases)
    job.state, job.step = "done", "Published"
    job.message = f"Live: {target.name}"


def _render(site: Path, env: dict) -> None:
    run([config.RACO, "pollen", "render", "-r", "."], site, env)
    run([config.RACO, "pollen", "render", "404.html.pm"], site, env)


def _checkout(commit: str) -> Path:
    """The build checkout at `commit` (a git worktree of the repo; its
    Pollen cache and resized images carry over between builds)."""
    if not (config.BUILD / ".git").exists():
        config.BUILD.parent.mkdir(parents=True, exist_ok=True)
        git("worktree", "add", "--force", "--detach", str(config.BUILD), commit)
    else:
        git("checkout", "-q", "--force", "--detach", commit, cwd=config.BUILD)
    return config.BUILD / "site"


# what goes online: as .github/workflows/build.yml collects it
PUBLIC_FILES = ["sitemap.xml", "robots.txt", "favicon.svg", "favicon.ico", "apple-touch-icon.png"]
PUBLIC_DIRS = ["css", "js", "images", "thumbs"]


def _collect(src: Path, dst: Path) -> None:
    """Pages, assets and images into dst. Images are hard links (no
    extra disk space; the build replaces files, it never edits them)."""
    def put(f: Path) -> None:
        out = dst / f.relative_to(src)
        if out.exists():
            return
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(f, out)
        except OSError:
            shutil.copy2(f, out)

    for f in src.rglob("*.html"):
        if "compiled" not in f.parts:
            out = dst / f.relative_to(src)
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, out)
    for name in PUBLIC_FILES:
        if (src / name).exists():
            shutil.copy2(src / name, dst / name)
    for d in PUBLIC_DIRS:
        if (src / d).is_dir():
            for f in (src / d).rglob("*"):
                if f.is_file():
                    put(f)
    for f in src.rglob("images/*"):
        if f.is_file() and "thumbs" not in f.relative_to(src).parts[:1]:
            put(f)


def _switch(target: Path) -> None:
    current = config.WWW / "current"
    tmp = config.WWW / ".current-new"
    if tmp.is_symlink() or tmp.exists():
        tmp.unlink()
    tmp.symlink_to(target.relative_to(config.WWW))
    os.replace(tmp, current)       # atomic: the site is never half-switched


def _prune(releases: Path) -> None:
    current = (config.WWW / "current").resolve()
    old = sorted(p for p in releases.iterdir() if p.is_dir())
    for p in old[:-KEEP_RELEASES]:
        if p.resolve() != current:
            shutil.rmtree(p)


def update_from_origin() -> str:
    """After code was pushed to the origin: take it in and rebuild the
    live site (run by the repository's post-receive hook)."""
    with build_lock():
        git("pull", "-q", "--rebase", "--autostash", "origin", "main")
        if regenerate():
            commit_changes("Regenerate pages")
            if config.PUSH:
                git("push", "-q", "origin", "HEAD:main")
        _release(git("rev-parse", "HEAD").strip())
        return job.message


# ─── history ─────────────────────────────────────────────────────────────

@dataclass
class Change:
    commit: str
    date: str
    note: str
    files: int


def history(limit: int = 40) -> list[Change]:
    fmt = "%H%x1f%cd%x1f%s"
    out = git("log", f"-{limit}", f"--format={fmt}", "--date=format:%d %b %Y, %H:%M",
              "--shortstat", "--", "content")
    changes, cur = [], None
    for line in out.splitlines():
        if "\x1f" in line:
            h, d, s = line.split("\x1f", 2)
            cur = Change(h, d, s, 0)
            changes.append(cur)
        elif cur and "changed" in line:
            cur.files = int(line.strip().split()[0])
    return changes
