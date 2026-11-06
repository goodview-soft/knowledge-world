class_name KWHotbar
extends RefCounted
## Barre rapide 1-0 du mode construction, persistée dans KWSettings ("hotbar").

const SIZE := 10


## 10 types (chaîne vide = slot libre), types inconnus filtrés.
static func slots() -> Array:
	var raw = KWSettings.get_value("hotbar")
	var out := []
	for i in SIZE:
		var t := ""
		if raw is Array and i < raw.size():
			t = str(raw[i])
		out.append(t if ObjectRegistry.DEFS.has(t) else "")
	return out


static func type_at(idx: int) -> String:
	var s := slots()
	return s[idx] if idx >= 0 and idx < SIZE else ""


static func index_of(type: String) -> int:
	return slots().find(type) if type != "" else -1


## Place `type` dans le slot idx ; s'il était déjà ailleurs, les deux slots sont échangés.
static func assign(idx: int, type: String, save := true) -> void:
	if idx < 0 or idx >= SIZE:
		return
	var s := slots()
	var prev := s.find(type) if type != "" else -1
	if prev >= 0 and prev != idx:
		s[prev] = s[idx]
	s[idx] = type
	KWSettings.set_value("hotbar", s)
	if save:
		KWSettings.save_settings()


static func clear(idx: int) -> void:
	assign(idx, "")


static func reset() -> void:
	KWSettings.set_value("hotbar", ObjectRegistry.PALETTE.duplicate())
	KWSettings.save_settings()


static func key_label(idx: int) -> String:
	return str((idx + 1) % 10)
