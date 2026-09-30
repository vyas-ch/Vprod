#!/usr/bin/env python3
"""Publish only public files from a main commit that passed GitHub Actions.

Installed as root-owned code, run by vprod-deploy without sudo. Repository
scripts are never executed on the server. No GitHub token or SSH key needed.
"""
import datetime
import fcntl
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

REPO = 'https://github.com/vyas-ch/Vprod.git'
API = 'https://api.github.com/repos/vyas-ch/Vprod/actions/workflows/website.yml/runs'
BASE = pathlib.Path('/srv/vprod')
CACHE = pathlib.Path('/var/lib/vprod-deploy')
EXTENSIONS = {'.html', '.css', '.js', '.svg', '.webp', '.png', '.ico', '.mp4', '.webm', '.txt', '.xml', '.woff2'}
MAX_BYTES = 100 * 1024 * 1024


def unpack(archive, target):
    total, seen = 0, set()
    handle = tarfile.open(fileobj=archive, mode='r:') if hasattr(archive, 'read') else tarfile.open(archive, 'r:')
    with handle as tf:
        members = tf.getmembers()
        for member in members:
            p = pathlib.PurePosixPath(member.name)
            if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0] != 'public':
                raise ValueError('Unexpected public archive path')
            if any(part.startswith('.') for part in p.parts) or member.name in seen:
                raise ValueError('Hidden or duplicate archive path')
            seen.add(member.name)
            if not (member.isfile() or member.isdir()):
                raise ValueError('Links and special files are not published')
            if member.isfile() and p.suffix.lower() not in EXTENSIONS:
                raise ValueError('File type is not permitted in public')
            total += member.size
            if total > MAX_BYTES:
                raise ValueError('Release too large')
        for member in members:
            destination = target / member.name
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tf.extractfile(member) as source, destination.open('xb') as output:
                    shutil.copyfileobj(source, output)
                destination.chmod(0o644)
    for required in ('index.html', 'app.js', 'style.css', 'site-config.js'):
        if not (target / 'public' / required).is_file():
            raise ValueError('Missing required public file: ' + required)
    for directory in [target, *[p for p in target.rglob('*') if p.is_dir()]]:
        directory.chmod(0o755)


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}


def activate(base, release, verify):
    current = base / 'current'
    previous = os.readlink(current)
    if not re.fullmatch(re.escape(str(base / 'releases')) + r'/[a-f0-9]{40}', previous):
        raise ValueError('Unexpected current release target')
    temporary = base / '.next-release'
    if temporary.is_symlink():
        temporary.unlink()
    temporary.symlink_to(release)
    os.replace(temporary, current)
    try:
        verify()
    except Exception:
        temporary.symlink_to(previous)
        os.replace(temporary, current)
        raise
    return previous


def fetch_json(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'Vprod-deploy', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def git(*args):
    env = {**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}
    return subprocess.check_output(['/usr/bin/git', *args], env=env, timeout=90)


def check_live(release):
    # Fresh requests: do not use browser caches. TLS/hostname validation remains on.
    for name in ('index.html', 'site-config.js', 'app.js', 'style.css'):
        url = 'https://vprod.nl/' + ('' if name == 'index.html' else name)
        with urllib.request.urlopen(url, timeout=15) as response:
            if response.read() != (release / 'public' / name).read_bytes():
                raise RuntimeError('Live content differs: ' + name)
    movie = release / 'public/assets/vprod-montage.mp4'
    if movie.exists():
        request = urllib.request.Request('https://vprod.nl/assets/vprod-montage.mp4', headers={'Range': 'bytes=0-99'})
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status != 206 or response.read() != movie.read_bytes()[:100]:
                raise RuntimeError('Video byte-range check failed')


def main():
    with (CACHE / 'deploy.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sha = git('ls-remote', REPO, 'refs/heads/main').decode().split()[0]
        if not re.fullmatch(r'[a-f0-9]{40}', sha):
            raise ValueError('Invalid Git commit')
        release = BASE / 'releases' / sha
        if os.readlink(BASE / 'current') == str(release):
            print('Already current:', sha)
            return
        runs = fetch_json(API + '?branch=main&event=push&head_sha=' + sha + '&per_page=10')['workflow_runs']
        runs = [r for r in runs if r['head_sha'] == sha and r['head_branch'] == 'main' and r['event'] == 'push']
        latest = max(runs, key=lambda r: r['id']) if runs else None
        if not latest or latest['status'] != 'completed' or latest['conclusion'] != 'success':
            print('Waiting for successful GitHub checks:', sha)
            return
        repo = CACHE / 'repo.git'
        if not repo.exists():
            git('init', '--bare', str(repo))
        git('--git-dir=' + str(repo), 'fetch', '--depth=1', REPO, sha)
        if git('--git-dir=' + str(repo), 'rev-parse', 'FETCH_HEAD').decode().strip() != sha:
            raise RuntimeError('Fetched commit differs')
        archive = git('--git-dir=' + str(repo), 'archive', '--format=tar', sha, 'public')
        if len(archive) > MAX_BYTES:
            raise ValueError('Archive too large')
        staging = pathlib.Path(tempfile.mkdtemp(prefix='.stage-', dir=BASE / 'releases'))
        try:
            unpack(io.BytesIO(archive), staging)
            manifest = hashes(staging / 'public')
            if release.exists():
                if hashes(release / 'public') != manifest:
                    raise ValueError('Existing release content differs')
            else:
                staging.rename(release)
            previous = activate(BASE, release, lambda: check_live(release))
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            report = {'commit': sha, 'previous': previous, 'installed_at': now,
                      'github_run': latest['html_url'], 'https_checks': 'passed', 'public_sha256': manifest}
            (BASE / 'deployments' / (now.replace(':', '-') + '-' + sha[:12] + '.json')).write_text(json.dumps(report, indent=2))
            temp_status = BASE / '.deploy-status'
            temp_status.write_text(f'commit={sha}\ninstalled_at={now}\nhttps_checks=passed\nsource=GitHub Actions\n')
            os.replace(temp_status, BASE / 'deploy-status.txt')
            print('Deployed:', sha, latest['html_url'])
        finally:
            if staging.exists():
                shutil.rmtree(staging)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--validate':
        with tempfile.TemporaryDirectory() as folder:
            unpack(sys.argv[2], pathlib.Path(folder))
        print('Public archive valid')
    else:
        main()
