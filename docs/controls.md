# GoBuild — Control Scheme

Design reference for every keyboard shortcut, mouse modifier, and UX interaction in GoBuild.
This document covers **implemented** controls and **planned** controls so the full scheme can be
evaluated as a whole before implementation.

Status legend: ✅ Implemented · 📋 Planned

---

## Design Philosophy

| Principle | Decision |
|---|---|
| **Modifier + drag = operation** | The primary way to trigger mesh operations is to hold a modifier and drag in the viewport. No need to click a panel button first. |
| **QWER = gizmo tool** | Matches Godot's own 3D editor and Unity/ProBuilder muscle-memory. |
| **1234 = edit mode** | Consistent, fast mode switching without leaving the home row. |
| **Blender-inspired operation keys** | Where a Blender shortcut doesn't conflict with QWER/1234, prefer it. |
| **Panel buttons = discoverability** | Panel operations are always available for users who haven't memorised shortcuts. |
| **Right-click = context menu** | Common operations surfaced at the cursor without hunting for panel buttons. |
| **Modifier toolbar feedback** | The panel/overlay updates in real-time to show what the held modifier will do — teaching the shortcut while you use it. |

---

## Edit Mode Selection

Always available whenever a `GoBuildMeshInstance` is selected.

| Key | Mode | Status |
|---|---|---|
| `1` | Object mode | ✅ |
| `2` | Vertex mode | ✅ |
| `3` | Edge mode | ✅ |
| `4` | Face mode | ✅ |

---

## Gizmo / Transform Tool

Switches the active gizmo drawn on the selected mesh. These follow Godot's own editor convention.

| Key | Gizmo | Status |
|---|---|---|
| `W` | Translate (Move) | ✅ |
| `E` | Rotate | ✅ |
| `R` | Scale | ✅ |

> **Note:** `Q` is Godot's built-in "select" gizmo suppressor. GoBuild relies on this — we set
> the gizmo tool to SELECT to hide Godot's default Move/Rotate/Scale handles and draw our own.

---

## Selection

| Input | Effect | Status |
|---|---|---|
| Left-click (on element) | Select single element | ✅ |
| `Shift` + Left-click | Additive select | ✅ |
| `Ctrl` + Left-click | Toggle element in/out of selection | ✅ |
| Left-drag (empty space) | Box / rubber-band select | ✅ |
| `Ctrl+A` | Select all elements in current mode | 📋 |
| `Escape` | Deselect all | 📋 |
| `Alt` + Left-click (edge) | Edge-loop select | 📋 |
| `Alt` + Left-click (face) | Face-loop select (connected coplanar ring) | 📋 |
| `Ctrl` + Left-click (edge) | Shortest-path select | 📋 |

---

## Drag Modifiers

Modifiers change what happens when you drag in the viewport. The gizmo tool (W/E/R) determines
the base operation; the modifier overlays a context-specific action on top.

| Modifier + Drag | Translate (W) | Scale (R) | Rotate (E) |
|---|---|---|---|
| Plain drag on handle | Move selected | Scale selected | Rotate selected |
| `Ctrl` + drag | Grid-snapped move | Grid-snapped scale | — |
| `V` + drag | Vertex-snapped move | — | — |
| `Shift` + drag (Face mode) | **Extrude face** along normal | **Inset face** inward | — |
| `Shift` + drag (Edge mode) | **Extrude edge** → new quad | — | — |
| `Shift+Ctrl` + drag | Extrude / Inset + grid snap | — | — |

Status: plain drag/Ctrl/V on Translate = ✅; all Shift+drag variants = 📋 Planned.

> **Why Scale → Inset?** Inset shrinks a face proportionally inward — this maps naturally onto
> the Scale gesture. Holding `Shift` while scaling signals "operate on this face's boundary"
> rather than the whole selection's bounding box.

> **Alt is reserved for loop/path selection** (edge-loop select, face-loop select, shortest-path
> select). These are planned for a later stage and must not conflict with the drag modifiers above.

> **Shift+drag vs panel button:** Both trigger the same operation. The panel button uses
> the default distance/amount. Shift+drag lets you set it interactively by drag delta, shown
> live in the viewport status overlay.

---

## Keyboard Operation Shortcuts

For fast one-key access to common operations. These fire on the current selection without
needing to click a panel button.

