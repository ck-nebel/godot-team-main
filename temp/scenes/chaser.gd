class_name Chaser
extends CharacterBody2D
## Perseguidor. Corre atrás do `target` (o player).
## ONDE e QUANDO ele aparece é decidido pela fase (level.gd); aqui fica só o comportamento.

## Encostou no player.
signal caught_player(body: Node2D)
## Pede para a fase fazê-lo reaparecer em outro ponto (ficou preso, muito para trás ou caiu).
signal needs_respawn(reason: String)

enum Mode {
	RUNNER, ## Corre e pula; colide com o cenário e com os blocos (dá para bloqueá-lo).
	GHOST,  ## Voa em linha reta e atravessa tudo. Mais lento.
}

const LAYER_CHASER := 4   # camada 3 ("chaser")
const MASK_WORLD := 2     # camada 2 ("world": chão, paredes e blocos)
const APPEAR_TIME := 0.25

@export var mode := Mode.RUNNER:
	set(value):
		mode = value
		if is_node_ready():
			_apply_mode()

@export_group("Corredor")
@export var max_speed := 230.0            ## o player corre a 300
@export var accel := 1500.0
@export var jump_height := 78.0           ## um pouco menos que o pulo do player (85)
@export var time_to_apex := 0.38
@export var fall_gravity_multiplier := 1.5
@export var max_fall_speed := 900.0
@export var ledge_jump := true            ## pula ao chegar na beira de um buraco

@export_group("Fantasma")
@export var ghost_speed := 150.0
@export var ghost_turn_rate := 4.0        ## quão rápido ele corrige a direção

@export_group("Reaparecer")
@export var stuck_time := 2.0             ## janela de tempo para checar se está preso
@export var stuck_distance := 30.0        ## px que precisa andar na horizontal nessa janela
@export var max_lag_distance := 1200.0    ## mais longe que isso do player = reaparece mais perto
@export var fall_limit_y := 1000.0        ## a fase sobrescreve com o próprio limite

@export_group("Visual")
@export var body_color := Color(0.92, 0.22, 0.3)
@export var ghost_color := Color(0.68, 0.45, 1.0, 0.8)

var target: Node2D
var active := false

var _jump_velocity := 0.0
var _gravity := 0.0
var _facing := 1.0
var _stuck_timer := 0.0
var _stuck_origin_x := 0.0
var _anim_t := 0.0
var _appear := 1.0

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hitbox: Area2D = $Hitbox


func _ready() -> void:
	_jump_velocity = -2.0 * jump_height / time_to_apex
	_gravity = 2.0 * jump_height / (time_to_apex * time_to_apex)
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_apply_mode()


# --- Controle pela fase ---------------------------------------------------------

## Faz o perseguidor surgir em `pos` e começar a correr.
func appear_at(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_stuck_timer = 0.0
	_stuck_origin_x = pos.x
	_appear = 0.0
	active = true
	visible = true
	_apply_mode()
	_shape.disabled = false
	_hitbox.set_deferred("monitoring", true)


## Some da fase (fica invisível, sem colisão) até o próximo appear_at().
func vanish() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO
	_shape.set_deferred("disabled", true)
	_hitbox.set_deferred("monitoring", false)


## Para onde está (fim de fase). Continua visível.
func stop() -> void:
	active = false
	velocity = Vector2.ZERO
	_hitbox.set_deferred("monitoring", false)


func _apply_mode() -> void:
	if mode == Mode.GHOST:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = LAYER_CHASER
		collision_mask = MASK_WORLD
	queue_redraw()


# --- Loop de física -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_anim_t += delta
	_appear = minf(_appear + delta / APPEAR_TIME, 1.0)
	queue_redraw()

	if not active or target == null:
		return

	if mode == Mode.GHOST:
		_move_ghost(delta)
	else:
		_move_runner(delta)

	_check_respawn(delta)


func _move_runner(delta: float) -> void:
	var to_target := target.global_position - global_position
	var dir := 0.0
	if absf(to_target.x) > 8.0:
		dir = signf(to_target.x)
		_facing = dir

	velocity.x = move_toward(velocity.x, dir * max_speed, accel * delta)

	if is_on_floor():
		if _should_jump(dir, to_target):
			velocity.y = _jump_velocity
	else:
		var g := _gravity
		if velocity.y > 0.0:
			g *= fall_gravity_multiplier
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)

	move_and_slide()


