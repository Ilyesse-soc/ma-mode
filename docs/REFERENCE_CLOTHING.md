# Habillage 3D : look de la maquette

Cette correction remplace le mode C de la V2 dans les catégories prises en charge : les pièces sélectionnées habillent désormais réellement le mannequin, au lieu d'être uniquement affichées à côté. La référence visuelle est le hoodie clair sous une veste noire ouverte, le cargo noir et les baskets blanches de l'image fournie. Le fond est un studio gris avec une lumière neutre et une ombre au sol ; les commandes 360°, zoom et recentrage disposent d'une bande réservée sous la figure.

## Composants et données

- `ClothingSpec` transforme les catégories et couleurs des vêtements appartenant au compte en une sélection de maillages préparés. Il respecte les emplacements et superpositions de `DressingSelection`.
- `MannequinViewer` charge `assets/3d/clothing/male-dressing.glb` ou `assets/3d/clothing/female-dressing.glb` lorsqu'une pièce compatible est sélectionnée. Sans pièce compatible, le modèle d'origine reste utilisé.
- `ClothingSpec.runtime` et `web/clothing-runtime.js` appliquent les couleurs et masquent les pièces non sélectionnées au moyen de l'API publique de matériaux de [model-viewer](https://modelviewer.dev/examples/scenegraph/). Le test de parité couvre les deux adaptations.
- `MannequinScreen`, `OutfitStage` et les trois propositions utilisent le même composant de rendu. Le bouton d'habillage, le glisser-déposer, le retrait et le remplacement changent les maillages visibles.
- La première tenue proposée dans le dressing utilise seulement des pièces réellement possédées, en privilégiant les catégories et couleurs de la référence. Les emplacements manquants restent vides ; aucun vêtement de démonstration n'est ajouté au backend.
- Une modification de couleur ou de catégorie dans la garde-robe rafraîchit aussi la sélection. Une suppression retire la pièce du rendu et invalide l'identifiant de tenue sauvegardée.
- Les sauvegardes et le suivi de port continuent de transmettre les véritables identifiants des pièces aux routes API existantes, avec les mêmes contrôles d'appartenance.

## Assets

Les sources `assets/3d/mannequins/male.glb` et `female.glb` restent inchangées. Les assets d'habillage réutilisent exactement leurs positions, normales, matériaux et données binaires ; une copie du maillage de rendu partage ces données et répartit ses indices par régions. Les surfaces couvertes sont masquées pour éviter que le corps et le sous-vêtement traversent le vêtement. Le torse central reste visible sous une veste ouverte lorsqu'aucun haut intérieur n'est sélectionné.

Onze modèles de vêtements ont été préparés localement dans Blender : T-shirt, pull, hoodie, veste ouverte, pantalon, cargo, short, jupe, robe, baskets et bottes. Les formes sont adaptées séparément aux deux profils ; coutures, épaisseurs, poches, cordons et semelles font partie des maillages. La texture textile et la géométrie ajoutées sont originales au projet, sans fournisseur externe ni génération payante.

La préparation est reproductible avec `scripts/build_reference_clothing.py` puis `scripts/package_reference_clothing.py`. Le premier écrit uniquement les vêtements et vues de contrôle dans `.tmp/reference-clothing` ; le second ajoute les vêtements à de nouveaux assets, contrôle la conservation du corps et enregistre les empreintes dans `REFERENCE_CLOTHING_ASSETS.json`. La préparation n'a pas lieu sur le téléphone.

Les deux assets d'habillage font environ 5,6 et 4,8 Mio, avec moins de 60 000 triangles supplémentaires pour l'ensemble des variantes de chaque profil. Ils utilisent le cache du moteur ; aucun GLB n'est reconstruit ni encodé en base64 au changement de tenue. Le composant est remonté lors d'un changement réel de coupe ou de couleur, car le plugin Flutter n'applique pas les nouveaux paramètres JavaScript à une vue déjà créée.

## Vérification

- `flutter analyze` : aucune anomalie.
- `flutter test` : 53 tests réussis, dont conservation des données GLB, sélection depuis la vraie garde-robe, remplacements, retraits, mise à jour des couleurs, suppression de pièces, validation des couleurs, isolation des chemins et parité Web/natif.
- Build Flutter Web classique réussi. Les avertissements du contrôle WebAssembly concernent le stockage sécurisé Web déjà utilisé par le projet ; aucun build Wasm n'est activé.
- Le rapport `REFERENCE_CLOTHING_BROWSER_CHECK.json` contient 25 contrôles réussis, sans exception JavaScript, sur le moteur 3D et l'API locale réels, avec un compte temporaire supprimé après les contrôles. Il couvre les deux profils, la sélection, le glisser-déposer réel, la rotation, le zoom, le recentrage de face après rotation automatique, les remplacements, les retraits, la sauvegarde, l'historique et l'erreur d'un véritable GLB absent.
- Aucun fichier `.env`, token, clé privée ou compte utilisateur réel n'est incorporé aux assets ou rapports.

Captures de l'application locale : [profil homme](REFERENCE_CLOTHING_MALE.png), [profil femme](REFERENCE_CLOTHING_FEMALE.png), [vue de dos](REFERENCE_CLOTHING_BACK.png).

## Différences restantes

Le look de vêtements est représenté, mais le résultat reste stylisé. Le visage du mannequin fourni est conservé ; il ne devient pas le personnage humain photoréaliste de l'image. Les plis et les coupes ne reconstituent pas exactement les produits photographiés, les logos ou les références commerciales.

Certaines catégories partagent une représentation approchée : chemise vers pull, manteau/doudoune/blazer vers veste, jean/jogging vers pantalon. Les accessoires et sandales sans modèle adapté restent dans la tenue et dans leur fiche photo/illustration, sans maillage inventé ni affirmation d'essayage exact. Une couleur non reconnue utilise une teinte neutre. Les motifs ne sont pas reconstruits à partir des photos.

La rotation, le zoom et les contrôles de chargement ont été vérifiés dans Flutter Web. La variante native partage les mêmes données et le même code de matériaux ; ses performances et ses gestes restent à contrôler sur un appareil Android/iOS réel. La caméra revient à sa position initiale lorsqu'une nouvelle sélection impose le remontage de la vue.
