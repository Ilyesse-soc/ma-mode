# Finition premium V2

Cette version remplace la composition procédurale décrite dans le précédent rapport de finalisation. Les vêtements gonflés ou déformés ont été supprimés du code de production ; les GLB fournis restent inchangés.

## Connexion

Carte centrée de largeur maximale 440 px, fond sombre, titre Playfair Display, sous-titre demandé, champs avec icônes et visibilité du mot de passe, validation sous les champs et bouton de 54 px. Les champs et les soumissions sont désactivés pendant la requête. Les quatre actions d’aide sont regroupées dans une section déroulante et conservent leurs vraies routes API. Le pied de page revient à la création de compte. Le retour ouvre l’accueil de connexion.

## Prévisualisation du mannequin

Mode C : le véritable mannequin est accompagné des images des pièces sélectionnées, avec une mention explicite de l’absence d’essayage 3D exact. Il ne porte aucun vêtement fabriqué à partir d’une photo ou d’une simple catégorie. `OutfitStage` partage ce rendu entre résultat, vue 3D et feedback ; `MannequinScreen` présente aussi un rail de pièces sélectionnées. La sélection, les zones de dépôt, les remplacements et la sauvegarde continuent d’utiliser les identifiants des vêtements appartenant au compte.

`MannequinViewer` charge exclusivement les modèles ci-dessous. Il conserve rotation, zoom, caméra centrée, éclairage neutre, fond dressing, état de chargement, erreur et nouvelle tentative. Le bouton HTML « Recentrer » agit sur le véritable moteur `<model-viewer>` ; son équivalent natif est installé par `statusJs`, et le Web par `web/mannequin-runtime.js`.

| Profil | Asset final | SHA-256 |
| --- | --- | --- |
| Femme | `apps/mobile/assets/3d/mannequins/female.glb` | `8e311f5d3e94a825dd6ceeed1f8b95a23e47977892c7007b3bc92ad6737f029b` |
| Homme | `apps/mobile/assets/3d/mannequins/male.glb` | `70b444911129ffa237f071544c7885b0994f3ef993ac10ca2dd23d91b9c00485` |

Les deux fichiers conservent `Mannequin_Body`, `Mannequin_Briefs` et leurs matériaux. Aucun modèle de vêtement 3D ajusté ou riggé n’a été ajouté. Les modes A et B ne sont donc pas annoncés comme disponibles. Le changement de pièces ne reconstruit plus le GLB ni ne crée une copie en base64.

## Import d’image

Les cinq cartes d’ajout sont, dans l’ordre : code-barres, photo du vêtement, photo de l’étiquette, import d’image et saisie manuelle. Leur iconographie, espacement et texte d’aide ont été harmonisés.

