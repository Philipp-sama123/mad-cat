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

const CLIMB_SPEED = 60.0

# --- NODES ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# --- STATE ---
var was_on_floor := false
var coyote_timer := 0.0
var jump_buffer := 0.0
var dodge_cd := 0.0
var is_dodging := false
var is_attacking := false
var dodge_timer := 0.0

var is_climbing := false # ← NEW: are we in climb mode?

var airborne_state := ""

func _ready():
	was_on_floor = is_on_floor()
	anim_player.animation_finished.connect(_on_animation_finished)

func _physics_process(delta):
	# ── Timers
	coyote_timer = COYOTE_TIME if is_on_floor() else coyote_timer - delta
	jump_buffer = max(0.0, jump_buffer - delta)
	dodge_cd = max(0.0, dodge_cd - delta)

	# ── Input
	var dir = Input.get_axis("Left", "Right")
	var wants_jump = Input.is_action_just_pressed("Jump")
	var wants_dodge = Input.is_action_just_pressed("Dash")
	var wants_attack = Input.is_action_just_pressed("Attack")
	var is_running = Input.is_action_pressed("Run")
	if wants_jump:
		jump_buffer = JUMP_BUFFER


	# ── WALL CLIMB START/END ────────────────────────────────────────────
	# If you’re in mid-air, touching a wall, and holding up → start climb
	if not is_on_floor() and is_on_wall() and Input.is_action_pressed("Up"):
		print_debug("Try to climb")
		if not is_climbing:
			is_climbing = true
			velocity = Vector2.ZERO
			_play_animation("WallClimb")
	else:
		# if you drop off the wall or let go of Up, exit climb state
		if is_climbing:
			is_climbing = false
				# immediately go into fall state so you don’t snap back to idle
			airborne_state = "fall"
			_play_animation("Fall")

	# ── HANDLE CLIMB MOTION ──────────────────────────────────────────────
	if is_climbing:
		# you only move vertically
		var climb_dir = Input.get_axis("Down", "Up")
		velocity.y = - climb_dir * CLIMB_SPEED
		# no gravity while climbing!
		# skip the normal gravity & move_and_slide for a pure climb
		move_and_slide()
		return # skip all other movement & animation logic

	# ── WALL JUMP
	if jump_buffer > 0 and not is_on_floor() and is_on_wall():
		var col = get_last_slide_collision()
		var wall_normal = col.get_normal()
		velocity.x = - wall_normal.x * WALL_JUMP_H_SPEED
		velocity.y = WALL_JUMP_V_SPEED
		_play_animation("Jump")
		jump_buffer = 0
		coyote_timer = 0
		airborne_state = "jump"
	# ── REGULAR JUMP
	elif jump_buffer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		_play_animation("Jump")
		jump_buffer = 0
		coyote_timer = 0
		airborne_state = "jump"

	# ── Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# ── Attack
	if wants_attack and not is_attacking and not is_dodging:
		is_attacking = true
		_play_animation("Attack")

	# ── Dodge
	if wants_dodge and dodge_cd <= 0 and not is_attacking and not is_dodging:
		is_dodging = true
		dodge_cd = DODGE_COOLDOWN
		dodge_timer = DODGE_DURATION
		var dir_sign = -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		_play_animation("Dash")
	if is_dodging:
		dodge_timer -= delta
		var dir_sign = -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		if dodge_timer <= 0:
			is_dodging = false

	# ── Horizontal Movement
	if not is_dodging and not is_attacking:
		if dir == 0 and is_on_floor():
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		else:
			var target = dir * (RUN_SPEED if is_running else WALK_SPEED)
			velocity.x = move_toward(velocity.x, target, ACCEL * delta)
		if dir != 0:
			sprite.flip_h = dir < 0


	# ── Move & Slide
	move_and_slide()

	# ── Landing
	if not was_on_floor and is_on_floor():
		_play_animation("Land")
		airborne_state = ""
	was_on_floor = is_on_floor()

	# ── Airborne Animations
	if not is_on_floor() and not is_dodging and not is_attacking:
		# just left the ground → already handled by was_on_floor check above
		# now if you switch from going up to down, trigger Fall once:
		if velocity.y > 0 and airborne_state != "fall":
			_play_animation("Fall")
			airborne_state = "fall"
	# ── Ground Animations
	elif is_on_floor() and not is_dodging and not is_attacking:
		if abs(dir) > 0:
			_play_animation("Run" if is_running else "Walk")
		else:
			_play_animation("Idle")


func _play_animation(anim_name: String) -> void:
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

func _on_animation_finished(finished_name: String) -> void:
	match finished_name:
		"Attack":
			is_attacking = false
		"Land":
			_play_animation("Idle")
			is_attacking = false
		"Dash":
			is_dodging = false
