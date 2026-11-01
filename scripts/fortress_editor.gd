extends Control
## Strumento di sviluppo: editor delle fortezze per gli assedi.
## Si disegnano mura, porte, postierle, torri e il punto di vittoria su una pianta vista
## dall'alto; si salva in user://fortezze/ e la fortezza compare nella preparazione.
##
## Comandi: 1-6 o i pulsanti per lo strumento · click sinistro per usarlo · trascina per
## tracciare un muro · click destro annulla il muro in corso · Ctrl+Z annulla l'ultima modifica.

enum Tool { WALL, GATE, POSTERN, TOWER, CAPTURE, ERASE }

const TOOL_NAMES := ["Muro", "Porta", "Postierla", "Torre", "Punto di vittoria", "Gomma"]
const TOOL_HELP := [
	"Trascina per tracciare un muro (orizzontale o verticale). Le estremità si agganciano a quelle vicine.",
	"Click su un muro per aprire una porta abbattibile. La larghezza decide la resistenza.",
	"Click su un muro per una postierla: solo i difensori la usano, non si può abbattere.",
	"Click per mettere una torre: tira frecce da sola sugli attaccanti entro 110 m.",
	"Click per spostare il punto di vittoria: deve stare dentro le mura.",
	"Click su un elemento per toglierlo. Togliendo un muro si tolgono anche le sue porte.",
]
const SNAP := 2.0
const ENDPOINT_SNAP := 5.0
const GATE_WIDTHS := [6, 8, 10, 12]
const TOWER_SIZES := [6, 8, 10]
const PANEL_BG := Color(0.1, 0.12, 0.16)
const ACCENT := Color(0.95, 0.78, 0.35)

var data := {}
var layout: FortressLayout
var tool := Tool.WALL
var current_path := ""        ## file da cui viene la fortezza (vuoto se nuova)
var dirty := false

var _map: FortressMapView
var _name_edit: LineEdit
var _tool_buttons: Array[Button] = []
var _help: Label
var _gate_width: OptionButton
var _tower_size: OptionButton
var _stats: Label
var _problems: Label
var _message: Label
var _load_list: OptionButton
var _delete_btn: Button
var _files: Array[Dictionary] = []
var _undo: Array[String] = []
var _dragging := false
var _drag_a := Vector2.ZERO
var _mouse_world := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if not GameConfig.fortress_override.is_empty():
		# di ritorno da una prova: si riprende da dove si era rimasti
		_set_data(GameConfig.fortress_override.duplicate(true), GameConfig.editor_path)
		dirty = GameConfig.editor_dirty
	else:
		_set_data(FortressLayout.classic_data(), "res://data/fortezze/classica.json")
	GameConfig.fortress_override = {}
	_select_tool(Tool.WALL)


