#!/usr/bin/env python3
"""PNG structure/dimensions/alpha-channel and exact flat ZIP members. Read-only."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import zlib


def safe_file(root, name):
    path = (root / name).resolve()
    path.relative_to(root)
    if not path.is_file():
        raise ValueError('file missing: ' + str(name))
    return path


def png_info(blob):
    if not blob.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('not PNG')
    pos, info, end, image = 8, None, False, False
    while pos < len(blob):
        if pos + 12 > len(blob):
            raise ValueError('truncated PNG')
        size = struct.unpack('>I', blob[pos:pos+4])[0]
        kind = blob[pos+4:pos+8]
        data = blob[pos+8:pos+8+size]
        if pos + size + 12 > len(blob):
            raise ValueError('truncated chunk')
        crc = struct.unpack('>I', blob[pos+8+size:pos+12+size])[0]
        if zlib.crc32(kind + data) & 0xffffffff != crc:
            raise ValueError('PNG CRC failed')
        if info is None and kind != b'IHDR':
            raise ValueError('IHDR must be first')
        if kind == b'IHDR':
            if info is not None or size != 13:
                raise ValueError('invalid IHDR')
            w, h, depth, color, comp, filt, inter = struct.unpack('>IIBBBBB', data)
            depths = {0: {1,2,4,8,16}, 2: {8,16}, 3: {1,2,4,8}, 4: {8,16}, 6: {8,16}}
            if not w or not h or depth not in depths.get(color, set()) or comp or filt or inter not in {0,1}:
                raise ValueError('invalid PNG header')
            info = {'width': w, 'height': h, 'alpha_channel': color in {4,6}}
        if kind == b'tRNS':
            info['alpha_channel'] = True
        if kind == b'IDAT':
            image = True
        if kind == b'IEND':
            if size or pos + 12 != len(blob):
                raise ValueError('invalid IEND or trailing data')
            end = True
        pos += size + 12
    if not info or not image or not end:
        raise ValueError('incomplete PNG')
    return info


def check(data, root):
    root = Path(root).resolve()
    errors = []
    assets = data.get('assets', [])
    for item in assets:
        try:
            blob = safe_file(root, item['file']).read_bytes()
            if hashlib.sha256(blob).hexdigest() != item['sha256']:
                raise ValueError('hash changed')
            info = png_info(blob)
            for key in ['width', 'height', 'alpha_channel']:
                if info[key] != item[key]:
                    raise ValueError('unexpected ' + key)
        except (KeyError, ValueError, OSError) as exc:
            errors.append('%s: %s' % (item.get('file'), exc))
    bundle = data.get('zip')
    if bundle:
        try:
            with zipfile.ZipFile(safe_file(root, bundle['file'])) as archive:
                names = archive.namelist()
                expected = bundle['members']
                if len(names) != len(set(names)) or set(names) != set(expected):
                    raise ValueError('ZIP member set differs')
                if any('/' in n or '\\' in n or n in {'.', '..'} for n in names):
                    raise ValueError('ZIP must be flat')
                if archive.testzip():
                    raise ValueError('ZIP CRC failed')
                for item in assets:
                    name = Path(item['file']).name
                    if name in expected and hashlib.sha256(archive.read(name)).hexdigest() != item['sha256']:
                        raise ValueError('ZIP asset hash differs: ' + name)
        except (KeyError, ValueError, OSError, zipfile.BadZipFile) as exc:
            errors.append(str(exc))
    return errors


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    p.add_argument('--root', type=Path)
    args = p.parse_args()
    try:
        errors = check(json.loads(args.manifest.read_text()), args.root or args.manifest.parent)
    except (ValueError, OSError) as exc:
        errors = [str(exc)]
    print(json.dumps({'ok': not errors, 'errors': errors,
                      'limit': 'Checks PNG structure, not decoded pixels, visuals or current store policy.'}, ensure_ascii=False, indent=2))
    raise SystemExit(bool(errors))

if __name__ == '__main__':
    main()
