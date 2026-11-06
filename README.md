# Knowledge World — V1

Univers 3D personnel de connaissances (Godot 4.7, GDScript, aucune dépendance).

## Lancer
    ./lancer.sh                      # ou : flatpak run org.godotengine.Godot --path ~/knowledge-world
Test d'intégration (sauvegarde séparée, ne touche pas vos données) :
    ./lancer.sh --headless -- --kw-test --kw-save=$PWD/.test/t.json
Sauvegarde réelle : `user://knowledge_world.json` (+ `.bak`), auto-sauvegarde ~1 s après chaque modification, Ctrl+S.

## Contrôles
ZQSD/flèches se déplacer · souris regarder · Maj courir · **Espace** sauter · **Ctrl gauche** (maintenu seul) ou **C** (bascule) s'accroupir · **E** interagir · **Échap** fermer le panneau ouvert, sinon menu (reprendre, carte, salle, paramètres, quitter) · clic reprendre la main
**Tab** carte/recherche/favoris/récents/création · **H** hub · **N** note rapide · **L** bibliothèque · **G** graphe · **F** relations (objet visé ou salle) · **P** personnaliser la salle · **T** style de l'objet visé · **F1** feuille de raccourcis
**B** construction : **I** ou **Tab** inventaire · 1-0 barre rapide · clic poser (fantôme vert = libre, rouge = occupé ; Maj+clic force) · clic sélectionner · G déplacer · R/molette pivoter · PgUp/PgDn taille (murs : largeur ; Maj = largeur seule / uniforme pour les murs) · **T** style de la sélection · Ctrl+D dupliquer · Suppr supprimer · X grille (+ accrochage des murs bout à bout) · clic droit annuler

## Inventaire de construction
- **I / Tab** en mode construction : vignettes par catégories (Connaissance, Mobilier, Architecture, Décoration, Navigation), recherche, survol = description et dimensions.
- Clic = l'objet rejoint la barre rapide (slot cible) et passe en pose · glisser une vignette sur un slot, clic droit « assigner au slot », ou touche 1-0 au survol · clic droit sur un slot = le vider.
- Barre rapide persistée dans `user://settings.json` (`hotbar`). Balancement de tête : clé `head_bob`.
- Objets : canapé, fauteuil, chaise, tables, étagère, plante, tapis, lampes, pouf, banc, coussins ; mur, demi-mur, mur vitré, colonne, estrade (montée en marchant), arche, rambarde, panneau lumineux (plafond) ; cadre, horloge, vase, livres, globe, sculpture.
- Code : `ObjectRegistry.DEFS` (cat, desc, mount, solid, parts, edge_snap, width_resize), visuels `scripts/build/object_builders.gd`, `scripts/inventory/` (`KWHotbar`, `KWItemIcon`), `scripts/ui/inventory_panel.gd`.

## Fonctionnalités V1
- Hub navigable, 3 portails, salle secondaire (Informatique → Godot & 3D), portes générées automatiquement.
- Création / renommage / suppression de salles et portails (carte), portes configurables posées à la main.
- Mode construction complet (sol / murs / sur d'autres objets, grille optionnelle).
- Notes, post-it, fiches ; tableau blanc (dessin, textes, gomme, annuler) ; Kanban (colonnes/cartes).
- Bureau avec assistant simulé contextuel (salle / portail / global) : synthèse, questions, connexions, plan Kanban, nouvelle salle — **toujours validé par l'utilisateur**.
- Bibliothèque : import texte/PDF simple (bouton ou glisser-déposer), lecture, un document lié à plusieurs salles, recherche, extrait → note.
- Relations typées (objets, salles, portails, documents), fils lumineux entre objets reliés.
- Transformations non destructives + historique : note → fiche / Kanban / salle, conversation → note, document → note.
- Recherche globale (salles, contenus, documents), favoris, récents, téléportation.

## Notes (inspirées d'Obsidian)
- Éditeur Markdown : bascule **Édition / Partagé / Aperçu** ; aperçu rendu (titres, gras/italique, ~~barré~~, ==surligné==, listes, `- [ ]` cases cliquables, code, citations, liens).
- Liens wiki `[[Nom]]` / `[[Nom|alias]]` vers une note, une salle ou un document, autocomplétion à la frappe de `[[` (↑↓, Entrée/Tab). Clic dans l'aperçu : ouvre la note (voyage si autre salle), la salle ou le document ; nom inexistant → proposition de créer la note.
- Colonne latérale : #tags (chips), liens sortants, rétroliens. Les liens wiki deviennent des relations World « thématique » (description `wikilink`) synchronisées à chaque sauvegarde, sans doublonner les relations manuelles.
- **G** (hors construction) ou bouton « Graphe » de la carte : graphe force-dirigé (salles, notes, documents ; arêtes = relations + hiérarchie), zoom molette, glisser, survol = voisins, clic = y aller, filtre « Notes seules » et par #tag.
- « Note du jour » : note datée (AAAA-MM-JJ) créée/ouverte dans le hub.
- Code : `scripts/notes/` (`NoteLinks`, `NoteMarkdown`, `KWGraphView`, `GraphPanel`).

## Interface & personnalisation
- Design system `KWTheme` (palette sombre, accent unique, variations PrimaryButton/GhostButton/DangerButton/Chip/Card…) et helpers `KWPanel` (`primary`, `card`, `slider`, `color_field`, `choice`…).
- Salle (P) : couleurs murs/sol/plafond, matériau du sol (bois, béton, moquette, carrelage, marbre), ambiance lumineuse + intensité, dimensions (objets recalés, portes suivent leur mur), préréglages. Champs optionnels dans `rooms[id]`.
- Objets (T) : nom, couleurs principale/secondaire, lampe : couleur/intensité — `params.style`.
- Paramètres (menu Échap) : sensibilité, FOV, vitesse, inverser Y, taille de l'UI — `user://settings.json` (hors monde).

## Reste à faire
Carte mentale, tableau comparatif, tableau de suivi, terminal/écran/statistiques · couloirs physiques entre salles (actuellement fondu enchaîné) · sons d'ambiance · PDF complexes / DOCX (backend) · backend RAG HTTP (FastAPI + Qdrant) · fournisseurs IA supplémentaires · annuler/rétablir global · multi-sélection en construction.

## IA
Par défaut : assistant simulé local. Pour Ollama local, créer `user://ai_config.json` :
`{"provider": "ollama", "url": "http://localhost:11434", "model": "llama3.2"}`. Aucune clé API dans le projet.

## Structures (mode construction, catégorie Architecture)
Mur tracé (clic A puis clic B, enchaînement), Sol / plancher (rectangle), Escalier (1 étage, R pivoter).
PgUp/PgDn : étage (3 m) · M : matériau (enduit, brique, bois, carrelage, pierre, béton, marbre, sombre) · clic droit/Échap : quitter.
Motifs plaqués en coordonnées monde : raccords sans couture. T sur une pièce : motif + teinte.

## Conscience
Entrée : parler dans la pièce (chat façon Minecraft) · Entrée maintenue : chat complet. Réponses lues à voix haute (TTS système, réglage « tts »).
