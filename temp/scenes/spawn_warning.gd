class_name SpawnWarning
extends Node2D
## Aviso visual no ponto onde o perseguidor vai nascer: um anel vermelho que fecha
## e um "!" piscando. A fase cria e remove este nó.

var duration := 0.9

var _t := 0.0


func _ready() -> void:
	z_index = 10


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 18.0)
	var color := Color(1.0, 0.25, 0.3, 0.35 + 0.5 * pulse)

	draw_arc(Vector2.ZERO, lerpf(48.0, 16.0, k), 0.0, TAU, 40, color, 3.0)
	draw_circle(Vector2.ZERO, 5.0 + 5.0 * k, Color(color, 0.5))
	# "!"
	draw_rect(Rect2(-3.0, -62.0, 6.0, 18.0), color)
	draw_rect(Rect2(-3.0, -40.0, 6.0, 6.0), color)
