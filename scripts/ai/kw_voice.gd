class_name KWVoice
extends RefCounted
## Voix de la conscience : synthèse vocale locale du système (DisplayServer TTS,
## speech-dispatcher sous Linux). Aucune API externe. Désactivable (réglage « tts »).

static var _voice := ""


static func available() -> bool:
	return DisplayServer.get_name() != "headless" and not DisplayServer.tts_get_voices().is_empty()


static func _pick_voice() -> String:
	if _voice != "":
		return _voice
	var fr := DisplayServer.tts_get_voices_for_language("fr")
	if not fr.is_empty():
		_voice = fr[0]
	elif not DisplayServer.tts_get_voices().is_empty():
		_voice = DisplayServer.tts_get_voices()[0].get("id", "")
	return _voice


static func speak(text: String) -> void:
	var on = KWSettings.get_value("tts")
	if (on != null and not bool(on)) or text.strip_edges() == "" or not available():
		return
	stop()
	var rate = KWSettings.get_value("tts_rate")
	DisplayServer.tts_speak(text.left(1200), _pick_voice(), 80, 0.92, float(rate) if rate != null else 1.0)


static func stop() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
