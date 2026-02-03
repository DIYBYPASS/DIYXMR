# 🚀 DIYXMR — Stack de Minage Monero par CPU

![License](https://img.shields.io/badge/LICENSE-SOURCE%20AVAILABLE-crimson?style=for-the-badge&logo=adguard&logoColor=white)
![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)
![Monero](https://img.shields.io/badge/Monero-XMR-FF6600?style=for-the-badge&logo=monero)

**DIYXMR** est un script Bash “tout-en-un” d'automatisation complet pour déployer, sécuriser et gérer un stack de minage Monero (XMR) performant sur Linux. Il gère l'installation de A à Z, l'optimisation du CPU, la sécurité réseau (Tor/UFW) et permet le **Merge Mining** avec Tari.

Tout est piloté via un **Tableau de Bord (TUI)** interactif en temps réel.

---

## ⚠️ Philosophie : Performance & Anti-Censure
Ce projet est conçu pour la **performance brute** et la **résilience**, pas pour l'anonymat.
- **Tor = Annuaire :** Le réseau Tor est utilisé uniquement pour la découverte de pairs (Peer Discovery) afin de contourner les blocages FAI.
- **Clearweb = Transport :** Le flux de minage (les shares) transite en clair sur Internet pour garantir une **latence zéro**.

## ⚡ La Règle d'Or : Latence > Hashrate
En minage, la vitesse de propagation (Latence) est plus critique que la puissance brute (Hashrate).
C'est une course de vitesse : **Premier arrivé, premier servi.**

Si vous trouvez un bloc en même temps qu'un autre mineur mais qu'il le propage avant vous à cause d'une latence réseau (VPN/Tor), votre bloc sera rejeté (Orphelin). **Vous aurez brûlé de l'électricité pour rien**.

## 🛑 OpSec : Séparez vos usages
Il est impossible d'avoir un stack à la fois **anonyme** (lent) et **performant** (rapide) pour le minage.
Ce script transforme votre machine en serveur de minage dédié : **ne l'utilisez pas pour votre vie privée**.

---

## ✨ Fonctionnalités Principales

### 🏗️ Architecture Complète
* **Monero Node (`monerod`)** : Nœud complet en mode **Pruned** (~70 Go). Fonctionne sur le **Clearweb** pour une latence minimale, avec **Tor** servant uniquement d'annuaire de secours pour récupérer des IPs de pairs en cas de blocage FAI.
* **P2Pool** : Sidechain décentralisée (0% frais, paiements directs sur votre wallet dès qu’un bloc est trouvé si vous avez des shares dans la fenêtre PPLNS ; minimum technique ~0.00027 XMR par payout).
* **XMRig** : Mineur CPU optimisé automatiquement selon votre matériel.
* **Tari (Minotari)** : Nœud complet (Pruned) pour le **Merge Mining**. Gagnez du Tari en "bonus" sans aucune perte de hashrate Monero.

### 🛡️ Sécurité & Confidentialité (Hardening)
* **Anti-Censure** : Monero et Tari utilisent **Tor** pour la découverte de pairs. Le minage P2Pool reste sur le **Clearweb** pour garantir une **latence minimale** (essentiel pour les gains).
* **Pare-feu (UFW)** : Configuration automatique stricte et adaptative selon le mode de minage (SOLO / P2Pool NANO-MINI-FULL / MoneroOcean) et les options activées (SSH, Tari) ; seuls les ports requis sont autorisés, le reste est bloqué.
* **Anti Brute-force** : Installation et configuration de **Fail2Ban** pour SSH.
* **Réseau** : Optimisation de la pile TCP (**BBR**) pour la vitesse et activation des **extensions de confidentialité IPv6** (Privacy Extensions).

### ⚡ Performance
* **HugePages & 1GB Pages** : Activation automatique et persistance au redémarrage.
* **Désactivation THP** : Gestion du Transparent Huge Pages pour éviter les latences.
* **Auto-tuning** : Détection du cache L3 pour calculer le nombre optimal de threads (compatible AMD 3D V-Cache).

### 🖥️ Expérience Utilisateur
* **Installation Interactive** : Assistant de configuration au premier lancement.
* **Dashboard TUI** : Vue en temps réel du hashrate, de la synchro, de la santé système et des logs, avec un menu interactif (raccourcis clavier) pour gérer rapidement les actions courantes (paramètres, mise à jour, affichage des logs, arrêt/nettoyage).
* **Auto-update** : Système de mise à jour intégré pour le script et les binaires (XMRig, Monero, P2Pool, Tari), avec vérification d’intégrité (SHA256) et validation des signatures (GPG) lorsqu’elles sont disponibles, afin de réduire le risque d’installer des archives altérées.

---

## 📊 Modes de Minage

### ⚡ P2Pool NANO
Sidechain très légère, conçue pour petits CPU.
- ✅ Pool décentralisé
- ✅ Pas de frais
- ✅ Paiements fréquents
- ❌ Plus de variance (récompenses plus irrégulières)
- 💡 **Idéal pour :** Petit CPU (Intel Atom / i3, AMD Ryzen 3 / 5, Raspberry Pi)

### 🎨 P2Pool MINI
Équilibre entre fréquence de paiements et stabilité des récompenses.
- ✅ Pool décentralisé
- ✅ Pas de frais
- ✅ Moins de variance que NANO
- ❌ Moins de paiements fréquents que NANO
- 💡 **Idéal pour :** CPU desktop (AMD Ryzen 7 / 9, Intel i5 / i7)

### 🔥 P2Pool FULL
Chaîne complète P2Pool pour gros CPU multithreads.
- ✅ Pool décentralisé
- ✅ Pas de frais
- ✅ Récompenses plus stables (moins de variance)
- ❌ Paiements moins fréquents que MINI/NANO
- 💡 **Idéal pour :** CPU serveur (AMD Threadripper, Intel i9, AMD EPYC, Intel Xeon)

### 🎯 SOLO
Minez directement avec votre nœud personnel.
- ✅ Décentralisé à 100 %
- ✅ Pas de frais
- ❌ Blocs rares, tout ou rien
- 💡 **Idéal pour :** Fermes de gros CPU

### 🌊 MoneroOcean
Pool centralisé avec switching automatique.
- ✅ Interface simple
- ✅ Switching RandomX/Rx/Cn
- ✅ Taux de change natif
- ❌ Pool centralisé
- 💡 **Idéal pour :** Simplicité, moins de bande passante

---

## 📈 Modes XMRig

### 🌿 ÉCO
Mode silencieux et optimisé pour un usage quotidien.
- ✅ 50% des threads activés
- ✅ Consommation électrique minimale
- ✅ Température réduite
- ✅ Ventilateurs silencieux
- ❌ Hashrate réduit de moitié
- 💡 **X3D :** Privilégie les cœurs avec V-Cache 3D pour maximiser l'efficacité RandomX

### ⚡ PERF
Mode performance maximale pour exploiter tout le potentiel du CPU.

- ✅ 100% des threads disponibles
- ✅ Hashrate maximal
- ❌ Consommation électrique élevée
- ❌ Température CPU élevée
- ❌ Ventilateurs bruyants
- 💡 **Astuce :** idéal en hiver pour chauffer la maison

---

## 📋 Configuration Requise

### J’ai développé et optimisé le script pour :
- **OS :** Ubuntu Server 24.04 LTS (x64)
- **Stockage :** SSD ou NVMe 500 Go recommandé pour les nœuds (HDD déconseillé)
- **RAM :** 8 Go minimum (Mode Dual Channel fortement recommandé pour le hashrate)
- **Réseau :** Fibre optique via Câble Ethernet (Wi-Fi déconseillé pour P2Pool)

P2Pool ne tolère pas la latence.

### Pour recevoir vos récompenses :
- Une adresse Monero (obligatoire)
- Une adresse Tari (facultatif)

### 3 points très importants à comprendre :
- Pour recevoir vos récompenses de minage, **utilisez des portefeuilles dédiés au minage** (c’est une question de confidentialité).
- Vos portefeuilles **ne doivent pas être stockés sur votre RIG** (c’est une question de sécurité).
- Pour Monero, vous devez impérativement utiliser **l’adresse principale (“Primary address”)** de votre portefeuille, car c’est la seule compatible avec P2Pool.

---

## 🚀 Installation Rapide

Ce script doit être exécuté en tant que **root**.

```bash
# 1. Télécharger le script
wget https://raw.githubusercontent.com/DIYBYPASS/DIYXMR/main/diyxmr.sh

# 2. Le rendre exécutable
chmod +x diyxmr.sh

# 3. L'exécuter (en root)
sudo ./diyxmr.sh
```

---

## 🤔  Conseil pour le Spec Mining

Pour ceux qui font du Spec Mining (j’en fais partie), dans le TUI, appuyez sur la touche **E**, puis choisissez l’option **3**.
Cela **arrête et désactive** tous les services du stack sans rien supprimer. Vous pourrez alors miner d’autres projets à côté avec 100 % de vos ressources.

Quand le Spec Mining est plus calme, relancez simplement le script : il va checker votre système et **tout remettre en route automatiquement** (services, firewall, etc.).

Dans une France, une Europe et un monde où les gouvernements deviennent **de plus en plus autoritaires** et où les libertés reculent, **le XMR a un bel avenir devant lui**.

---

## ❓ FAQ (Foire Aux Questions)

### Q : Pourquoi le Monero ?
R : Monero est le véritable argent liquide numérique : privé, fongible et conçu pour rester accessible à tous, car n'importe qui peut participer au réseau avec un simple processeur. Son équipe réactive adapte constamment l'algorithme pour neutraliser les ASICs ou les menaces complexes comme le Qubic, tandis que P2Pool répartit la puissance de hachage pour rendre les attaques à 51 % impossibles. Face à l'autoritarisme croissant et aux délistages des bourses, la communauté reste soudée en créant des solutions comme Haveno pour garantir la souveraineté des échanges. Monero réalise la promesse originelle de Bitcoin : une monnaie de résistance réellement décentralisée.

### Q : Pourquoi P2Pool ?
R : Lancé en 2021 par SChernykh, P2Pool est né pour contrer la centralisation des pools géants qui menaçait Monero d'attaques à 51 %. Cette alternative décentralisée supprime l'intermédiaire central pour protéger le réseau de la censure, tout en assurant aux mineurs des paiements aussi réguliers qu'un pool classique.

### Q : Est-ce que DIYXMR est gratuit ?
R : DIYXMR est un outil 100 % gratuit. Il est distribué en modèle "Source Available" (Code Transparent) : cela signifie que le code est entièrement visible pour être audité par sécurité, mais sa modification est interdite. Il n'impose aucune commission automatique (0 % fees). Toute votre puissance de calcul est dirigée vers vos propres portefeuilles par défaut. Le soutien au développeur via le "Dev Mining" reste une option volontaire à activer via le menu, sans aucun frais caché ni forcing.

### Q : Supporte-t-il les GPU ?
R : Non, ce script est optimisé pour le CPU uniquement (RandomX est CPU-friendly). Pour GPU, regardez d'autres outils.

### Q : Combien de temps pour la synchro initiale ?
R : 4-24 heures selon votre connexion et hardware. Utilisez un SSD pour accélérer.

### Q : Pourquoi la synchronisation ralentit-elle fortement vers la fin ?
R : C'est un phénomène tout à fait normal. Les premières années de la blockchain (2014-2017) contiennent des blocs légers qui se téléchargent très vite. À mesure que vous approchez du présent, les blocs deviennent plus lourds et cryptographiquement complexes (plus de transactions, confidentialité renforcée). Votre matériel doit alors vérifier chaque signature mathématique et effectuer des milliers d'écritures disque par seconde, ce qui ralentit naturellement la progression sur les derniers pourcents. Patience, c'est le signe que vous arrivez au sommet de la chaîne.

### Q : Le Merge Mining Tari impacte-t-il le hashrate Monero ?
R : Non, aucun impact. Le Merge Mining Tari utilise le même effort de calcul que Monero pour valider des blocs sur deux réseaux simultanément. Cela n'ajoute aucune charge CPU supplémentaire, vous permettant de cumuler des récompenses Tari en "bonus" sans jamais réduire votre hashrate XMR.

### Q : Le Merge Mining Tari mine-t-il dans P2Pool ?
R : Non, le minage de Tari est individuel. Bien que P2Pool orchestre techniquement le Merge Mining, les récompenses Tari ne sont pas mutualisées entre les membres du pool. Vous ne recevez des jetons que si votre propre machine trouve un bloc valide sur le réseau Tari : c’est donc du minage solo effectué en parallèle de votre participation au pool Monero.

### Q : Pourquoi ne pas utiliser les portefeuilles du RIG pour recevoir les récompenses ?
R : Utiliser une adresse externe protège vos fonds si le rig est infecté par des malwares (courants en spec mining) ou s'il subit une défaillance matérielle totale. En séparant vos clés de cette machine exposée, vous gardez l'accès à votre butin même si le matériel est détruit, défaillant ou piraté. C'est une sécurité vitale pour vos actifs.

### Q : Pourquoi utiliser des portefeuilles dédiés au minage ?
R : Cloisonnez vos revenus pour protéger votre confidentialité. Accumuler des micro-paiements sur votre portefeuille personnel lie directement votre épargne à votre activité de minage. Un portefeuille dédié évite d'exposer l'intégralité de votre historique financier si vous partagez une clé de vue. Votre capital reste ainsi anonyme, déconnecté de l'activité de vos machines.

---

## 💖 Soutenir le Projet

DIYXMR est un projet bénévole, maintenu sur mon temps libre.
Depuis le TUI, appuyez sur la touche D et choisissez parmi ces trois façons de m’encourager :

### 1️⃣ Dev Mining (Tari)
```bash
# Activation via le dashboard
➜ Option 1 : Soutenir le développeur → Dev Mining Tari
```
Exactement 0% CPU additionnel, 0% impact performance.

### 2️⃣ Dev Mining (Monero)
```bash
# Optionnel : une fois par mois pendant 24h
➜ Option 2 : Soutenir le développeur → Dev Mining Monero
```
Ponctuel, sans impact durable sur votre installation.

### 3️⃣ Donation Directe
```bash
# QR Code généré dans le dashboard
Address Monero: 48hPv8m5vvFKd6KcubnpXCdepPYiL28w7ZwMpGZxsK55hBjzB5PkfzyRfb3t3XBxieYmPGDPwdsD8FT3qG1YExC2VVmxs6N
```

---

## 📜 Licence & Droits d'Utilisation

Ce projet n'est **PAS Open Source**. Il est distribué sous une licence **PROPRIÉTAIRE / SOURCE AVAILABLE**.

- **🛡️ Audit & Transparence :** Le code source est rendu public uniquement pour permettre l'audit de sécurité par la communauté et garantir l'absence de code malveillant.
- **✅ Usage Gratuit :** Vous êtes libre de télécharger et d'utiliser ce script gratuitement sur vos machines pour miner.
- **⛔ Interdictions Formelles :** Il est **STRICTEMENT INTERDIT** de modifier le code, de supprimer les crédits, de changer les adresses de donation ou de redistribuer ce projet.

**Garantie :** Ce programme est fourni **SANS AUCUNE GARANTIE**. En l'utilisant, vous acceptez ces conditions.

### ⚠️ Note importante

La rentabilité du minage dépend de votre matériel et du coût de l’électricité. Ce script est un **outil technique** et ne constitue **pas un conseil financier**.

---

## 📚 Ressources & Liens

| Ressource | URL |
|-----------|-----|
| **DIYBYPASS** | https://diybypass.xyz |
| **Monero** | https://github.com/monero-project/monero |
| **P2Pool** | https://github.com/SChernykh/p2pool |
| **XMRig** | https://github.com/xmrig/xmrig |
| **Tari** | https://github.com/tari-project/tari |

---

# Happy Mining! 🚀
