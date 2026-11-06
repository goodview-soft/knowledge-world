class_name KeywordRag
extends RagBackend
## Recherche plein texte locale par mots-clés (pas d'index persistant : lit World).

const STOP := ["les", "des", "une", "est", "que", "qui", "pour", "dans", "avec", "sur", "pas", "par", "plus", "the", "and", "quoi", "comment"]


static func tokens(q: String) -> Array:
	var re := RegEx.new()
	re.compile("[\\p{L}\\p{N}]{3,}")
	var out := []
	for m in re.search_all(q.to_lower()):
		if not m.get_string() in STOP:
			out.append(m.get_string())
	return out


func search(query: String, doc_ids := [], k := 5) -> Array:
	var terms := tokens(query)
	var res := []
	if terms.is_empty():
		return res
	var ids: Array = doc_ids if not doc_ids.is_empty() else World.data.documents.keys()
	for id in ids:
		var d = World.data.documents.get(id)
		if d == null:
			continue
		var low: String = (d.name + "\n" + d.text).to_lower()
		var score := 0
		var first := -1
		for t in terms:
			var c := low.count(t)
			score += c
			if c > 0 and (first < 0 or low.find(t) < first):
				first = low.find(t)
		if score > 0:
			var start := maxi(0, first - 80)
			res.append({"doc_id": id, "score": score, "snippet": (d.name + "\n" + d.text).substr(start, 260).replace("\n", " ")})
	res.sort_custom(func(a, b): return a.score > b.score)
	return res.slice(0, k)
