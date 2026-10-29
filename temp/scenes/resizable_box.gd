extends RigidBody2D

signal resize_started
signal resize_finished

@export var box_size := Vector2(120, 120):
	set(value):
		box_size = value
		if is_node_ready():
			_apply_size()
@export var color := Color(0.29, 0.56, 0.89)
## Se falso, o bloco não pode ser editado pelo jogador.
@export var resizable := true
## Blocos girando atrapalham o redimensionamento e o player em cima deles.
@export var allow_rotation := false

@export_group("Redimensionamento")
@export var min_box_size := Vector2(40, 40)
@export var max_box_size := Vector2(600, 600)
## 0 = livre. Ex.: 20 faz o tamanho encaixar em múltiplos de 20 px.
@export var snap_step := 0.0
## Velocidade máxima de cada borda (px/s). Mais baixo = física mais estável.
@export var max_resize_speed := 900.0
## Espessura (px) da área de pegar em cada borda.
@export var edge_margin := 8.0
## Quantos corpos empilhados o bloco consegue empurrar ao crescer.
@export var max_push_chain := 3

@export_group("Física")
## Massa por pixel², então blocos maiores são mais pesados.
@export var density := 0.0001
@export var min_mass := 0.01

const LEFT := 1
const RIGHT := 2
const TOP := 4
const BOTTOM := 8
## Recuo lateral das faixas de teste, para não detectar vizinhos que só encostam.
const INSET := 1.0

## Bloco sendo arrastado agora (só um por vez).
static var _active: RigidBody2D = null

var _drag_edges := 0
var _hover_edges := 0
var _drag_start_mouse := Vector2.ZERO
var _drag_start_size := Vector2.ZERO
## Transform do bloco no momento em que foi agarrado; todo o cálculo é feito nesse referencial.
var _drag_frame := Transform2D()
## Retângulo atual do bloco no referencial de _drag_frame.
var _rect := Rect2()
var _wake_pending := false
var _query_shape := RectangleShape2D.new()

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Cada instância precisa da própria shape, senão redimensionar um bloco redimensiona todos.
	_shape.shape = _shape.shape.duplicate()
	lock_rotation = not allow_rotation
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	_apply_size()


func _exit_tree() -> void:
	if _active == self:
		_active = null
	if _hover_edges or _drag_edges:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _notification(what: int) -> void:
	# Se a janela perder o foco no meio do arrasto, o "soltar" nunca chega.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _drag_edges:
		_end_drag()


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if event.pressed:
		if not resizable or _active != null:
			return
		var edges := _edges_at(get_local_mouse_position())
		if edges:
			_begin_drag(edges)
			get_viewport().set_input_as_handled()
	elif _drag_edges:
		_end_drag()
		get_viewport().set_input_as_handled()


func _begin_drag(edges: int) -> void:
	_active = self
	_drag_edges = edges
	# Segura o bloco parado enquanto ele é redimensionado.
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_drag_frame = global_transform
	_drag_start_mouse = get_local_mouse_position()
	_drag_start_size = box_size
	_rect = Rect2(-box_size / 2.0, box_size)
	queue_redraw()
	resize_started.emit()


func _end_drag() -> void:
	_drag_edges = 0
	if _active == self:
		_active = null
	freeze = false
	sleeping = false
	_wake_pending = true
	queue_redraw()
	resize_finished.emit()


# --- Loop de física -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _wake_pending:
		_wake_pending = false
		_wake_neighbors()

	if not _drag_edges:
		_update_hover()
		return

	var target := _target_rect()
	var next := _step_toward(_rect, target, max_resize_speed * delta)
	next = _clamp_to_free_space(_rect, next)
	if not next.is_equal_approx(_rect):
		_set_rect(next)


