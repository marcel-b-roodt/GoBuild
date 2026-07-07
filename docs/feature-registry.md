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
| Generator parameter preview (pre-commit) | ✅ Complete | Panel-native live preview + Accept/Cancel for Cylinder/Cone/Sphere/Staircase/Torus/Arch with configurable counts (sides/segments/steps/rings) and size params; defaults/schema/build dispatch moved into `ShapeCreationCatalog`; final commit inserts a normal node via undo/redo |
| Shape placement at cursor | ✅ Complete | Right-click context menu "Add Shape" submenu in all modes; raycasts against GoBuild meshes for child placement with bottom-offset; Y-plane fallback for miss case; Create drawer places at viewport centre; preview shapes start positioned at cursor |
| Interactive shape draw (3-click insertion) | ✅ Complete | 3-click viewport drawing: POSITION → BASE (drag width/depth) → HEIGHT (drag along normal); wireframe ghost; live dimension labels; Shift constrains to uniform; Ctrl snaps to grid; non-drawable structural params shown in compact panel strip; ellipsoid support for Sphere; bake_in_place for responsive preview |

---

## Stage 2 — Element Selection & Transform

| Feature | Status | Notes |
|---|---|---|
| `SelectionManager` — mode + element selection state | ✅ Complete | `core/selection_manager.gd`; 28 unit tests |
| Edit-mode toolbar (Object / Vertex / Edge / Face) | ✅ Complete | Radio buttons in GoBuildPanel; synced via `mode_changed` signal |
| Keyboard shortcuts 1/2/3/4 (mode switch) | ✅ Complete | Global `_input` in `plugin.gd` — intercepts before Godot's orthographic view shortcuts |
| Viewport gizmos (`EditorNode3DGizmoPlugin`) | ✅ Complete | `GoBuildGizmoPlugin` + `GoBuildGizmo`; vertex/edge/face overlays with selected/unselected colour coding |
| Click-picking (select element on click) | ✅ Complete | `PickingHelper` — screen-space vertex/edge + Möller-Trumbore face; Shift=add, Ctrl=toggle; 11 unit tests |
| Multi-select (box, Shift, Ctrl) | ✅ Complete | Left-drag → rubber-band box select; Shift=additive, Ctrl=toggle; `_forward_3d_draw_over_viewport` fills + outlines rect; `PickingHelper.find_*_in_rect` |
| Grow / Shrink selection | ✅ Complete | `SelectionHelpers.grow_*` / `shrink_*` — one topological ring outward/inward; keyboard Ctrl+=/Ctrl+- and context menu; works in Vertex, Edge, Face modes |
| Loop / Ring select | ✅ Complete | `SelectionHelpers.edge_loop` / `edge_ring` / `face_loop` / `face_ring` — quad-topology walk; Alt+LMB (loop), Ctrl+Alt+LMB (ring); context menu Select Loop/Ring; terminates at boundaries, poles, n-gons; Shift adds to selection |
| Select Similar | ✅ Complete | Context menu submenu per mode; Face: material, side count, normal, coplanar, area; Edge: length, face count, dihedral; Vertex: valence; `SelectionHelpers.similar_faces/edges/vertices` static methods; GdUnit4 tests |
| Adjacency cache on GoBuildMesh | ✅ Complete | O(1) lookup dicts rebuilt in `rebuild_edges()`: `_vertex_to_faces`, `_vertex_to_edges`, `_face_to_edges`, `_edge_lookup`; replaces O(n) scans in `faces_of_vertex`, `find_edge`, etc. |
| Move handle (translate axis drag) | ✅ Complete | `GoBuildGizmoPlugin`: axis materials, `_get/set/commit_handle`; live vertex translate with undo/redo; coincident-vertex expansion ensures all split copies of a shared corner move together |
| Planar translate handles | ✅ Complete | Three semi-transparent squares (XY/YZ/XZ) drawn at centroid offset; `_apply_plane_drag` projects mouse onto the world plane; Ctrl-snap |
| Viewport-plane handle | ✅ Complete | Small square at centroid; `_apply_viewport_plane_drag` uses camera-forward as plane normal; Ctrl-snap |
| Rotate handle  | ✅ Complete | Ring gizmo per axis (YZ/XZ/XY plane); `_apply_rotate_drag` via `Vector3.signed_angle_to`; full undo/redo; `_ray_plane_intersect` pure-math helper with unit tests |
| Scale handle | ✅ Complete | Axis shafts + solid cube tips; `_apply_scale_drag` projects mouse onto axis and computes ratio; full undo/redo |
| Transform mode switch (W / E / R) | ✅ Complete | W=Translate, E=Rotate, R=Scale; intercepted in `_forward_3d_gui_input`; `GoBuildGizmoPlugin.transform_mode` drives gizmo drawing; stays in SELECT mode to suppress Godot's own widget |
| Grid snap (Ctrl modifier) | ✅ Complete | `Ctrl` held during any drag type; snaps to `editors/3d/grid_step` from EditorSettings via `_get_snap_step()`; applied in all four drag types (translate, plane, viewport-plane, rotate does not snap — angle-based) |
| Vertex snap | ✅ Complete | `V` held during any translate drag (axis, plane, viewport-plane); snaps selection centroid to nearest non-dragged mesh vertex; `_find_vertex_snap_world_pos` picks closest screen-space vertex |
| Unified drag pipeline | ✅ Complete | `GoBuildDragController` + `GoBuildDragOperation`: single pipeline for all drag types (gizmo translate/rotate/scale, param-preview extrude/inset/bevel/loop-cut/edge-extrude); precision mode (Shift), snap (Ctrl), vertex snap (Alt); offset-folding for clamp bounds; `post_commit_fn` callback hook; GoBuildDragHandler retired |
| Infinite scroll (param-preview) | ✅ Complete | MOUSE_MODE_CAPTURED provides infinite relative deltas; events captured globally via EditorPlugin._input(); context menu uses call_deferred to avoid cursor jump |
| Infinite scroll (gizmo drags) | ✅ Complete | All gizmo drags use MOUSE_MODE_CAPTURED with per-frame pixel delta accumulation matching param-preview responsiveness |
| Accumulated-delta gizmo strategies | ✅ Complete | Axis project, plane project, viewport plane project, rotate, scale axis, scale uniform, inset — all use GoBuildDeltaStrategy per-frame pixel deltas instead of ray-cast/project |
| Precision-mode indicator | ✅ Complete | Overlay anchor dot, directional colour line (green/red), and live parameter text during param-preview drags; seamless precision toggle mid-drag via anchor re-capture |
| Auto UV parameter controls | ✅ Complete | Scale, U/V Offset, Seam Rotation spinboxes in General drawer; active when Auto UV mode != None; Seam Rotation hidden for Planar/Box; changes trigger immediate re-projection; @export properties persist in scenes |
| UV projection instant preview | ✅ Complete | Planar/Box/Cylinder/Sphere buttons show the projection result immediately on click; no need to nudge a spinbox |
| Show back-faces toggle | ✅ Complete | Opt-in checkbox in panel; works on all material types (BaseMaterial3D duplicated with CULL_DISABLED; ShaderMaterial and null surfaces get semi-transparent blue override); clears on deselect |
| Debug logging gate | ✅ Complete | All diagnostic prints route through GoBuildDebug.log(), gated by GoBuildDebug.enabled (panel checkbox); no ungated prints remain |

