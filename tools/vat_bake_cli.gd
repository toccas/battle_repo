extends SceneTree
## Cottura VAT da riga di comando (vedi tools/vat_baker.gd).
##   godot --headless --path . --script res://tools/vat_bake_cli.gd -- --src=res://percorso/Modello.gltf \
##       [--unit=res://data/units/troll.tres] [--out=res://data/visuals] [--height=0] [--fps=20]
##       [--preset=auto] [--no-turn] [--idle=Idle --walk=Walk ... per scegliere a mano]
## --src può essere anche una cartella: si cuociono tutti i .glb/.gltf che contiene.

var _done := false


## La cottura parte al primo fotogramma, quando l'albero della scena è pronto.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_bake()
	return false


func _bake() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if not args.has("src"):
		print("Uso: --src=res://.../Modello.gltf [--unit=res://data/units/nome.tres] (vedi tools/vat_bake_cli.gd)")
		quit(1)
		return
	var mapping := {}
	for st in ["idle", "walk", "run", "attack", "shoot", "hit", "death"]:
		mapping[st] = args.get(st, "")
	var baker: GDScript = load("res://tools/vat_baker.gd")
	var src: String = args["src"]
	var files := PackedStringArray()
	if DirAccess.dir_exists_absolute(src):
		for f in DirAccess.get_files_at(src):
			if f.get_extension().to_lower() in ["glb", "gltf"]:
				files.append(src.path_join(f))
	else:
		files.append(src)
	var unit: UnitStats = load(args["unit"]) if args.has("unit") and files.size() == 1 else null
	var ok := true
	for f in files:
		var res: Dictionary = baker.bake_model(f, mapping, args.get("out", "res://data/visuals"),
				float(args.get("height", "0")), not args.has("no-turn"), float(args.get("fps", "20")),
				args.get("preset", "auto"), unit, self)
		print(res.get("message", ""))
		ok = ok and res.get("ok", false)
	quit(0 if ok else 1)
