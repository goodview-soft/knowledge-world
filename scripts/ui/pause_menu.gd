class_name PauseMenu
extends KWPanel
## Menu principal / pause (Échap) : reprendre, carte, salle, casier, paramètres, aide, quitter.


func _init() -> void:
	super("Knowledge World", Vector2(440, 570))
	var items := [
		["▶   Reprendre", func(): closed.emit()],
		["◎   Carte du monde", func(): main.open_panel(MapPanel.new())],
		["✎   Personnaliser la salle", func(): main.open_panel(RoomPanel.new(main.current_room))],
		["✦   Casier (personnalisation)", func(): main.open_panel(LockerPanel.new())],
		["⚙   Paramètres", func(): main.open_panel(SettingsPanel.new())],
		["⌂   Écran d'accueil · mondes", func(): main.show_title()],
		["?    Raccourcis", func():
			closed.emit()
			main.hud.help.visible = true],
	]
	for it in items:
		var b := styled_btn(body, it[0], it[1], "MenuItem")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
	spacer(body)
	sep(body)
	var q := styled_btn(body, "⏻   Sauvegarder et quitter", func():
		World.save_world()
		get_tree().quit(), "MenuItem")
	q.alignment = HORIZONTAL_ALIGNMENT_LEFT
	q.add_theme_color_override("font_color", KWTheme.DANGER)
	q.add_theme_color_override("font_hover_color", KWTheme.DANGER.lightened(0.3))


func _ready() -> void:
	super()
	if World.data.rooms.has(main.current_room):
		set_subtitle(World.data.rooms[main.current_room].name)
	(body.get_child(0) as Button).grab_focus()
