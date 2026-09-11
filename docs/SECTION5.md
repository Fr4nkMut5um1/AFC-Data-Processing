# Section 5: Per-Case Transport Deliverables

Section 5 defaults to `raw`; `postproc` switches the instantaneous velocities,
paired validity mask, repeat means, RMS, phase moments and quadrant thresholds
together. Each case computes and exports independently. No cross-case products
are generated, and Sections 1-4 outputs are not used as numerical inputs.

## Run One Case

Open that case's main script in the MATLAB editor. In Section 0 set:

```matlab
cfg.transport.source = 'raw';          % or 'postproc', switching all S5 inputs
cfg.stages.transport = 'compute';      % or 'reuse' for a matching saved S5 result
```

Edit these existing assignments in Section 0, Run Section 0, then Run Section 5.
The entry receives this cfg directly. It validates the selected local cache once,
including fs, actual frames, all repeat identities/boundaries, source and coordinates.
It does not require the other source, original DAT or Sections 2/3/4 when the selected
cache is available and matches cfg. Both delivered scripts still default transport
to skip; whole-script Run can start the independently enabled formal Section 4.

`all` selects the entire cache; `first_half` and `second_half` use the cache repeat
boundaries. An optional `[first last]` frame_range overrides frame_mode. These are
S5-only choices. Parameters, edge/profile support, H and fraction_floor are documented
in each case's PARAMETER_GUIDE.md and PARAMETER_MAP.csv. They do not change S2/3.

`reuse` rejects incompatible source, calculation or implementation identity and
regenerates this case's figures/tables. `compute` writes the selected source's S5
result; retain a separate result copy before intentional parameter experiments.
Neither mode automatically launches upstream sections.

Saved-configuration runners are explicit maintenance tools, described in
[tools/README.md](../tools/README.md); they are not the daily source of cfg.

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

Current cloud status: MATLAB execution has not been performed. In a selected case
directory, use `run('maintenance/checks/test_r2_section5_transport.m')` for the
targeted synthetic core/wrapper tests. See [validation instructions](../tests/README.md).
The original review smoke calls transport_analysis directly and does not cover
section5_run reuse, atomic publication or figure export. Normal wrapper tests also
do not certify interruption recovery or the full formal figure set.

[SECTION5_REVIEW_20260906.md](SECTION5_REVIEW_20260906.md) records historical
real-cache evidence from the earlier environment. It is not a current-run report.
Formal raw B6/C15 PNG plus FIG/CSV, and the separate formal postproc figures,
remain pending for this version. The supplied ZIP lacks the formal S5 MAT/FIG.
