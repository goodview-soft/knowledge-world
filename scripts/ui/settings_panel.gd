class_name SettingsPanel
extends KWPanel
## Paramètres globaux (user://settings.json, hors monde) : souris, FOV, vitesse, UI.


func _init() -> void:
	super("Paramètres", Vector2(640, 520))
	var c1 := card(body, "Contrôles")
	slider(c1, "Sensibilité souris", float(KWSettings.get_value("sensitivity")), 0.2, 3.0, 0.05, func(v): _put("sensitivity", v), "%.2f×")
	slider(c1, "Vitesse", float(KWSettings.get_value("speed")), 0.5, 2.0, 0.05, func(v): _put("speed", v), "%.2f×")
	var h := field(c1, "Inverser l'axe Y")
	var inv := CheckButton.new()
	inv.button_pressed = bool(KWSettings.get_value("invert_y"))
	inv.focus_mode = Control.FOCUS_CLICK
	inv.toggled.connect(func(on): _put("invert_y", on))
	h.add_child(inv)
	var c2 := card(body, "Affichage")
	slider(c2, "Champ de vision", float(KWSettings.get_value("fov")), 55.0, 100.0, 1.0, func(v): _put("fov", v), "%d°")
	var ui := slider(c2, "Taille de l'interface", float(KWSettings.get_value("ui_scale")), 0.75, 1.5, 0.05, func(_v): pass, "%.2f×")
	ui.drag_ended.connect(func(_changed): _put("ui_scale", ui.value))
	dim(c2, "La taille de l'interface s'applique en relâchant le curseur.")
	spacer(body)
	var row := hbox(body)
	ghost(row, "Valeurs par défaut", func():
		KWSettings.data = KWSettings.DEFAULTS.duplicate()
		main.apply_settings()
		closed.emit())
	spacer(row)
	primary(row, "Terminé", func(): closed.emit())


func _put(key: String, value) -> void:
	KWSettings.set_value(key, value)
	main.apply_settings()


func on_close() -> void:
	KWSettings.save_settings()
