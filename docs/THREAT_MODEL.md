# Modèle de menaces — Dressly

État au 5 octobre 2026. Périmètre : Flutter, API FastAPI, PostgreSQL, Redis, stockage S3, météo, produits, IA, CI. Les contrôles implémentés sont distincts des contrôles d'infrastructure non vérifiés. STRIDE : S usurpation, T altération, R répudiation, I divulgation, D indisponibilité, E élévation.

| Actif / STRIDE | Scénario | Impact | Probabilité initiale | Risque initial | Mesure | État / limite |
|---|---|---|---|---|---|---|
| Compte S/E | Credential stuffing, reset détourné | Élevé | Élevée | Élevé | Argon2id, limitations Redis IP/identité, réponses neutres, liens expirables à usage unique | Tests API ; SMTP réel à configurer |
| Sessions S/T | Vol de refresh, double renouvellement | Élevé | Moyenne | Élevé | Hash serveur, rotation verrouillée, détection de rejeu, sid vérifié en base, révocation immédiate | Tests ; pas de protection absolue d'un terminal compromis |
| Objets métier I/E | Identifiant d'un autre compte | Élevé | Élevée | Élevé | Filtrage propriétaire, 404, schémas interdisant champs supplémentaires | Tests garde-robe, images, tenues, destinations, IA, export |
| Photos T/D/I | Faux MIME, bombe pixels, EXIF GPS, fichier polyglotte | Élevé | Élevée | Élevé | Décodage réel, plafonds 10 Mio/20 Mp/8192 px, réencodage JPEG sans métadonnées | Tests ; antivirus externe non installé |
| S3 I/E | Bucket public, clé arbitraire, URL permanente | Élevé | Moyenne | Élevé | Vérification ACL/politique en production, namespace, propriété en base, URL 10 min, POST borné et quarantaine | MinIO local privé testé ; IAM/cloud externes à vérifier |
| IA T/I/D | Injection dans une étiquette, sortie inventée, coût abusif | Élevé | Élevée | Élevé | Consentement, données non fiables séparées, aucun outil/exécution, JSON strict, 600 tokens, délais/tailles/quotas | Tests validation/ownership ; analyse distante complète non mesurée |
| Réseau sortant I/E | SSRF vers metadata/private, redirection ou DNS rebinding | Élevé | Moyenne | Élevé | HTTPS public uniquement, résolution validée et connexion IP épinglée, pas de redirection/proxy implicite | Tests ; dépendance httpcore épinglée |
| Localisation I | Réidentification via coordonnées | Élevé | Moyenne | Élevé | Permission ponctuelle, ville manuelle, arrondi à 2 décimales, logs expurgés | Snapshots 30 jours ; destinations jusqu'à effacement |
| Cache mobile I | Téléphone perdu, compte suivant lisant le précédent | Élevé | Moyenne | Élevé | Secure Storage, Hive AES, URL signées exclues, purge et invalidation au changement de session | Tests ; Keystore/Keychain à éprouver sur appareils |
| Logs / télémétrie I/R | Tokens, photos, emails dans exceptions | Élevé | Élevée | Élevé | Redaction centrale, absence d'access logs, Sentry sans PII/contexte source, compteurs agrégés | Transport Sentry mémoire testé ; destination distante non configurée |
| Secrets CI I/E | Clé serveur dans l'APK, fichier env commité | Élevé | Moyenne | Élevé | Secrets serveur uniquement, exclusions Docker/Git, Gitleaks, gate production | Répertoire livré scanné ; historique Git absent localement |
| Dépendances T/E | Paquet/image vulnérable ou action modifiée | Élevé | Moyenne | Élevé | Hashes Python, pubspec.lock, actions SHA, scans, image minimale non-root | Scans ponctuels ; nouvelles CVE possibles |
| PostgreSQL I/E/D | Rôle superuser, accès public, panne | Élevé | Moyenne | Élevé | Rôle dédié non privilégié vérifié au démarrage prod, SQLAlchemy, TLS CA configurable | Rôle local et restauration testés ; chiffrement disque/firewall cloud externes |
| Export I/D | Export d'un autre compte ou épuisement mémoire | Élevé | Moyenne | Élevé | Utilisateur authentifié, données filtrées, JSON + photos, plafonds et 413 explicite | Grand export nécessite une filière support réelle |
| Effacement I/R | Orphelins S3, upload après suppression | Élevé | Moyenne | Élevé | Suppression SQL et sessions, queue durable, deuxième purge après expiration des signatures, réessais | Worker nécessaire ; sauvegardes à expirer selon politique externe |
| Disponibilité D | Flood JSON/images/auth/IA | Élevé | Élevée | Élevé | Limites corps/structures/délais, quotas différenciés, Redis fail-closed | Protection volumétrique CDN/WAF externe, Argon2 consomme CPU |

Frontières de confiance : téléphone ↔ API TLS ; API ↔ base/Redis privés ; API ↔ S3 privé ; API ↔ fournisseurs publics ; CI ↔ registre/déploiement. Les protections applicatives ne remplacent pas la configuration IAM, la validation juridique ou un test d'intrusion indépendant.
