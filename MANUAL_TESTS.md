# Tests manuels

À dérouler sur un build `make run`, menu de Thock ouvert quand un compteur est demandé (Diagnostics, déplié). Les compteurs n'affichent jamais de keycode. Cocher chaque case une fois le résultat attendu observé.

## 0. Préparation

- [ ] `make build` puis `make verify-signature` : `Authority=` affiche le certificat choisi dans `Config/Signing.local.xcconfig`, `flags=0x10000(runtime)`, `designated => identifier "com.louis.thock" and certificate leaf = H"<SHA1 du certificat>"`.
- [ ] Aucune invite de mot de passe pendant le build ni au lancement.

## 1. Permission et onboarding

- [ ] **Premier lancement sans permission** (`make reset-permissions`, puis `make run`) : la fenêtre « Bienvenue dans Thock » s'ouvre. L'icône de la barre des menus montre un clavier avec des points de suspension. Aucune invite système n'apparaît avant le clic.
- [ ] **Octroi sans relance** : « Ouvrir les Réglages Système » ouvre Confidentialité et sécurité > Surveillance de l'entrée, où Thock est déjà listé. Activer Thock. En 1 s environ, la fenêtre passe à « C'est prêt » et le menu affiche « Actif », sans relancer l'app. Si les Réglages proposent « Quitter et rouvrir », choisir « Plus tard » : la capture doit fonctionner quand même.
- [ ] **La permission survit à un rebuild** : modifier un fichier source (ou `make clean`), puis `make run`. Le menu affiche « Actif » tout de suite, sans invite ni mot de passe.
- [ ] **Retrait puis rétablissement app lancée** : désactiver Thock dans Surveillance de l'entrée. En 3 s au plus, la fenêtre d'accueil se rouvre et l'icône change. Taper : aucun son. Réactiver : « C'est prêt » revient sans relance et les sons reviennent.

## 2. Machine à états (compteurs Pressions / Relâchements)

- [ ] **Suppr maintenu 5 s** : un seul son de pression et un seul de relâchement (+1 / +1), malgré l'auto-repeat.
- [ ] **Frappe rapide** (phrase tapée vite, touches qui se chevauchent) : autant de pressions que de relâchements, aucun son manqué à l'oreille.
- [ ] **Combinaisons de modificateurs** : ⇧ gauche, ⇧ droit, ⌘ gauche et droit, ⌥ gauche et droit, ⌃, Fn et Globe donnent chacun +1 / +1. ⇧ gauche maintenu puis ⇧ droit appuyé et relâché : le relâchement de ⇧ droit sonne, celui de ⇧ gauche sonne à son tour. ⌘C, ⌘⇧4 : un son par touche.
- [ ] **Caps Lock** : une pression suivie d'un relâchement court à chaque appui, à l'activation comme à la désactivation.
- [ ] **Touche `<`** (ISO, à gauche du W en AZERTY) et touches de ponctuation : elles sonnent.

## 3. Audio

- [ ] **Un son à chaque frappe** dans plusieurs apps (Notes, Safari, Terminal sans saisie sécurisée).
- [ ] **Qualité des sons** : `make preview PACK=<id>` pour comparer les 8 packs hors de l'app (`holypanda`, `cream`, `mxbrown`, `mxblack`, `mxblue`, `boxnavy`, `bluealps`, `topre`), puis taper avec chacun dans Thock, spatialisation activée puis désactivée. Noter ceux à retirer ou à garder par défaut.
- [ ] **Rangées** : taper F5, 5, T, G, B avec un pack kbsim. Chaque rangée a son propre échantillon, et la même touche répétée varie légèrement en hauteur, en niveau et en timbre. Sur AZERTY, `<` (à gauche de W) sonne comme la rangée du bas.
- [ ] **Attaque** : avec Topre puis MX Brown (les clips kbsim aux plus longs silences initiaux), le son doit partir aussi vite qu'avec Cream. Aucun clic en fin de son, même sur l'espace de MX Brown, coupée net dans l'enregistrement d'origine.
- [ ] **Ancien pack enregistré** : au premier lancement de cette version, le pack Feutré enregistré dans les réglages n'existe plus. Thock sélectionne Holy Panda et le menu l'affiche coché.
- [ ] **Changement de pack en tapant** : ouvrir Réglages > Packs, taper en continu d'une main et cliquer sur un autre pack de l'autre. Pas de coupure durable, pas de plantage, le nouveau pack sonne dès la frappe suivante.
- [ ] **Latence réelle** : `make latency`, taper une minute, lire p50 et p99 dans Diagnostics (attendu : p99 < 2 ms). « Horodatages hors horloge hôte » ne doit pas augmenter à chaque frappe, sinon l'hypothèse sur l'unité du timestamp est fausse. Écouter aussi sur les haut-parleurs intégrés ou en filaire pour juger le délai ressenti (≈ 7 ms estimés).
- [ ] **CPU sur sortie filaire** : choisir les haut-parleurs intégrés comme sortie système, puis `make cpu`. Attendu : < 1 % au repos, < 3 % pendant le banc.- [ ] **Débrancher puis rebrancher des AirPods en tapant** : pas de crash. Le son revient en moins d'une seconde sur la nouvelle sortie et « Reconstructions » augmente.
- [ ] **Sortie choisie puis déconnectée** : choisir le casque dans « Sortie », puis l'éteindre. Le son passe sur la sortie par défaut et le menu affiche « Périphérique déconnecté ». Le rallumer : le son y revient.
- [ ] **Instruments Allocations** (optionnel, la mesure automatisée couvre ce point) : profiler Thock pendant la frappe et filtrer sur `com.louis.thock.audio`. Aucune allocation ne doit apparaître pendant la frappe, ni sur cette file ni sur le thread de rendu audio.

