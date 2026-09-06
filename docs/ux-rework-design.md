# Design — Viewport Toolbar Rework

Status: **DESIGN — for review. No implementation.**
Source: user request. Supersedes: drawer-in-sidebar layout. Deferred from the
post-hotspot sprint ("Big UX rework. This one should be done on its own").

## Colour palette (design tokens)

| Token | Swatch | Hex | Usage |
|---|---|---|---|
| Blue (primary) | 🟦 | `#4a9eff` | Object-mode ops, logo, inactive accents |
| Blue bright | 🔵 | `#7cbdf5` | Hover, active outlines |
| Gold (accent) | 🟡 | `#ffc84a` | Face-mode ops, active mode highlight, pin icon |
| Green (accent) | 🟢 | `#72e47e` | Edge-mode ops (hue 126° — halfway between vertex-blue 210° and face-gold 42°; 30% white tint for a softer read) |
| Blue dim | 🔷 | `#4082c5` | Vertex-mode ops |
| Neutral | ⚫ | `#3a3f47` | Settings cog, non-mode chrome |
| Paint (orange) | 🟧 | `#ff8c42` | Paint mode, brush cursor |

Live swatches (render in markdown viewers that support inline HTML):

<span style="display:inline-block;width:60px;height:20px;background:#4a9eff;"></span> Blue `#4a9eff` ·
<span style="display:inline-block;width:60px;height:20px;background:#7cbdf5;"></span> Blue bright `#7cbdf5` ·
<span style="display:inline-block;width:60px;height:20px;background:#ffc84a;"></span> Gold `#ffc84a` ·
<span style="display:inline-block;width:60px;height:20px;background:#72e47e;"></span> Edge green `#72e47e` ·
<span style="display:inline-block;width:60px;height:20px;background:#4082c5;"></span> Blue dim `#4082c5` ·
<span style="display:inline-block;width:60px;height:20px;background:#3a3f47;"></span> Neutral `#3a3f47` ·
<span style="display:inline-block;width:60px;height:20px;background:#ff8c42;"></span> Paint `#ff8c42`

Per-mode colour coding (button tint when active + icon accent):
Object → blue · Vertex → blue-dim · Edge → green · Face → gold · Paint → orange.
Mode buttons show the mode icon in its colour; the **active** mode
adds a gold underline bar. Drawer-menu icons use the mode colour that owns
them (Create/Object = blue, Edit drawers follow their mode colour).

