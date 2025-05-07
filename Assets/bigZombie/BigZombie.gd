extends CharacterBody3D

enum State {
	IDLE,
	WALK,
	ATTACK,
	STUN,
	DEAD,
	ROAR  # Roar state for handling aggression
}

# Signals for communicating with other systems
signal zombie_died
signal zombie_damaged(amount)

var health = 450
var diedOnce = false
var state = State.WALK
var MAX_SPEED = 7
var attack_range = 2  # Distance at which enemy will start attacking the player
var attack_timer = 0.0  # Time between attacks
var attack_cooldown = 1.0  # Cooldown for each attack
@onready var roar_timer = $roar_timer  # Reference to the Timer node for the roar cooldown
@onready var animation_tree = $AnimationTree
@onready var vanish_timer = $vanishTimer  # Vanish timer for when the enemy dies
@onready var model_anim_player = $bigzombieFin/AnimationPlayer # Reference to the GLB's AnimationPlayer

# Sound effects
@onready var roar_sound = $roar_sound
@onready var attack_sound = $attack_sound
@onready var spawn_sound = $spawn_sound
@onready var die_sound = $die_sound
@onready var run_sound = $run_sound
@onready var roar_sound_2 = $roar_sound2

var close_distance_threshold = 2.0  # Distance at which the run sound will stop playing

# References
#@onready var blood = preload("res://particleSystems/blood effects/bloodVFX.tscn")
@onready var player: Vehicle = $"../VehicleController/VehicleRigidBody"

var is_attacking = false
var has_roared = false  # Flag to track if the enemy has roared already

# Gravity constant
var gravity = -9.8  # Adjust this to suit the scale of your game world
var fall_speed = 0.0  # The speed at which the enemy falls

# Timer for dealing damage after attack (ensure it's in the scene tree)
var damage_delay_timer : Timer
@onready var roar_2 = $roar2

# Called when the node enters the scene tree for the first time.
func _ready():
	# Connect the GLB's AnimationPlayer to the AnimationTree
	animation_tree.anim_player = model_anim_player.get_path()
	animation_tree.active = true
	
	# Print available animations for debugging
	print("Available animations in the model:")
	for anim_name in model_anim_player.get_animation_list():
		print(" - " + anim_name)
	
	# Important: Configure the animation tree to let animations finish
	# Find the OneShot node for attack and configure it if needed
	# Add monitoring signal for animation completion
	var anim_finished_signal = "animation_finished"
	if model_anim_player.has_signal(anim_finished_signal):
		if not model_anim_player.is_connected(anim_finished_signal, _on_animation_finished):
			model_anim_player.connect(anim_finished_signal, _on_animation_finished)
	
	# Set initial animation states - using OneShot request instead of active
	animation_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)  # Initial state is not attacking
	animation_tree.set("parameters/die/active", false)  # Not dying at start
	animation_tree.set("parameters/stun/active", false)  # No stun at start
	
	# IMPORTANT: Set initial state to WALK and configure run animation
	state = State.WALK
	animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Set to run animation
	
	# Ensure the roar timer doesn't start automatically
	roar_timer.autostart = false

	# Play spawn sound when the enemy spawns
	spawn_sound.play()

	# Instantiate the damage delay timer
	damage_delay_timer = Timer.new()
	add_child(damage_delay_timer)  # Add it to the scene tree

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if diedOnce:
		return

	# Look towards the player and move towards them if not in range
	look_at_player()

	# Check if the attack animation is still playing
	var is_attack_active = animation_tree.get("parameters/attack/active")
	
	# Clear logic for run animation
	if state == State.WALK and velocity.length() > 0.5:
		# We're moving and in walk state - PLAY RUN ANIMATION
		animation_tree.set("parameters/RR_blend/blend_amount", 0.0)
		if not run_sound.playing and global_position.distance_to(player.global_position) > close_distance_threshold:
			run_sound.play()
	elif run_sound.playing:
		run_sound.stop()

	match state:
		State.ATTACK:
			# Don't start a new attack or change state if the animation is still playing
			if is_attack_active:
				return  # Let the animation finish first
				
			attack_timer -= delta  # Decrease the attack cooldown timer
			if attack_timer <= 0:  # Attack when timer is done
				attack_player()
			
			# Only transition to roar state if we're not in an attack animation
			if not is_attack_active and global_position.distance_to(player.global_position) > attack_range:
				state = State.ROAR
				roar_timer.start()  # Start the roar timer
				roar_2.start()
				
				animation_tree.set("parameters/RR_blend/blend_amount", 1.0)  # Roar animation blend
				velocity = Vector3(0, 0, 0)  # Stop moving while roaring

		State.ROAR:
			# Roar sound when transitioning to Roar state
			if !has_roared:
				roar_sound.play()
				has_roared = true

			# Check if the roar timer is finished and transition to walking towards the player
			if roar_timer.is_stopped():
				# After roar finishes, start moving towards the player
				state = State.WALK
				animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Set to run animation
				move_towards_player(delta)  # Start moving

		State.WALK:
			# Don't transition if we're in the middle of an attack animation
			if not is_attack_active:
				move_towards_player(delta)

