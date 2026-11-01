class_name Regiment
extends Node3D
## Un reggimento: il "cervello" (centro, ordini, morale, stanchezza) più i suoi soldati.
## I soldati NON sono nodi: sono array di dati (posizione, velocità, vita...) disegnati
## tutti insieme con un MultiMesh. È questo che permette di gestire migliaia di modelli.

enum State { IDLE, MOVING, ATTACKING, FIGHTING, ROUTING, GONE, BREACHING }

const STATE_NAMES := ["Fermo", "In marcia", "All'attacco", "In mischia", "In rotta", "Fuori campo", "Assalta la porta"]
const FATIGUE_NAMES := ["Fresco", "Attivo", "Accaldato", "Stanco", "Molto stanco", "Esausto"]
const MAX_RALLIES := 2
const AUTO_RETALIATE := true   ## i reparti fermi e senza ordini rispondono da soli quando vengono attaccati
const AUTO_CHASE := 35.0        ## oltre questa distanza dal punto di partenza la risposta automatica si ferma
const OUTLINE_ENEMY := Color(1.0, 0.08, 0.04)
const OUTLINE_OWN := Color(0.45, 1.0, 0.55)

var battle: BattleManager
var stats: UnitStats
var team := 0
var reg_id := 0
var display_name := ""
var team_color := Color.WHITE

# --- stato e formazione ---
var state: int = State.IDLE
var center := Vector3.ZERO          ## centro della PRIMA fila
var facing := Vector3(0, 0, -1)     ## direzione del fronte (sempre piatta, normalizzata)
var cols := 10

# --- ordini ---
var move_target := Vector3.ZERO
var move_facing := Vector3(0, 0, -1)
var running := false
var attack_target: Regiment = null
var auto_target := false        ## il bersaglio è una risposta automatica a un attacco, non un ordine
var _auto_home := Vector3.ZERO   ## da dove è partita la risposta: oltre AUTO_CHASE si torna a riposo
var attack_gate: Fortress.Gate = null   ## porta da abbattere (stato BREACHING)

# --- tappe successive (Shift + click destro) ---
## ogni tappa: {"pos": Vector3, "face": Vector3, "run": bool, "cols": int, "wall": int}
## oppure un attacco in coda: {"attack": Regiment, "run": bool}
var waypoints: Array[Dictionary] = []
var move_wall_side := -1      ## lato di mura di destinazione dell'ordine attuale (-1 = terreno)

# --- mura ---
var on_wall := false
var _wall_pos := PackedVector3Array()   ## sulle mura: posto di ogni slot lungo il camminamento
var _wall_face := PackedVector3Array()  ## e verso dove guarda (fuori dalle mura)
var wall_side := -1
var _base_y := 0.0            ## quota dei piedi: 0 a terra, Fortress.WALK_Y sulle mura
var _y_from := 0.0
var _y_to := 0.0
var _climb := 0.0             ## secondi rimasti di salita o discesa
var _climb_total := 1.0
var _ground_cols := 0         ## colonne da ripristinare quando si scende

# --- percorso (solo con una fortezza in campo) ---
var _route := PackedVector3Array()
var _route_final := Vector3(1e9, 0, 1e9)
var _route_timer := 0.0
var _route_gate: Fortress.Gate = null
var _squeezed := false
var _squeeze_at := Vector3.ZERO
var _pref_cols := 0

# --- combattimento (scritto dai sistemi) ---
var in_melee := false
var contact_this_tick := false
var melee_timer := 99.0
var melee_duration := 0.0
var charge_dist := 0.0
var charge_timer := 0.0
var impact_window := 0.0
var flank_timer := 0.0
var rear_timer := 0.0
var fear_timer := 0.0
var under_fire_timer := 0.0
var recent_dealt := 0.0
var recent_taken := 0.0
var kills := 0
var hot := false
var taken_melee := 0.0     ## statistiche: danni subiti in mischia
var taken_missile := 0.0   ## statistiche: danni subiti dal tiro
var killed_by := {}        ## statistiche: chi ha ucciso i nostri soldati

# --- morale e stanchezza ---
var morale := 50.0
var morale_target := 50.0
var fatigue := 0.0
var rout_count := 0
var shattered := false
var calm_timer := 0.0

# --- varie ---
var ammo := 0
var start_ammo := 0
var fled := false
var selected := false
var hovered := false
var hp_total := 0.0
var start_hp_total := 1.0

# --- soldati (array paralleli, indice = soldato) ---
var count := 0
var alive_count := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var push := PackedVector3Array()
var hp := PackedFloat32Array()
var timer := PackedFloat32Array()
var knock := PackedFloat32Array()
var alive := PackedByteArray()
var slot_of := PackedInt32Array()     ## soldato -> slot
var owner_of := PackedInt32Array()    ## slot -> soldato (-1 = vuoto)
var seek_target := PackedInt32Array() ## id globale del nemico da raggiungere, -1 = segui lo slot
var impact_done := PackedByteArray()

