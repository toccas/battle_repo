class_name BattleManager
extends Node3D
## Orchestratore della battaglia: fasi (schieramento, battaglia, fine), tempo,
## e il ciclo che chiama i sistemi a frequenze diverse (doc: "Architettura tecnica").

enum Phase { DEPLOY, BATTLE, ENDED }

signal battle_started
signal battle_ended(winner: int)

const EDGE := 170.0           ## i reggimenti in rotta escono oltre questa distanza (asse Z)
const TICK := 0.1             ## combattimento: 10 volte al secondo
const MORALE_TICK := 0.5      ## morale: 2 volte al secondo
const MAX_BATTLE_TIME := 40.0 * 60.0
const DEFENDER_TEAM := 1

var regiments: Array[Regiment] = []
var phase: int = Phase.DEPLOY
var time_scale := 1.0
var paused := false
var battle_time := 0.0
var winner := -1
var end_reason := ""
var army_routed := [false, false]
var fortress: Fortress = null                 ## presente solo nelle battaglie d'assedio
var home_dir: Array[float] = [1.0, -1.0]      ## verso dove fugge ogni squadra (asse Z)

var combat: CombatSystem
var morale_sys: MoraleSystem
var projectiles: ProjectileSystem
var ais: Array[AIGeneral] = []

var perf_tick_usec := 0.0
var _tick_acc := 0.0
var _morale_acc := 0.0
var _visuals := {}
var _unit_mats := {}
var _outline_mats := {}
## Orologio delle animazioni dei soldati: scorre con la simulazione e si ferma in pausa.
var anim_time := 0.0
const OUTLINE_SHADER := preload("res://scripts/outline.gdshader")


func _ready() -> void:
	combat = CombatSystem.new(self)
	morale_sys = MoraleSystem.new(self)
	projectiles = ProjectileSystem.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	projectiles.setup(self)


func add_regiment(stats: UnitStats, team: int, p_name: String, at: Vector3, face: Vector3, color: Color) -> Regiment:
	var r := Regiment.new()
	add_child(r)
	r.setup(self, stats, team, regiments.size(), p_name, at, face, color)
	regiments.append(r)
	return r


func add_ai(team: int) -> AIGeneral:
	var ai: AIGeneral
	if fortress != null:
		ai = SiegeAI.new(self, team)
	else:
		ai = AIGeneral.new(self, team)
	ais.append(ai)
	return ai


## Crea la fortezza: `defender` presidia le mura, l'altra squadra attacca da sud.
func setup_siege(defender: int, layout: FortressLayout = null) -> Fortress:
	fortress = Fortress.new()
	fortress.name = "Fortress"
	add_child(fortress)
	fortress.setup(self, defender, layout)
	home_dir[1 - defender] = 1.0     # gli attaccanti fuggono verso sud
	home_dir[defender] = -1.0        # i difensori escono dalla postierla verso nord
	return fortress


func start_battle() -> void:
	if phase != Phase.DEPLOY:
		return
	phase = Phase.BATTLE
	battle_started.emit()


func _process(delta: float) -> void:
	if not paused:
		anim_time += minf(delta, 0.05) * (time_scale if phase != Phase.DEPLOY else 1.0)
	RenderingServer.global_shader_parameter_set("unit_anim_time", anim_time)
	if phase != Phase.DEPLOY and not paused:
		var dt := minf(delta, 0.05) * time_scale
		var steps := maxi(1, int(ceil(dt / 0.034)))
		var sdt := dt / steps
		for s in steps:
			_sim_step(sdt)
	for r in regiments:
		r.update_visuals()
	projectiles.update_visuals()


func _sim_step(dt: float) -> void:
	battle_time += dt
	_tick_acc += dt
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		var t0 := Time.get_ticks_usec()
		combat.tick(TICK)
		projectiles.fire_tick(TICK)
		perf_tick_usec = lerpf(perf_tick_usec, float(Time.get_ticks_usec() - t0), 0.1)
	_morale_acc += dt
	if _morale_acc >= MORALE_TICK:
		_morale_acc -= MORALE_TICK
		morale_sys.tick(MORALE_TICK)
		_check_end()
	for ai in ais:
		ai.update(dt)
	for r in regiments:
		r.sim_update(dt)
	projectiles.update(dt)
	if fortress != null:
		fortress.update(dt)


# ---------------------------------------------------------------- fine battaglia

