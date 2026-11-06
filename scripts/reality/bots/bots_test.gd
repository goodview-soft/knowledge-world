extends SceneTree

func _init() -> void:
	var fails := 0
	var defs := BotDirector.load_defs()
	fails += _chk(defs.size() == 12, "12 bots chargés")
	var dir := BotDirector.new()
	dir.dialogue.force_fallback = true
	var brains := dir.load_brains()
	var a: BotBrain = brains[4]  # Basile
	var b: BotBrain = brains[1]  # Léo
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# conversation de repli
	var lines: Array = []
	dir.dialogue.say(a, b.bot_name, "", func(t: String) -> void: lines.append(t))
	dir.dialogue.say(b, a.bot_name, lines[0], func(t: String) -> void: lines.append(t))
	fails += _chk(lines.size() == 2 and lines[0] != "" and lines[1] != "", "conversation de repli")
	fails += _chk(a.memory.size() >= 1, "mémoire courte")
	# ragot
	var fact := "Un voyageur étrange est arrivé en ville."
	fails += _chk(a.knows(fact) and not b.knows(fact), "A connaît, B non")
	var g := BotBrain.exchange_gossip(a, b, rng, true)
	fails += _chk(b.knows(fact) and b.facts.back()["source"] != "" or g.size() > 0, "ragot transmis")
	var src := ""
	for f in b.facts:
		if f["text"] == fact:
			src = f["source"]
	fails += _chk(src == "Basile", "source = Basile")
	var reply: Array = [""]
	dir.dialogue.answer_player(b, "Qu'as-tu entendu ?", func(t: String) -> void: reply[0] = t)
	fails += _chk(reply[0].contains("Basile"), "réponse joueur (entendu)")
	reply[0] = ""
	dir.dialogue.answer_player(b, "Bonjour !", func(t: String) -> void: reply[0] = t)
	fails += _chk(reply[0] != "", "réponse joueur générique")
	# sauvegarde
	var d := dir.to_dict()
	var dir2 := BotDirector.new()
	dir2.from_dict(JSON.parse_string(JSON.stringify(d)))
	fails += _chk(dir2.brain_of("Léo").knows(fact), "to_dict/from_dict")
	fails += _level2(dir)
	print("BOTS TEST OK" if fails == 0 else "BOTS TEST FAIL %d" % fails)
	quit(fails)

func _chk(c: bool, msg: String) -> int:
	if not c:
		print("ECHEC: ", msg)
	return 0 if c else 1


func _level2(dir: BotDirector) -> int:
	var fails := 0
	var city := CityBuilder.new()
	root.add_child(city)
	city.build(CityBuilder.load_config())
	dir.setup(city)
	# foyers et travail
	var ok := dir.brains.size() == 12
	for b in dir.brains:
		var pl: Dictionary = city.places.get(b.work_id, {})
		if b.home.is_empty() or int(b.home["node"]) < 0 or pl.is_empty() or str(b.home["address"]) == "" or b.full_name() == b.bot_name:
			ok = false
	fails += _chk(ok, "12 bots : foyer, travail et identité valides")
	var ok_apt := true
	for b in dir.brains:
		var plan: Dictionary = city.buildings[int(b.home["building"])]["plan"]
		var aid: String = str(b.home.get("apartment_id", ""))
		if not plan["apartments"].has(aid) or not (plan["apartments"][aid]["occupants"] as Array).has(b.bot_name) or int(plan["apartments"][aid]["floor"]) != int(b.home["floor"]):
			ok_apt = false
	fails += _chk(ok_apt, "foyers : apartment_id valide, occupant référencé dans l'appartement")
	# chemin entre deux portes
	var pa: Array = city.graph.find_path(int(dir.brains[0].home["node"]), int(dir.brains[7].home["node"]))
	fails += _chk(pa.size() >= 2, "chemin entre deux portes (%d points)" % pa.size())
	# emploi du temps : 9 h jour 1 -> travail
	var marta: BotBrain = dir.brains[0]
	marta.node = int(marta.home["node"])
	marta.pos = city.graph.pos(marta.node)
	marta.path = []
	marta.key = ""
	dir.clock.set_time(1, 9.0)
	dir.sim(0.6)
	var wnode := int(city.places[marta.work_id]["door"])
	fails += _chk(marta.kind == "work" and (marta.is_moving() or marta.node == wnode), "9 h : travail en route ou sur place")
	for i in 400:
		dir.sim(1.0)
	fails += _chk(marta.node == wnode and not marta.is_moving(), "arrivée au travail")
	# nuit : chez soi, caché
	dir.clock.set_time(1, 23.0)
	dir.clock.day_length = 6000.0
	for i in 1200:
		dir.sim(0.5)
	fails += _chk(marta.kind == "home" and marta.hidden, "nuit : chez soi (caché)")
	# affinité modifiée par une rencontre
	var bas: BotBrain = dir.brain_of("Basile")
	var leo: BotBrain = dir.brain_of("Léo")
	var before := bas.aff("Léo")
	dir.silent_meet(bas, leo)
	fails += _chk(not is_equal_approx(bas.aff("Léo"), before) and is_equal_approx(bas.aff("Léo"), leo.aff("Basile")), "affinité modifiée après rencontre")
	fails += _chk(dir.brain_of("Gustave").aff("Basile") < 0.0 and dir.brain_of("Gustave").aff("Odette") > 0.0, "tensions et amitiés initiales")
	# événement -> fait
	var cam: BotBrain = dir.brain_of("Camille")
	var fact := "Il y a une fête au café ce soir."
	dir.announced.clear()
	dir.clock.set_time(3, 15.0)
	dir.tick_events()
	fails += _chk(cam.knows(fact), "événement annoncé -> fait connu")
	dir.clock.set_time(4, 2.0)
	dir.announced.clear()
	dir.clock.set_time(6, 2.0)
	dir.tick_events()
	fails += _chk(dir.blackout, "panne de lampadaires la nuit")
	# réponses concrètes + mémoire du joueur
	var r: Array = [""]
	dir.dialogue.answer_player(cam, "Où habites-tu ?", func(t: String) -> void: r[0] = t)
	fails += _chk(r[0].contains(str(cam.home["address"])), "où habites-tu : " + r[0])
	cam.path = []
	dir.dialogue.answer_player(cam, "Où vas-tu ?", func(t: String) -> void: r[0] = t)
	fails += _chk(r[0].begins_with("Je "), "où vas-tu : " + r[0])
	dir.dialogue.answer_player(cam, "Où est Léo ?", func(t: String) -> void: r[0] = t)
	fails += _chk(r[0].contains("Léo"), "où est Léo : " + r[0])
	dir.dialogue.answer_player(cam, "Je cherche un cadeau pour ma soeur.", func(t: String) -> void: r[0] = t)
	fails += _chk(cam.player_memory.size() == 1, "mémoire du joueur")
	for i in 8:
		BotBrain.exchange_gossip(cam, leo, dir.rng, true)
	var heard := false
	for f in leo.facts:
		if str(f["text"]).contains("cadeau") and str(f["source"]) == "Camille":
			heard = true
	fails += _chk(heard, "ragot : le voyageur a dit... (transmis)")
	fails += _level3()
	# sauvegarde / rechargement
	var d: Dictionary = JSON.parse_string(JSON.stringify(dir.to_dict()))
	var dir2 := BotDirector.new()
	dir2.load_brains()
	dir2.setup(city)
	dir2.from_dict(d)
	var c2 := dir2.brain_of("Camille")
	fails += _chk(dir2.clock.day == dir.clock.day and absf(dir2.clock.minutes - dir.clock.minutes) < 0.01, "sauvegarde : horloge")
	fails += _chk(is_equal_approx(dir2.brain_of("Basile").aff("Léo"), bas.aff("Léo")) and c2.player_memory.size() == 1 and c2.home == cam.home and c2.pos.is_equal_approx(cam.pos), "sauvegarde : affinités, mémoire, foyer, position")
	return fails


