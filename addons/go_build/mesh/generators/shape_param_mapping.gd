## Maps drawn AABB dimensions to generator parameters for each primitive shape.
##
## Given a shape name and the 3D bounding box the user drew (width, depth,
## height), computes the parameter dictionary that produces a mesh fitting
## that AABB.  Extra non-drawable params (sides, rings, caps, etc.) are
## merged in so [method build_params] returns a complete, normalised param
## dictionary ready for [ShapeCreationCatalog.build_mesh].
##
## Constraints (e.g. Torus radius_major > radius_minor) are enforced by
## clamping, never by rejecting input.
@tool
class_name ShapeParamMapping
extends RefCounted

const _EPSILON: float = 0.01


static func build_params(
		shape_name: String,
		drawn_width: float,
		drawn_depth: float,
		drawn_height: float,
		extra: Dictionary = {},
) -> Dictionary:
	var w: float = maxf(drawn_width, _EPSILON)
	var d: float = maxf(drawn_depth, _EPSILON)
	var h: float = maxf(drawn_height, _EPSILON)
	match shape_name:
		"Cube":
			return _cube_params(w, d, h, extra)
		"Plane":
			return _plane_params(w, d, extra)
		"Cylinder":
			return _cylinder_params(w, d, h, extra)
		"Sphere":
			return _sphere_params(w, d, h, extra)
		"Cone":
			return _cone_params(w, d, h, extra)
		"Torus":
			return _torus_params(w, d, h, extra)
		"Staircase":
			return _staircase_params(w, d, h, extra)
		"Arch":
			return _arch_params(w, d, h, extra)
		_:
			return {"width": w, "height": h, "depth": d}


static func _cube_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var p: Dictionary = {"width": w, "height": h, "depth": d}
	if extra.has("subdivisions"):
		p["subdivisions"] = int(extra["subdivisions"])
	return p


static func _plane_params(w: float, d: float, extra: Dictionary) -> Dictionary:
	var p: Dictionary = {"width": w, "depth": d}
	if extra.has("subdivisions_x"):
		p["subdivisions_x"] = int(extra["subdivisions_x"])
	if extra.has("subdivisions_z"):
		p["subdivisions_z"] = int(extra["subdivisions_z"])
	return p


static func _cylinder_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var r: float = maxf(w, d) / 2.0
	var p: Dictionary = {"radius": r, "height": h}
	p["sides"] = int(extra.get("sides", 16))
	p["cap_top"] = bool(extra.get("cap_top", true))
	p["cap_bottom"] = bool(extra.get("cap_bottom", true))
	if not is_equal_approx(w, d):
		p["_scale_x"] = w / (2.0 * r)
		p["_scale_z"] = d / (2.0 * r)
	return p


static func _sphere_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var radius: float = maxf(w, maxf(d, h)) / 2.0
	var p: Dictionary = {"radius": radius}
	p["rings"] = int(extra.get("rings", 8))
	p["segments"] = int(extra.get("segments", 16))
	p["_scale_x"] = w / (2.0 * radius)
	p["_scale_y"] = h / (2.0 * radius)
	p["_scale_z"] = d / (2.0 * radius)
	return p


static func _cone_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var r: float = maxf(w, d) / 2.0
	var p: Dictionary = {"radius": r, "height": h}
	p["sides"] = int(extra.get("sides", 16))
	p["cap_bottom"] = bool(extra.get("cap_bottom", true))
	if not is_equal_approx(w, d):
		p["_scale_x"] = w / (2.0 * r)
		p["_scale_z"] = d / (2.0 * r)
	return p


static func _torus_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var radius_minor: float = h / 2.0
	var radius_major: float = maxf(w, d) / 2.0 - radius_minor
	if radius_major <= radius_minor:
		radius_major = radius_minor + _EPSILON
	if radius_major <= 0.0:
		radius_major = _EPSILON
	if radius_minor <= 0.0:
		radius_minor = _EPSILON
	var p: Dictionary = {"radius_major": radius_major, "radius_minor": radius_minor}
	p["rings"] = int(extra.get("rings", 16))
	p["tube_segments"] = int(extra.get("tube_segments", 8))
	if not is_equal_approx(w, d):
		var max_diam: float = maxf(w, d)
		p["_scale_x"] = w / max_diam
		p["_scale_z"] = d / max_diam
	return p


static func _staircase_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var steps: int = maxi(int(extra.get("steps", 4)), 1)
	var p: Dictionary = {
		"steps": steps,
		"step_width": w,
		"step_height": h / float(steps),
		"step_depth": d / float(steps),
	}
	return p


static func _arch_params(w: float, d: float, h: float, extra: Dictionary) -> Dictionary:
	var max_wh: float = maxf(w, h)
	var outer_radius: float = max_wh / 2.0
	if outer_radius < _EPSILON:
		outer_radius = _EPSILON
	var thickness: float = float(extra.get("thickness", 0.2))
	if thickness >= outer_radius:
		thickness = maxf(_EPSILON, outer_radius * 0.5)
	var p: Dictionary = {
		"outer_radius": outer_radius,
		"thickness": thickness,
		"angle_degrees": float(extra.get("angle_degrees", 180.0)),
		"segments": int(extra.get("segments", 8)),
		"depth": d,
	}
	p["_scale_x"] = w / max_wh
	p["_scale_y"] = 2.0 * h / max_wh
	return p


static func constrain_uniform(
		shape_name: String,
		drawn_width: float,
		drawn_depth: float,
		drawn_height: float,
) -> Dictionary:
	var m: float = maxf(drawn_width, maxf(drawn_depth, drawn_height))
	match shape_name:
		"Cube":
			return {"width": m, "depth": m, "height": m}
		"Plane":
			var mp: float = maxf(drawn_width, drawn_depth)
			return {"width": mp, "depth": mp, "height": 0.0}
		"Cylinder", "Cone":
			return {"width": m, "depth": m, "height": drawn_height}
		"Sphere":
			return {"width": m, "depth": m, "height": m}
		"Torus":
			var h2: float = minf(drawn_height, m * 0.4999)
			return {"width": m, "depth": m, "height": h2}
		"Staircase":
			var mb: float = maxf(drawn_width, drawn_depth)
			return {"width": mb, "depth": mb, "height": drawn_height}
		"Arch":
			var m2: float = maxf(drawn_width, maxf(drawn_depth, drawn_height))
			return {"width": m2, "depth": m2, "height": m2}
		_:
			return {"width": m, "depth": m, "height": m}


static func needs_height_step(shape_name: String) -> bool:
	return shape_name != "Plane"


static func is_radial(shape_name: String) -> bool:
	match shape_name:
		"Cylinder", "Sphere", "Cone", "Torus":
			return true
		_:
			return false


static func needs_ellipsoid_scale(shape_name: String) -> bool:
	match shape_name:
		"Sphere", "Cylinder", "Cone", "Torus", "Arch":
			return true
		_:
			return false


static func ellipsoid_scale(params: Dictionary) -> Vector3:
	if not params.has("_scale_x"):
		return Vector3.ONE
	var sx: float = float(params.get("_scale_x", 1.0))
	var sy: float = float(params.get("_scale_y", 1.0))
	var sz: float = float(params.get("_scale_z", 1.0))
	return Vector3(sx, sy, sz)


static func clean_drawn_params(params: Dictionary) -> Dictionary:
	var p: Dictionary = params.duplicate(true)
	p.erase("_scale_x")
	p.erase("_scale_y")
	p.erase("_scale_z")
	return p