func _check_end() -> void:
	if phase != Phase.BATTLE:
		return
	for team in [0, 1]:
		var total := 0
		var broken := 0
		var morale_sum := 0.0
		for r in regiments:
			if r.team != team:
				continue
			total += 1
			if not r.is_on_field() or r.state == Regiment.State.ROUTING:
				broken += 1
			else:
				morale_sum += r.morale
		if total == 0:
			continue
		if broken == total:
			end_battle(1 - team, "L'esercito nemico è in rotta" if team == 1 else "Il tuo esercito è in rotta")
			return
		# rotta generale: 60% dei reggimenti in fuga e morale medio sotto 25
		if not army_routed[team] and broken >= int(ceil(total * 0.6)) and morale_sum / total < 25.0:
			army_routed[team] = true
			for r in regiments:
				if r.team == team and r.is_on_field():
					r.shatter()
	if fortress != null and battle_time >= Fortress.SIEGE_TIME:
		end_battle(fortress.defender_team, "Tempo scaduto: la fortezza ha resistito")
	elif battle_time >= MAX_BATTLE_TIME:
		end_battle(DEFENDER_TEAM, "Tempo scaduto")


func end_battle(w: int, reason := "") -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	winner = w
	end_reason = reason
	battle_ended.emit(w)


func team_summary(team: int) -> Dictionary:
	var start := 0
	var alive := 0
	var kills := 0
	for r in regiments:
		if r.team == team:
			start += r.count
			alive += r.alive_count
			kills += r.kills
	return {"start": start, "alive": alive, "lost": start - alive, "kills": kills}


# ---------------------------------------------------------------- utilità per i sistemi

func flee_dir(team: int) -> float:
	return home_dir[team]


func flee_z(team: int) -> float:
	return EDGE * flee_dir(team)


func general_of(team: int) -> Regiment:
	for r in regiments:
		if r.team == team and r.stats.is_general:
			return r
	return null


func nearest_enemy(r: Regiment, max_dist: float) -> Regiment:
	var best: Regiment = null
	var best_d := max_dist
	var m := r.mid()
	for o in regiments:
		if o.team == r.team or not o.is_on_field():
			continue
		var d := m.distance_to(o.mid())
		if d < best_d:
			best_d = d
			best = o
	return best


func enemy_within(r: Regiment, dist: float) -> bool:
	var m := r.mid()
	for o in regiments:
		if o.team != r.team and o.is_on_field() and o.state != Regiment.State.ROUTING:
			if m.distance_to(o.mid()) < dist + o.bound_radius():
				return true
	return false


func team_strength(team: int) -> float:
	var s := 0.0
	for r in regiments:
		if r.team == team and r.is_on_field() and r.state != Regiment.State.ROUTING:
			s += r.strength()
	return s


func soldier_count() -> int:
	var n := 0
	for r in regiments:
		if r.is_on_field():
			n += r.alive_count
	return n


# ---------------------------------------------------------------- aspetto dei soldati

const UNIT_SHADER := preload("res://scripts/unit.gdshader")

## Aspetto di un tipo di unità: quello impostato nell'Inspector, o la preimpostazione del prototipo.
func get_visual(stats: UnitStats) -> UnitVisual:
	if stats.visual != null and stats.visual.mesh != null:
		return stats.visual
	if not _visuals.has(stats.mesh_kind):
		_visuals[stats.mesh_kind] = UnitVisual.preset(stats.mesh_kind)
	return _visuals[stats.mesh_kind]


## Un materiale per tipo di unità, condiviso dai suoi reggimenti (la squadra è nel colore d'istanza).
func get_unit_material(stats: UnitStats) -> ShaderMaterial:
	if not _unit_mats.has(stats.id):
		var m := ShaderMaterial.new()
		m.shader = UNIT_SHADER
		get_visual(stats).apply_to(m)
		_unit_mats[stats.id] = m
	return _unit_mats[stats.id]


## Il contorno usa la stessa animazione: un materiale per tipo di unità e per colore.
func get_outline_material(col: Color, stats: UnitStats) -> ShaderMaterial:
	var key := "%s_%s" % [stats.id, col.to_html()]
	if not _outline_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_SHADER
		m.set_shader_parameter("outline_color", col)
		get_visual(stats).apply_to(m)
		_outline_mats[key] = m
	return _outline_mats[key]
