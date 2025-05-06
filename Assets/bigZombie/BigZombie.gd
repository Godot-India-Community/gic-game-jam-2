extends KinematicBody

enum State {
	Idle,
	Walk,
	Attack,
	Stun,
	Dead,
	Roar  # Roar state for handling aggression
}

var health = 450
var diedOnce = false
var state = State.Walk
var MAX_SPEED = 7
var attack_range = 2  # Distance at which enemy will start attacking the player
var attack_timer = 0.0  # Time between attacks
var attack_cooldown = 1.0  # Cooldown for each attack
var velocity = Vector3(0, 0, 0)
onready var roar_timer = $roar_timer  # Reference to the Timer node for the roar cooldown
onready var animation_tree = $AnimationTree
onready var vanish_timer = $vanishTimer  # Vanish timer for when the enemy dies

# Sound effects
onready var roar_sound = $roar_sound
onready var attack_sound = $attack_sound
onready var spawn_sound = $spawn_sound
onready var die_sound = $die_sound
onready var run_sound = $run_sound
onready var roar_sound_2 = $roar_sound2

var close_distance_threshold = 2.0  # Distance at which the run sound will stop playing

# References
onready var blood = preload("res://particleSystems/blood effects/bloodVFX.tscn")
onready var player = get_node("/root/Level1/PlaceHolder")  # Reference to the player

var is_attacking = false
var has_roared = false  # Flag to track if the enemy has roared already

# Gravity constant
var gravity = -9.8  # Adjust this to suit the scale of your game world
var fall_speed = 0.0  # The speed at which the enemy falls

# Timer for dealing damage after attack (ensure it's in the scene tree)
var damage_delay_timer : Timer
onready var roar_2 = $roar2

# Called when the node enters the scene tree for the first time.
func _ready():
	# Initial setup, set up animations
	Global.QZPresent = true
	animation_tree.set("parameters/attack/active", false)  # Initial state is not attacking
	animation_tree.set("parameters/die/active", false)  # Not dying at start
	animation_tree.set("parameters/stun/active", false)  # No stun at start
	animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Set blend for run/roar to idle

	# Ensure the roar timer doesn't start automatically
	roar_timer.autostart = false

	# Play spawn sound when the enemy spawns
	spawn_sound.play()

	# Instantiate the damage delay timer
	damage_delay_timer = Timer.new()
	add_child(damage_delay_timer)  # Add it to the scene tree

# Called every frame. 'delta' is the elapsed time since the previous frame.
# Reference to the run sound (assuming AudioStreamPlayer3D)

# Distance threshold to determine if the enemy is too close to the player

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if diedOnce:
		return

	# Look towards the player and move towards them if not in range
	look_at_player()

	match state:
		State.Attack:
			attack_timer -= delta  # Decrease the attack cooldown timer
			if attack_timer <= 0:  # Attack when timer is done
				attack_player()
			# If player moves out of attack range, transition to Roar state
			if global_transform.origin.distance_to(player.global_transform.origin) > attack_range:
				state = State.Roar
				roar_timer.start()  # Start the roar timer
				roar_2.start()
				
				animation_tree.set("parameters/RR_blend/blend_amount", 1)  # Roar animation blend
				velocity = Vector3(0, 0, 0)  # Stop moving while roaring

		State.Roar:
			# Roar sound when transitioning to Roar state
			if !has_roared:
				roar_sound.play()
				has_roared = true

			# Check if the roar timer is finished and transition to walking towards the player
			if roar_timer.is_stopped():
				# After roar finishes, start moving towards the player with the roar animation
				state = State.Walk
				animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Walk animation blend
				move_towards_player(delta)  # Start moving

		State.Walk:
			move_towards_player(delta)

			# Check if the enemy is moving (based on velocity)
			if velocity.length() > 0.1:  # Consider the enemy moving if the velocity is greater than a small threshold
				# Check if the enemy is not too close to the player
				if global_transform.origin.distance_to(player.global_transform.origin) > close_distance_threshold:
					if not run_sound.playing:
						run_sound.play()  # Start the run sound
				else:
					
					if run_sound.playing:
						run_sound.stop()  # Stop the run sound if the enemy is too close
			else:
				if run_sound.playing:
					run_sound.stop()
					  # Stop the run sound if the enemy is not moving

# Optional: You can stop the run sound when switching to other states like attack or death:
func stop_run_sound():
	if run_sound.playing:
		run_sound.stop()
		
		  # Stop playing the run sound
		
