@tool
class_name UnitVisual
extends Resource
## L'aspetto di un tipo di unità: la mesh di un singolo soldato e un'animazione per ogni stato.
## Si modifica nell'Inspector dentro la scheda dell'unità (data/units/*.tres → Aspetto → Visual).
##
## La mesh può essere una di quelle del prototipo (data/meshes/) o un modello tuo:
## importa il .glb in Godot, salva la sua mesh come risorsa e trascinala qui. Il soldato
## guarda verso -Z; se il modello guarda altrove, correggi con "Rotazione".
## Per usare le animazioni di un modello con scheletro, cuocile con tools/vat_baker.tscn:
## crea una UnitVisual già pronta, con mesh, texture VAT e fotogrammi di ogni stato.

## Gli stati, nell'ordine in cui li legge lo shader.
const STATES := ["idle", "walk", "run", "attack", "shoot", "hit", "death"]
enum { IDLE, WALK, RUN, ATTACK, SHOOT, HIT, DEATH }

@export_group("Modello")
## La mesh di un soldato (un solo pezzo per tutto il reggimento).
@export var mesh: Mesh:
	set(v): mesh = v; emit_changed()
## Texture dei colori del modello (vuota = tinta unita, solo colore della squadra).
@export var albedo_texture: Texture2D:
	set(v): albedo_texture = v; emit_changed()
## Texture a tavolozza (pochi pixel, un colore per zona, come nei pacchetti low-poly):
## niente sfumature tra i pixel, così i colori restano netti anche da lontano.
@export var pixel_texture := false:
	set(v): pixel_texture = v; emit_changed()
## Quanto il colore della squadra tinge il modello (1 = del tutto, 0 = colori originali).
@export_range(0.0, 1.0, 0.05) var team_color_strength := 1.0:
	set(v): team_color_strength = v; emit_changed()
## Scala del modello.
@export_range(0.01, 100.0, 0.01, "or_greater") var model_scale := 1.0:
	set(v): model_scale = v; emit_changed()
## Rotazione attorno all'asse verticale (gradi), per far guardare il modello verso -Z.
@export_range(-180.0, 180.0, 1.0) var model_yaw_deg := 0.0:
	set(v): model_yaw_deg = v; emit_changed()
## Spostamento del modello (m), per esempio per appoggiarlo a terra.
@export var model_offset := Vector3.ZERO:
	set(v): model_offset = v; emit_changed()

@export_group("Animazioni")
@export var idle: UnitAnimation:
	set(v): idle = v; _watch(v); emit_changed()
@export var walk: UnitAnimation:
	set(v): walk = v; _watch(v); emit_changed()
@export var run: UnitAnimation:
	set(v): run = v; _watch(v); emit_changed()
@export var attack: UnitAnimation:
	set(v): attack = v; _watch(v); emit_changed()
## Tiro (arcieri, artiglieria).
@export var shoot: UnitAnimation:
	set(v): shoot = v; _watch(v); emit_changed()
## Colpito e sbalzato a terra (dalle cariche e dalle esplosioni).
@export var hit: UnitAnimation:
	set(v): hit = v; _watch(v); emit_changed()
## Morte: alla fine il soldato resta nella posa finale.
@export var death: UnitAnimation:
	set(v): death = v; _watch(v); emit_changed()

@export_group("Animazioni cotte (VAT)")
## Posizioni dei vertici per ogni fotogramma (creata da tools/vat_baker.tscn).
@export var vat_positions: Texture2D:
	set(v): vat_positions = v; emit_changed()
## Normali dei vertici per ogni fotogramma.
@export var vat_normals: Texture2D:
	set(v): vat_normals = v; emit_changed()
## Righe della texture per ogni fotogramma (i vertici sono disposti su più righe se sono tanti).
@export var vat_rows_per_frame := 1:
	set(v): vat_rows_per_frame = v; emit_changed()


func _watch(a: UnitAnimation) -> void:
	# una modifica dentro un'animazione aggiorna l'anteprima come una modifica qui
	if a != null and not a.changed.is_connected(emit_changed):
		a.changed.connect(emit_changed)


func anim(state: int) -> UnitAnimation:
	var a: UnitAnimation = get(STATES[state])
	return a if a != null else UnitAnimation.new()


func duration_of(state: int) -> float:
	return anim(state).duration


func uses_vat() -> bool:
	return vat_positions != null


## Scrive nel materiale tutto ciò che serve allo shader dei soldati (e del contorno).
func apply_to(mat: ShaderMaterial) -> void:
	var p0: Array[Vector4] = []
	var p1: Array[Vector4] = []
	var p2: Array[Vector4] = []
	var p3: Array[Vector4] = []
	for s in STATES.size():
		var pk := anim(s).packed()
		p0.append(pk[0])
		p1.append(pk[1])
		p2.append(pk[2])
		p3.append(pk[3])
	mat.set_shader_parameter("anim_p0", p0)
	mat.set_shader_parameter("anim_p1", p1)
	mat.set_shader_parameter("anim_p2", p2)
	mat.set_shader_parameter("anim_p3", p3)
	mat.set_shader_parameter("model_scale", model_scale)
	mat.set_shader_parameter("model_yaw", deg_to_rad(model_yaw_deg))
	mat.set_shader_parameter("model_offset", model_offset)
	mat.set_shader_parameter("use_vat", uses_vat())
	mat.set_shader_parameter("vat_positions", vat_positions)
	mat.set_shader_parameter("vat_normals", vat_normals)
	mat.set_shader_parameter("vat_has_normals", vat_normals != null)
	mat.set_shader_parameter("vat_rows", maxi(vat_rows_per_frame, 1))
	if mat.shader != null and mat.shader.resource_path.ends_with("unit.gdshader"):
		mat.set_shader_parameter("albedo_texture", albedo_texture)
		mat.set_shader_parameter("use_texture", albedo_texture != null)
		mat.set_shader_parameter("albedo_texture_pixel", albedo_texture)
		mat.set_shader_parameter("pixel_texture", pixel_texture)
		mat.set_shader_parameter("team_strength", team_color_strength)


