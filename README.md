# GoBuild

**A free, open-source ProBuilder equivalent for Godot 4.**

> Model, edit, and ship game-ready geometry without leaving the Godot editor.

[![CI](https://github.com/marcel-b-roodt/GoBuild/actions/workflows/ci.yml/badge.svg)](https://github.com/marcel-b-roodt/GoBuild/actions/workflows/ci.yml)

---

## What is GoBuild?

GoBuild is a Godot 4 EditorPlugin that brings in-editor mesh modelling to Godot — the same way Unity's ProBuilder does for Unity. Block out levels, extrude faces, bevel edges, unwrap UVs, and assign per-face materials, all inside the editor you already use.

No Blender round-trips required for common geometry tasks.

## Status

🚧 **Early development — Stage 0 (Foundation).** The plugin is not yet functional. Star/watch the repo to follow progress.

See the [roadmap](docs/roadmap.md) for the planned feature stages.

## Installation (once released)

1. Open **Project → AssetLib** inside Godot.
2. Search for **GoBuild** and install.
3. Enable the plugin under **Project → Project Settings → Plugins**.
4. A **GoBuild** toolbar appears at the top of the 3D viewport.

Or download the latest zip from [Releases](https://github.com/marcel-b-roodt/GoBuild/releases) and drop the `addons/go_build/` folder into your project.

## Building from source

```bash
git clone https://github.com/marcel-b-roodt/GoBuild.git
cd GoBuild
dotnet test Tests/GoBuild.Tests/
```

Open `project.godot` in Godot 4 to run the development harness.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Please open an issue first for significant changes.

## Support the project

GoBuild is free and open-source. If it saves you time, consider supporting development on [Patreon](https://patreon.com/gobuild) *(coming soon)*.

## License

MIT — see [LICENSE](LICENSE).

