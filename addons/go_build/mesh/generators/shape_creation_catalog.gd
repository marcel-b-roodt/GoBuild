## Shared shape-creation catalog for panel flows.
##
## Centralises default parameters, preview support, editable parameter schema,
## and mesh generation dispatch for all primitive generators.
@tool
class_name ShapeCreationCatalog
extends RefCounted

# Self-preloads — dependency order.
const _MESH_SCRIPT := preload("res://addons/go_build/mesh/go_build_mesh.gd")
const _CUBE_SCRIPT := preload("res://addons/go_build/mesh/generators/cube_generator.gd")
const _PLANE_SCRIPT := preload("res://addons/go_build/mesh/generators/plane_generator.gd")
const _CYLINDER_SCRIPT := preload("res://addons/go_build/mesh/generators/cylinder_generator.gd")
const _SPHERE_SCRIPT := preload("res://addons/go_build/mesh/generators/sphere_generator.gd")
const _CONE_SCRIPT := preload("res://addons/go_build/mesh/generators/cone_generator.gd")
const _TORUS_SCRIPT := preload("res://addons/go_build/mesh/generators/torus_generator.gd")
const _STAIR_SCRIPT := preload("res://addons/go_build/mesh/generators/staircase_generator.gd")
const _ARCH_SCRIPT := preload("res://addons/go_build/mesh/generators/arch_generator.gd")


## All registered primitive shape names, in display order.
## Use this array wherever the full shape list is needed so the panel
## and any other consumer stay in sync automatically.
static func all_shapes() -> Array[String]:
	return [
		"Cube", "Plane", "Cylinder", "Sphere",
		"Cone", "Torus", "Staircase", "Arch",
	]


static func supports_preview(shape_name: String) -> bool:
	match shape_name:
		"Cylinder", "Cone", "Sphere", "Staircase", "Torus", "Arch":
			return true
		_:
			return false


static func node_name(shape_name: String) -> String:
	return "GoBuild" + shape_name


static func default_params(shape_name: String) -> Dictionary:
	match shape_name:
		"Cylinder":
			return {
				"radius": 0.5,
				"height": 1.0,
				"sides": 16,
				"cap_top": true,
				"cap_bottom": true,
			}
		"Cone":
			return {
				"radius": 0.5,
				"height": 1.0,
				"sides": 16,
				"cap_bottom": true,
			}
		"Sphere":
			return {
				"radius": 0.5,
				"rings": 8,
				"segments": 16,
			}
		"Staircase":
			return {
				"steps": 4,
				"step_width": 1.0,
				"step_height": 0.25,
				"step_depth": 0.3,
			}
		"Torus":
			return {
				"radius_major": 0.5,
				"radius_minor": 0.2,
				"rings": 16,
				"tube_segments": 8,
			}
		"Arch":
			return {
				"outer_radius": 1.0,
				"thickness": 0.2,
				"angle_degrees": 180.0,
				"segments": 8,
				"depth": 0.2,
			}
		"Cube":
			return {"width": 1.0, "height": 1.0, "depth": 1.0}
		"Plane":
			return {"width": 1.0, "depth": 1.0}
		_:
			return {}


