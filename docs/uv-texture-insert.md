# UV Texture Insert — Design Document

> **Status:** 📋 Planned
> **Stage:** 4 — UV Editing & Materials
> **NearTermTodo reference:** "insert a texture in the UV editor's page" (line 169)

---

## Problem

Assigning a texture to specific faces (a door, a window, a brick wall) requires the user to mentally map UV coordinates to pixel regions without visual feedback. The current UV editor shows only one background texture (from material slot 0) or a checkerboard. There is no way to:

1. Load a texture directly from within the UV editor.
2. See which texture applies to which faces.
3. Focus on the faces that matter without visual clutter from unrelated geometry.

---

## Design Principles

- **Material-driven, not texture-driven.** Textures live on `StandardMaterial3D` resources as `albedo_texture`. We assign *materials* to *faces*, not raw textures to UV islands. This stays consistent with Godot's material system and GoBuild's existing `material_index`/`material_slots` model.
- **Minimal noise.** When editing UVs, the user should see only what is relevant. Unselected faces, unrelated materials, and background geometry should fade or disappear.
- **Blender parity where natural.** Borrow the visibility dropdown concept from Blender's UV editor, but keep GoBuild's material-first workflow rather than introducing a separate texture-only concept.

---

## Features

### 1. Texture visibility dropdown

Replace the current BG cycle button ("BG:Checker" → "BG:Texture" → "BG:Off") with a proper dropdown or option button that shows all available textures plus the built-in modes.

**Options in the dropdown:**

| Option | Behaviour |
|---|---|
| Checker | Current checkerboard background (default) |
| Off | Dark tile background, no texture |
| *Material name + thumbnail* | Show that material's `albedo_texture` as the background |

The dropdown is populated dynamically from `GoBuildMesh.material_slots`. Each material with an `albedo_texture` appears as a named entry with a small swatch. Selecting it shows that texture behind the entire UV tile.

When the user selects faces in the 3D viewport or UV canvas, the dropdown auto-switches to the texture of the **first selected face's material** (if it has one). If the selected faces use different materials with different textures, the dropdown does **not** auto-switch (stays on whatever it was), avoiding flicker.

The user can override the auto-selection at any time by manually choosing from the dropdown. Manual selection persists until the next face selection change that would trigger an auto-switch.

### 2. Add Tex button

A button in the UV panel toolbar ("Add Tex" or a texture icon) that:

1. Opens an `EditorFileDialog` filtered to image files (`.png`, `.jpg`, `.svg`, `.webp`).
2. On file selection:
   - Checks whether an existing material in `material_slots` already uses this texture (by comparing `albedo_texture.resource_path`).
   - If a match is found, assigns that material's slot to the selected faces via `MaterialAssignOperation.apply_to_selected_faces()`.
   - If no match, creates a new `StandardMaterial3D` with the chosen texture as `albedo_texture`, appends it to `material_slots`, and assigns the new slot to the selected faces.
3. Triggers full undo/redo as a single action ("Add Texture to Faces").
4. After assignment, the UV canvas switches to show the newly assigned texture in the background, and the visibility dropdown updates to include the new material.

This gives a one-click workflow: select faces → pick an image → done.

### 3. Drag-and-drop material/texture assignment

The user can drag a material or texture from the Godot FileSystem dock onto the UV canvas. On drop:

- If the dropped resource is a `Texture2D`, search `material_slots` for an existing `StandardMaterial3D` with that `albedo_texture`. If found, assign that material to selected faces. If not found, create a new material and assign it (same logic as Add Tex button).
- If the dropped resource is a `Material`, assign it directly to the selected faces via the existing material assignment flow.
- If no faces are selected, prompt the user ("Select faces first" hint or no-op).

**Deduplication of materials:** When a texture is already in use by a material in the mesh's `material_slots`, we reuse that material rather than creating a duplicate. This prevents slot bloat when the same texture is assigned to multiple face groups over time.

### 4. Face isolation — show only selected faces

