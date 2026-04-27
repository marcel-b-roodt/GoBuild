## Prototype blockout materials for GoBuild.
##
## Provides lazy-initialised [StandardMaterial3D] presets suitable for
## greyboxing.  All materials are created once per editor session and cached.
##
## The checker texture tiles at 1 texture repeat per UV unit; combined with
## the default UV scale of 1.0 this means one checker repeat = one mesh unit
## (≈ one metre), giving immediate visual scale feedback while blocking out.
##
## Usage:
##   var mat := GoBuildMaterials.checker_material()
##   MaterialAssignOperation.apply(mesh, selected_faces, 0, mat)
@tool
class_name GoBuildMaterials
extends RefCounted

## Size of the checker texture in pixels.  Must be a power of 2.
const _TEX_SIZE: int = 256

## Size of each individual checker cell in pixels.
## 32 px out of 256 px = 1/8 of the tile; at scale 1.0 that is 12.5 cm per cell.
const _CELL_SIZE: int = 32

## Cached prototype materials.  Null until first requested.
static var _checker: StandardMaterial3D = null
static var _white: StandardMaterial3D = null
static var _grey: StandardMaterial3D = null


## Return a [StandardMaterial3D] whose albedo is a black-and-white checker
## texture.  One texture tile spans one UV unit (one mesh unit at default UV
## scale), making it easy to gauge metre-scale proportions during blockout.
##
## The returned material is cached; the same instance is returned on every call.
static func checker_material() -> StandardMaterial3D:
	if _checker != null:
		return _checker
	var img := Image.create(_TEX_SIZE, _TEX_SIZE, false, Image.FORMAT_RGB8)
	for y: int in _TEX_SIZE:
		for x: int in _TEX_SIZE:
			var cx: int = x / _CELL_SIZE
			var cy: int = y / _CELL_SIZE
			var light: bool = (cx + cy) % 2 == 0
			img.set_pixel(x, y, Color.WHITE if light else Color(0.3, 0.3, 0.3))
	var tex := ImageTexture.create_from_image(img)
	_checker = StandardMaterial3D.new()
	_checker.albedo_texture = tex
	# Nearest-neighbour filtering preserves sharp cell edges at normal distances.
	_checker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return _checker


## Return a solid-white [StandardMaterial3D] for non-textured blockout faces.
static func white_material() -> StandardMaterial3D:
	if _white != null:
		return _white
	_white = StandardMaterial3D.new()
	_white.albedo_color = Color.WHITE
	return _white


## Return a mid-grey [StandardMaterial3D] for default blockout geometry.
static func grey_material() -> StandardMaterial3D:
	if _grey != null:
		return _grey
	_grey = StandardMaterial3D.new()
	_grey.albedo_color = Color(0.5, 0.5, 0.5)
	return _grey
