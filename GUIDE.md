# GoBuild — How-To Guide

> Everything you need to start building geometry inside Godot with GoBuild.

---

## Table of Contents

1. [The big idea](#the-big-idea)
2. [Installation](#installation)
3. [The GoBuild Panel](#the-gobuild-panel)
4. [Creating a shape](#creating-a-shape)
5. [Edit modes](#edit-modes)
6. [Selecting elements](#selecting-elements)
7. [Moving selected elements](#moving-selected-elements)
8. [Rotating selected elements](#rotating-selected-elements)
9. [Undo and Redo](#undo-and-redo)
10. [Keyboard shortcuts](#keyboard-shortcuts)
11. [Shape reference](#shape-reference)

---

## The big idea

Think of your mesh like a solid block of clay.

- **Faces** are the flat surfaces on the outside.
- **Edges** are where two faces meet — the lines between them.
- **Vertices** are the corners where edges meet.

GoBuild lets you grab any of these pieces — one at a time, or many at once — and move or rotate them to reshape your geometry directly in the Godot editor.

---

## Installation

1. Copy the `addons/go_build/` folder into your project's `addons/` folder.
2. Open **Project → Project Settings → Plugins**.
3. Find **GoBuild** and set it to **Enabled**.
4. A **GoBuild** panel appears in the bottom-left dock.

---

## The GoBuild Panel

The GoBuild panel lives in your dock (usually bottom-left). It has three sections:

| Section | What it does |
|---|---|
| **Edit Mode** | Four buttons that control what you're editing — the whole object, vertices, edges, or faces. |
| **Create Shape** | One-click buttons to drop a new shape into your scene. |
| **Status / Stats** | Shows the name and vertex/face/edge count of the currently selected mesh. |

If the panel says *"No mesh selected."*, you haven't clicked a GoBuildMeshInstance in the scene tree yet.

---

## Creating a shape

1. Make sure you have a scene open (File → New Scene, or an existing one).
2. In the GoBuild panel, find the **Create Shape** section.
3. Click any shape button — **Cube**, **Plane**, **Sphere**, etc.
4. A new `GoBuildMeshInstance` node appears at the origin of your scene, already selected.

That's it. You now have a mesh you can edit.

> **Tip:** Every shape creation is undoable with **Ctrl+Z**.

---

## Edit modes

GoBuild has four modes. You switch between them using the buttons in the panel or the keyboard shortcuts **1 / 2 / 3 / 4**.

| Key | Mode | What you can select |
|---|---|---|
| **1** | Object | The mesh as a whole (Godot handles this — gizmos are hidden). |
| **2** | Vertex | Individual corner points. |
| **3** | Edge | Lines between corners. |
| **4** | Face | Flat surfaces. |

**How to use them:**

1. Click your `GoBuildMeshInstance` in the scene tree to select it.
2. Press **2**, **3**, or **4** to enter a sub-element mode.
3. The 3D viewport now shows coloured dots (vertices), lines (edges), or teal dots at face centres — these are the elements you can interact with.
4. Press **1** to go back to Object mode and hand control back to Godot's normal transform gizmo.

> **Tip:** If you press 2/3/4 but nothing appears in the viewport, make sure you actually have a `GoBuildMeshInstance` selected in the scene tree first.

> **Linux / NumLock tip:** If your 1–4 keys are also triggering Godot camera views (ortho front/top etc.), your system may be reporting regular number keys as numpad events. The fix is to rebind the mode shortcuts to keys that don't conflict — see the **Rebinding mode keys** section below.

---

## Selecting elements

Once you're in Vertex, Edge, or Face mode, click anything in the 3D viewport to select it. Selected elements turn **orange**.

| Action | How to do it |
|---|---|
| **Select one** | Left-click on a vertex / edge / face. |
| **Add to selection** | Hold **Shift** and left-click. |
| **Toggle in/out** | Hold **Ctrl** and left-click. |
| **Clear selection** | Left-click on empty space (no modifier). |
| **Box select** | Left-click and **drag** to draw a selection rectangle. Release to select everything inside it. |
| **Box select additive** | Hold **Shift** while dragging. |
| **Box select toggle** | Hold **Ctrl** while dragging. |

**Box select in detail:**

1. Hold the left mouse button and drag — a blue rectangle appears.
2. Keep dragging until it covers the elements you want.
3. Release — everything inside the rectangle is selected.

> **Edges:** an edge is included if either of its two endpoints falls inside the box.
> **Faces:** a face is included if its centre point falls inside the box.

---

## Moving selected elements

When at least one element is selected, three **coloured arrow handles** appear at the selection's centre:

| Handle colour | Axis |
|---|---|
| 🔴 Red arrow | X (left / right) |
| 🟢 Green arrow | Y (up / down) |
| 🔵 Blue arrow | Z (forward / back) |

**To move:**

1. Select one or more vertices, edges, or faces.
2. Click and drag the **tip** of the arrow for the axis you want.
3. Move your mouse — the selected elements follow along that axis.
4. Release to confirm. The mesh is updated and the action is added to the undo history.
5. Press **Ctrl+Z** to undo if needed.

> The move is always constrained to a single axis. To move freely on all axes, you currently need to drag each axis separately.

---

## Rotating selected elements

Alongside the move arrows, three **coloured rings** appear around the selection centre:

| Ring colour | Rotation axis | Ring plane |
|---|---|---|
| 🔴 Red ring | X | Rotates in the YZ plane |
| 🟢 Green ring | Y | Rotates in the XZ plane |
| 🔵 Blue ring | Z | Rotates in the XY plane |

**To rotate:**

1. Select one or more vertices, edges, or faces.
2. Click and drag the **dot** on a ring (the handle point on the ring's edge).
3. Move your mouse — the selected elements rotate around the selection centre along that axis.
4. Release to confirm. Undo works here too.

> Rotation always happens around the **centroid** (average centre point) of the selected elements, in local mesh space.

---

## Undo and Redo

All GoBuild operations are fully undoable through Godot's standard undo stack.

| Action | Shortcut |
|---|---|
| Undo | **Ctrl+Z** |
| Redo | **Ctrl+Shift+Z** |

This includes: inserting shapes, moving elements, and rotating elements.

---

## Keyboard shortcuts

| Key | Action |
|---|---|
| **1** | Switch to Object mode |
| **2** | Switch to Vertex mode |
| **3** | Switch to Edge mode |
| **4** | Switch to Face mode |
| **Shift + click** | Add element to selection |
| **Ctrl + click** | Toggle element in/out of selection |
| **Left-drag** | Box select |
| **Ctrl+Z** | Undo |
| **Ctrl+Shift+Z** | Redo |

### Rebinding mode keys

The 1/2/3/4 shortcuts are stored in the Godot Editor Settings and can be changed at any time:

1. Open **Editor → Editor Settings**.
2. In the search box type **gobuild**.
3. You will see four entries under **gobuild → shortcuts** — one for each mode.
4. Click the shortcut entry and press your preferred key.

> **Linux / NumLock note:** If pressing 1–4 on your keyboard also triggers Godot's camera ortho views, your system may be mapping regular number keys to numpad keycodes. The fix is to rebind the GoBuild shortcuts to any key that doesn't conflict — a letter key like `Q/W/E/R` works well.

---

## Shape reference

All shapes are inserted at the world origin and can be repositioned with Godot's normal move tool (Object mode) or by editing sub-elements (Vertex/Edge/Face modes).

| Shape | Description |
|---|---|
| **Cube** | A standard six-faced box. Good starting point for most solid objects. |
| **Plane** | A flat horizontal surface. Useful for floors, platforms, and terrain patches. |
| **Cylinder** | A round tube with optional end caps. Great for pillars, pipes, and barrels. |
| **Sphere** | A UV sphere. Good for round objects and organic starting shapes. |
| **Cone** | A cylinder that tapers to a point. Useful for spires, rooftops, and spikes. |
| **Torus** | A donut shape. Useful for rings, tyres, and looping tracks. |
| **Staircase** | A multi-step staircase solid with a configurable number of steps. |
| **Arch** | A curved arch with configurable outer radius, thickness, and segment count. |

---

## What's coming

GoBuild is in active development. Planned features include:

- Scale handle
- Extrude, bevel, loop cut, and other mesh operations
- UV editing and material assignment
- Boolean operations and mirror tool
- OBJ / GLB export

Follow the project on GitHub for updates.





