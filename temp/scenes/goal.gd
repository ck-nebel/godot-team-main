@tool
class_name Goal
extends Area2D
## Saída da fase. Quando o player entra, a fase é concluída.

signal reached(body: Node2D)

@export var size := Vector2(40, 72):
	set(value):
		size = value
		queue_redraw()

var _t := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(func(body: Node2D) -> void: reached.emit(body))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	var glow := 0.5 + 0.5 * sin(_t * 3.0)
	draw_rect(rect.grow(6.0 + 4.0 * glow), Color(0.4, 1.0, 0.6, 0.10 + 0.10 * glow))
	draw_rect(rect, Color(0.18, 0.75, 0.45))
	draw_rect(rect.grow(-6.0), Color(0.07, 0.2, 0.13))
	draw_rect(rect, Color(0.6, 1.0, 0.75), false, 2.0)
	# Seta apontando para dentro
	var c := Color(0.6, 1.0, 0.75, 0.6 + 0.4 * glow)
	var mid := rect.get_center()
	draw_colored_polygon(PackedVector2Array([
		mid + Vector2(-7, -10), mid + Vector2(7, 0), mid + Vector2(-7, 10)
	]), c)
