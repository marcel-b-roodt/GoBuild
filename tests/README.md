## GoBuild Tests

GDScript tests using [GdUnit4](https://github.com/MikeSchulze/gdUnit4).

### Structure

```
tests/
  mesh/
    go_build_mesh_test.gd       ← GoBuildMesh data model tests
    shape_generator_test.gd     ← Primitive shape generator tests
    operations/
      extrude_test.gd           ← Extrude face operation tests
      bevel_test.gd             ← Bevel edge operation tests
      weld_test.gd              ← Weld/merge vertex tests
  uv/
    planar_projection_test.gd   ← Planar UV projection tests
    box_projection_test.gd      ← Box UV projection tests
  export/
    obj_export_test.gd          ← OBJ export writer tests
```

### Running tests locally

1. Install GdUnit4 via **Project → AssetLib → search "GdUnit4"** (or add it manually to `addons/`).
2. Enable the plugin under **Project → Project Settings → Plugins**.
3. Open the **GdUnit4** panel in the bottom dock.
4. Click **Run all tests** or right-click any test file to run it individually.

### Running tests in CI

CI uses `MikeSchulze/gdUnit4-action` to run tests headlessly on every push/PR.
See `.github/workflows/ci.yml`.

### Writing a test

```gdscript
extends GdUnitTestSuite

func test_cube_face_count() -> void:
    var mesh = CubeGenerator.generate(1.0, 1.0, 1.0, 0)
    assert_int(mesh.faces.size()).is_equal(6)
```

