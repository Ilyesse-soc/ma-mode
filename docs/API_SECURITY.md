# API — OWASP API Security Top 10

| Risque | Contrôle livré | Vérification / limite |
|---|---|---|
| API1 BOLA | Queries propriétaire, références croisées vérifiées, objets S3 enregistrés avant utilisation | Tests multi-comptes, export et effacement ; pas un pentest exhaustif |
| API2 Broken Authentication | RS256, sid actif, Argon2id, rotation/verrouillage/rejeu, reset à usage unique, vérification email prod | Tests ; SMTP externe requis |
| API3 Property Authorization | StrictModel extra=forbid, schémas dédiés d'entrée, user_id imposé serveur | Tests mass assignment, textes/listes/NaN |
| API4 Resource Consumption | 256 Kio JSON, profondeur 16, photos 10 Mio/20 Mp, exports 20 Mio, quotas Redis, délais | Tests 413/429/503 ; WAF volumétrique et budget IA externe nécessaires |
| API5 Function Authorization | Auth requise sur opérations personnelles, réauth mot de passe suppression/révocation | Tests compte invité/propriétaire ; pas de rôle admin exposé |
| API6 Sensitive Business Flows | Quotas auth, récupération, médias, scan, IA ; consentement IA | Redis partagé fail-closed ; signal de rejeu |
| API7 SSRF | HTTPS public, ports/hosts contrôlés, DNS/IP épinglés, pas de redirects/proxy implicite | Tests adresses privées, IPv6, credentials/redirect ; URLs images fournisseur non téléchargées |
| API8 Misconfiguration | Startup prod fail-closed, CORS explicite, headers, docs/debug off, rôle SQL et bucket privé sondés | Tests Settings ; reverse proxy/TLS/IAM restent externes |
| API9 Inventory | Routes versionnées /api/v1, documentation de modules et CI, endpoints de santé sans secrets | Gate publication ; inventaire des déploiements externes à tenir |
| API10 Unsafe Consumption | JSON fournisseur borné/Pydantic, aucun code/outils IA, délais, TLS normal, pas de fallback inventé | Tests schémas ; météo réelle testée, identification distante à éprouver |

`POST /media/upload-url` renvoie désormais un **POST S3 signé** avec `fields` et politique de taille, à la place d'un PUT non borné. `POST /media/upload` demeure disponible et est utilisé par Flutter. Les fichiers de quarantaine sont décodés et réencodés avant attachement ; le client ne fait pas autorité sur dimensions, MIME ou taille.

Auth : access 900 s, refresh opaque haché avec échéance absolue 30 jours, reset 1 h et vérification email 24 h. Une réutilisation de refresh révoque les sessions ; une ancienne session n'autorise plus son access JWT. Les réponses de récupération et inscription production sont neutres. Sans SMTP, le reset renvoie une indisponibilité réelle plutôt que prétendre envoyer un mail.

Observabilité : logs expurgés sans access logs, Sentry opt-in avec payload filtré, compteurs Redis et alertes SMTP agrégées, worker de suppression/rétention supervisé. Le recipient et les DSN distants doivent être fournis. Le démarrage production refuse les credentials par défaut et un rôle SQL superuser/createdb/createrole.