# ---------------------------------------------------------------- interfaccia

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	_map = FortressMapView.new()
	_map.editing = true
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.gui_input.connect(_on_map_input)
	_map.mouse_exited.connect(func() -> void: _clear_previews())
	row.add_child(_map)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL_BG
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", st)
	row.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	var title := _label("EDITOR FORTEZZE", 22)
	title.add_theme_color_override("font_color", ACCENT)
	v.add_child(title)
	v.add_child(_label("Strumento di sviluppo", 12, Color(0.6, 0.62, 0.68)))

	v.add_child(_label("Nome", 14))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nome della fortezza"
	_name_edit.text_changed.connect(func(t: String) -> void:
		data["name"] = t
		dirty = true)
	v.add_child(_name_edit)

	v.add_child(_label("Strumenti", 14))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = "%d · %s" % [i + 1, TOOL_NAMES[i]]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_tool.bind(i))
		grid.add_child(b)
		_tool_buttons.append(b)
	_help = _label("", 12, Color(0.78, 0.8, 0.86))
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(300, 48)
	v.add_child(_help)

	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_theme_constant_override("h_separation", 10)
	v.add_child(opts)
	opts.add_child(_label("Larghezza porta", 13))
	_gate_width = OptionButton.new()
	for w in GATE_WIDTHS:
		_gate_width.add_item("%d m · resistenza %d" % [w, int(w * FortressLayout.GATE_HP_PER_M)])
	_gate_width.select(2)
	opts.add_child(_gate_width)
	opts.add_child(_label("Lato torre", 13))
	_tower_size = OptionButton.new()
	for t in TOWER_SIZES:
		_tower_size.add_item("%d m" % t)
	_tower_size.select(1)
	opts.add_child(_tower_size)

	v.add_child(HSeparator.new())
	_stats = _label("", 13)
	v.add_child(_stats)
	_problems = _label("", 13)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.custom_minimum_size = Vector2(300, 0)
	v.add_child(_problems)

	v.add_child(HSeparator.new())
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 6)
	v.add_child(file_row)
	var save := _button("Salva", _save)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(save)
	var new_btn := _button("Nuova", _new)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(new_btn)
	var undo := _button("Annulla", _undo_last)
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(undo)
	v.add_child(_label("Fortezze salvate", 14))
	_load_list = OptionButton.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_load_list)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 6)
	v.add_child(load_row)
	var load_btn := _button("Carica", _load_selected)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(load_btn)
	_delete_btn = _button("Elimina", _delete_selected)
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_delete_btn)
	_load_list.item_selected.connect(func(_i: int) -> void: _update_delete())

	v.add_child(HSeparator.new())
	v.add_child(_label("Prova in battaglia (con gli eserciti della preparazione)", 13))
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 6)
	v.add_child(test_row)
	var td := _button("Difendi", _test.bind(false))
	td.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(td)
	var ta := _button("Attacca", _test.bind(true))
	ta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(ta)
	v.add_child(_button("Torna alla preparazione", _back))
	_message = _label("", 13, ACCENT)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(300, 0)
	v.add_child(_message)
	_refresh_files()


func _label(t: String, sz: int, col := Color(0.92, 0.93, 0.96)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _select_tool(t: int) -> void:
	tool = t
	_tool_buttons[t].button_pressed = true
	_help.text = TOOL_HELP[t]
	_dragging = false
	_clear_previews()


# ---------------------------------------------------------------- dati

func _set_data(d: Dictionary, path: String) -> void:
	data = d
	for k in ["walls", "gates", "towers"]:
		if not data.has(k):
			data[k] = []
	current_path = path
	_name_edit.text = str(data.get("name", ""))
	_rebuild()
	dirty = false


func _rebuild() -> void:
	layout = FortressLayout.from_data(data)
	_map.set_layout(layout)
	var breakable := 0
	for g in layout.gates:
		if g["breakable"]:
			breakable += 1
	_stats.text = "Mura: %d · porte: %d · postierle: %d · torri: %d\nInterno: %d m²" % [
		layout.sides.size(), breakable, layout.gates.size() - breakable, layout.towers.size(),
		int(layout.interior_area())]
	var probs := layout.problems()
	if probs.is_empty():
		_problems.text = "✔ Pronta per la battaglia"
		_problems.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	else:
		_problems.text = "Da sistemare:\n• " + "\n• ".join(probs)
		_problems.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))


func _push_undo() -> void:
	_undo.append(JSON.stringify(data))
	if _undo.size() > 100:
		_undo.pop_front()
	dirty = true


func _undo_last() -> void:
	if _undo.is_empty():
		_say("Niente da annullare.")
		return
	var d: Variant = JSON.parse_string(_undo.pop_back())
	if d is Dictionary:
		data = d
		_name_edit.text = str(data.get("name", ""))
		_rebuild()


func _say(t: String) -> void:
	_message.text = t


# ---------------------------------------------------------------- mappa

func _snap(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, SNAP), snappedf(p.y, SNAP))


func _endpoints() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for w: Array in data["walls"]:
		out.append(Vector2(float(w[0]), float(w[1])))
		out.append(Vector2(float(w[2]), float(w[3])))
	return out


func _snap_endpoint(p: Vector2) -> Vector2:
	var best := _snap(p)
	var bd := ENDPOINT_SNAP
	for e in _endpoints():
		var d := e.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


func _clamp_build(p: Vector2) -> Vector2:
	var a := FortressLayout.BUILD_AREA
	return Vector2(clampf(p.x, a.position.x, a.end.x), clampf(p.y, a.position.y, a.end.y))