`ImportImageScreen` ouvre un vrai sélecteur de galerie, un sélecteur de fichier ou la galerie pour choisir une capture déjà enregistrée. Il ne prend pas automatiquement une capture du téléphone. Le fichier est limité à 10 Mo et décodé avant acceptation ; l’aperçu précède tout envoi ou analyse. Le sélecteur de fichiers utilise le [plugin officiel Flutter file_selector](https://pub.dev/packages/file_selector).

Après confirmation, l’image passe par le stockage privé existant : upload temporaire, contrôle d’appartenance, décodage serveur, suppression des métadonnées et attachement au brouillon archivé. L’IA reste optionnelle et soumise au consentement. Une panne d’IA conserve la photo et permet la saisie manuelle. Une panne d’envoi propose une nouvelle tentative ou une continuation explicite sans image ; elle n’est jamais présentée comme un import réussi.

L’extraction peut proposer catégorie, couleur, marque lisible, nom descriptif, référence réellement imprimée, matière estimée, styles, coupe, logo visible et détails distinctifs. Les marques non vérifiées restent indiquées comme supposées dans les cartes et le détail, y compris hors connexion. Leur confirmation est explicite et ne transforme pas le produit en correspondance exacte.

## Recherche et candidats

La recherche textuelle utilise les fournisseurs réellement configurés, à partir des informations cumulées : marque, référence, nom, catégorie, couleur et rayon homme/femme/mixte. Le catalogue local configuré est UPCitemdb. Il ne s’agit pas d’une recherche universelle ni d’une recherche inversée garantissant un modèle exact. Les limites du fournisseur restent respectées.

Les candidats gardent image disponible, nom, marque, source et score. L’utilisateur peut sélectionner une proposition, parcourir les autres, refuser les candidats ou affiner la recherche avec des informations, une photo d’étiquette, une photo du logo ou une capture supplémentaire. Le score de concordance mesure les critères comparables ; il n’est pas une probabilité d’identité. Une simple confirmation d’une proposition visuelle ne suffit pas à activer `exact_match`. Seul un identifiant catalogue effectivement concordant, actuellement le code-barres, peut le faire.

En l’absence de résultat satisfaisant, « Enregistrer comme vêtement personnalisé » ou « Continuer avec une version approchée » conserve la photo validée et les détails vérifiés. Le vêtement devient une vraie entrée non archivée de la garde-robe, utilisable par la sélection du mannequin et le moteur de recommandations.

## Données et protections

La migration `import_v2_20261006` ajoute uniquement `garments.import_metadata`. Les métadonnées conservent la provenance, la clé privée de l’image nettoyée, les attributs détectés, la requête de recherche, les candidats, la décision et la nature du secours. Les URL signées ne sont pas conservées comme origine. Le cache mobile ne conserve que les indicateurs de provenance et de vérification ; il exclut la clé d’image et les URL de candidats. Les exports de données existants incluent ces informations appartenant au compte.

Les clients ne peuvent pas injecter `import_metadata` ou déclarer arbitrairement une correspondance exacte dans un PATCH. Les nouvelles routes restent authentifiées et protégées par l’appartenance du vêtement. Aucune protection de session, autorisation, consentement, upload ou quota n’a été désactivée. Les fichiers `.env` locaux restent exclus du dépôt ; les exemples existants restent les seuls fichiers d’environnement publiables.

Le lanceur local détecte aussi les registres de plugins Web obsolètes, afin qu’un nouveau plugin ne soit pas oublié dans un build incrémental.

## Vérification

- `flutter analyze` : aucune anomalie.
- `flutter test` : 46 tests réussis.
- Ruff : réussi ; mypy : aucune anomalie sur 69 fichiers ; pytest : 120 tests réussis.
- Bandit : aucun résultat, voir `bandit-v2.json`.
- Les tests isolés couvrent validation et attente de connexion, aperçu avant upload, panne de stockage, absence de candidat, IA indisponible, plusieurs candidats, correspondance d’identifiant, provenance persistante, marque supposée, contrôle d’accès et cache sans URL privée.
- 25 validations navigateur ont reussi, sans exception JavaScript. Le contrôle navigateur utilise une vraie application Flutter Web et le vrai backend local, avec des comptes temporaires supprimés à la fin. Son détail est dans `PREMIUM_V2_BROWSER_CHECK.json` ; ses limites sont distinguées des tests avec doubles de fournisseurs.

## Limites

L’essayage exact et des catégories de vêtements 3D de qualité nécessitent des assets adaptés aux deux silhouettes. Une photographie ne suffit pas à les produire. La disponibilité de l’IA et la couverture du catalogue dépendent des fournisseurs et de leurs quotas ; aucun résultat n’est fabriqué pour masquer ces limites. Aucun téléphone Android ou iPhone physique n’est connecté ici : gestes natifs, permissions et performances mobiles restent à valider sur appareil. La livraison des emails d’aide à la connexion nécessite toujours une configuration SMTP réelle.

L’application locale est servie sur `http://127.0.0.1:18080`, avec l’API sur `http://127.0.0.1:18000`. Le build Web classique fonctionne ; le mode WebAssembly reste limité par la version actuelle du stockage sécurisé Web et n’est pas utilisé pour ce test.

Le test externe supplementaire (image de splash vers Gemini) a ete bloque par le controle automatique : autorisation du fichier et de sa destination requise. Aucun envoi effectue. Les scenarios IA et catalogue sont couverts par des doubles isoles dans les tests backend ; aucune simulation en production.
