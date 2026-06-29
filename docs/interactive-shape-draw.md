# Interactive Shape Draw

3-click viewport drawing system for inserting primitives. The user draws the
shape's bounding box directly in the 3D viewport with a live wireframe ghost,
measurement labels, and state guidance.

## State Machine

```
enum DrawState { IDLE, POSITION, BASE, HEIGHT }
```

| From | Event | To | Action |
|---|---|---|---|
| `IDLE` | Shape button / context menu | `POSITION` | Activate controller; spawn ghost (default size); ghost follows cursor via raycast |
| `POSITION` | Mouse motion | `POSITION` | Raycast updates ghost position |
| `POSITION` | Left click | `BASE` | Lock anchor point at hit position; begin base drag |
| `BASE` | Mouse drag (held) | `BASE` | Base rectangle drawn anchor→cursor; ghost + dims update |
| `BASE` | Left release | `HEIGHT` | Commit base dimensions; begin height phase |
| `HEIGHT` | Mouse motion | `HEIGHT` | Height scales along normal; ghost + dims update |
| `HEIGHT` | Left click | `IDLE` | Commit shape via `insert_shape()` with undo/redo |
| Any draw state | Escape / Right-click | `IDLE` | Cancel; remove ghost; no node inserted |

**Plane exception:** BASE release commits immediately (skips HEIGHT).

**Shift modifier:** Constrains base to uniform (width = depth for boxes;
square → circle for radial). During HEIGHT, constrains height to match base
(sphere/cube).

**Ctrl modifier:** Snaps to GoBuild's grid snap settings.

## AABB → Generator Parameter Mapping

| Shape | `base_width` → | `base_depth` → | `height` → | Notes |
|---|---|---|---|---|
| **Cube** | `width` | `depth` | `height` | Direct 1:1 |
| **Plane** | `width` | `depth` | *skipped* | 2-click only |
| **Cylinder** | `radius = max(w,d)/2` | — | `height` | Shift makes w=d (perfect circle) |
| **Sphere** | `radius_x = w/2` | `radius_z = d/2` | `radius_y = h/2` | Generator with max radius, then non-uniform scale for ellipsoid; Shift = perfect sphere |
| **Cone** | `radius = max(w,d)/2` | — | `height` | Shift makes w=d |
| **Torus** | `radius_major = (max(w,d) - h)/2` | — | `radius_minor = h/2` | Constraint: `AABB_width > 2 * AABB_height`; clamp if violated |
| **Staircase** | `step_width = w` | `total_depth = d` → `step_depth = d/steps` | `total_height = h` → `step_height = h/steps` | `steps` is a panel integer; origin is bottom-front (not centred) |
| **Arch** | `outer_radius = max(w,d)/2` | — | `depth` (along normal) | `angle_degrees`, `thickness`, `segments` are panel params |

## Wireframe Ghost

`GoBuildMeshInstance` with `owner = null`, `StandardMaterial3D` wireframe +
semi-transparent blue. Rebuilds mesh on every mouse-motion during BASE/HEIGHT.

## Overlay Labels

- **State label** (bottom-left, above mode hint): e.g.
  `"Create Cube — Click to place"` /
  `"Set Width/Depth | Shift: Square | Ctrl: Snap"` /
  `"Set Height | Shift: Uniform | Ctrl: Snap"`
- **Dimensions label** (bottom-right, existing ruler position): e.g.
  `"W: 2.5m × D: 1.0m × H: 0.8m"` or `"R: 1.25m × H: 0.8m"` for radial shapes

## Non-Drawable Panel Params

Compact strip in Create drawer during draw:

| Shape | Panel controls |
|---|---|
| Cube | `Subdivisions [0]` |
| Plane | `Subdiv X [0]  Subdiv Z [0]` |
| Cylinder | `Sides [16]  ☑ Cap Top  ☑ Cap Bottom` |
| Sphere | `Rings [8]  Segments [16]` |
| Cone | `Sides [16]  ☑ Cap Bottom` |
| Torus | `Rings [24]  Tube Segs [12]` |
| Staircase | `Steps [4]` |
| Arch | `Angle [180°]  Segments [8]  Thickness [0.2]` |

Size/radius SpinBoxes are removed — these are drawn.

## Architecture

### New files

| File | Purpose |
|---|---|
| `core/go_build_shape_draw_controller.gd` | State machine, input handling, raycast, ghost, snap, commit |
| `core/go_build_shape_draw_overlay.gd` | Static: state label text, dimension strings |
| `mesh/generators/shape_param_mapping.gd` | Drawn AABB dimensions → generator params per shape |

### Modified files

| File | Changes |
|---|---|
| `plugin.gd` | Wire draw controller into input + overlay; add `start_shape_draw()` |
| `core/go_build_create_drawer.gd` | Buttons → `start_shape_draw()`; compact param strip; remove size SpinBoxes |
| `core/selection_input_controller.gd` | Context menu → `start_shape_draw_at()` |
| `mesh/generators/shape_creation_catalog.gd` | Add `non_drawable_params()`, `build_mesh_from_draw()` |
| `core/go_build_shape_preview.gd` | Refactor into param-strip-only (structural params); remove size UI |
| `docs/feature-registry.md` | Update "Generator parameter preview" and "Shape placement" rows |