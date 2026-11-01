extends Node
## Solo per test: simula mouse e tastiera e controlla che gli ordini arrivino ai reggimenti.
## Uso: godot --headless --path . res://tools/input_test.tscn
var main: Node
var fails := 0


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(0.3).timeout
	var b: BattleManager = main.battle
	var c: PlayerController = main.controller
	var cam: Camera3D = main.rig.cam
	main.rig.focus_on(Vector3(0, 0, 70))
	main.rig._target_dist = 90.0
	main.rig.dist = 90.0
	main.rig._apply()
	await get_tree().process_frame
	var spear: Regiment = b.regiments[1]
	# 1. click sinistro sul reggimento
	var sp := cam.unproject_position(spear.mid())
	_click(MOUSE_BUTTON_LEFT, sp, sp)
	_check(c.selected.size() == 1 and c.selected[0] == spear, "click seleziona il reggimento")
	# 2. selezione a rettangolo di tutta la prima linea
	_click(MOUSE_BUTTON_LEFT, Vector2(5, 5), get_viewport().get_visible_rect().size - Vector2(5, 5))
	_check(c.selected.size() >= 5, "rettangolo seleziona più reggimenti (%d)" % c.selected.size())
	# 3. schieramento: trascinamento destro = teletrasporto in linea
	var a := cam.unproject_position(Vector3(-60, 0, 90))
	var z := cam.unproject_position(Vector3(60, 0, 90))
	var sel: Array[Regiment] = [b.regiments[1], b.regiments[2]]
	c.set_selection(sel)
	_click(MOUSE_BUTTON_RIGHT, a, z)
	_check(absf(b.regiments[1].center.z - 90.0) < 3.0 and absf(b.regiments[2].center.z - 90.0) < 3.0,
		"schieramento in linea (z=%.1f, %.1f)" % [b.regiments[1].center.z, b.regiments[2].center.z])
	_check(b.regiments[1].center.x < b.regiments[2].center.x, "ordine sinistra-destra rispettato")
	# 4. INVIO avvia la battaglia
	_key(KEY_ENTER)
	_check(b.phase == BattleManager.Phase.BATTLE, "INVIO avvia la battaglia")
	# 5. click destro sul terreno = movimento
	var dest := cam.unproject_position(Vector3(0, 0, 60))
	_click(MOUSE_BUTTON_RIGHT, dest, dest)
	_check(b.regiments[1].state == Regiment.State.MOVING, "click destro = ordine di movimento")
	# 6. click destro sul nemico = attacco
	var enemy: Regiment = b.regiments[10]
	main.rig.focus_on(enemy.mid())
	main.rig._apply()
	await get_tree().process_frame
	var ep := cam.unproject_position(enemy.mid())
	_click(MOUSE_BUTTON_RIGHT, ep, ep)
	_check(b.regiments[1].state == Regiment.State.ATTACKING and b.regiments[1].attack_target == enemy,
		"click destro sul nemico = attacco")
	# 6b. feedback: passando sopra il nemico -> outline, cursore a spada, freccia rossa
	_move(ep)
	await get_tree().process_frame
	_check(c.hover_enemy == enemy, "hover sul nemico lo riconosce")
	_check(enemy._outline.visible, "il nemico ha l'outline")
	_check(Input.get_current_cursor_shape() == Input.CURSOR_CROSS, "cursore a forma di spada")
	_check(c.feedback._im.get_surface_count() > 0, "frecce disegnate")
	# lontano dal nemico: outline spento, cursore normale
	var ground := cam.unproject_position(enemy.mid() + Vector3(0, 0, 45))
	_move(ground)
	await get_tree().process_frame
	_check(not enemy._outline.visible and c.hover_enemy == null, "outline spento lasciando il nemico")
	_check(Input.get_current_cursor_shape() == Input.CURSOR_ARROW, "cursore normale sul terreno")
	# arcieri selezionati: cerchio di gittata (molti più vertici di una sola freccia)
	var only_inf: Array[Regiment] = [b.regiments[1]]
	c.set_selection(only_inf)
	await get_tree().process_frame
	var n_inf: int = (c.feedback._im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var archers: Array[Regiment] = [b.regiments[5]]
	c.set_selection(archers)
	await get_tree().process_frame
	var n_arc: int = (c.feedback._im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check(b.regiments[5].stats.is_ranged and n_arc > n_inf + 300, "cerchio di gittata per gli arcieri (%d vs %d vertici)" % [n_arc, n_inf])
	c.set_selection(sel)
	# 7. gruppi e pausa
	_key(KEY_2, true)
	_key(KEY_ESCAPE)
	_check(c.selected.is_empty(), "Esc deseleziona")
	_key(KEY_2)
	_check(c.selected.size() == 2, "Ctrl+2 / 2 richiama il gruppo")
	_key(KEY_SPACE)
	_check(b.paused, "spazio mette in pausa")
	_key(KEY_SPACE)
	_key(KEY_BACKSPACE)
	_check(b.regiments[1].state == Regiment.State.IDLE, "Backspace ferma l'unità")
	# 8. qualche secondo di battaglia reale con l'interfaccia attiva
	b.time_scale = 3.0
	await get_tree().create_timer(3.0).timeout
	_check(b.battle_time > 1.0, "la simulazione avanza (%.1f s)" % b.battle_time)
	print("INPUT TEST: %s" % ("OK" if fails == 0 else "%d FALLITI" % fails))
	get_tree().quit(fails)


func _click(button: MouseButton, from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = from
	Input.parse_input_event(down)
	if from != to:
		var mv := InputEventMouseMotion.new()
		mv.position = to
		Input.parse_input_event(mv)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = to
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _move(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	Input.parse_input_event(mv)
	Input.flush_buffered_events()


func _key(k: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
