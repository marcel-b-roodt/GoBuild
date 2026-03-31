## GoBuild debug-logging utility.
##
## All [code][GoBuild][/code] diagnostic prints route through [method log] so
## a single flag silences them in production.
##
## [b]Toggle at runtime:[/b]
## - Check the [b]Debug logging[/b] box at the bottom of the GoBuild panel, or
## - Set [code]GoBuildDebug.enabled = true[/code] directly in the Godot console.
@tool
class_name GoBuildDebug
extends RefCounted

## Master switch.  [code]false[/code] = silent (default).
## All calls to [method log] are no-ops when this is [code]false[/code].
static var enabled: bool = false


## Print [param msg] to the Godot Output panel when [member enabled] is [code]true[/code].
static func log(msg: String) -> void:
	if enabled:
		print(msg)

