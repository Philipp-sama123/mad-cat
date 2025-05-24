extends CharacterBody2D

# --- CONFIG ---
const WALK_SPEED       = 25.0
const RUN_SPEED        = 50.0
const ACCELERATION     = 400.0
const FRICTION         = 600.0
const JUMP_VELOCITY    = -300.0
const GRAVITY          = 900.0
const COYOTE_TIME      = 0.5        # shortened for tighter control
const JUMP_BUFFER_TIME = 0.1
const DODGE_SPEED      = 150.0
const DODGE_COOLDOWN   = 0.6
const DODGE_DURATION   = 0.3        # quicker dodge
const WALL_JUMP_H      = 200.0
const WALL_JUMP_V      = -300.0
const CLIMB_SPEED      = 15.0

# --- NODES ---
@onready var sprite         = $Sprite2D
@onready var anim_player    = $AnimationPlayer
@onready var ray_wall       = $CollisionShape2D/RayCast_Wall
@onready var ray_ledge      = $CollisionShape2D/RayCast_Ledge
@onready var col_shape      = $CollisionShape2D
@onready var attack_area    = $AttackArea
@onready var attack_collider= $AttackArea/CollisionShape2D

# --- STATE ---
var was_on_floor           = false
var coyote_timer           = 0.0
var jump_buffer            = 0.0
var dodge_cd               = 0.0
var is_dodging             = false
var dodge_timer            = 0.0
var is_climbing            = false
var is_ledge_climbing      = false
var ledge_normal           = Vector2.ZERO
var airborne_state         = ""
var is_attacking           = false

func _ready():
	was_on_floor = is_on_floor()
	anim_player.animation_finished.connect(_on_animation_finished)
	attack_collider.disabled = true
	attack_area.connect("area_entered", Callable(self, "_on_attack_area_entered"))
	attack_area.connect("body_entered", Callable(self, "_on_attack_area_entered_body"))

func _on_attack_area_entered(area: Area2D) -> void:
	print("PLAYER -area _on_attack_area_entered",area)

	if area.has_method("take_damage"):
		area.take_damage()

func _on_attack_area_entered_body(body: CharacterBody2D) -> void:
	print("PLAYER -body _on_attack_area_entered",body)

	if body.has_method("take_damage"):
		body.take_damage()
func _physics_process(delta: float) -> void:
	# --- UPDATE TIMERS ---
	coyote_timer = COYOTE_TIME if is_on_floor() else max(coyote_timer - delta, 0)
	jump_buffer  = max(jump_buffer - delta, 0)
	dodge_cd     = max(dodge_cd - delta, 0)

	# skip movement during ledge climb
	if is_ledge_climbing:
		return

	# input
	var dir = Input.get_axis("Left", "Right")
	if Input.is_action_just_pressed("Jump"):
		jump_buffer = JUMP_BUFFER_TIME
	var wants_dodge  = Input.is_action_just_pressed("Dash")
	var wants_attack = Input.is_action_just_pressed("Attack")
	var is_running   = Input.is_action_pressed("Run")

	# wall climb start/end
	if not is_on_floor() and ray_wall.is_colliding() and Input.is_action_pressed("Up"):
		if not is_climbing:
			_start_climb()
	elif is_climbing:
		_end_climb()

	# ledge detect
	if is_climbing and _check_for_ledge():
		_start_ledge_climb()
		return

	# climb motion
	if is_climbing:
		_climb_motion(delta)
		return

	# jumps
	if jump_buffer > 0:
		if not is_on_floor() and is_on_wall():
			_do_wall_jump()
			jump_buffer = 0
		elif coyote_timer > 0:
			_do_jump()
			jump_buffer = 0

	# gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# attack
	if wants_attack and not is_dodging and not is_attacking:
		_start_attack()

	# dodge
	if wants_dodge and dodge_cd <= 0 and not is_dodging and not is_attacking:
		_start_dodge()
	if is_dodging:
		_update_dodge(delta)

	# horizontal movement
	if not is_dodging and not is_attacking:
		_walk_run(dir, is_running, delta)

	# move & slide
	move_and_slide()

	# landing detection
	if not was_on_floor and is_on_floor():
		_play_animation("Land")
		airborne_state = ""

	_update_animation(dir)
	was_on_floor = is_on_floor()

