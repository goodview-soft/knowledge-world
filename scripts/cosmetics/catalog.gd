class_name CosmeticCatalog
extends RefCounted
## Catalogue cosmétique data-driven : res://cosmetics/catalog.json (+ tout autre *.json du dossier,
## pour ajouter des packs sans toucher au code). Purement cosmétique : aucun item ne donne d'avantage.
## Item : {id, category, name, description, rarity, premium, price_cents, tags[], params{}}.

const DIR := "res://cosmetics"
const MAIN_FILE := "res://cosmetics/catalog.json"

var rarities := {}   # id -> {name, color, order}
var categories := [] # [{id, name, optional}]
var defaults := {}   # slot -> item id ("" = rien)
var items := {}      # id -> item
var order := []      # ids dans l'ordre du catalogue


func load_all() -> CosmeticCatalog:
	_merge(MAIN_FILE)
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			var p := DIR.path_join(f.trim_suffix(".remap"))
			if p.get_extension() == "json" and p != MAIN_FILE:
				_merge(p)
	return self


func _merge(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Catalogue cosmétique illisible : " + path)
		return
	var dd: Dictionary = parsed
	rarities.merge(dd.get("rarities", {}), true)
	for c in dd.get("categories", []):
		if not has_category(c.get("id", "")):
			categories.append(c)
	defaults.merge(dd.get("defaults", {}), true)
	for it in dd.get("items", []):
		var item: Dictionary = it
		if not item.has("id") or not item.has("category"):
			continue
		for k in ["name", "description"]:
			if not item.has(k):
				item[k] = item.id
		if not item.has("rarity"):
			item.rarity = "common"
		if not item.has("premium"):
			item.premium = false
		if not item.has("price_cents"):
			item.price_cents = 0
		if not item.has("tags"):
			item.tags = []
		if not item.has("params"):
			item.params = {}
		if not items.has(item.id):
			order.append(item.id)
		items[item.id] = item


func has_category(id: String) -> bool:
	for c in categories:
		if c.get("id", "") == id:
			return true
	return false


func category(id: String) -> Dictionary:
	for c in categories:
		if c.get("id", "") == id:
			return c
	return {}


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func by_category(cat: String) -> Array:
	var out := []
	for id in order:
		if items[id].category == cat:
			out.append(items[id])
	return out


func rarity_color(rarity: String) -> Color:
	var r: Dictionary = rarities.get(rarity, {})
	return Color(r.get("color", "#9aa3ad"))


func rarity_name(rarity: String) -> String:
	var r: Dictionary = rarities.get(rarity, {})
	return r.get("name", rarity)


## Prix indicatif lisible (aucun paiement réel n'existe dans ce projet).
static func price_text(item: Dictionary) -> String:
	var c := int(item.get("price_cents", 0))
	if c <= 0:
		return "Gratuit"
	return ("%d,%02d €" % [c / 100, c % 100])
