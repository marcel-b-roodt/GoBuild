# GoBuild — Project Goal

## North Star

> **Bring first-class in-editor mesh modelling to Godot 4, so developers never need to leave the editor for common geometry tasks.**

GoBuild is a Godot 4 EditorPlugin that delivers the core capabilities of Unity's ProBuilder — directly inside Godot. It targets indie developers, level designers, and solo creators who want to block out levels, prototype geometry, and ship production meshes without exporting to Blender or any other external tool.

---

## What GoBuild Is

- A **non-destructive, real-time mesh editor** embedded in the Godot editor viewport.
- A **shape-creation toolkit** — primitives, custom extrusions, bevels, UV editing, per-face materials.
- A **level design accelerator** — snap to grid, boolean bakes, collision auto-gen, lightmap UV output.
- **Open-source and community-driven** — free to use, transparently developed, Patreon-funded.

## What GoBuild Is Not

- A replacement for a full DCC tool (Blender, Maya). It covers the 80 % of geometry work that happens inside the editor, not the 20 % that needs sculpting or complex rigging.
- A runtime mesh manipulation library. GoBuild targets the Godot **editor** only; it does not ship code into your game build.
- A re-implementation of CSG nodes. GoBuild operates on real, baked `ImporterMesh`/`ArrayMesh` data — what you see is what you export.

---

## Success Criteria (v1.0 parity with ProBuilder core)

| Capability | Target |
|---|---|
| Primitive creation | Cube, Plane, Cylinder, Sphere, Cone, Torus, Staircase, Arch |
| Element selection | Vertex / Edge / Face selection with multi-select |
| Transform operations | Move, Rotate, Scale on element level |
| Core operations | Extrude, Inset, Bevel, Bridge, Loop Cut, Weld/Merge, Delete |
| UV editing | Auto-projection (planar, box, cylindrical) + manual UV panel |
| Materials | Per-face material assignment |
| Smooth groups | Soft/hard normals per face group |
| Export | `.obj` and `.glb` mesh export |
| Snap | Grid snap, vertex snap, surface snap |
| Collision | One-click collision mesh generation |

---

## Guiding Principles

1. **Editor-first.** Every workflow must feel native to Godot. No detached windows, no external processes for core operations.
2. **Non-destructive where possible.** Preserve enough metadata to allow re-editing primitives without starting from scratch.
3. **Performance-aware.** Mesh rebuild and viewport updates must be fast enough to feel instant on mid-range hardware (target: <16 ms rebuild for meshes under 10k faces).
4. **Accessible.** Sensible defaults, contextual hints, and a keyboard-shortcut map that mirrors Blender muscle-memory where natural.
5. **Stable.** Test coverage on all algorithmic code. A broken plugin that corrupts a scene is worse than a missing feature.

