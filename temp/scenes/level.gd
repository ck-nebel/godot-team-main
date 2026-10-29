class_name Level
extends Node2D
## Script de uma fase. Decide ONDE e QUANDO o perseguidor nasce, cuida da meta
## e das condições de derrota (pego, esmagado, caiu).
##
## Estrutura de uma fase (veja scenes/levels/):
##   Player        instância de player.tscn (com uma Camera2D filha)
##   Chaser        instância de chaser.tscn (começa escondido)
##   ChaserSpawns  Node2D com Marker2D filhos: lugares onde o perseguidor PODE nascer
##   Goal          instância de goal.tscn
##
## Regra de nascimento: o perseguidor só nasce em um Marker2D que esteja à ESQUERDA
## do player, a pelo menos `min_spawn_distance` px. Entre os pontos válidos, prefere os que
## estão até `max_spawn_distance` atrás e na mesma faixa de altura, sorteando um diferente
## do último usado. Antes de nascer, aparece um aviso no ponto por `warning_time` segundos.

signal completed
signal failed(reason: String)
signal status_changed(text: String)

enum State { WAITING, WARNING, CHASING, FINISHED }

const RELAX_AFTER := 2.0          # sem ponto válido por esse tempo: aceita pontos mais próximos
const RELAXED_MIN_DISTANCE := 90.0

@export var level_name := "Fase"
@export_multiline var hint := ""

@export_group("Referências")
@export var player: CharacterBody2D
@export var chaser: Chaser
@export var spawn_points_root: Node2D
@export var goal: Goal

@export_group("Perseguidor")
@export var first_spawn_delay := 3.0       ## segundos até o primeiro aparecimento
@export var respawn_delay := 1.0           ## pausa entre sumir e o próximo aviso
@export var warning_time := 0.9            ## duração do aviso antes de nascer
@export var min_spawn_distance := 260.0    ## nunca nasce mais perto que isso (na horizontal)
@export var max_spawn_distance := 900.0    ## prefere pontos até essa distância atrás do player
@export var max_vertical_distance := 260.0 ## prefere pontos nessa faixa de altura do player
@export var show_spawn_points := true      ## desenha os pontos possíveis (útil no protótipo)

@export_group("Derrota")
@export var fall_limit_y := 1000.0

var _state := State.WAITING
var _timer := 0.0
var _retry_time := 0.0
var _first_spawn_done := false
var _spawn_point := Vector2.ZERO
var _pending_marker: Marker2D
var _last_marker: Marker2D
var _warning: SpawnWarning
var _status := ""


func _ready() -> void:
	if player == null:
		player = get_node_or_null("Player") as CharacterBody2D
	if chaser == null:
		chaser = get_node_or_null("Chaser") as Chaser
	if spawn_points_root == null:
		spawn_points_root = get_node_or_null("ChaserSpawns") as Node2D
	if goal == null:
		goal = get_node_or_null("Goal") as Goal
	if player == null or chaser == null:
		push_error("Fase '%s' precisa de um Player e de um Chaser." % name)
		set_physics_process(false)
		return
	if _markers().is_empty():
		push_warning("Fase '%s' não tem pontos de nascimento em ChaserSpawns." % name)

	chaser.target = player
	chaser.fall_limit_y = fall_limit_y
	chaser.vanish()
	chaser.caught_player.connect(_on_chaser_caught_player)
	chaser.needs_respawn.connect(_on_chaser_needs_respawn)

	if player.has_signal("squashed"):
		player.connect("squashed", _on_player_squashed)
	if goal:
		goal.reached.connect(_on_goal_reached)

	_timer = first_spawn_delay
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _state == State.FINISHED:
		return

	if player.global_position.y > fall_limit_y:
		_fail("Você caiu!")
		return

	match _state:
		State.WAITING:
			_timer -= delta
			if _timer > 0.0:
				if not _first_spawn_done:
					_set_status("O perseguidor chega em %d..." % ceili(_timer))
			else:
				_try_begin_warning(delta)
		State.WARNING:
			_timer -= delta
			if _timer <= 0.0:
				_spawn_chaser()


# --- Nascimento do perseguidor ----------------------------------------------------