## Retângulo que o mouse está pedindo, já com mínimo, máximo e snap aplicados.
func _target_rect() -> Rect2:
	var mouse := _drag_frame.affine_inverse() * get_global_mouse_position()
	var d := mouse - _drag_start_mouse
	var half := _drag_start_size / 2.0
	var l := -half.x
	var t := -half.y
	var r := half.x
	var b := half.y

	if _drag_edges & LEFT:
		l = r - _clamp_length(r - (l + d.x), min_box_size.x, max_box_size.x)
	if _drag_edges & RIGHT:
		r = l + _clamp_length((r + d.x) - l, min_box_size.x, max_box_size.x)
	if _drag_edges & TOP:
		t = b - _clamp_length(b - (t + d.y), min_box_size.y, max_box_size.y)
	if _drag_edges & BOTTOM:
		b = t + _clamp_length((b + d.y) - t, min_box_size.y, max_box_size.y)

	return Rect2(l, t, r - l, b - t)


func _clamp_length(length: float, lo: float, hi: float) -> float:
	if snap_step > 0.0:
		length = snappedf(length, snap_step)
	return clampf(length, lo, hi)


## Move cada borda em direção ao alvo, no máximo `step` pixels.
func _step_toward(from: Rect2, to: Rect2, step: float) -> Rect2:
	var l := move_toward(from.position.x, to.position.x, step)
	var t := move_toward(from.position.y, to.position.y, step)
	var r := move_toward(from.end.x, to.end.x, step)
	var b := move_toward(from.end.y, to.end.y, step)
	return Rect2(l, t, r - l, b - t)


func _set_rect(r: Rect2) -> void:
	_rect = r
	# A origem do corpo é o centro do bloco: move-a para manter as bordas opostas fixas.
	global_position = _drag_frame * r.get_center()
	box_size = r.size
	_wake_neighbors()


# --- Colisão ao crescer -------------------------------------------------------

## Se o crescimento até `to` bate em algo, encontra (busca binária) o maior passo possível.
func _clamp_to_free_space(from: Rect2, to: Rect2) -> Rect2:
	if _growth_is_free(from, to):
		return to
	var lo := 0.0
	var hi := 1.0
	for i in 8:
		var mid := (lo + hi) * 0.5
		if _growth_is_free(from, _lerp_rect(from, to, mid)):
			lo = mid
		else:
			hi = mid
	return _lerp_rect(from, to, lo)


func _lerp_rect(a: Rect2, b: Rect2, t: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, t), a.size.lerp(b.size, t))


## Testa só a área NOVA que o bloco passaria a ocupar (uma faixa por borda que cresce).
## Encolher é sempre permitido.
func _growth_is_free(from: Rect2, to: Rect2) -> bool:
	var w := maxf(to.size.x - 2.0 * INSET, 0.01)
	var h := maxf(to.size.y - 2.0 * INSET, 0.01)

	if to.position.x < from.position.x:
		var strip := Rect2(to.position.x, to.position.y + INSET, from.position.x - to.position.x, h)
		if not _strip_is_free(strip, Vector2.LEFT):
			return false
	if to.end.x > from.end.x:
		var strip := Rect2(from.end.x, to.position.y + INSET, to.end.x - from.end.x, h)
		if not _strip_is_free(strip, Vector2.RIGHT):
			return false
	if to.position.y < from.position.y:
		var strip := Rect2(to.position.x + INSET, to.position.y, w, from.position.y - to.position.y)
		if not _strip_is_free(strip, Vector2.UP):
			return false
	if to.end.y > from.end.y:
		var strip := Rect2(to.position.x + INSET, from.end.y, w, to.end.y - from.end.y)
		if not _strip_is_free(strip, Vector2.DOWN):
			return false
	return true


