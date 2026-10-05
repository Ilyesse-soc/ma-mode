# Audit applicatif et préparation au test local

Date : 5 octobre 2026. Périmètre : projet présent dans `D:\alamode`, Flutter 3.41.4/Dart 3.11, FastAPI/Python 3.13, PostgreSQL, Redis, stockage S3, fournisseurs IA/météo/produits, Docker et workflow GitHub Actions. Backend et contrôles d'autorisation conservés ; aucune donnée fictive n'est utilisée pour remplacer une réponse fournisseur. Les doubles de tests restent dans les tests.

## Architecture et frontières vérifiées

Flutter appelle exclusivement l'origine API configurée ; les secrets JWT/S3/IA/SMTP sont serveur. FastAPI utilise SQLAlchemy, PostgreSQL avec rôle applicatif dédié et Redis partagé pour les quotas/compteurs. Les médias privés sont réservés, décodés, nettoyés et signés pour une durée limitée. Les fournisseurs sortants passent par un transport HTTPS public protégé contre SSRF. Les traitements optionnels IA nécessitent un choix enregistré. La suppression S3 et la rétention utilisent une file SQL durable et un worker.

Local : services séparés des autres projets, liés à localhost, secrets générés et fichiers ignorés `.local`. PostgreSQL et Redis sont réellement exécutés dans Docker ; MinIO est une instance native de test compilée depuis sa source officielle épinglée. Flutter web est réellement compilé et servi sur **http://127.0.0.1:18080**. Mode développement explicite avec authentification, quotas et propriété des données conservés. Créer son propre compte ; aucun compte de démonstration permanent.

## Faiblesses trouvées et corrections

Sévérités qualitatives selon scénario et exposition initiale, pas de CVSS inventé. Les contrôles déjà corrects (SQLAlchemy, mots de passe hachés, nombreuses queries propriétaire) ont été conservés.

| Constat | Sévérité | Correction réalisée |
|---|---|---|
| Access JWT utilisable après révocation de la session | Élevée | Claim sid, contrôle session propriétaire/active/échéance en base sur chaque accès |
| Concurrence refresh/logout et échéance renouvelable | Élevée | Verrou SQL, expiration absolue, détection de rejeu avec révocation, logout d'un ancêtre révoquant les successeurs |
| Plusieurs 401 Flutter et écriture tardive après logout | Élevée | Refresh single-flight, retry unique, génération de session et écritures Secure Storage sérialisées |
| Cache personnel lisible/local et données d'une ancienne session | Élevée | Hive AES, clé Secure Storage, suppression anciens caches, purge/invalidation par utilisateur, exclusion URLs signées |
| Configuration de production permissive / secrets par défaut | Élevée | Settings fail-closed, RSA/CORS/HTTPS/Redis/credentials contrôlés, probes rôle SQL et bucket privé |
| Schémas acceptant champs supplémentaires ou structures/textes excessifs | Élevée | StrictModel, bornes de taille, profondeur, listes, NaN ; données d'entrée exclues des erreurs |
| Upload MIME et propriétés déclaratives insuffisants, EXIF et bombes d'images | Élevée | Décodage et réencodage, tailles/pixels/dimensions, metadata stripping, policy POST et quarantaine |
| Signature S3 fondée uniquement sur préfixe | Élevée | Réservation et attachement en base, vérification propriétaire, clés strictes, TTL court, refus objets étrangers |
| Erasure S3 non durable / upload encore signé après clôture | Élevée | Queue persistante, réessais bornés, double purge différée, nettoyage des orphelins même après échec d'attachement |
| Sorties fournisseur non strictes / exposition SSRF potentielle | Élevée | HTTPS/IP publics épinglés, redirects interdits, plafonds/délais, JSON Pydantic strict, aucun outil/code exécuté |
| Analyses photos sans preuve de choix révocable | Élevée | Consentement ai-v1 en base, contrôle API, écran d'acceptation/retrait et voie manuelle |
| Logs/exception/Sentry susceptibles d'inclure PII ou contexte source | Élevée | Redaction récursive, pas d'access logs, erreurs génériques, payload Sentry réduit et breadcrumbs expurgés |
| Vérification email sans expiration complète et fausse disponibilité d'email | Moyenne | Expiration 24 h, renvoi réel SMTP, reset indisponible explicitement sans SMTP, UI des liens/code |
| Export incomplet | Moyenne | JSON métier/préférences/consents/candidats, ZIP des photos, isolation propriétaire et plafonds sans troncature |
| Coordonnées et metadata conservées sans règles opérationnelles explicites | Moyenne | Arrondi 2 décimales, snapshots 30 jours, audit 90 jours, propositions/uploads 7 jours, purge liens/sessions expirés et OCR historique |
| CI sans tous les gates/scans et release Android signée debug | Élevée | Scans bloquants, actions SHA, hashes dépendances, gate juridique/config, vraie signature Android obligatoire |
| pip 25.3 : cinq avis uniques, dix entrées du scanner | Selon avis | Mise à jour ciblée pip 26.2.1 ; audit final sans vulnérabilité connue |
| Première image Debian : 49 High, 61 Medium, 61 Low, 2 Unknown | Élevée | Base officielle Alpine épinglée, runtime minimal non-root, outils/build/pip exclus ; image finale sans CVE connue détectée |

