# Thock

Thock joue un son de clavier mécanique à chaque frappe, dans toutes les apps du Mac. L'app vit dans la barre des menus. Elle n'a ni fenêtre principale ni icône dans le Dock.

- macOS 14 ou plus récent, Swift 6, SwiftUI et AppKit, aucune dépendance tierce.
- App Sandbox et Hardened Runtime activés.
- Une seule permission : **Surveillance de l'entrée**. Thock ne demande jamais l'Accessibilité.
- Aucun accès réseau. Aucune frappe n'est stockée ni journalisée.

## Installation

Prérequis : Xcode 27 et XcodeGen (`brew install xcodegen`).

```sh
make build              # génère Thock.xcodeproj, compile et signe ; build/Thock.app pointe vers le produit
make run                # compile, arrête l'instance en cours, lance build/Thock.app
make test               # tests unitaires (Swift Testing)
make reset-permissions  # oublie la permission Surveillance de l'entrée (tccutil), le seul endroit qui touche à TCC
```

Autres cibles :

| Cible | Rôle |
|---|---|
| `make stop` | Quitte Thock. |
| `make logs [SINCE=2m]` | Journal de Thock, décisions TCC et refus de la sandbox qui le concernent. Aucun keycode n'y figure. |
| `make verify-signature` | Vérifie la signature, les entitlements et la designated requirement. |
| `make cpu [IDLE=20 BENCH=20]` | CPU au repos puis pendant le banc de frappe synthétique (`BENCH=0` : repos seul, aucun son). |
| `make latency` | Lance Thock avec l'histogramme de latence actif (menu > Diagnostics). |
| `make probe` / `make probe-hid` | Journalise type, `stateID` et PID de chaque événement (jamais le keycode). La seconde compare avec un tap HID. |
| `make render [PACK=mxblue LABEL=after]` | Rend hors ligne une séquence de frappe rapide (100 puis 140 mots/min, touches qui se chevauchent, rafale de Retour arrière, cinq touches à la fois) avec le vrai moteur audio. Écrit `build/renders/LABEL_PACK.wav` (48 kHz, lien vers le DerivedData, hors iCloud) et affiche crête, échantillons écrêtés, sons coupés et écart de timing. |
| `make preview [PACK=cream]` | Joue avec `afplay` quelques frappes d'un pack embarqué (lettres sur plusieurs rangées, espace, entrée), sans lancer Thock. Par défaut `holypanda`. |
| `make packs` | Retélécharge les enregistrements kbsim et réécrit les fichiers des packs embarqués qui ont changé. Seul ce script accède au réseau, jamais l'app. |
| `make icon` | Régénère l'icône de l'app. |
| `make clean` | Supprime le projet généré et le DerivedData. |

Le DerivedData vit dans `~/Library/Developer/Xcode/DerivedData/Thock-make`, hors de `~/Documents`. Sous `~/Documents` synchronisé, le bundle reçoit des attributs étendus et `codesign` échoue. `build/Thock.app` est un lien symbolique stable vers le produit. `make run` lance toujours ce chemin, si bien que TCC ne garde qu'une entrée.

## Permission Surveillance de l'entrée

Au premier lancement, Thock ouvre une fenêtre d'accueil qui explique la permission. Le bouton « Ouvrir les Réglages Système » inscrit Thock dans la liste (`CGRequestListenEventAccess`), puis ouvre directement le panneau Confidentialité et sécurité > Surveillance de l'entrée (`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`). Il reste à activer Thock.

Thock interroge `CGPreflightListenEventAccess()` une fois par seconde tant que la permission manque. Dès qu'elle est accordée, la capture démarre, sans relance. Le tap n'est créé qu'après un preflight positif. Sans cela, `tapCreate` afficherait l'invite système avant l'explication.

Si la permission est retirée pendant que Thock tourne, le watchdog du tap (toutes les 3 s) le détecte. Thock arrête alors le tap, oublie les touches tenues et rouvre la fenêtre d'accueil. Quand la permission revient, la capture redémarre seule.

## Signature

TCC rattache la permission Surveillance de l'entrée à la designated requirement de l'app. Il faut donc signer chaque build avec la même identité stable. Avec un certificat, la requirement a cette forme :

```
identifier "com.louis.thock" and certificate leaf = H"<SHA1 du certificat>"
```

Elle ne dépend que du bundle id et du certificat, donc elle reste la même d'un build à l'autre : on accorde la permission une fois, et elle survit aux rebuilds. `make verify-signature` l'affiche.

