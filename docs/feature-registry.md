# GoBuild — Feature Registry

**Single source of truth for all features.** Update this file whenever a feature is added, changed, or planned.

Status legend: ✅ Complete · 🔧 In Progress · 📋 Planned · ❌ Removed / Deferred

---

## Stage 0 — Foundation

| Feature | Status | Notes |
|---|---|---|
| EditorPlugin scaffold (`plugin.gd`) | ✅ Complete | Entry point, toolbar registration, GoBuildPanel dock |
| `GoBuildMesh` internal data model | ✅ Complete | Vertex / edge / face lists, normals, UVs, material slots; `translate_vertices`, `compute_centroid`, `take_snapshot`/`restore_snapshot`; `coincident_groups` + `rebuild_coincident_groups` / `get_coincident_vertices` for shared-corner drag correctness |
| `ArrayMesh` bake pipeline | ✅ Complete | Fan triangulation, flat/smooth-group normals, UV0+UV1 |
| MeshInstance3D edit-mode integration | ✅ Complete | `GoBuildMeshInstance` — auto-bakes on resource assign |
| Undo/Redo via `EditorUndoRedoManager` | ✅ Complete | `apply_operation()` + `restore_and_bake()` pattern |
| GdUnit4 test suite (`tests/`) | ✅ Complete | Covers bake, normals, edges, snapshot/restore, translate, centroid, gizmo plugin helpers, GoBuildPanel UX |
| GitHub Actions CI pipeline | ✅ Complete | `ci.yml` — GdUnit4 headless on push/PR |
| GitHub Actions release pipeline | ✅ Complete | `release.yml` — plugin zip on `v*` tag |

---

## Stage 1 — Primitive Shapes

| Feature | Status | Notes |
|---|---|---|
| Cube | ✅ Complete | Width/height/depth, subdivisions |
| Plane | ✅ Complete | Width/depth, XZ subdivisions |
| Cylinder | ✅ Complete | Radius, height, sides, optional end caps |
| Sphere (UV) | ✅ Complete | Radius, lat rings, lon segments |
| Cone | ✅ Complete | Radius, height, sides, optional base cap |
| Torus | ✅ Complete | Major/minor radius, ring + tube segments |
| Staircase | ✅ Complete | Steps, rise/run/width; closed solid |
| Arch | ✅ Complete | Outer radius, thickness, angle, segments, depth |
| Shape insert toolbar | ✅ Complete | One-click creation in GoBuildPanel; full undo/redo |

---

## Stage 2 — Element Selection & Transform

| Feature | Status | Notes |
|---|---|---|
| `SelectionManager` — mode + element selection state | ✅ Complete | `core/selection_manager.gd`; 28 unit tests |
| Edit-mode toolbar (Object / Vertex / Edge / Face) | ✅ Complete | Radio buttons in GoBuildPanel; synced via `mode_changed` signal |
| Keyboard shortcuts 1/2/3/4 (mode switch) | ✅ Complete | `_forward_3d_gui_input` in `plugin.gd` |
| Viewport gizmos (`EditorNode3DGizmoPlugin`) | ✅ Complete | `GoBuildGizmoPlugin` + `GoBuildGizmo`; vertex/edge/face overlays with selected/unselected colour coding |
| Click-picking (select element on click) | ✅ Complete | `PickingHelper` — screen-space vertex/edge + Möller-Trumbore face; Shift=add, Ctrl=toggle; 11 unit tests |
| Multi-select (box, Shift, Ctrl) | ✅ Complete | Left-drag → rubber-band box select; Shift=additive, Ctrl=toggle; `_forward_3d_draw_over_viewport` fills + outlines rect; `PickingHelper.find_*_in_rect` |
| Move handle (translate axis drag) | ✅ Complete | `GoBuildGizmoPlugin`: axis materials, `_get/set/commit_handle`; live vertex translate with undo/redo; coincident-vertex expansion ensures all split copies of a shared corner move together |
| Planar translate handles | ✅ Complete | Three semi-transparent squares (XY/YZ/XZ) drawn at centroid offset; `_apply_plane_drag` projects mouse onto the world plane; Ctrl-snap |
| Viewport-plane handle | ✅ Complete | Small square at centroid; `_apply_viewport_plane_drag` uses camera-forward as plane normal; Ctrl-snap |
| Rotate handle  | ✅ Complete | Ring gizmo per axis (YZ/XZ/XY plane); `_apply_rotate_drag` via `Vector3.signed_angle_to`; full undo/redo; `_ray_plane_intersect` pure-math helper with unit tests |
| Scale handle | ✅ Complete | Axis shafts + solid cube tips; `_apply_scale_drag` projects mouse onto axis and computes ratio; full undo/redo |
| Transform mode switch (W / E / R) | ✅ Complete | W=Translate, E=Rotate, R=Scale; intercepted in `_forward_3d_gui_input`; `GoBuildGizmoPlugin.transform_mode` drives gizmo drawing; stays in SELECT mode to suppress Godot's own widget |
| Grid snap (Ctrl modifier) | ✅ Complete | `Ctrl` held during any drag type; snaps to `editors/3d/grid_step` from EditorSettings via `_get_snap_step()`; applied in all four drag types (translate, plane, viewport-plane, rotate does not snap — angle-based) |
| Vertex snap | ✅ Complete | `V` held during any translate drag (axis, plane, viewport-plane); snaps selection centroid to nearest non-dragged mesh vertex; `_find_vertex_snap_world_pos` picks closest screen-space vertex |