## Il muro tracciato da a verso b: solo orizzontale o verticale (vince l'asse più lungo).
func _wall_end(a: Vector2, b: Vector2) -> Vector2:
	var e := _clamp_build(_snap_endpoint(b))
	if absf(e.x - a.x) >= absf(e.y - a.y):
		return Vector2(e.x, a.y)
	return Vector2(a.x, e.y)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_world = _map.to_world((event as InputEventMouseMotion).position)
		_update_previews()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse_world = _map.to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_dragging = false
			_update_previews()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if tool == Tool.WALL:
				_dragging = true
				_drag_a = _clamp_build(_snap_endpoint(_mouse_world))
			else:
				_apply_tool(_mouse_world)
		elif _dragging:
			_dragging = false
			_finish_wall(_mouse_world)
		_update_previews()


func _finish_wall(mouse: Vector2) -> void:
	var b := _wall_end(_drag_a, mouse)
	var length := _drag_a.distance_to(b)
	if length < 6.0:
		_say("Muro troppo corto: almeno 6 m.")
		return
	_push_undo()
	var a := _drag_a
	if b.x < a.x or b.y < a.y:
		var tmp := a
		a = b
		b = tmp
	(data["walls"] as Array).append([a.x, a.y, b.x, b.y])
	_rebuild()
	_say("Muro di %d m aggiunto." % int(round(length)))


## Dove andrebbe una porta larga `width` vicino al punto: {"wall", "t", "ok", "rect", "why"}.
func _gate_spot(p: Vector2, width: float) -> Dictionary:
	var best := -1
	var bd := 5.0
	var bt := 0.0
	for i in layout.sides.size():
		var sd: Dictionary = layout.sides[i]
		var a: Vector3 = sd["a"]
		var dir: Vector3 = sd["dir"]
		var t := (Vector3(p.x, 0, p.y) - a).dot(dir)
		if t < 0.0 or t > float(sd["len"]):
			continue
		var q := a + dir * t
		var d := Vector2(q.x, q.z).distance_to(p)
		if d < bd:
			bd = d
			best = i
			bt = t
	if best < 0:
		return {"ok": false, "why": "Avvicinati a un muro."}
	var sd2: Dictionary = layout.sides[best]
	var length := float(sd2["len"])
	if length < width + 6.0:
		return {"ok": false, "why": "Muro troppo corto per una porta di %d m." % int(width)}
	var t := clampf(snappedf(bt, 1.0), width * 0.5 + 3.0, length - width * 0.5 - 3.0)
	var a2: Vector3 = sd2["a"]
	var dir2: Vector3 = sd2["dir"]
	var c := a2 + dir2 * t
	var rect := FortressLayout._seg_rect(c - dir2 * width * 0.5, c + dir2 * width * 0.5, 0.0)
	for g in layout.gates:
		if int(g["wall"]) == best and absf(float(g["t"]) - t) < (float(g["width"]) + width) * 0.5 + 2.0:
			return {"ok": false, "why": "C'è già una porta lì.", "rect": rect}
	for tw in layout.towers:
		if (tw["rect"] as Rect2).intersects(rect.grow(-0.5)):
			return {"ok": false, "why": "Una torre copre quel punto.", "rect": rect}
	return {"ok": true, "wall": best, "t": t, "rect": rect, "normal": sd2["n"]}


func _gate_name(normal: Vector3, postern: bool) -> String:
	var dir := "sud"
	if absf(normal.x) > absf(normal.z):
		dir = "est" if normal.x > 0 else "ovest"
	elif normal.z < 0:
		dir = "nord"
	var base := ("Postierla %s" if postern else "Porta %s") % dir
	var n := base
	var k := 2
	var names := []
	for g: Dictionary in data["gates"]:
		names.append(str(g.get("name", "")))
	while names.has(n):
		n = "%s %d" % [base, k]
		k += 1
	return n