var _corpse_dirty := PackedByteArray()
# --- animazione: ultima azione di ogni soldato (attacco, tiro, colpito) e quando è iniziata
var act_kind := PackedByteArray()
var act_t := PackedFloat32Array()
var death_t := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _visual: UnitVisual
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _banner: Label3D
var _outline: MultiMeshInstance3D
var _moving_now := false
var _ran_now := false


func setup(p_battle: BattleManager, p_stats: UnitStats, p_team: int, p_id: int, p_name: String,
		at: Vector3, face: Vector3, color: Color) -> void:
	battle = p_battle
	stats = p_stats
	team = p_team
	reg_id = p_id
	display_name = p_name
	team_color = color
	name = "%s_%d" % [stats.id, reg_id]
	center = _flat(at)
	facing = _flat(face).normalized()
	move_target = center
	move_facing = facing
	count = stats.models
	alive_count = count
	cols = clampi(stats.default_cols, 1, count)
	pos.resize(count)
	vel.resize(count)
	push.resize(count)
	hp.resize(count)
	timer.resize(count)
	knock.resize(count)
	alive.resize(count)
	slot_of.resize(count)
	owner_of.resize(count)
	seek_target.resize(count)
	impact_done.resize(count)
	_corpse_dirty.resize(count)
	act_kind.resize(count)
	act_t.resize(count)
	death_t.resize(count)
	_seed.resize(count)
	for i in count:
		_seed[i] = randf()
	var first_delay := stats.reload_time if stats.is_ranged else stats.attack_interval
	for i in count:
		hp[i] = stats.hp
		alive[i] = 1
		slot_of[i] = i
		owner_of[i] = i
		seek_target[i] = -1
		timer[i] = randf() * first_delay
	for i in count:
		pos[i] = slot_world(i) + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
	hp_total = stats.hp * count
	start_hp_total = hp_total
	morale = stats.leadership
	morale_target = morale
	ammo = stats.ammo * count if stats.is_ranged else 0
	start_ammo = ammo
	_build_visuals()


# ---------------------------------------------------------------- formazione

func right_vec() -> Vector3:
	return Vector3(-facing.z, 0.0, facing.x)


func slot_world(s: int) -> Vector3:
	if on_wall and s < _wall_pos.size():
		return _wall_pos[s]
	var c := s % cols
	var r := int(float(s) / cols)
	# se restano meno soldati che colonne, la fila resta centrata (come front_width e mid)
	var off := (mini(cols, maxi(alive_count, 1)) - 1) * 0.5
	return center + right_vec() * ((c - off) * stats.spacing) - facing * (r * stats.row_spacing)


func rows() -> int:
	return int(ceil(float(maxi(alive_count, 1)) / cols))


func front_width() -> float:
	return (mini(cols, maxi(alive_count, 1)) - 1) * stats.spacing


func depth() -> float:
	return (rows() - 1) * stats.row_spacing


func mid() -> Vector3:
	return center - facing * depth() * 0.5


func bound_radius() -> float:
	var w := front_width()
	var d := depth()
	return 0.5 * sqrt(w * w + d * d) + stats.radius + 1.0


func local_of(p: Vector3) -> Vector2:
	var d := p - mid()
	return Vector2(d.dot(right_vec()), d.dot(facing))


## 0 = fronte, 1 = fianco, 2 = retro, rispetto alla scatola della formazione.
func side_of(p: Vector3) -> int:
	var l := local_of(p)
	var hw := maxf(front_width() * 0.5, 1.0) + 0.5
	var hd := maxf(depth() * 0.5, 1.0) + 0.5
	var fn := l.y / hd
	var rn := absf(l.x) / hw
	if fn >= rn:
		return 0
	if -fn >= rn:
		return 2
	return 1


func contains_point(p: Vector3, margin: float) -> bool:
	var l := local_of(p)
	return absf(l.x) <= front_width() * 0.5 + margin and absf(l.y) <= depth() * 0.5 + margin


func nearest_point_to(p: Vector3) -> Vector3:
	var l := local_of(p)
	var hw := front_width() * 0.5
	var hd := depth() * 0.5
	l.x = clampf(l.x, -hw, hw)
	l.y = clampf(l.y, -hd, hd)
	return mid() + right_vec() * l.x + facing * l.y


func set_cols(n: int) -> void:
	cols = clampi(n, 1, maxi(count, 1))
	compact()


## Riassegna gli slot ai vivi mantenendo il loro ordine: chiude i buchi.
func compact() -> void:
	var order := PackedInt32Array()
	for s in owner_of.size():
		var o := owner_of[s]
		if o >= 0 and alive[o] == 1:
			order.append(o)
	owner_of.fill(-1)
	for k in order.size():
		owner_of[k] = order[k]
		slot_of[order[k]] = k


# ---------------------------------------------------------------- ordini

