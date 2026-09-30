#!/usr/bin/env python3
"""Read-only mail/VPS health summary; no credentials or message bodies are emitted.

Run locally on the mail VPS, either from SSH or a systemd service. The caller may
atomically save stdout to /var/lib/vprod-mail/health.json. This script never writes
files, changes services, authenticates, sends mail, or sends notifications.
Exit 0 means every check passed; exit 1 means at least one issue needs attention.
"""

import argparse
import datetime
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import selectors
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


MIB = 1024 * 1024
SYSTEM_PATH = '/usr/sbin:/usr/bin:/sbin:/bin'
OOM_PATTERN = re.compile(r'out of memory|oom-kill|killed process\s+\d+|memory cgroup out of memory', re.I)


class CheckError(Exception):
    """A fixed, non-sensitive error code suitable for the JSON report."""


class HealthArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        # Do not echo arbitrary argument values into a status file or journal.
        raise CheckError('invalid_configuration')


def command(arguments, timeout=5, max_bytes=2 * MIB):
    """Capture bounded stdout, discard stderr, and always reap the process."""
    executable = shutil.which(arguments[0], path=SYSTEM_PATH)
    if not executable:
        raise CheckError('command_unavailable')
    process = subprocess.Popen(
        [executable, *arguments[1:]], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        env={'PATH': SYSTEM_PATH, 'LANG': 'C', 'LC_ALL': 'C'},
    )
    deadline, chunks, size = time.monotonic() + timeout, [], 0
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise CheckError('command_timeout')
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes:
                    raise CheckError('command_output_limit')
                chunks.append(chunk)
        code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
        return code, b''.join(chunks).decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        raise CheckError('command_timeout') from None
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def run_checked(arguments, timeout=5, max_bytes=2 * MIB):
    code, output = command(arguments, timeout, max_bytes)
    if code != 0:
        raise CheckError('command_failed')
    return output


def result(metrics, issues=()):
    return {'status': 'issue' if issues else 'healthy', 'metrics': metrics, 'issues': list(issues)}


def services_check(options):
    metrics, issues = {}, []
    for service in ('postfix', 'dovecot', 'rspamd'):
        try:
            code, output = command(['systemctl', 'is-active', service + '.service'], options.timeout, 1024)
            state = output.strip()
            metrics[service] = state if state in {'active', 'inactive', 'failed', 'activating', 'deactivating', 'reloading', 'unknown', 'maintenance'} else 'unknown'
            if code or state != 'active':
                issues.append(service + '_not_active')
        except CheckError as error:
            metrics[service] = 'unavailable'
            issues.append(service + '_' + str(error))
    return result(metrics, issues)


def resources_check(options):
    meminfo = {}
    for line in pathlib.Path('/proc/meminfo').read_text().splitlines():
        name, _, value = line.partition(':')
        fields = value.split()
        if fields:
            meminfo[name] = int(fields[0]) * 1024
    required = ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree')
    if any(name not in meminfo for name in required):
        raise CheckError('memory_metrics_unavailable')
    loads = [float(value) for value in pathlib.Path('/proc/loadavg').read_text().split()[:3]]
    cpus = os.cpu_count() or 1
    swap_used = max(0, meminfo['SwapTotal'] - meminfo['SwapFree'])
    swap_percent = 100 * swap_used / meminfo['SwapTotal'] if meminfo['SwapTotal'] else None
    metrics = {
        'memory_total_mib': round(meminfo['MemTotal'] / MIB, 1),
        'memory_available_mib': round(meminfo['MemAvailable'] / MIB, 1),
        'swap_total_mib': round(meminfo['SwapTotal'] / MIB, 1),
        'swap_used_mib': round(swap_used / MIB, 1),
        'swap_used_percent': round(swap_percent, 1) if swap_percent is not None else None,
        'cpu_count': cpus, 'load_1m': loads[0], 'load_5m': loads[1], 'load_15m': loads[2],
    }
    issues = []
    if meminfo['MemAvailable'] < options.min_available_mib * MIB:
        issues.append('low_available_memory')
    if not meminfo['SwapTotal']:
        issues.append('swap_not_configured')
    elif swap_percent >= options.max_swap_percent:
        issues.append('high_swap_usage')
    if loads[2] > options.max_load_per_cpu * cpus:
        issues.append('sustained_high_load')
    return result(metrics, issues)