# Optional: You can stop the run sound when switching to other states like attack or death:
func stop_run_sound():
	if run_sound.playing:
		run_sound.stop()  # Stop playing the run sound
		
func _physics_process(delta):
	if diedOnce:
		velocity = Vector3(0, -8, 0)  # Falling velocity after death (if needed)
		move_and_slide()
		return

	# Apply gravity when not grounded
	if not is_on_floor():
		fall_speed += gravity * delta  # Apply gravity to fall speed
	else:
		fall_speed = 0  # Reset fall speed when on the ground

	velocity.y = fall_speed  # Apply the fall speed to the Y velocity

	# Handle animation states based on character state
	if state == State.ATTACK:
		MAX_SPEED = 0.01  # Almost stop moving when attacking
		# Don't change animation state here - let attack_player handle it
	elif state == State.WALK:
		MAX_SPEED = 3  # Walking speed
		# Never abort an attack animation - let it finish naturally
		# We'll only start new animations when the current one is done
	elif state == State.ROAR:
		animation_tree.set("parameters/RR_blend/blend_amount", 1.0)  # Roar animation
		# Never abort an attack animation - let it finish naturally

	# IMPORTANT: DO NOT reset velocity to zero here!
	set_velocity(velocity)
	move_and_slide()

# Make the enemy look towards the player
func look_at_player():
	var target_position = player.global_position
	look_at(target_position)  # Rotate the enemy to face the player

# Move towards the player (when in walk or roar state)
func move_towards_player(delta):
	var direction = (player.global_position - global_position).normalized()
	
	# Check if an attack animation is currently playing
	var is_attack_active = animation_tree.get("parameters/attack/active")
	
	# Don't change state if attack animation is playing
	if is_attack_active:
		velocity = Vector3(0, 0, 0)  # Stay still while attacking
		return

	# Check if we're in attack range
	if global_position.distance_to(player.global_position) < attack_range:
		if state != State.ATTACK:
			state = State.ATTACK  # Switch to attack state
			attack_player()  # Call attack_player to start the animation
			stop_run_sound()  # Stop running sound
		velocity = Vector3(0, 0, 0)  # Stop moving when attacking
	elif global_position.distance_to(player.global_position) < attack_range * 2 and not has_roared:
		# Roar if within roar range (but only once)
		state = State.ROAR
		roar_timer.start()
		roar_sound.play()
		has_roared = true
		animation_tree.set("parameters/RR_blend/blend_amount", 1.0)  # Roar animation
		stop_run_sound()  # Stop running sound
	else:
		# Move towards the player
		state = State.WALK
		animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Use run animation
		velocity = direction * MAX_SPEED  # Set movement velocity
		
# Trigger attack when the enemy is close to the player
func attack_player():
	# Check if an attack animation is already playing
	if animation_tree.get("parameters/attack/active"):
		return  # Don't start a new attack if one is already in progress
		
	attack_timer = attack_cooldown  # Reset the attack timer
	
	# Use the request parameter to fire the attack animation
	animation_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	# Play attack sound when attacking
	attack_sound.play()

	# Set up the delay before dealing damage
	damage_delay_timer.start(0.3)  # Delay damage by 0.3 seconds (adjust as needed)

	# Only connect the signal if it's not already connected
	if not damage_delay_timer.timeout.is_connected(_on_damage_delay_timeout):
		damage_delay_timer.timeout.connect(_on_damage_delay_timeout)
		
	# Create a timer to track when the animation completes (assuming attack animation is ~1 second)
	var attack_anim_timer = Timer.new()
	attack_anim_timer.one_shot = true
	attack_anim_timer.wait_time = 1.0  # Set this to match your attack animation length
	add_child(attack_anim_timer)
	attack_anim_timer.timeout.connect(func(): attack_anim_timer.queue_free())
	attack_anim_timer.start()

# Call this function when the enemy takes damage
func damage(amount, _type=""):
	health -= amount
	#spawn_blood_effect()
	emit_signal("zombie_damaged", amount)  # Emit signal instead of using globals

	if health <= 0 and not diedOnce:
		die()

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
	# Once the roar timer finishes, switch to Walk state and continue moving towards the player
	state = State.WALK
	animation_tree.set("parameters/RR_blend/blend_amount", 0.0)  # Set to run animation
	move_towards_player(10)  # Keep moving towards the player
	run_sound.play()

# Function to apply damage after the delay
func _on_damage_delay_timeout():
	# Use player reference to call damage method
	if player.has_method("damage"):
		player.damage(5)  # Deal damage to the player
	damage_delay_timer.stop()  # Stop the timer after applying damage

func _on_roar2_timeout():
	roar_sound_2.play()
	
# Handle animation completion
func _on_animation_finished(anim_name):
	# Check if this was an attack animation
	if anim_name.to_lower().contains("attack"):
		# Reset attack state after animation finishes
		print("Attack animation finished: ", anim_name)
		# Don't immediately abort - let the OneShot node handle the transition
