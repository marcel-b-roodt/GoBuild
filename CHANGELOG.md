# Changelog

All notable changes to GoBuild are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.8.1] — 2026-06-30

### Fixed
- Shape draw: interactive shapes now grow upward from the base during the HEIGHT
  phase; previously the base was treated as the top of the AABB and height extended
  downward (fix in `_align_y_to_normal` — outward normal convention)
- Drag-and-drop on UV canvas: fixed `_can_drop_data` and `_drop_data` signatures
  to use `Variant` instead of `Dictionary` (Godot 4 API requirement)

---

## [Unreleased]

---

## [0.9.0] — 2026-07-23

### Added
- UV Select Island — double-click a face in the UV canvas to flood-fill select all
  UV-connected faces in its island; Shift+double-click adds the island to the current
  selection, Ctrl+double-click toggles it
- Prepare for Texturing — one-click "Prep Tex" button in the UV panel Operations
  drawer: applies Box UV projection to all faces, then packs islands into the 0-1
  tile; full undo/redo as a single action
- UV wireframe export (PNG) — "Export UV" button in the UV panel Operations drawer;
  renders UV wireframe to PNG at configurable resolution; white lines on transparent
  background by default; uses Bresenham line drawing with configurable width and colours
- Drag-and-drop texture to UV canvas — drop a Texture2D or Material from the
  FileSystem dock onto the UV canvas to assign it to selected faces; reuses existing
  material slots or creates a new StandardMaterial3D; full undo/redo
- Drag-and-drop material to 3D viewport — drag a Material or Texture2D from the
  FileSystem onto a GoBuild mesh to preview per-face assignment; raycast targets the
  face under the cursor; Ctrl hint overlay; Escape cancels; full undo/redo
- Rip operation (V key) — split shared vertices or edges apart, creating an open
  seam; works in Vertex mode and Edge mode; `RipOperation.apply_vertices` and
  `RipOperation.apply_edges`; panel buttons, context menu entries, and V shortcut;
  13 unit tests
- Normal visualiser overlay — face normals (cyan lines from face centroids) and
  vertex normals (lavender lines, area-weighted average of adjacent face normals);
  "Normals" and "Vtx N" checkboxes in General drawer; N key shortcut toggles face normals
- X-ray off mode — backface culling and depth occlusion for vertex, edge, and face
  picking; elements behind the mesh surface are not selectable when X-ray is off;
  box select also respects occlusion; gizmo elements behind the mesh are hidden by
  depth-tested materials
- Occlusion-aware mesh switching — clicking on another GoBuild mesh now only switches
  to it if no closer geometry blocks the click; parametric ray distance comparison
  replaces centroid-based approximation; prevents accidental hops to meshes behind the
  current one even in X-ray mode
- Camera-facing prism edge gizmos — edges are drawn as 3-face prisms (0°/60°/120°
  cross-section) instead of single flat ribbons, giving a consistent spherical
  appearance from every viewing angle; double-sided materials ensure visibility
- Consolidate material slots — "Consolidate Slots" button in Materials drawer merges
  duplicate material slots (same resource or both null) and removes empty slots,
  preventing slot proliferation from repeated face assignments
- Merge faces — "Merge Faces" button in Face drawer dissolves interior edges of
  adjacent selected faces, creating a single N-gon; works on any connected group;
  also available in right-click context menu (requires 2+ selected faces);
  winding-corrected: ring normal is checked against the average face normal and
  reversed if inward, preventing flipped normals
- Multi-mode operations — UV projection and smooth group buttons now work in
  Object mode, applying to all faces; UV projections in Object mode are immediate
  commits (no param preview) since fine-tuning all-face projections is rare

### Changed
- UV and Surface drawers now auto-open in Object mode (alongside Create Shape),
  making Object mode operations discoverable without manual drawer expansion;
  both drawers also default to open on initial panel load
- Edge gizmo thickness reduced (selected ratio 0.6, unselected 0.4, down from 0.8/0.7)
- Context edge colour (vertex/face mode) changed from grey (0.4) to dark grey (0.2)
  for a subtler wireframe look closer to Blender
- Vertex handles always drawn on top (no depth test) in vertex mode regardless of
  X-ray setting, preventing edges from drawing over vertex cubes
- Edge ribbon materials use double-sided rendering (CULL_DISABLED) so prism quads
  are visible from both sides

### Fixed
- Inset drag (Shift + Scale gizmo) was broken since the unified drag pipeline
  refactor — `GoBuildDragOperation.create_for_gizmo_handle` classified inset
  drags as SCALE_AXIS because the handle-ID check came before the inset-centroids
  check; moved inset-centroids check to the top of the elif chain
