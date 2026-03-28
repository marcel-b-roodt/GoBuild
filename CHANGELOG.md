# Changelog

All notable changes to GoBuild are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- `MeshGeneratorUtils.add_quad_grid` — shared helper for all flat-face generators;
  bilinear vertex interpolation, UV [0,1] per face, configurable steps_u/steps_v
- `CubeGenerator.generate(width, height, depth, subdivisions)` — axis-aligned cuboid,
  6 quad faces with correct outward normals (verified by tests), optional subdivision
- `PlaneGenerator.generate(width, depth, subdivisions_x, subdivisions_z)` — upward-facing
  XZ plane with independent X/Z subdivision counts
- 32 new GdUnit4 tests covering face counts, vertex counts, normals, dimensions,
  UVs, edge derivation, and bake output for both generators

---

<!-- New releases are prepended above this line in the format:

## [X.Y.Z] — YYYY-MM-DD
### Added
- ...
### Fixed
- ...
### Changed
- ...
### Removed
- ...

-->

