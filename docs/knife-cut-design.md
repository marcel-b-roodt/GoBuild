# Design — Knife Cut

Status: **IMPLEMENTED (in progress) — see Knife cut row in docs/feature-registry.md.**
This document predates the implementation; the registry row is authoritative.
Source: HighLevelTodos "Add knife cut. Arbitrarily cut any polygon out of an object,
such as a custom extrude. Allow snapping onto edges or vertices."

## What the user does

1. Pick **Knife** (Face mode toolbar button or `K` while a GoBuild object is edited).
2. Click a sequence of points on the mesh surface — each click raycasts to the
   nearest face; a marker + preview polyline is drawn like the existing polygon
   draw tool.
3. Snap assistance while hovering (before click):
   - **Vertex snap** — if a mesh vertex projects within ~12 px of the cursor,
     the point becomes that vertex exactly (`V` holds the behaviour, or default-on
     with Ctrl toggling, matching the V-modifier convention — final binding at build time).
   - **Edge snap** — same idea against edge *segments* (screen-space distance to
     the projected segment, clamped to it); no edge snapping exists today.
   - Raw-surface hit is the fallback.
4. Close the loop by clicking the first point (or Enter), or cancel (Esc / right-click).
5. On confirm, the cut runs as one undoable operation.

## Geometry algorithm

The knife path is a polyline of surface points. Processing is per-face:

1. **Collect cut points per face.** From the click sequence, each consecutive
   pair (A, B) is a segment on the surface. A segment generally crosses several
   faces; each crossing contributes an entry segment to that face. Segments are
   resolved face-by-face by walking the picked points' own faces first, then
   propagating across shared edges (segment vs edge intersection in the shared
   plane) — the same ring-walk spirit as `LoopCutOperation`.
2. **Split each affected face by its entry/exit segments.** New vertices are
   created at every segment–edge crossing via `append_vertex_lerp` (shared
   across adjacent faces with a canonical edge key, loop-cut pattern). Faces
   are then re-tessellated by ear-clipping (`Triangulate.ear_clip` — already
   mesh-ready because PolygonGenerator uses it for exactly this
   "fan-only-is-wrong" reason).
3. **Topology bookkeeping:** original face replaced in place
   (`mesh.faces[fi] = ...` + appends), material/smooth/UV data copied,
   `rebuild_edges()` once at the end, undo via snapshot — the canonical op
   pattern.

Cut edges become real shared edges (coincident groups keep drag behaviour
working). The cut polyline itself is not geometry until the user extrudes the
new face(s) — which is the "custom extrude" payoff.

## What gets built

| Piece | Location |
|---|---|
| Pure cutting math (segment/edge intersection in face plane, face re-tessellation) | `mesh/knife.gd` (pure, unit-testable) |
| Split application as a proper op | `mesh/operations/knife_cut_operation.gd` |
| Input FSM (point collection, hover snap, markers, preview) | `core/go_build_knife_controller.gd` + plugin.gd routing |
| Snapping helpers | extend PickingHelper usage (`find_nearest_vertex`, `find_nearest_edge`) |

## Under live symmetry (interacts with #5)

The knife is a structural op, so it materializes: a cut on the +X side of a
symmetric object automatically re-runs on the twin face. Cut + custom extrude
under symmetry therefore produces symmetric extrudes. The controller must pass
the *partner face's* world-space mirror of the cut points to keep the two cuts
aligned — handled by running the same op on the partner face set.

## Explicit non-goals (v1)

- No cutting across multiple separate objects (per-object like symmetry).
- No plane-cut (loop cut already covers straight cuts).
- No live re-drag of the cut path after confirm (re-cut with undo instead).
- Polygon-draw / shape creation flows unchanged.

## Risks

- Segment propagation across curved/high-poly surfaces (T-junction handling) —
  mitigated by requiring clicks ON a face (no free-space points) and limiting
  v1 to convex-face meshes.
- UV mapping of split faces is approximated (fan from position interpolation) —
  acceptable for blockout.

**Approval gate: implement only after sign-off.**