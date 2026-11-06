class_name AIProvider
extends Node
## Interface d'un fournisseur IA. Aucune dépendance à un fournisseur précis.
## complete() appelle cb.call(result) une seule fois avec :
##   {"text": String, "proposals": Array (optionnel), "error": String (optionnel), "stopped": bool (optionnel)}
## on_chunk (optionnel) reçoit le texte cumulé pendant le streaming.
## ctx["_system"] contient le prompt système préparé par Assistant.
## Les propositions ne sont JAMAIS appliquées automatiquement : l'utilisateur valide.

func display_name() -> String:
	return "aucun"


func complete(_context: Dictionary, _history: Array, cb: Callable, _on_chunk := Callable()) -> void:
	cb.call({"text": "Aucun fournisseur IA configuré.", "proposals": []})


## Interrompt la génération en cours (cb est alors appelé avec stopped = true).
func cancel() -> void:
	pass