func can_take_orders() -> bool:
	return is_on_field() and state != State.ROUTING


func is_on_field() -> bool:
	return alive_count > 0 and state != State.GONE


func uses_missiles() -> bool:
	return stats.is_ranged and ammo > 0


func order_move(target: Vector3, face: Vector3, run := false, new_cols := -1, wall := -1) -> void:
	if not can_take_orders():
		return
	waypoints.clear()
	_start_move(target, face, run, new_cols, wall)


## Shift + click destro: aggiunge una tappa in coda (o parte subito se è fermo).
func queue_move(target: Vector3, face: Vector3, run := false, new_cols := -1, wall := -1) -> void:
	if not can_take_orders():
		return
	if has_plan():
		waypoints.append({"pos": _flat(target), "face": face, "run": run, "cols": new_cols, "wall": wall})
	else:
		order_move(target, face, run, new_cols, wall)


## Shift + click destro su un nemico: l'attacco va in coda, dopo le tappe già date.
## Quando quel nemico muore o fugge, si prosegue con quello che c'è dopo.
func queue_attack(t: Regiment, run := false) -> void:
	if not can_take_orders() or not _can_attack(t):
		return
	if has_plan():
		waypoints.append({"attack": t, "run": run})
	else:
		order_attack(t, run)


## Ha un ordine in corso a cui accodare altre tappe?
func has_plan() -> bool:
	return state == State.MOVING or state == State.ATTACKING or state == State.FIGHTING \
			or state == State.BREACHING


## Dove si troverà il reggimento alla fine degli ordini già dati.
func planned_end() -> Vector3:
	if not waypoints.is_empty():
		return _stop_pos(waypoints.back())
	if state == State.MOVING:
		return move_target
	if (state == State.ATTACKING or state == State.FIGHTING) and attack_target != null:
		return attack_target.mid()
	return center


static func _stop_pos(w: Dictionary) -> Vector3:
	if w.has("attack"):
		var t: Regiment = w["attack"]
		return t.mid()
	return w["pos"]


func _start_move(target: Vector3, face: Vector3, run: bool, new_cols: int, wall: int) -> void:
	auto_target = false
	move_wall_side = wall if battle.fortress != null and Fortress.can_man_walls(self) else -1
	move_target = _flat(target)
	if face.length_squared() > 0.001:
		move_facing = _flat(face).normalized()
	running = run
	attack_target = null
	attack_gate = null
	if new_cols > 0 and new_cols != cols:
		if _squeezed:
			_pref_cols = new_cols
		else:
			set_cols(new_cols)
	_route_timer = 0.0
	state = State.MOVING


## Ordine attuale concluso: passa alla prossima tappa (o attacco) in coda, se c'è.
func _arrived() -> bool:
	while not waypoints.is_empty():
		var w: Dictionary = waypoints.pop_front()
		if w.has("attack"):
			var t: Regiment = w["attack"]
			if not _can_attack(t):
				continue   # già morto o in fuga: si salta
			_start_attack(t, w["run"])
			return true
		_start_move(w["pos"], w["face"], w["run"], w["cols"], w["wall"])
		return true
	state = State.IDLE
	return false


func _can_attack(t: Regiment) -> bool:
	if t == null or t.team == team or not t.is_on_field() or t.state == State.ROUTING:
		return false
	return stats.is_ranged or not t.on_wall   # sulle mura si arriva solo col tiro


func order_attack(t: Regiment, run := false) -> void:
	if not can_take_orders() or t == null or t.team == team:
		return
	if t.on_wall and not stats.is_ranged:
		return   # sulle mura non si sale dall'esterno: solo il tiro li raggiunge
	waypoints.clear()
	_start_attack(t, run)


func _start_attack(t: Regiment, run: bool) -> void:
	auto_target = false
	attack_target = t
	attack_gate = null
	running = run
	_route_timer = 0.0
	if state != State.FIGHTING:
		state = State.ATTACKING


## Assedio: abbatti una porta. La formazione si stringe alla larghezza della porta.
func order_breach(g: Fortress.Gate) -> void:
	if not can_take_orders() or g == null or g.destroyed or not g.breakable:
		return
	auto_target = false
	attack_gate = g
	attack_target = null
	running = false
	_route_timer = 0.0
	if not stats.is_artillery:
		_squeeze_for(g)
	if state != State.FIGHTING:
		state = State.BREACHING


## Artiglieria che bombarda una porta ed è già abbastanza vicina per tirare.
func bombarding_gate() -> Fortress.Gate:
	if stats.is_artillery and state == State.BREACHING and attack_gate != null and not attack_gate.destroyed:
		if _flat(attack_gate.center - mid()).length() <= missile_range():
			return attack_gate
	return null


func on_gate_destroyed(g: Fortress.Gate) -> void:
	_route_timer = 0.0
	if attack_gate == g:
		attack_gate = null
		if state == State.BREACHING:
			_lose_target()