## 4. Système

- [ ] **Veille et réveil** : mettre le Mac en veille, le réveiller, taper. Le son revient sans relancer l'app, et aucune touche ne reste « coincée » (pas de relâchement fantôme au premier appui).
- [ ] **Verrouillage de session** : verrouiller l'écran (⌃⌘Q), déverrouiller, taper. Le son revient. Le mot de passe tapé sur l'écran verrouillé ne doit pas sonner.
- [ ] **Champ de mot de passe** : cliquer dans un champ de mot de passe (Safari, Réglages). Le menu affiche « Saisie sécurisée active » en 2 s au plus et la frappe est silencieuse. En sortant du champ, l'indicateur disparaît et le son revient.
- [ ] **Changement rapide d'utilisateur** (si un second compte existe) : basculer, revenir, taper. Le son revient.

## 5. Interface et réglages

- [ ] **Raccourci global** : ⌃⌥⌘K depuis n'importe quelle app coupe Thock (icône haut-parleur barré, menu « Coupé »), puis le réactive.
- [ ] **Changer le raccourci** : Réglages > Général, cliquer sur ⌃⌥⌘K, taper ⌃⌥⌘J. Le nouveau raccourci marche, l'ancien ne fait plus rien. Taper ⌥A seul : refusé avec le message « doit contenir ⌘ ou ⌃ ». Échap annule. Quitter et relancer Thock : ⌃⌥⌘J est conservé. « Par défaut » rétablit ⌃⌥⌘K.
- [ ] **Raccourci déjà pris** : essayer une combinaison réservée par une autre app ou par macOS. Thock garde l'ancien raccourci et affiche l'erreur.
- [ ] **Sourdine micro (appel FaceTime)** : lancer un appel FaceTime (ou un mémo vocal). Le menu affiche « En sourdine : le micro est utilisé » et la frappe est silencieuse. Raccrocher : le son revient. Recommencer avec des AirPods comme entrée et sortie : même résultat.
- [ ] **Règle micro désactivée** : Réglages > Sourdine, décocher la règle micro. Pendant l'appel, Thock sonne.
- [ ] **App exclue** : Réglages > Sourdine > « Ajouter une app ouverte » > choisir une app (Notes). Passer au premier plan dans Notes : sourdine, avec « Notes est au premier plan » dans le menu. Ouvrir le menu de Thock depuis Notes : la sourdine reste. Passer dans une autre app : le son revient. Faire de même avec « Choisir une app… » et un `.app` de /Applications. Retirer l'app de la liste : le son revient dans Notes.
- [ ] **Sortie système muette** : couper le son du Mac (touche muet). Le menu affiche « la sortie audio est muette » et Thock se tait. Rétablir : le son revient. Décocher la règle : Thock suit alors seulement le volume du périphérique.
- [ ] **Sortie choisie muette** : choisir un casque dans « Sortie » alors que la sortie système reste les haut-parleurs. Couper les haut-parleurs : Thock continue de sonner dans le casque. Couper le casque : sourdine. Repasser sur « Sortie par défaut du système » pendant que le casque est muet : le son revient sans autre action.
- [ ] **Pack illisible** : importer un pack, quitter Thock, corrompre `alpha_down_1` dans `~/Library/Application Support/Packs/<pack>`, relancer et choisir ce pack. Le menu et Réglages > Packs affichent l'erreur, la sélection revient au pack qui joue réellement.
- [ ] **Synthétique** : avec un injecteur (Keyboard Maestro, expansion de texte), « Ignorés » augmente et les pressions non. Cocher « Inclure les frappes synthétiques » : les pressions augmentent.
- [ ] **Sonde stateID / PID** : `make probe`, taper sur le clavier interne, un clavier USB, une souris, avec un injecteur et via Partage d'écran. Relever `stateID` et `pid` pour chaque source. Attendu pour le matériel : `stateID=1 accepted=true`. Si un injecteur donne aussi `stateID=1`, noter son `pid`.
- [ ] **Tap HID sous sandbox** : `make probe-hid`. Le menu doit afficher « Actif » si le tap HID est accepté sous sandbox. Comparer le nombre d'événements avec `make probe`.
- [ ] **Lancer au démarrage** : cocher l'option, se déconnecter puis se reconnecter. Thock est dans la barre des menus. Si le menu indique « À autoriser », l'activer dans Réglages Système > Général > Ouverture.
- [ ] **Persistance** : changer volume, pack, sortie, spatialisation, sons de souris, règles et liste d'exclusion. Quitter, relancer : tout est conservé.

## 6. Packs

- [ ] **Import par bouton** : Réglages > Packs > « Importer un dossier… », choisir un dossier valide (`pack.json` et `alpha_down_1.wav`, par exemple). Le pack apparaît « importé » après les packs embarqués, il est sélectionné et il sonne.
- [ ] **Import par glisser-déposer** : glisser un dossier de pack depuis le Finder sur la liste. Même résultat.
- [ ] **Pack invalide** : glisser un dossier sans `pack.json`, puis un dossier sans `alpha_down`. Message d'erreur explicite, rien n'est ajouté.
- [ ] **Suppression** : supprimer le pack importé sélectionné. Il disparaît de la liste et du menu, et Thock revient à Holy Panda.

## 7. Non testable à la main

- La réactivation sur `tapDisabledByTimeout` : le code réactive le tap et vide les touches tenues, et le watchdog couvre aussi le cas. Aucun moyen simple de la provoquer.
