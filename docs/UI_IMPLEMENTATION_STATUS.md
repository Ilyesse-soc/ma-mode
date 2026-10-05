# Interface Dressly — état au 5 octobre 2026

La reproduction intégrale de la maquette PNG n'est pas achevée. Ce document distingue les parcours implémentés, les tests exécutés et les dépendances encore manquantes. Aucun chantier cybersécurité supplémentaire n'a été entrepris.

## Parcours implémentés

- Splash → restauration de session → accueil ou onboarding/authentification.
- Trois pages d'onboarding → inscription ; connexion depuis les pages d'authentification.
- Inscription → préférences ; sauvegarde des styles, couleurs et seuils de température avec erreur visible en cas d'échec.
- Navigation Accueil / Garde-robe / Outfit / Explorer / Profil ; menu relié aux bons onglets, aide et fermeture du menu.
- Garde-robe vide/remplie, filtres, détail chargé directement depuis l'API, modification et suppression confirmée.
- Ajout manuel ; sélection caméra/galerie, prévisualisation et reprise d'une photo de vêtement ou d'étiquette ; upload, analyse, validation et mise à jour du même brouillon.
- Scan code-barres → résultat → confirmation des informations → mise à jour du même brouillon. L'API renvoie désormais son identifiant. Les brouillons restent archivés jusqu'à la sauvegarde.
- Origine manuelle ou GPS ; sélection et gestion des destinations ; activité ; date ; génération via l'API ; résultat ; explications ; détails des pièces ; enregistrement de la tenue portée ; feedback avec erreur et nouvelle tentative.
- Historique → détails des pièces ; favoris persistés via l'API ; favoris dans Explorer ; réouverture de la dernière recommandation sans en générer une autre.
- Profil, thème persistant, préférences de notifications, documents de confidentialité, export JSON consultable, copiable et partageable comme fichier, suppression de compte avec mot de passe et confirmation.
- Caméra intégrée avec aperçu, capture, reprise, mode vêtement/étiquette, galerie, gestion des permissions et du cycle de vie ; lecture de code-barres depuis la caméra, une image ou la saisie du code imprimé.
- Police Inter embarquée avec sa licence OFL pour le rendu hors ligne ; couleurs préférées en pastilles, sensibilité thermique sur un curseur, boutons sans largeur infinie dans les lignes et dialogues.

## Vérifications exécutées

- `flutter analyze` : exit 0, **No issues found**.
- `flutter test --no-pub` : exit 0, **24 tests réussis** après intégration des mannequins finaux (voir `MANNEQUIN_INTEGRATION.md`).
- Backend : `.venv/Scripts/python -m pytest -q -p no:cacheprovider` : exit 0, **34 tests réussis, sans avertissement** après fermeture explicite de la base de test.
- Les tests Flutter utilisent des réponses réseau contrôlées uniquement dans `test/`. Les tests backend exercent les vrais handlers, l'authentification et une base isolée ; les fournisseurs météo/catalogue externes sont doublés dans les tests concernés. Ces résultats ne constituent pas une recette sur un backend déployé avec tous ses fournisseurs.
- Les nouveaux tests vérifient notamment la redirection des visiteurs, l'inscription suivie des préférences, le menu et le profil en largeur 320 px, la récupération directe d'un vêtement, la conservation de ses champs/photos en cache, les erreurs de sauvegarde et de feedback, la copie de l'export, les coordonnées d'une destination et les recommandations vides.
- Les tests complémentaires vérifient la caméra refusée puis autorisée, capture/reprise sur 320 px, libération/reprise de la caméra en arrière-plan, le fichier JSON partagé et le repli sur la copie, ainsi que la sélection d'activité et la génération sur 320 px. Les adaptateurs matériels sont remplacés uniquement dans les tests.
- Backend : brouillon photo archivé puis rendu visible avec le même identifiant ; scan puis confirmation sans doublon ; vêtement → tenue → historique → favori → export → suppression ; destinations, préférences, notifications et choix homme/femme.

## Limites restantes

- Les fonds photographiques du splash et des trois onboardings ne sont pas disponibles comme assets séparés dans le projet. Les illustrations par icônes de l'onboarding existant restent présentes ; elles ne reproduisent pas les photos/montages du PNG.
- Les deux GLB finaux fournis sont intégrés sans modification aux chemins `mannequins/female.glb` et `mannequins/male.glb`. `OutfitComposer` crée maintenant un habillage générique en mémoire avec les catégories/couleurs des vraies pièces. Aucun asset exact de vêtement n’est fourni ; les coupes/motifs restent approximatifs. Voir `PRODUCT_UX_REPORT.md`.
- La sélection des zones utilise les commandes de la silhouette ; la sélection anatomique sur les maillages 3D reste à réaliser avec les véritables modèles.
- Le résultat outfit montre les pièces réelles de la garde-robe plutôt que le mannequin habillé du PNG. L'historique ne dispose pas des mêmes vignettes de mannequin ni des températures/conditions du PNG lorsque l'API ne renvoie pas ces informations.
- La caméra intégrée et le cadre cyan du scanner sont implémentés ; leur rendu natif, le flash et la lecture d'images nécessitent encore une recette Android/iOS.
- Les boutons sociaux Apple/Google du PNG ne sont pas ajoutés : aucune route OAuth correspondante n'existe dans le backend. La création de compte réelle utilise email/mot de passe.
- Le feedback affiche les actions réellement acceptées par le backend ; il n'invente pas un endpoint pour les libellés absents du contrat.
- L'export partage le JSON complet comme fichier et conserve la copie en cas d'échec du partage. Le panneau de partage natif reste à vérifier sur appareil.
- Les documents légaux embarqués reprennent les modèles existants du projet et nécessitent les informations de l'éditeur.
- Aucun appareil Android/iOS n'est connecté. La caméra, le scanner, les permissions natives, le rendu/les gestes 3D et la recette complète sur appareil n'ont pas été validés.
- Les parcours upload/OCR/vision et reconnaissance catalogue nécessitent le stockage S3 et les fournisseurs externes réels configurés. Ils ne sont pas déclarés validés contre ces services.
- Une comparaison visuelle par captures avec la maquette originale reste à effectuer après intégration des assets. La typographie et plusieurs espacements/dispositions restent à ajuster.

