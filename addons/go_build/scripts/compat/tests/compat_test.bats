#!/usr/bin/env bats
# Tests for GoBuild compat transform functions and wrappers.

setup() {
	TEST_DIR="$(mktemp -d)"
	mkdir -p "${TEST_DIR}"
}

teardown() {
	rm -rf "${TEST_DIR}"
}

# ---------------------------------------------------------------------------
# copy_addon
# ---------------------------------------------------------------------------

@test "copy_addon copies the addon tree" {
	source "${BATS_TEST_DIRNAME}/../functions/copy_addon.sh"
	mkdir -p "${TEST_DIR}/fake_source"
	touch "${TEST_DIR}/fake_source/plugin.cfg"

	compat::copy_addon "${TEST_DIR}/fake_source" "${TEST_DIR}/output"

	[ -f "${TEST_DIR}/output/fake_source/plugin.cfg" ]
}

# ---------------------------------------------------------------------------
# check_addon_root
# ---------------------------------------------------------------------------

@test "check_addon_root succeeds when plugin.cfg exists" {
	source "${BATS_TEST_DIRNAME}/../functions/copy_addon.sh"
	mkdir -p "${TEST_DIR}/fake_addon"
	touch "${TEST_DIR}/fake_addon/plugin.cfg"

	compat::check_addon_root "${TEST_DIR}/fake_addon"
}

@test "check_addon_root fails when plugin.cfg is missing" {
	source "${BATS_TEST_DIRNAME}/../functions/copy_addon.sh"
	mkdir -p "${TEST_DIR}/not_addon"

	run compat::check_addon_root "${TEST_DIR}/not_addon"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# strip_typed_fors
# ---------------------------------------------------------------------------

@test "strip_typed_fors strips simple type annotations" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_typed_fors.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
for i: int in range(10):
	pass
for name: String in _NAMES:
	pass
GDSCRIPT

	compat::strip_typed_fors "${TEST_DIR}"

	grep -q 'for i in range(10):' "${TEST_DIR}/test.gd"
	grep -q 'for name in _NAMES:' "${TEST_DIR}/test.gd"
	! grep -q 'for i: int' "${TEST_DIR}/test.gd"
	! grep -q 'for name: String' "${TEST_DIR}/test.gd"
}

@test "strip_typed_fors strips dotted type annotations" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_typed_fors.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
for face: GoBuildFace in mesh.faces:
	pass
for mode: GoBuildFace.UvMode in modes:
	pass
GDSCRIPT

	compat::strip_typed_fors "${TEST_DIR}"

	grep -q 'for face in mesh.faces:' "${TEST_DIR}/test.gd"
	grep -q 'for mode in modes:' "${TEST_DIR}/test.gd"
}

@test "strip_typed_fors strips generic type annotations (Array[int])" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_typed_fors.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
for group: Array[int] in groups:
	pass
GDSCRIPT

	compat::strip_typed_fors "${TEST_DIR}"

	grep -q 'for group in groups:' "${TEST_DIR}/test.gd"
	! grep -q 'Array\[int\]' "${TEST_DIR}/test.gd"
}

@test "strip_typed_fors does not modify untyped for-loops" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_typed_fors.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
for i in range(10):
	pass
for child in get_children():
	pass
GDSCRIPT

	compat::strip_typed_fors "${TEST_DIR}"

	grep -q 'for i in range(10):' "${TEST_DIR}/test.gd"
	grep -q 'for child in get_children():' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# strip_export_groups
# ---------------------------------------------------------------------------

@test "strip_export_groups removes @export_group lines" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_export_groups.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
@export var name: String = ""
@export_group("Collision")
@export var use_collision: bool = false
@export_group("")
@export var other: int = 0
GDSCRIPT

	compat::strip_export_groups "${TEST_DIR}"

	! grep -q '@export_group' "${TEST_DIR}/test.gd"
	grep -q '@export var name' "${TEST_DIR}/test.gd"
	grep -q '@export var use_collision' "${TEST_DIR}/test.gd"
	grep -q '@export var other' "${TEST_DIR}/test.gd"
}

@test "strip_export_groups removes @export_subgroup lines" {
	source "${BATS_TEST_DIRNAME}/../functions/strip_export_groups.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
@export_subgroup("Details")
@export var detail: String = ""
GDSCRIPT

	compat::strip_export_groups "${TEST_DIR}"

	! grep -q '@export_subgroup' "${TEST_DIR}/test.gd"
	grep -q '@export var detail' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# replace_disable_mode_enum
# ---------------------------------------------------------------------------

@test "replace_disable_mode_enum replaces type and values" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_disable_mode_enum.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
@export var collision_disable_mode: StaticBody3D.DisableMode = StaticBody3D.DISABLE_MODE_REMOVE:
	set(value):
		collision_disable_mode = value
		if _collision_body != null:
			_collision_body.disable_mode = value
GDSCRIPT

	compat::replace_disable_mode_enum "${TEST_DIR}"

	! grep -q 'DisableMode' "${TEST_DIR}/test.gd"
	! grep -q 'DISABLE_MODE' "${TEST_DIR}/test.gd"
	grep -q '@export var collision_disable_mode: int = 0:' "${TEST_DIR}/test.gd"
	grep -q 'collision_disable_mode = value' "${TEST_DIR}/test.gd"
}

