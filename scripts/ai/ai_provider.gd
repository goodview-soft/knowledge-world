class_name AIProvider
extends Node
## Interface d'un fournisseur IA. Aucune dépendance à un fournisseur précis.
## complete() doit appeler cb.call(result) avec :
##   {"text": String, "proposals": [ {kind: "note"|"room"|"kanban"|"relation", ...} ]}
## Les propositions ne sont JAMAIS appliquées automatiquement : l'utilisateur valide.

func display_name() -> String:
	return "aucun"


func complete(_context: Dictionary, _history: Array, cb: Callable) -> void:
	cb.call({"text": "Aucun fournisseur IA configuré.", "proposals": []})
