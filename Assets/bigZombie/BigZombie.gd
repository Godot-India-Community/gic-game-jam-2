extends CharacterBody3D

enum State {
	IDLE,
	WALK,
	ATTACK,
	STUN,
	DEAD,
	ROAR,  # Roar state for handling aggression
	FRENZY,  # New state for wild attacking
	TELEPORT  # New state for teleportation
}

# Signals for communicating with other systems
signal zombie_died
signal zombie_damaged(amount)

var health = 450
var diedOnce = false
var state = State.WALK
var MAX_SPEED = 7
var FRENZY_SPEED = 1  # Speed when in frenzy mode
var attack_range = 5  # Increased attack range for earlier detection
var frenzy_range = 1  # Range at which enemy enters frenzy mode
var attack_timer = 0.0  # Time between attacks
var attack_cooldown = 1.0  # Default cooldown for each attack
var frenzy_attack_cooldown = 0.1  # Faster attack cooldown for frenzy mode
@onready var roar_timer = $roar_timer
@onready var animation_tree = $AnimationTree
@onready var vanish_timer = $vanishTimer
@onready var model_anim_player = $bigzombieFin/AnimationPlayer

# Sound effects
@onready var roar_sound = $roar_sound
@onready var attack_sound = $attack_sound
@onready var spawn_sound = $spawn_sound
@onready var die_sound = $die_sound
@onready var run_sound = $run_sound
@onready var roar_sound_2 = $roar_sound2
@onready var teleport_sound = $teleport_sound  # New sound for teleportation

# Teleportation parameters
var max_distance = 30.0  # Distance at which zombie will teleport
var min_teleport_distance = 8.0  # Minimum distance to teleport to (not too close)
var max_teleport_distance = 12.0  # Maximum distance to teleport to (not too far)
var teleport_cooldown = 10.0  # Time between teleports (seconds)
var teleport_timer = 0.0  # Timer to track teleport cooldown
var can_teleport = true  # Flag to control teleportation
var teleport_effect_scene = preload("res://addons/gevp/scenes/smoke_effect.tscn")  # Optional effect

var close_distance_threshold = 2.0  # Distance at which the run sound will stop playing

# References
@onready var player: Vehicle = $"../VehicleController/VehicleRigidBody"

var is_attacking = false
var has_roared = false
var in_frenzy = false  # Track if monster is in frenzy mode

# Gravity constant
var gravity = -9.8
var fall_speed = 0.0

# Timer for dealing damage after attack
var damage_delay_timer : Timer
var second_attack_timer : Timer  # New timer for second attack
@onready var roar_2 = $roar2

# New frenzy variables
var consecutive_attacks = 0  # Count consecutive attacks
var max_consecutive_attacks = 3  # Maximum number of attacks in a row
var frenzy_direction = Vector3.ZERO  # Direction to circle around the player

