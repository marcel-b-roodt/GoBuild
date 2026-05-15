# Changelog

All notable changes to GoBuild are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.6.0] — 2026-05-15

### Added
- Infinite scroll for param-preview operations (Extrude, Inset, Bevel, Loop Cut,
  Edge Extrude) — MOUSE_MODE_CAPTURED provides infinite relative deltas; events
  are captured globally via EditorPlugin._input() to bypass the editor viewport
  routing bug that broke context-menu param previews.
- Infinite scroll for gizmo drags (Translate, Rotate, Scale, Plane, Viewport-plane)
  — all gizmo drags now use MOUSE_MODE_CAPTURED with per-frame pixel delta
  accumulation, matching the precision and responsiveness of param previews.
- Unified drag pipeline — GoBuildDragController + GoBuildDragOperation replace the
  legacy GoBuildDragHandler for all interactive drags. Single code path for delta
  accumulation, precision mode, snap, commit, and cancel.
- Raw accumulator snap fix — replaced the old `snappedf()` approach that overwrote
  the per-frame accumulator with separate raw accumulators that always grow and
  derive snapped display/mutation values, so small deltas can cross grid boundaries
  over multiple frames.
- Per-frame pixel delta strategies for gizmo drags — axis project, plane project,
  viewport plane project, rotate, scale axis, scale uniform, and inset all use
  accumulated screen-space deltas instead of ray-cast/project approaches.
- 10x rotation sensitivity — rotate handles now produce usable angles per pixel
  of mouse travel, matching the feel of Blender's rotation gizmo.
- Precision-scaled overlay indicator with anchor dot, directional colour line,
  and live parameter text. Precision mode (Shift) scales sensitivity to 10%
  and seamlessly toggles mid-drag via anchor re-capture.
- Clamp folding — when a drag parameter hits min/max bounds, excess delta is
  folded back so reversing direction responds instantly with no dead zone.
- Directional extrude — new shapes created by Extrude Face or Extrude Edge
  orient their outward normal toward the camera, matching modeller expectation.
- Negative extrude support — drag left/down from the anchor to extrude inward.
- Inset and bevel preview — Shift+drag on scale handles starts an inset preview;
  the inset amount responds to mouse movement in real time.
- Fill/Bridge operation — fills a closed boundary loop with a new face, or bridges
  two open boundary chains. Single "Bridge/Fill" button auto-detects topology.
- Auto-select after Extrude Edge — newly created edges are automatically selected
  when the extrude commits, ready for further modelling.
- Post-commit selection callbacks on DragOperation and ParamPreview, with reusable
  `_make_select_edges_fn`, `_make_select_faces_fn`, `_make_select_vertices_fn`
  helpers in GoBuildDrawer.
- Auto UV parameter controls — Scale, U/V Offset, and Seam Rotation are now
  editable spinboxes in the General drawer when Auto UV is active.
  Seam Rotation only appears for Cylinder and Sphere modes. Adjustments are
  live-previewed and committed as a single undo step (add_do_property/add_undo_property)
  when the user releases the spin-drag or presses Enter. Undo/redo correctly
  restores the auto_uv_scale, auto_uv_offset, and auto_uv_seam_rotation properties
  and syncs the sidebar spinboxes.
- GoBuildUndoSpinBox — new SpinBox subclass that emits spin_committed on
  mouse-up after a drag and on Enter in the LineEdit, enabling proper undo
  commit timing for parameter editing.
- UV projection buttons (Planar, Box, Cylinder, Sphere) now show the projection
  result immediately on click — no need to nudge a spinbox first.
- UV rotation display in the UV editor now folds cumulative angles into ±360°
  so the readout wraps instead of growing without bound.
- UV view now centres on the 0-1 tile by default instead of showing the origin
  in the top-left corner.
- UV panel toolbar now scrolls horizontally when the dock is narrow, while the
  canvas continues to fill available space.
- GoBuild panel (side dock) no longer enforces a minimum width — the dock is
  freely resizable, with a horizontal scrollbar appearing when content overflows.
- Show Backfaces toggle now works on all material types — ShaderMaterial and
  other non-BaseMaterial3D surfaces get a semi-transparent blue double-sided
  override instead of being silently skipped.
- Materials drawer overhauled: quickset buttons removed, replaced by
  auto-discovered palettes with in-panel CRUD, per-slot [Use] and [x],
  and Object-mode [Use] that assigns to all faces. Palette migration from
  deprecated array to disk on first load.

