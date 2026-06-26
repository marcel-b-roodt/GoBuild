## Pure helpers for building overlay hint and panel context label strings.
##
## All methods are static, headless-safe, and have no editor-API dependencies.
## The calling code (plugin.gd) reads live state (modifier keys, selection
## mode, transform mode) and passes it in as plain values.
##
## Transform-mode integers match [enum GoBuildGizmoPlugin.TransformMode]:
##   TRANSLATE = 0, ROTATE = 1, SCALE = 2.
## They are kept as plain ints here so this helper has no dependency on the
## editor-only GoBuildGizmoPlugin class and can run in headless test contexts.
@tool
class_name OverlayHintHelper
extends RefCounted

# ---------------------------------------------------------------------------
# Self-preloads — dependency order matters.
#
# overlay_hint_helper.gd ('o') is compiled before selection_manager.gd
# ('se_m') in the core/ alphabetical scan. Explicit preload here ensures
# SelectionManager and its Mode enum are registered before any typed
# reference in function signatures below.
# ---------------------------------------------------------------------------
const _SEL_MGR_SCRIPT := preload("res://addons/go_build/core/selection_manager.gd")

## Integer aliases matching [enum GoBuildGizmoPlugin.TransformMode].
## GoBuildGizmoPlugin is excluded here to keep this helper headless-safe.
const TRANSLATE: int = 0
const ROTATE:    int = 1
const SCALE:     int = 2


# ---------------------------------------------------------------------------
# Overlay hint (bottom-left label)
# ---------------------------------------------------------------------------

## Build the bottom-left overlay hint string.
##
## [param mode]  — current selection mode.
## [param tmode] — current transform mode as an int (TRANSLATE / ROTATE / SCALE).
## [param shift] / [param ctrl] — modifier key states.
## Returns an empty string when [param mode] is OBJECT.
static func build_hint(
		mode: SelectionManager.Mode,
		tmode: int,
		shift: bool,
		ctrl: bool) -> String:
	if mode == SelectionManager.Mode.OBJECT:
		return ""

	var mode_label: String
	match mode:
		SelectionManager.Mode.VERTEX: mode_label = "Vertex"
		SelectionManager.Mode.EDGE:   mode_label = "Edge"
		_:                            mode_label = "Face"

	var op: String
	match tmode:
		ROTATE:
			op = "Rotate"
		SCALE:
			if shift and mode == SelectionManager.Mode.FACE:
				op = "■ INSET"
			elif ctrl:
				op = "■ SNAP"
			else:
				op = "Scale    Shift+Centre: Uniform"
		_:  # TRANSLATE
			if shift:
				match mode:
					SelectionManager.Mode.FACE: op = "■ EXTRUDE"
					SelectionManager.Mode.EDGE: op = "■ EXTRUDE EDGE"
					_:                          op = "Move"
			elif ctrl:
				op = "■ SNAP"
			else:
				op = "Move"

	var hints: Array[String] = []
	if not shift and not ctrl:
		match tmode:
			TRANSLATE:
				if mode == SelectionManager.Mode.FACE:
					hints.append("Shift: Extrude")
				elif mode == SelectionManager.Mode.EDGE:
					hints.append("Shift: Extrude Edge")
				hints.append("Ctrl+Click: Toggle  Ctrl+Drag: Snap")
				hints.append("Alt: Vertex Snap")
				hints.append("Ctrl+=: Grow  Ctrl+-: Shrink")
				if mode == SelectionManager.Mode.EDGE:
					hints.append("Alt+Click: Loop (cycle)  Ctrl+Alt+Click: Ring")
				elif mode == SelectionManager.Mode.FACE:
					hints.append("Alt+Click: Path  Shift+Alt: Add to path  Ctrl+Alt+Click: Ring")
			SCALE:
				if mode == SelectionManager.Mode.FACE:
					hints.append("Shift: Inset")
				hints.append("Ctrl+Click: Toggle  Ctrl+Drag: Snap")
				hints.append("Ctrl+=: Grow  Ctrl+-: Shrink")
				if mode == SelectionManager.Mode.EDGE:
					hints.append("Alt+Click: Loop (cycle)  Ctrl+Alt+Click: Ring")
				elif mode == SelectionManager.Mode.FACE:
					hints.append("Alt+Click: Path  Shift+Alt: Add to path  Ctrl+Alt+Click: Ring")
	elif shift:
		hints.append("+Ctrl: Snap")

	if hints.is_empty():
		return "%s  ·  %s" % [mode_label, op]
	return "%s  ·  %s    %s" % [mode_label, op, "  ".join(hints)]


# ---------------------------------------------------------------------------
# Panel context label
# ---------------------------------------------------------------------------

## Build the panel context label string.
##
## Returns an empty string when [param mode] is OBJECT, or when no meaningful
## operation name applies.
static func build_panel_context(
		mode: SelectionManager.Mode,
		tmode: int,
		shift: bool,
		ctrl: bool,
		alt_key: bool) -> String:
	if mode == SelectionManager.Mode.OBJECT:
		return ""

	var result: String
	match tmode:
		ROTATE:
			result = "■ Snap" if ctrl else "Rotate"
		SCALE:
			if shift and mode == SelectionManager.Mode.FACE:
				result = "■ Inset"
			elif ctrl:
				result = "■ Snap"
			else:
				result = "Scale"
		_:  # TRANSLATE
			if alt_key:
				result = "■ Alt Vertex Snap"
			elif ctrl:
				result = "■ Snap"
			elif shift:
				match mode:
					SelectionManager.Mode.FACE: result = "■ Extrude"
					SelectionManager.Mode.EDGE: result = "■ Extrude Edge"
					_:                          result = "Move"
			else:
				result = "Move"

	return result
