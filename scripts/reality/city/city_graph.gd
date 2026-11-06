class_name CityGraph
extends RefCounted
## Graphe piéton : points (coins de trottoir + portes) reliés ; chemin par A*.

var astar := AStar3D.new()
var _next := 0

func add_point(p: Vector3) -> int:
	var id := _next
	_next += 1
	astar.add_point(id, p)
	return id

func link(a: int, b: int) -> void:
	if a != b and not astar.are_points_connected(a, b):
		astar.connect_points(a, b, true)

func pos(id: int) -> Vector3:
	return astar.get_point_position(id)

func size() -> int:
	return astar.get_point_count()

func nearest(p: Vector3) -> int:
	return astar.get_closest_point(p)

## Suite d'identifiants de a à b ([] si aucun chemin).
func find_path(a: int, b: int) -> Array:
	var out: Array = []
	for id in astar.get_id_path(a, b):
		out.append(int(id))
	return out