func order_halt() -> void:
	if not can_take_orders():
		return
	auto_target = false
	waypoints.clear()
	attack_target = null
	attack_gate = null
	running = false
	move_target = center
	move_facing = facing
	if state != State.FIGHTING:
		state = State.IDLE


## Usato nello schieramento: sposta il reggimento all'istante.
func teleport(p: Vector3, face: Vector3, new_cols := -1) -> void:
	leave_wall_instant()
	center = _flat(p)
	if face.length_squared() > 0.001:
		facing = _flat(face).normalized()
	move_target = center
	move_facing = facing
	if new_cols > 0:
		set_cols(new_cols)
	for i in count:
		if alive[i] == 1:
			pos[i] = slot_world(slot_of[i])
			vel[i] = Vector3.ZERO


func missile_target() -> Regiment:
	if state == State.ATTACKING and attack_target != null and attack_target.is_on_field():
		return attack_target
	if state == State.IDLE:
		return battle.nearest_enemy(self, missile_range())
	return null


## Gittata attuale: dalle mura si tira più lontano.
func missile_range() -> float:
	return stats.missile_range * (Fortress.WALL_RANGE_BONUS if on_wall else 1.0)


func is_moving() -> bool:
	return _moving_now


func base_y() -> float:
	return _base_y


# ---------------------------------------------------------------- mura

## Sulle mura i soldati non stanno in un rettangolo: si dispongono lungo il camminamento, su due
## file, attorno al punto p, e se il lato non basta girano l'angolo sui lati vicini.
func _place_on_wall(side: int, p: Vector3) -> void:
	var f := battle.fortress
	var res := f.wall_slots(side, p, count, stats.spacing)
	_wall_pos = res["pos"]
	_wall_face = res["face"]
	wall_side = side
	facing = f.wall_normal(side)
	move_facing = facing
	# centro = media dei posti più vicini (quelli occupati dai vivi)
	var c := Vector3.ZERO
	var k := mini(maxi(alive_count, 1), _wall_pos.size())
	for i in k:
		c += _wall_pos[i]
	center = _flat(c / maxf(k, 1)) + facing * depth() * 0.5
	move_target = center


## Schieramento: direttamente sul camminamento.
func teleport_to_wall(side: int, p: Vector3) -> void:
	var f := battle.fortress
	if f == null or not Fortress.can_man_walls(self):
		return
	if not on_wall:
		_ground_cols = cols
	on_wall = true
	wall_side = side
	set_cols(f.wall_cols_for(self, side))
	_place_on_wall(side, p)
	_base_y = Fortress.WALK_Y
	_climb = 0.0
	for i in count:
		if alive[i] == 1:
			pos[i] = slot_world(slot_of[i])
			vel[i] = Vector3.ZERO


## Schieramento a terra di un reggimento che era sulle mura.
func leave_wall_instant() -> void:
	if on_wall:
		on_wall = false
		wall_side = -1
		_base_y = 0.0
		if _ground_cols > 0:
			set_cols(_ground_cols)


func _climb_onto(side: int) -> void:
	var f := battle.fortress
	_ground_cols = cols
	on_wall = true
	wall_side = side
	set_cols(f.wall_cols_for(self, side))
	_place_on_wall(side, move_target if move_wall_side == side else center)
	for i in count:
		if alive[i] == 1:
			pos[i] = slot_world(slot_of[i])
			vel[i] = Vector3.ZERO
	_animate_y(Fortress.WALK_Y, 3.0)   # le scale richiedono qualche secondo


func _descend() -> void:
	var f := battle.fortress
	var side := wall_side
	on_wall = false
	wall_side = -1
	center = f.wall_foot(side, center)
	facing = -f.wall_normal(side)
	if _ground_cols > 0:
		set_cols(_ground_cols)
	for i in count:
		if alive[i] == 1:
			pos[i] = Fortress.push_out_of(slot_world(slot_of[i]), stats.radius, f.solids_for(team))
			vel[i] = Vector3.ZERO
	_animate_y(0.0, 2.0)
	_route_timer = 0.0


func _animate_y(to: float, seconds: float) -> void:
	_y_from = _base_y
	_y_to = to
	_climb = seconds
	_climb_total = seconds


## Tutto ciò che fa un reggimento che sta sulle mura. Restituisce false se deve scendere.
func _update_on_wall(dt: float) -> bool:
	var f := battle.fortress
	var nrm := f.wall_normal(wall_side)
	if state == State.MOVING and move_wall_side >= 0 and f.walkway_connected(wall_side, move_wall_side):
		# spostamento lungo il camminamento (anche su un altro lato della stessa cinta):
		# i nuovi posti si calcolano subito e ogni soldato ci cammina
		_place_on_wall(move_wall_side, move_target)
		_arrived()
		return true
	if state == State.IDLE or (state == State.ATTACKING and uses_missiles()):
		facing = _turn(facing, nrm, stats.turn_rate * dt)
		return true
	return false


