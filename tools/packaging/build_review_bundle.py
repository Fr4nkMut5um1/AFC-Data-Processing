"""Make a bounded, self-contained review snapshot without changing case/lib code.

Usage: python tools/packaging/build_review_bundle.py stage|finalize
The MATLAB export step runs between stage and finalize; see handoff/TEST_DATA.md.
"""
from pathlib import Path
import ast
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
DEST = Path('D:/Users/Frank_7840HSw/Desktop/PIV_Review_20260910')
CASES = {'baseline': 'tandem_baseline_r2', 'controlled': 'tandem_f40a3_phi0_r2'}
HANDOFF = ROOT / 'docs/handoffs/review_20260910'


def write_json(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def stage():
    if DEST.exists():
        raise RuntimeError('Staging destination already exists; do not overwrite an earlier snapshot.')
    DEST.mkdir(parents=True)
    records = []

    def copy(source, relative, purpose):
        if source.stat().st_size > 6 * 1024**2:
            raise RuntimeError(f'Unexpected large non-fixture file: {source}')
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        records.append({'path': target.relative_to(DEST).as_posix(),
                        'original_path': str(source), 'purpose': purpose,
                        'original_modified_utc': datetime.fromtimestamp(source.stat().st_mtime, timezone.utc).isoformat()})

    for folder in ('lib', 'third_party', 'tests', 'tools', 'docs'):
        for source in sorted((ROOT / folder).rglob('*')):
            if not source.is_file() or any(x.startswith('.') or x == '__pycache__' for x in source.relative_to(ROOT / folder).parts):
                continue
            if source.name == 'create_section5_guide.js':
                continue  # failed, unrelated Word tool; documented, not a MATLAB dependency
            suffixes = {'.m', '.py', '.md', '.txt', '.json'}
            if folder == 'docs':
                suffixes |= {'.png', '.svg'}
            if source.suffix.lower() in suffixes or source.name in ('LICENSE', 'NOTICE'):
                copy(source, Path('project') / source.relative_to(ROOT), 'current source / documentation / dependency')
    for source in (ROOT / 'cases/per_case').glob('*.m'):
        copy(source, Path('project') / source.relative_to(ROOT), 'current bootstrap')
    for name in CASES.values():
        for source in (ROOT / 'cases/per_case' / name).glob('*.m'):
            copy(source, Path('project') / source.relative_to(ROOT), 'current case entry')
    for source in (ROOT / 'cases/experiments').glob('*/*.m'):
        copy(source, Path('project') / source.relative_to(ROOT), 'optional research entry')
    for name in ('README.md', 'PROJECT_PROGRESS.md', '.gitignore'):
        copy(ROOT / name, Path('project') / name, 'current project context')
    for source in (ROOT / 'archive/reorganization_20260906').glob('*'):
        if source.is_file() and source.suffix.lower() in {'.md', '.csv', '.json'} and source.stat().st_size < 2 * 1024**2:
            copy(source, Path('provenance/reorganization') / source.name, 'historical migration evidence, not active instructions')
    for source in HANDOFF.iterdir():
        if source.is_file():
            copy(source, Path('handoff') / source.name, 'current handoff requirements')
    copy(HANDOFF / 'START_HERE.md', Path('START_HERE.md'), 'reading entry')
    copy(ROOT / 'tools/packaging/run_review_smoke.m', Path('validation/run_review_smoke.m'), 'portable small-sample check')

    for short, name in CASES.items():
        out = ROOT / 'cases/per_case' / name / 'output'
        for area in ('section5/raw/png', 'section5/raw/csv', 'section5/raw/json', 'preview/section3'):
            for source in sorted((out / area).glob('*')):
                if source.is_file() and source.suffix.lower() in {'.png', '.csv', '.json'}:
                    copy(source, Path('reference_outputs') / short / area / source.name, 'existing reference output, not regenerated')
        for source in sorted((out / 'png').glob('*.png')):
            if source.name.startswith(('02', '06_loglaw', '06c_xi', '06d_modern', '11_friction')):
                copy(source, Path('reference_outputs') / short / 'section2' / source.name, 'existing Section 2 visual reference')
        s4 = out / 'section4_vlsm'
        for name4 in ('summary.json', 'report.md', 'figure_manifest.csv', 'frame_summary_4.csv', 'frame_summary_8.csv'):
            source = s4 / name4
            if source.exists():
                copy(source, Path('reference_outputs') / short / 'section4' / name4, 'existing full-run Section 4 summary; inspect date')
        manifest = s4 / 'figure_manifest.csv'
        if manifest.exists():
            selected = []
            with manifest.open(encoding='utf-8-sig', newline='') as f:
                for row in csv.DictReader(f):
                    source = Path(row.get('PNG', ''))
                    if row.get('Generated') == '1' and source.is_file() and source not in selected:
                        selected.append(source)
                        if len(selected) == 4:
                            break
            for source in selected:
                copy(source, Path('reference_outputs') / short / 'section4/png' / source.name, 'selected existing formal Section 4 PNG from its own manifest')

    # Preserve the previously requested 21-figure explanation as portable Markdown.
    guide_source = ROOT / 'tools/create_section5_guide.js'
    if guide_source.exists():
        js = guide_source.read_text(encoding='utf-8')
        guide = ['# Section 5：21 图与中文讲解', '',
                 '来自本对话最近一次图文说明，图片使用包内相对路径。raw 数据；每 case 独立。', '',
                 '口径补充：二维四象限云图显示 H=1；H=0/1/2 的比较在剖面图中。前次回答的“提高 H 后云图缩小”是一般阈值解释，并非这些固定 H=1 图片实际展示了多 H。', '',
                 '剪应力 -<uv> [m²/s²]；主剪切生产 P=-<uv>dU/dy [m²/s³]；剖面和相位图 x=80–320 mm。', '',
                 'Q2/Q4 对 -<uv> 为正，Q1/Q3 为负。相干细节采用独立色标。', '']
        for short, label in [('baseline', '基准工况'), ('controlled', '受控工况')]:
            match = re.search(r'const ' + short + r' = (\[.*?\n\]);', js, re.S)
            items = ast.literal_eval(match.group(1))
            guide += [f'## {label}', '']
            for i, (title, filename, physical, meaning, plain) in enumerate(items, 1):
                guide += [f'### {i}. {title}', '', f'![{title}]({short}/section5/raw/png/{filename})', '',
                          '**物理表征：** ' + physical, '', '**意味着什么：** ' + meaning, '', '**通俗理解：** ' + plain, '']
        (DEST / 'reference_outputs/SECTION5_GUIDE.md').write_text('\n'.join(guide), encoding='utf-8')

    inventory = []
    params = []
    module_paths = {}
    matlab_files = sorted((DEST / 'project').rglob('*.m'))
    for p in matlab_files:
        rel = p.relative_to(DEST).as_posix()
        parts = [s[1:] for s in p.parent.parts if s.startswith('+')]
        if parts:
            module_paths['.'.join(parts + [p.stem])] = rel
    for p in matlab_files:
        text = p.read_text(encoding='utf-8-sig')
        lines = text.splitlines()
        calls = sorted(set(re.findall(r'\b(?:tblR2|d23)(?:\.[A-Za-z]\w*)+\b', text)))
        record = {'file': p.relative_to(DEST).as_posix(), 'lines': len(lines),
                  'functions': [{'line': i, 'declaration': s.strip()} for i, s in enumerate(lines, 1) if re.match(r'\s*function\b', s)],
                  'sections': [{'line': i, 'title': s.strip()} for i, s in enumerate(lines, 1) if s.startswith('%%')],
                  'package_calls': [{'symbol': c, 'resolved_file': module_paths.get(c)} for c in calls]}
        inventory.append(record)
        if p.name.endswith('_case.m'):
            for i, s in enumerate(lines, 1):
                m = re.match(r'\s*(cfg(?:\.[A-Za-z]\w*)+)\s*=\s*(.*)', s)
                if m:
                    params.append([record['file'], i, m[1], m[2]])
    write_json(DEST / 'provenance/code_index.json', {'scope': 'Static lexical index, not dynamic dependency proof', 'files': inventory})
    with (DEST / 'provenance/parameter_index.csv').open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f); w.writerow(['file', 'line', 'parameter', 'assignment_and_comment']); w.writerows(params)
    write_json(DEST / 'provenance/copied_sources.json', records)
    git = {}
    for label, args in [('head', ['rev-parse', 'HEAD']), ('branch', ['branch', '--show-current']), ('status', ['status', '--short'])]:
        proc = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace')
        git[label] = proc.stdout.strip()
    write_json(DEST / 'provenance/working_tree.json', {'note': 'Actual disk snapshot includes untracked current code; not a clean HEAD export.', **git})
    print(f'STAGED {len(records)} copied files; {len(matlab_files)} MATLAB files; {len(params)} cfg assignments')