---

## Stage 3 — Core Modelling Operations

| Feature | Status | Notes |
|---|---|---|
| Extrude face(s) | ✅ Complete | `ExtrudeOperation.apply(mesh, face_indices, distance)`; per-face-normal extrude, side quads, CCW winding maintained; panel button (0.5u default) + full undo/redo via `apply_operation`; 17 unit tests |
| Extrude edge(s) | ✅ Complete | `EdgeExtrudeOperation.apply`; boundary and interior edges; new quad face `[va, vb, nb, na]` CCW winding; panel button + `Shift+drag` in Edge mode; 16 unit tests; undo/redo via `apply_operation` |
| Inset face(s) | ✅ Complete | `InsetOperation.apply(mesh, face_indices)`; shrinks selected faces inward with new boundary geometry; full undo/redo via `apply_operation` |
| Bevel edge(s) | ✅ Complete | `BevelOperation.apply(mesh, edge_indices, width)`; slides each selected edge's endpoints along the adjacent face perimeters by `width` units, replaces original verts in each adjacent face, and fills the gap with a new bevel quad; panel button (0.1 u default) + full undo/redo via `apply_operation`; boundary-edge guard (no bevel face for single-face edges); 12 unit tests |
| Subdivide faces | ✅ Complete | `SubdivideOperation.apply(mesh, face_indices)`; inserts centroid + shared edge midpoints; splits each N-gon into N quads; adjacent co-selected faces share midpoints (no T-junctions within selection); panel button in Face section + full undo/redo via `apply_operation`; 15 unit tests |
| Bridge / Fill | ✅ Complete | `BridgeOperation.apply(mesh, edge_indices)`; walks selected boundary edges into two connected chains, aligns loop B to loop A (nearest-start rotation + winding flip heuristic), resamples to equal length, fills with a quad strip; panel button in Edge section + `F` shortcut; 11 unit tests |
| Loop cut | ✅ Complete | `LoopCutOperation.apply(mesh, edge_indices, t)`; walks the quad ring in both directions from each seed edge; splits each ring face into two quads at position `t` (default 0.5); shared cut vertices reused across adjacent faces (no T-junctions); ring walk stops at non-quad faces and mesh boundaries; panel button in Edge section + full undo/redo via `apply_operation`; 14 unit tests |
| Delete geometry | ✅ Complete | `DeleteOperation.apply_faces/edges/vertices(mesh, indices)`; orphaned-vertex compaction + index remapping; panel button; `Delete`/`X` keyboard shortcut; right-click context menu (all sub-element modes); full undo/redo via `apply_operation` |
| Modifier-aware toolbar | ✅ Complete | Viewport overlay (`_build_overlay_hint` in `plugin.gd`): mode + op + available-shortcut hints drawn bottom-left of viewport; panel context label (`_context_label` in `go_build_panel.gd`, driven by `_build_panel_context` + `_refresh_panel_context` in `plugin.gd`): shows active op name (Move / ■ Extrude / ■ Extrude Edge / ■ Inset / ■ Snap / ■ Vertex Snap) below the mode buttons; updates on Shift/Ctrl/Alt/V key events, transform mode change, and mode switch |
| Shift+drag → Extrude | ✅ Complete | `_should_extrude_drag` + `_begin_extrude_drag` in `selection_input_controller.gd`; extrudes at distance=0 then translates; undo restores pre-extrude state in one step |
| Shift+drag → Inset | ✅ Complete | `_should_inset_drag` + `_begin_inset_drag` in `selection_input_controller.gd`; `InsetOperation.apply` at distance=0 then `_apply_inset_drag` (screen-space delta → lerp to centroid); undo restores pre-inset state in one step |
| Right-click context menu | ✅ Complete | `PopupMenu` in `selection_input_controller.gd`; per-mode items (Select All, Extrude, Flip Normals); stub items for planned ops |

