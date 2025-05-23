extends CharacterBody2D

# --- CONFIG ---
const WALK_SPEED = 25.0
const RUN_SPEED = 50.0
const ACCEL = 400.0
const FRICTION = 600.0
const JUMP_VELOCITY = -300.0
const GRAVITY = 900.0
const COYOTE_TIME = 0.25
const JUMP_BUFFER = 0.1
const DODGE_SPEED = 150.0
const DODGE_COOLDOWN = 0.6
const DODGE_DURATION = 0.6
const WALL_JUMP_H_SPEED = 200.0
const WALL_JUMP_V_SPEED = -300.0
const CLIMB_SPEED = 15.0

# --- NODES ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var ray_ledge: RayCast2D = $CollisionShape2D/RayCast_Ledge
@onready var ray_wall: RayCast2D = $CollisionShape2D/RayCast_Wall
@onready var col_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area:Area2D            = $AttackArea
@onready var attack_collider:CollisionShape2D            = $AttackArea/CollisionShape2D
# --- STATE ---
var was_on_floor := false
var coyote_timer := 0.0
var jump_buffer := 0.0
var dodge_cd := 0.0
var is_dodging := false
var is_attacking := false
var dodge_timer := 0.0
var is_ledge_climbing := false
var ledge_normal := Vector2.ZERO
var is_climbing := false
var airborne_state := ""

func _ready():
	was_on_floor = is_on_floor()
	anim_player.animation_finished.connect(_on_animation_finished)
	attack_collider.set_deferred("disabled",true)
	
	# Connect the area_entered signal on the attack-area
	attack_area.connect(
		"area_entered",
		Callable(self, "_on_attack_area_entered")
	)

func _on_attack_area_entered(area: Area2D) -> void:
	# only hit actual destructible objects
	print(area,"area")
	print(area.has_method("take_damage"))
	if area.has_method("take_damage"):
		# call its exposed method
		area.take_damage()


