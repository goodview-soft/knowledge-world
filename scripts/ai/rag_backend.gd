class_name RagBackend
extends RefCounted
## Interface de recherche documentaire. Implémentation actuelle : KeywordRag (local).
## Future : HttpRagBackend → FastAPI (extraction PDF/DOCX, embeddings, Qdrant, PostgreSQL)
## exposant POST /index {id, text, meta} , DELETE /index/{id} , POST /search {query, doc_ids, k}.

func index_document(_id: String, _text: String, _meta := {}) -> void:
	pass


func remove_document(_id: String) -> void:
	pass


## Renvoie [{doc_id, score, snippet}] triés par pertinence. doc_ids vide = tous.
func search(_query: String, _doc_ids := [], _k := 5) -> Array:
	return []
