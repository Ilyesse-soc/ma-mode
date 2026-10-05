# Confidentialité

La description actualisée des données, rétentions, consentement IA et droits est dans [RGPD_COMPLIANCE.md](RGPD_COMPLIANCE.md). La politique affichée dans Flutter provient de `apps/mobile/assets/legal/privacy-policy.md`.

Les coordonnées GPS précises servent temporairement au géocodage IGN/BAN et à la météo ; elles ne sont pas conservées telles quelles. Les coordonnées arrondies sont persistées dans les destinations et snapshots : il serait incorrect de déclarer qu'aucune coordonnée n'est enregistrée. Le worker applique 30 jours aux snapshots, 90 jours à l'audit et 7 jours aux uploads non attachés.

Export JSON `/api/v1/privacy/export` ou ZIP avec photos `/api/v1/account/export`, retrait du choix IA et suppression de compte avec purge S3 durable sont implémentés. Les textes restent des modèles bloqués à la publication tant que l'identité légale, les prestataires et la validation juridique manquent.