A toggle button in the UV panel toolbar (e.g. an eye icon or "Isolate" label) that, when active:

- **Hides unselected faces entirely** instead of drawing them as dim wireframe.
- Only the selected faces' UV polygons are drawn, with their fill and wireframe.
- When no faces are selected, isolation mode shows nothing (but the texture/dropdown background remains visible).

This eliminates visual noise when positioning a small number of UV islands against a texture. The toggle is independent of the visibility dropdown.

**Behaviour on mode switch / selection change:**
- Isolation stays active across selection changes. When the user selects new faces, only those appear.
- Pressing Escape or clicking the button again exits isolation mode, revealing all faces.

### 5. Workflow improvements — settings panel

A collapsible settings drawer in the UV panel (or a gear icon that opens a popup) that consolidates per-session preferences:

| Setting | Type | Default | Notes |
|---|---|---|---|
| Isolate selected faces | Toggle | Off | Same as the toolbar toggle |
| Auto-switch texture | Toggle | On | Whether the visibility dropdown auto-switches on face selection |
| Dim unselected faces | Slider (0–1) | 0.3 | Alpha of unselected face wireframes in non-isolation mode |
| Snap UV to pixels | Toggle | Off | Snap UV vertices to nearest pixel when editing (based on texture size) |
| Grid subdivision | SpinBox | 8 | Number of grid lines per UV unit |

This keeps the toolbar clean while giving power users access to fine-tuning. The "Isolate selected faces" toggle here duplicates the toolbar toggle for discoverability.

**Smooth group assignment from the UV editor** is a valid future improvement but is scoped out of this design. The UV editor already syncs face selection with the 3D viewport, so the user can assign smooth groups from the main panel while the UV editor is open. Adding a secondary smooth-group UI inside the UV panel would add complexity without a clear workflow benefit until we have per-face property editing in the UV editor more broadly.

---

## Data Model Changes

No changes to `GoBuildFace` or `GoBuildMesh`. The texture-material relationship already exists:

```
face.material_index → GoBuildMesh.material_slots[i] → StandardMaterial3D.albedo_texture
```

The new features are entirely in the **UV canvas rendering** and **UV panel UI**.

## Rendering Changes

### `_draw_grid()` — texture from visibility dropdown

Currently reads `material_slots[0]` unconditionally. Changed to read the material selected in the visibility dropdown.

### `_draw_faces()` — isolation mode

Currently draws all faces in two passes (unselected wireframe, then selected fill+wire). Add a flag `_isolate_selected: bool`:

- When `true`, skip Pass 1 entirely. Only draw selected faces.
- When `false`, draw both passes but use a configurable `_dim_alpha` for unselected face wireframe instead of the hardcoded `_FACE_WIRE_COLOR`.

### Visibility dropdown population

On every `selection_changed` signal or `mesh_changed` signal, rebuild the dropdown options from `material_slots`. Each entry shows:
- Material name (or "Slot N" if unnamed)
- Small swatch (the same preview logic already used in `go_build_materials_drawer.gd`)

---

## UI Layout

```
┌─ UV View ──────────────────────────────┐
│ [Face|Vert] [Move][Rot][Scale] [▽ BG] │  ← BG dropdown replaces cycle button
│ [Pack] [Stitch] [Add Tex] [👁 Iso]   │  ← new toolbar row
│ Repeat: [1]                            │
│ ┌─────────────────────────────────────┐│
│ │                                     ││
│ │         UV Canvas                   ││
│ │   (shows texture from dropdown,     ││
│ │    isolates selected faces if on)   ││
│ │                                     ││
│ └─────────────────────────────────────┘│
│ [⚙ Settings]                           │  ← collapsible settings drawer
└────────────────────────────────────────┘
```

**New controls:**
- **▽ BG dropdown:** replaces the old "BG:Checker" cycle button. Options: Checker, Off, and one entry per material with a texture.
- **Add Tex button:** opens file dialog, creates/assigns material.
- **👁 Iso button:** toggles "show only selected faces" mode.
- **⚙ Settings:** collapsible drawer with fine-tuning options.

