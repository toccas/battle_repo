class_name BattleUI
extends CanvasLayer
## Interfaccia di battaglia: carte delle unità, barra dell'equilibrio di potere,
## stato della battaglia, rettangolo di selezione, aiuto e schermata finale.

const BLUE := Color(0.3, 0.5, 1.0)
const RED := Color(0.9, 0.28, 0.22)

var battle: BattleManager
var controller: PlayerController

var _root: Control
var _phase_label: Label
var _power_a: ColorRect
var _power_b: ColorRect
var _cards_box: HFlowContainer
var _cards := {}          ## Regiment -> UnitCard
var _box: Panel
var _help: PanelContainer
var _perf: Label
var _detail: Label
var _end_panel: PanelContainer
var _end_label: Label
var _acc := 0.0
var _last_card_click := {}


func setup(b: BattleManager, c: PlayerController) -> void:
	battle = b
	controller = c
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top()
	_build_cards()
	_build_misc()
	_layout_cards()
	battle.battle_ended.connect(_on_battle_ended)


func _panel_style(bg: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(6)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _build_top() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-300, 10)
	top.custom_minimum_size = Vector2(600, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 18)
	_phase_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_phase_label.add_theme_constant_override("outline_size", 6)
	top.add_child(_phase_label)
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(600, 12)
	bar.add_theme_constant_override("separation", 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar)
	_power_a = ColorRect.new()
	_power_a.color = BLUE
	_power_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_a.size_flags_stretch_ratio = 1.0
	_power_b = ColorRect.new()
	_power_b.color = RED
	_power_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_b.size_flags_stretch_ratio = 1.0
	bar.add_child(_power_a)
	bar.add_child(_power_b)


const CARD_W := 60.0        ## carta a stendardo: larghezza piena
const CARD_MIN_W := 50.0    ## sotto questa larghezza le carte vanno a capo su più file
const CARD_RATIO := 1.8     ## altezza / larghezza
const CARD_GAP := 5
const CARDS_MARGIN := 10.0


func _build_cards() -> void:
	# le carte si stringono per stare in una fila; se sono troppe vanno a capo e crescono verso l'alto
	_cards_box = HFlowContainer.new()
	_cards_box.anchor_left = 0.5
	_cards_box.anchor_right = 0.5
	_cards_box.anchor_top = 1.0
	_cards_box.anchor_bottom = 1.0
	_cards_box.offset_bottom = -CARDS_MARGIN
	_cards_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cards_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("h_separation", CARD_GAP)
	_cards_box.add_theme_constant_override("v_separation", CARD_GAP)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cards_box)
	for r in battle.regiments:
		if r.team == controller.team:
			_add_card(r)
	get_viewport().size_changed.connect(_layout_cards)
	_layout_cards()


## Dimensioni delle carte in base a quante sono e a quanto è largo lo schermo.
func _layout_cards() -> void:
	var n := _cards.size()
	if n == 0:
		return
	var avail := get_viewport().get_visible_rect().size.x - CARDS_MARGIN * 2.0
	var w := clampf(floorf((avail - CARD_GAP * (n - 1)) / n), CARD_MIN_W, CARD_W)
	var per_row := maxi(1, int((avail + CARD_GAP) / (w + CARD_GAP)))
	var rows := ceili(float(n) / per_row)
	if rows > 1:
		# su più file: carte distribuite in modo uniforme tra le righe
		per_row = ceili(float(n) / rows)
		w = clampf(floorf((avail - CARD_GAP * (per_row - 1)) / per_row), CARD_MIN_W, CARD_W)
	var card_h := roundf(w * CARD_RATIO)
	for r: Regiment in _cards:
		(_cards[r] as Control).custom_minimum_size = Vector2(w, card_h)
	# larghezza del contenitore = una fila esatta: così le file escono equilibrate (7 + 6, non 9 + 4)
	var content_w := per_row * w + (per_row - 1) * CARD_GAP
	_cards_box.offset_left = -ceilf(content_w * 0.5) - 1.0
	_cards_box.offset_right = ceilf(content_w * 0.5) + 1.0
	var height := rows * card_h + (rows - 1) * CARD_GAP
	_cards_box.offset_top = -CARDS_MARGIN - height
	if _detail != null:
		_detail.offset_bottom = -CARDS_MARGIN - height - 12.0
		_detail.offset_top = _detail.offset_bottom - 208.0


