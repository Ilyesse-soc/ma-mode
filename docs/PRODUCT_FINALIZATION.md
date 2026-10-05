# Interface et garde-robe locale — 6 octobre 2026

L'application locale est servie sur http://127.0.0.1:18080, avec l'API réelle sur
http://127.0.0.1:18000. Les comptes, photos et tenues restent isolés par utilisateur.
Les configurations privées résident dans `.local/`; seul `.env.example` est publié.

La palette de la maquette est centralisée dans `AppColors` : fond `#0B0B0C`,
surfaces `#151517` et `#1C1C1F`, bordure `#29292D`, texte `#F5F2EA`, secondaire
`#A7A5A0`, crème `#EDE2CE`, succès `#5DAE78`, danger `#C95858`. Inter assure la
lecture de l'interface et Playfair Display les grands titres éditoriaux ; les
polices et leurs licences sont locales. Espacement horizontal principal : 16 px.

Les changements concernent le splash, la reprise fonctionnelle de l'onboarding,
les préférences, l'accueil, le dressing vide/rempli, l'ajout, le scanner, la revue
d'identification, le détail éditable, la silhouette, le mannequin, les résultats
et détails outfit, le feedback, l'historique, Explorer et le profil. La grille
utilise trois colonnes sur téléphone standard, deux sur écran étroit ou avec
agrandissement du texte. Une recherche locale filtre nom, marque, couleur et
catégorie, sans appels superflus.

`GarmentVisual` et `GarmentCard` partagent la priorité photo vêtement, image
catalogue confirmée, illustration de catégorie. Les nouvelles photos d'étiquette
ne deviennent pas l'image principale. La revue d'identification conserve les
sources, candidats, références et liens ; elle demande confirmation et complète
les champs manquants. Les scores de concordance ne sont pas présentés comme une
garantie statistique de l'identité du produit.

`DressingSelection` pilote toucher, remplacement, retrait et drop sur une zone
compatible. `OutfitStage` partage le rail des vêtements et la vue centrale.
`MannequinViewer` charge les modèles fournis, inchangés, depuis
`assets/3d/mannequins/male.glb` et `assets/3d/mannequins/female.glb` dans le bundle
mobile. `OutfitComposer` produit une représentation générique séparée en mémoire.
Les poses futures ne sont pas affichées comme des animations disponibles.

`scripts/seed_my_wardrobe.py` lit `SEED_USER_EMAIL` depuis `.local/seed.env`,
refuse une base distante, un environnement autre que development ou un compte
inexistant, et verrouille le compte pendant sa transaction. Il crée uniquement
ses 45 vêtements : 11 hauts, 5 vestes/manteaux, 11 bas, 5 chaussures et
13 accessoires. Il sauvegarde cinq tenues personnelles ; aucun historique de
port artificiel n'est créé. Les répétitions ont évité 45 doublons de vêtements et
5 doublons de tenues. Les vêtements déjà présents sont conservés.

Vérifications obtenues :

- `flutter analyze` : aucun problème.
- `flutter test` : 40 tests réussis, dont édition inline et drop incompatible.
- Ruff et mypy : aucun problème ; pytest : 112 tests réussis.
- Navigateur 390 × 844 : inscription, reprise préférences/consentement,
  dressing vide, ajout, véritable drag accepté/refusé, sélection par toucher,
  remplacement, sauvegarde, port, rendu GLB, rotation 360°, zoom, recentrage,
  remplacement API d'une seule catégorie, feedback neutre, météo de l'historique
  et navigation garde-robe/Explorer/profil. Voir `FINALIZATION_BROWSER_CHECK.json`.
- Sept scénarios en lecture seule sur la garde-robe personnelle : froid/pluie,
  10 °C, 18 °C, 25 °C, soirée, travail, voyage. Ils ne remplacent jamais la météo
  réelle de l'application. Rapport anonymisé : `PERSONAL_WARDROBE_CHECK.json`.
- Parcours API avec PostgreSQL, Redis, MinIO, météo, catalogue et IA réels :
  une passe précédente a validé les 25 parcours ; la dernière passe en valide
  23 sur 24, l'analyse photo étant limitée par un quota externe (HTTP 429 du
  fournisseur, réponse applicative 503), malgré une reprise bornée. L'OCR de
  l'étiquette a réussi lors de cette dernière passe. Aucun résultat n'est simulé.
- Bandit et Semgrep : zéro résultat ; Gitleaks : aucun secret détecté ; Trivy
  fichiers/image : aucune vulnérabilité HIGH/CRITICAL détectée dans leur périmètre.

La reproduction n'est pas certifiée pixel par pixel sur tous les écrans et états.
Les coupes, motifs et textures exacts des produits demandent des assets 3D de
vêtements ; les deux GLB livrés représentent les corps, pas une bibliothèque de
produits. La scène est composée avec un décor et une plateforme, sans nouveau
GLB de dressing. Le zoom et la rotation se font par gestes ; leur barre de
commandes n'est pas identique à celle de la maquette. Les étapes de génération
restent en attente tant que l'API ne fournit pas de progression détaillée.

Les 45 vêtements locaux utilisent des illustrations de catégorie faute de
photographies autorisées correspondantes. Aucune image de marque n'a été
scrapée. La migration conserve les anciennes images avec leur classification
par défaut ; les éventuelles anciennes photos d'étiquette peuvent nécessiter
une correction de provenance. L'authentification supplémentaire, les messages
de consentement et les états d'erreur occupent plus d'espace que la planche.

La caméra, le GPS matériel, les haptics et les performances Android/iOS restent
à vérifier sur appareil physique. Les vérifications par widgets/navigateur ne
les remplacent pas. Le build web JavaScript réussit ; le port Wasm n'est pas
validé. SMTP et les paramètres légaux/signature/TLS de production restent des
prérequis externes ; les protections et les gates de livraison restent actifs.