## Parameter schema for panel preview widgets.
## Field keys:
## - type: "float" | "int" | "bool"
## - key: parameter dictionary key
## - label: UI label
## - min/max/step: numeric limits (for float/int types)
static func preview_param_specs(shape_name: String) -> Array[Dictionary]:
	match shape_name:
		"Cylinder":
			return [
				{"type": "float", "key": "radius", "label": "Radius", "min": 0.01, "max": 100.0, "step": 0.01},
				{"type": "float", "key": "height", "label": "Height", "min": 0.01, "max": 100.0, "step": 0.01},
				{"type": "int", "key": "sides", "label": "Sides", "min": 3, "max": 256, "step": 1},
				{"type": "bool", "key": "cap_top", "label": "Cap Top"},
				{"type": "bool", "key": "cap_bottom", "label": "Cap Bottom"},
			]
		"Cone":
			return [
				{"type": "float", "key": "radius", "label": "Radius", "min": 0.01, "max": 100.0, "step": 0.01},
				{"type": "float", "key": "height", "label": "Height", "min": 0.01, "max": 100.0, "step": 0.01},
				{"type": "int", "key": "sides", "label": "Sides", "min": 3, "max": 256, "step": 1},
				{"type": "bool", "key": "cap_bottom", "label": "Cap Bottom"},
			]
		"Sphere":
			return [
				{"type": "float", "key": "radius", "label": "Radius", "min": 0.01, "max": 100.0, "step": 0.01},
				{"type": "int", "key": "rings", "label": "Rings", "min": 2, "max": 256, "step": 1},
				{"type": "int", "key": "segments", "label": "Segments", "min": 3, "max": 512, "step": 1},
			]
		"Staircase":
			return [
				{"type": "int", "key": "steps", "label": "Steps", "min": 1, "max": 256, "step": 1},
				{
					"type": "float", "key": "step_width", "label": "Step Width",
					"min": 0.01, "max": 100.0, "step": 0.01,
				},
				{
					"type": "float", "key": "step_height", "label": "Step Height",
					"min": 0.01, "max": 100.0, "step": 0.01,
				},
				{
					"type": "float", "key": "step_depth", "label": "Step Depth",
					"min": 0.01, "max": 100.0, "step": 0.01,
				},
			]
		"Torus":
			return [
				{
					"type": "float", "key": "radius_major", "label": "Major Radius",
					"min": 0.02, "max": 100.0, "step": 0.01,
				},
				{
					"type": "float", "key": "radius_minor", "label": "Minor Radius",
					"min": 0.01, "max": 99.0, "step": 0.01,
				},
				{"type": "int", "key": "rings", "label": "Rings", "min": 3, "max": 256, "step": 1},
				{"type": "int", "key": "tube_segments", "label": "Tube Segs", "min": 3, "max": 256, "step": 1},
			]
		"Arch":
			return [
				{
					"type": "float", "key": "outer_radius", "label": "Outer Radius",
					"min": 0.02, "max": 100.0, "step": 0.01,
				},
				{
					"type": "float", "key": "thickness", "label": "Thickness",
					"min": 0.01, "max": 99.0, "step": 0.01,
				},
				{
					"type": "float", "key": "angle_degrees", "label": "Angle",
					"min": 1.0, "max": 360.0, "step": 1.0,
				},
				{"type": "int", "key": "segments", "label": "Segments", "min": 1, "max": 256, "step": 1},
				{
					"type": "float", "key": "depth", "label": "Depth",
					"min": 0.01, "max": 100.0, "step": 0.01,
				},
			]
		_:
			return []


## Default values for non-drawable (structural) parameters only.
## Size/radius params are excluded — those are determined by the interactive
## draw flow.  Used by [GoBuildShapeDrawController] to seed the extra-params
## dictionary.
static func default_non_drawable_params(shape_name: String) -> Dictionary:
	match shape_name:
		"Cube":
			return {"subdivisions": 0}
		"Plane":
			return {"subdivisions_x": 0, "subdivisions_z": 0}
		"Cylinder":
			return {"sides": 16, "cap_top": true, "cap_bottom": true}
		"Sphere":
			return {"rings": 8, "segments": 16}
		"Cone":
			return {"sides": 16, "cap_bottom": true}
		"Torus":
			return {"rings": 16, "tube_segments": 8}
		"Staircase":
			return {"steps": 4}
		"Arch":
			return {"angle_degrees": 180.0, "segments": 8, "thickness": 0.2}
		_:
			return {}


## Parameter schema for non-drawable (structural) params only.
## These are the controls shown in the compact panel strip during draw.
## Size/radius params are excluded — they are drawn in the viewport.
static func non_drawable_param_specs(shape_name: String) -> Array[Dictionary]:
	match shape_name:
		"Cube":
			return [
				{"type": "int", "key": "subdivisions", "label": "Subdivs", "min": 0, "max": 256, "step": 1},
			]
		"Plane":
			return [
				{"type": "int", "key": "subdivisions_x", "label": "Sub X", "min": 0, "max": 256, "step": 1},
				{"type": "int", "key": "subdivisions_z", "label": "Sub Z", "min": 0, "max": 256, "step": 1},
			]
		"Cylinder":
			return [
				{"type": "int", "key": "sides", "label": "Sides", "min": 3, "max": 256, "step": 1},
				{"type": "bool", "key": "cap_top", "label": "Cap Top"},
				{"type": "bool", "key": "cap_bottom", "label": "Cap Bottom"},
			]
		"Sphere":
			return [
				{"type": "int", "key": "rings", "label": "Rings", "min": 2, "max": 256, "step": 1},
				{"type": "int", "key": "segments", "label": "Segments", "min": 3, "max": 512, "step": 1},
			]
		"Cone":
			return [
				{"type": "int", "key": "sides", "label": "Sides", "min": 3, "max": 256, "step": 1},
				{"type": "bool", "key": "cap_bottom", "label": "Cap Bottom"},
			]
		"Torus":
			return [
				{"type": "int", "key": "rings", "label": "Rings", "min": 3, "max": 256, "step": 1},
				{"type": "int", "key": "tube_segments", "label": "Tube Segs", "min": 3, "max": 256, "step": 1},
			]
		"Staircase":
			return [
				{"type": "int", "key": "steps", "label": "Steps", "min": 1, "max": 256, "step": 1},
			]
		"Arch":
			return [
				{
					"type": "float", "key": "angle_degrees",
					"label": "Angle", "min": 1.0, "max": 360.0, "step": 1.0,
				},
				{"type": "int", "key": "segments", "label": "Segments",
					"min": 1, "max": 256, "step": 1},
				{
					"type": "float", "key": "thickness",
					"label": "Thickness", "min": 0.01, "max": 99.0, "step": 0.01,
				},
			]
		_:
			return []


