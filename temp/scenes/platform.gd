@tool
extends StaticBody2D
## Bloco fixo do cenário (chão, parede, teto). A origem é o canto SUPERIOR ESQUERDO.
## Mude `size` no Inspetor: a colisão e o desenho acompanham, inclusive no editor.

@export var size := Vector2(200, 24):
	set(value):
		size = Vector2(maxf(value.x, 4.0), maxf(value.y, 4.0))
		_apply()
@export var color := Color(0.93, 0.84, 0.72):
	set(value):
		color = value
		queue_redraw()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var rect := cs.shape as RectangleShape2D
		if rect == null:
			rect = RectangleShape2D.new()
			cs.shape = rect
		rect.size = size
		cs.position = size / 2.0
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, color)
	draw_rect(Rect2(0.0, 0.0, size.x, minf(5.0, size.y)), color.lightened(0.35))
	draw_rect(r, color.darkened(0.35), false, 2.0)
