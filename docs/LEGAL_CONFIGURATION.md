# Configuration légale — À RENSEIGNER AVANT PUBLICATION

Les documents dans `docs/legal/` contiennent des placeholders. **Ne pas publier
l'application sans les remplacer.** Aucune information légale n'a été inventée.

## Placeholders à compléter

| Placeholder | Signification | Où |
|---|---|---|
| `[LEGAL_COMPANY_NAME]` | Raison sociale de l'éditeur | privacy-policy.md, cgu.md, mentions-legales.md |
| `[LEGAL_ADDRESS]` | Adresse du siège | mentions-legales.md, privacy-policy.md |
| `[LEGAL_EMAIL]` | Contact légal | tous |
| `[DPO_EMAIL]` | Délégué à la protection des données (si applicable) | privacy-policy.md |
| `[HOSTING_PROVIDER]` | Hébergeur (nom + adresse) | mentions-legales.md, privacy-policy.md |
| `[APP_STORE_NAME]` | Nom public de l'app | tous |

## Checklist pré-publication

- [ ] Remplir tous les placeholders ci-dessus
- [ ] Faire relire par un juriste (CGU + politique de confidentialité)
- [ ] Enregistrer les traitements au registre RGPD interne
- [ ] Configurer l'hébergeur réel (`[HOSTING_PROVIDER]`)
- [ ] Vérifier les écrans de consentement (localisation, photos) — textes en français clair
- [ ] Sign in with Apple **obligatoire** sur iOS si un login social tiers est ajouté
- [ ] Publier la politique de confidentialité sur une URL publique (exigence App Store / Play Store)
- [ ] Renseigner les questionnaires « Données collectées » App Store Connect / Play Console en cohérence avec [PRIVACY.md](PRIVACY.md)

## Fichiers

- [legal/privacy-policy.md](legal/privacy-policy.md) — Politique de confidentialité
- [legal/cgu.md](legal/cgu.md) — Conditions générales d'utilisation
- [legal/mentions-legales.md](legal/mentions-legales.md) — Mentions légales
