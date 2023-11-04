	# Wip from 20:00
extends CharacterBody3D
# 1) States
enum State {IDLE,WALKING,RUNNING,CROUCHING,SLIDING,ROLLING,JUMPING,WALL_RUNNING,FREE_LOOK,AIMING,FIRING,LANDING,DASHING
}
var current_state = State.IDLE
var direction = Vector3.ZERO

# 2) Speeds
@onready var movement_speeds = {
	"WALKING": 10.0,
	"RUNNING": 20.0,
	"MAX_RUNNING" : 30.00,
	"CROUCHING": 7.0,
	"SLIDING": 15.0,
	"MAX_LERP_SPEED" : 5.0,
	"LERP_SPEED": 10.0,
	"AIR_LERP_SPEED": 3.0,
}
var current_speed = 5.0

#3) Bob vars
@onready var head_bob_settings = {
	"sprint_speed": 22,
	"walk_speed": 14,
	"crouch_speed": 10,
	"sprint_intensity": 0.2,
	"walk_intensity": 0.1,
	"crouch_intensity": 0.05,
	"vector": Vector2.ZERO,  # Assuming Vector2.ZERO is a predefined vector in your environment
	"index": 0.0,
	"current_intensity": 0.0
	}

# 4) Timers
@onready var timer_settings = {
	"slide_timer": 0.0,
	"slide_timer_max": 1,
	"rolling_timer": 0.0,
	"rolling_timer_max": 1
	}

# 5) Check variables
@onready var checks = {
	"can_wall_run": true,
	"free_look": false,
	"setting": "air_movement"
}

# 6) Jump Variables
@onready var jump_vars = {
	"max_jumps": 3,
	"current_jump": 0,
	"gravity": ProjectSettings.get_setting("physics/3d/default_gravity") * 2,  # This line presumes you are working within an environment like Godot
	"jump_velocity": 10,
	"super_jump_velocity": 15
}

# 7) Camera Settings
@onready var player_camera_settings = {
	"direction": Vector3.ZERO,  # Assuming Vector3.ZERO is a predefined zero vector in your environment, such as in the Unity or Godot game engines
	"sensitivity": 0.83,
	"crouching_depth": -0.5,
	"slide_camera_tilt_angle": 15,
	"sens" :0.83  # This is a constant, but it can still be included in a dictionary for organizational purposes
}

# 8) NOdes
@onready var node_dict = {
	"head_banger": $HeadBanger,
	"neck": $neck,
	"head": $neck/head,
	"eyes": $neck/head/eyes,
	"camera_3d": $neck/head/eyes/Camera3D,
	"standing_collision_shape": $standing_collision_shape,
	"crouching_collision_shape": $crouching_collision_shape,
	"ray_cast_3d": $RayCast3D,
	"label_1": $"../Label",
	"label_2": $"../Label2",
	"bullet_scene": preload("res://ball.tscn"),
	"bullet_spawn_point": $neck/head/eyes/Camera3D/Aim/BulletSpawn,
	"aim_ray": $neck/head/eyes/Camera3D/Aim/AimRay,
	"cross_hair": $neck/head/eyes/Camera3D/Aim/CrossHair,
	"animation_player": $neck/head/eyes/AnimationPlayer
}

# Rotate the camera by mouse movement * sensitivity (two cases : free look or not free look)
func _input(event): #
	if event is InputEventMouseMotion :
		if 	checks['free_look'] :
			node_dict['neck'].rotate_y(deg_to_rad(-event.relative.x * player_camera_settings['sens']))
			node_dict['neck'].rotation.y = clamp(node_dict['neck'].rotation.y, deg_to_rad(-120),deg_to_rad(120))
			node_dict['camera_3d'].rotation.z = clamp(node_dict['neck'].rotation.y, deg_to_rad(-40),deg_to_rad(60))
		else :
			rotate_y(deg_to_rad(-event.relative.x * player_camera_settings['sens'])) #by default it rotates by rads we need to rotate by degs
			node_dict['camera_3d'].rotation.z = 0.0
			node_dict['head'].rotate_x(deg_to_rad(-event.relative.y * player_camera_settings['sens']))
			node_dict['head'].rotation.x = clamp(node_dict['head'].rotation.x,deg_to_rad(-89),deg_to_rad(89))

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	node_dict['standing_collision_shape'].disabled = false
	
func _physics_process(delta):
	var input_dir = Input.get_vector("left", "right", "up", "down")
	check_for_state_transitions(delta,input_dir)
	update_character_behavior(delta,input_dir)
	head_bob(delta,input_dir)
	move_and_slide()
	ground(delta)
	print(str(checks['free_look']))	
	logging()
	
