class_name GameClock
extends RefCounted
## Horloge du jeu : une journée = day_length secondes réelles (réglable).

var day_length := 1200.0
var day := 1
var minutes := 480.0

func advance(dt: float) -> void:
	minutes += dt * 1440.0 / maxf(day_length, 1.0)
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1

func hour() -> float:
	return minutes / 60.0

func set_time(d: int, h: float) -> void:
	day = d
	minutes = h * 60.0

func is_night() -> bool:
	return hour() >= 22.5 or hour() < 7.0

## Temps absolu en heures (pour comparer des événements).
func absolute() -> float:
	return day * 24.0 + hour()

func text() -> String:
	return "Jour %d · %02d:%02d" % [day, int(minutes) / 60, int(minutes) % 60]

func to_dict() -> Dictionary:
	return {"day": day, "minutes": minutes, "day_length": day_length}

func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", day))
	minutes = float(d.get("minutes", minutes))
	day_length = float(d.get("day_length", day_length))
