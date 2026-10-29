class_name ThreatIndicator
extends Control
## Seta piscando na borda da tela apontando para o perseguidor (ou para o aviso
## de nascimento) quando ele está fora da tela.

var level: Level

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if level == null or not is_instance_valid(level):
		return
	var threat: Variant = level.get_threat_position()
	if threat == null:
		return

	var threat_pos: Vector2 = threat
	var screen: Vector2 = get_viewport().get_canvas_transform() * threat_pos
	if Rect2(Vector2.ZERO, size).has_point(screen):
		return

	var margin := 26.0
	var p := Vector2(
		clampf(screen.x, margin, size.x - margin),
		clampf(screen.y, margin, size.y - margin)
	)
	var dir := (screen - p).normalized()
	var side := dir.orthogonal() * 11.0
	var col := Color(1.0, 0.25, 0.3, 0.55 + 0.45 * sin(_t * 10.0))
	var tip := p + dir * 14.0
	var back := p - dir * 8.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)
