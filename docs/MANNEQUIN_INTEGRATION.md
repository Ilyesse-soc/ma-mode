# Intégration des mannequins finaux — 5 octobre 2026

Les deux fichiers fournis ont remplacé les anciens GLB aux mêmes chemins. Leur contenu est identique octet par octet aux fichiers sources ; aucune géométrie, matière, couverture intime, orientation ou échelle n'a été modifiée. `pubspec.yaml` déclarait déjà le dossier `assets/3d/mannequins/` et n'a pas nécessité de modification. Le bundle a été régénéré pour éliminer les assets précédents en cache.

| Profil | Asset Flutter | Taille | Triangles | Hauteur rendue |
|---|---|---:|---:|---:|
| Femme (`female`) | `assets/3d/mannequins/female.glb` | 2 286 728 octets | 126 691 | 1,7674 m |
| Homme (`male`) | `assets/3d/mannequins/male.glb` | 2 780 272 octets | 154 102 | 1,8275 m |

SHA-256 :

- Femme : `8e311f5d3e94a825dd6ceeed1f8b95a23e47977892c7007b3bc92ad6737f029b`
- Homme : `70b444911129ffa237f071544c7885b0994f3ef993ac10ca2dd23d91b9c00485`

Les deux GLB 2.0 contiennent `Mannequin_Body` et `Mannequin_Briefs`, sans textures, skin ni animations. Corps métallique à 0, rugosité 0,55 ; briefs métalliques à 0, rugosité 0,6. Aucun téléchargement externe n'est nécessaire pour les modèles ou l'éclairage neutre du viewer.

## Composant et cadrage

`apps/mobile/lib/features/mannequin/mannequin_viewer.dart`, composant `MannequinViewer`, utilise `ModelViewer` de `model_viewer_plus`. La silhouette et le résultat outfit lui transmettent `mannequinPresentation` du profil. La résolution du chemin accepte uniquement `female` et `male` ; un changement de présentation recharge le bon asset et recrée le renderer.

- Centrage automatique sur les limites réelles ; orientation conservée, Y vertical ; échelle `1 1 1`.
- Caméra frontale `0deg 90deg 105%`, champ 30°, distance proportionnelle au modèle plutôt qu'une valeur arbitraire en mètres.
- Rotation manuelle avec inertie ; rotation automatique désactivée conformément au parcours dressing. Azimut libre, inclinaison bornée 25–155°, double-tap pour recentrer.
- Zoom actif, distances bornées 45–180 % ; déplacement du centre désactivé pour conserver le mannequin cadré.
- Environnement neutre, exposition 1,2, ombre 0,4 et douceur 1. Le rendu local montre les deux corps et leur couverture, de la tête aux pieds.

Les conventions de caméra et les événements suivent la [documentation officielle de model-viewer](https://modelviewer.dev/docs/).

## Chargement et erreurs

Prévalidation de disponibilité et d'en-tête GLB dans Flutter. Si le fichier est absent ou invalide : message et bouton `Réessayer`, sans autre mannequin. La prévalidation ne prétend pas valider toute la géométrie ; les erreurs de décodage et de WebGL sont prises en charge par le renderer.

Le renderer affiche un état de chargement, le retire après `load`, expose un message et une nouvelle tentative après `error`, ou après 45 secondes sans chargement. Une nouvelle tentative recharge seulement le viewer isolé. Aucun nouveau placeholder n'est généré. Le script de génération des anciens placeholders a été supprimé.

## Vérifications réellement exécutées

- Comparaison des octets sources/destination et des SHA-256 ; inspection de l'en-tête, JSON, meshes, matériaux, bounds et nombre de triangles.
- Rendu local des deux GLB dans Edge sans fenêtre, avec le JavaScript model-viewer embarqué par la dépendance Flutter, viewport de 390 px et rendu logiciel SwiftShader. Vérification visuelle des captures : centrage, orientation frontale, taille, éclairage et briefs conservés.
- Exercice de l'orbite à 90°, 180°, 270° et 360° et réduction de la distance caméra par l'API du renderer : réussis pour les deux modèles, après stabilisation du mouvement. Erreur sur GLB absent avec fallback visible. Résultats détaillés dans `MANNEQUIN_RENDER_CHECK.json`.
- Première session locale sans temps virtuel : environ 1 636 ms / 1 687 ms jusqu'à `load`. Mesures ponctuelles sur ordinateur avec serveur local, sans garantie de répétabilité ni extrapolation mobile.
- Dernière session avec cache navigateur chaud : 284 ms / 578 ms, conservés dans le reçu. Ces différences montrent pourquoi ces essais ne remplacent pas une mesure à froid sur appareil.
- `flutter analyze --no-pub` : aucune anomalie, exit 0.
- `flutter test --no-pub` : 24 tests réussis, exit 0 ; 5 nouveaux tests couvrent les vrais assets du bundle, les profils, les contrôles configurés, le fichier absent/corrompu et la nouvelle tentative.

## Limites

Aucun téléphone Android/iOS connecté : gestes de glissement/pincement dans la WebView, FPS, mémoire GPU, batterie et latence de chargement à froid sur mobile restent à mesurer. Le rendu navigateur exerce le même moteur mais ne constitue pas une recette de l'application native.

Les modèles dépassent le budget initial de 25 000 triangles. Aucun LOD ni aucune simplification n'a été appliqué, conformément à la demande. Il faut mesurer avant de décider si des variantes optimisées séparées sont nécessaires. L'outil `game-dev` et Blender ne sont pas disponibles : les vérifications ont utilisé l'inspection binaire et le renderer réel, sans normalisation ni certification complète glTF.

Les mannequins ne sont pas riggés ; aucun modèle exact de vêtement n’est fourni. `OutfitComposer` compose désormais en mémoire un habillage générique par catégorie/couleur, préservant les deux fichiers originaux. `MannequinScreen` filtre la vraie garde-robe par commandes de zones, remplace/retire les pièces et sauvegarde via l’API ; le résultat outfit utilise le même composant. La sélection anatomique précise sur les triangles, les autres poses et la reproduction exacte des coupes/motifs nécessitent des assets adaptés. Voir `PRODUCT_UX_REPORT.md` et `DRESSING_RENDER_CHECK.json` pour les vérifications récentes.

## Fichiers concernés

Les deux GLB, `lib/features/mannequin/mannequin_viewer.dart`, `test/mannequin_viewer_test.dart`, `docs/3D_ASSET_SPEC.md`, `docs/UI_IMPLEMENTATION_STATUS.md`, ce document et le reçu de rendu. Suppression de `apps/mobile/scripts/generate_placeholder_mannequin.py`. Aucun changement backend ni aucune modification des fichiers GLB sources.
