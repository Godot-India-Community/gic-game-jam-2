extends CharacterBody3D

class_name Monster

@export var look_speed := 5.0


# Export variables for tweaking in the editor
@export var chase_speed: float = 15.0
@export var roaming_speed: float = 5.0
@export var acceleration: float = 2.0
@export var attack_distance: float = 10.0
@export var attack_cooldown: float = 2.0
@export var damage: int = 25
@export var detection_radius: float = 60.0
@export var health: int = 100
@export var city_nav_mesh_path: NodePath
@export_range(0.0, 1.0) var aggression_level: float = 0.7  # Higher means more aggressive

# Node references
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $DetectionArea
@onready var roar_timer: Timer = $RoarTimer
@onready var waste_attack_area: Area3D = $WasteAttackArea

# State variables
var target = null
var player_car = null
var current_speed: float = roaming_speed
var attack_timer: float = 0.0
var is_dead: bool = false
var is_attacking: bool = false
var can_roar: bool = true
var rng = RandomNumberGenerator.new()
var wander_point: Vector3 = Vector3.ZERO
var city_nav_mesh = null

# Monster states
enum MonsterState {
	ROAMING,
	CHASING,
	ATTACKING,
	DEAD
}

var current_state = MonsterState.ROAMING

func _ready() -> void:

	rng.randomize()
	
	# Connect signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	waste_attack_area.body_entered.connect(_on_waste_attack_area_body_entered)
	roar_timer.timeout.connect(_on_roar_timer_timeout)
	
	# Set up navigation
	if city_nav_mesh_path:
		city_nav_mesh = get_node(city_nav_mesh_path)
	
	# Find player car
	player_car = get_tree().get_nodes_in_group("player_car").front()
	if player_car:
		print("Monster: Found player car")
	
	# Set up navigation agent properties
	navigation_agent.path_desired_distance = 2.0
	navigation_agent.target_desired_distance = 2.0
	navigation_agent.avoidance_enabled = true
	
	# Initial wandering point
	set_new_wander_point()
	
	# Start with a roar
	play_animation("roar")
	roar_timer.start(rng.randf_range(10.0, 20.0))

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	attack_timer = max(0.0, attack_timer - delta)
	
	match current_state:
		MonsterState.ROAMING:
			handle_roaming(delta)
		MonsterState.CHASING:
			handle_chasing(delta)
		MonsterState.ATTACKING:
			handle_attacking(delta)

func handle_roaming(delta: float) -> void:
	# Slow movement while roaming
	current_speed = move_toward(current_speed, roaming_speed, acceleration * delta)
	
	if !navigation_agent.is_navigation_finished():
		var next_location = navigation_agent.get_next_path_position()
		var direction = (next_location - global_position).normalized()
		
		# Apply velocity
		velocity = direction * current_speed
		look_at_smoothly(global_position + direction, delta)
		
		# Only play run animation if actually moving
		if velocity.length() > 0.5 and animation_player.current_animation != "run":
			play_animation("run")
			
		move_and_slide()
	else:
		# Reached destination, set new wander point
		set_new_wander_point()
		
	# Random chance to roar while roaming
	if can_roar and rng.randf() < 0.002:  # Small chance per frame
		play_animation("roar")
		can_roar = false
		roar_timer.start(rng.randf_range(15.0, 30.0))
		
	# Check if player is in natural detection range even without collision trigger
	if player_car and global_position.distance_to(player_car.global_position) < detection_radius:
		set_target(player_car)

func handle_chasing(delta: float) -> void:
	if !target or !is_instance_valid(target):
		current_state = MonsterState.ROAMING
		set_new_wander_point()
		return
		
	var distance_to_target = global_position.distance_to(target.global_position)
	
	# Attack if close enough
	if distance_to_target < attack_distance and attack_timer <= 0:
		current_state = MonsterState.ATTACKING
		return
		
	# Chase target
	current_speed = move_toward(current_speed, chase_speed, acceleration * delta)
	
	# Update navigation target
	navigation_agent.target_position = target.global_position
	
	if !navigation_agent.is_navigation_finished():
		var next_location = navigation_agent.get_next_path_position()
		var direction = (next_location - global_position).normalized()
		
		# Apply velocity with some randomness to make movement more natural
		var random_offset = Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * 0.2
		direction = (direction + random_offset).normalized()
		
		velocity = direction * current_speed
		look_at_smoothly(global_position + direction, delta)
		
		if animation_player.current_animation != "run":
			play_animation("run")
			
		move_and_slide()
		
	# Random chance to roar while chasing (more aggressive)
	if can_roar and rng.randf() < 0.005:  # Higher chance during chase
		play_animation("roar")
		can_roar = false
		roar_timer.start(rng.randf_range(5.0, 15.0))