func resume_after_fight() -> void:
	if attack_gate != null and not attack_gate.destroyed:
		state = State.BREACHING
	elif attack_target != null and attack_target.is_on_field():
		state = State.ATTACKING
	else:
		_lose_target()


func _lose_target() -> void:
	auto_target = false
	attack_target = null
	attack_gate = null
	running = false
	move_target = center
	move_facing = facing
	state = State.IDLE
	if not waypoints.is_empty():
		_arrived()   # bersaglio eliminato o porta abbattuta: si prosegue con le tappe


# ---------------------------------------------------------------- danni e morale

## melee = true: conta per "vince/perde lo scontro"; il tiro dà solo il malus "sotto tiro".
func take_damage(j: int, dmg: float, attacker: Regiment, melee := false) -> void:
	if alive[j] == 0 or dmg <= 0.0:
		return
	var real := minf(dmg, hp[j])
	hp[j] -= dmg
	hp_total -= real
	if melee:
		taken_melee += real
		recent_taken += real
		if attacker != null:
			attacker.recent_dealt += real
	else:
		taken_missile += real
		under_fire_timer = 4.0
	if attacker != null and AUTO_RETALIATE:
		_maybe_retaliate(attacker, melee)
	if hp[j] <= 0.0:
		_kill(j)
		if attacker != null:
			attacker.kills += 1
			killed_by[attacker.display_name] = int(killed_by.get(attacker.display_name, 0)) + 1


## Risposta automatica: un reparto fermo e senza ordini che viene attaccato reagisce da solo.
## In mischia si gira e affronta chi lo attacca con tutto il reparto; sotto tiro, chi ha
## frecce o colpi risponde al fuoco se il tiratore è a portata. La fanteria sotto tiro resta
## ferma (non insegue gli arcieri), l'artiglieria non si sposta, chi è sulle mura non scende.
## Un ordine del giocatore annulla sempre la risposta automatica.
func _maybe_retaliate(attacker: Regiment, melee: bool) -> void:
	if attacker.team == team or not attacker.is_on_field() or attacker.state == State.ROUTING:
		return
	if not can_take_orders() or not waypoints.is_empty():
		return
	# fermo, oppure già in mischia senza un bersaglio (il contatto l'ha trascinato nello scontro)
	var free := state == State.IDLE or (state == State.FIGHTING and attack_target == null and attack_gate == null)
	if not free:
		return
	if stats.is_artillery and melee:
		return   # i serventi si difendono dove sono
	if melee:
		if attacker.on_wall and not stats.is_ranged:
			return
		_auto_attack(attacker, true)
	elif uses_missiles():
		var d := _flat(attacker.mid() - mid()).length()
		if d <= missile_range() and d >= stats.min_range:
			_auto_attack(attacker, false)


func _auto_attack(t: Regiment, run: bool) -> void:
	_start_attack(t, run)
	auto_target = true
	_auto_home = center


func apply_knock(j: int, v: Vector3, t: float) -> void:
	if alive[j] == 1:
		knock[j] = t
		vel[j] = v
		mark_action(j, UnitVisual.HIT)


## Il soldato i ha appena attaccato, tirato o è stato colpito: parte quell'animazione.
func mark_action(i: int, kind: int) -> void:
	act_kind[i] = kind
	act_t[i] = battle.anim_time


func _kill(i: int) -> void:
	death_t[i] = battle.anim_time
	alive[i] = 0
	hp[i] = 0.0
	alive_count -= 1
	_corpse_dirty[i] = 1
	# il soldato dietro avanza a prendere il posto di chi è caduto
	var cur := slot_of[i]
	var nxt := cur + cols
	while nxt < owner_of.size() and owner_of[nxt] >= 0:
		var s := owner_of[nxt]
		owner_of[cur] = s
		slot_of[s] = cur
		cur = nxt
		nxt += cols
	owner_of[cur] = -1
	slot_of[i] = -1
	if cur < cols:
		compact()
	if alive_count <= 0:
		state = State.GONE
		in_melee = false


func start_rout() -> void:
	if state == State.ROUTING or not is_on_field():
		return
	rout_count += 1
	if rout_count > MAX_RALLIES:
		shattered = true
	state = State.ROUTING
	attack_target = null
	attack_gate = null
	waypoints.clear()
	running = true
	calm_timer = 0.0
	morale = 0.0
	_route_timer = 0.0


func shatter() -> void:
	shattered = true
	if is_on_field() and state != State.ROUTING:
		start_rout()


func rally() -> void:
	state = State.IDLE
	morale = 35.0
	calm_timer = 0.0
	running = false
	facing = Vector3(0.0, 0.0, -battle.flee_dir(team))
	move_target = center
	move_facing = facing


func eff_ma() -> float:
	var m := stats.melee_attack * fatigue_mult()
	if morale < 25.0:
		m *= 0.8
	elif morale < 50.0:
		m *= 0.9
	return m


