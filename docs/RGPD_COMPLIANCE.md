# Données personnelles et conformité à valider

Ce document décrit le code exécuté, sans attester une conformité juridique. Les bases proposées doivent être validées par le responsable de traitement et son conseil.

| Données réelles | Usage | Base envisagée, à valider | Conservation implémentée |
|---|---|---|---|
| Prénom, email, hash du mot de passe | Compte et authentification | Exécution du contrat | Durée du compte ; effacement SQL à la clôture |
| Sessions / liens de compte hachés | Accès et récupération | Contrat / sécurité | Access 15 min, refresh 30 jours maximum absolu, reset 1 h, vérification 24 h ; lignes de session supprimées un jour après expiration absolue ; hashes de liens expirés purgés |
| Présentation homme/femme, styles, couleurs, confort | Affichage et recommandations | Contrat | Durée du compte ; modifiable et exportable |
| Photos JPEG sans EXIF, vêtements, références, candidats IA structurés | Garde-robe et identification | Contrat ; analyse IA facultative soumise à choix explicite | Photos attachées jusqu'à suppression ; propositions IA et uploads non attachés 7 jours, quarantaine temporaire S3 1 jour |
| Choix IA ai-v1, acceptation/retrait horodatés | Autoriser l'analyse distante | Consentement à confirmer juridiquement | Durée du compte ; retrait immédiat pour les prochaines analyses |
| Coordonnées arrondies à 2 décimales et libellés | Météo, destinations, tenue | Permission / base à valider | Snapshots météo 30 jours ; destinations/historique jusqu'à suppression |
| Tenues, feedback, chaleur apprise | Recommandations explicables | Contrat / intérêt légitime à valider | Durée du compte |
| Audit pseudonymisé, événements de sécurité | Détection des abus | Intérêt légitime à documenter | 90 jours ; identité anonymisée à l'effacement |
| Notification preferences / identifiant push éventuel | Notifications | Choix utilisateur | Durée du compte ; token non exporté, supprimé avec le compte |

Le worker `apps/api/scripts/cleanup.py --loop` applique les rétentions. Les limites sont configurables dans les bornes de Settings. Les vêtements archivés ne sont pas assimilés automatiquement à des uploads abandonnés.

## Droits réellement disponibles

- Consultation/rectification via profil, préférences, vêtements et destinations.
- `GET /api/v1/privacy/export` : JSON de l'utilisateur ; `GET /api/v1/account/export` : ZIP JSON et photos. Hashes de mot de passe, tokens de session et clés fournisseur exclus. Au-delà de 10 000 lignes par collection ou 20 Mio, réponse 413 ; prise en charge support à organiser, sans troncature silencieuse.
- `DELETE /api/v1/me` avec mot de passe : effacement des tables personnelles, révocation immédiate et purge durable S3 ; seconde passe après expiration des uploads signés. Un stockage indisponible retarde la suppression physique avec réessais.
- Retrait du choix IA via confidentialité ; saisie manuelle disponible. Le retrait ne peut pas annuler une transmission déjà effectuée.

## Sous-traitants, transferts et formalités externes

Documenter les contrats/DPA et régions du véritable hébergeur, S3, SMTP, IA (Gemini configuré localement), Open-Meteo/alternative météo, fournisseur produits et Sentry si activé. Les fournisseurs reçoivent uniquement les données nécessaires ; l'IA reçoit une photo réencodée après consentement. Aucune durée de rétention distante, absence d'entraînement ou localisation UE n'est présumée. Vérifier ces paramètres contractuellement, SCC/transferts hors EEE et nécessité d'une AIPD.

Renseigner les mentions `[LEGAL_*]`, `[DPO_EMAIL]`, `[HOSTING_PROVIDER]`, `[APP_STORE_NAME]`, publier les textes validés et mettre en place un contact/délai de traitement des demandes. Le gate de publication bloque les mentions non renseignées. Les sauvegardes de production doivent expirer et les comptes supprimés doivent être ré-effacés après restauration. Aucun calendrier cloud n'a été installé ni validé ici.