## Contrat backend préservé

Les routes et protections existantes sont conservées. Les seuls changements fonctionnels du backend concernent le cycle de brouillon : `is_archived` à la création et `garment_id` dans le résultat du scan. Aucun contrôle d'authentification ou d'autorisation n'a été retiré.

## Fichiers modifiés ou ajoutés

La liste ci-dessous inclut les fichiers Dart reformattés, pas uniquement les changements de comportement. Elle exclut les sorties de build/cache et les métadonnées générées par Flutter.

- `apps/api/app/modules/wardrobe/router.py`
- `apps/api/app/modules/wardrobe/schemas.py`
- `apps/api/app/modules/wardrobe/service.py`
- `apps/api/tests/test_mobile_flows.py`
- `apps/api/tests/conftest.py` (fermeture de la base de test)
- `apps/mobile/android/settings.gradle.kts`
- `apps/mobile/assets/fonts/Inter.ttf`
- `apps/mobile/assets/fonts/OFL.txt`
- `apps/mobile/assets/legal/cgu.md`
- `apps/mobile/assets/legal/mentions-legales.md`
- `apps/mobile/assets/legal/privacy-policy.md`
- `apps/mobile/lib/app.dart`
- `apps/mobile/lib/core/models.dart`
- `apps/mobile/lib/core/network/api_client.dart`
- `apps/mobile/lib/core/providers.dart`
- `apps/mobile/lib/core/router.dart`
- `apps/mobile/lib/core/theme/app_theme.dart`
- `apps/mobile/lib/core/theme/theme_controller.dart`
- `apps/mobile/lib/core/widgets/app_widgets.dart`
- `apps/mobile/lib/features/auth/screens/login_screen.dart`
- `apps/mobile/lib/features/auth/screens/register_screen.dart`
- `apps/mobile/lib/features/auth/screens/welcome_screen.dart`
- `apps/mobile/lib/features/explore/explore_screen.dart`
- `apps/mobile/lib/features/history/history_screen.dart`
- `apps/mobile/lib/features/home/home_screen.dart`
- `apps/mobile/lib/features/home/home_shell.dart`
- `apps/mobile/lib/features/home/menu_drawer.dart`
- `apps/mobile/lib/features/location/destination_screen.dart`
- `apps/mobile/lib/features/location/location_controller.dart`
- `apps/mobile/lib/features/mannequin/mannequin_viewer.dart`
- `apps/mobile/lib/features/onboarding/onboarding_screen.dart`
- `apps/mobile/lib/features/preferences/preferences_screen.dart`
- `apps/mobile/lib/features/recommendation/activity_screen.dart`
- `apps/mobile/lib/features/recommendation/outfit_flow_screen.dart`
- `apps/mobile/lib/features/settings/account_screens.dart`
- `apps/mobile/lib/features/settings/settings_screen.dart`
- `apps/mobile/lib/features/silhouette/silhouette_screen.dart`
- `apps/mobile/lib/features/splash/splash_screen.dart`
- `apps/mobile/lib/features/stats/statistics_screen.dart`
- `apps/mobile/lib/features/wardrobe/screens/add_garment_screen.dart`
- `apps/mobile/lib/features/wardrobe/screens/barcode_scan_screen.dart`
- `apps/mobile/lib/features/wardrobe/screens/garment_detail_screen.dart`
- `apps/mobile/lib/features/wardrobe/screens/photo_screen.dart`
- `apps/mobile/lib/features/wardrobe/screens/wardrobe_screen.dart`
- `apps/mobile/pubspec.yaml`
- `apps/mobile/pubspec.lock`
- `apps/mobile/test/app_test.dart`
- `apps/mobile/test/device_flows_test.dart`
- `apps/mobile/test/mannequin_viewer_test.dart`
- `apps/mobile/test/user_flows_test.dart`
- `docs/UI_IMPLEMENTATION_STATUS.md`
- `docs/3D_ASSET_SPEC.md`
- `docs/MANNEQUIN_INTEGRATION.md`
- `docs/MANNEQUIN_RENDER_CHECK.json`
- Remplacement des assets `apps/mobile/assets/3d/mannequins/female.glb` et `male.glb` ; suppression de `apps/mobile/scripts/generate_placeholder_mannequin.py`.
