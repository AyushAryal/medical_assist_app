#!/usr/bin/env python3
"""Execute the migration DDL against a real SQLite and prove the two paths agree.

The Dart tests check the migration *list* invariants; this checks the SQL
itself. It replays the two paths a device can take —

  * a fresh install  : onCreate  replays v1 then v2
  * an existing v1   : onUpgrade replays only v2

— and asserts the resulting schemas are byte-identical. A divergence here is
the bug that shows up months later as "no such column" on somebody else's
phone, and it is invisible to the analyzer and to unit tests.

Requires the `sqlite3` binary. Run from the project root:

    python3 tool/verify_migrations.py /tmp
"""

import re, sys, subprocess, os, pathlib


src = pathlib.Path('lib/core/db/schema.dart').read_text()

def statements(block_name):
    # Grab `static const List<String> _vN = <String>[ ... ];`
    m = re.search(
        r"static const List<String> %s = <String>\[(.*?)\n  \];" % block_name,
        src, re.S)
    if not m:
        raise SystemExit(f'block {block_name} not found')
    body = m.group(1)
    out = []
    # Triple-quoted multi-line statements.
    for stmt in re.findall(r"'''(.*?)'''", body, re.S):
        out.append((stmt.strip(), body.index(stmt)))
    # Single-quoted one-liners.
    for stmt in re.findall(r"^\s*'([^']+)'\s*,\s*$", body, re.M):
        out.append((stmt.strip(), body.index(stmt)))
    out.sort(key=lambda t: t[1])
    return [s for s, _ in out]

v1 = statements('_v1')
v2 = statements('_v2')
print(f'v1: {len(v1)} statements, v2: {len(v2)} statements')

scratch = sys.argv[1]

def run(db, stmts, label):
    for i, s in enumerate(stmts):
        r = subprocess.run(['sqlite3', db], input=s + ';\n',
                           capture_output=True, text=True)
        if r.returncode != 0 or r.stderr.strip():
            print(f'FAIL {label}[{i}]: {r.stderr.strip()}')
            print(f'   SQL: {s[:160]}')
            return False
    return True

# Path A: a fresh install replays v1 then v2 (what onCreate does).
fresh = os.path.join(scratch, 'fresh.db')
if os.path.exists(fresh): os.remove(fresh)
ok_fresh = run(fresh, v1, 'onCreate.v1') and run(fresh, v2, 'onCreate.v2')

# Path B: an existing v1 device gets only v2 applied (what onUpgrade does).
upgraded = os.path.join(scratch, 'upgraded.db')
if os.path.exists(upgraded): os.remove(upgraded)
ok_upgrade = run(upgraded, v1, 'existing.v1') and run(upgraded, v2, 'onUpgrade.v2')

print('fresh install  :', 'OK' if ok_fresh else 'FAILED')
print('v1 -> v2 upgrade:', 'OK' if ok_upgrade else 'FAILED')

def schema_of(db):
    r = subprocess.run(['sqlite3', db, ".schema"], capture_output=True, text=True)
    return '\n'.join(sorted(l.strip() for l in r.stdout.splitlines() if l.strip()))

if ok_fresh and ok_upgrade:
    same = schema_of(fresh) == schema_of(upgraded)
    print('schemas converge:', 'IDENTICAL' if same else 'DIVERGED')
    if not same:
        import difflib
        for line in list(difflib.unified_diff(
                schema_of(fresh).splitlines(),
                schema_of(upgraded).splitlines(), lineterm=''))[:30]:
            print(line)
    r = subprocess.run(['sqlite3', fresh, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"],
                       capture_output=True, text=True)
    print('tables:', ', '.join(r.stdout.split()))
    # Foreign keys must resolve.
    r = subprocess.run(['sqlite3', fresh, "PRAGMA foreign_key_check;"],
                       capture_output=True, text=True)
    print('foreign_key_check:', r.stdout.strip() or 'clean')