func _apply_tool(p: Vector2) -> void:
	match tool:
		Tool.GATE, Tool.POSTERN:
			var postern := tool == Tool.POSTERN
			var width := 6.0 if postern else float(GATE_WIDTHS[_gate_width.selected])
			var spot := _gate_spot(p, width)
			if not spot["ok"]:
				_say(spot["why"])
				return
			_push_undo()
			(data["gates"] as Array).append({"wall": spot["wall"], "t": spot["t"], "width": width,
					"type": "postierla" if postern else "porta", "name": _gate_name(spot["normal"], postern)})
			_rebuild()
			_say("%s aggiunta." % ("Postierla" if postern else "Porta"))
		Tool.TOWER:
			var size := float(TOWER_SIZES[_tower_size.selected])
			var c := _clamp_build(_snap_endpoint(p))
			_push_undo()
			(data["towers"] as Array).append([c.x, c.y, size])
			_rebuild()
			_say("Torre aggiunta.")
		Tool.CAPTURE:
			var c := _clamp_build(_snap(p))
			_push_undo()
			data["capture"] = [c.x, c.y]
			_rebuild()
			_say("Punto di vittoria spostato.")
		Tool.ERASE:
			var hit := _erase_target(p)
			if hit.is_empty():
				_say("Niente da togliere qui.")
				return
			_push_undo()
			match hit["kind"]:
				"gate":
					(data["gates"] as Array).remove_at(hit["index"])
				"tower":
					(data["towers"] as Array).remove_at(hit["index"])
				"capture":
					data.erase("capture")
				"wall":
					var wi: int = hit["index"]
					(data["walls"] as Array).remove_at(wi)
					var kept := []
					for g: Dictionary in data["gates"]:
						var gw := int(g["wall"])
						if gw == wi:
							continue
						if gw > wi:
							g["wall"] = gw - 1
						kept.append(g)
					data["gates"] = kept
			_rebuild()
			_say("Tolto.")


## L'elemento sotto il cursore, nell'ordine porte, torri, punto, muri.
func _erase_target(p: Vector2) -> Dictionary:
	for i in layout.gates.size():
		if (layout.gates[i]["rect"] as Rect2).grow(1.5).has_point(p):
			return {"kind": "gate", "index": _data_gate_index(i), "shape": layout.gates[i]["rect"]}
	for i in layout.towers.size():
		if (layout.towers[i]["rect"] as Rect2).grow(1.0).has_point(p):
			return {"kind": "tower", "index": i, "shape": layout.towers[i]["rect"]}
	if layout.has_capture and Vector2(layout.capture.x, layout.capture.z).distance_to(p) < 14.0:
		return {"kind": "capture", "center": Vector2(layout.capture.x, layout.capture.z)}
	for i in layout.sides.size():
		var sd: Dictionary = layout.sides[i]
		var r := FortressLayout._seg_rect(sd["a"], sd["b"], FortressLayout.WALL_T * 0.5)
		if r.grow(1.5).has_point(p):
			return {"kind": "wall", "index": _data_wall_index(i), "shape": r}
	return {}


## Gli indici del layout saltano i muri e le porte non validi: si ritrova l'elemento nei dati.
func _data_wall_index(side_index: int) -> int:
	var sd: Dictionary = layout.sides[side_index]
	var walls: Array = data["walls"]
	for i in walls.size():
		var w: Array = walls[i]
		if Vector3(float(w[0]), 0, float(w[1])).is_equal_approx(sd["a"]) and Vector3(float(w[2]), 0, float(w[3])).is_equal_approx(sd["b"]):
			return i
	return side_index


func _data_gate_index(layout_index: int) -> int:
	var g: Dictionary = layout.gates[layout_index]
	var gates: Array = data["gates"]
	for i in gates.size():
		var d: Dictionary = gates[i]
		if str(d.get("name", "")) == g["name"] and int(d.get("wall", -1)) == int(g["wall"]):
			return i
	return layout_index


func _clear_previews() -> void:
	_map.preview_line = []
	_map.preview_rect = []
	_map.preview_point = []
	_map.highlight = []
	_map.queue_redraw()