# Called when the node enters the scene tree for the first time.
func _ready():
	# Add to zombies group for knockback direction finding
	add_to_group("zombies")
	
	# Connect the GLB's AnimationPlayer to the AnimationTree
	animation_tree.anim_player = model_anim_player.get_path()
	animation_tree.active = true
	
	# Print available animations for debugging
	print("Available animations in the model:")
	for anim_name in model_anim_player.get_animation_list():
		print(" - " + anim_name)
	
	# Configure animation signals
	var anim_finished_signal = "animation_finished"
	if model_anim_player.has_signal(anim_finished_signal):
		if not model_anim_player.is_connected(anim_finished_signal, _on_animation_finished):
			model_anim_player.connect(anim_finished_signal, _on_animation_finished)
	
	# Set initial animation states
	animation_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	animation_tree.set("parameters/die/active", false)
	animation_tree.set("parameters/stun/active", false)
	
	# Set initial state to WALK
	state = State.WALK
	animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Set to run animation
	
	# Ensure the roar timer doesn't start automatically
	roar_timer.autostart = false

	# Play spawn sound when the enemy spawns
	spawn_sound.play()

	# Instantiate the damage delay timers
	damage_delay_timer = Timer.new()
	add_child(damage_delay_timer)
	
	# Create the second attack timer
	second_attack_timer = Timer.new()
	second_attack_timer.one_shot = true
	add_child(second_attack_timer)
	second_attack_timer.timeout.connect(_on_second_attack_timer_timeout)
	
	# Create the teleport sound if it doesn't exist
	if not has_node("teleport_sound"):
		var sound = AudioStreamPlayer3D.new()
		sound.name = "teleport_sound"
		add_child(sound)
		# You'll need to assign an audio stream to this in the editor
		# or load one programmatically here

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if diedOnce:
		return

	# Update teleport cooldown timer
	if teleport_timer > 0:
		teleport_timer -= delta
		if teleport_timer <= 0:
			can_teleport = true

	# Look towards the player and move towards them if not in range
	look_at_player()

	# Check if the attack animation is still playing
	var is_attack_active = animation_tree.get("parameters/attack/active")
	
	# Run animation and sound handling
	if (state == State.WALK || state == State.FRENZY) and velocity.length() > 0.5:
		# We're moving - PLAY RUN ANIMATION
		animation_tree.set("parameters/RR_blend/blend_amount", 0.0)
		if not run_sound.playing and global_position.distance_to(player.global_position) > close_distance_threshold:
			run_sound.play()
	elif run_sound.playing:
		run_sound.stop()

	# Check distance to player for state transitions
	var distance_to_player = global_position.distance_to(player.global_position)
	
	# Check if player is too far and we need to teleport
	if state != State.DEAD and state != State.TELEPORT and distance_to_player > max_distance and can_teleport:
		state = State.TELEPORT
		perform_teleport()
		return
	
	# Update state based on distance if not in special states
	if state != State.DEAD and state != State.STUN and state != State.TELEPORT and !is_attack_active:
		if distance_to_player <= attack_range:
			# Enter attack mode when very close
			if state != State.ATTACK:
				state = State.ATTACK
				attack_timer = 0.0  # Attack immediately
		elif distance_to_player <= frenzy_range:
			# Enter frenzy mode when within frenzy range
			if state != State.FRENZY and state != State.ATTACK:
				enter_frenzy_mode()
		elif state == State.FRENZY:
			# Stay in frenzy mode even at a bit longer range
			pass
		else:
			# Regular walking state
			state = State.WALK

	match state:
		State.TELEPORT:
			# This state is handled by the perform_teleport function
			# It will automatically transition to WALK after teleporting
			pass
			
		State.ATTACK:
			# Don't start a new attack if the animation is still playing
			if is_attack_active:
				return  # Let the animation finish first
				
			attack_timer -= delta  # Decrease the attack cooldown timer
			if attack_timer <= 0:  # Attack when timer is done
				attack_player()
				consecutive_attacks += 1
				
				# If in frenzy, use shorter cooldown and allow multiple attacks
				if in_frenzy:
					attack_timer = frenzy_attack_cooldown
					if consecutive_attacks >= max_consecutive_attacks:
						# After several attacks, briefly circle the player
						state = State.FRENZY
						consecutive_attacks = 0
				else:
					attack_timer = attack_cooldown
			
			# Transition if target moved away
			if not is_attack_active and distance_to_player > attack_range:
				if distance_to_player <= frenzy_range:
					state = State.FRENZY
				else:
					state = State.ROAR
					roar_timer.start()
					roar_2.start()
					animation_tree.set("parameters/RR_blend/blend_amount", 1.0)
					velocity = Vector3.ZERO

		State.FRENZY:
			# In frenzy mode, move more erratically and quickly toward the player
			in_frenzy = true
			MAX_SPEED = FRENZY_SPEED
			
			# If close enough to attack, do it
			if distance_to_player <= attack_range:
				state = State.ATTACK
				attack_timer = 0.0  # Attack immediately
				return
				
			# Otherwise, circle around and close in on player
			move_frenzy_style(delta)
			
			# Occasionally roar during frenzy
			if randf() < 0.005:  # 0.5% chance per frame to roar
				roar_sound.play()

		State.ROAR:
			# Roar sound when transitioning to Roar state
			if !has_roared:
				roar_sound.play()
				has_roared = true

			# Check if the roar timer is finished and transition
			if roar_timer.is_stopped():
				# After roar, go to frenzy if close enough, otherwise walk
				if distance_to_player <= frenzy_range:
					enter_frenzy_mode()
				else:
					state = State.WALK
					animation_tree.set("parameters/RR_blend/blend_amount", 0.0)
					move_towards_player(delta)

		State.WALK:
			in_frenzy = false
			MAX_SPEED = 7  # Reset to normal speed
			
			# Don't transition if we're in the middle of an attack animation
			if not is_attack_active:
				move_towards_player(delta)
				
				# Check if we should enter frenzy mode
				if distance_to_player <= frenzy_range:
					enter_frenzy_mode()

# NEW FUNCTION: Performs the teleportation
func perform_teleport():
	# Stop any current sounds
	if run_sound.playing:
		run_sound.stop()
	
	# Optional: Play teleport-out effect at current position
	if teleport_effect_scene:
		var effect = teleport_effect_scene.instantiate()
		get_parent().add_child(effect)
		effect.global_position = global_position
	
	# Calculate position to teleport to
	var teleport_position = calculate_teleport_position()
	
	# Perform the teleport
	global_position = teleport_position
	
	# Optional: Play teleport-in effect at new position
	if teleport_effect_scene:
		var effect = teleport_effect_scene.instantiate()
		get_parent().add_child(effect)
		effect.global_position = global_position
	
	# Play teleport sound
	if teleport_sound:
		teleport_sound.play()
	
	# Reset teleport cooldown
	teleport_timer = teleport_cooldown
	can_teleport = false
	
	# Roar after teleporting to alert player
	roar_sound.play()
	
	# Transition back to WALK state (or FRENZY if close)
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= frenzy_range:
		enter_frenzy_mode()
	else:
		state = State.WALK