func _strip_is_free(strip: Rect2, dir_local: Vector2) -> bool:
	var thickness := strip.size.x if dir_local.x != 0.0 else strip.size.y
	if thickness < 0.01:
		return true

	var params := PhysicsShapeQueryParameters2D.new()
	_query_shape.size = strip.size
	params.shape = _query_shape
	params.transform = _drag_frame * Transform2D(0.0, strip.get_center())
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]

	var push := _drag_frame.basis_xform(dir_local).normalized() * (thickness + 1.0)
	var hits := get_world_2d().direct_space_state.intersect_shape(params, 16)
	for hit in hits:
		var body := hit["collider"] as PhysicsBody2D
		if body == null or not _is_pushable(body):
			return false  # parede, chão, TileMap, bloco congelado...
		if not _can_be_pushed(body, push, max_push_chain):
			return false  # player/caixa sem espaço para sair: não esmaga
	return true


func _is_pushable(body: PhysicsBody2D) -> bool:
	if body is CharacterBody2D:
		return true
	if body is RigidBody2D:
		return not (body as RigidBody2D).freeze
	return false


## O corpo consegue se mover `motion` sem bater em nada fixo? Segue pilhas de corpos empurráveis.
func _can_be_pushed(body: PhysicsBody2D, motion: Vector2, depth: int) -> bool:
	var collision := KinematicCollision2D.new()
	if not body.test_move(body.global_transform, motion, collision):
		return true
	var other := collision.get_collider() as PhysicsBody2D
	if other == null or other == self or depth <= 0 or not _is_pushable(other):
		return false
	return _can_be_pushed(other, motion - collision.get_travel(), depth - 1)


## Acorda corpos encostados, senão um bloco em cima de outro que encolheu fica flutuando.
func _wake_neighbors() -> void:
	var params := PhysicsShapeQueryParameters2D.new()
	_query_shape.size = box_size + Vector2.ONE * 8.0
	params.shape = _query_shape
	params.transform = global_transform
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 32):
		var body := hit["collider"] as RigidBody2D
		if body and not body.freeze:
			body.sleeping = false


# --- Tamanho e desenho --------------------------------------------------------

func _apply_size() -> void:
	(_shape.shape as RectangleShape2D).size = box_size
	mass = maxf(box_size.x * box_size.y * density, min_mass)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-box_size / 2.0, box_size)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.4), false, 2.0)

	var edges := _drag_edges if _drag_edges else _hover_edges
	if not edges:
		return
	var hl := color.lightened(0.6)
	var w := 4.0
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var bl := Vector2(rect.position.x, rect.end.y)
	var br := rect.end
	if edges & LEFT:
		draw_line(tl, bl, hl, w)
	if edges & RIGHT:
		draw_line(tr, br, hl, w)
	if edges & TOP:
		draw_line(tl, tr, hl, w)
	if edges & BOTTOM:
		draw_line(bl, br, hl, w)


# --- Hover e cursor -----------------------------------------------------------

func _update_hover() -> void:
	var edges := 0
	if resizable and (_active == null or _active == self):
		edges = _edges_at(get_local_mouse_position())
	if edges == _hover_edges:
		return

	var was_hovering := _hover_edges != 0
	_hover_edges = edges
	if edges:
		Input.set_default_cursor_shape(_cursor_for(edges))
	elif was_hovering:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	queue_redraw()


func _edges_at(local_pos: Vector2) -> int:
	var half := box_size / 2.0
	if absf(local_pos.x) > half.x + edge_margin or absf(local_pos.y) > half.y + edge_margin:
		return 0
	var edges := 0
	if local_pos.x <= -half.x + edge_margin:
		edges |= LEFT
	elif local_pos.x >= half.x - edge_margin:
		edges |= RIGHT
	if local_pos.y <= -half.y + edge_margin:
		edges |= TOP
	elif local_pos.y >= half.y - edge_margin:
		edges |= BOTTOM
	return edges


func _cursor_for(edges: int) -> Input.CursorShape:
	if edges == LEFT | TOP or edges == RIGHT | BOTTOM:
		return Input.CURSOR_FDIAGSIZE
	if edges == RIGHT | TOP or edges == LEFT | BOTTOM:
		return Input.CURSOR_BDIAGSIZE
	if edges == LEFT or edges == RIGHT:
		return Input.CURSOR_HSIZE
	return Input.CURSOR_VSIZE
