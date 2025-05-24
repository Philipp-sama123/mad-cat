extends Node2D

@export var tile_scene: PackedScene
@export var tile_size: Vector2 = Vector2(42.66, 56) # based on 128x168 / 3x3
@export var width: int = 100
@export var height: int = 10
@export var max_step: int = 2
@export var max_platform_height: int = 4
@export var flat_start_columns: int = 10
@export var delay: float = 5.0

var tiles: Array = []
var timer := 0.0
var last_y := height / 2
var current_step := 0

func _ready():
	generate_initial_map()

func _process(delta):
	timer += delta
	if timer >= delay:
		timer = 0.0
		extend_map()

func generate_initial_map():
	for x in width:
		generate_column(x)

func generate_column(x_index: int):
	var tile_x = x_index * tile_size.x
	var column: Array[Area2D] = []

	# First 10 columns flat
	if x_index < flat_start_columns:
		pass
	elif current_step < max_platform_height:
		current_step += 1
	elif randf() < 0.3:
		current_step = clamp(current_step + randi_range(-max_step, max_step), 1, max_platform_height)

	last_y = clamp(height - current_step, 1, height - 2)

	for y_index in range(height):
		if y_index < last_y:
			continue  # leave air
		var tile = tile_scene.instantiate()
		add_child(tile)

		var tile_y = y_index * tile_size.y
		tile.position = Vector2(tile_x, tile_y)

		var sprite: Sprite2D = tile.get_node("Sprite2D")

		var type = "center"
		if y_index == last_y:
			type = "top"
		elif y_index > last_y:
			type = "bottom"
		else:
			type = "center"

		var col_type = "center"
		if x_index == 0:
			col_type = "edge_left"
		elif x_index == width - 1:
			col_type = "edge_right"

		sprite.frame_coords = get_frame_coords(col_type + "_" + type)

		column.append(tile)

	tiles.append(column)

func extend_map():
	if tiles.size() > 0:
		var old_column = tiles.pop_front()
		for tile in old_column:
			if tile != null:
				tile.queue_free()

	generate_column(width)
	width += 1

func get_frame_coords(name: String) -> Vector2i:
	var frame_dict = {
		"edge_left_top": Vector2i(0, 0),
		"edge_left_center": Vector2i(0, 1),
		"edge_left_bottom": Vector2i(0, 2),
		"center_top": Vector2i(1, 0),
		"center_center": Vector2i(1, 1),
		"center_bottom": Vector2i(1, 2),
		"edge_right_top": Vector2i(2, 0),
		"edge_right_center": Vector2i(2, 1),
		"edge_right_bottom": Vector2i(2, 2)
	}
	return frame_dict.get(name, Vector2i(1, 1))
