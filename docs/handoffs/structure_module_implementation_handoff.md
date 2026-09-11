# Section 4 structure-module implementation handoff

## Implemented contracts

- `simple_gaussian_filter2` accepts directional sigma/radius, kernel and boundary options, mask-aware support, and writes metadata.
- `identify_structures` preserves the signed 2-D project catalog and adds geometric plus velocity-pulse-weighted centres.
- `paper_proxy` is a separate audit catalog using `|u'|/u_rms >= 1`, strict `Lx/delta99 > 3`, and explicit wall-normal comparability flags.
- `identify_quadrant_structures` adds Q2/Q4 objects, H, overlap-based parent attachment, and `unattached` status.
- `threshold_calibration_scan` scans alpha and H nodes with bootstrap intervals and never silently locks a threshold.
- `conditional_structure_average` accumulates geometric and velocity-weighted centre windows with valid-count/coverage maps.
- `conditional_spatial_spectra` provides matched same-frame SS/noSS windows, separate `Lx_bbox` and spectral wavelength metadata, zero-padding provenance, and low-wavenumber flags.
- `benchmark_structure_tracking` compares three short-run association models and labels the result benchmark-only.

## Real-data gates completed

- Tandem baseline trial: Section 4–8 trial completed with limits; paper proxy produced `paper_criteria_available`.
- Baseline 48-frame integrated gate: 446 signed objects, 1,867 Q2/Q4 objects, both centre methods, threshold scan, and benchmark output.
- Controlled f40a3 phi0 48-frame integrated gate: total and random conditional averages both produced; no ERROR diagnostics; paper proxy and alpha/H calibration enabled.
- Tandem baseline formal full run: completed with limits. The structure MAT contains the new fields; product manifest P01–P19 is complete and no ERROR diagnostic was emitted.
- SS/noSS spectra are enabled in the formal tandem baseline/control configurations. Because the measured wall-normal FOV is finite, the default spectral window is explicitly narrower than the conditional-average window (`x/delta99 = [-1,1]`, `y/delta99 = [-0.1,0.1]`). The noSS partner tries both streamwise sides and retains the side with the larger valid paired support; no padding or extrapolation is used.
- Spectral wavelength normalization is stored as `lambda_x/delta99` using consistent SI units (metres/metres). `Lx_bbox/delta99` remains the geometric component length and is never substituted for `lambda_x/delta99`.

## Expected run command

```matlab
cd('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation');
run(fullfile('cases','per_case','tandem_baseline_r1','tandem_baseline_r1_case.m'));
run(fullfile('cases','per_case','tandem_f40a3_phi0_r1','tandem_f40a3_phi0_r1_case.m'));
```

The controlled full run is intentionally allowed to remain long-running because it rebuilds two 6000-frame raw/PostProc sources before computing total/random and 24 phase bins. Its diagnostics and output MAT files must be reviewed before marking the final full-data gate complete.

The formal cases use `conditional_spectra.enabled = true`; a spectrum result with zero paired events is retained as `completed_with_limits` and must be treated as a FOV/coverage limitation rather than as a successful physical comparison. The latest real-data direct gates produced 50/50 baseline pairs and 8/8 total plus 8/8 random control pairs with the corrected SI normalization.
