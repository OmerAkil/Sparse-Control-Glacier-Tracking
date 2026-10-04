# Sparse-Control Glacier Tracking

**Version:** `1.2.0-beta`

A MATLAB workflow for deriving a **sparse horizontal glacier-displacement field** from repeat georeferenced imagery using progressive, human-validated feature tracking.

The method is intended for difficult glacier imagery in which fully automatic matching can be unreliable because of repetitive crevasse texture, snow/illumination changes, widening or deformation of crevasses, and local ambiguity.

It is **not a fully automatic image-velocimetry algorithm**. The software generates and refines candidate matches, but only correspondences explicitly accepted by the human reviewer are allowed to enter the trusted control set.

---

## Method overview

The workflow begins with:

- two overlapping georeferenced raster images from different epochs;
- a small set of trusted correspondences known in both epochs; and
- additional source points defined only in the earlier image.

For each unresolved source point, the software:

1. evaluates how well the current trusted network supports that point;
2. selects the best-supported unresolved point;
3. predicts its displacement from the current trusted controls;
4. performs a broad structural search in the later image;
5. refines the strongest candidate regions locally;
6. presents the retained hypotheses to the user for graphical review;
7. records the point as **ACCEPT**, **NO MATCH**, or **DEFER**; and
8. if accepted, immediately adds the correspondence to the trusted network before selecting the next point.

This produces a progressively growing sparse control field rather than matching every source point independently from a fixed initial prior.

```text
Initial trusted correspondences
            |
            v
Rank unresolved source points by spatial support
            |
            v
Select one best-supported source point
            |
            v
IDW displacement prior
            |
            v
Stage 1: broad structural candidate search
            |
            v
Stage 2: parent-preserving local refinement
            |
            v
Human graphical review
       /        |        \
   ACCEPT    NO MATCH    DEFER
      |           |         |
      v           |         |
Add to trusted    |     revisit later
control network   |         |
      \___________|_________/
                  |
                  v
         next unresolved point
```

Only **human-accepted** correspondences are promoted into the working trusted set.

---

## Matching architecture

### Progressive support ranking

Before each new match, the remaining source points are ranked using the geometry of the current trusted-control network.

The support diagnostics include:

- distance to the three nearest trusted controls;
- effective IDW support;
- dominant IDW weight;
- angular geometry of the three nearest trusted controls; and
- whether the source lies inside or outside the current trusted-control convex hull.

The ranking is lightweight: expensive image matching is run only for the single source point selected next.

### Stage 1 — broad structural search

Stage 1 predicts the source-point displacement using the current trusted controls and searches a broad neighborhood around the expected Epoch-2 position.

The default release configuration uses:

- IDW displacement prior, power = `3`;
- structural working GSD = `0.20 m`;
- context scales = `8, 12, 16 m`;
- candidate spacing = `0.40 m`;
- requested search radius = approximately `±15 m`;
- Gradient NCC;
- Oriented Partial Chamfer;
- multiple retained hypotheses per matching stream; and
- consensus clustering across matching streams.

This stage is intended to identify plausible structural neighborhoods rather than force a single automatic correspondence.

### Stage 2 — parent-preserving refinement

The strongest Stage-1 candidate regions are retained as independent parents and refined locally.

Default configuration:

- three visual Stage-1 beams;
- local refinement radius = `1.80 m`;
- refinement spacing = `0.20 m`;
- working GSD = `0.10 m`;
- local context = `4.80 m`; and
- Gradient NCC + Oriented Partial Chamfer refinement.

The parent structure is preserved so that a strong but incorrect Stage-1 basin does not automatically eliminate alternative hypotheses.

### Human review

For each source point, the GUI presents the earlier-image source region together with the retained candidate regions in the later image.

The reviewer can:

- inspect one of the retained beams or the IDW fallback region;
- click the visually corresponding Epoch-2 location;
- accept the manual click;
- snap to the nearest retained refined child;
- redo the click;
- switch candidate region;
- declare **NO MATCH**; or
- **DEFER** the point.

Deferred points are revisited after the never-reviewed points have been exhausted and the trusted network has had an opportunity to grow. During the deferred revisit, the point must be resolved as **ACCEPT** or **NO MATCH**.

---

## Scientific analysis

After progressive matching is complete, the accepted correspondences are finalized into one authoritative sparse displacement field.

The GUI then runs four downstream scientific stages.

### Stage 5 — field QC and velocity

Computes:

- East/North displacement;
- annualized East/North velocity;
- speed and direction;
- nearest-neighbor geometry;
- local IDW residual diagnostics;
- close source-point pairs; and
- Delaunay spatial-coverage diagnostics.

Local IDW residuals are **quality-control diagnostics only** and are not automatic rejection criteria.

Principal outputs include:

```text
output/05_field_qc/
    master_correspondence_velocity_qc.csv
    close_source_pairs.csv
    delaunay_edges_sorted_longest_first.csv
    field_qc.mat
    01_displacement_vectors.png
    02_speed_map.png
    03_local_IDW_residual_map.png
    04_spatial_coverage_delaunay.png
    05_speed_vs_easting.png
```