@test "replace_disable_mode_enum handles all three enum values" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_disable_mode_enum.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
var a = StaticBody3D.DISABLE_MODE_REMOVE
var b = StaticBody3D.DISABLE_MODE_MAKE_STATIC
var c = StaticBody3D.DISABLE_MODE_MAKE_KINEMATIC
GDSCRIPT

	compat::replace_disable_mode_enum "${TEST_DIR}"

	grep -q 'var a = 0' "${TEST_DIR}/test.gd"
	grep -q 'var b = 1' "${TEST_DIR}/test.gd"
	grep -q 'var c = 2' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# replace_dock_slot_bottom
# ---------------------------------------------------------------------------

@test "replace_dock_slot_bottom replaces DOCK_SLOT_BOTTOM with 7" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_dock_slot_bottom.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
GDSCRIPT

	compat::replace_dock_slot_bottom "${TEST_DIR}"

	grep -q 'add_control_to_dock(7, _uv_panel)' "${TEST_DIR}/test.gd"
	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)' "${TEST_DIR}/test.gd"
	! grep -q 'DOCK_SLOT_BOTTOM' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# replace_vector3_minmax
# ---------------------------------------------------------------------------

@test "replace_vector3_minmax replaces Vector3 min/max and downgrades Vector2" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_vector3_minmax.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
mn = mn.min(p)
mx = mx.max(p)
min_uv = min_uv.min(uv)
max_uv = max_uv.max(uv)
GDSCRIPT

	compat::replace_vector3_minmax "${TEST_DIR}"

	grep -q 'mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))' "${TEST_DIR}/test.gd"
	grep -q 'mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))' "${TEST_DIR}/test.gd"
	grep -q 'min_uv = Vector2(minf(min_uv.x, uv.x), minf(min_uv.y, uv.y))' "${TEST_DIR}/test.gd"
	grep -q 'max_uv = Vector2(maxf(max_uv.x, uv.x), maxf(max_uv.y, uv.y))' "${TEST_DIR}/test.gd"
	! grep -q '\.min(' "${TEST_DIR}/test.gd"
	! grep -q '\.max(' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# replace_enum_int_cast
# ---------------------------------------------------------------------------

@test "replace_enum_int_cast replaces 'as int' with int()" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_enum_int_cast.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
var mode_int: int = mode as int
var other: int = value as int
GDSCRIPT

	compat::replace_enum_int_cast "${TEST_DIR}"

	grep -q 'int(mode)' "${TEST_DIR}/test.gd"
	grep -q 'int(value)' "${TEST_DIR}/test.gd"
	! grep -q 'as int' "${TEST_DIR}/test.gd"
}

@test "replace_enum_int_cast does not touch 'as float' or 'as String'" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_enum_int_cast.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
var x: float = val as float
var y: String = val as String
GDSCRIPT

	compat::replace_enum_int_cast "${TEST_DIR}"

	grep -q 'as float' "${TEST_DIR}/test.gd"
	grep -q 'as String' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# compat_42.sh — end-to-end (in-place on a fake addon)
# ---------------------------------------------------------------------------