func _add_card(r: Regiment) -> void:
	var card := UnitCard.new()
	card.setup(r)
	card.gui_input.connect(_on_card_input.bind(r))
	_cards_box.add_child(card)
	_cards[r] = card


func _build_misc() -> void:
	_box = Panel.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_stylebox_override("panel", _panel_style(Color(0.4, 1.0, 0.5, 0.12), Color(0.4, 1.0, 0.5, 0.8), 1))
	_box.visible = false
	_root.add_child(_box)

	_help = PanelContainer.new()
	_help.position = Vector2(10, 10)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_theme_stylebox_override("panel", _panel_style(Color(0, 0, 0, 0.6)))
	var help_label := Label.new()
	help_label.add_theme_font_size_override("font_size", 13)
	help_label.text = """COMANDI  (H per nascondere)
Click sinistro / trascina: seleziona
Shift + click: aggiungi o togli
Doppio click: tutte le unità di quel tipo
Ctrl+A: seleziona tutto · Esc: deseleziona
Click destro: muovi · doppio click destro: corri
Shift + click destro: aggiungi una tappa (anche un attacco)
Click destro su un nemico: attacca (doppio = carica)
Destro trascinato: disponi in linea
Backspace: ferma · F: segui l'unità
Ctrl+1..9 crea gruppo · 1..9 richiama
WASD/frecce, Q/E, rotella, tasto centrale: camera
Spazio: pausa · Tab: velocità · Invio: inizia
Assedio: click destro su una porta per abbatterla
Difesa: click destro sulle mura per salirci (fanti e arcieri)
F9: ricomincia · F10: torna alla preparazione"""
	_help.add_child(help_label)
	_root.add_child(_help)

	_perf = Label.new()
	_perf.anchor_left = 1.0
	_perf.anchor_right = 1.0
	_perf.offset_left = -260
	_perf.offset_top = 10
	_perf.offset_right = -10
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_perf.add_theme_font_size_override("font_size", 12)
	_perf.add_theme_color_override("font_outline_color", Color.BLACK)
	_perf.add_theme_constant_override("outline_size", 4)
	_root.add_child(_perf)

	_detail = Label.new()
	_detail.anchor_left = 1.0
	_detail.anchor_right = 1.0
	_detail.anchor_top = 1.0
	_detail.anchor_bottom = 1.0
	_detail.offset_left = -300
	_detail.offset_right = -10
	_detail.offset_top = -340
	_detail.offset_bottom = -132
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_detail.add_theme_font_size_override("font_size", 12)
	_detail.add_theme_color_override("font_outline_color", Color.BLACK)
	_detail.add_theme_constant_override("outline_size", 4)
	_root.add_child(_detail)

	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.position = Vector2(-230, -170)
	_end_panel.custom_minimum_size = Vector2(460, 0)
	_end_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.1, 0.92), Color(0.8, 0.7, 0.4), 2))
	_end_panel.visible = false
	_end_label = Label.new()
	_end_label.add_theme_font_size_override("font_size", 15)
	_end_panel.add_child(_end_label)
	_root.add_child(_end_panel)


## Il punto è sopra un pannello dell'interfaccia (carte o schermata finale)?
func is_over_ui(p: Vector2) -> bool:
	for r: Regiment in _cards:
		if (_cards[r] as Control).get_global_rect().has_point(p):
			return true
	return _end_panel.visible and _end_panel.get_global_rect().has_point(p)


func show_box(rect: Rect2) -> void:
	_box.position = rect.position
	_box.size = rect.size
	_box.visible = true


func hide_box() -> void:
	_box.visible = false


func toggle_help() -> void:
	_help.visible = not _help.visible


func _on_card_input(event: InputEvent, r: Regiment) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var now := Time.get_ticks_msec() / 1000.0
			var dbl: bool = now - float(_last_card_click.get(r, -10.0)) < 0.35
			_last_card_click[r] = now
			controller.on_card_clicked(r, mb.shift_pressed, dbl)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.15:
		return
	_acc = 0.0
	_update_top()
	_update_cards()
	_update_detail()
	_perf.text = "%d FPS · %d soldati · tick %.1f ms" % [
		Engine.get_frames_per_second(), battle.soldier_count(), battle.perf_tick_usec / 1000.0]