### Stage 6 — flow-aligned affine velocity model

Defines:

- `x_along`: positive in the circular-mean glacier-flow direction;
- `y_cross`: positive 90° clockwise/right of the mean-flow direction.

Fits:

```text
v_along = beta0 + beta_x * x_along + beta_y * y_cross
```

and a secondary plane for `v_cross`.

Important interpretation:

`d(v_along)/d(y_cross)` is the **cross-glacier gradient of forward speed**. It is not the same quantity as cross-flow velocity.

Principal outputs include:

```text
output/06_flow_aligned_plane/
    flow_aligned_plane_results.csv
    flow_aligned_plane.mat
    01_flow_aligned_axes.png
    02_v_along_plane_3D.png
    03_v_along_plane_residual_map.png
    04_observed_vs_fitted_v_along.png
    05_partial_along_flow_gradient.png
    06_partial_cross_flow_gradient.png
```

### Stage 7 — horizontal strain-rate analysis

Derives a first-order two-dimensional horizontal velocity-gradient and strain-rate description from the fitted affine field.

Outputs include:

- longitudinal and transverse strain rates;
- shear strain rate;
- horizontal divergence;
- principal extension and compression rates;
- principal strain-axis orientations; and
- rigid-body rotation in the ordinary East/North map frame.

Bootstrap resampling is used to assess the stability of the fitted quantities.

Principal outputs include:

```text
output/07_strain_rate/
    strain_rate_summary.csv
    bootstrap_95CI.csv
    strain_rate_analysis.mat
    01_principal_strain_axes_map.png
    02_one_year_strain_ellipse.png
    03_strain_rate_components.png
    04_bootstrap_95CI.png
```

**Scientific scope:** this is a **global first-order affine deformation estimate over the spatial footprint of the trusted controls**. It should not be interpreted as a dense local strain field at every crevasse.

Horizontal divergence also does not, by itself, provide a complete three-dimensional or thickness-change interpretation.

### Stage 8 — robustness and sensitivity

Tests whether the fitted velocity/strain conclusions depend strongly on:

1. any single trusted correspondence, using leave-one-out refitting; or
2. bounded coordinate-localization uncertainty, using Monte Carlo perturbation.

Mean-flow direction and flow-aligned axes are recomputed during leave-one-out testing.

Monte Carlo ranges are **sensitivity intervals under the specified perturbation model**, not formal measurement-confidence intervals.

Principal outputs include:

```text
output/08_robustness/
    leave_one_out_metrics.csv
    robustness_summary.csv
    robustness_sensitivity.mat
    01_leave_one_out_gradient_influence.png
    02_MC_gradient_sensitivity.png
    03_MC_principal_strain_sensitivity.png
    04_coordinate_uncertainty_intervals.png
```

---

## Requirements

### MATLAB

The release dependency scan identifies:

- MATLAB
- Mapping Toolbox
- Image Processing Toolbox

The current implementation was developed and tested with **MATLAB R2024a**.

No Statistics and Machine Learning Toolbox is required by the Stage 5–8 scientific-analysis backend.

### Input imagery

The two epoch rasters must:

- be readable by MATLAB geospatial raster functions;
- contain georeferencing;
- use the same projected coordinate reference system;
- use metric map units; and
- spatially overlap.

The current GUI automatically recognizes WGS 84 UTM projected CRS definitions. Other projected metric CRS configurations may require explicit support.

---

## Installation

Clone or download the repository and keep its internal directory structure unchanged.

```text
Sparse-Control-Glacier-Tracking/
├── V1.m
├── VERSION
├── README.md
├── cases/
├── examples/
└── src/
```

In MATLAB:

```matlab
cd('path/to/Sparse-Control-Glacier-Tracking')
V1
```

`V1.m` adds the required source directories to the MATLAB path.

---

## Creating a project

From the GUI:

1. Select **New Project**.
2. Enter a project name.
3. Select the earlier and later georeferenced raster images.
4. Enter the two acquisition dates.
5. Create the project.
6. Import the trusted-correspondence CSV.
7. Import the source-point CSV.
8. Revalidate the project.
9. Start progressive matching.

Each case is stored locally under:

```text
cases/<caseName>/
```

Runtime cases are excluded from Git by default.

---

## Input tables

Example templates are provided in:

```text
examples/input_templates/
```

### `trusted_correspondences.csv`

Required columns:

```text
Point,Epoch1_X,Epoch1_Y,Epoch2_X,Epoch2_Y
```

These are the initial trusted correspondences used to construct the displacement prior.

At least **three** trusted correspondences are required.

### `source_points.csv`

Required columns:

```text
Point,Epoch1_X,Epoch1_Y
```

These points are defined only in the earlier image and will be processed by the progressive matching workflow.

### Point identifiers

Point identifiers must be:

- unique within each table;
- non-overlapping between trusted and source tables; and
- positive integer IDs, optionally written with a `P` prefix such as `P01`.

### `case_metadata.csv`