### Changed
- Retired GoBuildDragHandler — deleted entirely. GizmoPlugin, SIC, and plugin.gd
  no longer delegate to it. All drag state and lifecycle is owned by
  GoBuildDragController.
- Removed legacy param-preview fallback paths — SIC's _commit_param_preview and
  cancel_param_preview are replaced by direct DragController commit/cancel calls.
  Dead deferred-apply methods (_schedule_preview_apply, _flush_preview_apply)
  and variables removed.
- All diagnostic prints now route through GoBuildDebug.log() — 4 bare print()
  calls in GoBuildGizmoPlugin converted. No ungated debug output remains.
- _apply_auto_uv now reads auto_uv_scale, auto_uv_offset, and
  auto_uv_seam_rotation from the instance instead of hardcoded 1.0/0/0.
- Refactored GoBuildGizmoPlugin to persist Godot's native transform mode
  (Move/Rotate/Scale) across Object/Edit mode switches instead of saving and
  restoring it independently.
- Extracted GoBuildDrawer._make_select_*_fn static helpers from inline lambdas
  in GoBuildFaceDrawer and GoBuildEdgeDrawer. All post-commit selection callbacks
  now flow through these reusable factories.
- Right-click context menu now consumes the mouse event so Godot's editor does
  not also start a camera orbit. Object mode right-click still passes through
  for native editor behaviour.

### Fixed
- Context menu no longer causes cursor jump or viewport pan when opened in
  edit mode — deferred popup display lets Godot's camera finish its orbit-release
  cursor restoration before the menu appears.
- Gizmo handle picking uses the selection centroid for scale instead of the
  node origin, eliminating the desync between drawn and clickable handles when
  selection is far from origin.
- Precision inset range — inset drags with Shift held can now reach the full
  0–1 range instead of being limited by the old snap-overwrite bug.
- Dock panel no longer forces a minimum width — users can freely resize the
  GoBuild and UV docks, with horizontal scrollbars appearing when content
  overflows.

---

## [0.5.0] — 2026-04-30

### Added
- Auto UV — Cylindrical projection (`CylindricalProjection`): wraps U around
  the Y axis (0-1 using atan2), V scales with height / units_per_tile.
  Seam correction prevents cross-seam smear on faces that straddle the atan2
  discontinuity.  World-space transform support (same pattern as Box UV).
  Panel button "Cyl UV" in Face section; full undo/redo; 11 unit tests.
- Auto UV — Spherical projection (`SphericalProjection`): equirectangular
  lat/lon mapping with seam correction and world-space transform support;
  panel button "Sphere UV"; 10 unit tests.
- Selection dimensions overlay in the 3D viewport: live edge length, face
  width/height, mixed-selection bounding extents, and vertex world-position/
  delta readouts.

### Changed
- Shape creation flow: expanded panel-native pre-commit parameter preview to
  Cylinder, Cone, Sphere, Staircase, Torus, and Arch. These shapes open a live
  preview with configurable parameters (including sides/segments/steps/rings)
  and explicit Accept/Cancel actions before final insertion.
- Refactor: moved shape preview defaults, parameter schemas, sanitisation, and
  mesh-build dispatch into `ShapeCreationCatalog` so generator-specific creation
  logic is no longer embedded in `GoBuildPanel`.
- Panel UX refresh: collapsible operation sections fixed and normalized,
  GoBuild/UV panel flow tightened, material slots show swatches or thumbnails,
  and new shapes seed slot 0 with the default metre-grid material.
- Edit flow consistency: switching between GoBuild meshes now preserves active
  edit mode instead of dropping back to Object mode.

### Fixed
- Dock title regression: GoBuild panel tab now keeps the name `GoBuild` when
  wrapped in a `ScrollContainer` (instead of showing generated names like
  `@ScrollContainer@...`).
- Selection correctness: face picking now respects front-mesh occlusion, which
  prevents selecting faces through geometry behind the clicked mesh.
- Gizmo cleanup: stale selection overlays no longer remain on a previously
  edited mesh when switching to a different target.
- Material-slot tooltip formatting crash fixed (GDScript `%` precedence bug).
- Panel tests: restored compatibility shims for legacy panel helper methods and
  moved settings selection flow to a headless-safe button path.

---

## [0.5.0-dev2] — 2026-04-26

### Changed
- Further modify the dev release pipeline Update readme

