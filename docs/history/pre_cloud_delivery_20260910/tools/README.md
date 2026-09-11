# Tools

Daily calculations use only the two case entries:

- `cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m`
- `cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m`

The shared MATLAB packages live in `lib/+tblR2` and `lib/+d23`.
Add `lib`, not a package directory or `genpath(lib)`, to the MATLAB path.

## Section 5 Delivery

`run_section5_from_saved_case(case_name, source, stage, options)` reads the selected r2 case's
saved configuration and cache, without executing Sections 1-4. Source defaults
to `raw`; `postproc` switches all dependent statistics together. Each case
exports its own `output/section5/<source>/` figures, tables and review metadata.

```matlab
addpath(fullfile(repo_root, 'tools'));
run_section5_from_saved_case('tandem_baseline_r2', 'raw', 'compute');
```

The controlled case is `tandem_f40a3_phi0_r2`. Use `reuse` to regenerate figures
from a matching saved result. See [Section 5 definitions](../docs/SECTION5.md).

## Section 3 Preview

Set `repo_root` to this repository's absolute path, then call:

```matlab
addpath(fullfile(repo_root, 'tools'));
preview_section3();
```

The function locates the f40a3 r2 case from its own file, leaves the caller's
working directory and workspace intact, and loads the existing configuration,
statistics, mean boundary layer and phase MAT files. Profiles retain the saved
raw statistics/phase source; contours retain the configured independent postproc
source. When needed, the original postproc phase-cache calculation still runs.
This is not a promise of a zero-computation preview.

The five unchanged `test_v2_*.png` names are written to
`cases/per_case/tandem_f40a3_phi0_r2/output/preview/section3/`.
Existing images were preserved; this reorganization did not regenerate them.

## Research And Calibration

`tools/research/` contains research entry points, not additional daily cases.
To make the research functions and local helpers available:

```matlab
addpath(fullfile(repo_root, 'lib'));
addpath(fullfile(repo_root, 'tools', 'research'));
addpath(fullfile(repo_root, 'tools', 'research', 'r2_diagnostics'));
```

| Entry or group | Purpose and boundary |
| --- | --- |
| `benchmark_single_frame_structure_identification.m` | Timing from cached Gaussian structure options; assumes compatible historical caches. |
| `iterate_frame_calibration(...)` | Single-frame historical Gaussian/merge parameter experiments. |
| `run_r2_structure_diagnostics.m` | Historical percolation and sensitivity sweeps. |
| `run_r2_wide_percolation_sweep.m` | Historical alpha/seed/merge sweeps; embedded production claims describe the original experiment date. |
| `validate_single_frame_11627.m` | Historical Gaussian/merge experiment on a fixed frame. |
| `run_phaseC_with_figures.m` | Historical 480-frame Gaussian + neighbor-merge trial, not formal Section 4. |
| `run_structure_pod_denoise(...)` | Experimental POD/ Gaussian comparison; separate POD MAT names in the selected case's existing `output/mat`. |
| `tandem_baseline_r2_pod_cluster_case.m` | Experimental extension that first executes the baseline case, then full-resolution/all-frame POD. Can be expensive. |
| `r2_diagnostics/` | POD sweeps, annotation calibration, saved-run comparisons and review utilities, including preserved historical reports. |

For a script, use its full path with MATLAB `run`; for a function, call its
function name after the path setup above. Whole-file execution is the supported
path-resolution mode; Editor scratch sections are not validated.

Existing case MAT output locations are retained. New figures from the old
root-level calibration/trial scripts go under baseline `output/research/`.
Saved-run edge-regression aggregate reports now use that directory too.
The POD/annotation diagnostic family retains its existing `tmp/` input/output
contracts because basis caches, manifests and comparison scripts share them.
Old `tmp/` data and dated experiment runs may now be in the development archive;
restore the needed historical layout or explicitly supply supported path
arguments before using those utilities. Fixed experiment paths and saved
manifest paths are historical references, not evidence those inputs exist.
Python visual-review utilities also require their original external runtime,
credentials and dependencies.

These tools preserve research algorithms and parameter choices. Moving them
does not establish equivalence to the current formal Section 4, prove that
historical caches match current structures, or certify scientific acceptance.
Only static relocation/path checks were performed on 2026-09-06. No MATLAB,
POD decomposition or 12,000-frame job was run.

## Legacy r1 Tools

Seven tools that call only the retired `tbl.periodic`/r1 workflow were moved to
`archive/legacy_r1_20260906/tools/`: `diagnose_actual_tandem_section4_thresholds`,
`export_actual_tandem_vlsm_gallery`, `export_section48_trial_figures`,
`run_control_section4_trial`, `run_section48_trial`,
`validate_actual_tandem_section4` and `review_structure_modules`.
They are preserved for reading and manual restoration; their archived paths
are not maintained as runnable entry points.

The move plan and executed CSV are in
`archive/reorganization_20260906/tool_moves.json` and
`tool_moves.json.executed.csv`. No data files were deleted.

旧 `tools/run_section5` 已移到 `tools/maintenance/run_section5_from_saved_case`，仅供旧布局维护。日常运行本 case 主脚本 Section 0→5；独立 case 的旧配置入口为 `maintenance/run_section5_legacy_config`，必须显式指定配置文件。
