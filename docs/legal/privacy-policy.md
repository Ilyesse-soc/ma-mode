# Politique de confidentialité

> DOCUMENT MODÈLE : mentions à renseigner et validation juridique obligatoire avant publication.

**Éditeur** : [LEGAL_COMPANY_NAME], [LEGAL_ADDRESS] — [LEGAL_EMAIL]
**DPO / contact droits** : [DPO_EMAIL]
**Hébergeur** : [HOSTING_PROVIDER]

## Données et finalités

Le compte contient prénom, email et un hash Argon2id du mot de passe. La présentation homme/femme sert au mannequin. Les préférences, vêtements, photos, tenues, historique et feedback servent à organiser la garde-robe et proposer des tenues explicables.

La localisation est facultative : une ville peut être saisie manuellement. Les coordonnées GPS précises restent temporairement en mémoire et sont transmises au prestataire météo ainsi qu’au service de géocodage IGN/BAN pour déterminer la commune. Elles sont arrondies à deux décimales avant enregistrement en base. Les destinations choisies et la météo associée aux tenues peuvent être conservées ; les snapshots météo expirent après 30 jours.

Les photos sont réencodées sans métadonnées EXIF/GPS. Une analyse IA externe exige votre choix explicite, enregistré et révocable dans Confidentialité. La saisie manuelle reste disponible. Le retrait empêche de nouvelles analyses et ne supprime pas une transmission déjà effectuée.

## Destinataires

Hébergeur et stockage [HOSTING_PROVIDER], prestataire météo (coordonnées nécessaires à la requête), fournisseur produits et fournisseur IA configuré (photo lorsque vous autorisez et lancez une analyse). SMTP traite les emails de compte ; Sentry, s'il est activé, reçoit une télémétrie expurgée. Les fournisseurs exacts, régions, durées distantes et garanties de transfert doivent être précisés ici avant publication. Aucune vente de données n'est prévue par l'application.

## Droits et conservation

Vous pouvez modifier votre profil et préférences, retirer le choix IA, exporter vos données et photos en ZIP, ou supprimer le compte avec confirmation du mot de passe. Contact : [DPO_EMAIL]. Réclamation auprès de la CNIL.

Les données métier attachées restent pendant la durée du compte. Les propositions d’identification temporaires et les uploads non attachés expirent après 7 jours, la quarantaine temporaire après 1 jour, les snapshots météo après 30 jours et l'audit de sécurité après 90 jours. À la clôture, les données SQL et sessions sont supprimées, l'audit est anonymisé et les photos sont placées dans une file de suppression durable avec réessais. Une deuxième purge intervient après expiration des URLs d'upload encore valides. Une panne de stockage peut retarder la suppression physique.

Les limites d'export sont 10 000 lignes par collection et 20 Mio par ZIP ; un export plus grand nécessite le contact support. Les sauvegardes et rétentions des sous-traitants doivent être documentées avant production ; l'application ne garantit pas leur effacement instantané.

## Sécurité et bases légales

Tokens courts, rotation/révocation des sessions, stockage privé des photos, contrôles propriétaire, limites d'abus et chiffrement du cache mobile sont implémentés. HTTPS est requis en production. Les bases légales de chaque traitement et les contrats de sous-traitance sont à valider par le responsable de traitement ; ce modèle ne vaut pas attestation de conformité.