def storage_check(options):
    metrics, issues = {'filesystems': {}}, []
    for label, path in (('root', '/'), ('mail', options.mail_root)):
        if not pathlib.Path(path).is_dir():
            issues.append(label + '_directory_missing')
            continue
        usage = shutil.disk_usage(path)
        fs = os.statvfs(path)
        # statvfs free blocks include root-reserved space; use bytes available to
        # the unprivileged mail user for the capacity alert instead.
        available = fs.f_bavail * fs.f_frsize
        used_percent = 100 * usage.used / usage.total if usage.total else 100
        inode_percent = 100 * (fs.f_files - fs.f_ffree) / fs.f_files if fs.f_files else None
        metrics['filesystems'][label] = {
            'total_mib': round(usage.total / MIB, 1), 'used_percent': round(used_percent, 1),
            'available_mib': round(available / MIB, 1),
            'inodes_used_percent': round(inode_percent, 1) if inode_percent is not None else None,
        }
        if used_percent >= options.max_disk_percent or available < options.min_disk_free_mib * MIB:
            issues.append(label + '_low_disk_space')
        if inode_percent is not None and inode_percent >= 90:
            issues.append(label + '_low_free_inodes')
    if pathlib.Path(options.mail_root).is_dir():
        try:
            output = run_checked(['du', '-sx', '-B1', '--', options.mail_root], options.timeout, 4096)
            metrics['mail_spool_allocated_mib'] = round(int(output.split()[0]) / MIB, 2)
        except (CheckError, ValueError, IndexError):
            issues.append('mail_spool_usage_unavailable')
    return result(metrics, issues)


def certificate_check(options):
    certificate = pathlib.Path(options.certificate)
    if not certificate.is_file():
        raise CheckError('certificate_missing')
    output = run_checked(['openssl', 'x509', '-in', str(certificate), '-noout', '-enddate'], options.timeout, 1024)
    if not output.startswith('notAfter='):
        raise CheckError('certificate_expiry_unreadable')
    expires = ssl.cert_time_to_seconds(output.strip().partition('=')[2])
    days = (expires - time.time()) / 86400
    metrics = {'expires_at': datetime.datetime.fromtimestamp(expires, datetime.timezone.utc).isoformat(), 'days_remaining': round(days, 1)}
    return result(metrics, ['certificate_expiring'] if days < options.certificate_warning_days else [])


def queue_check(options):
    output = run_checked(['postqueue', '-j'], options.timeout, 8 * MIB)
    count, deferred, oldest_age = 0, 0, 0
    now = time.time()
    for line in output.splitlines():
        if not line.strip():
            continue
        # Never retain or emit sender, recipient, queue ID, or delivery reason.
        record = json.loads(line)
        if not isinstance(record, dict) or not isinstance(record.get('arrival_time'), (int, float)):
            raise CheckError('queue_format_unrecognized')
        count += 1
        deferred += record.get('queue_name') == 'deferred'
        oldest_age = max(oldest_age, max(0, now - record['arrival_time']))
    metrics = {'messages': count, 'deferred_messages': deferred, 'oldest_age_minutes': round(oldest_age / 60, 1)}
    issues = []
    if count >= options.max_queue_messages:
        issues.append('queue_backlog')
    if count and oldest_age >= options.max_queue_age_minutes * 60:
        issues.append('old_queued_messages')
    return result(metrics, issues)


