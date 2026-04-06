# GoBuild

**Free, open-source in-editor mesh modelling for Godot 4.**

> Block out levels, sculpt geometry, and ship game-ready meshes without leaving the Godot editor.

[![CI](https://github.com/marcel-b-roodt/GoBuild/actions/workflows/ci.yml/badge.svg)](https://github.com/marcel-b-roodt/GoBuild/actions/workflows/ci.yml)

---

## What is GoBuild?

GoBuild is a Godot 4 EditorPlugin that brings in-editor mesh modelling directly into Godot. Create and edit 3D geometry at the vertex, edge, and face level — select elements, move and rotate them, and build scenes out of solid shapes, all without leaving the editor.

Designed for level blockout, architecture, and game-ready props. No external tools required for common geometry tasks.

## Status

🔧 **Active development — Stage 2 (Element Selection & Transform).**

Primitive shapes, sub-element selection, move handles, rotate handles, and box select are working. See [GUIDE.md](GUIDE.md) for what you can do right now.

## Installation

**From the Godot Asset Library** *(once listed)*:
1. Open **Project → AssetLib** inside Godot.
2. Search for **GoBuild** and install.
3. Enable the plugin under **Project → Project Settings → Plugins**.

**From a release zip**:
1. Download the latest zip from [Releases](https://github.com/marcel-b-roodt/GoBuild/releases).
2. Drop the `addons/go_build/` folder into your project's `addons/` directory.
3. Enable the plugin under **Project → Project Settings → Plugins**.

**From source**:
```bash
git clone https://github.com/marcel-b-roodt/GoBuild.git
```
Open `project.godot` in Godot 4. The plugin activates automatically.

## Quick Start

See **[GUIDE.md](GUIDE.md)** for a full walkthrough — creating shapes, selecting elements, moving and rotating geometry, and all keyboard shortcuts.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Please open an issue first for significant changes.

## Support the project

GoBuild is free and open-source. If it saves you time, consider supporting development on [Patreon](https://patreon.com/gobuild) *(coming soon)*.

## License

GPL v3 — see [LICENSE.md](LICENSE.md).
