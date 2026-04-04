# GoBuild — Development Roadmap

Target: **Feature parity with Unity ProBuilder (core feature set) for Godot 4.**

Stages are ordered by dependency and user value. Each stage should be releasable as a versioned milestone.

---

## Stage 0 — Foundation (`v0.1.x`)

The scaffolding that all later work depends on. Nothing visible to the user except a toolbar.

| Item | Description |
|---|---|
| EditorPlugin setup | `plugin.gd` registers the plugin, toolbar, and panel |
| `GoBuildMesh` resource | Internal mesh data model: vertex list, edge list, face list, normals, UVs, material slots |
| MeshInstance3D integration | Selecting a `MeshInstance3D` with a GoBuild tag enters edit mode; exiting rebuilds the mesh |
| `ArrayMesh` bake pipeline | Converts `GoBuildMesh` → Godot `ArrayMesh` on commit |
| Undo/Redo integration | All edit operations push to `EditorUndoRedoManager` |
| Unit test project | `Tests/GoBuild.Tests` xUnit project wired to CI; mesh math helpers covered |
| CI pipeline | GitHub Actions: build, test, lint on every PR |

---

## Stage 1 — Primitive Shapes (`v0.2.x`)

Users can create basic shapes without leaving the editor.

| Item | Description |
|---|---|
| Cube | Parameterised width/height/depth, subdivisions |
| Plane | Width/height, subdivisions X/Y |
| Cylinder | Radius, height, sides, end caps |
| Sphere (UV) | Radius, latitude/longitude segments |
| Cone | Radius, height, sides |
| Torus | Outer/inner radius, segments |
| Staircase | Step count, rise/run, width |
| Arch | Angle, radius, thickness, sides |
| Shape toolbar | One-click insert at world origin with configurable defaults |

---

## Stage 2 — Element Selection & Transform (`v0.3.x`)

Core editing model. Users can switch between modes and move geometry.

| Item | Description |
|---|---|
| Selection modes | Object / Vertex / Edge / Face — toggle via toolbar or keyboard (`1`/`2`/`3`/`4`) |
| Viewport gizmos | Per-mode 3D handles rendered via `EditorNode3DGizmoPlugin` |
| Multi-select | Box select, Shift+click additive, Ctrl+click toggle |
| Move handle | Translate selected elements; mesh rebuilt on mouse-up |
| Rotate handle | Rotate around selection pivot |
| Scale handle | Scale around selection pivot |
| Grid snap | Configurable snap increment; `Ctrl` modifier to toggle |
| Vertex snap | Drag-to-snap to nearest vertex (`V` modifier) |

---

## Stage 3 — Core Modelling Operations (`v0.4.x`)

The operations designers use every session.

| Item | Description |
|---|---|
| Extrude face(s) | Extrude selected faces along their normal; creates new side geometry |
| Inset face(s) | Inset selected faces inward; uniform or per-face |
| Bevel edge(s) | Subdivide and offset selected edges by a configurable amount |
| Loop cut | Insert an edge loop along a ring of quads |
| Delete | Remove vertices, edges, or faces; optionally fill hole |
| Fill / Bridge | Bridge two open edge loops with a new face strip |
| Weld / Merge vertices | Merge vertices within a threshold or by explicit selection |
| Flip normals | Reverse winding order of selected faces |
| Subdivide | Subdivide selected faces into quads |

---

## Stage 4 — UV Editing & Materials (`v0.5.x`)

Enough UV control to produce lightmap-ready, textured geometry.

| Item | Description |
|---|---|
| Auto UV — Planar | Project UVs along the dominant axis of each face |
| Auto UV — Box | Six-axis box projection; best for cubes and blocky geometry |
| Auto UV — Cylindrical | Cylindrical wrap for pillars, pipes |
| Auto UV — Spherical | Spherical projection |
| UV panel | 2D UV editor panel showing the UV layout; drag, rotate, scale islands |
| Lightmap UV channel | Generate a second non-overlapping UV channel (UV2) for lightmapping |
| Per-face material | Right-click → Assign Material; each face stores a material index |
| Material palette | Sidebar panel showing all material slots on the active mesh |

---

## Stage 5 — Surface Detail (`v0.6.x`)

Normal quality and vertex data.

| Item | Description |
|---|---|
| Smooth groups | Assign faces to smooth groups; normals averaged within group |
| Hard/soft edge toggle | Mark individual edges as hard (split normals) or soft (averaged) |
| Vertex color paint | Paint per-vertex RGBA directly in the viewport with a brush |
| Normal visualiser | Optional overlay showing face/vertex normals as lines |

---

## Stage 6 — Boolean & Advanced Operations (`v0.7.x`)

Power tools for complex geometry.

| Item | Description |
|---|---|
| Boolean Union | Merge two GoBuild meshes into one; remove internal faces |
| Boolean Subtract | Subtract one mesh from another |
| Boolean Intersect | Keep only the overlapping volume |
| Mirror tool | Mirror selected geometry or the whole mesh across X/Y/Z |
| Array / duplicate | Duplicate mesh along a path or with a fixed offset/count |
| Surface snap | Snap vertices/objects to the surface of other meshes |
| Pivot tool | Reposition the mesh origin to selection centre / bounding box |

---

## Stage 7 — Export & Integration (`v0.8.x`)

Get geometry out and into the pipeline.

| Item | Description |
|---|---|
| OBJ export | Export selected mesh as `.obj` + `.mtl` |
| GLB export | Export as `.glb` (binary GLTF 2.0) |
| Collision generation | Auto-generate `ConvexPolygonShape3D` or `ConcavePolygonShape3D` as a sibling node |
| LOD generation | Generate simplified LOD meshes at configurable ratios |
| Batch export | Export all GoBuild meshes in a scene in one operation |

---

## Stage 8 — Polish & UX (`v0.9.x`)

Making everything feel finished.

| Item | Description |
|---|---|
| Keyboard shortcut map | Full configurable shortcut system; Blender-compatible defaults |
| Contextual tooltips | Operation hints displayed in the viewport status bar |
| Quick-action menu | Right-click context menu for common operations on selection |
| Preferences panel | Plugin preferences: snap defaults, display settings, shortcut overrides |
| In-editor documentation | `?` panel linking to online docs |
| Theme support | Respects Godot editor dark/light theme |

---

## Stage 9 — v1.0 Release

- All Stage 0–8 items complete and tested.
- Asset Library submission approved.
- Online documentation live.
- Patreon public launch.
- Demo project published.

---

## Future / Post-v1.0 (`v1.x+`)

| Idea | Notes |
|---|---|
| PolyBrush-style sculpt | Mesh sculpting with radius-based deformation |
| Shape draw tool | Draw a 2D shape on a surface; extrude into 3D |
| Parametric shapes | Re-editable primitives that retain their parameter history |
| Godot 4 terrain integration | Heightmap sculpting layer |
| SpriteMesh | Generate geometry from a 2D sprite outline |
| Prefab variant support | GoBuild mesh saved as a `.tres` resource for reuse |

