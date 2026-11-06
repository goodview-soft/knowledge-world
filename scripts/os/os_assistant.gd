class_name OSAssistant
extends OSApp
## Assistant IA : le ChatPanel existant, intégré tel quel dans une fenêtre
## (même conversation : content.messages du bureau).

var chat: ChatPanel


func _init(desk_id: String) -> void:
	super()
	chat = ChatPanel.new(desk_id)
	chat.custom_minimum_size = Vector2.ZERO
	chat.header.visible = false
	chat.header.get_parent().get_child(1).visible = false
	chat.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(chat)
