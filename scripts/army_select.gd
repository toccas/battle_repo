extends Control
## Scena di preparazione: tipo di battaglia, budget, composizione dell'esercito.
## Le scelte finiscono in GameConfig e la battaglia (main.tscn) le legge.

const BG := Color(0.07, 0.08, 0.11)
const PANEL := Color(0.12, 0.14, 0.19)
const ACCENT := Color(0.95, 0.78, 0.35)
const BLUE := Color(0.45, 0.62, 1.0)
const RED := Color(1.0, 0.45, 0.38)
const MODES := [
	["Battaglia campale", "field", true,
		"Due eserciti si affrontano in campo aperto. Vince chi mette in rotta l'altro."],
	["Assedio — attacchi tu", "siege", true,
		"Abbatti una porta della fortezza e tieni il punto di vittoria al centro per 45 secondi. Hai il 30% di punti in più. I difensori vincono se resistono 20 minuti."],
	["Assedio — difendi tu", "siege", false,
		"Il nemico ha il 30% di punti in più e cercherà di sfondare le porte. Tieni il punto di vittoria finché scade il tempo (20 minuti) o finché l'assalitore va in rotta."],
]
const BUDGETS := [3000, 5000, 7000, 9000, 999999]
const ROLE_NAMES := {"infantry": "Fanteria", "ranged": "Tiratori", "cavalry": "Cavalleria",
		"monster": "Mostro", "general": "Generale", "artillery": "Artiglieria"}

var _mode_btn: OptionButton
var _budget_btn: OptionButton
var _mode_desc: Label
var _player_list: VBoxContainer
var _enemy_list: VBoxContainer
var _player_points: Label
var _enemy_points: Label
var _start_btn: Button
var _warning: Label
var _add_buttons := {}
var _fort_label: Label
var _fort_btn: OptionButton
var _fort_preview: FortressMapView
var _forts: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "PREPARA LA BATTAGLIA"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	# --- tipo di battaglia e budget
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 12)
	root.add_child(opts)
	opts.add_child(_label("Tipo di battaglia", 15))
	_mode_btn = OptionButton.new()
	for m in MODES:
		_mode_btn.add_item(m[0])
	_mode_btn.custom_minimum_size = Vector2(260, 0)
	opts.add_child(_mode_btn)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(24, 0)
	opts.add_child(sp)
	opts.add_child(_label("Punti", 15))
	_budget_btn = OptionButton.new()
	for b in BUDGETS:
		_budget_btn.add_item(str(b))
	opts.add_child(_budget_btn)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(24, 0)
	opts.add_child(sp2)
	_fort_label = _label("Fortezza", 15)
	opts.add_child(_fort_label)
	_fort_btn = OptionButton.new()
	_fort_btn.custom_minimum_size = Vector2(220, 0)
	_fort_btn.item_selected.connect(_on_fortress_selected)
	opts.add_child(_fort_btn)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_child(filler)
	var editor_btn := Button.new()
	editor_btn.text = "Editor fortezze…"
	editor_btn.tooltip_text = "Strumento di sviluppo: disegna e salva nuove fortezze da assediare"
	editor_btn.pressed.connect(func() -> void:
		GameConfig.fortress_override = {}
		get_tree().change_scene_to_file("res://fortress_editor.tscn"))
	opts.add_child(editor_btn)
	var desc_row := HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 16)
	root.add_child(desc_row)
	_mode_desc = _label("", 14)
	_mode_desc.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	desc_row.add_child(_mode_desc)
	_fort_preview = FortressMapView.new()
	_fort_preview.custom_minimum_size = Vector2(300, 150)
	_fort_preview.show_labels = false
	_fort_preview.show_attack_zone = false
	_fort_preview.view = Rect2(-140.0, -175.0, 280.0, 175.0)
	desc_row.add_child(_fort_preview)

	# --- tre colonne: catalogo, tuo esercito, nemico
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var catalog := _scroll_list(_column(cols, "Unità disponibili", 1.25))
	for id in GameConfig.UNIT_IDS:
		catalog.add_child(_catalog_card(id))
	var mine := _column(cols, "Il tuo esercito", 1.0, BLUE)
	_player_points = _label("", 14)
	mine.add_child(_player_points)
	_player_list = _scroll_list(mine)
	var clear := Button.new()
	clear.text = "Svuota"
	clear.pressed.connect(func() -> void:
		GameConfig.player_army.assign(["general"])
		_refresh())
	mine.add_child(clear)
	var enemy := _column(cols, "Esercito nemico", 1.0, RED)
	_enemy_points = _label("", 14)
	enemy.add_child(_enemy_points)
	_enemy_list = _scroll_list(enemy)
	var reroll := Button.new()
	reroll.text = "Genera un altro nemico"
	reroll.pressed.connect(_reroll_enemy)
	enemy.add_child(reroll)

	# --- avvio
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	root.add_child(bottom)
	_warning = _label("", 14)
	_warning.add_theme_color_override("font_color", RED)
	_warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_warning)
	_start_btn = Button.new()
	_start_btn.text = "  Inizia la battaglia  ▶  "
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.custom_minimum_size = Vector2(300, 52)
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)

	# stato iniziale da GameConfig (ricorda le scelte quando si torna dal campo)
	for i in MODES.size():
		if MODES[i][1] == GameConfig.mode and (MODES[i][1] == "field" or MODES[i][2] == GameConfig.player_attacks):
			_mode_btn.select(i)
	_budget_btn.select(maxi(0, BUDGETS.find(GameConfig.budget)))
	_mode_btn.item_selected.connect(func(_i: int) -> void: _apply_options(true))
	_budget_btn.item_selected.connect(func(_i: int) -> void: _apply_options(true))
	_apply_options(false)