func handle_attacking(delta: float) -> void:
	if !target or !is_instance_valid(target):
		current_state = MonsterState.ROAMING
		set_new_wander_point()
		return
		
	var distance_to_target = global_position.distance_to(target.global_position)
	
	# Look at target when attacking
	look_at_smoothly(target.global_position, delta * 3.0)
	
	# Start attack animation if not already attacking
	if !is_attacking:
		# Choose between regular attack and waste attack
		if rng.randf() < 0.3:  # 30% chance for waste attack
			play_animation("waste")
		else:
			play_animation("attack")
		
		is_attacking = true
		attack_timer = attack_cooldown
		
	# If target moves away during attack, resume chase
	if distance_to_target > attack_distance * 1.5:
		current_state = MonsterState.CHASING
		is_attacking = false

func take_damage(amount: int) -> void:
	health -= amount
	
	# Flash or visual feedback can be added here
	
	if health <= 0 and !is_dead:
		die()
	else:
		# Getting hit increases aggression - instantly chase player
		if player_car:
			set_target(player_car)
			
		# Chance to roar when hit
		if can_roar and rng.randf() < 0.7:
			play_animation("roar")
			can_roar = false
			roar_timer.start(rng.randf_range(5.0, 10.0))

func die() -> void:
	is_dead = true
	current_state = MonsterState.DEAD
	
	# Stop all movement
	velocity = Vector3.ZERO
	
	# Play death animation
	play_animation("dead")
	
	# Disable collision and physics
	collision_layer = 0
	collision_mask = 0
	
	# Optional: Remove monster after animation (can be triggered at end of animation)
	var death_timer = get_tree().create_timer(5.0)
	death_timer.timeout.connect(func(): queue_free())

func set_target(new_target) -> void:
	target = new_target
	if target:
		current_state = MonsterState.CHASING
		navigation_agent.target_position = target.global_position

func set_new_wander_point() -> void:
	# Get a random point in the city to wander to
	var random_range = 30.0
	var attempt = 0
	var valid_point = false
	
	while !valid_point and attempt < 10:
		attempt += 1
		
		# Generate random point around current position
		wander_point = global_position + Vector3(
			rng.randf_range(-random_range, random_range),
			0, 
			rng.randf_range(-random_range, random_range)
		)
		
		# Ensure point is on navmesh
		if city_nav_mesh:
			wander_point.y = city_nav_mesh.get_closest_point(wander_point).y
			valid_point = true
		else:
			# Fallback if no navmesh
			wander_point.y = global_position.y
			valid_point = true
	
	# Set navigation target
	navigation_agent.target_position = wander_point

func play_animation(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		
		# Connect signal for attack and waste animations to know when they finish
		if anim_name == "attack" or anim_name == "waste" or anim_name == "roar":
			# Wait until animation finishes
			await animation_player.animation_finished
			
			is_attacking = false
			
			# Return to chase state after attack finishes
			if current_state == MonsterState.ATTACKING:
				current_state = MonsterState.CHASING

func look_at_smoothly(target: Vector3, delta: float):
	if global_transform.origin.is_equal_approx(target):
		return

	var target_flat = target
	target_flat.y = global_transform.origin.y  # Ignore Y so it doesn't look down
	var new_transform = global_transform.looking_at(target_flat, Vector3.UP)
	global_transform = global_transform.interpolate_with(new_transform, delta * look_speed)

func _on_detection_area_body_entered(body) -> void:
	if body.is_in_group("player_car"):
		set_target(body)
		
		# Roar when detecting player
		if can_roar:
			play_animation("roar")
			can_roar = false
			roar_timer.start(rng.randf_range(5.0, 10.0))

func _on_detection_area_body_exited(body) -> void:
	if body == target:
		# Don't lose target immediately, continue chase for a while
		await get_tree().create_timer(rng.randf_range(5.0, 10.0) * aggression_level).timeout
		
		# If target still out of range and we're not dead
		if !is_dead and current_state != MonsterState.DEAD:
			var still_in_range = false
			
			# Check if target is still valid and in extended detection range
			if target and is_instance_valid(target):
				still_in_range = global_position.distance_to(target.global_position) < detection_radius * 1.5
			
			if !still_in_range:
				current_state = MonsterState.ROAMING
				target = null
				set_new_wander_point()

func _on_waste_attack_area_body_entered(body) -> void:
	if body.is_in_group("player_car") and animation_player.current_animation == "waste":
		# Deal damage to car
		if body.has_method("take_damage"):
			body.take_damage(damage * 1.5)  # Waste attack deals more damage

func _on_roar_timer_timeout() -> void:
	can_roar = true

# Call this from gameplay manager when player escapes city
func player_escaped() -> void:
	# Monster gives up chase
	current_state = MonsterState.ROAMING
	target = null
	
	# Play roar animation in frustration
	play_animation("roar")
	
	# Start wandering
	set_new_wander_point()