# State mapping ✅
func check_for_state_transitions(delta,var_input_dir):
	# Check from Idle to Walking/Running
	if is_on_floor():
		if var_input_dir != Vector2.ZERO:
			if Input.is_action_pressed("run"):
				current_state = State.RUNNING
			else:
				current_state = State.WALKING
		else:
			current_state = State.IDLE
	# Check for Jump
	if  Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("super_jump"):
		current_state = State.JUMPING
	# Check for Crouch/Slide
	if Input.is_action_pressed("crouch"):
		if current_state == State.RUNNING:
			current_state = State.SLIDING
		else:
			current_state = State.CROUCHING
	# Check for Roll
	if Input.is_action_just_pressed("roll"):
		current_state = State.ROLLING
	# Check for Landing
	if not is_on_floor() and velocity.y < -0.9:
		current_state = State.LANDING
	# Check for Wall Run
	if is_on_wall() and Input.is_action_pressed("wall_run") and checks['can_wall_run'] == true:
		current_state = State.WALL_RUNNING
	# Check for Free Look
	if Input.is_action_pressed("freelook"):
		current_state = State.FREE_LOOK
	# Check for Dash
	if Input.is_action_just_pressed("dash"):
		current_state = State.DASHING

# Set state behavior and speed
# Helper function to handle collision shape toggling
func toggle_collision_shapes(standing_disabled, crouching_disabled):
	node_dict['standing_collision_shape'].disabled = standing_disabled
	node_dict['crouching_collision_shape'].disabled = crouching_disabled

# Helper function to handle camera head position
func update_head_position(target_y, delta):
	node_dict['head'].position.y = lerp(node_dict['head'].position.y, target_y, delta * movement_speeds['LERP_SPEED'])

# Set graduallly direction and speed
func handle_directional_movement(input_dir, delta, target_speed):
	if not node_dict['ray_cast_3d'].is_colliding():
		direction = lerp(direction, transform.basis * Vector3(input_dir.x, 0, input_dir.y).normalized(), delta * movement_speeds['LERP_SPEED'])
		current_speed = lerp(current_speed, target_speed, delta * movement_speeds['LERP_SPEED'])

# Set state behavior and speed
func update_character_behavior(delta, var_input_dir):
	match current_state:
		State.WALKING, State.RUNNING:
			handle_directional_movement(var_input_dir, delta, movement_speeds[State.keys()[current_state]])
			toggle_collision_shapes(false, true)  # Use the standing collision
			update_head_position(0.0, delta)  # Reset the camera to the standing position

		State.JUMPING:
			toggle_collision_shapes(false, true)
			if direction != Vector3.ZERO:
				handle_directional_movement(var_input_dir, delta, movement_speeds['AIR_LERP_SPEED'])
			handle_jump(delta,var_input_dir)  # This should contain the jump logic abstracted to another function

		State.SLIDING, State.CROUCHING:
			current_speed = lerp(current_speed, movement_speeds[ State.keys()[current_state]], delta * movement_speeds['LERP_SPEED'])
			update_head_position(player_camera_settings['crouching_depth'], delta)
			toggle_collision_shapes(true, false)  # Use the crouching collision
			if current_state == State.SLIDING:
				var slide_timer = timer_settings['slide_timer_max']  # Reset the countdown timer 
				handle_free_look(delta, direction)  # Assuming it's a function handling the free look logic
				slide_timer(delta)

		State.WALL_RUNNING:
			handle_wallrun(direction)  # Assuming it's a function handling wall running logic

		State.IDLE:
			current_speed = lerp(current_speed, 0.0, delta * movement_speeds['LERP_SPEED'])

	# Movement application
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)


func handle_free_look(delta,var_input_dir):		
		if current_state==State.SLIDING:
			checks['free_look'] = true 
			# First encountered on 12:00 - 15:00	-> Tilt the camera if sliding
			node_dict['eyes'].rotation.z = lerp(node_dict['eyes'].rotation.z, -deg_to_rad(player_camera_settings['slide_camera_tilt_angle']), delta*movement_speeds['LERP_SPEED'])
			velocity.x = var_input_dir.x * (timer_settings['slide_timer'] )  * movement_speeds[State.keys()[current_state]] #prevent from reaching zero
			velocity.z = var_input_dir.z * (timer_settings['slide_timer'] )  * movement_speeds[State.keys()[current_state]]
		elif current_state!=State.SLIDING :
			checks['free_look'] = false
			node_dict['eyes'].rotation.z = -deg_to_rad(node_dict['neck'].rotation.y * -deg_to_rad(player_camera_settings['slide_camera_tilt_angle']))
			node_dict['neck'].rotation.y = lerp(node_dict['neck'].rotation.y, 0.0, delta*movement_speeds['LERP_SPEED'])
			node_dict['eyes'].rotation.z = lerp(node_dict['eyes'].rotation.z, 0.0, delta*movement_speeds['LERP_SPEED'])