---

## Stage 3 — Core Modelling Operations

| Feature | Status | Notes |
|---|---|---|
| Extrude face(s) | ✅ Complete | `ExtrudeOperation.apply(mesh, face_indices, distance)`; per-face-normal extrude, side quads, CCW winding maintained; panel button (0.5u default) + full undo/redo via `apply_operation`; 17 unit tests |
| Extrude edge(s) | ✅ Complete | `EdgeExtrudeOperation.apply`; boundary and interior edges; new quad face `[va, vb, nb, na]` CCW winding; panel button + `Shift+drag` in Edge mode; 16 unit tests; undo/redo via `apply_operation` |
| Inset face(s) | ✅ Complete | `InsetOperation.apply(mesh, face_indices)`; shrinks selected faces inward with new boundary geometry; full undo/redo via `apply_operation` |
| Bevel edge(s) | ✅ Complete | `BevelOperation.apply(mesh, edge_indices, width)`; slides each selected edge's endpoints along the adjacent face perimeters by `width` units, replaces original verts in each adjacent face, and fills the gap with a new bevel quad; panel button (0.1 u default) + full undo/redo via `apply_operation`; boundary-edge guard (no bevel face for single-face edges); 12 unit tests |
| Subdivide faces | ✅ Complete | `SubdivideOperation.apply(mesh, face_indices)`; inserts centroid + shared edge midpoints; splits each N-gon into N quads; adjacent co-selected faces share midpoints (no T-junctions within selection); panel button in Face section + full undo/redo via `apply_operation`; 15 unit tests |
| Bridge / Fill | ✅ Complete | `BridgeOperation.apply(mesh, edge_indices)`; auto-detects topology: two separate boundary loops → quad strip bridge; single closed boundary loop → delegates to `FillOperation` for N-gon fill; panel button "Bridge/Fill" in Edge section + `F` shortcut + context menu; 11 bridge + 9 fill unit tests |
| Fill (standalone) | ✅ Complete | `FillOperation.apply(mesh, edge_indices)`; fills a single closed boundary loop with an N-gon face; extracted from BridgeOperation; context menu "Bridge/Fill" auto-detects topology; 9 unit tests |
| Loop cut | ✅ Complete | `LoopCutOperation.apply(mesh, edge_indices, t)`; walks the quad ring in both directions from each seed edge; splits each ring face into two quads at position `t` (default 0.5); shared cut vertices reused across adjacent faces (no T-junctions); ring walk stops at non-quad faces and mesh boundaries; panel button in Edge section + full undo/redo via `apply_operation`; 14 unit tests |
| Delete geometry | ✅ Complete | `DeleteOperation.apply_faces/edges/vertices(mesh, indices)`; orphaned-vertex compaction + index remapping; panel button; `Delete`/`X` keyboard shortcut; right-click context menu (all sub-element modes); full undo/redo via `apply_operation` |
| Directional extrude | ✅ Complete | New faces created by Extrude Face / Extrude Edge orient their outward normal toward the camera; negative extrude (drag inward) supported |
| Post-commit auto-select | ✅ Complete | `GoBuildDrawer._make_select_*_fn` factory helpers; auto-select new edges after Extrude Edge commit; extensible to other operations |
| Context menu (edit mode) | ✅ Complete | Right-click context menu per mode (Select All, Extrude, Flip Normals, etc.); suppresses stray viewport orbit events while open; deferred popup display avoids cursor jump |
| Modifier-aware toolbar | ✅ Complete | Viewport overlay (`_build_overlay_hint` in `plugin.gd`): mode + op + available-shortcut hints drawn bottom-left of viewport; panel context label (`_context_label` in `go_build_panel.gd`, driven by `_build_panel_context` + `_refresh_panel_context` in `plugin.gd`): shows active op name (Move / ■ Extrude / ■ Extrude Edge / ■ Inset / ■ Snap / ■ Vertex Snap) below the mode buttons; updates on Shift/Ctrl/Alt/V key events, transform mode change, and mode switch |
| Shift+drag → Extrude | ✅ Complete | `_should_extrude_drag` + `_begin_extrude_drag` in `selection_input_controller.gd`; extrudes at distance=0 then translates; undo restores pre-extrude state in one step |
| Shift+drag → Inset | ✅ Complete | `_should_inset_drag` + `_begin_inset_drag` in `selection_input_controller.gd`; `InsetOperation.apply` at distance=0 then `_apply_inset_drag` (screen-space delta → lerp to centroid); undo restores pre-inset state in one step |
| Right-click context menu | ✅ Complete | `PopupMenu` in `selection_input_controller.gd`; per-mode items (Select All, Extrude, Flip Normals); Add Shape submenu in all modes; Object mode context menu enabled; Add Texture in Face mode |
| Rip | ✅ Complete | Split shared vertices or edges apart by duplicating them and leaving an open seam; Vertex and Edge mode; `V` key; `RipOperation.apply_vertices` and `RipOperation.apply_edges`; context menu entry; panel button; 13 unit tests |

