## Palette discovery scan hygiene tests — [GoBuildProjectSettings].
##
## Host-project invariant (SpiritWalk bug report 2026-09-08): the
## whole-res:// scan must NOT descend into upstream-submodule dirs
## (`_*`) or hidden dirs — probing other plugins' test fixtures there
## triggers load errors for resources whose dependencies resolve
## outside the host's res:// tree.
@tool
extends GdUnitTestSuite

const _SETTINGS_SCRIPT := preload(
		"res://addons/go_build/core/go_build_project_settings.gd")


func _make_tree(root: String, dirs: Array, tres_files: Array) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	for d: String in dirs:
		DirAccess.make_dir_recursive_absolute(root.path_join(d))
	for entry: Array in tres_files:
		var f := FileAccess.open(root.path_join(entry[0]), FileAccess.WRITE)
		f.store_string(entry[1])
		f.close()


func _cleanup(root: String) -> void:
	var da := DirAccess.open(root)
	if da == null:
		return
	da.include_hidden = true
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		var full := root.path_join(item)
		if da.current_is_dir():
			_cleanup(full)
		else:
			DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(root)


func test_scan_skips_submodule_and_hidden_dirs() -> void:
	var base := "res://_scan_hygiene_test"
	_make_tree(base,
			["_go_other_upstream", ".godot", "materials"],
			[
				["top.tres", "[gd_resource type=\"Resource\"]"],
				["_go_other_upstream/fixture.tres", "[gd_resource type=\"Resource\"]"],
				[".godot/hidden.tres", "[gd_resource type=\"Resource\"]"],
				["materials/palette.tres", "[gd_resource type=\"Resource\"]"],
			])
	var files: PackedStringArray = _SETTINGS_SCRIPT._collect_tres_files(base)
	_cleanup(base)
	var found := {}
	for p: String in files:
		found[p.get_file()] = true
	assert_bool(found.has("top.tres")).is_true()
	assert_bool(found.has("palette.tres")).is_true()
	assert_bool(found.has("fixture.tres")).is_false()
	assert_bool(found.has("hidden.tres")).is_false()