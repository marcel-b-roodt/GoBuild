## Central script registry for GoBuild.
##
## Preloads every GoBuild script in dependency order so that [code]class_name[/code]
## identifiers are registered in Godot's global lookup before any dependent
## script is compiled.  Loaded once by [code]plugin.gd[/code] in [method _enter_tree].
##
## Without this, Godot's alphabetical startup scan can compile a script before its
## dependencies are registered, caching a compile error that persists until reload.
## The per-file self-preload pattern only works if [i]every[/i] script remembers to
## add the preload — a single miss causes hard-to-diagnose runtime failures.
##
## Adding a new script? Append its [code]preload[/code] here, after the scripts
## it depends on.  The order must be a valid topological sort of the dependency DAG.
@tool
class_name GoBuildInit
extends RefCounted


# ── Layer 0: No GoBuild dependencies (standalone data types) ────────────

const _DEBUG         := preload("res://addons/go_build/core/go_build_debug.gd")
const _CONSTANTS      := preload("res://addons/go_build/core/go_build_constants.gd")
const _FACE           := preload("res://addons/go_build/mesh/go_build_face.gd")
const _EDGE           := preload("res://addons/go_build/mesh/go_build_edge.gd")
const _TRIANGULATE    := preload("res://addons/go_build/mesh/triangulate.gd")

# ── Layer 1: Depends only on Layer 0 ────────────────────────────────────

const _MESH           := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _MESH_IMPORT    := preload("res://addons/go_build/mesh/mesh_import.gd")

# Generators (depend on GoBuildMesh, GoBuildFace)
const _GEN_UTILS      := preload("res://addons/go_build/mesh/generators/mesh_generator_utils.gd")
const _CUBE_GEN       := preload("res://addons/go_build/mesh/generators/cube_generator.gd")
const _PLANE_GEN      := preload("res://addons/go_build/mesh/generators/plane_generator.gd")
const _SPHERE_GEN     := preload("res://addons/go_build/mesh/generators/sphere_generator.gd")
const _CYLINDER_GEN   := preload("res://addons/go_build/mesh/generators/cylinder_generator.gd")
const _CONE_GEN       := preload("res://addons/go_build/mesh/generators/cone_generator.gd")
const _TORUS_GEN      := preload("res://addons/go_build/mesh/generators/torus_generator.gd")
const _ARCH_GEN       := preload("res://addons/go_build/mesh/generators/arch_generator.gd")
const _STAIR_GEN      := preload("res://addons/go_build/mesh/generators/staircase_generator.gd")
const _POLYGON_GEN    := preload("res://addons/go_build/mesh/generators/polygon_generator.gd")
const _SHAPE_CATALOG  := preload("res://addons/go_build/mesh/generators/shape_creation_catalog.gd")
const _SHAPE_PARAMS   := preload("res://addons/go_build/mesh/generators/shape_param_mapping.gd")

# Operations (depend on GoBuildMesh, GoBuildFace, GoBuildEdge)
const _VC_OP          := preload("res://addons/go_build/mesh/operations/vertex_color_operation.gd")
const _BEVEL_OP       := preload("res://addons/go_build/mesh/operations/bevel_operation.gd")
const _EXTRUDE_OP     := preload("res://addons/go_build/mesh/operations/extrude_operation.gd")
const _EDGE_EXTRUDE   := preload("res://addons/go_build/mesh/operations/edge_extrude_operation.gd")
const _INSET_OP       := preload("res://addons/go_build/mesh/operations/inset_operation.gd")
const _LOOP_CUT_OP    := preload("res://addons/go_build/mesh/operations/loop_cut_operation.gd")
const _RIP_OP         := preload("res://addons/go_build/mesh/operations/rip_operation.gd")
const _SUBDIVIDE_OP   := preload("res://addons/go_build/mesh/operations/subdivide_operation.gd")
const _WELD_OP        := preload("res://addons/go_build/mesh/operations/weld_operation.gd")
const _DELETE_OP      := preload("res://addons/go_build/mesh/operations/delete_operation.gd")
const _DISSOLVE_OP    := preload("res://addons/go_build/mesh/operations/dissolve_operation.gd")
const _FLIP_NORMALS   := preload("res://addons/go_build/mesh/operations/flip_normals_operation.gd")
const _MERGE_FACES    := preload("res://addons/go_build/mesh/operations/merge_faces_operation.gd")
const _FILL_OP        := preload("res://addons/go_build/mesh/operations/fill_operation.gd")
const _BRIDGE_OP      := preload("res://addons/go_build/mesh/operations/bridge_operation.gd")
const _CONSOLIDATE    := preload(
		"res://addons/go_build/mesh/operations/consolidate_slots_operation.gd")
const _MAT_ASSIGN     := preload(
		"res://addons/go_build/mesh/operations/material_assign_operation.gd")
const _AUTO_SMOOTH    := preload("res://addons/go_build/mesh/operations/auto_smooth_operation.gd")
const _SMOOTH_GRP     := preload("res://addons/go_build/mesh/operations/smooth_group_operation.gd")
const _HARD_EDGE      := preload("res://addons/go_build/mesh/operations/hard_edge_operation.gd")
const _TRIANGULATE_OP := preload("res://addons/go_build/mesh/operations/triangulate_operation.gd")

# ── Layer 2: UV (depends on GoBuildMesh) ─────────────────────────────────