func _update_previews() -> void:
	_map.preview_line = []
	_map.preview_rect = []
	_map.preview_point = []
	_map.highlight = []
	var p := _mouse_world
	match tool:
		Tool.WALL:
			if _dragging:
				var b := _wall_end(_drag_a, p)
				_map.preview_line = [_drag_a, b, _drag_a.distance_to(b) >= 6.0]
			else:
				var s := _clamp_build(_snap_endpoint(p))
				_map.preview_point = [s, 1.5, true]
		Tool.GATE, Tool.POSTERN:
			var width := 6.0 if tool == Tool.POSTERN else float(GATE_WIDTHS[_gate_width.selected])
			var spot := _gate_spot(p, width)
			if spot.has("rect"):
				_map.preview_rect = [spot["rect"], spot["ok"]]
		Tool.TOWER:
			var size := float(TOWER_SIZES[_tower_size.selected])
			var c := _clamp_build(_snap_endpoint(p))
			_map.preview_rect = [Rect2(c.x - size * 0.5, c.y - size * 0.5, size, size), true]
		Tool.CAPTURE:
			var c := _clamp_build(_snap(p))
			_map.preview_point = [c, 14.0, layout.cell_value(Vector3(c.x, 0, c.y)) == 1]
		Tool.ERASE:
			var hit := _erase_target(p)
			if hit.has("shape"):
				_map.highlight = [hit["shape"]]
			elif hit.has("center"):
				_map.highlight = [hit["center"], 14.0]
	_map.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _name_edit.has_focus():
		return
	if k.keycode == KEY_Z and (k.ctrl_pressed or k.meta_pressed):
		_undo_last()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_6:
		_select_tool(k.keycode - KEY_1)
	elif k.keycode == KEY_ESCAPE:
		_dragging = false
		_update_previews()


# ---------------------------------------------------------------- file e prova

func _refresh_files(select_path := "") -> void:
	_files = FortressLayout.list_all()
	_load_list.clear()
	var sel := 0
	for i in _files.size():
		var f: Dictionary = _files[i]
		_load_list.add_item(("%s  (del gioco)" if f["builtin"] else "%s") % f["name"])
		if f["path"] == select_path:
			sel = i
	if not _files.is_empty():
		_load_list.select(sel)
	_update_delete()


func _update_delete() -> void:
	var i := _load_list.selected
	_delete_btn.disabled = i < 0 or i >= _files.size() or _files[i]["builtin"]


func _save() -> void:
	data["name"] = _name_edit.text.strip_edges()
	if data["name"] == "":
		_say("Dai un nome alla fortezza prima di salvarla.")
		_name_edit.grab_focus()
		return
	_rebuild()
	var probs := layout.problems()
	if not probs.is_empty():
		_say("Non salvata: prima sistema i problemi elencati sopra.")
		return
	var path := FortressLayout.save_user(data)
	if path == "":
		_say("Errore: impossibile scrivere il file.")
		return
	current_path = path
	dirty = false
	GameConfig.fortress_path = path
	_refresh_files(path)
	_say("Salvata: «%s». La trovi nella preparazione, in modalità assedio.\n%s" % [data["name"], ProjectSettings.globalize_path(path)])


func _new() -> void:
	_push_undo()
	_set_data({"name": "Nuova fortezza", "walls": [], "gates": [], "towers": []}, "")
	dirty = true
	_say("Pianta vuota: traccia le mura, poi porte e punto di vittoria.")


func _load_selected() -> void:
	var i := _load_list.selected
	if i < 0 or i >= _files.size():
		return
	var d := FortressLayout.load_file(_files[i]["path"])
	if d.is_empty():
		_say("File non leggibile.")
		return
	_push_undo()
	_set_data(d, _files[i]["path"])
	_say("Caricata «%s»." % d.get("name", ""))


func _delete_selected() -> void:
	var i := _load_list.selected
	if i < 0 or i >= _files.size() or _files[i]["builtin"]:
		return
	var f: Dictionary = _files[i]
	FortressLayout.delete_user(f["path"])
	if GameConfig.fortress_path == f["path"]:
		GameConfig.fortress_path = GameConfig.DEFAULT_FORTRESS
	_refresh_files()
	_say("Eliminata «%s»." % f["name"])


func _test(attack: bool) -> void:
	data["name"] = _name_edit.text.strip_edges()
	_rebuild()
	var probs := layout.problems()
	if not probs.is_empty():
		_say("Prima sistema i problemi elencati sopra.")
		return
	GameConfig.mode = "siege"
	GameConfig.player_attacks = attack
	GameConfig.fortress_override = data.duplicate(true)
	GameConfig.editor_path = current_path
	GameConfig.editor_dirty = dirty
	GameConfig.return_to_editor = true
	if GameConfig.army_cost(GameConfig.enemy_army) > GameConfig.budget_for(false):
		GameConfig.enemy_army = GameConfig.random_army(GameConfig.budget_for(false))
	get_tree().change_scene_to_file("res://main.tscn")


func _back() -> void:
	GameConfig.return_to_editor = false
	get_tree().change_scene_to_file("res://army_select.tscn")
