extends Node
## Solo per test: percorre preparazione -> assedio e salva screenshot in user://.
## Uso: godot --path . res://tools/flow_test.tscn
var fails := 0


func _ready() -> void:
	var sel = load("res://army_select.tscn").instantiate()
	get_tree().root.add_child.call_deferred(sel)
	await get_tree().create_timer(0.4).timeout
	await _shot("select_field")
	# assedio, il giocatore attacca
	sel._mode_btn.select(1)
	sel._mode_btn.item_selected.emit(1)
	var before := GameConfig.player_army.size()
	sel._add_buttons["troll"].pressed.emit()
	_check(GameConfig.mode == "siege" and GameConfig.player_attacks, "modalità assedio-attacco scelta")
	_check(GameConfig.player_army.size() == before + 1 and GameConfig.player_army.has("troll"), "troll aggiunto all'esercito")
	_check(GameConfig.army_cost(GameConfig.player_army) <= GameConfig.budget_for(true), "costo entro il budget (%d/%d)" % [GameConfig.army_cost(GameConfig.player_army), GameConfig.budget_for(true)])
	_check(GameConfig.army_cost(GameConfig.enemy_army) <= GameConfig.budget_for(false), "nemico entro il budget")
	await _shot("select_siege")
	sel.queue_free()
	# battaglia d'assedio
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.ui.toggle_help()
	var b: BattleManager = main.battle
	_check(b.fortress != null and b.fortress.defender_team == 1, "fortezza creata, difende il nemico")
	main.rig.focus_on(Vector3(0, 0, -20))
	main.rig._target_dist = 150.0
	main.rig.dist = 150.0
	await _shot("siege_deploy")
	b.add_ai(0)
	b.start_battle()
	# hover sulla porta principale con un reparto selezionato, prima che arrivi qualcuno
	var sel0: Array[Regiment] = [b.regiments[1]]
	main.controller.set_selection(sel0)
	var g0: Fortress.Gate = b.fortress.gates[0]
	var mv0 := InputEventMouseMotion.new()
	mv0.position = main.rig.cam.unproject_position(g0.center + Vector3(0, 0, 1.5))
	Input.parse_input_event(mv0)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main.controller.hover_gate == g0, "hover sulla porta")
	_check(Input.get_current_cursor_shape() == Input.CURSOR_CROSS, "cursore a spada sulla porta")
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.position = mv0.position
	rc.pressed = true
	Input.parse_input_event(rc)
	var rc2 := rc.duplicate()
	rc2.pressed = false
	Input.parse_input_event(rc2)
	Input.flush_buffered_events()
	_check(b.regiments[1].state == Regiment.State.BREACHING and b.regiments[1].attack_gate == g0, "click destro sulla porta = assalto")
	while b.battle_time < 40.0:
		b._sim_step(0.03)
	main.rig.focus_on(Vector3(0, 0, -10))
	main.rig._target_dist = 70.0
	main.rig.dist = 70.0
	main.rig.yaw = 0.35
	var mine: Array[Regiment] = []
	for r in b.regiments:
		if r.team == 0 and r.stats.role == "infantry" and r.state != Regiment.State.BREACHING:
			mine.append(r)
			break
	main.controller.set_selection(mine)
	main.rig._apply()
	await get_tree().process_frame
	var g: Fortress.Gate = b.fortress.gates[0]
	var mv := InputEventMouseMotion.new()
	mv.position = main.rig.cam.unproject_position(g.center + Vector3(0, 0, 1.5))
	Input.parse_input_event(mv)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await _shot("siege_battle")
	while b.phase == BattleManager.Phase.BATTLE and b.battle_time < 400.0:
		b._sim_step(0.03)
	main.rig.focus_on(Vector3(0, 0, -60))
	main.rig._target_dist = 110.0
	main.rig.dist = 110.0
	await _shot("siege_end")
	print("FLOW TEST: %s (fine: %s)" % ["OK" if fails == 0 else "%d FALLITI" % fails, b.end_reason])
	get_tree().quit(fails)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _shot(label: String) -> void:
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % label)