---

## Stage 4 — UV Editing & Materials

| Feature | Status | Notes |
|---|---|---|
| Auto UV — Planar | ✅ Complete | `PlanarProjection.apply(mesh, face_indices, units_per_tile)`; dominant-axis per-face projection; defaults to 1 unit per texture repeat so checker or metre textures tile with mesh size; panel button in Face section + face context menu; 5 unit tests |
| Auto UV — Box | 📋 Planned | Six-axis projection |
| Auto UV — Cylindrical | 📋 Planned | |
| Auto UV — Spherical | 📋 Planned | |
| UV editor panel | 📋 Planned | 2D panel; drag/rotate/scale islands |
| Lightmap UV (UV2) generation | 📋 Planned | Non-overlapping second channel |
| Per-face material assignment | 📋 Planned | Right-click → Assign Material |
| Material palette panel | 📋 Planned | All slots on active mesh |
| Prototype blockout materials | 📋 Planned | Unit checker plus colour-coded defaults for fast greyboxing |
| GoBuild material palette resource | 📋 Planned | Swap-able palette asset supplying reusable material slots |

---

## Stage 5 — Surface Detail

| Feature | Status | Notes |
|---|---|---|
| Smooth groups | 📋 Planned | Normal averaging within group |
| Hard/soft edge toggle | 📋 Planned | Split normals per edge |
| Vertex color paint | 📋 Planned | Per-vertex RGBA brush |
| Normal visualiser overlay | 📋 Planned | Face + vertex normals as viewport lines |

---

## Stage 6 — Boolean & Advanced Operations

| Feature | Status | Notes |
|---|---|---|
| Boolean Union | 📋 Planned | |
| Boolean Subtract | 📋 Planned | |
| Boolean Intersect | 📋 Planned | |
| Mirror tool | 📋 Planned | X/Y/Z axis |
| Array / duplicate along path | 📋 Planned | |
| Surface snap | 📋 Planned | Snap to other mesh surfaces |
| World vertex snap | 📋 Planned | Snap selected elements to vertices on other meshes in the scene (extends V-modifier snap which targets the active mesh only) |
| Pivot tool | 📋 Planned | Reposition mesh origin |

---

## Stage 7 — Export & Integration

| Feature | Status | Notes |
|---|---|---|
| OBJ export | 📋 Planned | |
| GLB export | 📋 Planned | Binary GLTF 2.0 |
| Collision generation | 📋 Planned | Convex or concave sibling node |
| LOD generation | 📋 Planned | Simplified meshes at configurable ratios |
| Batch export | 📋 Planned | All GoBuild meshes in scene |

---

## Stage 8 — Polish & UX

| Feature | Status | Notes |
|---|---|---|
| Keyboard shortcut map | 📋 Planned | Configurable; Blender-compatible defaults |
| Contextual tooltips | 📋 Planned | Status bar hints |
| Right-click context menu | 📋 Planned | Quick-actions for selection |
| Preferences panel | 📋 Planned | Snap, display, shortcut overrides |
| In-editor documentation panel | 📋 Planned | Links to online docs |
| Theme support | 📋 Planned | Respects dark/light editor theme |

---

## Infrastructure & Tooling

| Feature | Status | Notes |
|---|---|---|
| Semantic versioning + CHANGELOG | 📋 Planned | `CHANGELOG.md` per Keep a Changelog |
| GitHub Actions CI | ✅ Complete | `ci.yml` — GdUnit4 headless on push/PR |
| GitHub Actions release workflow | ✅ Complete | `release.yml` — tag `vX.Y.Z` → draft GitHub Release |
| Godot Asset Library listing | 📋 Planned | Submitted at v1.0 |
| Documentation site | 📋 Planned | GitHub Pages or similar |

---

## Post-v1.0 / Future

| Feature | Status | Notes |
|---|---|---|
| PolyBrush-style sculpting | 📋 Planned | Post-v1.0 |
| Shape draw tool | 📋 Planned | Post-v1.0 |
| Parametric (re-editable) shapes | 📋 Planned | Post-v1.0 |
| SpriteMesh (geometry from sprite outline) | 📋 Planned | Post-v1.0 |