---

## Stage 4 — UV Editing & Materials

| Feature | Status | Notes |
|---|---|---|
| Auto UV — Planar | ✅ Complete | `PlanarProjection.apply(mesh, face_indices, units_per_tile)`; dominant-axis per-face projection; defaults to 1 unit per texture repeat so checker or metre textures tile with mesh size; panel button in Face section + face context menu; 5 unit tests |
| Auto UV — Box | ✅ Complete | `BoxProjection.apply(mesh, face_indices, units_per_tile, transform)`; world-space triplanar mapping; seamless tiling across adjacent axis-aligned faces; panel button; 8 unit tests |
| Auto UV — Cylindrical | ✅ Complete | `CylindricalProjection.apply(mesh, face_indices, units_per_tile, transform)`; wraps U around Y axis (atan2); V scales with height; seam correction for faces straddling the discontinuity; panel button ("Cyl UV"); 11 unit tests |
| Auto UV — Spherical | ✅ Complete | `SphericalProjection.apply(mesh, face_indices, units_per_tile, transform)`; equirectangular (lat/lon) mapping; U = longitude (atan2/TAU), V = latitude (acos/PI); seam correction for faces straddling the ±X seam; pole guard for degenerate vertices at origin; panel button ("Sphere UV") in Face UV section; 10 unit tests |
| UV projection parameters (scale, offset, seam rotation) | ✅ Complete | `uv_scale`, `uv_offset`, `uv_seam_rotation` stored per-face; exposed via `GoBuildUvParamBox` live-preview for all four projection buttons; per-face params re-applied by `_apply_face_projection` on auto-UV refresh. Auto UV also has instance-level `auto_uv_scale`, `auto_uv_offset`, `auto_uv_seam_rotation` exposed as spinboxes in the General drawer. |
| UV editor panel | ✅ Complete | `GoBuildUvCanvas` (pan/zoom, face wireframe + selection fill, click-select synced with 3D viewport, Shift/Ctrl add/toggle, rubber-band box select); `GoBuildUvPanel` dock at `DOCK_SLOT_LEFT_UL`; island drag (Move/Rotate/Scale via G/R/S keys or toolbar buttons); per-island pivot; full undo/redo with `take_snapshot`/`restore_and_bake`; Escape cancels drag |
| UV background display | ✅ Complete | `GoBuildUvCanvas` draws checkerboard or texture background in the 0-1 UV tile; cycles via BG button (Checker / Texture / Off); Texture mode reads albedo_texture from first material slot |
| UV pack islands | ✅ Complete | `UvPackIslands.apply(mesh, margin)` — flood-fill island detection, uniform scale-to-fit, shelf-based bin-packing into 0-1 tile; panel Pack button; full undo/redo |
| UV stitch islands | ✅ Complete | `UvStitchIslands.apply(mesh, selected_faces)` — merges UV islands along shared topology edges; snaps UVs on shared vertices; panel Stitch button; full undo/redo |
| UV vertex mode | ✅ Complete | `UvSelectMode.VERTEX` — per-UV-vertex selection and drag in the UV canvas; coincident UV verts move together; Face/Vertex toggle button + Tab shortcut; box-select verts; full undo/redo with Escape cancel |
| UV texture visibility dropdown | ✅ Complete | Dropdown replacing BG cycle button; shows per-material texture backgrounds from material_slots; auto-switches on face selection; manual override persists |
| UV face isolation toggle | ✅ Complete | Toggle to show only selected faces in UV canvas, hiding all others; eliminates visual noise during UV alignment |
| UV Select Island (double-click) | ✅ Complete | Double-click a face in UV canvas to flood-fill select all UV-connected faces in its island; Shift+double-click adds island, Ctrl+double-click toggles |
| Prepare for Texturing | ✅ Complete | One-click "Prep Tex" button in UV panel Operations drawer: applies Box UV projection to all faces then packs islands into 0-1 tile; full undo/redo as single action |
| UV wireframe export (PNG) | ✅ Complete | "Export UV" button in UV panel Operations drawer; renders UV wireframe to PNG at configurable resolution; white lines on transparent background by default; uses Bresenham line drawing with configurable width and colours |
| Add Tex button (UV editor) | ✅ Complete | File picker in UV panel to assign a texture to selected faces; creates or reuses a StandardMaterial3D with the chosen albedo_texture; full undo/redo |
| Drag-and-drop material/texture to UV canvas | ✅ Complete | Drop a Texture2D or Material from the FileSystem dock onto the UV canvas to assign it to selected faces; reuses existing material slots or creates a new StandardMaterial3D; full undo/redo |
| UV settings drawer | ✅ Complete | Collapsible settings drawer in UV panel: dim alpha for unselected faces (isolate toggle), auto-switch texture toggle, pixel snap (UV snap grid size SpinBox), grid subdivision (tile repeat) |
| Lightmap UV (UV2) generation | 📋 Planned | Non-overlapping second channel |
| Per-face material assignment | ✅ Complete | `MaterialAssignOperation.apply(mesh, faces, slot, material=null)`; assigns `face.material_index`; optionally writes material to `material_slots[slot]`; grows slots array as needed; Use button per palette slot in both Face mode (selected faces) and Object mode (all faces); full undo/redo; 10 unit tests |
| Material palette panel | ✅ Complete | Auto-discovered palettes from filesystem (`GoBuildProjectSettings.discover_palettes`); palette dropdown + [+ New] / [🗑 Delete] buttons; per-palette material list with [Use] + [×] per slot; [EditorResourcePicker] for adding materials; `filesystem_changed` signal refreshes dropdown live |
| Prototype blockout materials | ✅ Complete | `GoBuildMaterials`: lazily cached `StandardMaterial3D` presets — checker (256×256 procedural B&W grid, 8×8 cells, NEAREST filter), white, grey; shipped in Default palette at `res://addons/go_build/default_palette.tres` alongside metre checker material |
| GoBuild material palette resource | ✅ Complete | `GoBuildMaterialPalette` Resource (palette_name + materials array); auto-discovered from project filesystem; deprecated `GoBuildProjectSettings.palettes` array migrated to disk on load; in-panel creation/deletion; `ResourceSaver` persists changes on add/remove |

