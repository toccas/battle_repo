extends Node
## Solo per test: avvia la scena e salva screenshot dei feedback degli ordini.
## Uso: godot --path . res://tools/screenshot_test.tscn  (le immagini vanno nella cartella user://)
var main: Node


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(0.5).timeout
	main.ui.toggle_help()
	var b: BattleManager = main.battle
	var c: PlayerController = main.controller
	var cam: Camera3D = main.rig.cam
	b.start_battle()
	b.paused = true
	main.rig.focus_on(Vector3(0, 0, 35))
	main.rig._target_dist = 120.0
	main.rig.dist = 120.0
	main.rig.yaw = 0.0
	# 1. arcieri + lancieri selezionati, cursore sul terreno: frecce di movimento e gittata
	var sel: Array[Regiment] = [b.regiments[1], b.regiments[5]]
	c.set_selection(sel)
	await get_tree().process_frame
	_move(cam.unproject_position(Vector3(-25, 0, 35)))
	await _shot("feedback_move")
	# 2. cursore sul nemico: outline rossa e frecce d'attacco
	_move(cam.unproject_position(b.regiments[10].mid()))
	await _shot("feedback_attack")
	# 2b. da vicino, per vedere l'outline
	var enemy: Regiment = b.regiments[11]
	main.rig.focus_on(enemy.mid() + Vector3(0, 0, 22))
	main.rig._target_dist = 38.0
	main.rig.dist = 38.0
	main.rig._apply()
	await get_tree().process_frame
	_move(cam.unproject_position(enemy.mid()))
	await _shot("feedback_outline")
	main.rig.focus_on(Vector3(0, 0, 35))
	main.rig._target_dist = 120.0
	main.rig.dist = 120.0
	# 3. ordine dato e in esecuzione
	_click(cam.unproject_position(Vector3(-25, 0, 40)))
	b.paused = false
	for k in 30:
		b._sim_step(0.03)
	_move(Vector2(5, 5))
	await _shot("feedback_order")
	get_tree().quit()


func _move(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	Input.parse_input_event(mv)
	Input.flush_buffered_events()


func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = p
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _shot(label: String) -> void:
	for f in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % label)
	print("shot ", label, " -> ", ProjectSettings.globalize_path("user://%s.png" % label))