**Par défaut : signature ad hoc.** `Config/Signing.xcconfig`, suivi par git, signe ad hoc (`CODE_SIGN_IDENTITY = -`) pour que le projet compile sans configuration. Une signature ad hoc n'a pas de certificat. Sa designated requirement est le `cdhash`, l'empreinte du binaire, qui change à chaque compilation. macOS considère alors chaque build comme une nouvelle app et redemande la permission. Pour un usage suivi, renseigner une identité stable.

**Renseigner son identité.** Copier `Config/Signing.local.xcconfig.example` vers `Config/Signing.local.xcconfig`. Ce fichier est ignoré par git et inclus par `Config/Signing.xcconfig` (`#include?`). Deux choix :

- **Certificat auto-signé.** Ouvrir Trousseau d'accès > Assistant de certification > Créer un certificat. Choisir un nom, le type d'identité « Racine auto-signée » et le type de certificat « Signature de code ». Relever ensuite son SHA1 avec `security find-identity -v -p codesigning`, et le mettre dans `CODE_SIGN_IDENTITY` :

  ```
  CODE_SIGN_STYLE = Manual
  CODE_SIGN_IDENTITY = <SHA1 du certificat>
  DEVELOPMENT_TEAM =
  OTHER_CODE_SIGN_FLAGS = --timestamp=none
  ```

  Référencer le certificat par son SHA1 plutôt que par son nom évite toute ambiguïté si deux certificats portent le même nom.

- **Apple Development.** Avec un compte développeur dans Xcode :

  ```
  CODE_SIGN_STYLE = Manual
  CODE_SIGN_IDENTITY = Apple Development
  DEVELOPMENT_TEAM = <identifiant d'équipe>
  OTHER_CODE_SIGN_FLAGS = --timestamp=none
  ```

On peut aussi surcharger ponctuellement :

```sh
make build CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=XXXXXXXXXX
```

**Aucune invite de mot de passe.** Quand l'accès à la clé est autorisé pour `codesign`, la signature ne demande pas de mot de passe. L'app n'accède jamais au trousseau, et le build n'en crée ni n'en déverrouille aucun.

Changer d'identité change la designated requirement : il faut accorder la permission une dernière fois, éventuellement après `make reset-permissions`.

## Utilisation

**Menu de la barre des menus.** L'icône est un clavier. Elle devient un haut-parleur barré en sourdine, et un clavier avec des points de suspension tant que la permission manque. Le menu contient :

- l'interrupteur On/Off et la raison de la sourdine en cours (coupé, micro utilisé, app exclue au premier plan, sortie système muette) ;
- un indicateur discret quand la saisie sécurisée est active (`IsSecureEventInputEnabled()`, lu toutes les 2 s avec une tolérance de 1 s) ;
- le volume, le pack, la sortie audio (défaut du système ou un périphérique précis), la spatialisation et les sons de la souris ;
- l'option « Inclure les frappes synthétiques » et « Lancer au démarrage » (`SMAppService.mainApp`) ;
- les diagnostics, repliés par défaut : compteurs sans keycode, état audio et mesure de latence.

**Raccourci global.** ⌃⌥⌘K active ou coupe Thock par défaut. Il passe par Carbon `RegisterEventHotKey`, sans permission. On le change dans Réglages > Général : cliquer, puis taper la combinaison, ou Échap pour annuler. Le raccourci doit contenir ⌘ ou ⌃, car macOS 15 refuse les combinaisons de ⌥ ou ⌥⇧ seules. Si une autre app possède déjà la combinaison, Thock garde l'ancienne et l'indique.

**Sourdine automatique** (Réglages > Sourdine). Chaque règle se désactive séparément :

- **Micro utilisé.** Un listener sur `kAudioDevicePropertyDeviceIsRunningSomewhere` de l'entrée par défaut, réabonné quand l'entrée par défaut change. Cette propriété couvre les deux sens d'un périphérique. Quand l'entrée est aussi la sortie de Thock (AirPods, casque USB), elle serait toujours vraie à cause de Thock lui-même. Dans ce cas, Thock demande à chaque processus audio s'il enregistre (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+). Aucun flux d'entrée n'est jamais ouvert.
- **App exclue au premier plan.** Une liste de bundle ids, alimentée depuis les apps ouvertes ou par la sélection d'un `.app`. Thock suit `NSWorkspace.didActivateApplicationNotification`. Ouvrir le menu ou les réglages de Thock ne lève pas la sourdine de l'app placée dessous.
- **Sortie système muette.** La sourdine de la sortie par défaut, suivie par un listener Core Audio.

