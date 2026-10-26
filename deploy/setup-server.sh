#!/bin/bash
# Set up dominik-art.works on the EC2 server (Ubuntu 22.04). Safe to run
# again. Run as root from a checkout of this repository:
#
#   sudo deploy/setup-server.sh base    # packages, user, Racket, repository
#   (push the repository: git push server main)
#   sudo deploy/setup-server.sh app     # CMS, service, nginx test site, fail2ban
#
# Layout (all owned by the dominikart user):
#   /srv/dominik-art/site.git   the repository you and the CMS push to
#   /srv/dominik-art/repo       the CMS's checkout (content edits happen here)
#   /srv/dominik-art/build      where the live site is built
#   /srv/dominik-art/www        releases/ and current -> the live one (nginx)
#   /srv/dominik-art/instance   login details, secret key (private)
set -euo pipefail

SRV=/srv/dominik-art
USER_=dominikart
HERE=$(cd "$(dirname "$0")" && pwd)
RACKET=/opt/racket-9.3
RACKET_URL=https://download.racket-lang.org/installers/9.3/racket-9.3-x86_64-linux-cs.sh
# from https://download.racket-lang.org/releases/9.3/ (x86_64 Linux CS)
RACKET_SHA256=30dc59d9b5af083eacf793253d35782c5231e8bfb7a7331fe32ccd9a41fd792f

base() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq imagemagick fail2ban git python3-venv >/dev/null

  id "$USER_" >/dev/null 2>&1 || useradd --system --home-dir "$SRV" --create-home --shell /usr/sbin/nologin "$USER_"
  usermod -aG "$USER_" ubuntu           # ubuntu may push to the repository
  chmod 755 "$SRV"

  if [ ! -x "$RACKET/bin/racket" ]; then
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/racket.sh" "$RACKET_URL"
    echo "$RACKET_SHA256  $tmp/racket.sh" | sha256sum -c --quiet
    sh "$tmp/racket.sh" --in-place --dest "$RACKET" >/dev/null
    rm -rf "$tmp"
  fi
  "$RACKET/bin/raco" pkg show --scope installation pollen 2>/dev/null | grep -q '^ *pollen ' ||
    "$RACKET/bin/raco" pkg install --auto --batch --scope installation pollen

  install -d -o "$USER_" -g "$USER_" -m 755 "$SRV/www" "$SRV/bin"
  install -d -o "$USER_" -g "$USER_" -m 700 "$SRV/instance"
  if [ ! -d "$SRV/site.git" ]; then
    git init -q --bare --shared=group -b main "$SRV/site.git"
  fi
  chown -R "$USER_:$USER_" "$SRV/site.git"
  chmod -R g+rwX "$SRV/site.git"
  find "$SRV/site.git" -type d -exec chmod g+s {} +
  install -o "$USER_" -g "$USER_" -m 775 "$HERE/post-receive" "$SRV/site.git/hooks/post-receive"
  install -o "$USER_" -g "$USER_" -m 755 "$HERE/update" "$SRV/bin/update"
  for d in "$SRV/site.git" "$SRV/repo" "$SRV/build"; do
    git config --system --get-all safe.directory | grep -qx "$d" || git config --system --add safe.directory "$d"
  done
  echo "base done: now push the repository (git push server main), then run: $0 app"
}

app() {
  [ -n "$(git --git-dir="$SRV/site.git" rev-parse --verify -q main)" ] || { echo "push the repository first"; exit 1; }
  if [ ! -d "$SRV/repo/.git" ]; then
    sudo -u "$USER_" git clone -q "$SRV/site.git" "$SRV/repo"
  fi
  [ -x "$SRV/venv/bin/python" ] || sudo -u "$USER_" python3 -m venv "$SRV/venv"
  sudo -u "$USER_" "$SRV/venv/bin/pip" install -q --upgrade pip
  sudo -u "$USER_" "$SRV/venv/bin/pip" install -q -r "$SRV/repo/cms/requirements.txt"

  install -d -m 700 /etc/dominik-art
  [ -f /etc/dominik-art/cms.env ] || install -m 600 "$HERE/cms.env.example" /etc/dominik-art/cms.env

  # first build of the live site
  sudo -u "$USER_" "$SRV/bin/update" build

  install -m 644 "$HERE/dominik-art-cms.service" /etc/systemd/system/dominik-art-cms.service
  systemctl daemon-reload
  systemctl enable -q dominik-art-cms
  systemctl restart dominik-art-cms

  install -m 644 "$HERE/nginx/dominik-art-limits.conf" /etc/nginx/conf.d/dominik-art-limits.conf
  install -m 644 "$HERE/nginx/dominik-art-test.conf" /etc/nginx/sites-available/dominik-art-test
  ln -sf /etc/nginx/sites-available/dominik-art-test /etc/nginx/sites-enabled/dominik-art-test
  nginx -t -q && systemctl reload nginx

  install -m 644 "$HERE/fail2ban/dominik-art-cms.filter.conf" /etc/fail2ban/filter.d/dominik-art-cms.conf
  install -m 644 "$HERE/fail2ban/dominik-art.jail.conf" /etc/fail2ban/jail.d/dominik-art.conf
  systemctl enable -q fail2ban
  systemctl restart fail2ban
  echo "app done: the new site is on 127.0.0.1:8081 (ssh tunnel), the admin at /admin/"
}

"${1:?usage: $0 base|app}"
