# Sécurité

Consulter [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md) pour les contrôles, résultats de tests/scans et limites, [THREAT_MODEL.md](THREAT_MODEL.md) pour les menaces, [API_SECURITY.md](API_SECURITY.md) et [MOBILE_SECURITY.md](MOBILE_SECURITY.md) pour les vérifications OWASP, [RGPD_COMPLIANCE.md](RGPD_COMPLIANCE.md), [BACKUP_AND_RECOVERY.md](BACKUP_AND_RECOVERY.md) et [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md) pour l'exploitation.

Les secrets existants restent dans des fichiers d'environnement ignorés ; ils n'ont pas été effacés ni présentés comme absents de la machine. Les livrables sont scannés, et la CI vérifie aussi les fichiers suivis et l'historique Git lorsqu'un dépôt existe. Ne jamais publier les fichiers `.local` ou `.env`.

La configuration production est fail-closed et son gate bloque les mentions légales non renseignées. L'interface de test locale et ses prérequis sont documentés dans [LOCAL_TESTING.md](LOCAL_TESTING.md).