Pendant une sourdine, l'engine audio continue de tourner et la machine à états de suivre les touches. Le retour du son ne coûte rien et aucun relâchement fantôme n'est joué.

Tous les réglages sont persistés dans `UserDefaults`.

## Format des packs

Un pack est un dossier :

```
MonPack/
├── pack.json            {"name": "Mon pack", "author": "Moi", "license": "CC-BY-4.0", "source": "https://…"}
├── alpha_down_r0.caf    rangée 0 : Échap et touches F
├── alpha_down_r1.caf    rangée 1 : chiffres
├── alpha_down_r2.caf    rangée 2 : Tab, A Z E R T Y (Q W E R T Y)
├── alpha_down_r3.caf    rangée 3 : Verr. Maj, Q S D F (A S D F), Entrée
├── alpha_down_r4.caf    rangée 4 : Maj, W X C V (Z X C V), puis espace, ⌘ ⌥ ⌃ et flèches
├── alpha_up_1.caf
├── space_down_1.wav
└── …
```

- Noms de fichiers, au choix :
  - `catégorie_direction_variante` : `alpha_down_1.caf`, joué sur toutes les rangées ;
  - `catégorie_direction_rRANGÉE` ou `catégorie_direction_rRANGÉE_variante` : `alpha_down_r2.caf`, `alpha_down_r2_3.wav`, joué sur cette rangée seulement.
- Extensions : `caf`, `wav`, `aiff`, `aif`. `source` est facultatif dans `pack.json`.
- Catégories : `alpha` (lettres et chiffres), `space`, `enter`, `backspace`, `tab`, `modifier`, `arrow`, `punctuation` et `mouse`. Directions : `down` pour la pression, `up` pour le relâchement.
- Rangées : la rangée physique de la touche, déduite de son keycode virtuel, donc identique en AZERTY, QWERTY et ISO. La touche `<` de l'ISO (keycode 10) est en rangée 4. Le découpage suit kbsim, où la rangée de l'espace partage l'échantillon de la rangée 4.
- Pour une touche, Thock prend les fichiers de sa rangée, sinon les variantes sans rangée, sinon la rangée enregistrée la plus proche. Une catégorie sans aucun fichier reprend `alpha` de la même direction, pour la même rangée. Un pack au format `alpha_down_1.caf` sans rangée fonctionne donc comme avant.
- Il faut au moins un fichier `alpha_down`, avec ou sans rangée.
- Au chargement, Thock mixe en mono et rééchantillonne. Il coupe ensuite chaque fichier 1 ms avant le premier échantillon à 20 dB sous sa propre crête, et après le dernier à 45 dB sous elle. De courts fondus évitent les clics aux deux coupures. Enfin, il normalise le pack entier à -1 dBFS crête. Le seuil est relatif parce que les enregistrements ont jusqu'à 20 dB d'écart de niveau entre eux et un bruit de fond MP3 vers -50 dBFS : un seuil absolu se déclenchait sur le bruit et laissait jusqu'à 20 ms de silence avant l'attaque. Un seul gain pour tout le pack garde les écarts voulus, par exemple une espace plus forte qu'une lettre.
- Chaque frappe varie en continu : vitesse de lecture à ±1,5 % (±2,5 % pour un relâchement), gain entre -2,5 dB et le niveau enregistré (-4 dB pour un relâchement), et une part du son adoucie par un passe-bas à 3 kHz, jusqu'à 30 % (60 % pour un relâchement). Les relâchements varient davantage parce que kbsim n'en a qu'un fichier par switch. Quand une touche a plusieurs fichiers, elle n'en joue jamais deux fois de suite le même.

**Import.** Glisser le dossier sur la liste de Réglages > Packs, ou cliquer « Importer un dossier… » (sandbox : accès en lecture au seul dossier choisi). Thock copie `pack.json` et les fichiers audio reconnus dans `~/Library/Containers/com.louis.thock/Data/Library/Application Support/Packs/`. Il décode ensuite la copie : un pack qui ne jouerait pas est refusé avec la raison, et rien ne reste sur le disque. Le pack importé est listé avec les packs embarqués, puis sélectionné. Un pack importé se supprime depuis la même liste.

**Packs embarqués.** Ce sont de vrais enregistrements de switches mécaniques, tirés de kbsim (voir Crédits) et convertis par `make packs` en CAF mono 16 bits à 48 kHz :

