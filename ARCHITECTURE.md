# Architecture

Principe : **les données font foi** ; la 3D est une projection reconstruite à partir d'elles.

| Module | Fichier | Rôle |
|---|---|---|
| Données & persistance | `scripts/core/world.gd` (autoload `World`) | portails, salles, objets, documents, relations, historique ; ids stables ; JSON atomique + .bak ; signal `changed(kind, id, action)` |
| Catalogue d'objets | `scripts/world/object_registry.gd` | définitions (taille, panneau), contenu par défaut, visuels, `text_of()` |
| Objet 3D | `scripts/world/kw_object.gd` | nœud reconstruit depuis `World.data.objects[id]` |
| Salles | `scripts/world/room_builder.gd` | génère toute salle depuis `{size, color}` |
| Joueur | `scripts/player/player.gd` | FPS, RayCast3D |
| Construction | `scripts/build/build_mode.gd` | pose/déplacement/rotation/échelle/duplication/suppression |
| Orchestration | `scripts/main.gd` | salle courante, interactions, panneaux, transitions |
| UI | `scripts/ui/*` | `KWPanel` (base) + un panneau par outil, HUD |
| IA | `scripts/ai/assistant.gd` (autoload) + `AIProvider` / `MockProvider` / `OllamaProvider` | contexte 4 niveaux (global, portail, salle, documents), propositions validées |
| RAG | `scripts/ai/rag_backend.gd` (interface) + `keyword_rag.gd` | recherche locale ; futur `HttpRagBackend` (FastAPI : /index, /search) |
| Tests | `tests/self_test.gd` | intégration dans la vraie scène (`--kw-test`) |

## Modèle de données (`knowledge_world.json`)
- `portals{id: {name, color, entrance}}`
- `rooms{id: {name, portal_id, parent_id, size[w,h,d], color}}`
- `objects{id: {type, name, room_id, pos, rot, scale, content{}, params{}, created, modified}}` — portes/portails : `params.target_room`
- `documents{id: {name, ext, text, source_path, rooms[]}}` — un document, plusieurs salles
- `relations{id: {from{kind,id}, to{kind,id}, type, description, created}}`
- `history[]` (transformations), `favorites[]`, `recent[]`, `hub`

## Ajouter un type d'objet
1. Entrée dans `ObjectRegistry.DEFS` (+ `PALETTE` si posable). 2. `default_content` et un cas dans `build()`.
3. Si éditable : un panneau `extends KWPanel` et un cas dans `Main.interact()`.

## Ajouter un fournisseur IA
Hériter de `AIProvider`, implémenter `complete(context, history, cb)` → `{text, proposals[]}`, le brancher dans `Assistant._ready()` selon `ai_config.json`.
