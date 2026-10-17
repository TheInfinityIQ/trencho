extends SceneTree

# Run with: godot --headless --path . --script tools/redraw_battlefield.gd
# Edits the saved TileMapLayer, so the layout is also visible in the editor.
const MAP_PATH := "res://scenes/maps/map_test.tscn"
const SIZE := 52

func _initialize() -> void:
	var map = load(MAP_PATH).instantiate()
	var tiles: TileMapLayer = map.get_node("TileMapLayer")
	var grass_patches: Array[Vector2i] = []
	var roads: Array[Vector2i] = []
	var trenches: Array[Vector2i] = []
	
	
	tiles.clear()
	for y in range(SIZE):
		for x in range(SIZE):
			var cell := Vector2i(x, y)
			tiles.set_cell(cell, 0, Vector2i(1, 1))
			var from_end := mini(y, SIZE - 1 - y)
			var lane_centers := [10.0 + sin(from_end * 0.20) * 1.7, 25.5 + sin(from_end * 0.15) * 1.2, 41.0 - sin(from_end * 0.20) * 1.7]
			var lane_distance := 100.0
			for center in lane_centers:
				lane_distance = minf(lane_distance, absf(x - center))
			var road := lane_distance < 1.8 and y >= 5 and y <= 46
			# One cross-field road connects all three avenues at the center.
			road = road or (absf(y - (25.5 + sin(x * 0.16) * 1.5)) < 1.5 and x >= 7 and x <= 44)
			# Two continuous, stepped trench lines, with open lane crossings.
			var trench_y := 16 + (2 if (x >= 18 and x <= 33) else 0)
			var trench := from_end >= trench_y and from_end <= trench_y + 2 and x >= 3 and x <= 48 and lane_distance > 4.8
			# Irregular vegetation patches tie the edges together without repeated quadrants.
			var patch := pow((x - 3.0) / 5.0, 2) + pow((y - 11.0) / 8.0, 2) < 1.0
			patch = patch or pow((x - 48.0) / 5.0, 2) + pow((y - 39.0) / 9.0, 2) < 1.0
			patch = patch or pow((x - 4.0) / 5.0, 2) + pow((y - 35.0) / 6.0, 2) < 1.0
			patch = patch or pow((x - 47.0) / 5.0, 2) + pow((y - 14.0) / 6.0, 2) < 1.0
			patch = patch or pow((x - 18.0) / 3.5, 2) + pow((y - 7.0) / 3.0, 2) < 1.0
			patch = patch or pow((x - 33.0) / 3.5, 2) + pow((y - 44.0) / 3.0, 2) < 1.0
			if road:
				roads.append(cell)
			elif trench:
				trenches.append(cell)
			elif patch and lane_distance > 3.5 and absf(y - 25.5) > 5.0 and abs(from_end - trench_y) > 4:
				grass_patches.append(cell)
	tiles.set_cells_terrain_connect(grass_patches, 0, 2)
	tiles.set_cells_terrain_connect(roads, 0, 0)
	tiles.set_cells_terrain_connect(trenches, 0, 3)
	# Complete outer trench edges explicitly; the original terrain metadata lacks
	# several corner combinations and otherwise leaves square cut-offs.
	for cell in trenches:
		var column := 7 + (cell.x % 2)
		var row := 8 + (cell.y % 2)
		if not trenches.has(cell + Vector2i.LEFT):
			column = 6
		elif not trenches.has(cell + Vector2i.RIGHT):
			column = 9
		if not trenches.has(cell + Vector2i.UP):
			row = 7
		elif not trenches.has(cell + Vector2i.DOWN):
			row = 10
		tiles.set_cell(cell, 0, Vector2i(column, row))
	assert(tiles.get_used_rect() == Rect2i(0, 0, SIZE, SIZE))
	assert(tiles.get_used_cells().size() == SIZE * SIZE)
	var packed := PackedScene.new()
	assert(packed.pack(map) == OK)
	assert(ResourceSaver.save(packed, MAP_PATH) == OK)
	# The goal subscene already owns these signals; do not serialize them twice.
	var scene_text := FileAccess.get_file_as_string(MAP_PATH)
	var duplicate_connections := RegEx.new()
	duplicate_connections.compile('(?m)^\\[connection signal="body_entered" from="Goal2?" to="Goal2?" method="_on_body_entered"\\]\\r?\\n?')
	var scene_file := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	scene_file.store_string(duplicate_connections.sub(scene_text, "", true).strip_edges() + "\n")
	scene_file.close()
	# Render a compact tile-for-tile overview without launching a game window.
	var atlas := tiles.tile_set.get_source(0) as TileSetAtlasSource
	var texture := atlas.texture.get_image()
	var overview := Image.create(SIZE * 20, SIZE * 20, false, Image.FORMAT_RGBA8)
	for cell in tiles.get_used_cells():
		var tile := texture.get_region(Rect2i(tiles.get_cell_atlas_coords(cell) * 128, Vector2i(128, 128)))
		tile.resize(20, 20, Image.INTERPOLATE_LANCZOS)
		overview.blit_rect(tile, Rect2i(0, 0, 20, 20), cell * 20)
	overview.save_png("res://.godot/battlefield-preview.png")
	print("Redrawn 52x52 battlefield: three avenues, central connection, two trench lines, irregular grass patches.")
	map.free()
	quit()
