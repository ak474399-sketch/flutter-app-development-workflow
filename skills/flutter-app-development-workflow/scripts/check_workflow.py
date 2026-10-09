#!/usr/bin/env python3
"""Read-only checks. Does not grant approval or prove its authenticity."""
import argparse
import hashlib
import json
from pathlib import Path

KINDS = {'static', 'runtime', 'user_decision', 'inference', 'pending'}
STATES = {'pending', 'in_progress', 'accepted', 'not_applicable'}

def artifact(root, item, errors, label):
    try:
        path = (root / item['file']).resolve()
        path.relative_to(root)
        if not path.is_file():
            raise ValueError('file missing')
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != item.get('sha256'):
            raise ValueError('hash changed or missing')
    except (KeyError, TypeError, ValueError, OSError) as exc:
        errors.append('%s: %s' % (label, exc))

def check(data, root, target=None):
    root = Path(root).resolve()
    errors = []
    if data.get('schema') != 1:
        errors.append('unsupported schema')
    modules = data.get('modules', {})
    if modules.get('firebase') is not True or modules.get('meta') is not True:
        errors.append('required Firebase/Meta modules missing')
    stages = data.get('stages', [])
    ids = [s.get('id') for s in stages]
    if len(ids) != len(set(ids)) or None in ids:
        errors.append('stage IDs missing or duplicated')
    index = {s.get('id'): s for s in stages}
    sources = data.get('sources', [])
    source_ids = [s.get('id') for s in sources]
    if len(source_ids) != len(set(source_ids)) or None in source_ids:
        errors.append('source IDs missing or duplicated')
    for source in sources:
        if source.get('type') not in KINDS or not source.get('reference'):
            errors.append('invalid source: %s' % source.get('id'))
    pages = data.get('pages', [])
    page_ids = {p.get('id') for p in pages}
    if len(page_ids) != len(pages) or None in page_ids:
        errors.append('page IDs missing or duplicated')
    for kind in ['pages', 'interactions', 'assets']:
        for item in data.get(kind, []):
            label = '%s:%s' % (kind, item.get('id'))
            refs = item.get('source_ids', [])
            if not refs or any(ref not in source_ids for ref in refs):
                errors.append(label + ': unmapped source')
            if kind != 'pages' and item.get('page') not in page_ids:
                errors.append(label + ': unknown page')
            if kind == 'assets' and item.get('status') == 'complete':
                if item.get('placeholder') == 'icon' and item.get('role') in {'hero', 'illustration'}:
                    errors.append(label + ': placeholder cannot count as complete image')
                artifact(root, item, errors, label)
    visiting, visited = set(), set()
    def walk(key):
        if key in visiting:
            errors.append('cyclic dependency: ' + str(key))
            return
        if key in visited or key not in index:
            return
        visiting.add(key)
        for dep in index[key].get('requires', []):
            walk(dep)
        visiting.remove(key)
        visited.add(key)
    for key in ids:
        walk(key)
    for stage in stages:
        sid = stage.get('id')
        state = stage.get('status')
        if state not in STATES:
            errors.append(str(sid) + ': invalid stage state')
        deps = stage.get('requires', [])
        if any(d not in index for d in deps):
            errors.append(str(sid) + ': missing dependency')
        needs_gate = state in {'in_progress', 'accepted', 'not_applicable'} or sid == target
        if needs_gate:
            for dep in deps:
                if index.get(dep, {}).get('status') not in {'accepted', 'not_applicable'}:
                    errors.append(str(sid) + ': dependency not accepted: ' + str(dep))
        if needs_gate and state != 'not_applicable':
            if not stage.get('scope') or not stage.get('criteria'):
                errors.append(str(sid) + ': scope/criteria missing')
            for item in stage.get('inputs', []):
                artifact(root, item, errors, str(sid) + ':input')
        if state in {'accepted', 'not_applicable'}:
            approval = stage.get('approval') or {}
            if approval.get('revision') != stage.get('revision'):
                errors.append(str(sid) + ': stale approval revision')
            if any(not approval.get(k) for k in ['quote', 'message_ref', 'time']):
                errors.append(str(sid) + ': user approval evidence missing')
            if state == 'not_applicable':
                if not stage.get('na_reason'):
                    errors.append(str(sid) + ': not-applicable reason missing')
            else:
                if not stage.get('outputs'):
                    errors.append(str(sid) + ': accepted without outputs')
                for item in stage.get('outputs', []):
                    artifact(root, item, errors, str(sid) + ':output')
    if target is not None and target not in index:
        errors.append('target stage not found')
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--for-stage')
    args = parser.parse_args()
    try:
        data = json.loads(args.manifest.read_text())
        errors = check(data, args.root or args.manifest.parent, args.for_stage)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        errors = [str(exc)]
    print(json.dumps({'ok': not errors, 'errors': errors,
                      'limit': 'Does not verify user approval authenticity, UI or business behavior.'}, ensure_ascii=False, indent=2))
    raise SystemExit(1 if errors else 0)

if __name__ == '__main__':
    main()