- Merge faces could produce inward-facing normals when the boundary ring walk
  happened to traverse the ring clockwise; now computes the Newell normal of the
  ring and compares it to the average outward normal of the original faces, reversing
  the ring if they disagree

## [0.8.0] — 2026-06-29

---

### Added
- Interactive shape draw (3-click insertion) — click in the viewport to position a
  shape, drag to set width/depth, then drag to set height; live wireframe ghost and
  dimension labels update in real time; Shift constrains to uniform aspect ratio;
  Ctrl snaps to grid; parent mode selector (Child/Sibling/Root); non-drawable params
  (sides, rings, caps, etc.) shown in a compact panel strip during draw
- ShapeParamMapping — maps AABB dimensions from the drawn box to generator-specific
  parameters for all 8 shapes (Cube, Plane, Cylinder, Sphere, Cone, Torus,
  Staircase, Arch); handles axis swapping for Plane (XZ) vs. other shapes (XYZ)
- A* pathfinding for face_path and edge_path — replaces BFS/Dijkstra with
  Euclidean distance heuristic for direct, geodesic-shortest paths instead of
  hop-count or normal-deviation-weighted routes; geometric distance cost ensures
  paths follow diagonals on curved surfaces instead of hugging coplanar strips
- Boundary edge loop fallback — when Alt+Click on a single boundary edge (1 face)
  produces no topology loop (corners, T-junctions, non-quad meshes), the loop
  automatically falls back to walking connected boundary edges in both directions;
  works on staircases, house shapes, and any mesh with boundary edges at 90° corners
- Edge loop cycling — repeated Alt+Click on the same edge cycles through loop types:
  topology loop → boundary loop (if available) → ring; lets users select edges
  around 90° corners and shapes where the default loop result isn't what they want
- Boundary loop face-sharing preference — at junction vertices where multiple boundary
  edges meet, the loop prefers edges that share a face with the current edge,
  keeping the loop walking along the same face boundary rather than jumping to
  an unrelated face
- Edge path (Alt+Click with 2+ edges selected) — finds the shortest geometric path
  between the last two selected edges; A* with edge-midpoint heuristic; vertex-only
  connection penalty discourages corner-cutting through non-face-sharing edges
- Face path (Alt+Click in Face mode with a face already selected) — finds the
  shortest geometric path between the last selected face and the clicked face;
  A* with face-center heuristic; symmetric results in both directions
- Adjacency caches on `GoBuildMesh` — O(1) lookup dicts (`_vertex_to_faces`,
  `_vertex_to_edges`, `_face_to_edges`, `_edge_lookup`) rebuilt in `rebuild_edges()`;
  replaces O(n) scans in `faces_of_vertex`, `find_edge`, etc.
- Selection helpers — `SelectionHelpers` with `grow_vertices/edges/faces`,
  `shrink_vertices/edges/faces`; wired to Ctrl+=/Ctrl+- keyboard shortcuts and
  context menu in all sub-element modes
- Loop/Ring select — `edge_loop` (with momentum disambiguation at multi-candidate
  vertices and boundary loop fallback), `edge_ring`, `face_loop`, `face_ring`;
  Alt+LMB (loop), Ctrl+Alt+LMB (ring); context menu "Select Loop/Ring"; Shift adds
  to selection
- Select Similar — context menu submenu per mode; Face: material, side count,
  normal, coplanar, area; Edge: length, face count, dihedral; Vertex: valence;
  dot-product comparison for normals, relative tolerance for area/length,
  absolute tolerance for dihedral angles
- UV texture visibility dropdown — per-material texture backgrounds in the UV
  canvas; auto-switches on face selection
- UV face isolation toggle — show only selected faces in UV canvas, hiding all
  others to reduce visual noise during alignment
- UV vertex drag and snap — per-UV-vertex selection and drag in the UV canvas;
  grid snap during UV editing
- Add Texture button in UV panel and via face context menu — file picker assigns
  a texture to selected faces, creating or reusing a `StandardMaterial3D`
- UV drawer-based panel layout — collapsible drawers for UV controls that fit
  narrow dock widths
- Cheatsheet popup — `GoBuildCheatsheetPopup` with balanced 2-column layout;
  accessible via "Help" button in panel header; Escape to dismiss
- Ctrl+Click toggle select — clicking with Ctrl held toggles element selection
  (add if absent, remove if present); overlay hints show the modifier
- Shape placement at cursor — right-click "Add Shape" submenu in all modes;
  raycasts against GoBuild meshes for child placement with bottom-offset; Y-plane
  fallback for miss case; align-to-surface toggle
- World-grid snap mode for gizmo drags — Ctrl+drag on any translate/rotate/scale
  handle now snaps to the editor grid step; axis-aware flush offset and normal
  clamping for placement operations

### Changed
- Mode-switch keys (1-4) now handled in global `_input` callback to take priority
  over Godot's built-in viewport orthographic shortcuts