# ---------------------------------------------------------------- costruzione UI

func _label(t: String, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	return l


func _style(col: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _column(parent: Control, title: String, ratio: float, col := ACCENT) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.add_theme_stylebox_override("panel", _style(PANEL))
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := _label(title, 18)
	t.add_theme_color_override("font_color", col)
	v.add_child(t)
	return v


func _scroll_list(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v


func _catalog_card(id: String) -> Control:
	var s := GameConfig.stats(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color(0.16, 0.18, 0.24), Color(1, 1, 1, 0.08)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var head := _label("%s  ·  %s" % [s.display_name, ROLE_NAMES.get(s.role, s.role)], 16)
	v.add_child(head)
	var stats := _label(_stats_line(s), 12)
	stats.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	v.add_child(stats)
	var desc := _label(s.description, 12)
	desc.add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var add := Button.new()
	add.text = "+ %d" % s.cost
	add.custom_minimum_size = Vector2(86, 40)
	add.tooltip_text = "Aggiungi %s (%d punti)" % [s.display_name, s.cost]
	add.pressed.connect(_add_unit.bind(id))
	h.add_child(add)
	_add_buttons[id] = add
	return card


func _stats_line(s: UnitStats) -> String:
	var parts := PackedStringArray()
	parts.append("%d modelli" % s.models)
	parts.append("vita %d" % int(s.hp))
	parts.append("att %d" % int(s.melee_attack))
	parts.append("dif %d" % int(s.melee_defense))
	parts.append("corazza %d" % int(s.armor))
	parts.append("vel %.0f" % s.speed)
	if s.is_ranged:
		parts.append("gittata %d" % int(s.missile_range))
	if s.is_artillery:
		parts.append("esplosione %d m" % int(s.splash_radius))
		parts.append("sfonda porte")
	if s.anti_large:
		parts.append("anti-grande")
	if s.charge_bonus >= 30.0:
		parts.append("carica %d" % int(s.charge_bonus))
	if s.causes_fear:
		parts.append("paura")
	return " · ".join(parts)


# ---------------------------------------------------------------- logica

func _apply_options(user_changed: bool) -> void:
	var m: Array = MODES[_mode_btn.selected]
	GameConfig.mode = m[1]
	GameConfig.player_attacks = m[2]
	GameConfig.budget = BUDGETS[_budget_btn.selected]
	_mode_desc.text = m[3]
	var siege := GameConfig.is_siege()
	_fort_label.visible = siege
	_fort_btn.visible = siege
	_fort_preview.visible = siege
	if siege:
		_refresh_fortresses()
	_trim(GameConfig.player_army, GameConfig.budget_for(true))
	if user_changed or GameConfig.army_cost(GameConfig.enemy_army) > GameConfig.budget_for(false):
		_reroll_enemy()
	_refresh()


func _trim(army: Array[String], points: int) -> void:
	while army.size() > 1 and GameConfig.army_cost(army) > points:
		army.remove_at(army.size() - 1)


func _add_unit(id: String) -> void:
	var army := GameConfig.player_army
	if army.size() - 1 >= GameConfig.MAX_REGIMENTS:
		return
	if GameConfig.army_cost(army) + GameConfig.stats(id).cost > GameConfig.budget_for(true):
		return
	army.append(id)
	_refresh()


func _remove_unit(index: int) -> void:
	if index <= 0 or index >= GameConfig.player_army.size():
		return
	GameConfig.player_army.remove_at(index)
	_refresh()


func _reroll_enemy() -> void:
	GameConfig.enemy_army = GameConfig.random_army(GameConfig.budget_for(false))
	_refresh()


func _refresh() -> void:
	var p_budget := GameConfig.budget_for(true)
	var e_budget := GameConfig.budget_for(false)
	var p_cost := GameConfig.army_cost(GameConfig.player_army)
	var regs := GameConfig.player_army.size() - 1
	_player_points.text = "Punti %d / %d  ·  reggimenti %d / %d" % [p_cost, p_budget, regs, GameConfig.MAX_REGIMENTS]
	_enemy_points.text = "Punti %d / %d  ·  reggimenti %d" % [GameConfig.army_cost(GameConfig.enemy_army), e_budget, GameConfig.enemy_army.size() - 1]
	for id: String in _add_buttons:
		var b: Button = _add_buttons[id]
		b.disabled = regs >= GameConfig.MAX_REGIMENTS or p_cost + GameConfig.stats(id).cost > p_budget
	_fill_list(_player_list, GameConfig.player_army, true)
	_fill_list(_enemy_list, GameConfig.enemy_army, false)
	var has_fighters := regs > 0
	_start_btn.disabled = not has_fighters
	_warning.text = "" if has_fighters else "Aggiungi almeno un reggimento oltre al generale."


func _fill_list(list: VBoxContainer, army: Array[String], removable: bool) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	# raggruppa per tipo: "Lancieri ×2"
	var counts := {}
	var order: Array[String] = []
	for id in army:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	for id in order:
		var s := GameConfig.stats(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := _label("%s  ×%d" % [s.display_name, counts[id]], 15)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var cost_l := _label("%d" % (s.cost * int(counts[id])), 14)
		cost_l.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
		row.add_child(cost_l)
		if removable and id != "general":
			var minus := Button.new()
			minus.text = "−"
			minus.custom_minimum_size = Vector2(34, 30)
			minus.tooltip_text = "Togli un reggimento di %s" % s.display_name
			minus.pressed.connect(func() -> void: _remove_unit(army.rfind(id)))
			row.add_child(minus)
			var plus := Button.new()
			plus.text = "+"
			plus.custom_minimum_size = Vector2(34, 30)
			plus.disabled = (_add_buttons[id] as Button).disabled if _add_buttons.has(id) else true
			plus.pressed.connect(_add_unit.bind(id))
			row.add_child(plus)
		list.add_child(row)


func _refresh_fortresses() -> void:
	_forts = FortressLayout.list_all()
	_fort_btn.clear()
	var sel := 0
	for i in _forts.size():
		var f: Dictionary = _forts[i]
		_fort_btn.add_item(f["name"] if f["builtin"] else "%s  (tua)" % f["name"])
		if f["path"] == GameConfig.fortress_path:
			sel = i
	if not _forts.is_empty():
		_fort_btn.select(sel)
		_on_fortress_selected(sel)


func _on_fortress_selected(i: int) -> void:
	if i < 0 or i >= _forts.size():
		return
	GameConfig.fortress_path = _forts[i]["path"]
	_fort_preview.set_layout(FortressLayout.from_data(FortressLayout.load_file(GameConfig.fortress_path)))


func _start() -> void:
	GameConfig.fortress_override = {}
	GameConfig.return_to_editor = false
	get_tree().change_scene_to_file("res://main.tscn")
