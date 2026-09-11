# Section 5: Per-Case Transport Deliverables

Section 5 defaults to `raw`; `postproc` switches the instantaneous velocities,
paired validity mask, repeat means, RMS, phase moments and quadrant thresholds
together. Each case computes and exports independently. No cross-case products
are generated, and Sections 1-4 outputs are not used as numerical inputs.

## Run One Case

From the repository root in MATLAB:

```matlab
addpath('tools');
run_section5('tandem_baseline_r2', 'raw', 'compute');
% Run the controlled case independently:
run_section5('tandem_f40a3_phi0_r2', 'raw', 'compute');
```

Change the second argument to `postproc` to select that cache. `reuse` loads a
matching Section 5 MAT and regenerates figures/tables; it rejects changes to the
source cache identity, calculation parameters or numerical implementation.
The runner reads that case's saved `output/mat/00_case_configuration.mat`.
It does not execute the case script. To change the frame selection or profile
averaging interval independently of the saved configuration:

```matlab
options = struct('frame_mode', 'first_half', 'profile_x_range_mm', [80 320]);
run_section5('tandem_baseline_r2', 'raw', 'compute', options);
```

`all` selects the entire cache; `first_half` and `second_half` select the first
and second repeat using cache boundaries. An optional `[first last]`
`frame_range` overrides `frame_mode`. A new compute replaces only the selected
source's Section 5 result. Keep a separate copy before intentional parameter
experiments if the preceding result is needed.

In the main case script, set `cfg.transport.source` and
`cfg.stages.transport = 'compute'` (or `reuse`). Section 5's dependency check no
longer requires Sections 2/3. Existing stage switches for other sections remain
under user control; the dedicated runner avoids their computation and previews.

## Definitions

- All moments are population moments of paired finite U/V samples with
  `sampleValid=true`, within the requested frames.
- Each repeat has its own temporal mean. Controlled data additionally require
  `cfg.phase.minimum_samples_per_bin` within each repeat, phase bin and grid
  point. Rejected bins are excluded from total, coherent and random statistics
  together. Temporal means are recomputed on this admitted support.
- Phase assignment retains the existing concatenated frame-clock convention.
  The current repeats each contain 6000 frames, an integer number of 24-frame
  forcing periods. No phase alignment is inferred from measured velocities.
- Coherent stress is the sample-weighted average of repeat-specific coherent
  products. It is not the product of phase velocities pooled across repeats.
- Reynolds shear stress is `-<uv>`. All production components multiply the same
  time-mean `dU/dy` (coordinates converted from mm to m). Only the main shear
  production term is reported, not a complete planar or 3D TKE production.
- FD is primary; polynomially augmented local Gaussian RBF-FD is a gradient
  sensitivity calculation. The configured mask/edge buffer applies to reported
  maps and profiles; unmasked production arrays remain in MAT for audit.
- Both total and random branches retain Q1-Q4. Hole events satisfy the strict
  condition `abs(uv) > H*u_rms*v_rms`; random thresholds use phase RMS.
- Probabilities and contributions have the number of observed samples as their
  denominator, including non-events. Conditional intensity is NaN when no event
  occurs. Missing observations are NaN, not a reported zero.
- Signed quadrant fractions divide by signed total stress and sum to one at
  H=0 where defined. Near-zero stress denominators are masked; dimensional
  contributions remain available. Profile CSV values are equal-weight spatial
  averages, with finite spatial column counts explicitly recorded.

## Outputs

Each case writes to `output/section5/raw/` or `output/section5/postproc/`:

- `mat/04_transport_quadrant.mat`: computed moments, counts, masks, quadrant
  events, unmasked products, diagnostics and provenance.
- `png/`, `fig/` (or configured formats): independent case figures. Baseline has
  six figures; controlled adds nine phase/coherent/random figures, including a
  clearly labeled coherent-detail view with its own scales.
- `csv/transport_profiles.csv`, `quadrant_profiles.csv`: values behind the
  profile plots, including all configured H values.
- `csv/phase_profiles.csv`: controlled phase stresses, production and Q2/Q4.
- `csv/display_limits.csv`: actual color limits, valid and clipped counts.
- Colors default to the 99.5th percentile of absolute finite values, shared
  across comparable panels. This changes display only. The CSV records full
  extrema and clipping counts. Set `cfg.figures.section5.display_quantile=1`
  for full-range color limits. No spatial smoothing is applied.
- `json/section5_review.json`: scope, numerical closure metrics, source/cache
  identity, parameters, code digest and delivered file list.

Original `output/mat/04_transport_quadrant.mat` is a legacy result from the
earlier mixed-source implementation and is not reused by this workflow.

On the current nearly uniform y grid, the three-node augmented RBF-FD and
centered FD derivatives can coincide to floating-point accuracy. Their small
difference is not independent evidence of measurement accuracy; the diagnostic
color floor prevents roundoff from being presented as a resolved flow pattern.

## Validation

```matlab
run('tests/test_r2_section5_transport.m');
```

This uses analytic synthetic sequences to check validity, opposite repeat phase
responses, missing/rejected bins, stress/production and H=0 closure, signed
fractions, strict hole equality, frame selection, source switching and gradient
units. Real-cache numerical and visual evidence is recorded in
[SECTION5_REVIEW_20260906.md](SECTION5_REVIEW_20260906.md).