# --- ACTIONS ---
func _start_climb():
	is_climbing = true
	velocity = Vector2.ZERO
	_play_animation("WallClimb")

func _end_climb():
	is_climbing = false
	# grant coyote time after climbing
	coyote_timer = COYOTE_TIME
	if not is_on_floor():
		airborne_state = "fall"
		_play_animation("Fall")

func _start_ledge_climb():
	is_climbing = false
	is_ledge_climbing = true
	ledge_normal = ray_wall.get_collision_normal()
	var ext = (col_shape.shape as RectangleShape2D).extents
	var end_pos = global_position + Vector2(-ledge_normal.x * ext.x, -ext.y)
	var t = create_tween()
	t.tween_property(self, "global_position", end_pos, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_play_animation("LedgeStuck")
	# grant jump window while climbing
	coyote_timer = COYOTE_TIME

func _climb_motion(delta: float) -> void:
	velocity = Vector2.ZERO
	velocity.y = -Input.get_axis("Down", "Up") * CLIMB_SPEED
	move_and_slide()

func _do_wall_jump():
	var collision = get_last_slide_collision()
	if collision:
		var normal = collision.get_normal()
		velocity.x = -normal.x * WALL_JUMP_H
		velocity.y = WALL_JUMP_V
		airborne_state = "jump"
		_play_animation("Jump")
		coyote_timer = 0

func _do_jump():
	velocity.y = JUMP_VELOCITY
	airborne_state = "jump"
	_play_animation("Jump")
	coyote_timer = 0

func _start_attack():
	is_attacking = true
	attack_collider.disabled = false
	_play_animation("Attack")

func _start_dodge():
	is_dodging = true
	dodge_cd = DODGE_COOLDOWN
	dodge_timer = DODGE_DURATION
	velocity.x = (-1 if sprite.flip_h else 1) * DODGE_SPEED
	_play_animation("Dash")

func _update_dodge(delta: float) -> void:
	dodge_timer -= delta
	velocity.x = (-1 if sprite.flip_h else 1) * DODGE_SPEED
	if dodge_timer <= 0:
		is_dodging = false

func _walk_run(dir: float, running: bool, delta: float) -> void:
	if dir == 0 and is_on_floor():
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
	else:
		var target = dir * (RUN_SPEED if running else WALK_SPEED)
		velocity.x = move_toward(velocity.x, target, ACCELERATION * delta)
	if dir != 0:
		sprite.flip_h = dir < 0
		col_shape.scale.x = -1 if sprite.flip_h else 1
		attack_area.scale.x = col_shape.scale.x

func _update_animation(dir: float) -> void:
	if is_attacking or is_dodging:
		return
	if not is_on_floor():
		if velocity.y > 0 and airborne_state != "fall":
			_play_animation("Fall")
			airborne_state = "fall"
	else:
		if abs(dir) > 0:
			_play_animation("Run" if Input.is_action_pressed("Run") else "Walk")
		else:
			_play_animation("Idle")

func _play_animation(name: String) -> void:
	if anim_player.current_animation != name:
		anim_player.play(name)

func _on_animation_finished(anim: String) -> void:
	match anim:
		"Attack":
			is_attacking = false
			attack_collider.disabled = true
		"Land":
			_play_animation("Idle")
		"Dash":
			is_dodging = false
		"LedgeStuck":
			_play_animation("LedgeClimb")
		"LedgeClimb":
			is_ledge_climbing = false
			var ext = (col_shape.shape as RectangleShape2D).extents
			global_position += Vector2(-ledge_normal.x * ext.x, -ext.y)
			_play_animation("Idle")

func _check_for_ledge() -> bool:
	ray_wall.force_raycast_update()
	ray_ledge.force_raycast_update()
	return ray_wall.is_colliding() and not ray_ledge.is_colliding()
