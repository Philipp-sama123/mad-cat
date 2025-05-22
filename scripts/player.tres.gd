extends CharacterBody2D

# --- CONFIG ---
const WALK_SPEED          = 25.0
const RUN_SPEED           = 50.0
const ACCEL               = 400.0
const FRICTION            = 600.0
const JUMP_VELOCITY       = -300.0
const GRAVITY             = 900.0
const COYOTE_TIME         = 0.25
const JUMP_BUFFER         = 0.1
const DODGE_SPEED         = 150.0
const DODGE_COOLDOWN      = 0.6
const DODGE_DURATION      = 0.6
# ← New wall-jump constants
const WALL_JUMP_H_SPEED   = 200.0
const WALL_JUMP_V_SPEED   = -300.0

# --- NODES ---
@onready var sprite      : Sprite2D        = $Sprite2D
@onready var anim_player : AnimationPlayer = $AnimationPlayer

# --- STATE ---
var was_on_floor   := false
var coyote_timer   := 0.0
var jump_buffer    := 0.0
var dodge_cd       := 0.0
var is_dodging     := false
var is_attacking   := false
var dodge_timer    := 0.0

func _ready():
	was_on_floor = is_on_floor()
	anim_player.animation_finished.connect(_on_animation_finished)

func _physics_process(delta):
	# ── Timers
	coyote_timer = COYOTE_TIME if is_on_floor() else coyote_timer - delta
	jump_buffer  = max(0.0, jump_buffer - delta)
	dodge_cd     = max(0.0, dodge_cd    - delta)

	# ── Input
	var dir          = Input.get_axis("Left", "Right")
	var wants_jump   = Input.is_action_just_pressed("Jump")
	var wants_dodge  = Input.is_action_just_pressed("Dash")
	var wants_attack = Input.is_action_just_pressed("Attack")
	var is_running   = Input.is_action_pressed("Run")
	if wants_jump:
		jump_buffer = JUMP_BUFFER

	# ── WALL JUMP (small addition!)
	if jump_buffer > 0 and not is_on_floor() and is_on_wall():
		# grab the wall normal from the last collision
		var col = get_last_slide_collision()
		var wall_normal = col.get_normal()
		# push off horizontally and vertically
		velocity.x = -wall_normal.x * WALL_JUMP_H_SPEED
		velocity.y = WALL_JUMP_V_SPEED
		_play_animation("Jump")
		jump_buffer = 0
		coyote_timer = 0
	# ── REGULAR JUMP (buffer + coyote)
	elif jump_buffer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		_play_animation("Jump")
		jump_buffer = 0
		coyote_timer = 0

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
		dodge_cd   = DODGE_COOLDOWN
		dodge_timer = DODGE_DURATION
		var dir_sign = -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		_play_animation("Dash")
	if is_dodging:
		dodge_timer -= delta
		var dir_sign = -1 if sprite.flip_h else 1
		velocity.x = dir_sign * DODGE_SPEED
		if dodge_timer <= 0.0:
			is_dodging = false

	# ── Horizontal Movement (when free)
	if not is_dodging and not is_attacking:
		if dir == 0 and is_on_floor():
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		else:
			var target = dir * (RUN_SPEED if is_running else WALK_SPEED)
			velocity.x = move_toward(velocity.x, target, ACCEL * delta)
		if dir != 0:
			sprite.flip_h = dir < 0

	# ── move & slide
	move_and_slide()

	# ── Landing
	if not was_on_floor and is_on_floor():
		_play_animation("Land")
	was_on_floor = is_on_floor()

	# ── Airborne animations
	if not is_on_floor() and not is_dodging and not is_attacking:
		if velocity.y < 0 and anim_player.current_animation != "Jump":
			_play_animation("Jump")
		elif velocity.y > 0 and anim_player.current_animation != "Fall":
			_play_animation("Fall")
	# ── Ground animations
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