**Paint colour rationale:** orange works as-is — it complements the blue/gold
palette without implying a *hierarchy* (it isn't an edit mode). If you want a
pure colour-theory alternative: **vermilion `#e34234`** is red-orange, sits
triadically against the gold, and reads "cut/active" strongly; but it risks
conflict with Godot's own red error-tint conventions in the editor chrome.
Recommendation: keep `#ff8c42`.

## Problem

- 3 separate docks (GoBuild panel LEFT_UL, UV editor BOTTOM, Vertex painter
  RIGHT_UL) = screen bloat; user asked "toggle all GoBuild windows off without
  disabling the plugin".
- All drawers live in a scrolling sidebar; operations require mouse-to-dock travel.
- No icons anywhere; drawer discovery is by text.

## Goal

**One toolbar row bolted to the spatial-editor menu bar (`CONTAINER_SPATIAL_EDITOR_MENU`),
zero mandatory docks.** Everything reachable from the toolbar; the sidebar becomes
optional (an "old habits" tab still holding the full panel for users who want it).

## Layout proposal

```
[GoBuild logo] | [Object][Vertex][Edge][Face] | [Create ▾] [Edit ▾] [Surface ▾] [UV ▾] [Materials ▾] | [Pin-able popups] | [Paint ⊛] | [? …… ⚙]
```

| Element | Widget | Source |
|---|---|---|
| GoBuild logo | `TextureRect` (SVG → ImageTexture) | new |
| Mode buttons | 4 toggle Buttons w/ icons, radio-synced 1-4, **colour-coded per mode** | exists + icons |
| Drawer menus | MenuButton per drawer group, dropdown = flat Button list | wraps existing drawers |
| Paint toggle | Mode toggle; paint settings in an anchored popup on the button | see Modes |
| Help | "?" → cheatsheet popup | exists |
| ⚙ Settings | **Right-most** anchored popup: Space Local/World, Snap/Rot/Scale steps, Snap Mode, back-faces, X-Ray, Normals, Symmetry, Debug logging | moves out of General drawer |
| Pin | Small 📌 on pinned popups (⚙, paint settings): keeps the panel open while working; clicking the toolbar button again unhooks it | new |

Settings drawer sits **last on the right edge** of the toolbar row.

## Drawer → MenuButton mapping

Each `GoBuildMesh…Drawer` keeps its logic; the toolbar hosts a `MenuButton`+
`PopupMenu` per drawer (like the context menu). `refresh_buttons()` gains a
per-item `set_disabled` path (PopupMenu `set_item_disabled`) — one adapter
method per drawer, ~10 lines each. `go_build_panel.gd` stays as the single
owner of drawers; the toolbar reads the same instances (no logic move, no
state duplication) — the panel dock becomes an optional secondary view.

## Pinning

Anchored popups (⚙ settings, paint settings, optionally drawer menus) get a
small pin toggle in their corner. Pinned = panel stays open, keeps following
its toolbar anchor while the user works in the viewport; un-pinned = closes on
outside click as usual. Pin state persists in settings for the ⚙ panel.

## Modes: Vertex Paint as a viewport mode; UV stays a dock

- Plugin mode enum grows **PAINT** only: `OBJECT / VERTEX / EDGE / FACE /
  PAINT`. Paint is exclusive from edit modes (same behaviour as clicking the
  existing Paint toggle) — clicking PAINT switches the viewport into brush
  mode; the painter dock becomes just an optional secondary panel.
- **UV editor remains a bottom dock, always usable** — it complements edit
  modes rather than competing with them. Rework adds one thing to the dock:
  a **grid background at 0.1 UV increments** (toggleable, drawn in
  `GoBuildUvCanvas` under the face wireframe).

## Icons

- Generated programmatically as SVG strings → `ImageTexture` at startup
  (simple paths, 24px grid, palette: blue `#4a9eff`, gold `#ffc84a`).
- **Colour coding by mode/operation class:** Object = neutral blue,
  Vertex = blue-dim, Edge = green, Face = gold — final per-mode hues
  chosen so active mode buttons are identifiable at a glance (like
  Blender's 3/1/2/4 select keys but chromatic).
- Icons per drawer group + mode + settings cog + paint. ~16 icons total.
- Kept in one script of SVG string constants (`ui_icons.gd`), rendered once
  and cached — no loose files to manage.

### Icon inventory (24px grid, monochrome-glyph + colour accent)

| Name | glyph (concept) | colour | swatch | used by |
|---|---|---|---|---|
| `logo` | stylised "G" | blue+gold | <span style="display:inline-block;width:24px;height:12px;background:linear-gradient(90deg,#4a9eff 50%,#ffc84a 50%);"></span> | toolbar start |
| `mode_object` | cube outline | blue | <span style="display:inline-block;width:24px;height:12px;background:#4a9eff;"></span> | Object mode btn |
| `mode_vertex` | 3 dots + wire triangle | blue-dim | <span style="display:inline-block;width:24px;height:12px;background:#4082c5;"></span> | Vertex mode btn |
| `mode_edge` | cube wireframe w/ highlighted edges | green | <span style="display:inline-block;width:24px;height:12px;background:#72e47e;"></span> | Edge mode btn |
| `mode_face` | shaded quad | gold | <span style="display:inline-block;width:24px;height:12px;background:#ffc84a;"></span> | Face mode btn |
| `mode_paint` | brush stroke | orange | <span style="display:inline-block;width:24px;height:12px;background:#ff8c42;"></span> | Paint mode btn |
| `menu_create` | cube + plus | blue | <span style="display:inline-block;width:24px;height:12px;background:#4a9eff;"></span> | Create ▾ |
| `menu_edit` | pencil-over-cube | gold-dim | <span style="display:inline-block;width:24px;height:12px;background:#c9973a;"></span> | Edit ▾ |
| `menu_surface` | sphere w/ shading arcs | blue | <span style="display:inline-block;width:24px;height:12px;background:#7cbdf5;"></span> | Surface ▾ |
| `menu_uv` | square + inner cross (UV tile) | gold-dim | <span style="display:inline-block;width:24px;height:12px;background:#c9973a;"></span> | UV ▾ |
| `menu_materials` | swatch stack | gold | <span style="display:inline-block;width:24px;height:12px;background:#ffc84a;"></span> | Materials ▾ |
| `cog` | gear | neutral | <span style="display:inline-block;width:24px;height:12px;background:#3a3f47;"></span> | Settings ⚙ |
| `pin` | push-pin | gold pinned / grey idle | <span style="display:inline-block;width:24px;height:12px;background:#ffc84a;"></span> | popup corners |
| `help` | "?" in circle | neutral | <span style="display:inline-block;width:24px;height:12px;background:#3a3f47;"></span> | Help btn |

Rendering: `ImageTexture` per icon via Godot's SVG import at 24px; the script
holds raw SVG strings with the accent colour baked per icon (no runtime tinting).

## Front-end mockups (ASCII)

Toolbar row (in Godot's spatial-editor menu bar):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ [G]  │ ▣ ◉ ⬡ ▣ ⊛ │  Create ▾   Edit ▾   Surface ▾   UV ▾   Materials ▾ │  ? … ⚙ │
│      │  (modes,   │  ← MenuButtons, dropdown lists of drawer buttons →  │        │
│      │  colour-   │                                                     │        │
│      │  coded,    │                                                     │        │
│      │  gold bar  │                                                     │        │
│      │  = active) │                                                     │        │
└──────────────────────────────────────────────────────────────────────────────┘
```

Create ▾ open (PopupMenu, buttons listed mirroring the Create drawer):

```
┌──────────────┐
│ Cube         │
│ Plane        │
│ Cylinder     │
│ Sphere       │
│ Cone         │
│ Torus        │
│ Staircase    │
│ Arch         │
│ Doorway      │
│ Polygon      │
│──────────────│
│ Import Mesh  │
└──────────────┘
```

⚙ Settings popup (right-most, pinnable — 📌 top-right):

```
                    ┌───────────────────────────────┐📌
                    │  GoBuild Settings             │
                    ├───────────────────────────────┤
                    │ Space:      [Local ▾]         │
                    │ Snap:       [0.5  ▾]          │
                    │ Rot Snap:   [15°  ▾]          │
                    │ Scale Snap: [0.1  ▾]          │
                    │ Snap Mode:  [World ▾]         │
                    │ Symmetry:   [Off ▾]           │
                    │───────────────────────────────│
                    │ [x] Show back-faces           │
                    │ [x] X-Ray handles             │
                    │ [ ] Face normals              │
                    │ [ ] Vertex normals            │
                    │ [ ] Debug logging             │
                    └───────────────────────────────┘
```

Paint settings popup (top-right of viewport, anchored under the PAINT button):

```
                                              ┌────────────────────────────┐
 ┌ toolbar ─────────────────────────────────┐ │  ── Vertex Paint ──   📌   │
 │ [PAINT ⊛]← anchor                        │ ├────────────────────────────┤
 └──────────────────────────────────────────┘ │ Color:  [■            ]    │
                                              │ [x] Greyscale  ────●── 1.00│
                                              │ Target: [Color     ▾]  👁   │
                                              │ Channels: [x]R [x]G [x]B[ ]A│
                                              │ Blend:   [Mix   ▾]         │
                                              │ ── Brush ──                │
                                              │ Radius:   [0.50]           │
                                              │ Strength: [1.00]           │
                                              │ ── Apply ──                │
                                              │ [Fill Selected] [Fill All] │
                                              │ [Eyedropper]               │
                                              └────────────────────────────┘
```

Paint-mode viewport hint (existing pattern, bottom-right):
`LMB=Paint  Alt+Click=Eyedropper  Alt+S=Size  Alt+D=Strength  Shift+A=Cycle Blend`

## Risks / non-goals

- MenuButton popups close on outside click — the ⚙ multi-control settings
  panel must be an anchored `PanelContainer` (param-popup pattern), pinnable.
- Vertex Paint keyboard flow (Alt+S/D etc.) must not fight mode keys — paint
  keys only live while PAINT mode is on (already true).
- The dock version of the panel stays functional during the whole migration
  (feature-flagged), so nothing breaks mid-rework.

## Decisions (user-confirmed)

- UV editor **stays a bottom dock**, always usable alongside edit modes; gains
  a 0.1-increment grid background (toggleable).
- Icons get a **per-mode colour coding** system (Object/Vertex/Edge/Face),
  recorded above with exact tokens.
- ⚙ Settings popup is **right-most, last on the toolbar**.
- **Paint becomes an exclusive viewport mode** (equivalent to the existing
  Paint button); UV does not become a mode.
- **Paint controls live in a dedicated popup anchored top-right of the
  viewport**: colour picker, greyscale, target channel, channels mask, blend
  mode, brush radius/strength, fill ops, eyedropper — the full painter widget
  set from the current dock, hosted as a pinnable anchored PanelContainer.
- **Pinning:** popups (settings, paint) can be pinned open while working;
  pin state persists for the ⚙ panel.

## Phases

1. **Icons + colour system** (additive — current UI untouched).
2. **Toolbar MenuButtons** mirroring the element drawers (Create/Vertex/Edge/Face).
3. **⚙ Settings panel** (right-most, pinnable) absorbing General drawer toggles; sidebar optional.
4. **PAINT as viewport mode** (UV dock stays; separate follow-up for input layering).