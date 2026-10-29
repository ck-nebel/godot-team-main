extends Node
## Cena principal: carrega as fases em sequência, mostra o HUD e reinicia ao perder.
## Para adicionar uma fase, crie a cena (copie uma de scenes/levels/) e coloque-a em `levels`.

@export var levels: Array[PackedScene] = []
@export var restart_delay := 0.9
@export var next_level_delay := 1.2

var _index := 0
var _level: Level
var _deaths := 0
var _all_done := false
## Muda a cada troca de fase; invalida esperas (timers) de uma fase anterior.
var _token := 0

@onready var _level_root: Node2D = $LevelRoot
@onready var _indicator: ThreatIndicator = %ThreatIndicator
@onready var _flash: ColorRect = %Flash
@onready var _level_label: Label = %LevelLabel
@onready var _hint_label: Label = %HintLabel
@onready var _status_label: Label = %StatusLabel
@onready var _deaths_label: Label = %DeathsLabel
@onready var _center_label: Label = %CenterLabel


func _ready() -> void:
	if levels.is_empty():
		push_error("Nenhuma fase configurada em Game.levels.")
		return
	_load_level(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		if _all_done:
			_deaths = 0
			_load_level(0)
		else:
			_load_level(_index)
		get_viewport().set_input_as_handled()
		return

	# Atalho de teste: teclas 1..9 pulam direto para a fase.
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var n := int(key.physical_keycode) - int(KEY_1)
		if n >= 0 and n < mini(levels.size(), 9):
			_load_level(n)
			get_viewport().set_input_as_handled()


func _load_level(index: int) -> void:
	_token += 1
	_all_done = false
	if _level:
		_level_root.remove_child(_level)
		_level.queue_free()
		_level = null

	_index = index
	_level = levels[index].instantiate() as Level
	_level_root.add_child(_level)
	_level.completed.connect(_on_level_completed)
	_level.failed.connect(_on_level_failed)
	_level.status_changed.connect(_on_status_changed)
	_indicator.level = _level

	_level_label.text = "Fase %d/%d — %s" % [index + 1, levels.size(), _level.level_name]
	_hint_label.text = _level.hint
	_status_label.text = ""
	_center_label.hide()
	_update_deaths()


func _on_level_failed(reason: String) -> void:
	_deaths += 1
	_update_deaths()
	_show_center(reason)
	_flash_screen()
	_after(restart_delay, _load_level.bind(_index))


func _on_level_completed() -> void:
	if _index + 1 < levels.size():
		_show_center("Fase concluída!")
		_after(next_level_delay, _load_level.bind(_index + 1))
	else:
		_all_done = true
		_show_center("Você escapou!\nMortes: %d\n\nR para jogar de novo" % _deaths)


func _on_status_changed(text: String) -> void:
	_status_label.text = text


func _after(seconds: float, action: Callable) -> void:
	var token := _token
	await get_tree().create_timer(seconds).timeout
	if token == _token:
		action.call()


func _show_center(text: String) -> void:
	_center_label.text = text
	_center_label.show()


func _flash_screen() -> void:
	_flash.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.5)


func _update_deaths() -> void:
	_deaths_label.text = "Mortes: %d" % _deaths
