extends Camera3D

@export var follow_distance = 5.0
@export var follow_distance_look_back = 8.0  # More distance when looking back
@export var follow_height = 2.0
@export var speed := 20.0
@export var follow_this : Node3D
@export var danger_distance = 10.0
@export var danger_zoom_out = 10.0
@export var normal_follow_distance = 5.0

var is_looking_back := false
var current_distance := 5.0  # Initialize to avoid potential null references

@onready var monster: CharacterBody3D = $"../BigZombie"


func _physics_process(delta : float):
	if not follow_this or not monster:
		return  # Ensure neither follow_this nor monster is null
	
	var distance_to_monster = follow_this.global_position.distance_to(monster.global_position)
	var target_distance = danger_zoom_out if distance_to_monster < danger_distance else normal_follow_distance
	
	# Update looking back state
	is_looking_back = Input.is_action_pressed("look_back")
	
	# Update current_distance based on look_back state
	current_distance = follow_distance_look_back if is_looking_back else follow_distance
	
	# Smooth interpolation for danger zoom
	current_distance = lerp(current_distance, target_distance, delta * 2.0)
	
	var car_forward = -follow_this.global_transform.basis.z
	var car_position = follow_this.global_transform.origin
	
	var follow_direction = car_forward if not is_looking_back else -car_forward
	var target_position = car_position - (follow_direction * current_distance)
	target_position.y = car_position.y + follow_height
	
	# Use lerp() instead of linear_interpolate() for Vector3 in Godot 4.4
	global_position = global_position.lerp(target_position, delta * speed)
	look_at(car_position, Vector3.UP)
