extends Node
## Solo per test: aspetto e animazioni delle unità.
## Uso: godot --path . res://tools/anim_test.tscn
var fails := 0


func _ready() -> void:
	await get_tree().process_frame
	# 1. ogni unità ha mesh e un'animazione per stato nell'Inspector
	for f in DirAccess.get_files_at("res://data/units"):
		if not f.ends_with(".tres"):
			continue
		var u: UnitStats = load("res://data/units/" + f)
		var ok := u.visual != null and u.visual.mesh != null
		var missing := []
		if ok:
			for st in UnitVisual.STATES:
				if u.visual.get(st) == null:
					missing.append(st)
		_check(ok and missing.is_empty(), "%s: mesh %s, animazioni mancanti %s" % [f, u.visual.mesh.resource_path if ok else "-", missing])
	# 2. in battaglia i soldati attraversano gli stati
	GameConfig.mode = "field"
	var main = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var b: BattleManager = main.battle
	b.add_ai(0)
	b.start_battle()
	var seen := {}
	while b.battle_time < 60.0:
		b._sim_step(0.03)
		b.anim_time += 0.03
		if int(b.battle_time * 10) % 10 == 0:
			for r in b.regiments:
				r.update_visuals()
				for i in r.count:
					var c := r._mm.get_instance_custom_data(i)
					seen[int(c.g + 0.5)] = int(seen.get(int(c.g + 0.5), 0)) + 1
	var names := []
	for k in seen:
		names.append("%s %d" % [UnitVisual.STATES[k], seen[k]])
	print("    stati osservati: ", ", ".join(names))
	for st in [UnitVisual.IDLE, UnitVisual.WALK, UnitVisual.RUN, UnitVisual.ATTACK, UnitVisual.SHOOT, UnitVisual.DEATH]:
		_check(seen.get(st, 0) > 0, "stato «%s» usato in battaglia" % UnitVisual.STATES[st])
	var mat := b.get_unit_material(b.regiments[0].stats)
	_check(mat.shader.resource_path.ends_with("unit.gdshader"), "materiale dei soldati con lo shader di animazione")
	_check(not (mat.get_shader_parameter("anim_p0") as Array).is_empty(), "parametri delle animazioni nel materiale")
	main.queue_free()
	await get_tree().process_frame
	# 3. modifica nell'Inspector -> materiale aggiornato (anteprima dal vivo)
	var prev = load("res://tools/anteprima_unita.tscn").instantiate()
	get_tree().root.add_child(prev)
	await get_tree().process_frame
	var u2: UnitStats = load("res://data/units/swordsmen.tres").duplicate(true)
	prev.unit = u2
	prev.state = UnitVisual.ATTACK
	var before: Vector4 = (prev._mat.get_shader_parameter("anim_p1") as Array)[UnitVisual.ATTACK]
	u2.visual.attack.bend_deg = 99.0
	var after: Vector4 = (prev._mat.get_shader_parameter("anim_p1") as Array)[UnitVisual.ATTACK]
	_check(is_equal_approx(after.y, 99.0) and not is_equal_approx(before.y, 99.0), "anteprima aggiornata subito dopo una modifica (%.0f -> %.0f)" % [before.y, after.y])
	prev.queue_free()
	await get_tree().process_frame
	print("ANIM TEST: %s" % ("OK" if fails == 0 else "%d FALLITI" % fails))
	get_tree().quit(fails)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
