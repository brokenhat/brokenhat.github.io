"""Setting up the admin login, from a terminal (on the server, over ssh).

    python -m cms.manage init         # username, password, 2FA (once)
    python -m cms.manage password     # change the password
    python -m cms.manage 2fa          # connect a new authenticator app
    python -m cms.manage update       # pull pushed code and rebuild the site
    python -m cms.manage build        # rebuild the live site from what's committed
"""

from __future__ import annotations

import getpass
import sys

import pyotp
import qrcode

from .auth import hasher, load_admin, save_admin

MIN_PASSWORD = 12


def ask_password() -> str:
    while True:
        p1 = getpass.getpass(f"New password (at least {MIN_PASSWORD} characters): ")
        if len(p1) < MIN_PASSWORD:
            print("Too short.")
            continue
        if getpass.getpass("Same again: ") != p1:
            print("They don't match.")
            continue
        return p1


def show_2fa(secret: str, username: str) -> None:
    uri = pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name="dominik-art.works admin")
    print("\nScan this with an authenticator app (Google Authenticator, Aegis, 1Password, ...):\n")
    qr = qrcode.QRCode(border=1)
    qr.add_data(uri)
    qr.print_ascii(invert=True)
    print(f"\nOr type this key in by hand: {secret}\n")


def confirm_2fa(secret: str) -> None:
    totp = pyotp.TOTP(secret)
    for _ in range(3):
        if totp.verify(input("Enter the 6-digit code the app shows now: ").strip(), valid_window=1):
            print("2FA works.")
            return
        print("That code didn't match.")
    sys.exit("2FA not confirmed; nothing saved.")


def main(argv: list[str]) -> None:
    cmd = argv[1] if len(argv) > 1 else ""
    admin = load_admin()
    if cmd == "init":
        if admin and input("An admin exists. Replace it? [y/N] ").lower() != "y":
            return
        username = input("Username: ").strip()
        password = ask_password()
        secret = pyotp.random_base32()
        show_2fa(secret, username)
        confirm_2fa(secret)
        save_admin({"username": username, "password_hash": hasher.hash(password), "totp_secret": secret})
        print("Saved. Log in at /admin/")
    elif cmd == "password" and admin:
        admin["password_hash"] = hasher.hash(ask_password())
        save_admin(admin)
        print("Password changed.")
    elif cmd == "2fa" and admin:
        secret = pyotp.random_base32()
        show_2fa(secret, admin["username"])
        confirm_2fa(secret)
        admin["totp_secret"] = secret
        admin.pop("last_code_step", None)
        save_admin(admin)
        print("New authenticator app connected; the old one no longer works.")
    elif cmd == "update":
        from . import publish
        print(publish.update_from_origin())
    elif cmd == "build":
        from . import publish
        with publish.build_lock():
            publish._release(publish.git("rev-parse", "HEAD").strip())
        print(publish.job.message)
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv)
