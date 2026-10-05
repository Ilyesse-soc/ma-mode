# Sauvegarde et reprise

## Preuve locale effectuée

`scripts/backup_and_restore_local.py` a exécuté un vrai `pg_dump` du projet Docker **dressly-local**, chiffré l'archive en AES-256-GCM, déchiffré puis restauré avec `pg_restore` dans une nouvelle base isolée. Le schéma et les 39 catégories de référence ont été vérifiés ; la base de contrôle et les dumps en clair ont été supprimés. Voir `BACKUP_RESTORE_CHECK.json`.

L'archive et la clé locales sont dans `.local`, ignorée et non livrée. Elles sont sur la même machine : cette preuve de restauration ne représente **pas** une séparation de clés ou un backup hors site. Les autres projets Docker n'ont pas été modifiés.

## Plan de production à mettre en place

1. Sauvegarde PostgreSQL quotidienne chiffrée et PITR/WAL si le service le permet ; proposer RPO 24 h / RTO 4 h puis faire approuver ces objectifs.
2. Stockage hors compte/région principale, chiffrement avec clé KMS séparée et rôle de restauration restreint. IAM du runtime sans droits de supprimer les backups. Proposition de rétention 30 jours à valider juridiquement.
3. Politique de backup/versioning des photos séparée, suppression/expiration des versions conformément aux droits utilisateurs ; le versioning ne doit pas empêcher l'effacement.
4. Test mensuel sur infrastructure isolée : vérifier intégrité, migrations, clés, liens d'images, nombre d'objets et parcours authentifiés. Chronométrer et enregistrer le résultat sans données personnelles.
5. Après restauration, rejouer le registre d'effacement, invalider les sessions et tokens compromis, purger les objets correspondants avant réouverture. Ne pas réintroduire un utilisateur supprimé.

Aucun scheduler cloud, PITR, backup S3, RPO/RTO réel ou restauration de production n'a été validé. Ces points exigent l'infrastructure de l'utilisateur. Ne pas envoyer un dump ou la clé de chiffrement dans Git, l'APK, les logs ou Sentry.
