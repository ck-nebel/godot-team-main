extends CharacterBody2D

## Emitido quando o player fica preso entre duas superfícies (ex.: bloco crescendo contra o teto).
signal squashed

@export_group("Movimento horizontal")
@export var max_speed := 300.0
@export var ground_accel := 2400.0     ## px/s² ao acelerar no chão
@export var ground_decel := 3200.0     ## px/s² ao soltar o direcional no chão
@export var air_accel := 1600.0
@export var air_decel := 900.0
@export var turn_multiplier := 1.6     ## aceleração extra ao inverter direção

@export_group("Pulo")
@export var jump_height := 85.0              ## altura do pulo em pixels (pulo completo)
@export var time_to_apex := 0.4              ## segundos até o ponto mais alto
@export var fall_gravity_multiplier := 1.7   ## queda mais pesada que a subida
@export var jump_cut_multiplier := 0.45      ## quanto do impulso sobra ao soltar o botão
@export var apex_threshold := 40.0           ## |vel.y| abaixo disso = perto do ápice
@export var apex_gravity_multiplier := 0.6   ## "flutuada" no ápice
@export var max_fall_speed := 900.0
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Empurrar blocos")
@export var push_force := 900.0          ## força aplicada no bloco (a = F / massa)
@export var max_push_speed := 140.0      ## velocidade máxima que o player consegue dar ao bloco
@export var push_speed_penalty := 0.6    ## player anda mais devagar empurrando

@export_group("Esmagamento")
@export var respawn_on_squash := true
@export var squash_frames := 4           ## frames seguidos espremido para contar como esmagado

@export_group("Visual")
@export var visual: Node2D               ## Sprite2D ou AnimatedSprite2D (opcional)

var _jump_velocity: float
var _jump_gravity: float
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _is_jumping := false
var _is_pushing := false
var _squash_counter := 0
var _spawn_position: Vector2


func _ready() -> void:
	_recalculate_jump()
	_spawn_position = global_position
	floor_snap_length = 6.0  # mantém o player colado ao descer degraus/bordas de blocos


## Chame isto se alterar jump_height/time_to_apex em tempo de execução.
func _recalculate_jump() -> void:
	_jump_velocity = -2.0 * jump_height / time_to_apex
	_jump_gravity = 2.0 * jump_height / (time_to_apex * time_to_apex)


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("left", "right")

	_update_timers(delta)
	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal(direction, delta)

	var intended_vx := velocity.x
	move_and_slide()

	_push_bodies(direction, intended_vx)
	_check_squash()
	_update_visual(direction)


# --- Timers -----------------------------------------------------------------

func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		_is_jumping = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("up"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


# --- Gravidade e pulo ---------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return

	var g := _jump_gravity
	if _is_jumping and absf(velocity.y) < apex_threshold and Input.is_action_pressed("up"):
		g *= apex_gravity_multiplier
	elif velocity.y > 0.0:
		g *= fall_gravity_multiplier

	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _handle_jump() -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = _jump_velocity
		_is_jumping = true
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Pulo variável: soltar o botão durante a subida corta o pulo.
	if _is_jumping and Input.is_action_just_released("up") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


# --- Movimento horizontal -----------------------------------------------------

func _handle_horizontal(direction: float, delta: float) -> void:
	var target := direction * max_speed
	if _is_pushing:
		target *= push_speed_penalty

	var accel: float
	if direction != 0.0:
		accel = ground_accel if is_on_floor() else air_accel
		if velocity.x != 0.0 and signf(direction) != signf(velocity.x):
			accel *= turn_multiplier
	else:
		accel = ground_decel if is_on_floor() else air_decel

	velocity.x = move_toward(velocity.x, target, accel * delta)


# --- Empurrar blocos ----------------------------------------------------------

func _push_bodies(direction: float, intended_vx: float) -> void:
	_is_pushing = false
	if direction == 0.0:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody2D
		if body == null:
			continue

		var normal := collision.get_normal()
		# Só contato lateral (ignora quando está em cima ou embaixo do bloco).
		if absf(normal.x) < 0.7:
			continue
		# Só empurra se estiver andando CONTRA o bloco.
		var push_dir := -signf(normal.x)
		if signf(direction) != push_dir:
			continue

		_is_pushing = true

		# Limita a velocidade do bloco; força constante => blocos pesados aceleram menos.
		var body_vx := body.linear_velocity.x * push_dir
		if body_vx < max_push_speed:
			body.apply_central_force(Vector2(push_dir * push_force, 0.0))

	# Evita que a colisão zere o embalo do player a cada frame enquanto empurra.
	if _is_pushing:
		velocity.x = intended_vx


# --- Esmagamento --------------------------------------------------------------

func _check_squash() -> void:
	var crushed := is_on_floor() and is_on_ceiling()

	if not crushed:
		var count := get_slide_collision_count()
		for a in count:
			var na := get_slide_collision(a).get_normal()
			for b in range(a + 1, count):
				if na.dot(get_slide_collision(b).get_normal()) < -0.8:
					crushed = true
					break
			if crushed:
				break

	_squash_counter = _squash_counter + 1 if crushed else 0

	if _squash_counter >= squash_frames:
		_squash_counter = 0
		squashed.emit()
		if respawn_on_squash:
			respawn()


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_is_jumping = false
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0


# --- Visual -------------------------------------------------------------------

func _update_visual(direction: float) -> void:
	if visual == null or direction == 0.0:
		return
	if "flip_h" in visual:
		visual.set("flip_h", direction < 0.0)