---

## Drag-and-Drop Implementation

The UV canvas (`GoBuildUvCanvas`) processes `can_drop_data` / `drop_data`:

1. `can_drop_data(position, data)` — check if the dropped data contains a `Texture2D` or `Material` resource. Return `true` only if faces are selected.
2. `drop_data(position, data)` — extract the resource, run the assign-or-create logic, wrap in undo/redo.
3. Visual feedback: on `can_drop_data == true`, highlight the canvas border to indicate a valid drop target.

---

## Blender Comparison

| Feature | Blender UV Editor | GoBuild (planned) |
|---|---|---|
| Texture background | Shown per-object from active material's image | Dropdown to choose any material's texture; auto-switches on selection |
| Assign texture to faces | Assign material in Properties → reflects in UV editor | Add Tex button, or drag from FileSystem |
| Isolate faces | Not built-in; users hide mesh parts in 3D viewport | Isolate toggle in UV toolbar |
| Multiple materials on one mesh | Each face uses its assigned material's image | Same; dropdown shows all material textures |
| UV snapping to pixels | Pixel snap toggle | Planned in settings drawer |
| Face selection sync | Synced with 3D viewport | Already implemented in GoBuild |

GoBuild's approach differs from Blender by making **material assignment accessible directly in the UV editor** (Add Tex button, drag-and-drop), rather than requiring the user to go to a separate Properties panel. This keeps the UV editing workflow self-contained.

---

## Implementation Slices

These are ordered for independent, testable delivery:

### Slice 1: Visibility dropdown (replaces BG cycle button)
- Replace `UvBgMode` with an `OptionButton` populated from `material_slots`.
- Auto-switch on face selection (when all selected faces share a material with a texture).
- Manual override persists until next auto-trigger.
- Files: `go_build_uv_panel.gd`, `go_build_uv_canvas.gd`

### Slice 2: Face isolation toggle
- Add `_isolate_selected` bool to canvas.
- Skip unselected face pass when active.
- Toolbar toggle button.
- Files: `go_build_uv_canvas.gd`, `go_build_uv_panel.gd`

### Slice 3: Add Tex button
- `EditorFileDialog` for image files.
- Material deduplication logic: search existing slots for matching `albedo_texture.resource_path`.
- Create-or-assign via `MaterialAssignOperation`.
- Undo/redo wrapper.
- Files: `go_build_uv_panel.gd`, new helper or inline in panel.

### Slice 4: Drag-and-drop material/texture
- `can_drop_data` / `drop_data` on canvas.
- Same deduplication logic as Add Tex.
- Files: `go_build_uv_canvas.gd`

### Slice 5: Settings drawer
- Collapsible `GoBuildDrawer` under UV panel.
- Dim alpha slider, auto-switch toggle, pixel snap toggle (prep only, no snap logic yet), grid subdivision.
- Files: new `go_build_uv_settings_drawer.gd`, `go_build_uv_panel.gd`.

### Slice 6: Dim unselected faces (configurable alpha)
- Replace hardcoded `_FACE_WIRE_COLOR` alpha with `_dim_alpha` setting.
- Interpolated between 0 and 1 based on settings slider.
- Files: `go_build_uv_canvas.gd`.

---

## Open Questions

1. **Should the visibility dropdown auto-switch be a toggle or always-on?** Current plan: always-on with a settings toggle to disable it. Open to testing feedback.
2. **Should drag-and-drop also support dropping from the materials palette in the main panel?** Yes, if practical. The `can_drop_data` handler accepts any `Material` or `Texture2D` resource.
3. **Should Add Tex work in Object mode (apply to all faces)?** Yes, following the existing pattern where material operations in Object mode target all faces. The button should be disabled if no target mesh is active.
4. **Should we support `ORMMaterial3D` or shader materials for texture display?** Not in this iteration. `StandardMaterial3D` covers the common case. We can inspect `next_pass` and shader uniforms later if needed.