---

## Stage 5 — Surface Detail

| Feature | Status | Notes |
|---|---|---|
| Smooth groups | ✅ Complete | `SmoothGroupOperation.apply(mesh, faces, group_id)`; group 0 = flat-shaded, non-zero IDs average normals at shared vertices; panel Surface section with Group SpinBox (0-31) + Assign, Flat, Smooth buttons; 9 unit tests |
| Hard/soft edge toggle | ✅ Complete | `HardEdgeOperation.apply(mesh, edges, hard)`; `GoBuildEdge.is_hard` (derived); `GoBuildMesh.hard_edge_pairs @export`; BFS `_compute_face_regions()` replaces smooth-group-keyed normals; panel Hard/Soft buttons in Edge section; 11 unit tests incl. bake seam |
| Vertex color paint | 📋 Planned | Per-vertex RGBA brush |
| Normal visualiser overlay | ✅ Complete | Face normals as cyan lines from face centroids; vertex normals as lavender lines from vertices (area-weighted average of adjacent face normals); toggled via "Normals" / "Vtx N" checkboxes in General drawer or N key shortcut; `_draw_face_normals` and `_draw_vertex_normals` in `GoBuildGizmo._redraw()` |

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
| Mesh split / separate | 📋 Planned | Extract selected faces into a new GoBuildMeshInstance; original loses those faces; full undo/redo |
| Mesh cut / seam split | 📋 Planned | Split mesh at seam edges so disconnected geometry becomes separate objects |

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
| Cheatsheet popup | ✅ Complete | `GoBuildCheatsheetPopup`; "Help" button in panel header; balanced 2-column layout; Escape to dismiss |
| Contextual tooltips | 📋 Planned | Status bar hints |
| Right-click context menu | ✅ Complete | Quick-actions for selection; per-mode items; Add Shape submenu |
| Bug report recorder / replay system | 📋 Planned | `GoBuildReplayLogger` records operations (type, parameters, mesh snapshot hash) to JSON; `GoBuildReplayPlayer` replays them for bug reports; design needed before implementation |
| Preferences panel | 📋 Planned | Snap, display, shortcut overrides |
| In-editor documentation panel | 📋 Planned | Links to online docs |
| Theme support | 📋 Planned | Respects dark/light editor theme |
| Sphere / Circle brush select | 📋 Planned | Viewport brush tool; drag circle to paint-select vertices/edges/faces; low priority (grow/loop/ring cover most needs) |

---

## Infrastructure & Tooling

| Feature | Status | Notes |
|---|---|---|
| Semantic versioning + CHANGELOG | ✅ Complete | `CHANGELOG.md` per Keep a Changelog; version in `plugin.cfg` |
| GitHub Actions CI | ✅ Complete | `ci.yml` — GdUnit4 headless on push/PR |
| GitHub Actions release workflow | ✅ Complete | `release.yml` — tag `vX.Y.Z` → draft GitHub Release |
| Godot Asset Library listing | 📋 Planned | Submitted at v1.0 |
| Documentation site | 📋 Planned | GitHub Pages or similar |

---

## Post-v1.0 / Future

| Feature | Status | Notes |
|---|---|---|
| PolyBrush-style sculpting | 📋 Planned | Post-v1.0 |
| Shape draw tool | ✅ Complete | Moved to Stage 1 — see "Interactive shape draw" above |
| Parametric (re-editable) shapes | 📋 Planned | Post-v1.0 |
| SpriteMesh (geometry from sprite outline) | 📋 Planned | Post-v1.0 |

