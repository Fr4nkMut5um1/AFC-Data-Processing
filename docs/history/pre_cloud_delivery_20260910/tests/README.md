# Active validation

These tests cover the two current r2 cases and the shared MATLAB packages
in `lib/+tblR2` and `lib/+d23`. Run commands from the repository root.

Offline checks (Python with NumPy):

```text
python tests/matlab_check.py
python tests/test_r2_extracted_modules.py
```

In MATLAB, run the script tests with `run(fullfile(pwd, 'tests', '<name>.m'))`.
Run function-based tests with `runtests(fullfile(pwd, 'tests', '<name>.m'))`
and inspect/assert their results. The function-based tests are
`test_deshpande2023_baseline`, `test_r2_section4_vlsm_figures`, and
`test_r2_bootstrap_paths`. Other active MATLAB tests are scripts.

The bootstrap test checks both cases from repository and case working
directories without executing the scientific pipeline. Numerical smoke
tests create synthetic data; some require MATLAB toolboxes and figure support.
Do not recursively add the whole repository to the MATLAB path.

`test_r2_section5_transport.m` checks analytic repeat/phase decompositions,
paired validity, rejected bins, signed quadrants and H=0 closure, frame/source
selection, gradient units and single-column grids, single-repeat controlled
data, plus source-specific compute/reuse invalidation. It uses temporary caches
and does not alter scientific outputs.

Historical tbl/r1 tests are preserved in
`archive/legacy_r1_20260906/tests/` for reading and deliberate restoration.
They are excluded from active validation and are not maintained as runnable
tests in the current layout. Moves are recorded in
`archive/reorganization_20260906/test_moves.json.executed.csv`.
