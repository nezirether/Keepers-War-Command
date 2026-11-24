#!/usr/bin/env python3
"""Build and verify KWC 2.0 private test ZIPs from COMMITTED git blobs.

Outputs (dist/):
  KWC-2.0-public-private-test.zip    -> KeepersWarCommand/
  KWCC-2.0-officer-private-test.zip  -> KeepersWarCommand_Command/
  KWC-2.0-combined-private-test.zip  -> both folders + LIVE_SMOKE_TEST.md
  MANIFEST.txt                       -> versions, commit, file counts, SHA-256
Refuses to package with uncommitted changes in the add-on folders.
"""
import argparse, hashlib, io, os, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, 'dist')
ADDONS = ['KeepersWarCommand', 'KeepersWarCommand_Command']
EXCLUDE_SUFFIX = ('.md', '.txt.legacy')

def git(*args, binary=False):
    out = subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True)
    return out.stdout if binary else out.stdout.decode()

def committed_files(addon):
    names = git('ls-tree', '-r', '--name-only', 'HEAD', addon).splitlines()
    return [n for n in names if not n.endswith(EXCLUDE_SUFFIX)]

ALLOWED_EXT = ('.lua', '.toc', '.tga', '.txt')

def toc_entries(addon):
    raw = git('show', f'HEAD:{addon}/{addon}.toc')
    files, meta = [], {}
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith('##'):
            k, _, v = line[2:].partition(':'); meta[k.strip()] = v.strip()
        elif line and not line.startswith('#'):
            files.append(f'{addon}/' + line.replace('\\', '/'))
    return files, meta

def build(zip_name, addons, extras=(), output_dir=DIST):
    path = os.path.join(output_dir, zip_name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for addon in addons:
            for name in committed_files(addon):
                data = git('show', f'HEAD:{name}', binary=True)
                info = zipfile.ZipInfo(name, date_time=(2026, 11, 23, 12, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                z.writestr(info, data)
        for arc, src in extras:
            data = git('show', f'HEAD:{src}', binary=True)
            info = zipfile.ZipInfo(arc, date_time=(2026, 11, 23, 12, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    return path

def verify(path, addons, extras=()):
    problems = []
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad: problems.append(f'CRC failure: {bad}')
        names = z.namelist()
        tops = {n.split('/')[0] for n in names if '/' in n}
        if tops != set(addons): problems.append(f'top-level folders {sorted(tops)} != {addons}')
        for addon in addons:
            files, meta = toc_entries(addon)
            missing = [f for f in files if f not in names]
            if missing: problems.append(f'{addon}: TOC files missing in zip: {missing}')
            if meta.get('Interface') != '16001': problems.append(f'{addon}: Interface {meta.get("Interface")}')
        for n in names:
            if n in [e[0] for e in extras]: continue
            if z.read(n) != git('show', f'HEAD:{n}', binary=True): problems.append(f'not byte-identical: {n}')
            if n.startswith('tests/') or '/tests/' in n or n.endswith('.legacy'): problems.append(f'dev file shipped: {n}')
            if not n.endswith(ALLOWED_EXT) and n not in [e[0] for e in extras]: problems.append(f'unexpected file type shipped: {n}')
        count = len(names)
    return problems, count

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 16), b''): h.update(chunk)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public-only', action='store_true', help='Build only the public KWC ZIP.')
    public_only = parser.parse_args().public_only
    selected = ADDONS[:1] if public_only else ADDONS
    dirty = git('status', '--porcelain', '--', *selected).strip()
    if dirty:
        print('Refusing to package: uncommitted changes in add-on folders:\n' + dirty); return 1
    output_dir = DIST
    commit = git('rev-parse', 'HEAD').strip()
    branch = git('rev-parse', '--abbrev-ref', 'HEAD').strip()
    jobs = [
        ('KWC-2.0-public-private-test.zip', ['KeepersWarCommand'], ()),
        ('KWCC-2.0-officer-private-test.zip', ['KeepersWarCommand_Command'], ()),
        ('KWC-2.0-combined-private-test.zip', ADDONS, (('LIVE_SMOKE_TEST.md', 'docs/LIVE_SMOKE_TEST.md'),)),
    ]
    if public_only:
        from theme_art import check
        try:
            check(lambda path: git('show', f'HEAD:{path}', binary=True),
                  paths=committed_files(selected[0]))
            import json
            from alert_art import check as check_alerts
            problems, _ = check_alerts(
                json.loads(git('show', 'HEAD:docs/ALERT_ART.json', binary=True)),
                reader=lambda path: git('show', f'HEAD:{path}', binary=True),
                paths=committed_files(selected[0]))
            if problems:
                raise ValueError('Alert artwork: ' + ', '.join(problems))
        except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
            print(f'Public artwork preflight failed: {error}')
            return 1
        _, meta = toc_entries(selected[0])
        version = meta['Version']
        output_dir = os.path.join(DIST, version)
        name = f'KWC-{version}-public-private-test.zip'
        jobs = [(name, selected, ())]
    os.makedirs(output_dir, exist_ok=True)
    lines = [f'KWC 2.0 private test packages', f'branch {branch}  commit {commit}', '']
    for addon in selected:
        _, meta = toc_entries(addon)
        lines.append(f'{addon}: Version {meta.get("Version")}  Interface {meta.get("Interface")}')
    lines.append('')
    ok = True
    for name, addons, extras in jobs:
        path = build(name, addons, extras, output_dir)
        problems, count = verify(path, addons, extras)
        digest = sha256(path)
        status = 'OK' if not problems else 'FAIL'
        ok = ok and not problems
        lines.append(f'{name}\n  files {count}  bytes {os.path.getsize(path)}  verify {status}\n  sha256 {digest}')
        for p in problems: lines.append('  ! ' + p)
    text = '\n'.join(lines) + '\n'
    with open(os.path.join(output_dir, 'MANIFEST.txt'), 'w') as f: f.write(text)
    print(text)
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
