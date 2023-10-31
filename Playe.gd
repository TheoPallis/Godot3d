	# Wip from 20:00
extends CharacterBody3D

# Nodes 
# Body
@onready var neck = $neck
@onready var head = $neck/head
@onready var eyes = $neck/head/eyes
@onready var camera_3d = $neck/head/eyes/Camera3D
# Collision
@onready var standing_collision_shape = $standing_collision_shape
@onready var crouching_collision_shape = $crouching_collision_shape
@onready var ray_cast_3d = $RayCast3D
# Labels
@onready var label_1 = $"../Label"
@onready var label_2 = $"../Label2"
var bullet_scene = preload("res://ball.tscn")
@onready var bullet_spawn_point = $neck/head/eyes/Camera3D/Aim/BulletSpawn
@onready var aim_ray = $neck/head/eyes/Camera3D/Aim/AimRay
@onready var cross_hair = $neck/head/eyes/Camera3D/Aim/CrossHair
@onready var animation_player = $neck/head/eyes/AnimationPlayer

var setting = "air_movement"
var grappling = false
var hookpoint = Vector3()
var hookpoint_get=  false
#1) State vars
var walking = false
var running = false
var crouching = false
var sliding = false
var rolling = false
var stomping = false
var idle = false
var free_look = false
var can_wall_run = true
var col = 0
var norm = 0
#2) Movement speeds
var current_speed = 5.0
const walking_speed = 6.0
const running_speed = 10.0
const max_runnning_speed = 20.0
const max_lerp_speed = 5.0
const crouching_speed = 3.0
const dash_speed = 16.0
const super_dash_speed = 300

#3) Slide vars
var slide_timer = 0.0
var slide_timer_max = 1
var rolling_timer = 0.0
var rolling_timer_max = 1

var slide_speed = 10.0
var slide_vector = Vector2.ZERO


#4) Bob vars
const head_bob_sprint_speed = 22
const head_bob_walk_speed = 14
const head_bob_crouch_speed = 10

const head_bob_sprintintensity = 0.2
const head_bob_walk_intensity = 0.1
const head_bob_crouch_intensity = 0.05

var head_bob_vector = Vector2.ZERO
var head_bob_index= 0.0
var head_bob_current_intensity = 0.0

#5)  Jump vars
var max_jumps = 3
var current_jump = 0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") *  2
const JUMP_VELOCITY = 10
const super_jump_velocity = 15

#6)  Input vars
var direction = Vector3.ZERO
var sens = 0.83

# Rest vars
var crouching_depth = -0.5
var lerp_speed = 10.0  #gradually changes speed
var air_lerp_speed = 3.0  #gradually changes speed
const SLIDE_CAMERA_TILT_ANGLE = 15  # in degrees, you can adjust to your preference
var dagger = false
var bullet_speed = 200
var last_velocity = Vector3.ZERO
@onready var head_banger = $HeadBanger

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
func _physics_process(delta):
	var input_dir = Input.get_vector("left", "right", "up", "down")
	handle_slide(delta,input_dir)
	handle_roll(delta,input_dir)
	handle_free_look(delta,input_dir)
	movement(delta,input_dir)
	head_bob(delta,input_dir)
	ground(delta)
	
	
	handle_jump(input_dir)
	handle_landing()
	handle_dash(delta)
	handle_stomp(delta)		
	handle_wallrun(input_dir)	
	_spawn_bullet()
	last_velocity = velocity #get the velocity in the last frame(detect if player was in the air previously)
	move_and_slide()
	logging()

# Camera Movement :
# If free look: Rotate y of neck 
# else :  	    Rotate y of body
# Always :	    Rotate x of head
#😡 We need to use delta for the camera roation.z

func _input(event): #✅
	if event is InputEventMouseMotion :
		if free_look :
			neck.rotate_y(deg_to_rad(-event.relative.x * sens))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120),deg_to_rad(120))
			camera_3d.rotation.z = clamp(neck.rotation.y, deg_to_rad(-40),deg_to_rad(60))
#			camera_3d.rotation.z = lerp(camera_3d.rotation.z, 0.0,delta*lerp_speed)
		else :
			rotate_y(deg_to_rad(-event.relative.x * sens)) #by default it rotates by rads we need to rotate by degs
			camera_3d.rotation.z = 0.0
		head.rotate_x(deg_to_rad(-event.relative.y * sens))
		head.rotation.x = clamp(head.rotation.x,deg_to_rad(-89),deg_to_rad(89))



func handle_slide(delta,var_input_dir) :
	if Input.is_action_pressed("crouch") || sliding :