La présence de secrets existants dans des fichiers runtime ignorés a été constatée. Ils restent exclusivement nécessaires côté serveur ; ils ne sont ni publiés ni affichés dans ce rapport. Les exemples contiennent uniquement les noms. Un historique Git antérieur n'est pas disponible dans cette copie : la rotation d'un secret précédemment publié reste une action externe indispensable si ce cas existe.

## Tests créés et preuves fonctionnelles

- **58 nouveaux cas API sécurité**, dans `apps/api/tests/security/`, en plus des 34 tests fonctionnels existants : auth/JWT, reset et verification expiry, rotation/rejeu/logout, mass assignment, IDOR, quotas, uploads et EXIF, SSRF, URLs signées, export, effacement/réessais, consentement, Sentry, rétention et isolation IA/destinations.
- **6 tests Flutter sécurité** : stockage sérialisé, clé AES stable, refresh concurrent, refus bearer vers origine étrangère, cache sans URL signée, expiration de session et filtre Sentry. Suite totale : **35 tests**.
- `LOCAL_SMOKE_TEST.json` : **8 parcours réussis** avec les véritables PostgreSQL/Redis/S3/API/Open-Meteo ; upload, POST signé/quarantaine, EXIF supprimés, S3 anonyme refusé, IDOR refusé, tenue portée/historique, ZIP avec deux photos, météo, génération et effacement. Comptes temporaires supprimés.
- `LOCAL_ROTATION_CHECK.json` : deux requêtes simultanées sur le vrai PostgreSQL, statuts **200 et 401** ; access du successeur refusé après rejeu. Compte temporaire supprimé.
- `LOCAL_BROWSER_CHECK.json` : Flutter réellement rendu dans Edge 390×844, trois pages d'onboarding et inscription via interface atteignant les préférences ; aucune exception JavaScript relevée pendant ce parcours. Ce test ne couvre pas tous les parcours natifs.
- `BACKUP_RESTORE_CHECK.json` : vraie archive PostgreSQL AES-256-GCM déchiffrée/restaurée en base isolée, schéma et 39 catégories vérifiés. Aucun backup de production revendiqué.
- Image Docker finale : imports API/worker et Argon2id exécutés en non-root, réseau absent, filesystem read-only, capacités supprimées et no-new-privileges. Aucun pip dans le runtime.

## Outils réellement exécutés

| Outil / commande | Résultat final | Preuve |
|---|---|---|
| `ruff check .` | Réussite, zéro erreur | Console finale API |
| `mypy app` | Réussite, 67 fichiers | Console finale API |
| `pytest -q -p no:cacheprovider` | **92 passed**, zéro warning | Cache pytest seul désactivé pour éviter une ACL locale ; aucun test/protection exclu |
| `flutter analyze` | **No issues found** | Log local de commande finale |
| `flutter test` | **30 passed** | Log local de commande finale |
| Flutter web build JavaScript | Réussite | Avertissement dry-run WASM lié à secure_storage_web ; pas de build WASM revendiquée |
| Bandit 1.9.4 | **0 finding** | `bandit.json` |
| Semgrep 1.145.2 | **0 finding**, 6 règles locales, 67 fichiers Python | `semgrep.json` ; ce nombre ne représente pas toutes les règles OWASP |
| pip-audit 2.10.1 | **No known vulnerabilities** | `pip-audit.json` |
| Gitleaks 8.24.3 | **0 secret dans les livrables scannés** | `gitleaks.json` ; runtimes/artefacts ignorés ; empreinte GPG publique Python exclue précisément |
| Trivy 0.69.3 fichiers | **0 CVE / 0 misconfiguration détectée** | `trivy-filesystem.json`, locks Python/Dart et Dockerfile |
| Trivy image finale | **0 CVE détectée**, toutes sévérités | `trivy-image.json`, archive de l'image effectivement reconstruite |
| `flutter pub outdated --json` | Inventaire effectué ; pas de migration majeure aveugle | `flutter-pub-outdated.json` |
| Gate production | **Échec attendu** en mode développement, sans mentions légales/alertes/signature réelles | `SECURITY_VALIDATION_RESULTS.json` |
| YAML CI, XML Android, plist iOS | Syntaxe validée | Contrôle parseurs Python locaux |