Required columns:

```text
dtDays,dtYears
```

The table must contain exactly one row and both values must be positive.

The GUI normally creates and maintains the case metadata automatically from the supplied acquisition dates.

---

## GUI workflow

The normal user workflow is:

```text
New/Open Project
      |
      v
Import / validate inputs
      |
      v
Start or Resume Progressive Matching
      |
      v
Finalize Progressive Correspondences
      |
      v
Run Scientific Analysis
      |
      v
View Results
```

Progressive sessions are persistent and resumable. Review decisions and iteration provenance are written after each processed source point.

The principal progressive state is stored under:

```text
output/01_progressive_matching/
```

Final authoritative correspondences are written to:

```text
output/04_finalized_correspondences/
```

including:

```text
final_correspondences.csv
progressive_provenance.csv
progressive_finalization_summary.csv
progressive_finalization_manifest.mat
```

---

## Reproducibility

The project utilities can write a reproducibility manifest containing:

- release version;
- UTC creation time;
- MATLAB version/release;
- toolbox versions;
- platform information;
- case and epoch metadata;
- raster dimensions, bounds, GSD and CRS;
- SHA-256 checksums of configuration, input tables and rasters;
- configured random seeds; and
- Git commit information when available.

Large runtime data and generated products are intentionally excluded from version control.

---

## Release validation

### Software regression

The cleaned `v1.2.0-beta` repository was tested against a previously completed progressive glacier-tracking case.

Starting only from the saved progressive matching state, the cleaned release independently regenerated:

- progressive finalization;
- Stage 5 field QC;
- Stage 6 flow-aligned modelling;
- Stage 7 strain-rate analysis; and
- Stage 8 robustness analysis.

All **11 principal CSV products** compared in the regression test were identical to the validated development outputs by SHA-256 hash comparison.

The release was also tested for:

- MATLAB dependency resolution;
- GUI startup;
- clean new-project schema generation; and
- removal of retired fixed-pipeline configuration/stage directories.

### Method validation status

The software-regression result demonstrates that repository cleanup did not change the validated numerical workflow.

It does **not** establish universal scientific performance across all glaciers, sensors, spatial resolutions, deformation regimes or image conditions. Candidate-generation performance and the required density/distribution of trusted controls should be evaluated for each new imagery regime.

---

## Important limitations

- The workflow is **human-validated and semi-automated**, not fully automatic.
- Repetitive crevasse texture can produce multiple high-scoring but incorrect image matches.
- Large physical deformation between epochs can change local feature appearance.
- Snow, illumination and surface-condition changes can reduce correspondence confidence.
- The quality of progressive propagation depends on the spatial coverage and reliability of the trusted-control network.
- A source point may legitimately have **NO MATCH**.
- Stage 5 local-consistency diagnostics should not be used as automatic rejection rules.
- The Stage 6–7 affine model describes the large-scale first-order velocity/deformation field over the control footprint.
- Annualized velocity represents the observed epoch-to-epoch interval scaled to one year; it should not automatically be interpreted as a climatological annual mean.
- Stage 8 Monte Carlo intervals quantify sensitivity to the specified perturbation model and are not formal observational confidence intervals.

---

## Repository structure

```text
Sparse-Control-Glacier-Tracking/
│
├── V1.m                         # Main graphical interface
├── VERSION
├── README.md
├── .gitignore
│
├── cases/                       # Local runtime workspaces; ignored by Git
│   └── .gitkeep
│
├── examples/
│   └── input_templates/
│       ├── README.md
│       ├── trusted_correspondences.csv
│       ├── source_points.csv
│       └── case_metadata.csv
│
└── src/
    ├── matching/
    │   ├── v1_compute_source_support.m
    │   ├── v1_select_next_source.m
    │   ├── v1_stage1_single_point.m
    │   ├── v1_stage2_single_point.m
    │   ├── v1_progressive_initialize.m
    │   ├── v1_progressive_prepare_next.m
    │   ├── v1_progressive_review_current.m
    │   ├── v1_progressive_run_session.m
    │   ├── v1_progressive_finalize.m
    │   └── v1_progressive_ensure_final_schema.m
    │
    ├── analysis/
    │   ├── v1_stage5_field_qc.m
    │   ├── v1_stage6_flow_plane.m
    │   ├── v1_stage7_strain_rate.m
    │   └── v1_stage8_robustness.m
    │
    └── utils/
        ├── v1_check_dependencies.m
        ├── v1_create_case_skeleton.m
        ├── v1_prepare_case.m
        └── v1_write_manifest.m
```

---

## Release status

`v1.2.0-beta` is a research-software release.

The current release is suitable for reproducible use and further scientific evaluation, but its transferability to new glaciers and imagery regimes should be assessed rather than assumed.

---

## Citation

Citation metadata will be provided in `CITATION.cff`.

If this software contributes to a scientific publication, describe the method as a **human-validated, semi-automated sparse feature-tracking workflow** rather than as a fully automatic glacier image-velocimetry algorithm.

---

## License

See `LICENSE`.
