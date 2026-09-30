#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID == 0 ]] || exit 1
[[ $# == 1 && $1 =~ ^[a-f0-9]{40}$ ]] || exit 2
release="/srv/vprod/releases/$1"
[[ -f "$release/ops/auto-deploy.py" && -f /etc/letsencrypt/live/vprod.nl/fullchain.pem ]] || exit 1
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y git
if ! id vprod-deploy >/dev/null 2>&1; then
    useradd --system --user-group --home-dir /var/lib/vprod-deploy --shell /usr/sbin/nologin vprod-deploy
fi
install -d -o vprod-deploy -g vprod-deploy -m 700 /var/lib/vprod-deploy
install -d -o vprod-deploy -g vprod-deploy -m 755 /srv/vprod/deployments
# Ownership is limited to website releases and their activation link.
chown vprod-deploy:vprod-deploy /srv/vprod /srv/vprod/releases
install -d -m 755 /usr/local/libexec
install -o root -g root -m 755 "$release/ops/auto-deploy.py" /usr/local/libexec/vprod-auto-deploy.py
install -o root -g root -m 644 "$release/ops/vprod-deploy.service" /etc/systemd/system/vprod-deploy.service
install -o root -g root -m 644 "$release/ops/vprod-deploy.timer" /etc/systemd/system/vprod-deploy.timer
systemd-analyze verify /etc/systemd/system/vprod-deploy.service /etc/systemd/system/vprod-deploy.timer
systemctl daemon-reload
systemctl enable --now vprod-deploy.timer
systemctl start vprod-deploy.service
systemctl is-active --quiet vprod-deploy.timer
printf 'VPROD_AUTO_DEPLOY_OK\n'