# NEW FUNCTION: Calculates where to teleport to
func calculate_teleport_position():
	# Get player position and forward direction
	var player_pos = player.global_position
	var player_forward = -player.global_transform.basis.z.normalized()
	
	# Calculate random angle offset (to appear slightly to the side or behind)
	var angle_offset = randf_range(-PI/2, PI/2)  # +/- 90 degrees
	
	# Create rotation matrix for the angle offset
	var rot_matrix = Basis(Vector3.UP, angle_offset)
	var direction = rot_matrix * player_forward
	
	# Calculate distance for teleport (within min/max range)
	var distance = randf_range(min_teleport_distance, max_teleport_distance)
	
	# Calculate target position
	var target_pos = player_pos + direction * distance
	
	# Ensure the position is valid (raycast to check for obstacles if needed)
	# This is simplified and might need adjustment for your specific level layout
	var space_state = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.new()
	ray_query.from = player_pos + Vector3.UP
	ray_query.to = target_pos + Vector3.UP
	ray_query.collision_mask = 1  # Set to your world collision layer
	ray_query.exclude = [self]  # Don't collide with self
	
	var result = space_state.intersect_ray(ray_query)
	if result:
		# If there's an obstacle, adjust position to be before the obstacle
		var hit_pos = result["position"]
		var hit_normal = result["normal"]
		target_pos = hit_pos + hit_normal * 2.0  # Offset from wall
	
	# Ensure we're on the ground or at valid height
	# Here we're doing a simple adjustment, but you might want a more complex check
	target_pos.y = player_pos.y
	
	return target_pos

func enter_frenzy_mode():
	state = State.FRENZY
	in_frenzy = true
	MAX_SPEED = FRENZY_SPEED
	
	# Generate a new circling direction
	update_frenzy_direction()
	
	# Play roar at start of frenzy
	roar_sound.play()
	
	# Reset attack chain
	consecutive_attacks = 0

func update_frenzy_direction():
	# Calculate a direction that circles around the player
	var to_player = player.global_position - global_position
	frenzy_direction = Vector3(-to_player.z, 0, to_player.x).normalized()
	
	# Add some randomness
	frenzy_direction = (frenzy_direction + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))).normalized()

# Move erratically in frenzy mode
func move_frenzy_style(delta):
	var to_player = (player.global_position - global_position).normalized()
	
	# Occasionally update circling direction
	if randf() < 0.02:  # 2% chance per frame
		update_frenzy_direction()
	
	# Blend between circling and direct approach
	var circle_weight = randf_range(0.3, 0.7)  # How much to circle vs approach directly
	var direction = (to_player * (1.0 - circle_weight) + frenzy_direction * circle_weight).normalized()
	
	# Set velocity
	velocity = direction * MAX_SPEED
	
	# Occasionally make sudden lunges
	if randf() < 0.01:  # 1% chance per frame
		velocity *= 1.5  # Brief speed boost

# Stop the run sound when switching to other states
func stop_run_sound():
	if run_sound.playing:
		run_sound.stop()
		
func _physics_process(delta):
	if diedOnce:
		velocity = Vector3(0, -8, 0)  # Falling velocity after death
		move_and_slide()
		return

	# Apply gravity when not grounded
	if not is_on_floor():
		fall_speed += gravity * delta
	else:
		fall_speed = 0

	velocity.y = fall_speed

	# Handle animation states based on character state
	if state == State.ATTACK:
		MAX_SPEED = 0.01  # Almost stop moving when attacking
	elif state == State.WALK:
		MAX_SPEED = 7  # Normal walking speed
	elif state == State.FRENZY:
		MAX_SPEED = FRENZY_SPEED  # Faster speed in frenzy
	elif state == State.ROAR:
		animation_tree.set("parameters/RR_blend/blend_amount", 1.0)  # Roar animation

	set_velocity(velocity)
	move_and_slide()

# Make the enemy look towards the player
func look_at_player():
	var target_position = player.global_position
	look_at(target_position)