## Les bots bougent, les véhicules avancent et roulent à droite, portes et campagne présentes.
func _level3() -> int:
	var fails := 0
	var city := CityBuilder.new()
	city.build(CityBuilder.load_config())
	var d := BotDirector.new()
	d.load_brains()
	d.setup(city)
	var start := {}
	for b in d.brains:
		start[b.bot_name] = b.pos + b.jitter
	var cars0: Array = []
	for c in city.traffic.cars:
		cars0.append((c["pos"] as Vector3))
	var right_ok := true
	var min_gap := 99.0
	var steps := 0
	for i in 400:   # 40 s simulées
		d.sim(0.1)
		steps += 1
		for c in city.traffic.cars:
			if c["turn"]:
				continue
			var p: Vector3 = c["pos"]
			var lp: float = (p.z - city.traffic._lpos(0, int(c["k"]))) if c["axis"] == 0 else (p.x - city.traffic._lpos(1, int(c["k"])))
			var want: float = 2.5 * float(c["sg"]) if c["axis"] == 0 else -2.5 * float(c["sg"])
			if absf(lp - want) > 0.05:
				right_ok = false
		for a in city.traffic.cars:
			for o in city.traffic.cars:
				if a != o:
					min_gap = minf(min_gap, (a["pos"] as Vector3).distance_to(o["pos"]))
	var moved := 0
	var visible := 0
	for b in d.brains:
		if not b.hidden:
			visible += 1
			if (b.pos + b.jitter).distance_to(start[b.bot_name]) > 0.5:
				moved += 1
	fails += _chk(visible > 0 and moved * 2 >= visible, "les bots bougent (%d/%d visibles)" % [moved, visible])
	var cm := 0
	for i in cars0.size():
		if (city.traffic.cars[i]["pos"] as Vector3).distance_to(cars0[i]) > 5.0:
			cm += 1
	fails += _chk(city.traffic.cars.size() >= 10 and cm * 2 >= cars0.size(), "les véhicules avancent (%d/%d)" % [cm, cars0.size()])
	fails += _chk(right_ok, "les véhicules roulent à droite")
	fails += _chk(min_gap > 1.5, "pas de collision (écart min %.1f m)" % min_gap)
	fails += _chk(city.details.door_count == city.buildings.size() and city.details.sign_count >= 5, "portes (%d) et enseignes (%d)" % [city.details.door_count, city.details.sign_count])
	fails += _chk(city.cols_n >= 11 and city.country != null and city.country.farm_count > 0 and city.country.tree_count > 0 and city.country.road_count > 0, "ville agrandie + campagne")
	city.free()
	return fails