func _physics_process(delta):
	if diedOnce:
		velocity = Vector3(0, -8, 0)  # Falling velocity after death (if needed)
		move_and_slide(velocity, Vector3(0, 1, 0))
		return

	# Apply gravity when not grounded
	if not is_on_floor():
		fall_speed += gravity * delta  # Apply gravity to fall speed
	else:
		fall_speed = 0  # Reset fall speed when on the ground

	velocity.y = fall_speed  # Apply the fall speed to the Y velocity

	# Update MAX_SPEED depending on the state
	if state == State.Attack:
		MAX_SPEED = 0.01  # Stop moving when attacking
		animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Stop any walk or roar animation during attack
		animation_tree.set("parameters/attack/active", true)  # Ensure attack animation plays
	elif state == State.Walk:
		MAX_SPEED = 3  # Walking speed
		animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Walking animation blend reset
		animation_tree.set("parameters/attack/active", false)  # Stop attack animation when walking
	elif state == State.Roar:
		# Roar animation with blend_amount = 14
		animation_tree.set("parameters/RR_blend/blend_amount", 1)
		animation_tree.set("parameters/attack/active", false)  # Ensure no attack animation during roar

	# Apply movement (horizontal velocity)
	velocity = velocity.linear_interpolate(Vector3(0, 0, 0), delta)
	move_and_slide(velocity, Vector3(0, 1, 0))

# Make the enemy look towards the player
func look_at_player():
	var target_position = player.global_transform.origin
	look_at(target_position, Vector3.UP)  # Rotate the enemy to face the player

# Move towards the player (when in walk or roar state)
func move_towards_player(delta):
	var direction = (player.global_transform.origin - global_transform.origin).normalized()

	# If within attack range, stop and attack
	if global_transform.origin.distance_to(player.global_transform.origin) < attack_range:
		if state != State.Attack:
			state = State.Attack  # Transition to attack state when in range
			animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Ensure attack animation stops any walking/roaring
			animation_tree.set("parameters/attack/active", true)  # Ensure attack animation is played
		velocity = Vector3(0, 0, 0)  # Stop movement when attacking
	elif global_transform.origin.distance_to(player.global_transform.origin) < attack_range * 2 and not has_roared:
		# Roar if within roar range (but only once)
		state = State.Roar  # Change to Roar state when close to player
		roar_timer.start()  # Start the roar timer
		roar_sound.play()
		
		has_roared = true  # Mark that the enemy has roared
		animation_tree.set("parameters/RR_blend/blend_amount", 1)  # Roar animation blend
		
		velocity = direction * MAX_SPEED  # Keep moving during the roar animation
	else:
		# Move towards the player with roar animation blend active (after roar finishes)
		state = State.Walk
		animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Walking animation blend reset
		velocity = direction * MAX_SPEED  # Keep moving
		

# Trigger attack when the enemy is close to the player
func attack_player():
	attack_timer = attack_cooldown  # Reset the attack timer
	animation_tree.set("parameters/attack/active", true)  # Start the attack animation

	# Play attack sound when attacking
	attack_sound.play()

	# Set up the delay before dealing damage
	damage_delay_timer.start(0.3)  # Delay damage by 0.3 seconds (adjust as needed)

	# Only connect the signal if it's not already connected
	if not damage_delay_timer.is_connected("timeout", self, "_on_damage_delay_timeout"):
		damage_delay_timer.connect("timeout", self, "_on_damage_delay_timeout")

# Call this function when the enemy takes damage
func damage(amount, _type=""):
	health -= amount
	spawn_blood_effect()

	if health <= 0 and not diedOnce:
		die()

# Spawn a blood effect at the enemy's position
func spawn_blood_effect():
	var b = blood.instance()
	add_child(b)
	b.global_transform.origin = $bigzombieFin/Armature004/Skeleton/BoneAttachment/bloodSpawn.global_transform.origin
	b.play()

# Handle the enemy's death
func die():
	if not diedOnce:
		diedOnce = true
		animation_tree.set("parameters/attack/active", false)  # Stop any attack animation
		animation_tree.set("parameters/die/active", true)  # Play the death animation
		die_sound.play()  # Play death sound
		Global.player.highScore += 200  # Update the score for killing the enemy
		vanish_timer.start()  # Start the timer to remove the enemy after death

# Call this when the vanish timer finishes
func _on_vanishTimer_timeout():
	queue_free()  # Remove the enemy from the scene
	Global.QZPresent = false  # Update the global state to show the enemy is no longer present

# This function handles when the roar timer finishes
func _on_roar_timer_timeout():
	# Once the roar timer finishes, switch to Walk state and continue moving towards the player
	state = State.Walk
	animation_tree.set("parameters/RR_blend/blend_amount", 0)  # Keep walking animation blend
	move_towards_player(0.0)  # Keep moving towards the player
	run_sound.play()
	

# Function to apply damage after the delay
func _on_damage_delay_timeout():
	Global.player.damage(5)  # Deal damage to the player (adjust as necessary)
	damage_delay_timer.stop()  # Stop the timer after applying damage


func _on_roar2_timeout():
	roar_sound_2.play()