func _try_begin_warning(delta: float) -> void:
	var marker := _pick_spawn_marker(_retry_time >= RELAX_AFTER)
	if marker == null:
		# Nenhum ponto à esquerda do player (ex.: ele voltou até o começo). Tenta de novo depois.
		_retry_time += delta
		return

	_retry_time = 0.0
	_pending_marker = marker
	_spawn_point = marker.global_position
	_warning = SpawnWarning.new()
	_warning.duration = warning_time
	add_child(_warning)
	_warning.global_position = _spawn_point
	_timer = warning_time
	_state = State.WARNING
	_set_status("Ele está surgindo atrás de você!")


func _spawn_chaser() -> void:
	if is_instance_valid(_warning):
		_warning.queue_free()
	_warning = null

	# O player pode ter recuado durante o aviso: se o ponto ficou perto demais
	# (ou à direita dele), sorteia outro em vez de nascer em cima dele.
	if player.global_position.x - _spawn_point.x < min_spawn_distance * 0.5:
		_state = State.WAITING
		_timer = 0.0
		return

	_last_marker = _pending_marker
	chaser.appear_at(_spawn_point)
	_state = State.CHASING
	_first_spawn_done = true
	_set_status("")


## Escolhe um Marker2D à esquerda do player. Retorna null se não houver nenhum.
func _pick_spawn_marker(relaxed: bool) -> Marker2D:
	var p := player.global_position
	var min_dist := RELAXED_MIN_DISTANCE if relaxed else min_spawn_distance

	var behind: Array[Marker2D] = []
	for m in _markers():
		if m.global_position.x <= p.x - min_dist:
			behind.append(m)
	if behind.is_empty():
		return null

	var pool: Array = []
	if relaxed:
		# Usa o ponto mais à esquerda, o mais longe possível do player.
		var leftmost := behind[0]
		for m in behind:
			if m.global_position.x < leftmost.global_position.x:
				leftmost = m
		pool = [leftmost]
	else:
		for m in behind:
			var dx := p.x - m.global_position.x
			var dy := absf(m.global_position.y - p.y)
			if dx <= max_spawn_distance and dy <= max_vertical_distance:
				pool.append(m)
		if pool.is_empty():
			# Nada na faixa ideal: usa o ponto (atrás do player) mais próximo dele.
			var closest := behind[0]
			for m in behind:
				if m.global_position.distance_squared_to(p) < closest.global_position.distance_squared_to(p):
					closest = m
			pool = [closest]

	# Varia o lugar: evita repetir o último ponto quando há outra opção.
	if pool.size() > 1 and _last_marker in pool:
		pool.erase(_last_marker)

	var chosen: Marker2D = pool.pick_random()
	return chosen


func _markers() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	if spawn_points_root:
		for child in spawn_points_root.get_children():
			if child is Marker2D:
				out.append(child)
	return out


## Posição (global) do perigo atual: o aviso ou o próprio perseguidor. null se não há.
func get_threat_position() -> Variant:
	match _state:
		State.WARNING:
			return _spawn_point
		State.CHASING:
			return chaser.global_position
	return null


# --- Eventos -----------------------------------------------------------------------

func _on_chaser_caught_player(_body: Node2D) -> void:
	_fail("O perseguidor te pegou!")


func _on_chaser_needs_respawn(_reason: String) -> void:
	if _state != State.CHASING:
		return
	chaser.vanish()
	_state = State.WAITING
	_timer = respawn_delay


func _on_player_squashed() -> void:
	_fail("Esmagado!")


func _on_goal_reached(body: Node2D) -> void:
	if body != player or _state == State.FINISHED:
		return
	_finish()
	completed.emit()


func _fail(reason: String) -> void:
	if _state == State.FINISHED:
		return
	_finish()
	failed.emit(reason)


func _finish() -> void:
	_state = State.FINISHED
	_set_status("")
	if is_instance_valid(_warning):
		_warning.queue_free()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	chaser.stop()


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)


# --- Desenho dos pontos de nascimento (protótipo) ----------------------------------

func _draw() -> void:
	if not show_spawn_points:
		return
	var c := Color(1.0, 0.3, 0.35, 0.35)
	for m in _markers():
		var pos := to_local(m.global_position)
		draw_line(pos + Vector2(-6, -6), pos + Vector2(6, 6), c, 2.0)
		draw_line(pos + Vector2(-6, 6), pos + Vector2(6, -6), c, 2.0)
