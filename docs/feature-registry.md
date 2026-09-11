# GoBuild — Feature Registry

**Single source of truth for all features.** Update this file whenever a feature is added, changed, or planned.

Status legend: ✅ Complete · 🔧 In Progress · 📋 Planned · ❌ Removed / Deferred

---

## Stage 0 — Foundation

| Feature | Status | Notes |
|---|---|---|
| EditorPlugin scaffold (`plugin.gd`) | ✅ Complete | Entry point, toolbar registration, GoBuildPanel dock; "Reset Panel Layout" tool menu item restores dock positions |
| `GoBuildMesh` internal data model | ✅ Complete | Vertex / edge / face lists, normals, UVs, material slots; `translate_vertices`, `compute_centroid`, `take_snapshot`/`restore_snapshot`; `coincident_groups` + `rebuild_coincident_groups` / `get_coincident_vertices` for shared-corner drag correctness |
| `ArrayMesh` bake pipeline | ✅ Complete | Convexity-gated triangulation (`Triangulate.triangulate_face`: O(n) convexity test → `fan` for convex, `ear_clip` for concave, CW-from-outside normalised), flat/smooth-group normals, UV0+UV1 |
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
| Staircase | ✅ Complete | Steps, rise/run/width; closed solid, all faces outward-wound (ray-parity clean) |
| Arch | ✅ Complete | Outer radius, thickness, angle, segments, depth |
| Doorway | ✅ Complete | `DoorwayGenerator.generate(width, height, depth, opening_width, opening_height, arched, segments)`; AABB wall with rectangular or arched centred opening cut through full depth; decomposed pieces (jambs / spandrels / arc head) butt cleanly with no overlapping solids or buried coplanar faces (`_add_box_x` skip param — no z-fighting); registered in `ShapeCreationCatalog` with Open W/H ratios, Arched toggle, Segments in the param strip; 16 unit tests |
| Shape insert toolbar | ✅ Complete | One-click creation in GoBuildPanel; full undo/redo |
| Viewport param popup during draw | ✅ Complete | `GoBuildDrawParamPopup` (PanelContainer over 3D viewport, top-right); floats over viewport during 3-click draw so structural params (steps/sides/caps) are editable without focusing the dock; shown/hidden by `GoBuildCreateDrawer` alongside the dock strip; plain PanelContainer (not PopupPanel) so outside clicks keep reaching the draw flow |
| Generator parameter preview (pre-commit) | ✅ Complete | Panel-native live preview + Accept/Cancel for Cylinder/Cone/Sphere/Staircase/Torus/Arch with configurable counts (sides/segments/steps/rings) and size params; defaults/schema/build dispatch moved into `ShapeCreationCatalog`; final commit inserts a normal node via undo/redo |
| Shape placement at cursor | ✅ Complete | Right-click context menu "Add Shape" submenu in all modes; raycasts against GoBuild meshes for child placement with bottom-offset; Y-plane fallback for miss case; Create drawer places at viewport centre; preview shapes start positioned at cursor |
| Interactive shape draw (click-based insertion) | ✅ Complete | Click flow: POSITION → WIDTH (click fixes width segment; its direction becomes the shape's local +X = orientation) → LENGTH (click fixes depth on the perpendicular) → HEIGHT → commit; polygon shapes: POSITION → POLYGON vertices → HEIGHT.  Wireframe ghost; live dimension labels; Shift = square/uniform; every inserted node's pivot sits at the mesh BASE CENTRE (bottom face centre — consistent gizmo/snap behaviour across generators, `_pivot_to_base_centre` normalizes the authored origin at draw time); Ctrl = ProBuilder-style snap (cursor positions to world grid AND dimension values quantized — no mode toggle); pure maths in `ShapeDrawMaths` (24 unit tests) + ray-parity invariant test over every catalog shape; non-drawable structural params shown in compact panel strip; ellipsoid support for Sphere; bake_in_place for responsive preview |
| Polygon draw tool | ✅ Complete | Draw arbitrary convex/concave polygon outlines in the viewport; click to place vertices, close loop on first vertex or Enter; then drag height to extrude into a prism; first vertex highlighted green, rest cyan; inherits existing create-shape pipeline; `PolygonGenerator` creates prism from arbitrary vertex list; ear-clip triangulation for concave caps; `Triangulate` utility with `fan()` and `ear_clip()` extracted as reusable helpers; node positioned at centroid of drawn points; polygon step uses the shared 2D crosshair + rubber-band cursor overlay (`GoBuildCursorOverlay`, same as knife) |

---

## Stage 2 — Element Selection & Transform

| Feature | Status | Notes |
|---|---|---|
| `SelectionManager` — mode + element selection state | ✅ Complete | `core/selection_manager.gd`; 28 unit tests |
| Edit-mode toolbar (Object / Vertex / Edge / Face) | ✅ Complete | Radio buttons in GoBuildPanel; synced via `mode_changed` signal |
| Keyboard shortcuts 1/2/3/4 (mode switch) | ✅ Complete | Global `_input` in `plugin.gd` — intercepts before Godot's orthographic view shortcuts |
| Viewport gizmos (`EditorNode3DGizmoPlugin`) | ✅ Complete | `GoBuildGizmoPlugin` + `GoBuildGizmo`; vertex/edge/face overlays with selected/unselected colour coding |
| Click-picking (select element on click) | ✅ Complete | `PickingHelper` — screen-space vertex/edge + Möller–Trumbore face; Shift=add, Ctrl=toggle; backface culling + vertex/edge occlusion when X-ray off; 13 unit tests |
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
| Localized snap grid (Ctrl overlay) | ✅ Complete | Three small orthogonal panels (±2 snap cells) that **follow the drag** (anchored at the live snapped reference each frame) during translate drags with Ctrl: bright axis centre lines + dim outline + lattice-point crosses; Godot axis colours; Delta mode orients to node-local axes |
| Grid snap (Ctrl modifier) | ✅ Complete | `Ctrl` held during any drag type; snaps to `editors/3d/grid_step` from EditorSettings via `_get_snap_step()`; applied in all drag types.  GoBuild toolbar on its **own line** (child of the Node3DEditor VBox under the native tool row): `GoBuild vX` label, edit-mode toggles, **Snap** button (chevron) → popup with enum dropdowns (Mode / Translate / Rotation / Scale), read-only summary label, **Local/World** gizmo-space OptionButton with values label, **Space** Local/World, cog (⚙) menu (Print Selection, Debug Logging, X-Ray, Face/Vertex Normals, Reset Panel Layout), and docs (README) button.  Edit-mode toggles sync with the 1-4 shortcuts. The global Debug/X-Ray/Normals toggles moved out of the General drawer into the cog menu; the dock panel keeps its drawers and context label only.  Snap Mode: **Hybrid** (ProBuilder default — object moves snap final world positions to grid crossings; element edits snap the drag reference's absolute position to grid crossings, correction applied rigidly so off-grid geometry lands on grid), **World** (same absolute-position snapping for element edits; object moves quantize deltas; scale quantizes the resulting world size), **Delta** (legacy local incremental) |
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
| Inset face(s) | ✅ Complete | `InsetOperation.apply(mesh, face_indices, amount, inner_centroids, inner_normals)`; amount ≥ 0 blends toward centroid (0..1), amount < 0 = depth mode: inner ring pushed along -face-normal by units (sunken floor with vertical wall quads); panel Inset preview range widened to -100..100; Shift+drag inset supports negative drag via `_inset_normals` map in drag controller; 11 unit tests |
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
| Rip | ✅ Complete | Split shared vertices or edges apart by duplicating them and leaving an open seam; Vertex and Edge mode; `V` key; `RipOperation.apply_vertices` and `RipOperation.apply_edges`; context menu entry; panel button; 14 unit tests |
| Merge faces | ✅ Complete | `MergeFacesOperation.apply(mesh, face_indices)`; merges adjacent selected faces into single N-gon by dissolving interior edges; BFS groups faces by adjacency; boundary ring walk with Newell-normal winding correction (reverses ring if normal is inward); inherits material, smooth group, and UVs from first face; panel button in Face section (requires 2+ selected faces) |
| Dissolve (vertex/edge/face) | ✅ Complete | `DissolveOperation.dissolve_vertices/dissolve_edges`; merges surrounding faces into one, removing the element without leaving holes; vertex dissolve walks face-to-face boundary ring with Newell-normal winding check; edge dissolve merges two adjacent faces into one; face dissolve delegates to `MergeFacesOperation`; panel buttons in Vertex, Edge, Face sections; context menu entries (IDs 14, 27, 38); full undo/redo; winding verification ensures correct CCW output |
| Triangulate faces | ✅ Complete | `TriangulateOperation.apply(mesh, face_indices)`; converts selected N-gon faces into triangles using `ear_clip` for concave polygons with `fan` fallback for non-planar faces; preserves material, smooth group, UV projection settings; panel "Triangulate" button in Face section; context menu ID 39; full undo/redo |
| Consolidate material slots | ✅ Complete | `ConsolidateSlotsOperation.apply(mesh)`; merges duplicate material slots (same resource or both null) into one; removes empty slots; reindexes all face material_index values; panel button "Consolidate Slots" in Materials drawer |
| Multi-mode operations (UV + smooth groups) | ✅ Complete | UV projection buttons (Planar, Box, Cyl, Sphere) and smooth group buttons (Flat, Smooth, Assign) now work in Object mode, applying to all faces; Face mode still requires selection |

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
| GoBuild material palette resource | ✅ Complete | `GoBuildMaterialPalette` Resource (palette_name + materials array); auto-discovered from project filesystem; deprecated `GoBuildProjectSettings.palettes` array migrated to disk on load; in-panel creation/deletion; `ResourceSaver` persists changes on add/remove; `material_from_file(path)` static helper wraps Texture2D in `StandardMaterial3D` (albedo) or loads `.tres` materials |
| Palette texture drag-drop | ✅ Complete | Drop Texture2D / Material files from FileSystem dock onto the Materials drawer palette list (`_can_drop_data`/`_drop_data` on `GoBuildMaterialsDrawer`); first file wrapped via `GoBuildMaterialPalette.material_from_file`, appended to palette, persisted via `ResourceSaver` |

---

## Stage 5 — Surface Detail

| Feature | Status | Notes |
|---|---|---|
| Smooth groups | ✅ Complete | `SmoothGroupOperation.apply(mesh, faces, group_id)`; group 0 = flat-shaded, non-zero IDs average normals at shared vertices; panel Surface section with Group SpinBox (0-31) + Assign, Flat, Smooth buttons; 9 unit tests |
| Hard/soft edge toggle | ✅ Complete | `HardEdgeOperation.apply(mesh, edges, hard)`; `GoBuildEdge.is_hard` (derived); `GoBuildMesh.hard_edge_pairs @export`; BFS `_compute_face_regions()` replaces smooth-group-keyed normals; panel Hard/Soft buttons in Edge section; 11 unit tests incl. bake seam |
| Vertex color paint | ✅ Complete | `VertexColorOperation`: fill_faces, fill_all, set_vertices with blend modes (Mix/Add/Subtract/Multiply) and channel masking (R/G/B/A); 4 custom float channels (CUSTOM0–3) for per-vertex data beyond colour; `GoBuildVertexPainter` separate dock panel with colour picker, greyscale slider, target channel dropdown (Color/Custom 0–3), channel mask toggles, blend mode, brush radius/strength, Fill Selected/Fill All buttons, Paint mode toggle; `GoBuildVertexPaintBrush` stroke controller: click-drag to paint vertices within brush radius, Alt+S=resize, Alt+D=strength, Shift+A=cycle blend, Alt+Click=eyedropper, undo/redo per stroke; brush cursor overlay with radius circle and info label; Isolate View: shader overlay visualises R/G/B/A channels with greyscale toggle, swaps custom channel data into vertex_colors for shader readback; `paint_vertices_in_radius` static helper for testable brush logic; `begin_preview`/`bake_preview`/`end_preview` for performant in-stroke updates; auto-transparency when vertex alpha < 1.0; `VertexColorOperation.swap_channel_to_vertex_colors`/`restore_vertex_colors`/`sync_channel_to_vertex_colors` pure helpers for isolate channel management; vertex_colors and custom channels preserved through all mesh operations; `GoBuildMesh.has_alpha_below_one()` extracted as reusable query; `GoBuildMeshInstance.bake_silently()` for signal-safe bakes |
| Normal visualiser overlay | ✅ Complete | Face normals as cyan lines from face centroids; vertex normals as lavender lines from vertices (area-weighted average of adjacent face normals); toggled via "Normals" / "Vtx N" checkboxes in General drawer or N key shortcut; `_draw_face_normals` and `_draw_vertex_normals` in `GoBuildGizmo._redraw()` |

---

## Stage 6 — Boolean & Advanced Operations

| Feature | Status | Notes |
|---|---|---|
| Boolean Union | 📋 Planned | |
| Knife cut | 🔧 In Progress | Three-phase pipeline in `GoBuildKnife` — cycle-based resolver: closed strokes drop the duplicate closing point, run entry/exit crossings come from the INCOMING/OUTGOING segments (with stable `va/vb` edge indices — immune to ring shifts), pass-through single-point faces cut correctly, touch/graze cases are clean no-ops (no more "degenerate anchors" drops); edges re-crossed by the path split SEQUENTIALLY (ring-authority sub-chain walk — stale edge lookups no longer skip cuts); cut vertices position-keyed (one vertex per physical point across edges/directions); closed strokes whose points all lie on one face (interior or ring boundary — cursor-face picking on shared edges scatters the indices) remap to that geometric owner and resolve as a single-face loop (an all-on-ring-edges quad loop now cuts: 4 split halves + 2 drawn edges, island + 2 outer bands); point-in-poly treats on-ring points as inside (the ray test is undefined at the polygon's max-y edge — top-edge points read as outside and killed the owner remap); closed-loop emission = Blender's minimal layout via TWO-BAND split: island n-gon (drawn edges 1:1) bridged to two ring corners (nearest island corner 0 + opposite corner), outer region split into two concave-but-simple band n-gons — island arcs assigned geometrically (arc whose interior corners sit nearest the outer arc; winding-independent), same counts as Blender's keyhole (+n_loop v, +n_loop+2 e, +2 f) without the non-manifold slit; ring-member loop corners (snapped corners, cut verts) chain bands member→member with zero bridge edges — on-edge loop points SPLIT the ring (shared with the neighbour face, no T-junctions) before band assembly, so boundary-hugging loops become member chains (one band takes the island far side, Blender-parity slit edge); two-member bands take the non-empty island arc, 3+ member stretches pair arcs by distance; single-member hug emits ONE keyhole n-gon — [member, outer walk, member, island far side] with the attachment slit, NO bridge edge and no sliver triangle (Blender parity for vertex/edge-attached loops, verified area-preserving); the island-walk direction (hole) is picked by smallest ring area (face − island vs the double-counted face + island — parity probes lie on self-touching rings); island-arc pairing for interior-island bridges AND 3+-member stretches is structural (arc holds no other member; leftover island corners stay outside the band polygon via a corrected point-in-poly — the old maxf epsilon clamp on the signed interpolation denominator dropped downward-edge crossings and poisoned every containment verdict) with the distance metric as tie-break only; open-cut paths with consecutive duplicate points (off-face clicks clamping to one corner) are deduped, and a path revisiting a position is rejected cleanly before vertex creation; open-run partition is a ring-order member-chain band system: mid-path on-edge points split their ring edge (shared with the neighbour), path points on ring vertices/cut verts reuse them, every ring arc between consecutive members becomes one band closed by a monotone chain walk (first emitted band replaces the face); edge snaps in the knife controller store mesh-local positions (same space as all other snap branches); knife snapping works outside the silhouette (vertex → edge → face-hit order, context face = the face under the cursor when available); gizmo selection-highlight fill ear-clips face rings (dent-safe — the old fan spilled over island cuts as phantom diagonals); off-face picked points clamp to the nearest ring-edge point (Blender surface semantics); zero-geometry close when the loop rides existing edges; Enter auto-closes visually-closed strokes (last hover near the first point on screen within the close threshold), Ctrl+Enter forces the closed form, Backspace undoes the last stroke point; a viewport popup during cutting offers clickable "Undo Point" and "Close Loop" buttons mirroring the keys (PopupPanel hosted on the editor base control, shown via `visible` — container semantics, no transient auto-close; exists only while the stroke is active, hidden on cancel/confirm); open runs thread path verts between anchors (reversed into arc A, forward into arc B); UV preservation: edge splits insert a lerped UV into every affected face (sizes stay aligned), emitted n-gons map UVs by ring slot against the source face; new interior vertices interpolate the source face's UV field barycentrically over its ear-clip triangulation (planar 1-unit=1-tile fallback only when the source face has no UVs) — cut geometry keeps the original UV layout instead of stretching; toolbar "Print Selection" button dumps selected verts (index@position), edges (index[a→b]), faces (index ring=…) to the Output panel; hover system: motion-tracked snap chain (face → vertex → edge with cursor projected on the edge) shared by hover + click, edge click places a snapped point (Blender semantics), Ctrl grid-snaps the raw surface hit (world x/z to editor grid step, Create Shape/Polygon convention — vertex/edge snaps stay exact); overlay: hovered edge highlight, crossing/pierce preview dots (per segment, where the cut will create vertices), shared crosshair (`GoBuildCursorOverlay`), rubber band, closing preview, the PENDING segment (last point → hover position) shows its crossing dots too — the cut's edge pierces light up while hovering, Blender-style; `find_nearest_face` returns -1 on miss; [KnifeGeom] debug prints; multi-face strokes: the single-face-owner test requires every point ON the candidate face's PLANE (cross-plane points folded onto ring edges and collapsed a 4,2,2,4 two-face stroke into a bogus single-face loop — warped island quad spanning two planes, no splits); screen-space edge crossings: the controller projects the stroke through the CURRENT camera at confirm and injects the visible edge pierces (Blender's screen-space knife — a straight 3D segment between picks on adjacent faces tunnels the shared corner edge; the projected path is authoritative), crossings insert INTO the stroke as on-ring picked points so runs anchor at the cut verts (edge split twice for a double-crossed shared edge, both faces' rings walk the halves, no T-junctions); screen crossings inject ONLY when the 3D chord TUNNELS past the edge (3D point-line distance > 1% of segment scale — coplanar crossings of previous cut edges belong to the resolver; injecting those scattered single-face loops into broken runs with wrong host faces); the owner remap collects candidates from EVERY point's picked face + ring adjacency (a snap-grabbed shared element recorded under the wrong cursor-face sits on the neighbour's ring) and runs BEFORE the face clamp (clamping first displaced the point onto the wrong face's boundary — a bottom-edge click became a top-edge hug); run ends whose INCOMING/OUTGOING pick lies on the face ring resolve to that member (shared-edge snapped points anchor the run instead of the nearest corner — the "anchors not on ring"/triangle-mess path); knife picking honours X-ray mode (culling follows the gizmo plugin's flag like selection — X-ray OFF never snaps through the mesh) and vertex/edge occlusion casts each element's OWN screen ray (the old test compared t along the click ray: visible snap candidates were culled and hidden ones passed — the "X-ray" snap behaviour and misaligned placed points); face_crossings rejects skew-segment phantom hits (edge_hit's coplanar formula on off-plane segments invented ring crossings — phantom splits and bogus anchors on multi-face strokes); coplanar-partition strokes: when no single face holds a closed stroke, each point re-picks its face geometrically (first face whose polygon contains it — picked face preferred, ring-adjacent next), so a quad drawn across several coplanar faces cuts ALL of them (the drawn quad over an L-shaped earlier-cut surface no longer cuts only one face); face_crossings' phantom gate is a 3D point-to-SEGMENT distance test (a hit on a ring edge is always in the face plane, so the plane gate could not catch phantoms — the segment-distance gate does); edge snap occlusion tests the SNAP POSITION (the cursor's parameter on the edge) instead of either endpoint — no more snap/highlight on edge portions behind the surface; edge snap lands at the CAMERA-RAY × 3D-edge closest approach (the old screen-parameter lerp misaligned under perspective — screen-t ≠ world-t along a 3D segment; the placed point jumped, worst at oblique angles, even mid-quad when an edge was within the snap radius); pick trace debug prints (cursor px, world pos, re-projected screen px, pixel error) on every plotted knife point; the re-pick face test requires the point ON the face plane (cross-plane folds onto shared edges read as "inside" and scattered the stroke); apply() is TRANSACTIONAL — a failed run rolls the whole op back from a snapshot (failed applies no longer leave orphaned cut verts behind); edge-snap ray-edge closest approach uses the CORRECT edge parameter sign (the negated formula clamped to the wrong end of the edge — the 314px jump; the pick trace pinpointed it: only the edge-snapped point showed err≠0); a single-touch run is a clean no-op, not a failure (the transactional rollback no longer discards the other runs' successful cuts); same-face groups SPLIT at geometric ring exits (a stroke drawn across coplanar bands with all clicks under one face index now cuts every face the path crosses — the crossing point closes one run and opens the next on the neighbour face; the "incomplete quad" on partitioned surfaces); edge snap = screen-perp foot of the cursor, then the camera ray through the FOOT intersected with the 3D edge line (the closest-approach clamp grabbed the wrong end of oblique edges — corner jumps, left-side bias); group-split exits verify the segment LEAVES the face (the point just past the crossing must be outside the face polygon — a ring-vertex graze no longer hands the rest of the path to the neighbour and reshapes the drawn polygon); 35 unit tests + 2 user-mesh regression tests (GoBuildCube5 fixture: the closed-interior-quad must resolve as a loop; the pick round-trip must re-hit the point) |
| Persistent edge topology | ✅ Complete | BMesh-style migration per docs/persistent-edges-design.md; `GoBuildMesh` mutation helpers (`edge_key`, `register_face`, `unregister_face`, `split_edge` = ring insertion + hard-pair split, `replace_vertex_in_rings`, `delete_faces`, `compact_edges`, `refresh_edge_face_indices` incl. `_vertex_to_faces`/`_vertex_to_edges` rebuilds, `sync_edge_hard_state`); knife fully incremental (zero rebuilds — split_edge + per-face unregister/register + compaction + drift assert); extrude + loop_cut migrated off `rebuild_edges` (loop_cut cut verts now go through `split_edge` — open-ring cuts no longer create T-junctions; replacement faces are arcs of the split ring, winding-safe for n-gons); delete op via `mesh.delete_faces`; debug-only `validate_edge_topology()` asserts persistent edges ≡ ring-derived after ops; `find_edge` unified on `edge_key`; `hard_edge_pairs` stays serialization authority, `GoBuildEdge.is_hard` runtime view; remaining ops keep `rebuild_edges()` (correct, migrate incrementally with the assert as net); file format unchanged — old scenes load as-is |
| Boolean Subtract | 📋 Planned | |
| Boolean Intersect | 📋 Planned | |
| Mirror tool | 🔧 In Progress | Live symmetry: `GoBuildSymmetry` (pure mirror math, position-hashed partner maps, `materialize()` twin-append + weld); toggle + axis in General drawer; `GoBuildMeshInstance.symmetry_enabled`/`symmetry_axis` persist; enable runs undoable materialize so existing geometry becomes symmetric; drag transforms mirror live (partners moved, on-plane verts pinned); structural ops materialize via `apply_operation`; boundaries: per-object (creation flows like Create Polygon spawn separate nodes, not mirrored); v1 |
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
| GLB export | 🔧 In Progress | Binary GLTF 2.0 via Godot GLTFDocument; inspector button on GoBuildMeshInstance |
| Collision generation | ✅ Complete | Toggle on GoBuildMeshInstance creates child StaticBody3D + CollisionShape3D; concave (default) or convex; stays in sync on bake; proxy collision properties (layer, mask, disable mode, ray pickable) on GoBuildMeshInstance; hidden when use_collision=false; Inspector groups: Collision, Auto UV |
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
| Code deduplication pass 1 | ✅ Complete | `_compact_vertices` extracted to `GoBuildMesh.compact_vertices()` (was duplicated in weld, delete, bevel, rip operations); `compute_ring_normal` added to `GoBuildMesh` (was duplicated in `MergeFacesOperation`); both return remap dict for callers that need it |
| Code deduplication pass 2 | ✅ Complete | `UVProjectionUtils` (project_to_dominant_axis, correct_seam) extracted from planar/box/cylindrical/spherical projections; `UvTopology` (build_uv_vertex_map, uv_key) extracted from uv_island_select and uv_pack_islands; `GoBuildConstants` centralises gizmo/picking constants; `SelectionManager` O(1) Dictionary membership; `GoBuildMesh.finalize()` convenience wrapper; `Triangulate` utility with `fan()` and `ear_clip()` extracted from bake pipeline and polygon generator |
| Code deduplication pass 3 | ✅ Complete | `VertexColorOperation.swap_channel_to_vertex_colors` / `restore_vertex_colors` / `sync_channel_to_vertex_colors` extracted from painter isolate logic; `GoBuildMesh.has_alpha_below_one()` extracted from `GoBuildMeshInstance._any_alpha_below_one`; `GoBuildMeshInstance.bake_silently()` replaces disconnect-bake-reconnect pattern |
| Godot Asset Library listing | 📋 Planned | Submitted at v1.0 |
| Documentation site | 📋 Planned | GitHub Pages or similar |
| Mesh import (ArrayMesh → GoBuildMesh) | ✅ Complete | `MeshImport.from_array_mesh`: reads vertex positions, UVs, UV2s, vertex colours from each surface; per-triangle faces; material slots; `reverse_winding` flag for re-importing GoBuild-baked meshes; indexed and non-indexed meshes; edges rebuilt on import |

---

## Post-v1.0 / Future

| Feature | Status | Notes |
|---|---|---|
| PolyBrush-style sculpting | 📋 Planned | Post-v1.0 |
| Shape draw tool | ✅ Complete | Moved to Stage 1 — see "Interactive shape draw" above |
| Parametric (re-editable) shapes | 📋 Planned | Post-v1.0 |
| SpriteMesh (geometry from sprite outline) | 📋 Planned | Post-v1.0 |