La dernière colonne donne la réputation de chaque switch, pas un jugement d'écoute : on compare avec `make preview PACK=<id>`.

| Pack | Switch | Réputation |
|---|---|---|
| Holy Panda (par défaut) | tactile | bosse marquée, frappe ronde |
| NovelKeys Cream | linéaire | feutré, grave, doux |
| Cherry MX Brown | tactile léger | sec et discret, proche d'un clavier de bureau |
| Cherry MX Black | linéaire lourd | net et franc |
| Cherry MX Blue | clicky | clic aigu (kbsim n'a pas d'espace ni d'entrée dédiés : ces touches reprennent la rangée 4) |
| Kailh Box Navy | clicky lourd | clic épais et sonore |
| Alps SKCM Blue | clicky vintage | clic sec et métallique |
| Topre | électrocapacitif | « thock » sourd et profond |

Chaque pack a un échantillon de pression par rangée, un relâchement générique, et des fichiers dédiés pour l'espace, Entrée et Retour arrière. Les autres touches (Tab, modificateurs, flèches, ponctuation) prennent l'échantillon de leur rangée, comme dans kbsim. Écartés pour garder des caractères distincts : `alpaca`, `turquoise`, `blackink` et `redink`, quatre linéaires de plus, et `buckling` (ressort à flambage IBM), un clicky de plus. Aucun fichier des huit packs retenus n'est défectueux : durée, crête et plancher de bruit ont été mesurés pour chacun.

## Choix techniques

**`.cgSessionEventTap` plutôt que `.cghidEventTap`.**

- Apple documente le tap listen-only sous sandbox avec la permission Surveillance de l'entrée. Le niveau session est le cas normal de cette combinaison. Le niveau HID a toujours été associé à root ou à l'Accessibilité.
- Le tap session ne voit que la session de connexion. Après un changement rapide d'utilisateur, Thock n'entend pas l'autre session.
- La saisie sécurisée est respectée sans rien faire.
- L'écart de latence avec le niveau HID est supposé de l'ordre de la dizaine de µs, négligeable devant le tampon audio. Il n'est pas mesuré. `make probe-hid` permet de comparer.

**Chemin chaud.** Le callback du tap, sur un thread dédié avec sa runloop, copie quelques champs dans un ring SPSC en C11, sans allocation ni log. Il réveille ensuite la file audio par `DispatchSourceUserDataAdd`. Cette file filtre, réduit la machine à états et pousse une commande de 32 octets dans un second ring SPSC, sans changer de thread ni appeler AVFoundation. Le bloc de rendu d'un `AVAudioSourceNode` (`Sampler`) lit ce ring et mixe jusqu'à 32 voix. L'engine reste chaud. Le tampon IO est de 128 trames.

**Échantillonneur maison plutôt que 32 `AVAudioPlayerNode`.** Mesuré avec `make render` : `scheduleBuffer(at: nil)` démarre le son au rendu suivant, ou un à deux cycles plus tard, au hasard d'une course interne. Le même instant de frappe ne donne pas le même départ d'un passage à l'autre. En frappe rapide, l'écart entre deux sons s'éloignait ainsi de jusqu'à 7 ms de l'écart entre les deux frappes. Programmer à la trame près demande un `AVAudioTime` par son, donc une allocation. Le `Sampler` place au contraire chaque son exactement un cycle plus 1 ms après sa frappe, par interpolation d'Hermite à vitesse variable. Il ne coupe une voix que si aucune n'est libre, et il prend alors celle à qui il reste le moins de son. Un limiteur sans anticipation garde la sortie sous -1 dBFS. Le bloc de rendu ne prend aucun verrou et n'alloue rien.

## Mesures

Ordres de grandeur indicatifs, qui varient selon la machine et la sortie audio. Les outils pour les reproduire sont `make cpu`, `make latency` et `make render`.

| Mesure | Ordre de grandeur |
|---|---|
| CPU au repos (app lancée, engine à 48 kHz, sans frappe) | ≈ 0 % |
| CPU en frappe soutenue simulée (17 événements/s, `--bench-typing`) | ≈ 0 à 1 % |
| Latence logicielle, timestamp du CGEvent → son programmé | p50 de quelques dizaines de µs, p99 sous 0,1 ms |
| Frappe → départ du son, en rendu hors ligne à 128 trames | constant, un cycle plus 1 ms (≈ 3,7 ms), sans écart d'intervalle |
| Latence de sortie annoncée par Core Audio | celle du périphérique : quelques ms en filaire, plus de 150 ms pour un casque Bluetooth |
| Allocations dans notre code (drain du pipeline, 200 événements) | 0, vérifié par les tests |

**Variation de hauteur.** Un `AVAudioUnitVarispeed` par voix a été essayé et abandonné : en rendu hors ligne, 32 voix au repos coûtaient plus de dix fois plus de CPU avec lui. Le `Sampler` fait varier la vitesse lui-même, par interpolation.

Le banc est synthétique : il pousse des événements dans le vrai ring sans passer par le tap. La latence perçue en filaire est estimée à environ 7 ms (3,7 ms d'avance du `Sampler`, plus un cycle de sortie et le périphérique). C'est une estimation, pas une mesure de bout en bout.

## Limites connues

- **Saisie sécurisée.** Dans un champ de mot de passe, ou quand une app active la saisie sécurisée (Terminal avec « Saisie sécurisée au clavier », certains gestionnaires de mots de passe), macOS ne transmet plus les frappes au tap. Thock se tait et le menu l'indique. C'est voulu, Thock ne la contourne pas.
- **Bluetooth.** La latence est imposée par le casque (souvent plus de 150 ms annoncés par un casque Bluetooth). Aucun réglage de Thock n'y change rien. En filaire ou sur les haut-parleurs intégrés, le délai est de quelques ms.
- **Allocations.** Rien n'alloue entre le tap et le ring du `Sampler`, ni dans son bloc de rendu : mesuré avec un hook `malloc_logger`. `renderOffline` d'AVAudioEngine alloue lui-même 2 blocs pour 64 cycles, qu'il y ait 12 voix à mixer ou aucune.
- **Micro sur un périphérique partagé.** Quand l'entrée par défaut est aussi la sortie de Thock, la détection passe par les processus audio, ce qui demande macOS 14.2. Sur macOS 14.0 et 14.1, la règle ne se déclenche pas dans ce cas.
- **Frappes synthétiques.** Le filtre garde `eventSourceStateID == 1` (état HID). C'est la valeur attendue pour le matériel. Elle reste à confirmer avec `make probe` sur chaque type de clavier et d'injecteur.
- **Unité du timestamp CGEvent.** Elle est supposée en ticks `mach_absolute_time`. Le compteur « Horodatages hors horloge hôte » des diagnostics le vérifiera en frappe réelle. Si l'hypothèse est fausse, Thock joue quand même chaque son.
- **Lancer au démarrage.** `SMAppService.mainApp` enregistre le bundle à son emplacement réel, ici dans le DerivedData. Après `make clean`, il faut réactiver l'option.

## Confidentialité

- Thock reçoit des événements de clavier et de souris en écoute seule (`.listenOnly`). Il ne peut ni les modifier ni en injecter.
- Seuls le type d'événement, le keycode, les modificateurs, l'auto-repeat, la source et l'horodatage sont copiés, puis oubliés après le son. Rien n'est écrit sur disque.
- Aucun keycode n'est journalisé, même en mode sonde. `RawInputEvent` n'a pas de description textuelle.
- Aucun entitlement réseau, aucune télémétrie.
- Entitlements : `com.apple.security.app-sandbox` et `com.apple.security.files.user-selected.read-only` (import de packs, sélection d'une app à exclure). En Debug, Xcode ajoute `get-task-allow`. La lecture de l'état du micro fonctionne sans `com.apple.security.device.audio-input` : vérifié sous sandbox, sans aucune trace TCC dans le journal.
- Les seules données persistées sont les réglages (`UserDefaults`) et les packs importés.

## Dépannage

- **La capture ne démarre pas alors que la permission est accordée.** Utiliser « Relancer Thock » dans le menu. Si la permission semble attachée à un ancien build, `make reset-permissions`, puis l'accorder de nouveau.
- **Aucun son.** Regarder la raison de sourdine dans le menu, puis les diagnostics (« Audio arrêté » ou compteurs à zéro). `make logs` affiche l'état de l'engine.
- **Tests manuels.** Voir [MANUAL_TESTS.md](MANUAL_TESTS.md).

## Crédits

- **Sons des packs embarqués** : enregistrements de switches de [kbsim](https://github.com/tplai/kbsim) par Thomas Lai, sous licence MIT (dossier `src/assets/audio`). Thock les convertit en CAF mono à 48 kHz, puis les coupe et les normalise au chargement. Le découpage des échantillons par rangée de clavier reprend aussi celui de kbsim. Texte complet de la licence : [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).
- Thock n'utilise ni le nom, ni l'icône, ni les sons de Klack.