func handle_wallrun(var_input_dir) :
	velocity.y  = jump_vars['jump_velocity']
	velocity.x = var_input_dir.x
	jump_vars['current_jump'] = 0
	var wall_normal = get_slide_collision(0)
func handle_jump(delta,var_input_dir) :
	if direction != Vector3.ZERO :
		direction = lerp(direction,transform.basis * Vector3(var_input_dir.x, 0, var_input_dir.y).normalized(),delta*movement_speeds['AIR_LERP_SPEED'])
		if Input.is_action_just_pressed("ui_accept"):
			node_dict['animation_player'].play("jump_animation")
			if is_on_floor() or jump_vars['current_jump'] < jump_vars['max_jumps']:
				velocity.y = jump_vars['jump_velocity'] 
				# Jump forward to the direction you are going
				velocity.x = var_input_dir.x
				jump_vars['current_jump'] += 1
		elif Input.is_action_just_pressed("super_jump") and jump_vars['current_jump'] <= 3:
			node_dict['animation_player'].play("jump_animation")
			velocity.y = jump_vars['super_jump_velocity']
			velocity.x = var_input_dir.x
			jump_vars['current_jump'] += 1
func slide_timer(delta) :
	if current_state == State.SLIDING :
		timer_settings['slide_timer'] -= delta
	if timer_settings['slide_timer'] <= 0:
		current_state != State.SLIDING
		checks['free_look'] = false

func head_bob(delta,var_input_dir) :
	# Set current intensity and inddex based on state
	if current_state == State.RUNNING :
		head_bob_settings['current_intensity'] = head_bob_settings['sprint_intensity']
		head_bob_settings['index'] += head_bob_settings['sprint_speed'] * delta
	elif  current_state == State.WALKING :
		head_bob_settings['current_intensity'] = head_bob_settings['walk_intensity']
		head_bob_settings['index'] += head_bob_settings['walk_speed'] * delta
	elif current_state == State.CROUCHING :
		head_bob_settings['current_intensity'] = head_bob_settings['crouch_intensity']	
		head_bob_settings['index'] += head_bob_settings['crouch_speed'] * delta
	# Get vectors based on trigonometry and set eyes postion based on them 
	if is_on_floor() && current_state != State.SLIDING && var_input_dir != Vector2.ZERO :
		head_bob_settings['vector'].y = sin(head_bob_settings['index'])
		head_bob_settings['vector'].x = sin(head_bob_settings['index']/2) + 0.5
		node_dict['eyes'].position.y = lerp(node_dict['eyes'].position.y,head_bob_settings['vector'].y*(head_bob_settings['current_intensity']/2.0),delta* movement_speeds['LERP_SPEED'])
		node_dict['eyes'].position.x = lerp(node_dict['eyes'].position.x,head_bob_settings['vector'].x*(head_bob_settings['current_intensity']),delta* movement_speeds['LERP_SPEED'])
	else :
		node_dict['eyes'].position.y = lerp(node_dict['eyes'].position.y,0.0,delta* movement_speeds['LERP_SPEED'])
		node_dict['eyes'].position.x = lerp(node_dict['eyes'].position.x,0.0,delta* movement_speeds['LERP_SPEED'])

func _spawn_bullet():
	if Input.is_action_just_pressed("shoot"):
		var new_bullet = node_dict['bullet_scene'].instantiate()
		new_bullet.global_transform.origin = node_dict['camera_3d'].global_transform.origin # Start at camera's position
		add_child(new_bullet)
		# Shoot forward
		var shoot_direction = -node_dict['camera_3d'].global_transform.basis.z 
		new_bullet.apply_central_impulse(shoot_direction * 500)

func ground(delta) :
	if not is_on_floor():
		velocity.y -= jump_vars['gravity'] * delta
	else :
		jump_vars['current_jump'] = 0
		

func logging () :
	node_dict['label_1'].text = "Currwent state is " + State.keys()[current_state] + \
				   "\nSpeed is " + str(current_speed) + \
				   "\nNumber of jumps " + str(jump_vars['current_jump']

	)