const _UV_UTILS       := preload("res://addons/go_build/uv/uv_projection_utils.gd")
const _PLANAR_UV      := preload("res://addons/go_build/uv/planar_projection.gd")
const _BOX_UV         := preload("res://addons/go_build/uv/box_projection.gd")
const _CYL_UV         := preload("res://addons/go_build/uv/cylindrical_projection.gd")
const _SPHERE_UV      := preload("res://addons/go_build/uv/spherical_projection.gd")
const _UV_TOPO        := preload("res://addons/go_build/uv/uv_topology.gd")
const _UV_ISLAND_SEL  := preload("res://addons/go_build/uv/uv_island_select.gd")
const _UV_ISLAND_XFORM := preload("res://addons/go_build/uv/uv_island_transform.gd")
const _UV_PACK        := preload("res://addons/go_build/uv/uv_pack_islands.gd")
const _UV_PICKER      := preload("res://addons/go_build/uv/uv_picker.gd")
const _UV_PREPARE     := preload("res://addons/go_build/uv/uv_prepare_for_texturing.gd")
const _UV_STITCH      := preload("res://addons/go_build/uv/uv_stitch_islands.gd")
const _UV_VERTEX_XFORM := preload("res://addons/go_build/uv/uv_vertex_transform.gd")
const _UV_WIREFRAME   := preload("res://addons/go_build/uv/uv_wireframe_export.gd")
const _UV_CANVAS      := preload("res://addons/go_build/uv/go_build_uv_canvas.gd")

# ── Layer 3: Core helpers (depend on mesh + selection) ───────────────────

const _SEL_MGR        := preload("res://addons/go_build/core/selection_manager.gd")
const _SEL_HELPERS    := preload("res://addons/go_build/core/selection_helpers.gd")
const _SEL_DIMS       := preload("res://addons/go_build/core/selection_dims_helper.gd")
const _PICKING        := preload("res://addons/go_build/core/picking_helper.gd")
const _OVERLAY_HINT   := preload("res://addons/go_build/core/overlay_hint_helper.gd")
const _PALETTE        := preload("res://addons/go_build/core/go_build_material_palette.gd")
const _SETTINGS       := preload("res://addons/go_build/core/go_build_project_settings.gd")
const _MATERIALS      := preload("res://addons/go_build/core/go_build_materials.gd")
const _TRANSFORM_HLP  := preload("res://addons/go_build/core/go_build_transform_helpers.gd")
const _MOUSE_TRACKER  := preload("res://addons/go_build/core/go_build_mouse_tracker.gd")
const _DELTA_STRAT    := preload("res://addons/go_build/core/go_build_delta_strategy.gd")
const _UNDO_SPIN      := preload("res://addons/go_build/core/go_build_undo_spin_box.gd")

# ── Layer 4: Mesh instance + gizmo (depend on core helpers) ──────────────

const _MESH_INSTANCE  := preload("res://addons/go_build/core/go_build_mesh_instance.gd")
const _GIZMO_PLUGIN   := preload("res://addons/go_build/core/go_build_gizmo_plugin.gd")
const _GIZMO          := preload("res://addons/go_build/core/go_build_gizmo.gd")

# ── Layer 5: Drawers + controllers (depend on gizmo, mesh instance) ─────

const _DRAWER         := preload("res://addons/go_build/core/go_build_drawer.gd")
const _VERTEX_DRAWER  := preload("res://addons/go_build/core/go_build_vertex_drawer.gd")
const _EDGE_DRAWER    := preload("res://addons/go_build/core/go_build_edge_drawer.gd")
const _FACE_DRAWER    := preload("res://addons/go_build/core/go_build_face_drawer.gd")
const _GENERAL_DRAWER := preload("res://addons/go_build/core/go_build_general_drawer.gd")
const _SURFACE_DRAWER := preload("res://addons/go_build/core/go_build_surface_drawer.gd")
const _CREATE_DRAWER  := preload("res://addons/go_build/core/go_build_create_drawer.gd")
const _MATERIALS_DRAW := preload("res://addons/go_build/core/go_build_materials_drawer.gd")
const _UV_DRAWER      := preload("res://addons/go_build/core/go_build_uv_drawer.gd")
const _PARAM_PREVIEW   := preload("res://addons/go_build/core/go_build_param_preview.gd")
const _DRAG_OP        := preload("res://addons/go_build/core/go_build_drag_operation.gd")
const _DRAG_CTRL      := preload("res://addons/go_build/core/go_build_drag_controller.gd")
const _SHAPE_DRAW_CTRL := preload("res://addons/go_build/core/go_build_shape_draw_controller.gd")
const _SHAPE_DRAW_OVER := preload("res://addons/go_build/core/go_build_shape_draw_overlay.gd")
const _DROP_CONVERTER := preload("res://addons/go_build/core/go_build_material_drop_converter.gd")
const _SIC            := preload("res://addons/go_build/core/selection_input_controller.gd")
const _SHAPE_PLACEMENT := preload("res://addons/go_build/core/shape_placement.gd")
const _CHEATSHEET     := preload("res://addons/go_build/core/go_build_cheatsheet_popup.gd")
const _TOOL_PINNER    := preload("res://addons/go_build/core/node3d_editor_tool_pinner.gd")

# ── Layer 6: Panels (depend on everything above) ─────────────────────────

const _PANEL          := preload("res://addons/go_build/core/go_build_panel.gd")
const _UV_PANEL       := preload("res://addons/go_build/uv/go_build_uv_panel.gd")
const _VC_PAINTER     := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_painter.gd")
const _VC_BRUSH       := preload(
		"res://addons/go_build/vertex_paint/go_build_vertex_paint_brush.gd")

# ── Layer 7: Export (depends on mesh instance) ─────────────────────────────

const _GLB_EXPORTER   := preload("res://addons/go_build/export/glb_exporter.gd")
const _EXPORT_INSP    := preload(
		"res://addons/go_build/export/go_build_export_inspector_plugin.gd")
