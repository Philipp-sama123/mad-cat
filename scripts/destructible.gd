extends Area2D

@export var hits_to_destroy := 3
@onready var anim_player: AnimationPlayer = $Sprite2D/AnimationPlayer
@onready var hit_shape: CollisionShape2D = $CollisionShape2D

var hits_taken := 0

func take_damage() -> void:
	hits_taken += 1
	anim_player.play("Hit")
	if hits_taken >= hits_to_destroy:
		_destroy()

func _destroy() -> void:
	anim_player.play("Destroy")
	hit_shape.set_deferred("disabled",true)

func _ready() -> void:
	anim_player.animation_finished.connect(Callable(self, "_on_animation_finished"))

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Destroy":
		queue_free()