func _update_top() -> void:
	match battle.phase:
		BattleManager.Phase.DEPLOY:
			_phase_label.text = "SCHIERAMENTO — click destro (o trascinato) per disporre le unità · INVIO per iniziare"
		BattleManager.Phase.BATTLE:
			var t := int(battle.battle_time)
			var s := "Battaglia  %02d:%02d   velocità %dx" % [t / 60, t % 60, int(battle.time_scale)]
			if battle.paused:
				s += "   ‖ PAUSA"
			_phase_label.text = s + _siege_text()
		BattleManager.Phase.ENDED:
			_phase_label.text = "Battaglia conclusa — R per ricominciare · M per la preparazione"
	var a := battle.team_strength(0)
	var b := battle.team_strength(1)
	var tot := maxf(a + b, 0.001)
	_power_a.size_flags_stretch_ratio = maxf(a / tot, 0.001)
	_power_b.size_flags_stretch_ratio = maxf(b / tot, 0.001)


## Riga extra in assedio: conquista del punto, porte, tempo rimasto.
func _siege_text() -> String:
	var f := battle.fortress
	if f == null:
		return ""
	var gs := PackedStringArray()
	for g in f.gates:
		if g.breakable:
			gs.append("%s %s" % [g.name.replace("Porta ", ""), "abbattuta" if g.destroyed else "%d%%" % int(100.0 * g.hp / g.max_hp)])
	var left := maxi(0, int(Fortress.SIEGE_TIME - battle.battle_time))
	var role := "Attacchi" if f.attacker_team == controller.team else "Difendi"
	return "\n%s · Punto di vittoria %d%% (%s) · Porte: %s · Tempo %02d:%02d" % [
		role, int(f.capture_progress * 100.0), f.capture_state_text(), ", ".join(gs), left / 60, left % 60]


func _update_cards() -> void:
	for r: Regiment in _cards:
		(_cards[r] as UnitCard).refresh()


func _update_detail() -> void:
	if controller.selected.size() != 1:
		_detail.text = ""
		return
	var r := controller.selected[0]
	var lines := PackedStringArray()
	lines.append("%s — %s" % [r.display_name, Regiment.STATE_NAMES[r.state]])
	lines.append("Morale %d (%s) · %s" % [int(r.morale), r.morale_label(), Regiment.FATIGUE_NAMES[r.fatigue_level()]])
	var mods := battle.morale_sys.modifiers(r)
	for k: String in mods:
		lines.append("   %+d  %s" % [int(mods[k]), k])
	lines.append("Uccisioni %d · formazione %d colonne" % [r.kills, r.cols])
	if r.charge_timer > 0.0:
		lines.append("Bonus carica attivo (%.0f s)" % r.charge_timer)
	_detail.text = "\n".join(lines)


func _on_battle_ended(winner: int) -> void:
	var me := battle.team_summary(controller.team)
	var foe := battle.team_summary(1 - controller.team)
	var title := "VITTORIA" if winner == controller.team else "SCONFITTA"
	var ratio := float(foe["lost"]) / maxf(float(me["lost"]), 1.0)
	if winner == controller.team:
		if ratio > 3.0:
			title = "VITTORIA DECISIVA"
		elif ratio < 1.0:
			title = "VITTORIA DI PIRRO"
	var lines := PackedStringArray()
	lines.append(title)
	if battle.end_reason != "":
		lines.append(battle.end_reason)
	lines.append("")
	lines.append("Tempo: %d:%02d" % [int(battle.battle_time) / 60, int(battle.battle_time) % 60])
	lines.append("Il tuo esercito: %d perdite su %d, %d uccisioni" % [me["lost"], me["start"], me["kills"]])
	lines.append("Nemico: %d perdite su %d, %d uccisioni" % [foe["lost"], foe["start"], foe["kills"]])
	lines.append("")
	for r in battle.regiments:
		if r.team == controller.team:
			lines.append("  %-16s %3d/%3d   uccisioni %d" % [r.display_name, r.alive_count, r.count, r.kills])
	lines.append("")
	lines.append("R per ricominciare · M per tornare alla preparazione")
	_end_label.text = "\n".join(lines)
	_end_panel.visible = true
