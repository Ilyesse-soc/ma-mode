# Vérification mobile — OWASP MASVS

PASS = contrôle de code et test local effectué, pas une certification. PARTIAL = contrôle présent avec preuve native/infrastructure manquante. TODO = travail externe restant. N/A = fonctionnalité absente.

| Domaine | Statut | Preuve / limite |
|---|---|---|
| MASVS-STORAGE : tokens | PARTIAL | Session unique Secure Storage, sérialisation anti-écriture tardive ; Keystore/Keychain réels non testés sur appareil |
| MASVS-STORAGE : données | PARTIAL | Hive AES avec clé aléatoire Secure Storage, suppression des anciens caches clairs, exclusion URLs signées ; l'app web utilise le stockage navigateur |
| MASVS-AUTH : sessions | PASS | Refresh single-flight, un seul retry, génération de session, expiration/purge, révocation serveur ; tests de concurrence |
| MASVS-NETWORK : transport | PARTIAL | Origine API vérifiée avant bearer, redirects interdits, HTTPS requis prod, Android cleartext release interdit ; TLS cloud et interception sur téléphone à vérifier |
| MASVS-PLATFORM : sauvegardes | PARTIAL | Android backup désactivé, Keychain this-device-only ; extraction/restore Android/iOS non effectués |
| MASVS-CODE : qualité/dépendances | PASS | flutter analyze, tests et lockfile scanné ; consulter reçus d'audit |
| MASVS-PRIVACY : collecte | PARTIAL | Choix IA réel révocable, GPS arrondi, export/effacement/cache ; déclarations stores et avis juridiques externes |
| MASVS-RESILIENCE : root/debug/hooking | TODO | Pas d'attestation Play Integrity/App Attest, ni validation résistance sur appareil ; le backend reste l'autorité |
| Certificate pinning | TODO | Non activé sans cycle de rotation/backup pins testé ; validation TLS système conservée |
| Biométrie / paiement | N/A | Non utilisés |

Le rendu 3D utilise les GLB fournis sans transformation, via `MannequinViewer` et model_viewer_plus. Les exceptions loopback servent le renderer local ; elles n'autorisent pas un backend distant HTTP en release. Les ressources GLB ne contiennent aucun secret serveur.

La build navigateur locale sert à tester les parcours. Elle n'établit pas les propriétés Keystore/Keychain, permissions caméra/GPS, partage natif, performances 3D sur téléphone ou conformité d'une APK/IPA finale. Aucun SDK Android ni appareil iOS utilisable n'était disponible pour ces contrôles.

Référentiel : [OWASP MASVS](https://mas.owasp.org/MASVS/).

Signature Android : le fallback vers la clé debug en release a été supprimé. Une release exige un vrai keystore et ses credentials par environnement ; la CI échoue en leur absence. La compilation native/signature effective reste à tester avec le SDK et la clé du propriétaire.