func eff_md() -> float:
	var m := stats.melee_defense * fatigue_mult()
	if morale < 25.0:
		m *= 0.8
	return m


func morale_label() -> String:
	if state == State.ROUTING:
		return "Spezzato" if shattered else "In rotta"
	if morale > 75.0:
		return "Ardito"
	if morale >= 50.0:
		return "Saldo"
	if morale >= 25.0:
		return "Esitante"
	return "Vacillante"


func fatigue_level() -> int:
	return mini(5, int(fatigue / 17.0))


func fatigue_mult() -> float:
	return 1.0 - 0.04 * fatigue_level()


func strength() -> float:
	var off := stats.melee_attack + stats.melee_defense + stats.damage_base + stats.damage_ap
	if stats.is_ranged and ammo > 0:
		off += stats.missile_damage * 2.0
	return hp_total * off / 100.0


func random_alive() -> int:
	if alive_count <= 0:
		return -1
	for k in 8:
		var i := randi() % count
		if alive[i] == 1:
			return i
	for i in count:
		if alive[i] == 1:
			return i
	return -1


# ---------------------------------------------------------------- simulazione

func sim_update(dt: float) -> void:
	if state == State.GONE or alive_count <= 0:
		return
	charge_timer = maxf(0.0, charge_timer - dt)
	flank_timer = maxf(0.0, flank_timer - dt)
	rear_timer = maxf(0.0, rear_timer - dt)
	fear_timer = maxf(0.0, fear_timer - dt)
	under_fire_timer = maxf(0.0, under_fire_timer - dt)
	if _climb > 0.0:
		# salita o discesa in corso: si resta fermi finché non è finita
		_climb = maxf(0.0, _climb - dt)
		_base_y = lerpf(_y_to, _y_from, _climb / _climb_total)
		_update_soldiers(dt)
		return
	_update_center(dt)
	_update_fatigue(dt)
	_update_soldiers(dt)


func _update_center(dt: float) -> void:
	_moving_now = false
	_ran_now = false
	var fat := fatigue_mult()
	var walk := stats.speed * 0.5 * fat
	var run := stats.speed * fat
	var dest := center
	var want := false
	var spd := walk
	var face_to := Vector3.ZERO
	var final := center
	if on_wall:
		if _update_on_wall(dt):
			return
		_descend()   # qualsiasi altro ordine: prima si scende
		return
	match state:
		State.MOVING:
			final = move_target
			want = true
			spd = run if running else walk
			if move_wall_side >= 0:
				# destinazione sulle mura: si va ai piedi delle scale e si sale
				final = battle.fortress.wall_foot(move_wall_side, move_target)
				if _flat(final - center).length() < 2.5:
					_climb_onto(move_wall_side)
					return
		State.ATTACKING:
			if attack_target == null or not attack_target.is_on_field():
				_lose_target()
			elif auto_target and (attack_target.state == State.ROUTING
					or _flat(attack_target.mid() - _auto_home).length() > AUTO_CHASE):
				_lose_target()   # risposta automatica: non si inseguono i fuggiaschi né chi si allontana
			else:
				var tm := attack_target.mid()
				var d := _flat(tm - mid()).length()
				if uses_missiles():
					if d > missile_range() * 0.9:
						final = tm
						want = true
					else:
						face_to = _flat(tm - center)
				else:
					final = attack_target.nearest_point_to(center)
					want = true
					spd = run if (running or d < 30.0) else walk
		State.ROUTING:
			final = Vector3(center.x, 0.0, battle.flee_z(team))
			want = true
			spd = stats.speed * 1.05
		State.BREACHING:
			if attack_gate == null or attack_gate.destroyed:
				_lose_target()
			elif stats.is_artillery:
				# artiglieria: si avvicina finché la porta è a tiro, poi si ferma e la bombarda
				var gc := attack_gate.center
				if _flat(gc - mid()).length() > missile_range() * 0.85:
					final = attack_gate.outside_point(minf(missile_range() * 0.6, 140.0))
					want = true
				else:
					face_to = _flat(gc - center)
			else:
				# la prima fila si piazza a 1,5 m dalla porta, rivolta verso di essa
				final = attack_gate.outside_point(Fortress.WALL_T * 0.5 + 1.5)
				var gd := _flat(final - center).length()
				if gd > 1.5:
					want = true
					spd = run if gd > 12.0 else walk   # di corsa sotto le mura, poi in ordine
				else:
					face_to = -attack_gate.normal
		State.IDLE:
			face_to = move_facing
	if want:
		dest = _nav(final, dt)
		var to := _flat(dest - center)
		var d := to.length()
		if d > 1.0:
			var dir := to / d
			facing = _turn(facing, dir, stats.turn_rate * dt)
			var align := maxf(0.2, facing.dot(dir))
			var step := minf(spd * align * dt, d)
			center += (facing + dir).normalized() * step
			_moving_now = true
			_ran_now = spd >= run * 0.99
			if state == State.ATTACKING and _ran_now and facing.dot(dir) > 0.97:
				charge_dist += step
			else:
				charge_dist = 0.0
		else:
			if state == State.MOVING and move_wall_side < 0:
				_arrived()
			charge_dist = 0.0
		if state == State.ROUTING and absf(center.z) >= BattleManager.EDGE - 3.0:
			_leave_field()
	else:
		charge_dist = 0.0
		if face_to.length_squared() > 0.0001:
			facing = _turn(facing, face_to.normalized(), stats.turn_rate * dt)
	if battle.fortress != null:
		center = Fortress.push_out_of(center, 0.6, battle.fortress.solids_near(center, 3.0, team))
		_update_squeeze()


