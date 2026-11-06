class_name WBView
extends Control
## Vue statique d'éléments sur une région (utilisée dans une SubViewport : texture 3D, export).

var elements: Array = []
var region := WBModel.FRAME


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WBDraw.BG)
	var z := size.x / region.size.x
	WBDraw.draw_all(self, elements, -region.position * z, z)
