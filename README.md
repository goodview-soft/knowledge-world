# Knowledge World — V1

Univers 3D personnel de connaissances (Godot 4.7, GDScript, aucune dépendance).

## Lancer
    ./lancer.sh                      # ou : flatpak run org.godotengine.Godot --path ~/knowledge-world
Test d'intégration (sauvegarde séparée, ne touche pas vos données) :
    ./lancer.sh --headless -- --kw-test --kw-save=$PWD/.test/t.json
Sauvegarde réelle : `user://knowledge_world.json` (+ `.bak`), auto-sauvegarde ~1 s après chaque modification, Ctrl+S.

## Contrôles
ZQSD/flèches se déplacer · souris regarder · Maj courir · **E** interagir · Échap fermer/libérer la souris · clic reprendre la main
**Tab** carte/recherche/favoris/récents/création · **H** hub · **N** note rapide · **L** bibliothèque · **F** relations (objet visé ou salle) · **F1** aide
**B** construction : 1-0 choisir l'objet, clic poser · clic sélectionner · G déplacer · R/molette pivoter · PgUp/PgDn taille · Ctrl+D dupliquer · Suppr supprimer · X grille · clic droit annuler

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

## Reste à faire
Carte mentale, tableau comparatif, tableau de suivi, terminal/écran/statistiques · couloirs physiques entre salles (actuellement fondu enchaîné) · sons d'ambiance · PDF complexes / DOCX (backend) · backend RAG HTTP (FastAPI + Qdrant) · fournisseurs IA supplémentaires · annuler/rétablir global · réglages (sensibilité, FOV) · multi-sélection en construction.

## IA
Par défaut : assistant simulé local. Pour Ollama local, créer `user://ai_config.json` :
`{"provider": "ollama", "url": "http://localhost:11434", "model": "llama3.2"}`. Aucune clé API dans le projet.