## Prossima tappa verso `final`, passando dalle porte se serve (solo in assedio).
func _nav(final: Vector3, dt: float) -> Vector3:
	var f := battle.fortress
	if f == null:
		return final
	_route_timer -= dt
	if _route.is_empty() or _route_timer <= 0.0 or _flat(_route_final - final).length() > 4.0:
		_route = f.route(center, final, team)
		_route_final = final
		_route_timer = 1.0
		_route_gate = f.last_route_gate if _route.size() > 1 else null
	while _route.size() > 1 and _flat(_route[0] - center).length() < 2.5:
		_route.remove_at(0)
	if _route_gate != null and center.distance_to(_route_gate.center) < 30.0:
		_squeeze_for(_route_gate)
	return _route[0]


## Stringe la formazione per passare da una porta (o per assaltarla).
func _squeeze_for(g: Fortress.Gate) -> void:
	var narrow := maxi(2, int(g.width / stats.spacing))
	if _squeezed:
		_squeeze_at = g.center
		return
	if narrow >= cols:
		return
	_squeezed = true
	_squeeze_at = g.center
	_pref_cols = cols
	set_cols(narrow)


func _update_squeeze() -> void:
	if not _squeezed or state == State.BREACHING:
		return
	var away := _flat(center - _squeeze_at).length() > depth() + 8.0
	if away or state == State.IDLE or state == State.FIGHTING:
		_squeezed = false
		set_cols(_pref_cols)


func _update_fatigue(dt: float) -> void:
	var rate := -2.0
	if in_melee:
		rate = 1.5
	elif _moving_now:
		rate = 3.0 if _ran_now else 0.2
	fatigue = clampf(fatigue + rate * dt, 0.0, 100.0)


func _update_soldiers(dt: float) -> void:
	var max_spd := stats.speed * fatigue_mult()
	var routing := state == State.ROUTING
	var flee := Vector3(0.0, 0.0, battle.flee_dir(team))
	var blend := minf(1.0, dt * 6.0)
	var walls: Array[Rect2] = []
	var breach_gate: Fortress.Gate = attack_gate if state == State.BREACHING else null
	if battle.fortress != null and not on_wall:
		walls = battle.fortress.solids_near(mid(), bound_radius() + 8.0, team)
	for i in count:
		if alive[i] == 0:
			continue
		var p := pos[i]
		if knock[i] > 0.0:
			knock[i] -= dt
			var kv := vel[i] * maxf(0.0, 1.0 - 3.0 * dt)
			vel[i] = kv
			pos[i] = p + (kv + push[i]) * dt
			if not walls.is_empty():
				pos[i] = Fortress.push_out_of(pos[i], stats.radius, walls)
			continue
		var goal: Vector3
		var cap := max_spd * 1.2
		var stop := 0.0
		var tg := seek_target[i]
		if routing and battle.fortress == null:
			goal = p + flee * 10.0 + Vector3(sin(i * 1.7) * 2.0, 0.0, 0.0)
			cap = max_spd * 1.05
		elif routing:
			# in assedio la fuga segue il centro, che passa dalle porte
			goal = slot_world(slot_of[i])
			cap = max_spd * 1.25
		elif tg >= 0:
			var o: Regiment = battle.regiments[tg >> 12]
			goal = o.pos[tg & 4095]
			stop = 0.8 + stats.radius + o.stats.radius
			cap = max_spd * 0.5
		else:
			goal = slot_world(slot_of[i])
			if breach_gate != null:
				# chi è vicino alla porta ci si accalca contro per colpirla
				var q := Vector3(clampf(p.x, breach_gate.rect.position.x, breach_gate.rect.end.x), 0.0,
						clampf(p.z, breach_gate.rect.position.y, breach_gate.rect.end.y))
				if _flat(q - p).length() < 7.0:
					goal = q + breach_gate.normal * (stats.radius + 0.2)
					cap = max_spd * 0.6
		var to := goal - p
		to.y = 0.0
		var d := to.length()
		var desired := Vector3.ZERO
		if d > stop + 0.05:
			desired = to / d * minf((d - stop) * 2.5, cap)
		var nv := vel[i].lerp(desired, blend)
		vel[i] = nv
		var np := p + (nv + push[i]) * dt
		if not walls.is_empty():
			np = Fortress.push_out_of(np, stats.radius, walls)
		pos[i] = np


