# Section 5 Delivery Review

Date: 2026-09-06. MATLAB R2022b. Scope: independent raw-source Section 5
deliverables for the two current r2 cases. No cross-case comparison figures.

## Delivered

| Case | Selected frames | PNG | Editable FIG | CSV |
|---|---:|---:|---:|---:|
| tandem_baseline_r2 | 12000 | 6 | 6 | 3 |
| tandem_f40a3_phi0_r2 | 12000 | 15 | 15 | 4 |

Each case additionally has its own MAT result and `json/section5_review.json`
under `output/section5/raw/`. All 49 figure/table paths listed in the two JSON
manifests exist. Source-specific compute and subsequent strict reuse both
completed successfully. The original caches and Sections 1-4 products remain
in their existing locations.

## Numerical Evidence

| Check | Case | Relative RMS residual | Maximum absolute residual |
|---|---|---:|---:|
| H=0 total quadrant sum | baseline | 1.791e-15 | 2.220e-14 m2/s2 |
| H=0 total quadrant sum | controlled | 1.435e-15 | 2.043e-14 m2/s2 |
| Total = coherent + random stress | controlled | 1.196e-15 | 4.874e-14 m2/s2 |
| Same identity within phase bins | controlled | 2.754e-15 | 1.066e-12 m2/s2 |
| Main-shear production decomposition | controlled | 1.238e-15 | 8.367e-11 m2/s3 |
| H=0 random quadrant sum | controlled | 8.394e-16 | 4.263e-14 m2/s2 |

Baseline retained 54,425 spatial statistical points and 48,658 buffered
production points. Controlled retained 54,424 and 48,657, respectively.
Controlled phase-bin rejection excluded 4,328 paired samples before the final
spatial acceptance criterion. All reported components share admitted support.

The masked FD/RBF-FD difference is at most 1.070e-11 s^-1 for baseline and
1.153e-11 s^-1 for controlled. The nearly uniform grid makes these three-node
schemes coincide to floating-point accuracy. A near-uniform gray difference
panel is therefore expected; it does not establish measurement accuracy.

## Tests And Review

Passed MATLAB scripts:

- `test_r2_section5_transport`: analytic moments, opposite phase responses and
  repeat offsets, paired validity, rejected bins, H=0 closure, strict hole
  equality, signed fractions, frame subsets, raw/postproc scaling and mismatch,
  single-repeat controlled data, source-specific reuse invalidation, gradient
  units on nonuniform ascending/descending grids, and single-column rendering
  with optional figure configuration omitted.
- `test_compact_case_contract` and `test_r2_baseline_control_contract`.
- `test_r2_library_contract`.
- `test_r2_phase_smoke` and `test_r2_cache_statistics_smoke`.

Python structural validation passed for 234 MATLAB files, and
`test_r2_extracted_modules.py` passed. Independent code review findings were
fixed and rechecked: single-repeat random reads, obsolete Section 5 dependencies,
summary output paths, single-column graphics and optional figure configuration.

All 21 final PNGs were opened for visual inspection across the primary and
independent reviews. No unresolved blank-data, label-overlap or export failures
were found. Gradient roundoff and the weak coherent overview were explicitly
checked against numerical ranges; neither is missing data.

## Figure Iterations

The first full-extrema color range hid the bulk flow behind isolated edge
extrema. Final colors use the 99.5th percentile of absolute finite values,
with limits, full extrema and clipping counts recorded in `display_limits.csv`.
No spatial smoothing or numerical replacement was applied. Related panels
share a scale, while a separately labeled coherent-detail figure uses its own
stress and production scales. Total and random profiles use solid/dashed lines
so overlapping curves remain distinguishable. Phase panels cover 0-360 degrees
with the periodic endpoint displayed consistently.

## Scope Limits

Full real-cache delivery in this iteration is raw only. Postproc selection,
consistent rescaling, separate output paths and reuse were verified with
synthetic caches; full postproc figures were not generated. The same runner
supports them as described in [SECTION5.md](SECTION5.md).

Closure checks verify internal numerical consistency, not PIV uncertainty or
physical model completeness. Production is only `-<uv>*dU/dy`; no unmeasured
terms are inferred. Earlier Section 2/3 statistics have not been overwritten or
redefined, and may differ from the corrected Section 5 support and decomposition.