## [0.5.0-dev1] — 2026-04-25

---

## [0.4.1] — 2026-04-23

### Fixed
- Scene reload crash — `GoBuildMesh`, `GoBuildFace`, and `GoBuildEdge` were
  missing `@tool` annotations, causing Godot to return placeholder `Resource`
  instances in editor context and crash with "Attempt to call a method on a
  placeholder instance" on every reload
- Mesh data not persisted — `GoBuildFace` extended `RefCounted` (not
  serialisable by Godot) and none of the data fields had `@export`; after a
  save/reload cycle all vertex positions, faces, and UVs were silently lost;
  fixed by changing `GoBuildFace` to extend `Resource` and exporting
  `vertices`, `faces`, and `material_slots` on `GoBuildMesh`
- Derived caches stale after reload — `GoBuildMeshInstance._ready()` now calls
  `rebuild_edges()` before `bake()` so the edge list and coincident-vertex
  groups are always warm on the first frame after a scene reload

### Tests
- 20 new persistence round-trip tests (`go_build_mesh_persistence_test.gd`)
  covering vertex positions, face topology, UV0/UV1, edge rebuild, coincident
  groups, bake integrity, and a regression guard that catches the
  `@tool`/`@export`-missing failure mode directly

---

## [0.4.0] — 2026-04-21

### Added

**UV Editing & Materials (Stage 4, started)**
- Auto UV planar projection — `PlanarProjection.apply(mesh, face_indices, units_per_tile)` projects each selected face onto the plane implied by its dominant normal axis; defaults to 1 unit per texture repeat so checker or metre textures tile according to mesh size; exposed via the Face section of GoBuildPanel and the face right-click context menu; now supports default auto-application after mesh edits (including drag-based editing), live UV updates during deferred preview, and an `Auto UV` panel toggle; 5 unit tests covering dominant-axis projection, tiling span, selection scoping, and no-op guards

---

## [0.2.0] — 2026-04-15

### Added

**Mesh Operations (Stage 3, continued)**
- Delete geometry — `DeleteOperation` with three entry points: `apply_faces`, `apply_edges`, `apply_vertices`; orphaned-vertex compaction with full index remapping after deletion; coincident-group expansion in vertex mode so all split copies of a shared corner are removed together; panel button (enabled in any sub-element mode with a non-empty selection); `Delete` and `X` keyboard shortcuts (pass-through in Object mode so Godot can still delete nodes); right-click context menu items in all three sub-element modes; full undo/redo via `apply_operation`; 24 unit tests
- Merge vertices — `MergeOperation`: collapses all selected vertices (and their coincident partners) to their collective centroid; panel button in Vertex section; right-click context menu; full undo/redo
- Weld vertices — `WeldOperation`: snaps all vertices within a configurable distance threshold together; `apply_weld_by_threshold` performs a full coincident-group compaction pass; panel button; useful for closing seams on imported or subdivided geometry; full undo/redo
- Edge extrude — `EdgeExtrudeOperation`: extrudes any selected edge (boundary or interior) at distance 0, adding a new quad face [va, vb, nb, na] with CCW winding matching the side-face convention of `ExtrudeOperation`; Shift+drag on an axis handle in Edge mode immediately transitions to a translate drag restricted to the two new vertices; works on closed meshes (e.g. a cube) where all edges are interior; 16 unit tests

**Editor UX**
- Show back-faces toggle — opt-in checkbox in the panel (alongside Debug logging) that disables back-face culling on the active mesh while editing; useful for diagnosing flipped normals and inside-out geometry; implemented as surface override materials (`BaseMaterial3D.CULL_DISABLED`) so the exported mesh is never affected; clears automatically when the mesh is deselected or the plugin is disabled
- Panel operation categories — Vertex / Edge / Face / General labelled sections in the operations panel for easier navigation; each section is only populated with buttons relevant to the active sub-element mode
- `mesh_changed` signal on `GoBuildMeshInstance` — emitted after every bake so the panel (and any external listeners) receive up-to-date vertex/edge/face counts without polling

### Fixed
- Weld primitives on generation — `WeldOperation.apply_weld_by_threshold` now calls `rebuild_edges()` even when no vertices are remapped, fixing the 0-edge state that occurred on freshly generated planes
- Vertex snap on viewport-plane handle — snapping with V while dragging the viewport-plane handle now lands at the correct 3D world position (was slightly offset due to a stale centroid)

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

