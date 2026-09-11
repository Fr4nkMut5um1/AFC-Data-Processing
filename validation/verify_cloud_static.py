#!/usr/bin/env python3
"""Read-only release audit. No MATLAB execution or scientific array calculation.

Run from any directory: python /path/to/project/validation/verify_cloud_static.py
Optional --original-bundle points to the original extracted ZIP root (project/,
fixtures/, handoff/). Optional --original-zip verifies the retained ZIP separately.
--report accepts a NEW file only. There is no record/update-baseline mode.
Parameter checks describe the delivered snapshot, not limits on user editing.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys


CASES = ('tandem_baseline_r2', 'tandem_f40a3_phi0_r2')


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def files_under(root):
    return {p.relative_to(root).as_posix(): p for p in root.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-bundle', type=Path)
    parser.add_argument('--original-zip', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.report is not None and args.report.exists():
        parser.error('Existing report refused; choose a new path. Nothing overwritten.')
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'validation/protected_sources.sha256.json').read_text(encoding='utf-8'))
    failures = []
    checks = []

    def check(condition, name, detail=''):
        checks.append({'check': name, 'status': 'PASS_STATIC' if condition else 'FAIL', 'detail': detail})
        if not condition:
            failures.append(name)

    def verify_hashes(base, expected, label):
        differences = []
        for relative, expected_hash in expected.items():
            path = base / relative
            if not path.is_file():
                differences.append(relative + ': missing')
            elif sha256(path) != expected_hash:
                differences.append(relative + ': SHA-256 differs')
        check(not differences, label, {'files': len(expected), 'differences': differences})

    for case_name in CASES:
        case = root / 'cases/per_case' / case_name
        verify_hashes(case, manifest['files'], case_name + ': unchanged original files/resources')
        text = (case / (case_name + '_case.m')).read_text(encoding='utf-8')
        check(re.findall(r'^%% (\d)\.', text, re.M) == list('0123456789'),
              case_name + ': section title text only (NOT Editor Run Section)')
        zero = text.split('%% 1.', 1)[0]
        heavy_calls = re.findall(
            r'\b(clearvars|clc|prepare_sequence_cache|resolve_case_repeats|load|matfile|'
            r'write_case_card|mean_stats_cache|section5_run)\s*\(', zero)
        check(not heavy_calls, case_name + ': no listed heavy calls in Section 0 text', heavy_calls)
        unwanted = [name for name in ('bootstrap_r2_case', 'recover_sources_from_cache',
                    'transport_statistics', 'restoredefaultpath', 'savepath') if name in text]
        check(not unwanted, case_name + ': no listed legacy daily entry references', unwanted)
        fields = {key: re.sub(r'\s+', '', value) for key, value in re.findall(
            r'^(cfg\.[A-Za-z0-9_.]+)\s*=\s*([^;]+);', zero, re.M)}
        expected = {
            'cfg.fs': '960', 'cfg.n_frames': '6000', 'cfg.total_frames': '2*cfg.n_frames',
            'cfg.formal_required_frames': '6000', 'cfg.allow_debug_snapshot': 'false',
            'cfg.grid_size': '[64091]', 'cfg.wall_side': "'top'",
            'cfg.phase.n_bins': '[]' if case_name == CASES[0] else '24',
            'cfg.phase.minimum_samples_per_bin': '[]' if case_name == CASES[0] else '20',
            'cfg.phase_preview.marker_stride': '1', 'cfg.phase_preview.smooth_points': '5',
            'cfg.sources.raw.offsets': '[00]', 'cfg.sources.postproc.offsets': '[00]',
            'cfg.transport.source': "'raw'", 'cfg.transport.frame_mode': "'all'",
            'cfg.transport.stress_fraction_floor': '1e-6',
            'cfg.rebuild_cache': "strcmp(cfg.stages.cache,'compute')",
            'cfg.stages.cache': "'reuse'", 'cfg.stages.statistics': "'reuse'",
            'cfg.stages.mean_bl': "'reuse'", 'cfg.stages.structures': "'compute'",
            'cfg.stages.transport': "'skip'",
            'cfg.stages.phase': "'skip'" if case_name == CASES[0] else "'reuse'",
            'cfg.stages.figures': "'skip'" if case_name == CASES[0] else "'compute'",
        }
        for stage in ('temporal', 'spatial', 'pod', 'dmd', 'lcs', 'spod', 'correlations', 'harmonics'):
            expected['cfg.stages.' + stage] = "'skip'"
        differences = {key: {'release': value, 'actual': fields.get(key)}
                       for key, value in expected.items() if fields.get(key) != value}
        check(not differences, case_name + ': release parameter declarations (not executed cfg)', differences)
        check(len(re.findall(r'^cfg.rebuild_cache\s*=', text, re.M)) == 1,
              case_name + ': one rebuild_cache derivation')
        prefix = 'Tandem_Baseline' if case_name == CASES[0] else 'Tandem_f40A3_Phi+0'
        for source, role in (('raw', 'PIV'), ('postproc', 'PostProc')):
            declaration = fields.get('cfg.sources.' + source + '.ids')
            wanted = "{'%s_%s_3rd','%s_%s_2nd'}" % (prefix, role, prefix, role)
            check(declaration == wanted, case_name + ': ' + source + ' explicit repeat order', declaration)
        adapter = (case / 'lib/+tblR2/section4_vlsm_analysis.m').read_text(encoding='utf-8')
        check('if nt ~= cfg.total_frames || nt ~= 12000 || ny ~= 89 || nx ~= 640' in adapter,
              case_name + ': formal S4 gate text remains')

    first = root / 'cases/per_case' / CASES[0]
    second = root / 'cases/per_case' / CASES[1]
    for folder in ('lib', 'third_party'):
        a, b = files_under(first / folder), files_under(second / folder)
        missing = sorted(set(a) ^ set(b))
        different = sorted(name for name in set(a) & set(b) if sha256(a[name]) != sha256(b[name]))
        check(not missing and not different, folder + ': both case copies identical',
              {'files_each': len(a), 'different_file_sets': missing, 'different_bytes': different})
        editorial = [name for name, path in a.items()
                     if not (root / folder / name).is_file() or sha256(path) != sha256(root / folder / name)]
        check(not editorial, folder + ': local copies agree with corresponding maintenance files', editorial)

    original_count = 0
    if args.original_bundle is not None:
        original_manifest = json.loads((root / 'validation/original_bundle.sha256.json').read_text(encoding='utf-8'))
        verify_hashes(args.original_bundle, original_manifest, 'original extracted bundle including smoke_expected')
        original_count += len(original_manifest)
        source = args.original_bundle / 'validation/run_review_smoke.m'
        if source.is_file():
            old = source.read_text(encoding='utf-8')
            new = (root / 'validation/run_review_smoke_for_case.m').read_text(encoding='utf-8')
            marker = 'function compare_values'
            check(marker in old and marker in new and old.split(marker, 1)[1] == new.split(marker, 1)[1],
                  'original smoke comparison body/tolerances preserved as text')
    if args.original_zip is not None:
        check(args.original_zip.is_file() and sha256(args.original_zip) == manifest['original_zip_sha256'],
              'original ZIP SHA-256')
        original_count += 1

    report = {
        'status': 'FAIL_STATIC' if failures else 'PASS_STATIC_ONLY',
        'scope': 'File bytes and release text only. No MATLAB, Editor execution or numerical acceptance.',
        'checked_utc': datetime.now(timezone.utc).isoformat(),
        'project_root': str(root),
        'protected_original_files_per_case': len(manifest['files']),
        'original_evidence_files_checked': original_count,
        'checks': checks,
        'matlab_dynamic_acceptance': 'NOT_EXECUTED',
        'formal_data_acceptance': 'NOT_EXECUTED',
        'failures': failures,
    }
    if args.report is not None:
        # Exclusive creation also refuses a file created after the initial check.
        with args.report.open('x', encoding='utf-8') as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    print(json.dumps({'status': report['status'], 'checks': len(checks),
                      'original_evidence_files': original_count,
                      'failures': failures, 'matlab': 'NOT_EXECUTED'}, ensure_ascii=False))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
