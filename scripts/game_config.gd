extends Node
## Autoload "GameConfig": le scelte fatte nella scena di preparazione, lette dalla battaglia.
## Se si avvia direttamente main.tscn valgono i valori di default.

const UNIT_IDS := ["spearmen", "swordsmen", "archers", "knights", "troll", "catapult", "cannon"]
const MAX_ARTILLERY := 2                 ## negli eserciti generati a caso
const DEFAULT_FORTRESS := "res://data/fortezze/classica.json"
const MAX_REGIMENTS := 20                ## generale escluso
const SIEGE_ATTACKER_BONUS := 1.3        ## chi assedia ha più punti: i difensori hanno le mura
const DEFAULT_PLAYER := ["general", "spearmen", "swordsmen", "swordsmen", "spearmen",
		"archers", "archers", "knights", "knights"]
const DEFAULT_ENEMY := ["general", "spearmen", "swordsmen", "troll", "swordsmen", "spearmen",
		"archers", "archers", "knights"]

var mode := "field"            ## "field" = battaglia campale, "siege" = assedio
var player_attacks := true     ## solo assedio: il giocatore attacca (true) o difende (false)
var budget := 5000
var fortress_path := DEFAULT_FORTRESS    ## fortezza scelta nella preparazione
var fortress_override := {}              ## pianta non salvata (prova dall'editor): ha la precedenza
var return_to_editor := false            ## a fine prova si torna all'editor invece che alla preparazione
var editor_path := ""                    ## file aperto nell'editor prima della prova
var editor_dirty := false                ## modifiche non salvate nell'editor prima della prova
var player_army: Array[String] = []
var enemy_army: Array[String] = []

var _stats := {}


func _init() -> void:
	player_army.assign(DEFAULT_PLAYER)
	enemy_army.assign(DEFAULT_ENEMY)


## La pianta della fortezza da usare in assedio.
func fortress_layout() -> FortressLayout:
	var d := fortress_override
	if d.is_empty():
		d = FortressLayout.load_file(fortress_path)
	if d.is_empty():
		d = FortressLayout.classic_data()
	return FortressLayout.from_data(d)


func fortress_name() -> String:
	if not fortress_override.is_empty():
		return str(fortress_override.get("name", "Senza nome"))
	return str(FortressLayout.load_file(fortress_path).get("name", "Classica"))


func is_siege() -> bool:
	return mode == "siege"


func stats(id: String) -> UnitStats:
	if not _stats.has(id):
		_stats[id] = load("res://data/units/%s.tres" % id)
	return _stats[id]


func army_cost(ids: Array[String]) -> int:
	var c := 0
	for id in ids:
		c += stats(id).cost
	return c


## Budget per una delle due parti: in assedio l'attaccante ne riceve di più.
func budget_for(is_player: bool) -> int:
	if not is_siege():
		return budget
	var attacker := player_attacks if is_player else not player_attacks
	return int(budget * SIEGE_ATTACKER_BONUS) if attacker else budget


## Esercito casuale ma sensato per il budget dato: almeno metà fanteria, qualche tiratore.
func random_army(points: int) -> Array[String]:
	var out: Array[String] = ["general"]
	var weights := {"spearmen": 3.0, "swordsmen": 3.0, "archers": 2.2, "knights": 1.4, "troll": 1.0,
			"catapult": 0.7, "cannon": 0.6}
	var left := points
	while out.size() - 1 < MAX_REGIMENTS:
		var infantry := out.count("spearmen") + out.count("swordsmen")
		var options: Array[String] = []
		var total := 0.0
		for id: String in weights:
			if stats(id).cost > left:
				continue
			if stats(id).is_artillery and out.count("catapult") + out.count("cannon") >= MAX_ARTILLERY:
				continue
			# finché la fanteria è meno della metà, si scelgono solo fanti
			if infantry < (out.size() - 1) * 0.5 and id != "spearmen" and id != "swordsmen" and out.size() > 1:
				continue
			options.append(id)
			total += weights[id]
		if options.is_empty():
			break
		var roll := randf() * total
		for id in options:
			roll -= weights[id]
			if roll <= 0.0:
				out.append(id)
				left -= stats(id).cost
				break
	return out
