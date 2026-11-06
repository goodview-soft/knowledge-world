extends SceneTree

func _init() -> void:
	var fails := 0
	var defs := BotDirector.load_defs()
	fails += _chk(defs.size() == 6, "6 bots chargés")
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
	print("BOTS TEST OK" if fails == 0 else "BOTS TEST FAIL %d" % fails)
	quit(fails)

func _chk(c: bool, msg: String) -> int:
	if not c:
		print("ECHEC: ", msg)
	return 0 if c else 1