| Key | Context | Action | Status |
|---|---|---|---|
| `Delete` or `X` | Any sub-element mode | Delete selected elements | 📋 |
| `F` | Vertex or Edge mode | Fill — create face from selected verts/edges | 📋 |
| `M` | Vertex mode | Merge vertices (submenu: at center / at cursor / by distance) | 📋 |
| `Ctrl+B` | Edge mode | Bevel selected edges | 📋 |
| `Ctrl+R` | Any | Loop cut — insert edge loop on hovered quad ring | 📋 |
| `Shift+D` | Any sub-element mode | Duplicate selected elements | 📋 |
| `H` | Any sub-element mode | Hide selected | 📋 |
| `Alt+H` | Any sub-element mode | Unhide all | 📋 |
| `N` | Any | Toggle panel visibility (Blender-style side panel) | 📋 |

> **Why no `E` for extrude?** `E` is already claimed by the Rotate gizmo (QWER convention).
> Extrude is triggered by `Shift+drag` (interactive) or the panel button (default distance).
> If a numeric-input extrude workflow is added later (Blender-style: press `E`, type distance,
> Enter), a different key will be chosen to avoid conflicts.

---

## Modifier-Aware Toolbar

The GoBuildPanel and viewport status overlay update in real-time based on held modifier keys.
This teaches shortcuts while you work — you see what the modifier will do before you drag.

### Behaviour

| State | Panel label | Highlighted button | Overlay hint |
|---|---|---|---|
| No modifier, translate tool | "Move" | — | "Drag handle to move" |
| `Shift` held (face, translate) | **"Extrude"** | Extrude button | "Shift+drag to extrude face" |
| `Shift` held (edge, translate) | **"Extrude Edge"** | — | "Shift+drag to extrude edge" |
| `Shift` held (face, scale) | **"Inset"** | Inset button | "Shift+drag to inset face" |
| `Ctrl` held | "Snap" | — | "Ctrl+drag for grid snap" |
| `V` held | "Vertex Snap" | — | "V+drag to snap to vertex" |
| `Alt` held | — | — | *(reserved for loop select — future)* |

### Implementation notes

- `plugin.gd` tracks modifier state in `_forward_3d_gui_input` (key press/release events).
- Emits a `modifier_changed(modifier_flags)` signal.
- `GoBuildPanel` connects to this signal and updates the context label + button highlight state.
- A viewport overlay label (drawn in `_forward_3d_draw_over_viewport`) shows the hint text
  near the cursor.

---

## Right-Click Context Menu

Right-clicking on a selection opens a `PopupMenu` at the cursor with context-sensitive operations.

### Per-mode contents

| Mode | Menu items |
|---|---|
| **Object** | Select All, Deselect All, Reset Transform, Enter Edit Mode |
| **Vertex** | Merge (submenu), Delete, Duplicate, Select Loop, Select All |
| **Edge** | Bevel, Loop Cut, Bridge, Extrude Edge, Delete, Select Loop, Select All |
| **Face** | Extrude, Inset, Flip Normals, Delete, Subdivide, Assign Material, Select All |

### Implementation

```gdscript
# In plugin.gd _forward_3d_gui_input:
if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
        and event.pressed and _editing_node != null:
    _show_context_menu(event.position)
    return EditorPlugin.AFTER_GUI_INPUT_STOP

func _show_context_menu(at: Vector2) -> void:
    var popup := PopupMenu.new()
    EditorInterface.get_base_control().add_child(popup)
    # populate based on mode + selection...
    popup.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
    popup.id_pressed.connect(_on_context_menu_item.bind(popup))
    popup.popup_hide.connect(popup.queue_free)
```

---

## Numeric Input for Operations (Future)

Blender lets you type a number after triggering an operation to set it precisely:
press `G`, type `2.5`, `Enter` → move 2.5 units. This is a Stage 8+ UX refinement.

For GoBuild, a simpler first version would be:
- After `Shift+drag` extrude, show a small input field in the viewport or status bar.
- The user can type an exact distance and press `Enter` to finalize.
- `Escape` reverts to the drag result.

This keeps keyboard+drag fast and still allows precision without a panel popup.

---

## Summary Table — Current Implementation State

| Category | Done | Planned |
|---|---|---|
| Mode switching (1/2/3/4) | ✅ 4/4 | — |
| Gizmo tools (W/E/R) | ✅ 3/3 | — |
| Selection (click, box, Shift, Ctrl) | ✅ | Loop select, Select All, Escape |
| Drag modifiers (Ctrl snap, V snap) | ✅ | Shift+drag extrude, Alt+drag inset |
| Operation keyboard shortcuts | — | Delete, F, M, Ctrl+B, Ctrl+R |
| Modifier-aware toolbar | — | Full implementation |
| Right-click context menu | — | Stage 8 |
| Numeric input for operations | — | Post-Stage 8 |

