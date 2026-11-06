class_name StoreEntitlements
extends EntitlementProvider
## EMPLACEMENT RÉSERVÉ — futur backend boutique. Non branché, aucun appel réseau, aucune clé.
## Pour l'activer plus tard :
##  1. Steam : GodotSteam → Steam Inventory / microtransactions ; owns(id) = item d'inventaire présent.
##     itch.io : clés de téléchargement / API serveur ; serveur maison : GET /entitlements (jeton de session).
##  2. Mettre en cache la liste reçue (refresh()) et émettre entitlements_changed.
##  3. purchase(id) : ouvrir le flux de paiement de la plateforme, puis _finish(id, ok, message).
##  4. Brancher dans Cosmetics._make_provider() (ex. si un fichier user://store_config.json existe).
## Règles produit : purement cosmétique, jamais d'avantage, aucune progression forcée.

var _owned := {} # id -> true (cache de la dernière synchronisation)


func provider_name() -> String:
	return "store (non branché)"


func owns(id: String) -> bool:
	var it := catalog.get_item(id)
	return not it.is_empty() and (not bool(it.premium) or _owned.has(id))


func purchase(id: String) -> void:
	_finish.call_deferred(id, false, "Boutique non connectée.")
