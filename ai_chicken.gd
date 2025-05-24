extends CharacterBody2D

# --- CONFIG ---
const WALK_SPEED               = 25.0
const RUN_SPEED                = 50.0
const ACCELERATION             = 100.0
const FRICTION                 = 250.0
const GRAVITY                  = 900.0
const FLEE_SPEED               = 50.0
const FLEE_RADIUS              = 50.0
const PECK_DURATION            = 1.5
const WANDER_CHANGE_INTERVAL   = 2.0

# --- FLY CONFIG ---
const STATE_FLY                = 5
const FLY_MIN_DURATION         = 5.0
const FLY_MAX_DURATION         = 10.0
const FLY_RADIUS               = 30.0

# --- STATES ---
const STATE_IDLE               = 0
const STATE_WANDER             = 1
const STATE_FLEE               = 2
const STATE_PECK               = 3
const STATE_HIT                = 4

# --- NODES ---
@onready var sprite            = $Sprite2D
@onready var anim_player       = $Sprite2D/AnimationPlayer
@onready var ray_front         = $RayCast2D
@onready var player            = get_parent().get_node_or_null("Player")

# --- STATE VARS ---
var state                      = STATE_IDLE
var timer: float               = 0.0
var direction: int             = 1               # +1 right, -1 left
var health: int                = 10

# --- FLY VARS ---
var fly_center: Vector2
var fly_duration: float        = 0.0
var fly_timer: float           = 0.0
var fly_angle: float           = 0.0
var fly_ang_speed: float       = 0.0

func _ready():
	ray_front.enabled = true
	_enter_state(STATE_WANDER)

func _physics_process(delta: float) -> void:
	if state == STATE_FLY:
		# orbit around the center
		fly_timer -= delta
		fly_angle += fly_ang_speed * delta
		global_position = fly_center + Vector2(cos(fly_angle), sin(fly_angle)) * FLY_RADIUS
		if fly_timer <= 0:
			_enter_state(STATE_IDLE)
		return

	# apply gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# flee trigger
	if player and global_position.distance_to(player.global_position) < FLEE_RADIUS and state not in [STATE_HIT, STATE_FLY]:
		_enter_state(STATE_FLEE)
	elif state == STATE_FLEE and (not player or global_position.distance_to(player.global_position) >= FLEE_RADIUS):
		_enter_state(STATE_WANDER)

	# decrement state timer
	timer -= delta
	if state == STATE_HIT and timer <= 0:
		_enter_state(STATE_WANDER)

	match state:
		STATE_IDLE:
			if timer <= 0:
				_enter_state(STATE_WANDER)
		STATE_WANDER:
			if ray_front.is_colliding():
				direction *= -1
				ray_front.target_position.x = abs(ray_front.target_position.x) * direction
			if timer <= 0:
				# for debugging: always fly (10/10)
				_enter_state(STATE_FLY)
			velocity.x = direction * WALK_SPEED
		STATE_FLEE:
			var dir_sign = sign(global_position.x - player.global_position.x)
			direction = dir_sign
			velocity.x = dir_sign * FLEE_SPEED
		STATE_PECK:
			velocity.x = 0
			if timer <= 0:
				_enter_state(STATE_WANDER)

	# friction & acceleration
	if state in [STATE_WANDER, STATE_FLEE]:
		velocity.x = move_toward(velocity.x, velocity.x, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

	move_and_slide()
	_update_animation()

func _enter_state(new_state: int) -> void:
	state = new_state
	match state:
		STATE_HIT:
			velocity.x = 0
			timer = anim_player.get_animation("Hit").length
			_play_animation("Hit")
		STATE_IDLE:
			timer = randf_range(1.0, WANDER_CHANGE_INTERVAL)
			_play_animation("Idle")
		STATE_WANDER:
			direction = -1 if randi() % 2 == 0 else 1
			ray_front.target_position = Vector2(16 * direction, 0)
			timer = WANDER_CHANGE_INTERVAL
			_play_animation("Walk")
		STATE_FLEE:
			_play_animation("Run")
		STATE_PECK:
			timer = PECK_DURATION
			_play_animation("Peck")
		STATE_FLY:
			# initialize fly (invulnerable) circling
			fly_center = global_position
			fly_duration = randf_range(FLY_MIN_DURATION, FLY_MAX_DURATION)
			fly_timer = fly_duration
			fly_ang_speed = TAU / fly_duration
			fly_angle = 0.0
			_play_animation("Fly")

func _update_animation() -> void:
	var current = anim_player.current_animation
	if current in ["Hit", "Die", "Peck", "Fly"]:
		return
	sprite.flip_h = direction < 0
	if state == STATE_FLEE and current != "Run":
		_play_animation("Run")

func _play_animation(anim_name: String) -> void:
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

# --- DAMAGE HANDLING ---
func take_damage(amount: int = 1) -> void:
	if state == STATE_FLY:
		return
	health -= amount
	if health <= 0:
		_die()
	else:
		_enter_state(STATE_HIT)

func _die() -> void:
	_play_animation("Die")
	set_physics_process(false)
