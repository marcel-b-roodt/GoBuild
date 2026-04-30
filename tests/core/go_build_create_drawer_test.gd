## GdUnit4 tests for [GoBuildCreateDrawer].
##
## NOTE: GoBuildCreateDrawer requires [EditorInterface] for shape insertion
## (getting the edited scene root and selection).  Headless GdUnit4 tests
## cannot drive EditorInterface, so unit testing is deferred to manual
## in-editor verification.
##
## What to verify manually:
##   - Panel shows "Create Shape" drawer open by default in Object mode.
##   - Clicking a shape button (e.g. Cube) inserts a GoBuildMeshInstance
##     with the correct node name into the scene root.
##   - The inserted node is auto-selected in the scene tree.
##   - Undo (Ctrl+Z) removes the inserted node.
##   - Redo (Ctrl+Shift+Z) re-inserts the node.
##   - Shapes with configurable parameters (e.g. Cylinder) open a preview
##     dialog; cancelling does not insert a node.
@tool
extends GdUnitTestSuite
