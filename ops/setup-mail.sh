#!/usr/bin/env bash
# Reviewed one-time setup for the existing V Production Ubuntu 26.04 VPS.
# Secrets are prompted on the VPS and never belong in this repository.
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]] || { printf 'Start met sudo.\n' >&2; exit 1; }
[[ $# == 1 && $1 =~ ^[a-zA-Z0-9._+-]+@vps\.transip\.email$ ]] || exit 2
relay_user=$1
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
/bin/bash "$source_dir/mail/verify-target.sh"
[[ -f /etc/os-release ]] && . /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 26.04 ]] || exit 1
[[ ! -e /var/lib/vprod-mail/installed.json ]] || { printf 'Mail is al ingericht; gebruik gericht onderhoud.\n' >&2; exit 1; }
for service in postfix dovecot dovecot-core rspamd; do
  if dpkg-query -W -f='${Status}' "$service" 2>/dev/null | grep -q 'install ok installed'; then
    printf 'Bestaand pakket %s gevonden: eerst inspecteren.\n' "$service" >&2; exit 1
  fi
done
[[ ! -e /etc/nginx/sites-enabled/vprod-mail && ! -e /etc/nginx/sites-available/vprod-mail ]] || exit 1
[[ ! -e /etc/letsencrypt/renewal-hooks/deploy/vprod-mail ]] || exit 1
[[ $(getent ahostsv4 mail.vprod.nl | awk 'NR==1 {print $1}') == 37.97.129.7 ]] || { printf 'Wacht op DNS voor mail.vprod.nl.\n' >&2; exit 1; }
[[ $(df --output=avail -k / | tail -1) -gt 8388608 ]] || exit 1
[[ -d $source_dir/mail/rspamd/local.d && -f $source_dir/mail-health.py ]] || exit 1
[[ ! -e /etc/postfix/sasl_passwd && ! -e /etc/dovecot/users ]] || exit 1
printf 'Plak het VPS-mailservice-wachtwoord uit TransIP; invoer blijft onzichtbaar.\n'
read -rs -p 'TransIP SMTP-wachtwoord: ' relay_password </dev/tty
printf '\n'
[[ ${#relay_password} -ge 8 && $relay_password != *[$'\r\n\t ']* ]] || { unset relay_password; exit 1; }
printf '%s' "$relay_password" | python3 "$source_dir/mail/verify-relay.py" "$relay_user"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=/var/backups/vprod-mail/setup-$stamp
install -d -m 700 "$backup"
cp -a /etc/nginx /etc/fstab "$backup/"
[[ ! -e /etc/aliases ]] || cp -a /etc/aliases "$backup/aliases-before"
dpkg-query -W >"$backup/packages-before.txt"
ss -lnt >"$backup/listeners-before.txt"
free -m >"$backup/memory-before.txt"
timer_was_active=0
systemctl is-active --quiet vprod-deploy.timer && timer_was_active=1
systemctl stop vprod-deploy.timer
success=0
cleanup() {
  code=$?
  unset relay_password
  if [[ $success == 0 ]]; then
    systemctl stop postfix dovecot rspamd vprod-mail-health.timer vprod-mail-backup.timer 2>/dev/null || true
    systemctl disable postfix dovecot rspamd vprod-mail-health.timer vprod-mail-backup.timer 2>/dev/null || true
    rm -f /var/lib/vprod-mail/installed.json
    rm -f /etc/nginx/sites-enabled/vprod-mail /etc/nginx/sites-available/vprod-mail
    rm -f /etc/letsencrypt/renewal-hooks/deploy/vprod-mail
    nginx -t && systemctl reload nginx || true
    printf '\nInstallatie gestopt; website behouden. Mail blijft uit.\nBackup: %s\n' "$backup" >&2
    printf 'Pakketten, swap en eventueel certificaat blijven voor diagnose aanwezig.\n' >&2
  fi
  [[ $timer_was_active == 0 ]] || systemctl start vprod-deploy.timer
  exit "$code"
}
trap cleanup EXIT

# No unconfigured mail daemon may listen while apt installs packages.
for service in postfix dovecot rspamd; do systemctl mask "$service.service"; done
if [[ $(awk 'NR>1 {sum+=$3} END {print sum+0}' /proc/swaps) == 0 ]]; then
  [[ ! -e /swapfile-vprod-mail ]] || { printf 'Onverwacht swapbestand; stop.\n' >&2; exit 1; }
  fallocate -l 2G /swapfile-vprod-mail
  chmod 600 /swapfile-vprod-mail
  mkswap /swapfile-vprod-mail >/dev/null
  swapon /swapfile-vprod-mail
  printf '\n/swapfile-vprod-mail none swap sw 0 0\n' >>/etc/fstab
fi
printf 'postfix postfix/mailname string mail.vprod.nl\npostfix postfix/main_mailer_type select No configuration\n' | debconf-set-selections
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postfix dovecot-core dovecot-imapd dovecot-lmtpd libsasl2-modules rspamd fail2ban python3-systemd
[[ $(dovecot --version) == 2.4.* ]] || { printf 'Onverwachte Dovecot-versie.\n' >&2; exit 1; }
cp -a /etc/postfix /etc/dovecot /etc/rspamd "$backup/"
install -d -m 755 /var/lib/letsencrypt/.well-known/acme-challenge
install -m 644 "$source_dir/mail/nginx-mail.conf" /etc/nginx/sites-available/vprod-mail
ln -s /etc/nginx/sites-available/vprod-mail /etc/nginx/sites-enabled/vprod-mail
nginx -t
systemctl reload nginx
certbot certonly --webroot -w /var/lib/letsencrypt --cert-name mail.vprod.nl -d mail.vprod.nl --non-interactive --keep-until-expiring

getent group vmail >/dev/null || groupadd --system vmail
id vmail >/dev/null 2>&1 || useradd --system --gid vmail --home-dir /var/vmail --shell /usr/sbin/nologin vmail
install -d -o vmail -g vmail -m 700 /var/vmail /var/vmail/vprod.nl /var/vmail/vprod.nl/info /var/vmail/vprod.nl/info-home
install -d -o vmail -g vmail -m 700 /var/vmail/vprod.nl/info/{cur,new,tmp}
install -d -m 700 /etc/vprod-mail
install -d -m 755 /var/lib/vprod-mail /usr/local/libexec
install -m 644 "$source_dir/mail/dovecot.conf" /etc/dovecot/dovecot.conf
install -m 644 "$source_dir/mail/postfix-main.cf" /etc/postfix/main.cf
install -m 644 "$source_dir/mail/postfix-master.cf" /etc/postfix/master.cf
printf 'info@vprod.nl vprod.nl/info/\n' >/etc/postfix/vmailbox
printf 'postmaster@vprod.nl info@vprod.nl\n' >/etc/postfix/virtual
printf 'info@vprod.nl info@vprod.nl\n' >/etc/postfix/sender_login
printf '[vps.transip.email]:587 %s:%s\n' "$relay_user" "$relay_password" >/etc/postfix/sasl_passwd
unset relay_password
chmod 600 /etc/postfix/sasl_passwd
for map in vmailbox virtual sender_login sasl_passwd; do postmap "/etc/postfix/$map"; done
chmod 600 /etc/postfix/sasl_passwd.db
printf 'root: info@vprod.nl\npostmaster: info@vprod.nl\n' >/etc/aliases
newaliases

# Generate a unique mailbox password privately; never pass it via process args.
python3 - <<'PY'
import json, os, pathlib, secrets, subprocess
password = secrets.token_urlsafe(24)
p = subprocess.run(['openssl','passwd','-6','-stdin'], input=password+'\n', text=True, capture_output=True, check=True)
pathlib.Path('/etc/dovecot/users').write_text('info@vprod.nl:{SHA512-CRYPT}'+p.stdout.strip()+'\n')
pathlib.Path('/etc/vprod-mail/client.json').write_text(json.dumps({'address':'info@vprod.nl','username':'info@vprod.nl','password':password,'imap_host':'mail.vprod.nl','imap_port':993,'imap_security':'SSL/TLS','smtp_host':'mail.vprod.nl','smtp_port':587,'smtp_security':'STARTTLS'}, indent=2)+'\n')
os.chmod('/etc/dovecot/users', 0o640)
os.chmod('/etc/vprod-mail/client.json', 0o600)
PY
chown root:dovecot /etc/dovecot/users

cp -a "$source_dir/mail/rspamd/local.d/." /etc/rspamd/local.d/
install -m 644 "$source_dir/mail/rspamd/rspamd.conf.override" /etc/rspamd/rspamd.conf.override
chown -R root:root /etc/rspamd/local.d
find /etc/rspamd/local.d -type f -exec chmod 644 {} +
install -d -m 755 /etc/systemd/system/rspamd.service.d /etc/systemd/system/dovecot.service.d
cat >/etc/systemd/system/rspamd.service.d/vprod-memory.conf <<'EOF'
[Service]
MemoryAccounting=yes
MemoryHigh=256M
MemoryMax=384M
MemorySwapMax=512M
Restart=on-failure
RestartSec=10
EOF
cat >/etc/systemd/system/dovecot.service.d/vprod-memory.conf <<'EOF'
[Service]
MemoryAccounting=yes
MemoryHigh=128M
MemoryMax=192M
MemorySwapMax=128M
Restart=on-failure
RestartSec=10
EOF
cat >/etc/fail2ban/jail.d/vprod-mail.local <<'EOF'
[dovecot]
enabled = true
backend = systemd
port = 993,587
findtime = 10m
bantime = 1h
maxretry = 5
[postfix-sasl]
enabled = true
backend = systemd
port = 587
findtime = 10m
bantime = 1h
maxretry = 5
EOF
install -m 755 "$source_dir/mail/renew-hook.sh" /etc/letsencrypt/renewal-hooks/deploy/vprod-mail
install -m 755 "$source_dir/mail-health.py" /usr/local/libexec/vprod-mail-health
install -m 755 "$source_dir/mail-backup.sh" /usr/local/libexec/vprod-mail-backup
cat >/etc/systemd/system/vprod-mail-backup.service <<'EOF'
[Unit]
Description=Private V Production mailbox snapshot
After=dovecot.service
[Service]
Type=oneshot
UMask=0077
Nice=15
IOSchedulingClass=idle
TimeoutStartSec=15min
ExecStart=/usr/local/libexec/vprod-mail-backup
EOF
cat >/etc/systemd/system/vprod-mail-backup.timer <<'EOF'
[Unit]
Description=Daily V Production mailbox snapshot
[Timer]
OnCalendar=*-*-* 04:15:00
RandomizedDelaySec=15min
Persistent=true
[Install]
WantedBy=timers.target
EOF
cat >/etc/systemd/system/vprod-mail-health.service <<'EOF'
[Unit]
Description=Read-only V Production mail health report
After=network-online.target
[Service]
Type=oneshot
UMask=0022
ExecStart=/bin/sh -c '/usr/local/libexec/vprod-mail-health > /var/lib/vprod-mail/health.json.tmp; code=$$?; chmod 644 /var/lib/vprod-mail/health.json.tmp; mv /var/lib/vprod-mail/health.json.tmp /var/lib/vprod-mail/health.json; exit "$$code"'
Nice=10
EOF
cat >/etc/systemd/system/vprod-mail-health.timer <<'EOF'
[Unit]
Description=Check V Production mail every five minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
[Install]
WantedBy=timers.target
EOF
doveconf -n >"$backup/dovecot-validated.txt"
postfix check
rspamadm configtest --strict
fail2ban-client --test >/dev/null
systemctl daemon-reload
for service in postfix dovecot rspamd; do systemctl unmask "$service.service"; done
systemctl enable --now rspamd dovecot postfix
systemctl restart fail2ban
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  for port in 25 587 993; do ufw allow "$port/tcp"; done
fi
sleep 3
python3 "$source_dir/mail/verify-local.py"
curl --fail --silent --show-error https://vprod.nl/ -o /dev/null
certbot renew --cert-name mail.vprod.nl --dry-run --run-deploy-hooks --no-random-sleep-on-renew
install -d -o vyas -g vyas -m 700 /home/vyas/.config/vprod-mail
install -o vyas -g vyas -m 600 /etc/vprod-mail/client.json /home/vyas/.config/vprod-mail/client.json
if ! systemctl start vprod-mail-health.service; then
  cat /var/lib/vprod-mail/health.json >&2
  exit 1
fi
systemctl enable --now vprod-mail-health.timer
free -m >"$backup/memory-after.txt"
printf '{"installed_at":"%s","public_verification":"pending","mailbox":"info@vprod.nl"}\n' "$stamp" >/var/lib/vprod-mail/installed.json
chmod 644 /var/lib/vprod-mail/installed.json
systemctl start vprod-mail-backup.service
systemctl enable --now vprod-mail-backup.timer
success=1
printf '\nVPROD_MAIL_LOCAL_OK\nMailbox lokaal getest; externe ontvangst en bezorging worden nog gecontroleerd.\n'
printf 'Privé mailinstellingen: /home/vyas/.config/vprod-mail/client.json\nBackup: %s\n' "$backup"
