# Splash et onboarding

Les quatre PNG originaux sont conservés sans modification dans `assets/images` :

1. `bording1.png` : splash Dressly.
2. `boarding2.png` : garde-robe intelligente.
3. `boarding3.png` : recommandations.
4. `boarding4.png` : destination.

Le dossier fourni s'appelait initialement `assets/image` ; il a été regroupé sous
le chemin `assets/images` demandé. Les anciennes copies enregistrées dans
`apps/mobile/assets/image` ont été retirées.

`assets/pubspec.yaml` définit un package Flutter local d'images. La dépendance
`dressly_intro_assets` dans le pubspec mobile utilise directement ce dossier,
sans téléchargement ni copie de production. Le bundle expose les clés
`packages/dressly_intro_assets/images/<nom>.png`. Cette structure est portable
et évite les chemins `../../` dans les URL du build web.

`IntroAssets` centralise l'ordre et le préchargement. `IntroBackground` applique
`BoxFit.cover` et un gradient sombre. `OnboardingPageModel` et
`OnboardingPageWidget` fournissent les trois pages réutilisables. Les fonds
défilent avec leur texte, avec une apparition et une translation de 300 ms.
Les textes et boutons sont en Inter local ; le splash utilise une headline
éditoriale, sans dépendance à une police disponible uniquement sur ordinateur.

Le splash conserve la décision de navigation selon la session et le marqueur
d'onboarding. Suivant avance, Commencer et Passer enregistrent ce marqueur puis
ouvrent la création de compte existante. Les protections d'authentification
restent celles du routeur existant.

Validation : `flutter analyze` sans problème et 37 tests Flutter réussis,
dont le chargement des quatre PNG originaux, le swipe, la pagination et la
navigation Commencer. La vérification web est consignée séparément dans
`ONBOARDING_BROWSER_CHECK.json` après son exécution.
