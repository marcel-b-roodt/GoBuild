# GoBuild — Architecture

> **Who this is for:** contributors and anyone curious about how the plugin is structured internally.
> For *using* GoBuild, see [GUIDE.md](../GUIDE.md).

---

## Layer map

| Layer | Path | Description |
|---|---|---|
| Plugin entry point | `addons/go_build/plugin.gd` | `EditorPlugin` root. Registers toolbar, panel dock, gizmo plugin; owns all viewport input routing. |
| Core / UI | `addons/go_build/core/` | Editor panel, gizmo plugin & gizmo instances, picking logic, selection manager, mesh instance node. |
| Mesh data model | `addons/go_build/mesh/` | `GoBuildMesh` resource, face/edge types, shape generators, modelling operations. |
| UV algorithms | `addons/go_build/uv/` | Planar, box, cylindrical, spherical projection *(Stage 4, not yet implemented)*. |
| Export writers | `addons/go_build/export/` | OBJ, GLB, collision builder, LOD generator *(Stage 7, not yet implemented)*. |
| Tests | `tests/` | GdUnit4 suites mirroring the addon structure. |

---

## Key scripts

### `plugin.gd` — EditorPlugin entry point

Owns:
- Viewport input routing (`_forward_3d_gui_input`)
- Box-select tracking state
- Handle-drag lifecycle (begin / update / commit / cancel)
- Mode-switch shortcuts (1/2/3/4, W/E/R)
- Hover highlight tracking
- `EditorUndoRedoManager` integration

### `core/go_build_gizmo_plugin.gd` — GizmoPlugin + drag maths

Owns:
- Shared materials for all gizmo elements
- Canonical cone / plane-quad / scale-cube `ArrayMesh` objects (built once in `setup()`)
- All drag math: `_apply_translate_drag`, `_apply_rotate_drag`, `_apply_plane_drag`, `_apply_scale_drag`, `_apply_viewport_plane_drag`
- Vertex snap: `_find_vertex_snap_world_pos` (V modifier)
- Deferred bake and gizmo-redraw throttling
- Public drag API: `begin_drag / update_drag / commit_drag`

### `core/go_build_gizmo.gd` — per-node gizmo

Owns:
- `_redraw()`: draws vertex cubes, edge lines/ribbons, face overlays, transform handles
- Reads `GoBuildGizmoPlugin.transform_mode` and `_hovered_handle_id` via `Object.get()`

### `core/picking_helper.gd` — element picking

Static utilities:
- `find_nearest_vertex / find_nearest_edge / find_nearest_face` — single-click pick
- `find_vertices/edges/faces_in_rect` — box-select pick
- `ray_triangle_intersect` (Möller–Trumbore), `point_to_segment_dist`

### `core/selection_manager.gd` — selection state

- Stores mode (Object / Vertex / Edge / Face) and selected index sets
- Emits `mode_changed` and `selection_changed` signals consumed by plugin.gd, panel, and gizmo

### `mesh/go_build_mesh.gd` — internal mesh model

Central data structure:

```
vertices:          Array[Vector3]
faces:             Array[GoBuildFace]   (vertex indices, UVs, material, smooth group)
edges:             Array[GoBuildEdge]   (derived; rebuilt via rebuild_edges)
coincident_groups: Array[int]           (group map for shared-corner drag)
material_slots:    Array[Material]
```

Key methods:
- `bake() → ArrayMesh` — fan-triangulates all faces into a Godot mesh
- `compute_face_normal(face)` — Newell's method; always use this, never derive manually
- `rebuild_edges()` — rebuilds edges + coincident_groups from faces
- `take_snapshot() / restore_snapshot()` — deep copy for undo/redo
- `translate_vertices(indices, delta)` — move vertices; does not rebuild edges

### `mesh/operations/` — modelling operations

Each operation is a **static class** (`extends RefCounted`) with a single `apply(mesh, …)` entry point.
Operations mutate the mesh in-place and call `rebuild_edges()` when topology changes.
The panel or plugin wraps each call in `GoBuildMeshInstance.apply_operation()` to get undo/redo for free.

| File | Operation |
|---|---|
| `extrude_operation.gd` | Extrude face(s) along their normal |

### `mesh/generators/` — primitive shape generators

Each generator is a **static class** with a `generate(…) → GoBuildMesh` entry point.
All use `MeshGeneratorUtils.add_quad_grid` for planar quad grids.

---

## Language policy

**All plugin code is GDScript.** No C#, no GDExtension — this ensures the plugin works in every Godot 4 project regardless of whether the user has .NET installed. GDExtension is a last resort only if profiling proves a specific operation cannot meet the <16 ms target in GDScript.

---

## Coordinate system

| Axis | Direction | Godot constant |
|---|---|---|
| X | Right | `Vector3.RIGHT = (1, 0, 0)` |
| Y | Up | `Vector3.UP = (0, 1, 0)` |
| +Z | Toward viewer | `Vector3.BACK = (0, 0, 1)` |
| −Z | Camera-forward | `Vector3.FORWARD = (0, 0, -1)` |

> **Gotcha:** `Vector3.FORWARD` is **−Z**. `Vector3.BACK` is **+Z**.

---

## Face winding invariant

| Layer | Winding | Purpose |
|---|---|---|
| `face.vertex_indices` | CCW from outside | Correct Newell outward normal |
| `_build_surface` output | CW from outside | Front-facing in Godot 4 Vulkan |

All generators and operations **must** store CCW-from-outside winding. The reversal for the GPU happens once in `GoBuildMesh._build_surface()`.

---

## Undo/Redo pattern

```gdscript
# Preferred: use apply_operation for any mesh mutation.
node.apply_operation(
    "Extrude Face",
    func(): ExtrudeOperation.apply(node.go_build_mesh, selected_faces, distance),
    get_undo_redo(),
)
# apply_operation takes a before-snapshot, runs the operation, and registers
# add_do_method(_do_operation) / add_undo_method(restore_and_bake) automatically.
```

---

## Self-preload rule

Godot scans scripts alphabetically. If script A uses class `B` as a type annotation but `B`'s script file hasn't been compiled yet, the class name resolves to `null` and the script is cached with an error.

**Rule:** every script that uses another GoBuild class name at **compile time** (typed vars, parameters, return types) must `preload` that script explicitly at the top of the file, in dependency order.

Runtime-only uses (`is`, `as` casts) do **not** require preloads.

---

## Testing

Framework: **GdUnit4** (install from AssetLib).

Tests mirror the source path under `tests/`:

```
tests/
  mesh/
    go_build_mesh_test.gd
    shape_generator_test.gd
    operations/
      extrude_test.gd
  core/
    selection_manager_test.gd
    picking_helper_test.gd
    ...
  export/
    obj_export_test.gd
  uv/
    planar_projection_test.gd
```

Run locally: open the GdUnit4 panel in Godot → **Run all tests**.
Run in CI: `MikeSchulze/gdUnit4-action` on every push/PR via `.github/workflows/ci.yml`.

