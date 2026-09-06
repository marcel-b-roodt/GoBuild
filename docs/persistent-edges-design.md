# Design — Persistent Edge Topology Migration

Status: **Complete (Phases A + B + C).**
Source: knife-tool lessons; user direction ("target the architectural change").

## Why

Every structural bug the knife shipped traced to one root: our edges are
*derived data* — rebuilt lists that go stale the instant a face mutates.
BMesh (Blender) never has this class of bug because edges are first-class
objects that own their face references; mutations update them incrementally
and the structure makes inconsistency unrepresentable.

## Current model

- `GoBuildFace` — vertex ring + UVs + per-face attrs. Unchanged by this plan.
- `GoBuildEdge` — derived view: `vertex_a/b`, `face_indices`, `is_hard`.
  Recreated wholesale by `rebuild_edges()`; ops treat edges as read-only.
- Adjacency caches (`_edge_lookup`, `_face_to_edges`, `_vertex_to_edges`)
  rebuilt with it.
- 278 `.edges` references across 25 addon files + tests.

## Target model

`GoBuildEdge` becomes **persistent state**:

| Field | Before | After |
|---|---|---|
| `vertex_a/b` | derived | owned (edge object created by mutation) |
| `face_indices` | derived | **authority** — maintained on every face mutation |
| `is_hard` | derived from `hard_edge_pairs` | owned by the edge; `hard_edge_pairs` kept as the serialized backup |

Key invariant: **every face mutation must go through edge-maintenance
helpers** (insert-into-ring / remove-from-ring / split-edge / splice-ring),
which update edge objects in the same breath. `rebuild_edges()` survives as
a *full rebuild used only for load, undo/redo restore, and validation* —
it stops being the mechanism by which ops update topology.

## Public API compatibility

- `mesh.edges: Array[GoBuildEdge]` — unchanged; consumers reading
  `vertex_a/b`, `face_indices`, `is_hard` untouched.
- `find_edge`, `faces_of_edge`, `edges_of_face`, `faces_of_vertex` — same
  signatures, now served by persistent state (O(1) without rebuild).
- `rebuild_edges()` — same name, becomes refresh/assert; existing op code
  calling it keeps working.
- Serialization: `hard_edge_pairs` format unchanged → **existing scenes
  load as-is**. No `project.godot` or addon-data migration needed.
- Tests: they assert on `.edges` contents, which remains. Nearly zero churn.

## Migration plan (phased, each phase shippable)

1. **Phase A — persistence core.** ✅ `GoBuildEdge` gains ownership semantics;
   `rebuild_edges` refactored into the load/restore path; mutation helpers
   added to `GoBuildMesh`: `edge_key`, `register_face`, `unregister_face`,
   `split_edge` (ring insertion + hard-pair split), `replace_vertex_in_rings`,
   `delete_faces`, `compact_edges`, `refresh_edge_face_indices`.
   Ops still call `rebuild_edges()` — behaviour identical.
2. **Phase B — incremental ops.** ✅ Knife fully converted (phase-2 uses
   `split_edge`; `_emit_ngon` unregisters/registers per face; ends with
   `compact_edges` + `refresh_edge_face_indices` — zero rebuilds). Delete op
   routes through `mesh.delete_faces`. Debug-only `validate_edge_topology()`
   assert: persistent edges ≡ ring-derived after ops — drift fails loudly
   with the offending edge key. Remaining ops keep `rebuild_edges()`
   (correct today, migrate incrementally with the assert as safety net).
3. **Phase C — cleanup.** ✅ `refresh_edge_face_indices` also rebuilds
   `_vertex_to_faces` and `_vertex_to_edges` (index-shift-safe);
   `compact_edges` simplified to orphan-drop + lookup remap (no O(n)
   `faces.find`); `find_edge` unified onto `edge_key`;
   `sync_edge_hard_state()` added so `hard_edge_pairs` remains the
   serialization authority while `GoBuildEdge.is_hard` is the runtime view.

## Risk register

- **Drift bugs** (op mutates faces without helpers): mitigated by the debug
  assert in Phase B — it turns silent corruption into an immediate, located
  error.
- **Undo/redo snapshots**: snapshot already captures vertices/faces/hard
  pairs; edges rebuild from faces on restore — unchanged semantics.
- **Performance**: incremental maintenance is *cheaper* than full rebuilds
  per op; 16 ms budget unaffected.
- **Scene compat**: none — file format untouched.

## Effort estimate

Phase A ≈ 1 session (core + helpers + tests). Phase B ≈ 1 session per 3–4
ops with tests. Phase C ≈ half a session. Total ~3–4 focused sessions,
each independently shippable with the suite green.

## Open questions

- Keep `hard_edge_pairs` as serialized authority (safer) or move to
  per-edge serialization in `GoBuildMesh._get_property_list`? (Lean: keep —
  zero-format-change guarantee.)
- Do we ever need edge-level UVs/custom channels? (BMesh keeps them per
  loop; we don't today — no action.)