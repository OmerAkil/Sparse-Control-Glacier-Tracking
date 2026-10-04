# Input templates

These files demonstrate the input table schemas used by Sparse-Control Glacier Tracking.

The coordinates shown here are synthetic examples only. They are not a runnable dataset.

## trusted_correspondences.csv

Contains the initial trusted correspondences between the two epochs.

Required columns:

- `Point` — unique point identifier
- `Epoch1_X` — projected X coordinate in the first image
- `Epoch1_Y` — projected Y coordinate in the first image
- `Epoch2_X` — corresponding projected X coordinate in the second image
- `Epoch2_Y` — corresponding projected Y coordinate in the second image

At least three trusted correspondences are required.

## source_points.csv

Contains points that are known only in Epoch 1 and will be propagated through the progressive matching workflow.

Required columns:

- `Point`
- `Epoch1_X`
- `Epoch1_Y`

Point identifiers must be unique and must not overlap with the trusted-correspondence identifiers.

## case_metadata.csv

Contains the temporal separation between the two image epochs.

Required columns:

- `dtDays`
- `dtYears`

The file must contain exactly one row.

## Coordinate requirements

Coordinates must use the same projected metric coordinate reference system as the two input rasters.

Both rasters must:

- contain readable georeferencing,
- use the same projected CRS,
- use metric map units,
- and spatially overlap.

## Creating a real case

Normally, users should create a project through the V1 GUI. The software creates the case directory and configuration structure automatically. These files are provided primarily as schema references.