# ---------------------------------------------------------------- preimpostazioni

static func _a(p: Dictionary) -> UnitAnimation:
	return UnitAnimation.make(p)


## Un aspetto completo per i modelli del prototipo, con animazioni adatte al tipo di mesh.
static func preset(kind: String, p_mesh: Mesh = null) -> UnitVisual:
	var v := UnitVisual.new()
	v.mesh = p_mesh if p_mesh != null else UnitMeshes.build(kind)
	match kind:
		"cavalry", "general":
			v.idle = _a({"speed": 0.4, "bob": 0.02, "rock_deg": 1.0})
			v.walk = _a({"speed": 1.6, "bob": 0.1, "rock_deg": 2.5, "sway_deg": 1.5})
			v.run = _a({"speed": 2.4, "bob": 0.3, "rock_deg": 7.0, "lean_deg": 4.0})
			v.attack = _a({"one_shot": true, "duration": 0.6, "bend_deg": 45.0, "bend_pivot": 1.7, "lean_deg": 5.0})
			v.shoot = _a({"one_shot": true, "duration": 0.5, "bend_deg": -15.0, "bend_pivot": 1.7})
			v.hit = _a({"one_shot": true, "duration": 1.0, "lean_deg": -18.0})
			v.death = _a({"one_shot": true, "duration": 1.0, "lean_deg": 80.0, "hold_lean": true})
		"monster":
			v.idle = _a({"speed": 0.3, "bob": 0.06, "sway_deg": 2.0})
			v.walk = _a({"speed": 1.0, "bob": 0.16, "sway_deg": 6.0, "lean_deg": 3.0})
			v.run = _a({"speed": 1.5, "bob": 0.32, "sway_deg": 8.0, "lean_deg": 9.0})
			v.attack = _a({"one_shot": true, "duration": 0.9, "bend_deg": 60.0, "bend_pivot": 1.9, "lean_deg": 10.0})
			v.shoot = _a({"one_shot": true, "duration": 0.9, "bend_deg": 40.0, "bend_pivot": 1.9})
			v.hit = _a({"one_shot": true, "duration": 0.9, "lean_deg": -14.0})
			v.death = _a({"one_shot": true, "duration": 1.4, "lean_deg": 85.0, "hold_lean": true})
		"catapult":
			v.idle = _a({})
			v.walk = _a({"speed": 1.0, "bob": 0.03, "rock_deg": 1.5})
			v.run = _a({"speed": 1.2, "bob": 0.05, "rock_deg": 2.0})
			v.attack = _a({"one_shot": true, "duration": 0.6, "lean_deg": 3.0})
			# il braccio scatta in avanti e torna giù
			v.shoot = _a({"one_shot": true, "duration": 1.4, "bend_deg": 75.0, "bend_pivot": 2.3})
			v.hit = _a({"one_shot": true, "duration": 0.8, "lean_deg": -6.0})
			v.death = _a({"one_shot": true, "duration": 1.2, "lean_deg": 28.0, "hold_lean": true})
		"cannon":
			v.idle = _a({})
			v.walk = _a({"speed": 1.0, "bob": 0.03, "rock_deg": 1.5})
			v.run = _a({"speed": 1.2, "bob": 0.05, "rock_deg": 2.0})
			v.attack = _a({"one_shot": true, "duration": 0.6, "lean_deg": 3.0})
			# rinculo: la bocca si alza e il pezzo sobbalza
			v.shoot = _a({"one_shot": true, "duration": 0.5, "lean_deg": -9.0, "bob": 0.0})
			v.hit = _a({"one_shot": true, "duration": 0.8, "lean_deg": -6.0})
			v.death = _a({"one_shot": true, "duration": 1.0, "lean_deg": 22.0, "hold_lean": true})
		_:
			# soldati a piedi: fanti, lancieri, arcieri
			v.idle = _a({"speed": 0.35, "bob": 0.015, "sway_deg": 1.2})
			v.walk = _a({"speed": 1.8, "bob": 0.07, "sway_deg": 3.0, "lean_deg": 3.0})
			v.run = _a({"speed": 2.6, "bob": 0.14, "sway_deg": 4.0, "lean_deg": 10.0})
			v.attack = _a({"one_shot": true, "duration": 0.55, "bend_deg": 55.0, "bend_pivot": 1.0, "lean_deg": 8.0})
			v.shoot = _a({"one_shot": true, "duration": 0.7, "bend_deg": -14.0, "bend_pivot": 1.0, "lean_deg": -3.0})
			v.hit = _a({"one_shot": true, "duration": 0.9, "lean_deg": -35.0})
			v.death = _a({"one_shot": true, "duration": 0.8, "lean_deg": 88.0, "hold_lean": true})
	return v