func _should_jump(dir: float, to_target: Vector2) -> bool:
	if dir == 0.0:
		return to_target.y < -60.0  # player logo acima: pula no lugar
	# Bateu numa parede ou bloco na direção do player.
	if is_on_wall() and signf(get_wall_normal().x) == -dir:
		return true
	# Beira de buraco à frente.
	if ledge_jump and not _has_floor_ahead(dir):
		return true
	# Player perto e mais alto.
	if to_target.y < -50.0 and absf(to_target.x) < 140.0:
		return true
	return false


func _has_floor_ahead(dir: float) -> bool:
	var from := global_position + Vector2(dir * 20.0, 0.0)
	var to := from + Vector2(0.0, 22.0 + 48.0)  # pés ficam em +22; aceita descidas de até 48 px
	var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, [get_rid()])
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _move_ghost(delta: float) -> void:
	var desired := global_position.direction_to(target.global_position) * ghost_speed
	velocity = velocity.lerp(desired, clampf(ghost_turn_rate * delta, 0.0, 1.0))
	if absf(velocity.x) > 5.0:
		_facing = signf(velocity.x)
	global_position += velocity * delta


# --- Reaparecer ----------------------------------------------------------------

func _check_respawn(delta: float) -> void:
	if global_position.y > fall_limit_y:
		needs_respawn.emit("caiu")
		return
	if target.global_position.x - global_position.x > max_lag_distance:
		needs_respawn.emit("ficou para trás")
		return
	if mode == Mode.GHOST:
		return

	_stuck_timer += delta
	if _stuck_timer < stuck_time:
		return
	var moved := absf(global_position.x - _stuck_origin_x)
	# Embaixo do player (ex.: player em cima de um bloco alto) não conta como preso.
	var under_player := absf(target.global_position.x - global_position.x) < 120.0
	_stuck_timer = 0.0
	_stuck_origin_x = global_position.x
	if moved < stuck_distance and not under_player:
		needs_respawn.emit("preso")


func _on_hitbox_body_entered(body: Node2D) -> void:
	if active and body == target:
		caught_player.emit(body)


# --- Visual --------------------------------------------------------------------

func _draw() -> void:
	# "Estica" ao surgir e balança de leve enquanto corre.
	var k := 1.0 - pow(1.0 - _appear, 3.0)
	var stretch := Vector2(lerpf(0.3, 1.0, k), lerpf(1.7, 1.0, k))
	var bob := 0.0
	if active and absf(velocity.x) > 20.0:
		bob = sin(_anim_t * 16.0) * 1.5
	draw_set_transform(Vector2(0.0, bob), 0.0, stretch)

	var c := ghost_color if mode == Mode.GHOST else body_color
	var body := Rect2(-14.0, -22.0, 28.0, 44.0)

	# Chifres
	var horn := PackedVector2Array([Vector2(-14, -22), Vector2(-6, -22), Vector2(-13, -33)])
	draw_colored_polygon(horn, c)
	draw_colored_polygon(Transform2D.FLIP_X * horn, c)
	# Corpo
	draw_rect(body, c)
	draw_rect(body, c.darkened(0.45), false, 2.0)
	# Olhos olhando para onde ele corre
	var eye := Color(1.0, 0.95, 0.4)
	var ex := _facing * 4.0
	draw_rect(Rect2(ex - 9.0, -13.0, 6.0, 6.0), eye)
	draw_rect(Rect2(ex + 3.0, -13.0, 6.0, 6.0), eye)
	# Boca serrilhada
	var mouth := PackedVector2Array()
	for i in 6:
		mouth.append(Vector2(ex - 9.0 + i * 3.6, 2.0 if i % 2 == 0 else 6.0))
	draw_polyline(mouth, c.darkened(0.6), 2.0)

	draw_set_transform(Vector2.ZERO)