@test "compat_42.sh transforms typed for-loops, dock slot, DisableMode, Vector3 min/max, and enum casts" {
	local addon_dir="${TEST_DIR}/go_build"
	mkdir -p "${addon_dir}"

	cat > "${addon_dir}/plugin.cfg" <<'CFG'
[plugin]
name="GoBuild"
version="0.10.0"
script="plugin.gd"
CFG

	cat > "${addon_dir}/test.gd" <<'GDSCRIPT'
@export_group("Collision")
@export var use_collision: bool = false
@export var collision_disable_mode: StaticBody3D.DisableMode = StaticBody3D.DISABLE_MODE_REMOVE:
	set(value):
		collision_disable_mode = value
for i: int in range(10):
	pass
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)
mn = mn.min(p)
mx = mx.max(p)
var mode_int: int = mode as int
GDSCRIPT

	local script_dir="${addon_dir}/scripts/compat"
	mkdir -p "${script_dir}/functions"
	cp "${BATS_TEST_DIRNAME}/../compat_42.sh" "${script_dir}/"
	cp "${BATS_TEST_DIRNAME}/../functions/strip_typed_fors.sh" "${script_dir}/functions/"
	cp "${BATS_TEST_DIRNAME}/../functions/replace_dock_slot_bottom.sh" "${script_dir}/functions/"
	cp "${BATS_TEST_DIRNAME}/../functions/replace_disable_mode_enum.sh" "${script_dir}/functions/"
	cp "${BATS_TEST_DIRNAME}/../functions/replace_vector3_minmax.sh" "${script_dir}/functions/"
	cp "${BATS_TEST_DIRNAME}/../functions/replace_enum_int_cast.sh" "${script_dir}/functions/"
	chmod +x "${script_dir}/compat_42.sh"

	GIT_DIR=/nonexistent bash "${script_dir}/compat_42.sh"

	# Keeps export groups (4.2 supports them)
	grep -q '@export_group' "${addon_dir}/test.gd"
	# Strips typed for-loops
	grep -q 'for i in range(10):' "${addon_dir}/test.gd"
	! grep -q 'for i: int' "${addon_dir}/test.gd"
	# Replaces DOCK_SLOT_BOTTOM with 7
	grep -q 'add_control_to_dock(7, _uv_panel)' "${addon_dir}/test.gd"
	! grep -q 'DOCK_SLOT_BOTTOM' "${addon_dir}/test.gd"
	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)' "${addon_dir}/test.gd"
	# Replaces DisableMode
	! grep -q 'DisableMode' "${addon_dir}/test.gd"
	! grep -q 'DISABLE_MODE' "${addon_dir}/test.gd"
	grep -q '@export var collision_disable_mode: int = 0:' "${addon_dir}/test.gd"
	# Replaces Vector3.min/max with minf/maxf
	grep -q 'Vector3(minf(mn.x, p.x)' "${addon_dir}/test.gd"
	grep -q 'Vector3(maxf(mx.x, p.x)' "${addon_dir}/test.gd"
	! grep -q '\.min(' "${addon_dir}/test.gd"
	! grep -q '\.max(' "${addon_dir}/test.gd"
	# Replaces "as int" with int()
	grep -q 'int(mode)' "${addon_dir}/test.gd"
	! grep -q 'as int' "${addon_dir}/test.gd"
}

# ---------------------------------------------------------------------------
# replace_dock_slot_bottom_43
# ---------------------------------------------------------------------------

@test "replace_dock_slot_bottom_43 replaces DOCK_SLOT_BOTTOM with DOCK_SLOT_LEFT_UR" {
	source "${BATS_TEST_DIRNAME}/../functions/replace_dock_slot_bottom_43.sh"

	cat > "${TEST_DIR}/test.gd" <<'GDSCRIPT'
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
GDSCRIPT

	compat::replace_dock_slot_bottom_43 "${TEST_DIR}"

	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UR, _uv_panel)' "${TEST_DIR}/test.gd"
	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)' "${TEST_DIR}/test.gd"
	! grep -q 'DOCK_SLOT_BOTTOM' "${TEST_DIR}/test.gd"
}

# ---------------------------------------------------------------------------
# compat_43.sh — end-to-end (in-place on a fake addon)
# ---------------------------------------------------------------------------

@test "compat_43.sh replaces DOCK_SLOT_BOTTOM with DOCK_SLOT_LEFT_UR only" {
	local addon_dir="${TEST_DIR}/go_build"
	mkdir -p "${addon_dir}"

	cat > "${addon_dir}/plugin.cfg" <<'CFG'
[plugin]
name="GoBuild"
version="0.10.0"
script="plugin.gd"
CFG

	cat > "${addon_dir}/test.gd" <<'GDSCRIPT'
add_control_to_dock(DOCK_SLOT_BOTTOM, _uv_panel)
add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)
for i: int in range(10):
	pass
var mode_int: int = mode as int
GDSCRIPT

	local script_dir="${addon_dir}/scripts/compat"
	mkdir -p "${script_dir}/functions"
	cp "${BATS_TEST_DIRNAME}/../compat_43.sh" "${script_dir}/"
	cp "${BATS_TEST_DIRNAME}/../functions/replace_dock_slot_bottom_43.sh" "${script_dir}/functions/"
	chmod +x "${script_dir}/compat_43.sh"

	GIT_DIR=/nonexistent bash "${script_dir}/compat_43.sh"

	# Replaces DOCK_SLOT_BOTTOM with DOCK_SLOT_LEFT_UR
	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UR, _uv_panel)' "${addon_dir}/test.gd"
	! grep -q 'DOCK_SLOT_BOTTOM' "${addon_dir}/test.gd"
	grep -q 'add_control_to_dock(DOCK_SLOT_LEFT_UL, _panel)' "${addon_dir}/test.gd"
	# Does NOT touch other syntax (4.3 already supports typed for-loops, as int, etc.)
	grep -q 'for i: int in range(10):' "${addon_dir}/test.gd"
	grep -q 'mode as int' "${addon_dir}/test.gd"
}