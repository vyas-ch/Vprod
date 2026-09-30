#!/usr/bin/env bash
# First installation for the inspected, empty Ubuntu VPS. Run through sudo.
set -Eeuo pipefail
umask 022

if [[ $EUID -ne 0 ]]; then printf 'Beheerdersrechten nodig. Start via sudo.\n' >&2; exit 1; fi
if [[ -e /etc/letsencrypt/live/vprod.nl/fullchain.pem ]]; then
    printf 'HTTPS bestaat al. Gebruik deploy-vps.sh om TLS te behouden.\n' >&2
    exit 1
fi
if [[ $# -ne 3 ]]; then printf 'Gebruik: setup-vps.sh ARCHIEF SHA256 GIT_COMMIT\n' >&2; exit 2; fi
archive=$1
expected_sha=$2
commit=$3
[[ $expected_sha =~ ^[a-f0-9]{64}$ && $commit =~ ^[a-f0-9]{40}$ ]] || exit 2
[[ -f $archive && ! -L $archive ]] || exit 2
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="/var/backups/vprod/${stamp}-${commit:0:12}"
release="/srv/vprod/releases/$commit"
config=/etc/nginx/sites-available/vprod
enabled=/etc/nginx/sites-enabled/vprod
staging=''
changed=0
had_current=0
had_config=0
had_enabled=0
nginx_was_active=0
systemctl is-active --quiet nginx && nginx_was_active=1

install -d -m 700 "$backup"
install -m 600 "$archive" "$backup/release.tar"
printf '%s  %s\n' "$expected_sha" "$backup/release.tar" | sha256sum --check --status
if [[ -e /srv/vprod/current || -L /srv/vprod/current ]]; then
    [[ -L /srv/vprod/current ]] || { printf '/srv/vprod/current is geen symlink; stop.\n' >&2; exit 1; }
    cp -a /srv/vprod/current "$backup/current"
    had_current=1
fi
if [[ -e $config || -L $config ]]; then cp -a "$config" "$backup/site-config"; had_config=1; fi
if [[ -e $enabled || -L $enabled ]]; then cp -a "$enabled" "$backup/site-enabled"; had_enabled=1; fi
dpkg-query -W nginx > "$backup/nginx-package-before.txt" 2>/dev/null || true
printf 'commit=%s\narchive_sha256=%s\nprevious_current=%s\n' "$commit" "$expected_sha" "$(readlink /srv/vprod/current 2>/dev/null || true)" > "$backup/manifest.txt"

rollback() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        printf '\nInstallatie mislukt. Herstel van de V Production-configuratie.\n' >&2
        if [[ $changed == 1 ]]; then
            rm -f /srv/vprod/current "$config" "$enabled"
            [[ $had_current == 0 ]] || cp -a "$backup/current" /srv/vprod/current
            [[ $had_config == 0 ]] || cp -a "$backup/site-config" "$config"
            [[ $had_enabled == 0 ]] || cp -a "$backup/site-enabled" "$enabled"
            if [[ $nginx_was_active == 1 ]]; then
                if command -v nginx >/dev/null && nginx -t; then systemctl reload nginx || true; fi
            else
                systemctl disable --now nginx || true
            fi
        fi
        printf 'Backup en manifest: %s\n' "$backup" >&2
    fi
    if [[ -n $staging && $staging == /srv/vprod/releases/.stage-* ]]; then rm -rf -- "$staging"; fi
    exit "$status"
}
trap rollback EXIT

printf '1/4 Websitebestanden controleren en plaatsen.\n'
install -d -m 755 /srv/vprod /srv/vprod/releases
staging=$(mktemp -d /srv/vprod/releases/.stage-XXXXXXXX)
python3 - "$backup/release.tar" "$staging" <<'PY'
import pathlib, sys, tarfile
archive, target = sys.argv[1:]
with tarfile.open(archive, 'r:') as tf:
    members = tf.getmembers()
    for m in members:
        p = pathlib.PurePosixPath(m.name)
        if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0] not in ('public', 'ops'):
            raise SystemExit(f'Onverwacht archiefpad: {m.name}')
        if not (m.isfile() or m.isdir()) or any(part.startswith('.') for part in p.parts):
            raise SystemExit(f'Onverwacht archiefbestand: {m.name}')
    tf.extractall(target, members=members, filter='data')
if not (pathlib.Path(target)/'public/index.html').is_file():
    raise SystemExit('index.html ontbreekt')
PY
chown -R root:root "$staging"
find "$staging" -type d -exec chmod 755 {} +
find "$staging" -type f -exec chmod 644 {} +
if [[ -e $release ]]; then
    diff -qr "$staging" "$release" >/dev/null || { printf 'Bestaande release wijkt af; stop.\n' >&2; exit 1; }
else
    mv "$staging" "$release"
    staging=''
fi

printf '2/4 Nginx installeren vanuit de Ubuntu-pakketbron.\n'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y nginx
install -d -m 755 /etc/nginx/sites-available /etc/nginx/sites-enabled
changed=1
install -m 644 "$release/ops/vprod.nginx.conf" "$config"
ln -sfn "$config" "$enabled"
ln -s "$release" "/srv/vprod/.current-$stamp"
mv -Tf "/srv/vprod/.current-$stamp" /srv/vprod/current

printf '3/4 Configuratie valideren en activeren.\n'
nginx -t
systemctl enable nginx
if systemctl is-active --quiet nginx; then systemctl reload nginx; else systemctl start nginx; fi
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow 80/tcp; fi

printf '4/4 Website en beveiligde paden controleren.\n'
curl --fail --silent --show-error -H 'Host: vprod.nl' http://127.0.0.1/ -o "$backup/homepage.html"
grep -q 'Van idee' "$backup/homepage.html"
curl --fail --silent --show-error -H 'Host: vprod.nl' http://127.0.0.1/assets/logo.svg -o /dev/null
curl --fail --silent --show-error -H 'Host: vprod.nl' http://127.0.0.1/privacy.html -o /dev/null
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: vprod.nl' http://127.0.0.1/.env) == 403 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: vprod.nl' http://127.0.0.1/ops/setup-vps.sh) == 404 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: vproduction.nl' http://127.0.0.1/test) == 301 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: vprod.nl' -H 'Range: bytes=0-99' http://127.0.0.1/assets/studio-hero.webp) == 206 ]]
python3 - "$release/public" "$backup/public-sha256.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
data = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
pathlib.Path(sys.argv[2]).write_text(json.dumps(data, indent=2))
PY
printf 'commit=%s\ninstalled_at=%s\nbackup=%s\nhttp_checks=passed\nhttps=pending_dns\n' "$commit" "$stamp" "$backup" > /srv/vprod/deploy-status.txt
printf '\nVPROD_SETUP_OK\nWebsite: http://37.97.129.7\nGit-commit: %s\nBackup: %s\n' "$commit" "$backup"
printf 'HTTPS en de domeinen worden afgerond nadat DNS naar deze VPS verwijst.\n'
