class_name LocalEntitlements
extends EntitlementProvider
## Implémentation locale (hors ligne) : gratuit = possédé, premium = verrouillé.
## --kw-unlock-all (arguments utilisateur) : tout est possédé (développement / captures).
## `granted` : ids accordés localement (cadeaux, codes futurs…), persistés par Cosmetics.

var unlock_all := false
var granted := []


func _init() -> void:
	unlock_all = "--kw-unlock-all" in OS.get_cmdline_user_args()


func provider_name() -> String:
	return "local" + (" (dev : tout débloqué)" if unlock_all else "")


func owns(id: String) -> bool:
	var it := catalog.get_item(id)
	if it.is_empty():
		return false
	return unlock_all or not bool(it.premium) or id in granted


func purchase(id: String) -> void:
	if owns(id):
		_finish.call_deferred(id, true, "Déjà possédé.")
	else:
		_finish.call_deferred(id, false, "Boutique bientôt disponible — aucun paiement n'est possible pour l'instant.")
