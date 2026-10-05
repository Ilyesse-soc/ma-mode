# Tester Dressly en local

Application : **http://127.0.0.1:18080**. API : `http://127.0.0.1:18000/health` et `/readiness`. Les services sont liés à localhost ; aucun déploiement public n'est effectué.

Créer son compte depuis l'application, compléter ses préférences, ajouter ses propres vêtements, puis générer une tenue. Aucun compte ou vêtement de démonstration n'est injecté. Seules les catégories métier officielles sont amorcées. L'inscription locale fonctionne sans SMTP ; en production la vérification email est obligatoire.

## Démarrer / arrêter

Depuis PowerShell dans `D:\alamode`, Docker Desktop démarré et Flutter dans PATH :

```powershell
.\scripts\start-local.ps1
```

Le script conserve les secrets locaux générés, démarre PostgreSQL/Redis et MinIO privé, applique les migrations, amorce le catalogue, lance API et worker, exécute `flutter analyze` et `flutter test`, puis compile/sert Flutter web. `-SkipChecks` évite seulement de répéter ces contrôles de développement ; il ne modifie aucune protection API.

```powershell
.\scripts\stop-local.ps1
```

L'arrêt conserve les volumes et ne cible que ce projet. Les fichiers `.local/*.env` et les clés sont ignorés : ne pas les partager. Diagnostics `.local/*.log`, `.local/*.error.log` ; aucun token/email/mot de passe n'est nécessaire dans un rapport d'erreur.

Préparation déjà effectuée sur cette machine : venv Python et dépendances verrouillées, Flutter web, PostgreSQL sur 15432, Redis sur 16379, API sur 18000, S3 privé sur 19000, console locale sur 19001. MinIO a été compilé depuis une source officielle épinglée et vérifiée ; `scripts/build_local_minio.py` permet de reconstruire le binaire absent. Le projet upstream étant archivé, cette instance est réservée aux tests locaux ; choisir un stockage S3 maintenu pour la production.

## Ce qu'il faut tester avec ses données

- Inscription, connexion, logout ; préférences homme/femme et bons GLB.
- Garde-robe vide, ajout manuel ou photo, détail/modification, retrait d'un vêtement.
- Destination et météo, génération avec un haut/bas/chaussures disponibles, explication, enregistrement, port et historique. Une tenue juste portée peut être exclue des nouvelles suggestions.
- Confidentialité : accepter/refuser l'analyse IA, retirer son choix, export ZIP contenant JSON/photos, suppression du compte avec mot de passe.
- Vue 3D : rotation, zoom et recentrage ; « Mon mannequin » permet zones tactiles, filtres, choix/remplacement/retrait des vraies pièces, sauvegarde et port. L’habillage représente génériquement catégorie/couleur, sans reproduire les coupes ou motifs exacts.

La clé IA existante est conservée côté serveur ; des analyses réelles de photo et d’étiquette ont réussi avec Gemini, sans garantie d’identification pour chaque photo. SMTP, alertes et Sentry distants ne sont pas configurés : récupération email indisponible explicitement, sans faux envoi. Configurer ces comptes dans `.local/api.env` pour les tester.

Le navigateur ne remplace pas une validation Android/iOS : stockage sécurisé natif, caméra/scan/GPS, partage, deep links, rendu/performance 3D et build release restent à vérifier sur appareil. Pour un téléphone, ne pas remplacer le backend par `127.0.0.1` du téléphone : utiliser un environnement de test TLS configuré et un `API_BASE_URL` approprié, sans exposer les secrets locaux.

## Vérifications reproductibles

```powershell
apps\api\.venv\Scripts\python.exe scripts\smoke_local.py
apps\api\.venv\Scripts\python.exe scripts\backup_and_restore_local.py
apps\api\.venv\Scripts\python.exe scripts\security_release_check.py
```

Le smoke crée deux comptes temporaires, teste les véritables services et supprime ses comptes. Le gate production **doit échouer** en développement et tant que les mentions légales/paramètres externes manquent.

Source de statut MinIO : [dépôt officiel archivé](https://github.com/minio/minio).