func _leave_field() -> void:
	fled = true
	state = State.GONE
	in_melee = false
	# nascondi i vivi, lascia i caduti sul campo
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in count:
		if alive[i] == 1:
			_mm.set_instance_transform(i, hidden)
	_banner.visible = false


# ---------------------------------------------------------------- grafica

func _build_visuals() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	# dati per soldato letti dallo shader: vivo/caduto, stato, inizio dello stato, numero casuale
	_mm.use_custom_data = true
	_visual = battle.get_visual(stats)
	_mm.mesh = _visual.mesh
	_mm.instance_count = count
	for i in count:
		_mm.set_instance_custom_data(i, Color(1, 0, 0, _seed[i]))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = battle.get_unit_material(stats)
	add_child(_mmi)
	# l'outline riusa lo stesso MultiMesh con un materiale diverso: nessun costo extra di dati
	_outline = MultiMeshInstance3D.new()
	_outline.multimesh = _mm
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.visible = false
	add_child(_outline)
	_banner = Label3D.new()
	_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_banner.no_depth_test = true
	_banner.fixed_size = true
	_banner.pixel_size = 0.0011
	_banner.font_size = 30
	_banner.outline_size = 12
	_banner.modulate = team_color.lightened(0.35)
	_banner.render_priority = 10
	add_child(_banner)
	update_visuals()


func set_outline(on: bool, col := OUTLINE_ENEMY) -> void:
	if _outline == null:
		return
	_outline.visible = on and not fled
	hovered = on
	if on:
		_outline.material_override = battle.get_outline_material(col, stats)
	_banner.modulate = team_color.lightened(0.7) if on else team_color.lightened(0.35)


func banner_text() -> String:
	var s := display_name
	if state == State.ROUTING or morale < 50.0:
		s += "\n" + morale_label().to_upper()
	return s


func update_visuals() -> void:
	if fled:
		return
	var base := team_color * stats.tint
	if selected:
		base = base.lightened(0.45)
	elif hovered:
		base = base.lightened(0.2)
	if state == State.ROUTING:
		base = base.lerp(Color(0.92, 0.92, 0.85), 0.55)
	var now := battle.anim_time
	var run_sq := pow(stats.speed * 0.62, 2.0)
	var walk_sq := 0.35 * 0.35
	var routing := state == State.ROUTING
	for i in count:
		if alive[i] == 0:
			if _corpse_dirty[i] == 1:
				# il caduto resta dov'era e lo shader lo fa cadere (animazione di morte)
				_corpse_dirty[i] = 0
				var pc := pos[i]
				var fc := vel[i] if vel[i].length_squared() > 0.3 else facing
				var bc := Basis(Vector3.UP, atan2(-fc.x, -fc.z))
				_mm.set_instance_transform(i, Transform3D(bc, Vector3(pc.x, _base_y, pc.z)))
				_mm.set_instance_color(i, base.darkened(0.65))
				_mm.set_instance_custom_data(i, Color(0, UnitVisual.DEATH, death_t[i], _seed[i]))
			continue
		var p := pos[i]
		var v := vel[i]
		var f := facing
		if on_wall and slot_of[i] < _wall_face.size():
			f = _wall_face[slot_of[i]]   # sulle mura ognuno guarda fuori dal proprio lato
		var sp := v.length_squared()
		if sp > 0.3:
			f = v
		var b := Basis(Vector3.UP, atan2(-f.x, -f.z))
		_mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, _base_y, p.z)))
		_mm.set_instance_color(i, base)
		# stato dell'animazione: azione in corso (colpito, attacco, tiro), altrimenti il passo
		var st := UnitVisual.IDLE
		var t0 := 0.0
		var k := act_kind[i]
		if k != 0 and (k == UnitVisual.HIT and knock[i] > 0.0 or now - act_t[i] < _visual.duration_of(k)):
			st = k
			t0 = act_t[i]
		elif routing or sp > run_sq:
			st = UnitVisual.RUN
		elif sp > walk_sq or _moving_now:
			st = UnitVisual.WALK
		_mm.set_instance_custom_data(i, Color(1, st, t0, _seed[i]))
	_banner.position = mid() + Vector3(0.0, _base_y + stats.model_height + 3.0, 0.0)
	var t := banner_text()
	if _banner.text != t:
		_banner.text = t
	_banner.outline_modulate = Color(1, 1, 1, 0.9) if selected else Color(0, 0, 0, 0.8)


# ---------------------------------------------------------------- utilità

static func _turn(a: Vector3, b: Vector3, max_ang: float) -> Vector3:
	var ang := clampf(a.signed_angle_to(b, Vector3.UP), -max_ang, max_ang)
	return a.rotated(Vector3.UP, ang).normalized()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
