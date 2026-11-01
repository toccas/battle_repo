@tool
extends Node3D
## Anteprima delle unità: apri tools/anteprima_unita.tscn nell'editor, seleziona il nodo radice
## e scegli unità e stato qui nell'Inspector. Le modifiche all'aspetto dell'unità
## (data/units/*.tres → Aspetto → Visual) si vedono subito nella vista 3D, senza avviare il gioco.
## Avviata con F6: tasti 1-7 per lo stato, Q/E per cambiare unità, rotella per lo zoom.

const STATE_NAMES := ["Fermo", "Cammino", "Corsa", "Attacco", "Tiro", "Colpito", "Morte"]
const UNIT_SHADER := preload("res://scripts/unit.gdshader")

## L'unità da mostrare (un file di data/units/).
@export var unit: UnitStats:
	set(v):
		if unit != null and unit.changed.is_connected(_refresh):
			unit.changed.disconnect(_refresh)
		unit = v
		if unit != null:
			unit.changed.connect(_refresh)
		_refresh()
@export_enum("Fermo", "Cammino", "Corsa", "Attacco", "Tiro", "Colpito", "Morte") var state := 1:
	set(v): state = v; _restart()
## Quanti soldati in fila e in profondità.
@export var soldiers := Vector2i(4, 2):
	set(v): soldiers = v; _refresh()
@export var team_color := Color(0.25, 0.45, 0.95):
	set(v): team_color = v; _refresh()
## Ripeti le animazioni "una volta" (attacco, tiro, colpito, morte) con una pausa tra l'una e l'altra.
@export var repeat_one_shots := true
## Velocità dell'anteprima (1 = tempo reale).
@export_range(0.05, 2.0, 0.05) var playback_speed := 1.0

var time := 0.0
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _visual: UnitVisual
var _start := 0.0
var _units: Array[UnitStats] = []
var _label: Label
var _cam: Camera3D
var _cam_dist := 9.0


func _ready() -> void:
	_build_scene()
	if unit == null:
		unit = load("res://data/units/spearmen.tres")
	_refresh()
	if not Engine.is_editor_hint():
		for f in DirAccess.get_files_at("res://data/units"):
			if f.ends_with(".tres"):
				_units.append(load("res://data/units/" + f))


func _build_scene() -> void:
	# nodi interni, senza proprietario: non finiscono nel file della scena
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.24, 0.32, 0.16)
	ground.material_override = gm
	add_child(ground)
	_mmi = MultiMeshInstance3D.new()
	add_child(_mmi)
	_cam = Camera3D.new()
	add_child(_cam)
	_place_camera()
	if not Engine.is_editor_hint():
		var layer := CanvasLayer.new()
		_label = Label.new()
		_label.position = Vector2(14, 10)
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 6)
		layer.add_child(_label)
		add_child(layer)


func _place_camera() -> void:
	if _cam == null:
		return
	var h := unit.model_height if unit != null else 1.8
	var d := _cam_dist * maxf(h / 1.8, 1.0)
	_cam.position = Vector3(d * 0.75, h * 0.9 + d * 0.25, d * 0.55)
	_cam.look_at(Vector3(0, h * 0.5, -1.0))


## Ricostruisce mesh, materiale e soldati dall'aspetto dell'unità.
func _refresh() -> void:
	if not is_inside_tree() or _mmi == null or unit == null:
		return
	var v: UnitVisual = unit.visual if unit.visual != null and unit.visual.mesh != null else UnitVisual.preset(unit.mesh_kind)
	if _visual != v:
		if _visual != null and _visual.changed.is_connected(_apply):
			_visual.changed.disconnect(_apply)
		_visual = v
		_visual.changed.connect(_apply)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _visual.mesh
	mm.instance_count = soldiers.x * soldiers.y
	var sx := maxf(unit.spacing, 1.0)
	var sz := maxf(unit.row_spacing, 1.0)
	var k := 0
	for z in soldiers.y:
		for x in soldiers.x:
			var p := Vector3((x - (soldiers.x - 1) * 0.5) * sx, 0, z * sz)
			mm.set_instance_transform(k, Transform3D(Basis(), p))
			mm.set_instance_color(k, team_color * unit.tint)
			k += 1
	_mmi.multimesh = mm
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = UNIT_SHADER
	_mmi.material_override = _mat
	_apply()
	_place_camera()
	_restart()


func _apply() -> void:
	if _mat != null and _visual != null:
		_visual.apply_to(_mat)


func _restart() -> void:
	_start = time
	_write_custom()


func _write_custom() -> void:
	if _mmi == null or _mmi.multimesh == null:
		return
	var mm := _mmi.multimesh
	for k in mm.instance_count:
		# sfasamento fisso per soldato: si vede che i passi non sono sincronizzati
		var seed := fposmod(k * 0.618034, 1.0)
		mm.set_instance_custom_data(k, Color(1, state, _start, seed))


func _process(delta: float) -> void:
	time += delta * playback_speed
	RenderingServer.global_shader_parameter_set("unit_anim_time", time)
	if _visual != null and repeat_one_shots:
		var a := _visual.anim(state)
		if a.one_shot and time - _start > a.duration + 0.8:
			_restart()
	if _label != null and unit != null:
		_label.text = "%s · %s   (1-7 stato, Q/E unità, rotella zoom)" % [unit.display_name, STATE_NAMES[state]]


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc >= KEY_1 and kc <= KEY_7:
			state = kc - KEY_1
		elif (kc == KEY_Q or kc == KEY_E) and not _units.is_empty():
			var i := _units.find(unit)
			unit = _units[posmod(i + (1 if kc == KEY_E else -1), _units.size())]
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(3.0, _cam_dist * 0.9)
			_place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(60.0, _cam_dist * 1.1)
			_place_camera()