static func normalise_params(shape_name: String, raw_params: Dictionary) -> Dictionary:
	var p: Dictionary = raw_params.duplicate(true)
	match shape_name:
		"Cylinder":
			p["radius"] = maxf(float(p.get("radius", 0.5)), 0.01)
			p["height"] = maxf(float(p.get("height", 1.0)), 0.01)
			p["sides"] = maxi(int(p.get("sides", 16)), 3)
		"Cone":
			p["radius"] = maxf(float(p.get("radius", 0.5)), 0.01)
			p["height"] = maxf(float(p.get("height", 1.0)), 0.01)
			p["sides"] = maxi(int(p.get("sides", 16)), 3)
		"Sphere":
			p["radius"] = maxf(float(p.get("radius", 0.5)), 0.01)
			p["rings"] = maxi(int(p.get("rings", 8)), 2)
			p["segments"] = maxi(int(p.get("segments", 16)), 3)
		"Staircase":
			p["steps"] = maxi(int(p.get("steps", 4)), 1)
			p["step_width"] = maxf(float(p.get("step_width", 1.0)), 0.01)
			p["step_height"] = maxf(float(p.get("step_height", 0.25)), 0.01)
			p["step_depth"] = maxf(float(p.get("step_depth", 0.3)), 0.01)
		"Torus":
			var major := maxf(float(p.get("radius_major", 0.5)), 0.02)
			var minor := maxf(float(p.get("radius_minor", 0.2)), 0.01)
			if minor >= major:
				minor = maxf(0.01, major * 0.5)
			p["radius_major"] = major
			p["radius_minor"] = minor
			p["rings"] = maxi(int(p.get("rings", 16)), 3)
			p["tube_segments"] = maxi(int(p.get("tube_segments", 8)), 3)
		"Arch":
			var outer := maxf(float(p.get("outer_radius", 1.0)), 0.02)
			var thick := maxf(float(p.get("thickness", 0.2)), 0.01)
			if thick >= outer:
				thick = maxf(0.01, outer * 0.5)
			p["outer_radius"] = outer
			p["thickness"] = thick
			p["angle_degrees"] = clampf(float(p.get("angle_degrees", 180.0)), 1.0, 360.0)
			p["segments"] = maxi(int(p.get("segments", 8)), 1)
			p["depth"] = maxf(float(p.get("depth", 0.2)), 0.01)
	return p


static func build_mesh(shape_name: String, params: Dictionary) -> GoBuildMesh:
	var p: Dictionary = normalise_params(shape_name, params)
	match shape_name:
		"Cube":
			return CubeGenerator.generate(
				float(p.get("width", 1.0)),
				float(p.get("height", 1.0)),
				float(p.get("depth", 1.0)),
			)
		"Plane":
			return PlaneGenerator.generate(
				float(p.get("width", 1.0)),
				float(p.get("depth", 1.0)),
			)
		"Cylinder":
			return CylinderGenerator.generate(
				float(p.get("radius", 0.5)),
				float(p.get("height", 1.0)),
				int(p.get("sides", 16)),
				bool(p.get("cap_top", true)),
				bool(p.get("cap_bottom", true)),
			)
		"Sphere":
			return SphereGenerator.generate(
				float(p.get("radius", 0.5)),
				int(p.get("rings", 8)),
				int(p.get("segments", 16)),
			)
		"Cone":
			return ConeGenerator.generate(
				float(p.get("radius", 0.5)),
				float(p.get("height", 1.0)),
				int(p.get("sides", 16)),
				bool(p.get("cap_bottom", true)),
			)
		"Torus":
			return TorusGenerator.generate(
				float(p.get("radius_major", 0.5)),
				float(p.get("radius_minor", 0.2)),
				int(p.get("rings", 16)),
				int(p.get("tube_segments", 8)),
			)
		"Staircase":
			return StaircaseGenerator.generate(
				int(p.get("steps", 4)),
				float(p.get("step_width", 1.0)),
				float(p.get("step_height", 0.25)),
				float(p.get("step_depth", 0.3)),
			)
		"Arch":
			return ArchGenerator.generate(
				float(p.get("outer_radius", 1.0)),
				float(p.get("thickness", 0.2)),
				float(p.get("angle_degrees", 180.0)),
				int(p.get("segments", 8)),
				float(p.get("depth", 0.2)),
			)
		_:
			return CubeGenerator.generate()