def oom_check(options):
    output = run_checked([
        'journalctl', '--kernel', '--since', f'{options.oom_window_minutes} minutes ago',
        '--no-pager', '--quiet', '--output=json', '--lines=1000',
    ], options.timeout, 4 * MIB)
    entries, matches = 0, 0
    for line in output.splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if not isinstance(record, dict):
            raise CheckError('kernel_journal_format_unrecognized')
        message = record.get('MESSAGE', '')
        if isinstance(message, list):
            message = bytes(message).decode('utf-8', 'replace')
        entries += 1
        matches += bool(OOM_PATTERN.search(message)) if isinstance(message, str) else False
    issues = ['recent_kernel_oom'] if matches else []
    if entries >= 1000:
        issues.append('kernel_journal_scan_limit')
    return result({'window_minutes': options.oom_window_minutes, 'oom_entries': matches, 'entries_scanned': entries}, issues)


def tls_metrics(connection):
    certificate = connection.getpeercert()
    expires = ssl.cert_time_to_seconds(certificate['notAfter'])
    return {
        'certificate_verified': True, 'tls_version': connection.version(),
        'certificate_sha256': hashlib.sha256(connection.getpeercert(binary_form=True)).hexdigest(),
        'certificate_days_remaining': round((expires - time.time()) / 86400, 1),
    }


def imap_check(options):
    context = ssl.create_default_context()
    with socket.create_connection((options.connect_address, 993), options.timeout) as raw:
        with context.wrap_socket(raw, server_hostname=options.hostname) as secure:
            with secure.makefile('rb') as reader:
                greeting = reader.readline(4097)
                if len(greeting) > 4096 or not greeting.upper().startswith(b'* OK '):
                    raise CheckError('imap_greeting_invalid')
                metrics = tls_metrics(secure)
                secure.sendall(b'H1 LOGOUT\r\n')
    issues = ['imap_certificate_expiring'] if metrics['certificate_days_remaining'] < options.certificate_warning_days else []
    return result(metrics, issues)


def smtp_reply(reader):
    lines, expected = [], None
    for _ in range(30):
        line = reader.readline(4097)
        if len(line) > 4096 or len(line) < 4 or not line[:3].isdigit() or line[3:4] not in (b' ', b'-'):
            raise CheckError('smtp_response_invalid')
        code = int(line[:3])
        if expected is not None and code != expected:
            raise CheckError('smtp_response_invalid')
        expected = code
        lines.append(line[4:].strip().upper())
        if line[3:4] == b' ':
            return code, lines
    raise CheckError('smtp_response_limit')


def submission_check(options):
    context = ssl.create_default_context()
    with socket.create_connection((options.connect_address, 587), options.timeout) as raw:
        with raw.makefile('rb') as reader:
            if smtp_reply(reader)[0] != 220:
                raise CheckError('smtp_greeting_invalid')
            raw.sendall(b'EHLO healthcheck.invalid\r\n')
            code, extensions = smtp_reply(reader)
            if code != 250 or b'STARTTLS' not in extensions:
                raise CheckError('smtp_starttls_unavailable')
            raw.sendall(b'STARTTLS\r\n')
            if smtp_reply(reader)[0] != 220:
                raise CheckError('smtp_starttls_rejected')
        with context.wrap_socket(raw, server_hostname=options.hostname) as secure:
            metrics = tls_metrics(secure)
            with secure.makefile('rb') as reader:
                secure.sendall(b'EHLO healthcheck.invalid\r\n')
                code, extensions = smtp_reply(reader)
                if code != 250:
                    raise CheckError('smtp_tls_ehlo_failed')
                metrics['authentication_advertised_after_tls'] = any(line.startswith(b'AUTH ') for line in extensions)
                secure.sendall(b'QUIT\r\n')
                smtp_reply(reader)
    issues = []
    if metrics['certificate_days_remaining'] < options.certificate_warning_days:
        issues.append('submission_certificate_expiring')
    if not metrics['authentication_advertised_after_tls']:
        issues.append('submission_authentication_unavailable')
    return result(metrics, issues)


