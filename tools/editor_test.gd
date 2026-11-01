extends Node
## Solo per test: disegna una fortezza nell'editor col mouse, la salva, la ritrova nella
## preparazione e ci combatte un assedio IA contro IA. Screenshot in user://.
## Uso: godot --path . res://tools/editor_test.tscn
const SAVE := "user://fortezze/forte_di_prova.json"
var fails := 0
var ed: Node
var map: FortressMapView


func _ready() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	ed = load("res://fortress_editor.tscn").instantiate()
	get_tree().root.add_child.call_deferred(ed)
	await get_tree().create_timer(0.4).timeout
	map = ed._map
	await _shot("editor_classica")
	ed._new()
	_check(ed.data["walls"].is_empty(), "nuova pianta vuota")
	# 1. quattro muri trascinando col mouse (l'ultimo tracciato un po' storto: va raddrizzato)
	ed._select_tool(0)
	_drag(Vector2(-50, -40), Vector2(50, -40))
	_drag(Vector2(50, -40), Vector2(50, -100))
	_drag(Vector2(50, -100), Vector2(-50, -100))
	_drag(Vector2(-50, -100), Vector2(-49, -41))
	_check(ed.data["walls"].size() == 4, "4 muri tracciati (%d)" % ed.data["walls"].size())
	var last: Array = ed.data["walls"][3]
	_check(is_equal_approx(float(last[0]), float(last[2])), "muro raddrizzato in verticale")
	_check(ed.layout.problems().size() >= 1, "senza porte e punto la fortezza non è valida")
	# 2. porta a sud, postierla a nord, torri agli angoli, punto di vittoria
	ed._select_tool(1)
	_click(Vector2(0, -40))
	ed._select_tool(2)
	_click(Vector2(10, -100))
	ed._select_tool(3)
	for c in [Vector2(-50, -40), Vector2(50, -40), Vector2(50, -100), Vector2(-50, -100)]:
		_click(c + Vector2(1.5, -1.0))   # si aggancia all'angolo
	ed._select_tool(4)
	_click(Vector2(0, -72))
	_check(ed.data["gates"].size() == 2, "porta e postierla (%d)" % ed.data["gates"].size())
	_check(ed.data["towers"].size() == 4, "4 torri (%d)" % ed.data["towers"].size())
	var t0: Array = ed.data["towers"][0]
	_check(is_equal_approx(float(t0[0]), -50.0) and is_equal_approx(float(t0[1]), -40.0), "torre agganciata all'angolo")
	_check(ed.layout.problems().is_empty(), "fortezza valida: %s" % [ed.layout.problems()])
	# una porta sopra l'altra non si può mettere
	ed._select_tool(1)
	_click(Vector2(2, -40))
	_check(ed.data["gates"].size() == 2, "porta sovrapposta rifiutata")
	# 3. gomma e annulla
	ed._select_tool(5)
	_click(Vector2(50, -100))
	_check(ed.data["towers"].size() == 3, "gomma toglie una torre")
	ed._undo_last()
	_check(ed.data["towers"].size() == 4, "annulla la riporta")
	ed._select_tool(5)
	_click(Vector2(-50, -70))   # muro ovest
	_check(ed.data["walls"].size() == 3 and not ed.layout.problems().is_empty(), "togliendo un muro la fortezza si apre")
	ed._undo_last()
	ed._select_tool(1)
	_move(Vector2(0, -40))
	await _shot("editor_disegno")
	# 4. salvataggio
	ed._name_edit.text = "Forte di prova"
	ed._save()
	_check(FileAccess.file_exists(SAVE), "salvata in %s" % SAVE)
	var back := FortressLayout.load_file(SAVE)
	_check(back.get("name", "") == "Forte di prova" and (back["walls"] as Array).size() == 4, "il file contiene la fortezza")
	_check(GameConfig.fortress_path == SAVE, "diventa la fortezza scelta")
	ed.queue_free()
	await get_tree().process_frame
	# 5. preparazione: la fortezza è nell'elenco
	var sel = load("res://army_select.tscn").instantiate()
	get_tree().root.add_child(sel)
	await get_tree().process_frame
	sel._mode_btn.select(1)
	sel._mode_btn.item_selected.emit(1)
	var names := []
	for i in sel._fort_btn.item_count:
		names.append(sel._fort_btn.get_item_text(i))
	_check(names.has("Forte di prova  (tua)"), "nella preparazione: %s" % [names])
	_check(sel._fort_btn.get_item_text(sel._fort_btn.selected) == "Forte di prova  (tua)", "già selezionata")
	sel._add_buttons["catapult"].pressed.emit()
	await _shot("preparazione_fortezza")
	sel.queue_free()
	await get_tree().process_frame
	# 6. assedio su questa fortezza (nemico fisso: due reparti di arcieri da mettere sulle mura)
	GameConfig.enemy_army.assign(["general", "spearmen", "swordsmen", "swordsmen", "archers", "archers", "knights"])
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.ui.toggle_help()
	var b: BattleManager = main.battle
	_check(b.fortress != null and b.fortress.layout.name == "Forte di prova", "battaglia sulla fortezza salvata")
	_check(b.fortress.gates.size() == 2, "porte in battaglia: %d" % b.fortress.gates.size())
	var on_wall := 0
	var inside := 0
	for r in b.regiments:
		if r.team == b.fortress.defender_team:
			if r.on_wall:
				on_wall += 1
			elif b.fortress.inside(r.mid()):
				inside += 1
	_check(on_wall == 2 and inside >= 3, "difensori schierati: %d sulle mura, %d dentro" % [on_wall, inside])
	main.rig.focus_on(Vector3(0, 0, -45))
	main.rig._target_dist = 95.0
	main.rig.dist = 95.0
	main.rig.yaw = 0.3
	await _shot("assedio_forte_di_prova")
	b.add_ai(0)
	b.start_battle()
	while b.phase == BattleManager.Phase.BATTLE and b.battle_time < 600.0:
		b._sim_step(0.03)
	var gates_down := 0
	for g in b.fortress.gates:
		if g.destroyed:
			gates_down += 1
	_check(b.phase == BattleManager.Phase.ENDED, "l'assedio si conclude: %s (porte abbattute %d)" % [b.end_reason, gates_down])
	print("EDITOR TEST: %s" % ("OK" if fails == 0 else "%d FALLITI" % fails))
	get_tree().quit(fails)


func _screen(w: Vector2) -> Vector2:
	return map.get_global_rect().position + map.to_screen(w)


func _move(w: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = _screen(w)
	mv.global_position = mv.position
	Input.parse_input_event(mv)
	Input.flush_buffered_events()


func _button(w: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _screen(w)
	e.global_position = e.position
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _click(w: Vector2) -> void:
	_move(w)
	_button(w, true)
	_button(w, false)


func _drag(a: Vector2, b: Vector2) -> void:
	_move(a)
	_button(a, true)
	_move((a + b) * 0.5)
	_move(b)
	_button(b, false)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _shot(label: String) -> void:
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % label)