Les JSON de scans ont été générés par les outils, pas rédigés comme des résultats fictifs. Les résultats sont ponctuels et dépendent des bases de vulnérabilités. Trivy avertit que son catalogue EOL ne connaît pas encore Alpine 3.24 : aucun statut de support OS n'est déduit de ce scan. Le scan image porte sur l'API, pas sur tous les services de la machine. Semgrep et Trivy n'établissent pas l'absence de faille métier.

## Risques ouverts et infrastructure réelle

1. Android/iOS non exécutés sur appareil : SDK, signature réelle, Keystore/Keychain, backup/restore mobile, caméra/scan/GPS/partage, deep links et performance 3D restent à vérifier. Aucun pinning ou attestation mobile n'est présenté comme opérationnel.
2. SMTP/recipient d'alerte/Sentry distants non configurés. Tests SMTP/Sentry utilisent un transport de test ; pas de preuve de réception d'un vrai email ou événement distant. Mail de compte sans queue durable : une panne de livraison nécessite un renvoi. Supervision externe de worker/Redis indispensable.
3. Vérification de disponibilité du modèle Gemini existant effectuée ; pas de benchmark ou identification photo complète distante validée ici. Quotas financiers fournisseur, conditions de rétention et contrat à renseigner.
4. MinIO local upstream archivé : réservé aux tests ; choisir un stockage maintenu et vérifier IAM minimal, TLS, chiffrement disque/KMS, bucket/CORS/lifecycle/versions, réseau et audit sur le compte réel. La policy temporaire locale expire après un jour ; l'abandon multipart cloud doit être configuré séparément.
5. PostgreSQL TLS avec vérification de certificat est prévu en production ; firewall privé, CA/rotation, accès DBA, sauvegardes hors site/PITR et restauration cloud ne sont pas validés. Les backups locaux ont une clé sur le même hôte.
6. Historique Git absent localement : impossible d'en certifier l'absence de secrets historiques. Workflow full-history et refus des env suivis ajoutés, mais CI GitHub distante non exécutée faute de dépôt configuré. Branch protection/environnement production et secrets du compte à appliquer.
7. Aucun WAF/CDN anti-DDoS, antivirus cloud ou test d'intrusion indépendant exécuté. Les plafonds protègent l'application mais une forte concurrence d'Argon2 ou de ZIP nécessite une mesure de capacité et une protection infrastructure.
8. Export au-delà des limites exige un support opérationnel ; effacement physique S3 dépend du worker et du stockage. Sauvegardes et prestataires doivent disposer de règles d'expiration/effacement vérifiées.
9. La maquette contient des assets visuels et vêtements 3D non fournis ; le travail cybersécurité ne transforme pas les GLB en véritables tenues 3D. Voir `UI_IMPLEMENTATION_STATUS.md` et `MANNEQUIN_INTEGRATION.md` pour les limites visuelles/natives.

## Validation juridique obligatoire

Les mentions légales restent des modèles, le gate de publication les bloque. Renseigner l'éditeur, l'adresse, les contacts droits/DPO, l'hébergeur et les stores ; faire valider les bases légales, DPA/transferts, rétentions distantes, notifications de violation et nécessité d'AIPD. Aucune certification OWASP ni déclaration de conformité RGPD n'est délivrée.

Documents associés : `THREAT_MODEL.md`, `API_SECURITY.md`, `MOBILE_SECURITY.md`, `RGPD_COMPLIANCE.md`, `BACKUP_AND_RECOVERY.md`, `INCIDENT_RESPONSE.md`, `LOCAL_TESTING.md`, `SECURITY_CHANGED_FILES.md`.
