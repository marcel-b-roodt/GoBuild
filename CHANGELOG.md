# Changelog

All notable changes to GoBuild are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

---

## [0.1.0] — 2026-04-06

First public release. Covers the full foundation, all primitive shape generators, complete sub-element selection and transform, and the first set of mesh operations.

### Added

**Foundation (Stage 0)**
- `EditorPlugin` scaffold with toolbar registration and GoBuildPanel dock
- `GoBuildMesh` internal data model: vertex, edge, and face lists; normals, UVs, material slots; `translate_vertices`, `compute_centroid`, `take_snapshot`/`restore_snapshot`; coincident-vertex groups for correct shared-corner drag behaviour
- `ArrayMesh` bake pipeline: fan triangulation, flat and smooth-group normals, UV0 and UV1
- `GoBuildMeshInstance` — auto-bakes on resource assign
- Undo/redo via `EditorUndoRedoManager`: `apply_operation()` + `restore_and_bake()` pattern
- GdUnit4 test suite covering bake, normals, edges, snapshot/restore, translate, centroid, gizmo helpers, and panel UX
- GitHub Actions CI pipeline (`ci.yml`) — GdUnit4 headless on push/PR
- GitHub Actions release pipeline (`release.yml`) — plugin zip on `v*` tag

**Primitive Shapes (Stage 1)**
- Cube — width, height, depth, subdivisions
- Plane — width, depth, independent XZ subdivisions
- Cylinder — radius, height, sides, optional end caps
- Sphere (UV) — radius, latitude rings, longitude segments
- Cone — radius, height, sides, optional base cap
- Torus — major/minor radius, ring and tube segments
- Staircase — steps, rise/run/width; closed solid
- Arch — outer radius, thickness, angle, segments, depth
- Shape insert toolbar — one-click creation in GoBuildPanel with full undo/redo

**Selection and Transform (Stage 2)**
- `SelectionManager`: mode and element selection state; 28 unit tests
- Edit-mode toolbar (Object / Vertex / Edge / Face) with radio buttons; synced via `mode_changed` signal
- Keyboard shortcuts: 1/2/3/4 for mode switch; W/E/R for Translate/Rotate/Scale
- Viewport gizmos (`GoBuildGizmoPlugin` + `GoBuildGizmo`) — vertex, edge, and face overlays with selected/unselected colour coding
- Click-picking via `PickingHelper`: screen-space vertex/edge picking and Moller-Trumbore face picking; Shift=add, Ctrl=toggle; 11 unit tests
- Box multi-select: left-drag rubber-band rect; Shift=additive, Ctrl=toggle
- Axis translate handles with coincident-vertex expansion
- Planar translate handles (XY/YZ/XZ planes)
- Viewport-plane translate handle
- Rotate handles (ring gizmo per axis)
- Scale handles (axis shafts + solid cube tips)
- Grid snap (Ctrl) using `editors/3d/grid_step` from EditorSettings
- Vertex snap (V) — snaps selection centroid to nearest non-dragged mesh vertex in screen space

**Mesh Operations (Stage 3, initial)**
- Extrude face(s) — `ExtrudeOperation`: per-face-normal extrude, side quads, CCW winding; panel button; 17 unit tests
- Inset face(s) — `InsetOperation`: shrinks selected faces inward with new boundary geometry; full undo/redo
- Flip normals — `FlipNormalsOperation`: reverses winding and UV arrays; panel button, right-click context menu; 15 unit tests
- Shift+drag extrude in Face mode — extrudes at distance 0 then translates; single-step undo
- Right-click context menu — per-mode items (Select All, Extrude, Flip Normals)

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

