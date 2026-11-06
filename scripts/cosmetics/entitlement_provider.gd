class_name EntitlementProvider
extends RefCounted
## Interface « droits d'usage » des cosmétiques. Le jeu ne sait jamais COMMENT un item est obtenu :
## il demande seulement owns(id). Implémentations :
## - LocalEntitlements : tout le gratuit est possédé, le premium est verrouillé (mode dev : --kw-unlock-all).
## - Futur backend boutique (Steam / itch.io / serveur) : créer une sous-classe (voir store_entitlements.gd),
##   la brancher dans Cosmetics._make_provider(). Aucune clé ni paiement réel dans ce dépôt.

## Fin d'une tentative d'achat : ok = l'item est désormais possédé ; message = texte pour l'utilisateur.
signal purchase_finished(id: String, ok: bool, message: String)
## La liste des items possédés a changé (achat, restauration, synchronisation…).
signal entitlements_changed

var catalog: CosmeticCatalog


func setup(cat: CosmeticCatalog) -> EntitlementProvider:
	catalog = cat
	return self


## Nom affiché (diagnostic / README).
func provider_name() -> String:
	return "abstract"


func owns(_id: String) -> bool:
	return false


func list_owned() -> Array:
	var out := []
	for id in catalog.order:
		if owns(id):
			out.append(id)
	return out


## La boutique est-elle ouverte ? (false → les boutons d'achat affichent « Bientôt disponible »)
func store_available() -> bool:
	return false


## Lance un achat ; le résultat arrive TOUJOURS par purchase_finished (asynchrone).
func purchase(id: String) -> void:
	_finish.call_deferred(id, false, "Boutique bientôt disponible.")


## Re-synchronise les droits (ex. « Restaurer mes achats »).
func refresh() -> void:
	entitlements_changed.emit()


func _finish(id: String, ok: bool, message: String) -> void:
	purchase_finished.emit(id, ok, message)
	if ok:
		entitlements_changed.emit()