func _physics_process(delta):
	if is_ledge_climbing:
		return

	# if attacking, don’t move at all
	if is_attacking:
		velocity = Vector2.ZERO
		return
	# --- TIMERS ---
	coyote_timer = COYOTE_TIME if is_on_floor() else coyote_timer - delta
	jump_buffer = max(0.0, jump_buffer - delta)
	dodge_cd = max(0.0, dodge_cd - delta)

	# --- INPUT ---
	var dir = Input.get_axis("Left", "Right")
	if Input.is_action_just_pressed("Jump"):
		jump_buffer = JUMP_BUFFER
	var wants_dodge = Input.is_action_just_pressed("Dash")
	var wants_attack = Input.is_action_just_pressed("Attack")
	var is_running = Input.is_action_pressed("Run")

	# --- WALL CLIMB START/END ---
	var can_climb = not is_on_floor() and ray_wall.is_colliding() and Input.is_action_pressed("Up")
	
	if can_climb:
		if not is_climbing:
			is_climbing = true
			velocity = Vector2.ZERO
			_play_animation("WallClimb")
	elif is_climbing:
		is_climbing = false
		if not is_on_floor():
			airborne_state = "fall"
			_play_animation("Fall")

	# --- LEDGE DETECTION ---
	if is_climbing and check_for_ledge():
		is_climbing = false
		is_ledge_climbing = true
		ledge_normal = ray_wall.get_collision_normal()

		var cap = col_shape.shape as RectangleShape2D
		var ext = cap.extents

		# calculate the 2D end‐position
		var start_pos = global_position
		var end_pos = start_pos + Vector2(0, -ext.y)
		end_pos.x += -ledge_normal.x * ext.x # ToDo: make this fit better to the animation!
		# get the real animation duration
		var duration = .5
		# create and drive the tween
		var t = create_tween()
		t.tween_property(self, "global_position", end_pos, duration) \
		 .set_trans(Tween.TRANS_QUAD) \
		 .set_ease(Tween.EASE_IN_OUT)

		anim_player.play("LedgeStuck")
		return


	# --- CLIMB MOTION ---
	if is_climbing:
		# lock horizontal and vertical movement to climbing
		velocity = Vector2.ZERO
		var climb_dir = Input.get_axis("Down", "Up")
		velocity.y = -climb_dir * CLIMB_SPEED
		move_and_slide()
		return

	# --- WALL JUMP ---
	if jump_buffer > 0 and not is_on_floor() and is_on_wall():
		var col = get_last_slide_collision()
		var wall_normal = col.get_normal()
		velocity.x = -wall_normal.x * WALL_JUMP_H_SPEED
		velocity.y = WALL_JUMP_V_SPEED
		_play_animation("Jump")
		jump_buffer = 0.0
		coyote_timer = 0.0
		airborne_state = "jump"
	# --- REGULAR JUMP ---
	elif jump_buffer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		_play_animation("Jump")
		jump_buffer = 0.0
		coyote_timer = 0.0
		airborne_state = "jump"

	# --- GRAVITY ---
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# --- ATTACK ---
	if wants_attack and not is_attacking and not is_dodging:
		is_attacking = true
		attack_collider.set_deferred("disabled",false)
		_play_animation("Attack")

	# --- DODGE ---
	if wants_dodge and dodge_cd <= 0 and not is_attacking and not is_dodging:
		is_dodging = true
		dodge_cd = DODGE_COOLDOWN
		dodge_timer = DODGE_DURATION
		var dir_sign = -1 if sprite.flip_h else 1
		col_shape.scale.x =  -1 if sprite.flip_h else 1
		attack_area.scale.x =  -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		_play_animation("Dash")
	if is_dodging:
		dodge_timer -= delta
		var dir_sign = -1 if sprite.flip_h else 1
		col_shape.scale.x =  -1 if sprite.flip_h else 1
		attack_area.scale.x =  -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		if dodge_timer <= 0.0:
			is_dodging = false

	# --- HORIZONTAL MOVEMENT ---
	if not is_dodging and not is_attacking:
		if dir == 0 and is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		else:
			var speed = RUN_SPEED if is_running else WALK_SPEED
			var target = dir * speed
			velocity.x = move_toward(velocity.x, target, ACCEL * delta)
		if dir != 0:
			sprite.flip_h = dir < 0
			col_shape.scale.x =  -1 if sprite.flip_h else 1
			attack_area.scale.x =  -1 if sprite.flip_h else 1

	# --- MOVE & SLIDE ---
	move_and_slide()

	# --- LANDING ---
	if not was_on_floor and is_on_floor():
		_play_animation("Land")
		airborne_state = ""
	was_on_floor = is_on_floor()

	# --- AIRBORNE/GROUND ANIMATIONS ---
	if not is_on_floor() and not is_dodging and not is_attacking:
		if velocity.y > 0.0 and airborne_state != "fall":
			_play_animation("Fall")
			airborne_state = "fall"
	elif is_on_floor() and not is_dodging and not is_attacking:
		if abs(dir) > 0.0:
			_play_animation( "Run" if is_running else "Walk")
		else:
			_play_animation("Idle")

func _play_animation(anim_name: String) -> void:
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

func _on_animation_finished(finished_name: String) -> void:
	match finished_name:
		"Attack":
			is_attacking = false
			attack_collider.set_deferred("disabled",true)
		"Land":
			_play_animation("Idle")
			is_attacking = false
		"Dash":
			is_dodging = false
		"LedgeClimb":
			is_ledge_climbing = false
			var cap = col_shape.shape as RectangleShape2D
			var ext = cap.extents

			# calculate the 2D end‐position
			var start_pos = global_position
			var end_pos = start_pos + Vector2(0, -ext.y)
			end_pos.x += -ledge_normal.x * ext.x # ToDo: make this fit better to the animation!
			global_position = end_pos
			_play_animation("Idle")
		"LedgeStuck":
			anim_player.play("LedgeClimb")

func check_for_ledge() -> bool:
	ray_ledge.force_raycast_update()
	ray_wall.force_raycast_update()
	return ray_wall.is_colliding() and not ray_ledge.is_colliding()
