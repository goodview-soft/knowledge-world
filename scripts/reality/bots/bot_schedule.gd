class_name BotSchedule
extends RefCounted
## Emploi du temps type d'un bot (heures de jeu). Modifiable ici.
## Renvoie {key, kind, target} ; target : "home", "work", "cafe", "parc", "friend:<prénom>" ou "place:<id>".

const WORK_START := 7.3   # + décalage individuel (0..0.6 h)
const LUNCH := [12.0, 13.0]
const LEISURE := [17.5, 19.5]
const HOME_EVENING := 22.5

static func plan(b: BotBrain, h: float, day: int, event: Dictionary) -> Dictionary:
	var kind := "home"
	var target := "home"
	var sel := absi(b.bot_name.hash()) + day * 7
	if not event.is_empty():
		kind = "event"
		target = "place:" + str(event.get("place", ""))
		return {"key": "event:%s:%d" % [event.get("id", ""), day], "kind": kind, "target": target}
	if h < WORK_START + b.offset or h >= HOME_EVENING:
		kind = "home"
	elif h < LUNCH[0] or (h >= LUNCH[1] and h < LEISURE[0]):
		kind = "work"
		target = "work"
	elif h < LUNCH[1]:
		kind = "break"
		target = "cafe" if sel % 2 == 0 else "parc"
	elif h < LEISURE[1]:
		var friend := b.best_friend(10.0)
		var r := sel % 10
		if friend != "" and r < 4:
			kind = "visit"
			target = "friend:" + friend
		elif r < 7:
			kind = "leisure"
			target = "parc"
	return {"key": "%s:%s:%d" % [kind, target, day], "kind": kind, "target": target}
