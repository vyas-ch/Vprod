#!/usr/bin/env bash
# Deploy a verified release and activate/retain HTTPS on the V Production VPS.
set -Eeuo pipefail
umask 022
[[ $EUID == 0 ]] || { printf 'Start via sudo.\n' >&2; exit 1; }
[[ $# == 4 ]] || { printf 'Gebruik: deploy-vps.sh ARCHIEF SHA256 COMMIT VORIGE_COMMIT\n' >&2; exit 2; }
archive=$1 expected_sha=$2 commit=$3 previous=$4
[[ $expected_sha =~ ^[a-f0-9]{64}$ && $commit =~ ^[a-f0-9]{40}$ && $previous =~ ^[a-f0-9]{40}$ ]] || exit 2
[[ -f $archive && ! -L $archive ]] || exit 2
exec 9>/run/lock/vprod-deploy.lock
flock -n 9 || { printf 'Er loopt al een deploy.\n' >&2; exit 1; }
[[ $(readlink /srv/vprod/current) == "/srv/vprod/releases/$previous" ]] || { printf 'Actieve release is gewijzigd; controleer eerst.\n' >&2; exit 1; }
systemctl is-active --quiet nginx
nginx -t

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="/var/backups/vprod/${stamp}-${commit:0:12}-https"
release="/srv/vprod/releases/$commit"
config=/etc/nginx/sites-available/vprod
staging=''
changed=0
install -d -m 700 "$backup"
install -m 600 "$archive" "$backup/release.tar"
printf '%s  %s\n' "$expected_sha" "$backup/release.tar" | sha256sum --check --status
cp -a /srv/vprod/current "$backup/current"
cp -a "$config" "$backup/site-config"
cp -a /srv/vprod/deploy-status.txt "$backup/deploy-status.txt"
printf 'commit=%s\nprevious=%s\narchive_sha256=%s\n' "$commit" "$previous" "$expected_sha" > "$backup/manifest.txt"

rollback() {
    local status=$?
    if [[ $status != 0 && $changed == 1 ]]; then
        printf '\nDeploy mislukt. Vorige website en Nginx-configuratie herstellen.\n' >&2
        cp -a "$backup/site-config" "$config"
        ln -s "/srv/vprod/releases/$previous" "/srv/vprod/.rollback-$stamp"
        mv -Tf "/srv/vprod/.rollback-$stamp" /srv/vprod/current
        cp -a "$backup/deploy-status.txt" /srv/vprod/deploy-status.txt
        if nginx -t; then systemctl reload nginx || true; fi
    fi
    if [[ -n $staging && $staging == /srv/vprod/releases/.stage-* ]]; then rm -rf -- "$staging"; fi
    [[ $status == 0 ]] || printf 'Backup: %s\n' "$backup" >&2
    exit "$status"
}
trap rollback EXIT

printf '1/5 Release controleren.\n'
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
for file in ('public/index.html', 'public/assets/vprod-montage.mp4', 'ops/vprod.https.nginx.conf'):
    if not (pathlib.Path(target)/file).is_file():
        raise SystemExit(f'Ontbreekt: {file}')
PY
chown -R root:root "$staging"
find "$staging" -type d -exec chmod 755 {} +
find "$staging" -type f -exec chmod 644 {} +
if [[ -e $release ]]; then
    diff -qr "$staging" "$release" >/dev/null || { printf 'Bestaande release wijkt af.\n' >&2; exit 1; }
else
    mv "$staging" "$release"
    staging=''
fi

printf '2/5 Certbot installeren uit Ubuntu en DNS controleren.\n'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y certbot
python3 - <<'PY'
import socket
for domain in ('vprod.nl','www.vprod.nl','vproduction.nl','www.vproduction.nl'):
    addresses = {item[4][0] for item in socket.getaddrinfo(domain,80,type=socket.SOCK_STREAM)}
    if addresses != {'37.97.129.7'}:
        raise SystemExit(f'DNS nog niet klaar voor {domain}: {sorted(addresses)}. Probeer later opnieuw.')
    print(domain, 'DNS OK')
PY
install -d -m 755 /var/lib/letsencrypt/.well-known/acme-challenge
changed=1
# An existing TLS configuration stays active throughout later deployments.
if ! grep -Eq 'listen[[:space:]]+443[[:space:]]+ssl' "$config"; then
    install -m 644 "$release/ops/vprod.nginx.conf" "$config"
    nginx -t
    systemctl reload nginx
fi
token="vprod-preflight-$stamp"
printf '%s' "$token" > "/var/lib/letsencrypt/.well-known/acme-challenge/$token"
for domain in vprod.nl www.vprod.nl vproduction.nl www.vproduction.nl; do
    [[ $(curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "http://$domain/.well-known/acme-challenge/$token") == "$token" ]]
done
rm "/var/lib/letsencrypt/.well-known/acme-challenge/$token"

printf '3/5 HTTPS-certificaat aanvragen en website activeren.\n'
certbot certonly --non-interactive --agree-tos --register-unsafely-without-email \
    --webroot -w /var/lib/letsencrypt --cert-name vprod.nl --keep-until-expiring \
    -d vprod.nl -d www.vprod.nl -d vproduction.nl -d www.vproduction.nl
install -m 644 "$release/ops/vprod.https.nginx.conf" "$config"
ln -s "$release" "/srv/vprod/.current-$stamp"
mv -Tf "/srv/vprod/.current-$stamp" /srv/vprod/current
nginx -t
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then ufw allow 443/tcp; fi
systemctl reload nginx

printf '4/5 HTTPS, doorverwijzingen en videostream controleren.\n'
curl --fail --silent --show-error --resolve vprod.nl:443:127.0.0.1 https://vprod.nl/ -o "$backup/homepage.html"
cmp "$backup/homepage.html" "$release/public/index.html"
curl --fail --silent --show-error --resolve vprod.nl:443:127.0.0.1 https://vprod.nl/assets/vprod-montage.mp4 -o "$backup/video-check.mp4"
cmp "$backup/video-check.mp4" "$release/public/assets/vprod-montage.mp4"
rm "$backup/video-check.mp4"
[[ $(curl -s --resolve vprod.nl:443:127.0.0.1 -o /dev/null -w '%{http_code}' https://vprod.nl/.env) == 403 ]]
[[ $(curl -s --resolve vprod.nl:443:127.0.0.1 -o /dev/null -w '%{http_code}' https://vprod.nl/ops/deploy-vps.sh) == 404 ]]
[[ $(curl -s --resolve vprod.nl:443:127.0.0.1 -H 'Range: bytes=0-99' -o /dev/null -w '%{http_code}' https://vprod.nl/assets/vprod-montage.mp4) == 206 ]]
for domain in vprod.nl www.vprod.nl vproduction.nl www.vproduction.nl; do
    [[ $(curl -s --resolve "$domain:80:127.0.0.1" -o /dev/null -w '%{redirect_url}' "http://$domain/test?x=1") == 'https://vprod.nl/test?x=1' ]]
done
for domain in www.vprod.nl vproduction.nl www.vproduction.nl; do
    [[ $(curl -s --resolve "$domain:443:127.0.0.1" -o /dev/null -w '%{redirect_url}' "https://$domain/test?x=1") == 'https://vprod.nl/test?x=1' ]]
done

printf '5/5 Automatische certificaatvernieuwing instellen en testen.\n'
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
hook=/etc/letsencrypt/renewal-hooks/deploy/vprod-nginx
[[ ! -e $hook ]] || cp -a "$hook" "$backup/renewal-hook"
cat > "$hook" <<'HOOK'
#!/bin/sh
set -eu
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/vprod.nl ]; then
    /usr/sbin/nginx -t
    /usr/bin/systemctl reload nginx
fi
HOOK
chmod 755 "$hook"
systemctl enable --now certbot.timer
certbot renew --cert-name vprod.nl --dry-run --run-deploy-hooks --no-random-sleep-on-renew
systemctl is-active --quiet certbot.timer
python3 - "$release/public" "$backup/public-sha256.json" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
pathlib.Path(sys.argv[2]).write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()},indent=2))
PY
printf 'commit=%s\ninstalled_at=%s\nbackup=%s\nhttps_checks=passed\nrenewal_dry_run=passed\n' "$commit" "$stamp" "$backup" > /srv/vprod/deploy-status.txt
printf '\nVPROD_HTTPS_OK\nWebsite: https://vprod.nl\nCommit: %s\nBackup: %s\n' "$commit" "$backup"