def website_check(options):
    # A GET, not a HEAD-only probe: confirm that Nginx still serves an HTML page.
    request = urllib.request.Request(options.website, headers={'User-Agent': 'Vprod-mail-health/1.0'})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=options.timeout) as response:
        status = response.status
        https = urllib.parse.urlsplit(response.geturl()).scheme == 'https'
        content_type = response.headers.get_content_type()
        body = response.read(4096).lower()
    html = b'<!doctype html' in body or b'<html' in body
    issues = []
    if status != 200 or not https or content_type != 'text/html' or not html:
        issues.append('website_unhealthy')
    return result({'http_status': status, 'https_verified': https, 'content_type': content_type, 'html_present': html}, issues)


def evaluate(name, callback, options):
    try:
        return callback(options)
    except CheckError as error:
        code = str(error)
    except ssl.SSLCertVerificationError:
        code = 'tls_certificate_verification_failed'
    except (TimeoutError, socket.timeout):
        code = 'timeout'
    except FileNotFoundError:
        code = 'required_file_missing'
    except PermissionError:
        code = 'permission_denied'
    except urllib.error.HTTPError as error:
        return result({'http_status': error.code}, ['http_request_failed'])
    except (OSError, ValueError, TypeError, KeyError, IndexError, urllib.error.URLError):
        code = 'check_unavailable'
    except Exception:
        # Keep monitoring output parseable even when a tool changes its format;
        # exception strings can contain private paths, addresses, or responses.
        code = 'unexpected_check_error'
    return result({}, [code])


def parse_options(arguments=None):
    parser = HealthArgumentParser(description=__doc__)
    parser.add_argument('--hostname', default='mail.vprod.nl')
    parser.add_argument('--connect-address', default='127.0.0.1', help='Local address for verified IMAPS/STARTTLS probes.')
    parser.add_argument('--website', default='https://vprod.nl/')
    parser.add_argument('--mail-root', default='/var/vmail')
    parser.add_argument('--certificate', default='/etc/letsencrypt/live/mail.vprod.nl/fullchain.pem')
    parser.add_argument('--timeout', type=float, default=5)
    parser.add_argument('--min-available-mib', type=int, default=96)
    parser.add_argument('--max-swap-percent', type=float, default=80)
    parser.add_argument('--max-load-per-cpu', type=float, default=2)
    parser.add_argument('--max-disk-percent', type=float, default=85)
    parser.add_argument('--min-disk-free-mib', type=int, default=1024)
    parser.add_argument('--max-queue-messages', type=int, default=20)
    parser.add_argument('--max-queue-age-minutes', type=int, default=60)
    parser.add_argument('--certificate-warning-days', type=int, default=14)
    parser.add_argument('--oom-window-minutes', type=int, default=30)
    return parser.parse_args(arguments)


def main(arguments=None):
    started = time.monotonic()
    checks = {}
    try:
        options = parse_options(arguments)
        hostname = options.hostname.encode('idna').decode('ascii')
        if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', hostname):
            raise ValueError
        options.hostname = hostname
        ipaddress.ip_address(options.connect_address)
        url = urllib.parse.urlsplit(options.website)
        if url.scheme != 'https' or not url.hostname or url.username or url.password:
            raise ValueError
        numeric = vars(options)
        if any(value <= 0 for value in numeric.values() if isinstance(value, (int, float))):
            raise ValueError
        if options.max_disk_percent > 100 or options.max_swap_percent > 100:
            raise ValueError
    except (ValueError, UnicodeError, CheckError):
        checks['configuration'] = result({}, ['invalid_configuration'])
    else:
        for name, callback in (
            ('services', services_check), ('resources', resources_check),
            ('storage', storage_check), ('certificate', certificate_check),
            ('queue', queue_check), ('kernel_oom', oom_check),
            ('imaps', imap_check), ('submission', submission_check),
            ('website', website_check),
        ):
            checks[name] = evaluate(name, callback, options)
    issues = [{'check': name, 'code': issue} for name, check in checks.items() for issue in check['issues']]
    report = {
        'schema_version': 1,
        'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'issue' if issues else 'healthy',
        'duration_seconds': round(time.monotonic() - started, 2),
        'checks': checks, 'issues': issues,
    }
    print(json.dumps(report, sort_keys=True, separators=(',', ':')))
    return 1 if issues else 0


if __name__ == '__main__':
    sys.exit(main())