def finalize():
    # Refresh handoff records after validation; original computational code is immutable.
    for source in HANDOFF.iterdir():
        if source.is_file():
            shutil.copy2(source, DEST / 'handoff' / source.name)
            shutil.copy2(source, DEST / 'project/docs/handoffs/review_20260910' / source.name)
    shutil.copy2(HANDOFF / 'START_HERE.md', DEST / 'START_HERE.md')
    shutil.copy2(Path(__file__), DEST / 'project/tools/packaging' / Path(__file__).name)
    shutil.copy2(ROOT / 'PROJECT_PROGRESS.md', DEST / 'project/PROJECT_PROGRESS.md')
    copied = json.loads((DEST / 'provenance/copied_sources.json').read_text(encoding='utf-8'))
    computational = [r for r in copied if r['path'].startswith(('project/lib/', 'project/cases/')) and r['path'].endswith('.m')]
    for r in computational:
        assert Path(r['original_path']).read_bytes() == (DEST / r['path']).read_bytes(), r['path']
    assert len(list((DEST / 'reference_outputs').glob('*/section5/raw/png/*.png'))) == 21
    sample_check = json.loads((DEST / 'validation/sample_check_report.json').read_text(encoding='utf-8'))
    assert sample_check['completed'] and all(v['comparison'].startswith('PASS') for v in sample_check['cases'].values())
    size_entries = {}
    for p in DEST.rglob('*'):
        if p.is_file():
            key = p.relative_to(DEST).parts[0]
            size_entries[key] = size_entries.get(key, 0) + p.stat().st_size
    summary = {'created_utc': datetime.now(timezone.utc).isoformat(),
               'included_current_computational_files_unchanged': len(computational),
               'section5_png_count': 21,
               'original_frames_per_case': 12000, 'fixture_frames_per_source_per_case': 48,
               'fixture_grid_matlab': [48, 89, 640], 'fixture_sources': ['raw', 'postproc'],
               'uncompressed_bytes_by_group': size_entries,
               'excluded': ['full experimental DAT sequences', 'full sequence caches', 'full POD intermediate arrays',
                            'GB catalogs', 'full output trees', 'legacy runtime code', 'Git objects',
                            'Draft and literature downloads', 'local MCP/agent configuration', 'credentials']}
    write_json(DEST / 'provenance/package_summary.json', summary)
    manifest = []
    for p in sorted(DEST.rglob('*')):
        if p.is_file() and p.name != 'SHA256SUMS.csv':
            manifest.append([p.relative_to(DEST).as_posix(), p.stat().st_size, hashlib.sha256(p.read_bytes()).hexdigest()])
    with (DEST / 'provenance/SHA256SUMS.csv').open('w', encoding='utf-8', newline='') as f:
        w = csv.writer(f); w.writerow(['path', 'bytes', 'sha256']); w.writerows(manifest)
    zip_path = DEST.with_suffix('.zip')
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in sorted(DEST.rglob('*')):
            if p.is_file():
                z.write(p, (Path(DEST.name) / p.relative_to(DEST)).as_posix())
    with zipfile.ZipFile(zip_path) as z:
        assert z.testzip() is None
        assert all('..' not in Path(n).parts and not Path(n).is_absolute() for n in z.namelist())
    size = zip_path.stat().st_size
    assert size < 150 * 1024**2, f'ZIP exceeded intentional review budget: {size}'
    print(json.dumps({'zip': str(zip_path), 'MiB': round(size / 1024**2, 2), 'files': len(manifest)+1,
                      'uncompressed_MiB': round(sum(r[1] for r in manifest) / 1024**2, 2),
                      'unchanged_computational_files': len(computational), 'zip_integrity': 'PASS'}, ensure_ascii=False))


if __name__ == '__main__':
    {'stage': stage, 'finalize': finalize}[sys.argv[1]]()
