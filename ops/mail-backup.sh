#!/usr/bin/env bash
# Daily snapshot of the one V Production mailbox. Run as root via systemd.
# Mail export is private to vyas; configuration/credentials stay root-only.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
[[ $EUID == 0 && $# == 0 ]] || { printf 'Run as root, without arguments.\n' >&2; exit 1; }
[[ -f /var/lib/vprod-mail/installed.json ]] || { printf 'Mail installation is not complete.\n' >&2; exit 1; }
[[ $(dovecot --version) == 2.4.* ]] || { printf 'Unsupported Dovecot version.\n' >&2; exit 1; }
getent passwd vmail >/dev/null
getent passwd vyas >/dev/null

# Root-controlled archive namespace; vmail may traverse only for doveadm staging.
backup_root=/var/backups/vprod-mail
[[ ! -L $backup_root ]] || exit 1
if [[ -e $backup_root ]]; then
  [[ -d $backup_root && $(stat -c %u "$backup_root") == 0 ]] || exit 1
fi
install -d -o root -g vmail -m 0710 "$backup_root"
exec 9>"$backup_root/.backup.lock"
flock -n 9 || { printf 'Mail backup is already running.\n' >&2; exit 1; }

# Leave room for the uncompressed snapshot, archive, private export and headroom.
# Fail before copying when space is low; never prune the last good backups first.
source_bytes=$(du -sb /var/vmail/vprod.nl/info | awk '{print $1}')
available_bytes=$(df --output=avail -B1 "$backup_root" | tail -1 | tr -d ' ')
required_bytes=$((source_bytes * 3 + 268435456))
[[ $available_bytes -gt $required_bytes ]] || { printf 'Insufficient free disk for a safe mail snapshot.\n' >&2; exit 1; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
final_dir=$backup_root/backup-$stamp
[[ ! -e $final_dir ]] || { printf 'Backup timestamp already exists.\n' >&2; exit 1; }
work_dir=$(mktemp -d "$backup_root/.work.XXXXXXXX")
cleanup() {
  code=$?
  # This is exclusively the mktemp directory owned by this invocation.
  if [[ -n ${work_dir:-} && $work_dir == "$backup_root"/.work.* && -d $work_dir && ! -L $work_dir ]]; then
    rm -rf --one-file-system -- "$work_dir"
  fi
  exit "$code"
}
trap cleanup EXIT
chown root:vmail "$work_dir"
chmod 0710 "$work_dir"
install -d -o vmail -g vmail -m 0700 "$work_dir/Maildir"

# Dovecot 2.4 still accepts mail_driver:mail_path for the dsync destination.
# No -R (reverse), -A (all users), mailbox exclusion or size/date filters.
# Exit 2 means changes occurred during sync; retry, never publish a partial copy.
snapshot_ok=0
for attempt in 1 2 3; do
  if doveadm backup -u info@vprod.nl -f -l 30 -T 120 "maildir:$work_dir/Maildir"; then
    snapshot_ok=1
    break
  else
    result=$?
    [[ $result == 2 ]] || exit "$result"
  fi
done
[[ $snapshot_ok == 1 ]] || { printf 'Mailbox kept changing; previous backup retained.\n' >&2; exit 1; }

cat >"$work_dir/MAIL-RESTORE.txt" <<'EOF'
Mailbox: info@vprod.nl. Maildir contains every folder in the configured inbox namespace.
This archive contains mail and mail metadata; no service passwords or TLS private keys.
Extract into an isolated restore directory first. Review contents and ownership before
any import into a live mailbox. Do not reverse-sync an unreviewed backup over live mail.
Archive readability was checked; a complete restore was not performed by this script.
EOF
printf '{"mailbox":"info@vprod.nl","snapshot_utc":"%s","format":"Maildir","dovecot_major_minor":"2.4"}\n' "$stamp" >"$work_dir/mail-metadata.json"
tar -czf "$work_dir/mail.tar.gz" -C "$work_dir" -- Maildir MAIL-RESTORE.txt mail-metadata.json
gzip -t "$work_dir/mail.tar.gz"
tar -tzf "$work_dir/mail.tar.gz" >/dev/null

# Separate private recovery material. No unrelated sites, certificates or mailboxes.
# Archive confidentiality relies on root-only filesystem permissions, not encryption.
install -d -o root -g root -m 0700 "$work_dir/config" "$work_dir/config/etc" "$work_dir/config/tls"
for item in dovecot postfix vprod-mail rspamd; do
  [[ -d /etc/$item && ! -L /etc/$item ]] || exit 1
  cp -a -- "/etc/$item" "$work_dir/config/etc/"
done
cp -a -- /etc/aliases "$work_dir/config/etc/"
cp -L -- /etc/letsencrypt/live/mail.vprod.nl/fullchain.pem "$work_dir/config/tls/fullchain.pem"
cp -L -- /etc/letsencrypt/live/mail.vprod.nl/privkey.pem "$work_dir/config/tls/privkey.pem"
chmod 0600 "$work_dir/config/tls/"*.pem
cat >"$work_dir/config/PRIVATE.txt" <<'EOF'
Contains mailbox credentials, outbound relay credentials and mail TLS private key.
Root-only recovery archive. Do not place in Git, web roots or the vyas export folder.
For off-server storage, encrypt with a separately held recovery key before copying.
EOF
tar -czf "$work_dir/config.tar.gz" -C "$work_dir" -- config
gzip -t "$work_dir/config.tar.gz"
tar -tzf "$work_dir/config.tar.gz" >/dev/null
chmod 0600 "$work_dir/mail.tar.gz" "$work_dir/config.tar.gz"

# Remove only this run's uncompressed staging after both archives were verified.
rm -rf --one-file-system -- "$work_dir/Maildir" "$work_dir/config"
rm -f -- "$work_dir/MAIL-RESTORE.txt" "$work_dir/mail-metadata.json"
chown root:root "$work_dir"
chmod 0700 "$work_dir"
mv -T -- "$work_dir" "$final_dir"
work_dir=

# Use directory file descriptors and O_NOFOLLOW for the user-owned export path.
# This avoids following a user-created symlink while running as root.
python3 - "$final_dir" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import pwd
import re
import secrets
import shutil
import stat
import sys

version = pathlib.Path(sys.argv[1])
archive = version / 'mail.tar.gz'
account = pwd.getpwnam('vyas')
directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
fd = os.open('/home', directory_flags)
try:
    next_fd = os.open('vyas', directory_flags, dir_fd=fd)
    os.close(fd)
    fd = next_fd
    if os.fstat(fd).st_uid != account.pw_uid:
        raise RuntimeError('Unexpected owner of /home/vyas')
    for component in ('.local', 'share', 'vprod-mail-backups'):
        created = False
        try:
            os.mkdir(component, 0o700, dir_fd=fd)
            created = True
        except FileExistsError:
            pass
        next_fd = os.open(component, directory_flags, dir_fd=fd)
        os.close(fd)
        fd = next_fd
        if created:
            os.fchown(fd, account.pw_uid, account.pw_gid)
        metadata = os.fstat(fd)
        if metadata.st_uid != account.pw_uid or metadata.st_mode & 0o022:
            raise RuntimeError('Unsafe owner/permissions in private export path')
    os.fchmod(fd, 0o700)
    temporary = '.latest-' + secrets.token_hex(12)
    output_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    try:
        digest = hashlib.sha256()
        with archive.open('rb') as source, os.fdopen(output_fd, 'wb') as output:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
            os.fchown(output.fileno(), account.pw_uid, account.pw_gid)
            os.fchmod(output.fileno(), 0o600)
        os.replace(temporary, 'latest.tar.gz', src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    except BaseException:
        try:
            os.unlink(temporary, dir_fd=fd)
        except FileNotFoundError:
            pass
        raise
finally:
    os.close(fd)

# Prune only our completed version directories, never setup-* or other backups.
root = pathlib.Path('/var/backups/vprod-mail')
pattern = re.compile(r'backup-[0-9]{8}T[0-9]{6}Z')
versions = []
for candidate in root.iterdir():
    info = candidate.lstat()
    if pattern.fullmatch(candidate.name) and stat.S_ISDIR(info.st_mode) and info.st_uid == 0:
        versions.append(candidate)
for expired in sorted(versions, key=lambda p: p.name, reverse=True)[7:]:
    shutil.rmtree(expired)

status_dir = pathlib.Path('/var/lib/vprod-mail')
info = status_dir.lstat()
if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
    raise RuntimeError('Unsafe backup status directory')
status = {
    'last_success_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'mailbox': 'info@vprod.nl',
    'archive_filename': str(archive.relative_to(root)),
    'archive_sha256': digest.hexdigest(),
    'archive_bytes': archive.stat().st_size,
    'retained_versions': min(len(versions), 7),
    'restore_test': 'gzip-and-tar-readable; full restore not tested',
    'private_export': '/home/vyas/.local/share/vprod-mail-backups/latest.tar.gz',
    'configuration_exported': False,
}
temporary_status = status_dir / ('.backup-' + secrets.token_hex(12) + '.json')
with temporary_status.open('x') as output:
    json.dump(status, output, indent=2)
    output.write('\n')
    output.flush()
    os.fsync(output.fileno())
os.chmod(temporary_status, 0o644)
os.replace(temporary_status, status_dir / 'backup.json')
PY
printf 'V Production mailbox snapshot completed: %s\n' "${final_dir##*/}"
