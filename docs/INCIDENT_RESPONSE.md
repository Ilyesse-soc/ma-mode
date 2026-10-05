# Réponse aux incidents

Responsable, suppléant, astreinte, coordonnées et prestataires à renseigner avant production. Les alertes agrégées détectent 5xx, 401/403, échecs login, rejeu refresh et erreurs DB/S3/IA ; les seuils sont dans `app/core/monitoring.py`. Tester les vrais canaux SMTP/Sentry avant ouverture.

Étapes communes : horodater le début, contenir, préserver preuves expurgées à accès restreint, déterminer périmètre/impact, corriger et tourner les accès, vérifier, réouvrir progressivement, rédiger retour d'expérience. Éviter d'invalider les preuves ou de copier des données personnelles dans un ticket public.

| Incident | Confinement immédiat | Rétablissement et vérification |
|---|---|---|
| Secret fournisseur/S3/SMTP exposé | Révoquer la clé chez le fournisseur, limiter egress/IAM, désactiver la fonction touchée | Générer une nouvelle clé via secret manager, inspecter usage et coûts ; Gitleaks historique complet |
| Clé JWT compromise | Bloquer temporairement l'auth, remplacer paire RSA, révoquer toutes les sessions | Redéployer, vérifier refus anciens tokens et accès normal après reconnexion ; informer selon impact |
| Refresh/compte compromis | Révocation des sessions, reset vérifié et assistance utilisateur | Contrôler audit/objets modifiés, restaurer les données autorisées, tester login/rejeu |
| Bucket public | Retirer public ACL/policy, couper signatures si nécessaire, conserver audit cloud | Vérifier accès anonyme refusé, IAM minimal, objets et traces téléchargées ; traiter divulgation possible |
| Base compromise | Isoler réseau/rôle, préserver backup/forensic chiffrés | Rotation DB/JWT/provider, restaurer snapshot sain en isolement et rejouer effacements ; ne pas réouvrir une base altérée |
| Abus ou injection IA | Révoquer provider key si nécessaire, désactiver analyses distantes, garder saisie manuelle | Examiner compteurs/quota et validation des sorties ; ne jamais exécuter le contenu hostile |
| Dépendance vulnérable | Évaluer version réellement exploitée, bloquer release, mitigation ciblée | Mise à jour contrôlée, lock hashes, scans et tests ; reconstruire image et artefacts |
| Indisponibilité stockage/Redis/SQL | Restreindre fonctions affectées, maintenir refus fail-closed, superviser worker | Tester readiness, réessais de suppression et cohérence ; ne pas remplacer par données fictives |

Si violation de données personnelles : faire déterminer par le responsable/DPO les obligations et délais de notification (notamment RGPD 72 h lorsque applicable), les personnes concernées et la documentation. Le code ne prend aucune décision juridique ni n'envoie automatiquement de notification réglementaire.

Référence réglementaire : [CNIL — règles de notification des violations](https://www.cnil.fr/fr/violations-de-donnees-personnelles-les-regles-suivre).
