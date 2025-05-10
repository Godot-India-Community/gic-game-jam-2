extends Node3D


@onready var game_over: Control = $GameOver
@onready var label: Label = $CanvasLayer/Label


func _ready() -> void:
	game_over.hide()

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("Hide"):
		label.visible = not label.visible
		
	if Input.is_action_just_pressed("Restart"):
		get_tree().reload_current_scene()

func _on_area_3d_body_entered(body: Node3D) -> void:
	game_over.visible = true
	get_tree().paused = true


func _on_restart_game_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