- Selected-edge ribbons now face the camera for consistent visual thickness from
  every viewing angle (no more paper-thin appearance when viewed edge-on)
- Edge loop disambiguation at multi-candidate vertices now uses momentum (sum of
  walk direction + previous walk direction) for reliable continuation
- Overlay hints updated: Face mode shows "Alt+Click: Path" and "Ctrl+Alt+Click:
  Ring"; Edge mode shows "Alt+Click: Loop (cycle)" and "Ctrl+Alt+Click: Ring";
  all modes show "Ctrl+Click: Toggle" and "Ctrl+Drag: Snap"
- F1 hotkey removed from cheatsheet (conflicts with Godot's add-child-node)
- Face path and edge path cost functions now use pure geometric distance (face-center
  to face-center, edge-midpoint to edge-midpoint) instead of flat hop cost plus
  normal-deviation penalty; this matches Blender's "shortest path" behavior where
  paths follow the geodesic shortest route rather than detouring through coplanar
  surfaces
- Pathfinding tie-breaking in A* prefers nodes closer to the goal (lower heuristic
  score) when f-scores are equal, reducing directional asymmetry in path results
- Default Torus segments reduced from 24 rings / 12 tube segments to 16 / 8,
  reducing face count from 288 to 128 for better interactive draw performance

### Fixed
- Keys 1-4 for GoBuild mode switching no longer conflict with Godot's orthographic
  view shortcuts (Top/Front/Side etc.)
- Vertex and edge pick radii now computed per-element through the node's global
  transform, correctly handling perspective foreshortening and non-uniform scale;
  circumscribe multipliers increased for comfortable click targets that are
  visibly larger than the drawn elements; minimum pick radius floor raised to 10 px
- `close_requested` signal on cheatsheet popup now uses a lambda instead of
  `unbind()` which was invalid in GDScript
- Select Similar: Normal and Coplanar criteria now use dot-product comparison
  (0.999 threshold ≈ 2.5°) instead of quantised string matching; Area and Length
  use relative tolerance (0.1%); Dihedral uses absolute angle tolerance (3°)
- UV general controls split into two rows for narrow panels; tile texture repeat
  extends symmetrically into negative UV space; repeat value of 0 now valid
  (single tile, no surrounding ring)
- Shape placement offset, parenting, and preview positioning bugs fixed
- Staircase generator: side walls decomposed into grid cells for correct fan
  triangulation; bottom and back faces subdivided into per-step strips to eliminate
  T-junction duplicate edges; all edges are now manifold (exactly 2 faces per edge)
- Edge loop cycling now works when clicking any edge in the current loop selection,
  not just the last-selected edge; previously clicking a different edge in the loop
  would compute an unwanted edge_path instead of cycling to the next loop type
- Stale coincident groups after gizmo drags: vertex-move operations (translate,
  rotate, scale) no longer leave coincident groups in a stale state, which caused
  subsequent scale drags to include vertices that should have been separated
  (e.g. after extrude+translate, scaling the top face would also move the base)
- Shape draw ghost uses full-resolution mesh; segment count capping removed.
  Topology changes trigger full bake + edge wireframe rebuild. Dimension-only
  changes use bake_in_place() and surface_update_vertex_region() for fast
  in-place updates without allocating new ArrayMesh objects each frame
- Removed unused GoBuildShapePreview class (replaced by interactive shape draw)

### Tests
- Adjacency cache unit tests added
- 11 failing assertions across 6 test suites fixed
- Face path symmetry tests (grid, cube, staircase — A→B same length as B→A)
- Edge path symmetry tests (grid, cube)
- Face path diagonal preference test (grid)
- Edge path straight-line preference test (grid)
- Boundary edge loop tests (grid, cube, staircase)
- Interior edge loop test (grid — topology walk still works)

---

## [0.7.1] — 2026-06-12

---

### Added
- World/Local transform space toggle — "Space: Local/World" dropdown in the
  toolbar switches gizmo handles between object-aligned (Local) and
  world-aligned (World) orientation; all drag modes (translate, rotate,
  scale, plane, viewport-plane) respect the selected space
- Transform helpers unit tests — 18 pure-math tests covering
  `get_local_axis`, `ray_plane_intersect`, basis transform orthogonality,
  and double-transform regression guard

### Fixed
- Gizmo drags on rotated child meshes now move along the displayed gizmo
  axes instead of world-space axes — removed double-basis-transform bug in
  `GoBuildDragController._compute_frame_result()` where `op.world_axis`
  (already in world space) was re-transformed through the node's basis
- `_compute_initial_world_size` for scale handles now uses the local-space
  axis instead of the world-space axis for projecting local vertex
  positions, fixing incorrect scale sensitivity on rotated meshes

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