# Move towards the player (when in walk state)
func move_towards_player(delta):
	var direction = (player.global_position - global_position).normalized()
	
	# Check if an attack animation is currently playing
	var is_attack_active = animation_tree.get("parameters/attack/active")
	
	# Don't change state if attack animation is playing
	if is_attack_active:
		velocity = Vector3(0, 0, 0)
		return

	# Check if we're in attack range
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player < attack_range:
		if state != State.ATTACK:
			state = State.ATTACK
			attack_player()
			stop_run_sound()
		velocity = Vector3(0, 0, 0)
	elif distance_to_player < frenzy_range and not has_roared:
		# Roar and enter frenzy if within range (but only once)
		state = State.ROAR
		roar_timer.start()
		roar_sound.play()
		has_roared = true
		animation_tree.set("parameters/RR_blend/blend_amount", 1.0)
		stop_run_sound()
	else:
		# Move towards the player
		state = State.WALK
		animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Use run animation
		velocity = direction * MAX_SPEED
		
# Trigger attack when the enemy is close to the player
func attack_player():
	# Check if an attack animation is already playing
	if animation_tree.get("parameters/attack/active"):
		return  # Don't start a new attack if one is already in progress
		
	# Use the request parameter to fire the attack animation
	animation_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	# Play attack sound - sometimes play at lower pitch for variation
	if in_frenzy and randf() < 0.3:
		attack_sound.pitch_scale = randf_range(0.8, 1.2)
	else:
		attack_sound.pitch_scale = 1.0
	attack_sound.play()

	# First attack damage
	damage_delay_timer.start(0.25)  # Delay damage by 0.25 seconds

	# Only connect the signal if it's not already connected
	if not damage_delay_timer.timeout.is_connected(_on_damage_delay_timeout):
		damage_delay_timer.timeout.connect(_on_damage_delay_timeout)
	
	# Second attack damage - happens later in the same animation
	second_attack_timer.wait_time = 0.6  # Second hit at 0.6 seconds into animation
	second_attack_timer.start()
		
	# Create a timer to track when the animation completes
	var attack_anim_timer = Timer.new()
	attack_anim_timer.one_shot = true
	attack_anim_timer.wait_time = 1.0
	add_child(attack_anim_timer)
	attack_anim_timer.timeout.connect(func(): attack_anim_timer.queue_free())
	attack_anim_timer.start()

# Call this function when the enemy takes damage
func damage(amount, _type=""):
	health -= amount
	emit_signal("zombie_damaged", amount)

	if health <= 0 and not diedOnce:
		die()
	else:
		# Enter frenzy when damaged if not already in frenzy
		if !in_frenzy and !diedOnce:
			enter_frenzy_mode()
		
		# Also reset teleport cooldown when damaged
		# This ensures zombie can teleport again quickly if player tries to escape after damaging it
		teleport_timer = min(teleport_timer, 2.0)

# Handle the enemy's death
func die():
	if not diedOnce:
		diedOnce = true
		# Abort any attack animations
		animation_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		animation_tree.set("parameters/die/active", true)  # Play the death animation
		die_sound.play()  # Play death sound
		stop_run_sound()  # Stop running sound
		
		# Use signal instead of global variable
		emit_signal("zombie_died")
		
		# Add points to player score using direct reference
		if player.has_method("add_score"):
			player.add_score(200)
		
		vanish_timer.start()  # Start the timer to remove the enemy after death

# Call this when the vanish timer finishes
func _on_vanishTimer_timeout():
	queue_free()  # Remove the enemy from the scene

# This function handles when the roar timer finishes
func _on_roar_timer_timeout():
	# After roar, check if we should go to frenzy or walk
	var distance_to_player = global_position.distance_to(player.global_position)
	if distance_to_player <= frenzy_range:
		enter_frenzy_mode()
	else:
		state = State.WALK
		animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Set to run animation
		move_towards_player(10)  # Keep moving towards the player
		run_sound.play()

# Function to apply damage after the delay (first hit)
func _on_damage_delay_timeout():
	# Use player reference to call damage method
	if player.has_method("damage"):
		player.damage(1)  # Deal 1 damage to the player (counting hits)
	
	# Play attack sound for first hit
	attack_sound.pitch_scale = 1.0
	attack_sound.play()
	
	damage_delay_timer.stop()  # Stop the timer after applying damage

# Function to apply damage for the second hit in the same animation
func _on_second_attack_timer_timeout():
	# Use player reference to call damage method
	if player.has_method("damage"):
		player.damage(1)  # Deal additional 1 damage for second hit
	
	# Play attack sound for second hit with slightly different pitch
	attack_sound.pitch_scale = 1.2
	attack_sound.play()

func _on_roar2_timeout():
	roar_sound_2.play()
	
# Handle animation completion
func _on_animation_finished(anim_name):
	# Check if this was an attack animation
	if anim_name.to_lower().contains("attack"):
		# If in frenzy mode and close to player, chain attacks
		if in_frenzy and global_position.distance_to(player.global_position) <= attack_range:
			attack_timer = 0.1  # Very short delay between chain attacks