#		current_speed =  slide_speed # Set speed to sliding speed Theo		
		current_speed = lerp(current_speed,slide_speed,delta*lerp_speed)
		head.position.y = lerp(head.position.y,crouching_depth,delta * lerp_speed) # Lower the camera by the crouching depth gradually/lerp
					
		standing_collision_shape.disabled  = true  
		crouching_collision_shape.disabled = false # Use the crouching collision

		#1️⃣ Slide state
		if running and direction != Vector3.ZERO  : # If the player is running in a direction (and he is either crouching or sliding)
			sliding = true # Set sliding to true
			slide_timer = slide_timer_max # Reset the countdown timer 
			slide_vector = var_input_dir # Get the direction of the slide from the general direction
			free_look = true # Enable free look
	# Ensure that the player is in the sliding or crouching state only	
		walking = false
		running = false
		crouching = true

	# Crouching state
	elif  !ray_cast_3d.is_colliding() : # If there is not somethihng above the player
		#Standing 
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true # Use the standing collision
		head.position.y = lerp(head.position.y,0.0,delta * lerp_speed)  #Reset the camera gradually to the 0.0 position
		
		# Set speeds and states (running or walking only)
		if Input.is_action_pressed("run") : 
#			current_speed = running_speed theo
			# Accelerate to max speed
			current_speed = lerp(current_speed,max_runnning_speed,delta * 0.1)
			walking = false
			running =  true
			crouching = false
		
		else : 
			current_speed = lerp(current_speed,walking_speed,delta * lerp_speed)
			walking = true
			running =  false
			crouching = false
# Need to press it continuously

func handle_roll(delta, var_input_dir) :
	if Input.is_action_just_pressed('roll') and not rolling:
		rolling = true
		animation_player.play(("rolling_animation"))
		rolling_timer = rolling_timer_max
		standing_collision_shape.disabled  = true  
		crouching_collision_shape.disabled = false
	if rolling:
		print("rolling")
		# Move character forward in the direction of roll
		direction = transform.basis.z * -current_speed
		velocity.x = direction.x
		velocity.z = direction.z
		# Simulate camera motion for roll (roll the camera)		
		rolling_timer -= delta
		if rolling_timer <= 0:    
			rolling = false
			standing_collision_shape.disabled  = false
			crouching_collision_shape.disabled = true
			

				
		
			
			
# if isnput is action pressed free look	 -> 5:00
func handle_free_look(delta, var_input_dir):
	if Input.is_action_pressed("freelook") or sliding or (is_on_wall() &&  Input.is_action_pressed("wall_run") && can_wall_run):
		free_look = true 
		if sliding:
			# First encountered on 12:00 - 15:00	-> Tilt the camera if sliding
			eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(SLIDE_CAMERA_TILT_ANGLE), delta*lerp_speed)
		else:
			eyes.rotation.z = -deg_to_rad(neck.rotation.y * -deg_to_rad(SLIDE_CAMERA_TILT_ANGLE))
	else:
		free_look = false
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta*lerp_speed)
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta*lerp_speed)

				#direction = -wall_normal.normal * current_speed

func movement(delta,var_input_dir):	
	if setting == "no_air_movement" : 
		if is_on_floor() :
			direction = lerp(direction,transform.basis * Vector3(var_input_dir.x, 0, var_input_dir.y).normalized(),delta*lerp_speed) #prevent changing direction in the air
		else : # If the player has a direction in the air / presses any movement button
			if direction != Vector2.ZERO :
				direction = lerp(direction,transform.basis * Vector3(var_input_dir.x, 0, var_input_dir.y).normalized(),delta*air_lerp_speed)
			
	elif setting == "air_movement" : 	
		direction = transform.basis * Vector3(var_input_dir.x, 0, var_input_dir.y).normalized()
	if sliding || rolling:
		direction = (transform.basis * Vector3(slide_vector.x,0,slide_vector.y)).normalized()
		#current_speed = (slide_timer+0.1) * slide_speed -? Use this to slow down on slide
		velocity.x = direction.x * (slide_timer )  * slide_speed #prevent from reaching zero
		velocity.z = direction.z * (slide_timer ) * slide_speed
		slide_timer -= delta
		if slide_timer <= 0:
			sliding = false
			rolling = false
			free_look = false
			slide_vector = var_input_dir
			
	if direction :
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)


