"""Source inventory only. Text matches are INFERRED, never MATLAB STATIC.

Usage: python source_inventory.py CASE_ROOT NEW_OUTPUT_DIRECTORY
No scientific code is executed. Output directory must be new and outside case.
No parser claim: references can include strings, guards and comments; absence
does not establish dead code. Use MATLAB for native dependency evidence.
"""
import hashlib
import json
import re
import sys
from pathlib import Path


def collect(root):
    files, references, sections = [], [], []
    for path in sorted(root.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        data = path.read_bytes()
        files.append({'path': rel, 'bytes': len(data),
                      'sha256': hashlib.sha256(data).hexdigest()})
        if path.suffix != '.m':
            continue
        for number, line in enumerate(data.decode('utf-8-sig').splitlines(), 1):
            if line.startswith('%%'):
                sections.append({'file': rel, 'line': number, 'heading': line})
            for symbol in sorted(set(re.findall(r'\b(?:tblR2|d23)(?:\.[A-Za-z]\w*)+', line))):
                parts = symbol.split('.')
                candidate = Path('lib', *('+' + p for p in parts[:-1]), parts[-1] + '.m')
                references.append({'file': rel, 'line': number, 'symbol': symbol,
                                   'candidate': candidate.as_posix(),
                                   'candidate_exists': (root / candidate).is_file(),
                                   'comment_only': line.lstrip().startswith('%'),
                                   'kind': 'lexical_reference', 'evidence': 'INFERRED'})
    return {'status': 'SOURCE_INVENTORY_ONLY', 'evidence': 'INFERRED',
            'case_name': root.name, 'files': files, 'sections': sections,
            'references': references,
            'limitations': ['Not a MATLAB parser or dependency analyzer.',
                            'References include strings and comments; not call edges.',
                            'No runtime, missing-dependency or dead-code verdict.']}


if __name__ == '__main__':
    root, output = (Path(p).resolve() for p in sys.argv[1:])
    if not root.is_dir() or not (root / (root.name + '_case.m')).is_file():
        raise SystemExit('Expected one case folder containing its main script.')
    if output == root or root in output.parents:
        raise SystemExit('Evidence must be outside the scientific case.')
    result = collect(root)
    output.mkdir(parents=True, exist_ok=False)
    (output / 'source_inventory.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'case': root.name, 'files': len(result['files']),
                      'references': len(result['references']), 'status': result['status']}))
