# 🗺️ Roadmap - DIYXMR

Voici la feuille de route de DIYXMR et ses prochaines évolutions pour transformer le projet en un orchestrateur de minage intelligent, modulaire et automatisé.

---

## 🛠 v1.0.0 - Fondations & Refactoring (Prochaine version)
*L'objectif de cette version est la stabilité, la propreté du code et la validation sur les environnements standards.*

* **Refactoring global du script** : Réorganisation du code en fonctions modulaires, séparation de la logique métier (installation, configuration) et de l'interface utilisateur (TUI).
* **Validation des OS** : Tests approfondis et validation de la compatibilité sur Ubuntu Server Minimal (gestion des dépendances manquantes par défaut) et Debian 12 (Stable).
* **Gestion optimisée des erreurs** : Amélioration des retours d'erreurs pour faciliter le débogage de l'utilisateur final.

---

## 🖥️ v1.1.0 - Expérience Utilisateur (UX) & CLI
*Rendre l'interface et l'utilisation quotidienne plus fluides et accessibles.*

* **Arguments CLI avancés** : Ajout de commandes directes sans passer par le TUI (ex: `./diyxmr.sh --logs`, `./diyxmr.sh --donate`, `./diyxmr.sh --clean`).
* **Conseils d'optimisation matérielle** : Analyse automatique du matériel (CPU/RAM) et suggestions de réglages BIOS au lancement (activation XMP/EXPO, Precision Boost Overdrive, vérification approfondie des HugePages).
* **Internationalisation (i18n)** : Support multi-langue (FR/EN) détecté automatiquement via la variable `LANG` ou forcé via le fichier de configuration.
* **Documentation locale** : Génération automatique d'un fichier d'aide local (ex: `/home/worker/readme.txt`) résumant les commandes et les chemins utiles.

---

## 🛡️ v1.2.0 - Sécurité & Résilience
*Renforcer la robustesse du système et le respect de la configuration réseau de l'hôte.*

* **Gestion d'état UFW (Snapshots)** : Sauvegarde automatique des règles UFW existantes lors du premier lancement. Proposition de restauration de cet état initial en cas de désinstallation du stack.
* **Vérification d'intégrité du script** : Validation automatique de l'authenticité des fichiers via vérification du hash (SHA-256) ou de la signature (GPG) avant toute exécution ou mise à jour, garantissant une protection contre les altérations.

---

## ⚡ v1.5.0 - Automatisation & Smart Mining
*Rendre le minage intelligent, adaptatif et économe en fonction du contexte énergétique.*

* **Planificateur Horaire (Scheduler)** : Définition de plages horaires pour basculer automatiquement entre les états : Arrêt / Mode ÉCO / Mode PERF.
* **Intégration API Énergie (EDF)** : Connexion aux API de tarification électrique (ex: Tempo, Heures Creuses). Automatisation du minage selon le coût de l'électricité (ex: passage en Mode ÉCO ou Arrêt les jours "Rouge").
* **Mode "Spec Mining" Avancé** : Amélioration de la fonction d'arrêt temporaire avec désactivation au boot et restauration stricte des règles pare-feu (UFW) d'origine pendant la pause.

---

## 🏗️ v2.0.0 - Architecture & Modularité
*Faire évoluer le script d'un simple nœud local à un outil de déploiement pour fermes de minage.*

* **Modes d'installation modulaires (Stack Modes)** :
    * `Full Stack` (Défaut) : Nœud + P2Pool + Mineur sur la même machine.
    * `Node Only` : Déploiement d'un serveur dédié centralisant la blockchain et le P2Pool pour alimenter d'autres machines.
    * `Miner Only` : Installation ultra-légère (XMRig seul) configurée pour se connecter automatiquement à un nœud distant sur le réseau local (LAN).
* **Support de l'architecture ARM64** : Détection automatique de l'architecture (`uname -m`) et adaptation des téléchargements/compilations pour supporter officiellement les Raspberry Pi 4/5, Orange Pi et les serveurs cloud ARM (ex: Oracle Cloud).