func head_bob(delta,var_input_dir) :
	if running :
		head_bob_current_intensity = head_bob_sprintintensity
		head_bob_index += head_bob_sprint_speed * delta
	elif walking :
		head_bob_current_intensity = head_bob_walk_intensity
		head_bob_index += head_bob_walk_speed * delta
	elif crouching :
		head_bob_current_intensity = head_bob_crouch_intensity	
		head_bob_index += head_bob_crouch_speed * delta
	if is_on_floor() && !sliding && var_input_dir != Vector2.ZERO :
		head_bob_vector.y = sin(head_bob_index)
		head_bob_vector.x = sin(head_bob_index/2) + 0.5
		eyes.position.y = lerp(eyes.position.y,head_bob_vector.y*(head_bob_current_intensity/2.0),delta* lerp_speed)
		eyes.position.x = lerp(eyes.position.x,head_bob_vector.x*(head_bob_current_intensity),delta* lerp_speed)
	else :
		eyes.position.y = lerp(eyes.position.y,0.0,delta* lerp_speed)
		eyes.position.x = lerp(eyes.position.x,0.0,delta* lerp_speed)
		
		
#	direction = lerp(direction,transform.basis * Vector3(input_dir.x, 0, input_dir.y).normalized(),delta)

func ground(delta) :
	if not is_on_floor():
		velocity.y -= gravity * delta
		can_wall_run = true
	else :
		current_jump = 0
		can_wall_run = true


#func _grapple() :
# =2:38 if input is action pressed crouch

# Jumping Section
func handle_jump(var_input_dir):
	if Input.is_action_just_pressed("ui_accept"):
		animation_player.play("jump_animation")
		if is_on_floor() or current_jump < max_jumps:
			velocity.y = JUMP_VELOCITY 
			# Jump forward to the direction you are going
			velocity.x = var_input_dir.x
			current_jump += 1
	elif Input.is_action_just_pressed("super_jump") and current_jump <= 3:
			animation_player.play("jump_animation")
			velocity.y = super_jump_velocity
			velocity.x = var_input_dir.x
			current_jump += 1
		
func handle_landing() :
	if is_on_floor() :
		if last_velocity.y < -0.9 : # If we were in the air last frame
			animation_player.play("landing_animation")
# Wall Run Section		
func handle_dash(delta) :
	if direction && !Input.is_action_just_pressed("dash") && !Input.is_action_just_pressed("super_dash") :
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	elif direction && Input.is_action_just_pressed("super_dash"):
		velocity.x = direction.x * current_speed * super_dash_speed
		velocity.z = direction.z * current_speed * super_dash_speed
		print("super")
	elif direction && Input.is_action_just_pressed("dash"):
		velocity.x = direction.x * dash_speed  * current_speed
		velocity.z = direction.z  * dash_speed	* current_speed
		print('dash')

func handle_stomp(delta) :
	if !is_on_floor() and Input.is_action_pressed("stomp") :
		stomping = true
		velocity.y = lerp(velocity.y,3,delta*lerp_speed)
	else :
		stomping = false
		
func handle_wallrun(var_input_dir) :
	if can_wall_run :
		if is_on_wall() :
			if Input.is_action_pressed("wall_run") :
				velocity.y  = JUMP_VELOCITY
				velocity.x = var_input_dir.x
				current_jump = 0
				var wall_normal = get_slide_collision(0)
				await(get_tree().create_timer(0.2))

func _spawn_bullet():
	if Input.is_action_just_pressed("shoot"):
		var new_bullet = bullet_scene.instantiate()
		new_bullet.global_transform.origin = camera_3d.global_transform.origin # Start at camera's position
		add_child(new_bullet)
		var shoot_direction = -camera_3d.global_transform.basis.z 
		new_bullet.apply_central_impulse(shoot_direction * 500)

		
func logging () :
	pass
	label_1.text = "Grappling is " + str(grappling) + "\nCamera rotation z is " + str(camera_3d.rotation.z) + "\nSliding is " + str(sliding) + "\nRunning is " + str(running) + "\nCrouching is " + str(crouching) + "\n Free look is "  + str(free_look) + "\n Speed is " + str(current_speed) + "\n Number of jumps  " + str(current_jump)		

#	if Input.is_action_just_pressed("y") :
#		grappling = false
#		gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
#a
#	elif Input.is_action_just_pressed(("hook")) :
#		if grapple_cast_ray_cast.is_colliding() :
#			if not grappling:
#				grappling = true
#	if grappling :
#		gravity = 0
#		if not hookpoint_get :
#			hookpoint = grapple_cast_ray_cast.get_collision_point()	+ Vector3(0,2.25,0)
#			hookpoint_get = true
#	if transform.origin != null :
#		if hookpoint.distance_to(transform.origin) > 1 :
#			if hookpoint_get :
#				transform.origin = lerp(transform.origin, hookpoint,0.05)
#		else :
#			grappling = false
#			hookpoint_get = false
#		if head_banger.is_colliding():
#			grappling = false
#			hookpoint = null
#			hookpoint_get = false
#			global_translate(Vector3(0,-1,0) )
