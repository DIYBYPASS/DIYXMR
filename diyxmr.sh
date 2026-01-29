#!/usr/bin/env bash

# Copyright (c) 2026 DIYBYPASS
# Projet : DIYXMR - Monero Mining Stack
# Version : 1.0
#
# CONDITIONS SUPPLÉMENTAIRES (Article 7b de la GPLv3) :
# 1. ATTRIBUTION : Toute redistribution ou version modifiée doit conserver
#    de manière visible la marque "DIYBYPASS" et le lien "diybypass.xyz".
# 2. INTÉGRITÉ DES DONS : La modification des adresses de donation originales
#    est fortement découragée par l'auteur afin de soutenir la maintenance du projet.
#
# Ce programme est distribué SANS AUCUNE GARANTIE.
# Voir <https://www.gnu.org/licenses/gpl-3.0.html> pour plus de détails.

# shellcheck disable=SC2155,SC2086,SC2034,SC2059,SC1090,SC2002,SC2015

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Durcissement bash : options de sécurité et débogage ───────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
set -Eeuo pipefail
shopt -s extglob
IFS=$'\n\t'
trap 'printf "\e[31m✖  %s:%d : %s (code %s)\e[0m\n" \
      "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" "$?"' ERR

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Exécute en root ───────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
[[ $EUID -eq 0 ]] || {
  printf "\e[31m✖  Exécute en root (sudo ./script.sh)\e[0m\n"
  exit 1
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Initialisation + styles ───────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
clear
sleep 0.1

RESET='\e[0m'
BOLD='\e[1m'
FG_WHITE='\e[97m'
FG_GREEN='\e[32m'
FG_RED='\e[31m'
FG_BLACK='\e[30m'
FG_YELLOW='\e[33m'
FG_BLUE='\e[34m'
FG_CYAN='\e[36m'
FG_MAGENTA='\e[35m'
BG_WHITE='\e[47m'
BG_MAGENTA='\e[45m'
OK="✔"
NO="✖"

# Spinner
spinner() {
  local pid=$1 msg="$2"
  local delay=0.15 spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local clean_msg="\e[97m$msg\e[0m"

  while kill -0 "$pid" 2>/dev/null; do
    for ((i = 0; i < ${#spinstr}; i++)); do
      printf "\r  ${FG_YELLOW}%s${RESET} %b" "${spinstr:$i:1}" "$clean_msg"
      sleep "$delay"
    done
  done
  wait "$pid"
  local rc=$?
  printf "\r\033[K"

  if ((rc == 0)); then
    printf "  ${FG_GREEN}✔${RESET} %b\n" "$clean_msg"
  else
    printf "  ${FG_RED}✖${RESET} %b (code %s)\n" "$clean_msg" "$rc"
  fi
  return $rc
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# En-tête ───────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "${FG_WHITE}${BOLD}"
printf '▣%.0s' {1..64}
printf "\n"

# Branding
printf "🚀 diyXMR v1.0${RESET}  ${FG_MAGENTA}— Stack de minage Monero auto-géré\n"
printf "${FG_YELLOW}${BOLD}🄯  diybypass.xyz${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '▣%.0s' {1..64}
printf "\n\n${RESET}"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Constantes ────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
WORKER_HOME=/home/worker
P2POOL_PORT=37888
STRATUM_PORT=3333
CONFIG_FILE="/etc/diyxmr.conf"
REFRESH_INTERVAL=120
LAST_VERSION_CHECK=0
VERSION_CHECK_INTERVAL=3600

INSTALLED_P2POOL=""
P2POOL_VERSION=""

INSTALLED_TARI=""
TARI_VERSION=""
TARI_GRPC_PORT=18142
TARI_P2P_PORT=18189
GRUB_FILE="/etc/default/grub"

DEV_XMR_WALLET="48hPv8m5vvFKd6KcubnpXCdepPYiL28w7ZwMpGZxsK55hBjzB5PkfzyRfb3t3XBxieYmPGDPwdsD8FT3qG1YExC2VVmxs6N"
DEV_TARI_WALLET="12CLp1Enfi96pa7g6jm27E4Uaduuv5rRCD9vCD8MvCwsh5mrTXpvzmjEMG1prYCYSSz3bX7Yyt9mpP8T8d1P2fGN8wN"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Formulaire de Configuration Interactif (TUI) ──────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
configure_wizard() {
  # 1. On charge la config actuelle (si elle existe) pour avoir les valeurs par défaut
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

  # 1. Choix automatique du Pool (si pas encore défini)
  if [[ -z "${MINING_MODE:-}" ]]; then
    local ram_mb=$(free -m | awk '/Mem:/ {print $2}')
    local cpu_cores=$(nproc)

    # Si machine faible (Moins de 4Go RAM ou Moins de 4 Threads) -> NANO
    if ((ram_mb < 3800 || cpu_cores < 4)); then
      MINING_MODE="pool-nano"
    else
      # Sinon -> MINI (Le standard le plus rentable pour CPU)
      MINING_MODE="pool-mini"
    fi
  fi

  # -- Variables par défaut si vides --
  MONERO_ADDRESS="${MONERO_ADDRESS:-}"
  TARI_ADDRESS="${TARI_ADDRESS:-}"
  MINING_MODE="${MINING_MODE:-pool-mini}"
  XMRIG_MODE="${XMRIG_MODE:-perf}"

  # --- DÉBUT MODIFICATION SSH (Détection intelligente) ---
  DETECTED_PORT="22"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    DETECTED_PORT=$(echo "$SSH_CONNECTION" | awk '{print $4}')
  elif [[ -n "${SSH_CLIENT:-}" ]]; then
    DETECTED_PORT=$(echo "$SSH_CLIENT" | awk '{print $3}')
  fi

  # Initialisation de SSH_PORT :
  if [[ -z "${SSH_PORT:-}" ]]; then
    if [[ "${ALLOW_SSH:-1}" -eq 0 ]]; then
      SSH_PORT=0
    else
      SSH_PORT="$DETECTED_PORT"
    fi
  fi
  # --- FIN MODIFICATION SSH ---

  # -- Sauvegarde des valeurs d'origine pour comparaison --
  local orig_xmr="$MONERO_ADDRESS"
  local orig_tari="$TARI_ADDRESS"
  local orig_mode="$MINING_MODE"
  local orig_xmrig="$XMRIG_MODE"
  local orig_ssh_port="$SSH_PORT"

  # -- Données pour les listes --
  MINING_MODES_KEYS=("solo" "pool-nano" "pool-mini" "pool-full" "moneroocean")
  MINING_MODES_LBL=("SOLO (Nœud personnel)" "P2Pool NANO (Très faible CPU)" "P2Pool MINI (CPU Standard)" "P2Pool FULL (Gros CPU)" "MoneroOcean (Auto-switch)")

  XMRIG_MODES_KEYS=("eco" "perf")
  XMRIG_MODES_LBL=("Éco (Silencieux/Efficace)" "Perf (Max Hashrate)")

  # -- Fonction locale pour trouver le label --
  _get_lbl() {
    local key="$1"
    shift
    local keys=("${!1}")
    shift
    local lbls=("${!1}")
    for i in "${!keys[@]}"; do [[ "${keys[$i]}" == "$key" ]] && echo "${lbls[$i]}" && return; done
    echo "Inconnu"
  }

  # -- Fonction locale pour le style (Gras/Blanc si modifié) --
  _style() {
    local current="$1"
    local original="$2"
    local text="$3"

    if [[ "$current" != "$original" ]]; then
      echo "${BOLD}${FG_WHITE}$text${RESET}"
    else
      echo "${FG_WHITE}$text${RESET}"
    fi
  }

  while true; do
    clear
    BOX_WIDTH=56
    TITLE="CONFIGURATION DU STACK"

    title_len=${#TITLE}
    padding=$(((BOX_WIDTH - title_len) / 2))
    pad=$(printf ' %.0s' $(seq 1 $padding))
    end_pad_len=$((BOX_WIDTH - title_len - padding))
    end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

    printf "${BOLD}${FG_CYAN}╔"
    printf '═%.0s' $(seq 1 $BOX_WIDTH)
    printf "╗\n"
    printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"
    printf "╚"
    printf '═%.0s' $(seq 1 $BOX_WIDTH)
    printf "╝${RESET}\n\n"

    # --- Affichage de l'état actuel ---

    # 1. Monero
    if [[ -z "$MONERO_ADDRESS" ]]; then
      val_xmr="${FG_RED}(Requis)${RESET}"
    else
      display_xmr="${MONERO_ADDRESS:0:12}...${MONERO_ADDRESS: -12}"
      val_xmr=$(_style "$MONERO_ADDRESS" "$orig_xmr" "$display_xmr")
    fi
    echo -e "  ${FG_GREEN}1)${RESET} Adresse Monero  : $val_xmr"

    # 2. Tari
    if [[ -z "$TARI_ADDRESS" ]]; then
      if [[ "$TARI_ADDRESS" != "$orig_tari" ]]; then
        val_tari="${BOLD}${FG_WHITE}(Désactivé)${RESET}"
      else
        val_tari="${FG_WHITE}(Désactivé)${RESET}"
      fi
    else
      display_tari="${TARI_ADDRESS:0:12}...${TARI_ADDRESS: -12}"
      val_tari=$(_style "$TARI_ADDRESS" "$orig_tari" "$display_tari")
    fi
    echo -e "  ${FG_GREEN}2)${RESET} Adresse Tari    : $val_tari"

    # 3. Mode Minage
    lbl_mode=$(_get_lbl "$MINING_MODE" MINING_MODES_KEYS[@] MINING_MODES_LBL[@])
    val_mode=$(_style "$MINING_MODE" "$orig_mode" "$lbl_mode")
    echo -e "  ${FG_GREEN}3)${RESET} Mode de Minage  : $val_mode"

    # 4. Profil CPU
    lbl_cpu=$(_get_lbl "$XMRIG_MODE" XMRIG_MODES_KEYS[@] XMRIG_MODES_LBL[@])
    val_cpu=$(_style "$XMRIG_MODE" "$orig_xmrig" "$lbl_cpu")
    echo -e "  ${FG_GREEN}4)${RESET} Profil CPU      : $val_cpu"

    # 5. SSH (Affichage dynamique du port)
    if [[ "$SSH_PORT" -gt 0 ]]; then
      txt_ssh="PORT $SSH_PORT"
    else
      txt_ssh="BLOQUÉ (0)"
    fi
    val_ssh=$(_style "$SSH_PORT" "$orig_ssh_port" "$txt_ssh")
    echo -e "  ${FG_GREEN}5)${RESET} Accès SSH       : $val_ssh"

    echo -e "\n  ────────────────────────────────────────────────────────"

    # Détection des changements (incluant SSH_PORT)
    has_changes=0
    if [[ "$MONERO_ADDRESS" != "$orig_xmr" || "$TARI_ADDRESS" != "$orig_tari" ||
      "$MINING_MODE" != "$orig_mode" || "$XMRIG_MODE" != "$orig_xmrig" || "$SSH_PORT" != "$orig_ssh_port" ]]; then
      has_changes=1
    fi

    # 6. Validation
    if [[ -n "$MONERO_ADDRESS" ]]; then
      if [[ $has_changes -eq 1 ]]; then
        echo -e "  ${FG_GREEN}6)${RESET} ${FG_GREEN}✔ APPLIQUER ET DÉMARRER${RESET}"
      else
        echo -e "  ${FG_WHITE}6)${RESET} ✔ SAUVEGARDER ET DÉMARRER"
      fi
    else
      echo -e "  ${FG_WHITE}6)${RESET} ⚿ Sauvegarder (Adresse Monero requise)"
    fi

    echo -e "  ${FG_CYAN}0)${RESET} Annuler / Sortir"

    # --- Saisie ---
    read -rp $'\n➜  Modifier option (0-6) : ' choice
    case "$choice" in
      1)
        # Modification Monero (Vide = Annuler)
        echo -e "\n${FG_CYAN}Colle ton adresse Monero (Entrée pour annuler) :${RESET}"
        read -r input_addr

        if [[ -z "$input_addr" ]]; then
          echo -e "${FG_YELLOW}↩  Annulé.${RESET}"
          sleep 0.5
        elif [[ "$input_addr" =~ ^[48][0-9AB][1-9A-HJ-NP-Za-km-z]{92,105}$ ]]; then
          MONERO_ADDRESS="$input_addr"
        else
          echo -e "${FG_RED}✖ Format invalide.${RESET}"
          sleep 1.5
        fi
        ;;

      2)
        # Modification Tari (0 = Annuler, Vide = Désactiver)
        echo -e "\n${FG_CYAN}Adresse Tari (Entrée=Désactiver, tape '0' pour Annuler) :${RESET}"
        read -r input_tari

        if [[ "$input_tari" == "0" ]]; then
          echo -e "${FG_YELLOW}↩  Annulé.${RESET}"
          sleep 0.5
        elif [[ -z "$input_tari" ]]; then
          TARI_ADDRESS=""
          echo -e "${FG_YELLOW}⚪ Tari désactivé.${RESET}"
          sleep 0.5
        elif [[ ${#input_tari} -ge 50 ]]; then
          TARI_ADDRESS="$input_tari"
        else
          echo -e "${FG_RED}✖ Format invalide.${RESET}"
          sleep 1.5
        fi
        ;;

      3)
        # Menu Minage (0 = Retour)
        echo -e "\n${FG_CYAN}--- Choisis le mode de minage ---${RESET}"
        echo "  1) Solo (Nœud perso)"
        echo "  2) P2Pool Nano (Petit CPU)"
        echo "  3) P2Pool Mini (Standard)"
        echo "  4) P2Pool Full (Gros CPU)"
        echo "  5) MoneroOcean (Switching)"
        echo -e "  ${FG_YELLOW}0) Retour${RESET}"
        read -rp "➜ Ton choix (0-5) : " m_choice
        case "$m_choice" in
          1) MINING_MODE="solo" ;;
          2) MINING_MODE="pool-nano" ;;
          3) MINING_MODE="pool-mini" ;;
          4) MINING_MODE="pool-full" ;;
          5) MINING_MODE="moneroocean" ;;
          0)
            echo -e "${FG_YELLOW}↩  Retour.${RESET}"
            sleep 0.5
            ;;
          *)
            echo -e "${FG_RED}✖ Invalide.${RESET}"
            sleep 1
            ;;
        esac
        ;;

      4)
        # Bascule simple (Toggle)
        if [[ "$XMRIG_MODE" == "eco" ]]; then XMRIG_MODE="perf"; else XMRIG_MODE="eco"; fi
        ;;

      5)
        # Modification Port SSH (Nouvelle logique interactive)
        echo -e "\n${FG_CYAN}--- Configuration SSH ---${RESET}"
        echo -e "Port détecté actuel : ${BOLD}$DETECTED_PORT${RESET}"
        echo -e "Entrez ${BOLD}0${RESET} pour bloquer totalement SSH."
        echo -e "Appuyez sur ${BOLD}Entrée${RESET} pour conserver le port $DETECTED_PORT."

        read -rp "➜ Port SSH souhaité : " input_ssh

        if [[ -z "$input_ssh" ]]; then
          # L'utilisateur a juste fait Entrée, on prend le port détecté par défaut
          SSH_PORT="$DETECTED_PORT"
          echo -e "${FG_YELLOW}On conserve le port $SSH_PORT.${RESET}"
          sleep 0.5
        elif [[ "$input_ssh" =~ ^[0-9]+$ ]]; then
          SSH_PORT="$input_ssh"
          if [[ "$SSH_PORT" -eq 0 ]]; then
            echo -e "${FG_RED}SSH sera désactivé.${RESET}"
            sleep 0.5
          else
            echo -e "${FG_GREEN}Port SSH fixé à $SSH_PORT.${RESET}"
            sleep 0.5
          fi
        else
          echo -e "${FG_RED}✖ Ce n'est pas un nombre valide.${RESET}"
          sleep 1
        fi
        ;;

      6)
        if [[ -n "$MONERO_ADDRESS" ]]; then
          echo -e "\n${FG_GREEN}💾 Sauvegarde de la configuration...${RESET}"
          # Sauvegarde avec la variable SSH_PORT
          cat <<EOF >"$CONFIG_FILE"
MONERO_ADDRESS="$MONERO_ADDRESS"
TARI_ADDRESS="$TARI_ADDRESS"
MINING_MODE="$MINING_MODE"
XMRIG_MODE="$XMRIG_MODE"
SSH_PORT=$SSH_PORT
INITIAL_SETUP_DONE=yes
EOF
          chmod 600 "$CONFIG_FILE"
          sleep 1
          echo -e "${FG_GREEN}🚀 Relance du script...${RESET}"
          sleep 1
          exec "$0"
        else
          echo -e "\n${FG_RED}⚠  Tu dois renseigner l'adresse Monero (Option 1).${RESET}"
          sleep 2
        fi
        ;;

      0)
        # --- LOGIQUE DE RELANCE DEMANDÉE ---
        echo -e "\n${FG_YELLOW}↩️  Annulation...${RESET}"
        sleep 0.5

        # Vérifier l'état de la configuration
        if [[ -f "$CONFIG_FILE" ]] && grep -q '^INITIAL_SETUP_DONE=' "$CONFIG_FILE"; then
          # Config existe : on annule les modifications et on retourne au dashboard
          echo -e "${FG_CYAN}🔄 Relance du tableau de bord...${RESET}"

          # Restaurer le marqueur à "yes" (annule les modifications)
          sed -i 's/^INITIAL_SETUP_DONE=.*/INITIAL_SETUP_DONE=yes/' "$CONFIG_FILE"

          sleep 1
          exec "$0"
        else
          # Pas de config : première installation abandonnée
          echo -e "${FG_RED}Installation abandonnée.${RESET}"
          exit 0
        fi
        ;;

      *)
        echo -e "${FG_RED}✗${RESET} Choix invalide."
        sleep 1
        ;;
    esac
  done
}

# Charger la configuration existante si elle existe
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Lancer le wizard automatiquement SI la config n'est pas validée
if [[ "${INITIAL_SETUP_DONE:-}" != "yes" ]]; then
  configure_wizard
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Définir les ports selon le mode ───────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
case "$MINING_MODE" in
  solo)
    P2POOL_PORT=""
    STRATUM_PORT=""
    ;;
  pool-nano)
    P2POOL_PORT=37890
    STRATUM_PORT=37887
    ;;
  pool-mini)
    P2POOL_PORT=37888
    STRATUM_PORT=37887
    ;;
  pool-full)
    P2POOL_PORT=37889
    STRATUM_PORT=37887
    ;;
  moneroocean)
    P2POOL_PORT=""
    STRATUM_PORT=""
    ;;
esac

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Utilitaires ───────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
github_latest_tag() {
  local repo="$1"
  local api_url="https://api.github.com/repos/$repo/releases/latest"
  local tag

  tag=$(
    { curl -fsSL -H 'Accept: application/vnd.github+json' \
      -H 'User-Agent: Mozilla/5.0' \
      "$api_url" | jq -r .tag_name; } 2>/dev/null
  )

  if [[ -z "$tag" || "$tag" == "null" ]]; then
    return 1
  else
    echo "$tag"
    return 0
  fi
}

refresh_latest_versions() {
  MONERO_VERSION=$(github_latest_tag monero-project/monero || echo "")
  P2POOL_VERSION=$(github_latest_tag SChernykh/p2pool || echo "")
  TARI_VERSION=$(github_latest_tag tari-project/tari || echo "")
  XMRIG_VERSION=$(github_latest_tag xmrig/xmrig || echo "")
}

print_status() {
  local rc="$1"
  local msg="\e[97m$2\e[0m"

  if ((rc == 0)); then
    printf "  ${FG_GREEN}✔${RESET} %b\n" "$msg"
  else
    printf "  ${FG_RED}✖${RESET} %b\n" "$msg"
  fi
}

verify_archive() {
  local label="$1" archive="$2" version="$3"
  local url_hash="$4" url_sig="$5" gpg_url="$6"
  local expected_name="$7" format="$8"

  local tmp_dir
  tmp_dir=$(mktemp -d)

  # Télécharger les fichiers nécessaires (Avec User-Agent pour éviter 403)
  curl -fsSL -A "Mozilla/5.0" "$url_hash" -o "$tmp_dir/HASHES" &
  spinner $! "Téléchargement HASHES ($label)"
  if [[ -n "$url_sig" ]]; then
    curl -fsSL -A "Mozilla/5.0" "$url_sig" -o "$tmp_dir/HASHES.sig" &
    spinner $! "Téléchargement signature ($label)"
  fi

  # Importer la clé GPG si manquante
  if ! gpg --list-keys "$gpg_url" &>/dev/null; then
    curl -fsSL -A "Mozilla/5.0" "$gpg_url" | gpg --import &>/dev/null &
    spinner $! "Import de la clé GPG ($label)"
  fi

  # Vérification GPG si signature présente
  if [[ -s "$tmp_dir/HASHES.sig" ]]; then
    gpg --verify "$tmp_dir/HASHES.sig" "$tmp_dir/HASHES" &>/dev/null &
    spinner $! "Vérification GPG de la signature ($label)"
  else
    gpg --verify "$tmp_dir/HASHES" &>/dev/null &
    spinner $! "Vérification GPG ($label)"
  fi

  # Extraction du hash attendu
  local expected actual
  case "$format" in
    "simple")
      expected=$(grep "$expected_name" "$tmp_dir/HASHES" | awk '{print $1}')
      ;;
    "xmrig")
      expected=$(awk -v name="$expected_name" '{
        gsub(/^[*\\.\\/]+/, "", $2);
        if ($2 == name) print $1
      }' "$tmp_dir/HASHES")
      ;;
    "p2pool")
      expected=$(awk -v name="$expected_name" '
        $1 == "Name:" && $2 == name { getline; getline; print $2 }
      ' "$tmp_dir/HASHES")
      ;;
    *)
      echo "✖ Format de hash inconnu : $format"
      exit 1
      ;;
  esac

  actual=$(sha256sum "$archive" | awk '{print $1}')

  if [[ "$expected" != "$actual" || -z "$expected" ]]; then
    print_status 1 "SHA256 invalide pour l’archive $label"
    echo -e "${FG_RED}Attendu : $expected\nTrouvé  : $actual${RESET}"
    exit 1
  fi

  print_status 0 "Intégrité SHA256 vérifiée pour $label"
  rm -rf "$tmp_dir"
}

fetch_latest_version() {
  local label="$1" repo="$2" outvar="$3"
  local tmp_file="/tmp/version_$outvar"

  (
    if tag=$(github_latest_tag "$repo" 2>/dev/null); then
      echo "$outvar=\"$tag\""
      exit 0
    else
      echo "$outvar=\"\""
      exit 0
    fi
  ) >"$tmp_file" &

  spinner $! "Recherche version $label"
  source "$tmp_file"
  rm -f "$tmp_file"

  if [[ -z "${!outvar}" ]]; then
    local found_local
    found_local=$(command -v "${label,,}" || find "$WORKER_HOME" -maxdepth 1 -type d -iname "${label,,}-*" 2>/dev/null)

    if [[ -n "$found_local" ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} \e[97m%s : quota GitHub atteint — utilisation de la version actuelle.\e[0m\n" "$label"
    else
      printf "  ${FG_RED}✖${RESET} \e[97m%s : quota atteint ET aucune version locale trouvée.\e[0m\n" "$label"
    fi
  fi
}

show_component() {
  local name="$1" current="$2" latest="$3"
  local padname=$(printf "%-8s" "$name")

  if [[ -z "$latest" || "$latest" == "v0.0.0" ]]; then
    if [[ -n "$current" ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} \e[97m%s : %s (dernière version distante inconnue)\e[0m\n" "$padname" "$current"
    else
      printf "  ${FG_RED}✖${RESET} \e[97m%s : aucune version disponible\e[0m\n" "$padname"
    fi
    return
  fi

  if [[ "$current" == "$latest" && -n "$current" ]]; then
    printf "  ${FG_GREEN}✔${RESET} \e[97m%s : %s (à jour)\e[0m\n" "$padname" "$current"
  else
    printf "  ${FG_YELLOW}⇧${RESET} \e[97m%s : %s → %s\e[0m\n" "$padname" "${current:-Ø}" "$latest"
  fi
}

download_and_extract() {
  local url="$1"
  local dest_dir="$2"
  local version="$3"
  local tmp_file
  tmp_file=$(mktemp)

  # --- GESTION SPÉCIALE TARI (ZIP avec détection automatique) ---
  if [[ $url == *github.com/tari-project/tari/releases/download* && -n ${version:-} ]]; then

    local api_url="https://api.github.com/repos/tari-project/tari/releases/tags/${version}"
    local assets_json=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" -H "User-Agent: diyxmr-script" "$api_url" 2>/dev/null)

    # Trouver le fichier mainnet x86_64 (pas esme qui est le testnet)
    local zip_filename=$(echo "$assets_json" | grep -oP '"name":\s*"\K[^"]*mainnet[^"]*linux-x86_64\.zip(?=")' | grep -v '\.sha256' | head -n1)

    if [[ -z "$zip_filename" ]]; then
      printf "  ${FG_RED}✖${RESET} Impossible de trouver le fichier Tari mainnet pour ${version}\n"
      rm -f "$tmp_file"
      return 1
    fi

    local zip_url="https://github.com/tari-project/tari/releases/download/${version}/${zip_filename}"
    local checksum_url="${zip_url}.sha256"

    # Télécharger le ZIP
    rm -f "$tmp_file"
    curl --fail -L --retry 3 -sS "$zip_url" -o "$tmp_file" &
    spinner $! "Téléchargement ${zip_filename}"

    if [[ ! -f "$tmp_file" || ! -s "$tmp_file" ]]; then
      printf "  ${FG_RED}✖${RESET} Échec du téléchargement de Tari\n"
      return 1
    fi

    # Vérifier le checksum SHA256
    local checksum_file
    checksum_file=$(mktemp)
    if curl -fsSL "$checksum_url" -o "$checksum_file" 2>/dev/null; then
      local expected_hash=$(cat "$checksum_file" | awk '{print $1}')
      local actual_hash=$(sha256sum "$tmp_file" | awk '{print $1}')

      if [[ -n "$expected_hash" && "$expected_hash" != "$actual_hash" ]]; then
        printf "  ${FG_RED}✖${RESET} SHA256 invalide pour Tari\n"
        printf "     Attendu: %s\n" "$expected_hash"
        printf "     Actuel:  %s\n" "$actual_hash"
        rm -f "$checksum_file" "$tmp_file"
        return 1
      fi
      printf "  ${FG_GREEN}✔${RESET} Intégrité SHA256 vérifiée pour Tari\n"
      rm -f "$checksum_file"
    else
      printf "  ${FG_YELLOW}⚠${RESET} Checksum non disponible, extraction sans vérification\n"
    fi

    # Extraire le ZIP
    local extract_dir
    extract_dir=$(mktemp -d)
    printf "  ${FG_YELLOW}⠋${RESET} Extraction du package Tari..."

    if unzip -q -o "$tmp_file" -d "$extract_dir" >/dev/null 2>&1; then
      printf "\r  ${FG_GREEN}✔${RESET} Extraction du package Tari réussie\n"
    else
      printf "\r  ${FG_RED}✖${RESET} Échec de l'extraction Tari\n"
      rm -rf "$extract_dir" "$tmp_file"
      return 1
    fi

    # Créer le dossier de destination final
    mkdir -p "$dest_dir/tari-${version}"

    # 1. Trouver où se cache le binaire principal pour localiser le bon dossier
    local bin_path=$(find "$extract_dir" -name "minotari_node" -type f 2>/dev/null | head -n1)

    if [[ -f "$bin_path" ]]; then
      # 2. Identifier le dossier parent contenant tous les outils
      local source_dir="${bin_path%/*}"

      # 3. Tout copier vers le dossier final (Node, Wallet, Miner...)
      cp -r "$source_dir"/* "$dest_dir/tari-${version}/"

      # 4. Rendre tous les outils exécutables
      chmod +x "$dest_dir/tari-${version}/"* 2>/dev/null

      printf "  ${FG_GREEN}✔${RESET} Suite Tari complète installée (Node, Wallet, Miner...)\n"
    else
      printf "  ${FG_RED}✖${RESET} Impossible de trouver les binaires Tari dans l'archive\n"
      rm -rf "$extract_dir" "$tmp_file"
      return 1
    fi

    # Nettoyer
    rm -rf "$extract_dir" "$tmp_file"
    return 0
  fi

  curl --fail -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --retry 3 -sS "$url" -o "$tmp_file" &
  spinner $! "Téléchargement $(basename "$url")"

  # --- VÉRIFICATIONS DE HASH ---
  if [[ $url == *getmonero.org* && -n ${version:-} ]]; then
    local hash_file="$dest_dir/SHA256SUMS"
    local hash_url_official="https://www.getmonero.org/downloads/hashes.txt"
    local hash_url_github="https://github.com/monero-project/monero/releases/download/${version}/SHA256SUMS"
    local hash_ok=0

    printf "  ${FG_YELLOW}⠙${RESET} Récupération signatures Monero..."

    # Tentative 1 : Site Officiel avec User-Agent
    if curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --fail "$hash_url_official" -o "$hash_file"; then
      hash_ok=1
    else
      # Tentative 2 : GitHub Fallback
      if curl -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --fail "$hash_url_github" -o "$hash_file"; then
        hash_ok=1
      fi
    fi

    if ((hash_ok == 0)); then
      printf "\r\033[K  ${FG_RED}✖${RESET} Échec critique : Impossible de récupérer les hashes Monero\n"
      rm -f "$tmp_file"
      exit 1
    fi

    # Vérification Hash
    local filename=$(basename "$url")
    local expected=$(grep "$filename" "$hash_file" | awk '{print $1}')
    local actual=$(sha256sum "$tmp_file" | awk '{print $1}')

    if [[ "$expected" == "$actual" && -n "$expected" ]]; then
      printf "\r\033[K  ${FG_GREEN}✔${RESET} Intégrité Monero validée (SHA256)\n"
      rm -f "$hash_file"
    else
      printf "\r\033[K  ${FG_RED}⚠${RESET} Hash Monero invalide !\n"
      rm -f "$tmp_file" "$hash_file"
      exit 1
    fi

  elif [[ $url == *github.com/xmrig/xmrig* && -n ${version:-} ]]; then
    verify_archive "XMRig" "$tmp_file" "$version" \
      "https://github.com/xmrig/xmrig/releases/download/${version}/SHA256SUMS" \
      "https://github.com/xmrig/xmrig/releases/download/${version}/SHA256SUMS.sig" \
      "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x446A53638BE94409" \
      "xmrig-${version#v}-linux-static-x64.tar.gz" "xmrig"

  elif [[ $url == *github.com/SChernykh/p2pool* && -n ${version:-} ]]; then
    verify_archive "P2Pool" "$tmp_file" "$version" \
      "https://github.com/SChernykh/p2pool/releases/download/${version}/sha256sums.txt.asc" "" \
      "https://p2pool.io/SChernykh.asc" \
      "p2pool-${version}-linux-x64.tar.gz" "p2pool"
  fi

  # --- EXTRACTION SELON L'EXTENSION ---
  if [[ "$url" == *.zip ]]; then
    unzip -q -o "$tmp_file" -d "$dest_dir" &
    spinner $! "Extraction $(basename "$url")"
  else
    tar -xf "$tmp_file" -C "$dest_dir" &
    spinner $! "Extraction $(basename "$url")"
  fi

  rm -f "$tmp_file"
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Attendre qu’un service ouvre son port ─────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
wait_service_port() {
  local service="$1" port="$2" timeout="$3" restart="${4:-0}"
  local msg="$service démarré (port $port)"
  local delay=0.15 spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 t rc

  ((restart)) && systemctl restart "$service" &>/dev/null
  sleep 1

  printf "  ${FG_YELLOW}%s${RESET} %s" "${spinstr:0:1}" "$msg"
  for ((t = timeout; t > 0; t--)); do
    if ss -tunlp | grep -q ":${port}"; then
      rc=0
      break
    fi
    sleep "$delay"
    i=$(((i + 1) % ${#spinstr}))
    printf "\r\033[K  ${FG_YELLOW}%s${RESET} %s" "${spinstr:$i:1}" "$msg"
  done

  rc=${rc:-1}
  printf "\r\033[K"
  if ((rc == 0)); then
    printf "  ${FG_GREEN}✔${RESET} %s\n" "$msg"
  else
    printf "  ${FG_RED}✖${RESET} %s\n" "$msg"
  fi

  return "$rc"
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Attente de l’API RPC Monero (Mode PATIENT : Pas de restart, juste de l'attente) ───────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
wait_rpc_ready() {

  local retries=60 delay=2 spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0 tries=0

  while ((tries < retries)); do

    output=$(curl -s -w "%{http_code}" -o /dev/null http://127.0.0.1:18081/get_info 2>/dev/null || echo "000")

    if [[ "$output" == "200" ]]; then
      printf "\r\033[K  ${FG_GREEN}✔${RESET} API Monero disponible (port 18081)\n"
      return 0
    fi

    printf "\r\033[K  ${FG_YELLOW}%s${RESET} Attente de l’API Monero... (Code: %s) " "${spinstr:$i:1}" "$output"

    sleep "$delay"
    i=$(((i + 1) % ${#spinstr}))
    tries=$((tries + 1))
  done

  printf "\r\033[K  ${FG_RED}✖${RESET} API Monero toujours indisponible après 2 minutes.\n"

  return 1
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Vérifier l'inscription XMRvsBEAST ──────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
check_xmrvsbeast() {
  local address="$1"

  if [[ -z "$address" ]]; then
    echo "unknown"
    return 0
  fi

  # API correcte
  local api_url="https://xmrvsbeast.com/cgi-bin/p2pool_bonus_history_api.cgi?address=${address}"
  local response=$(curl -sf --max-time 5 --connect-timeout 3 "$api_url" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    echo "unknown"
    return 0
  fi

  # CORRECTION : Chercher "donor_" (clés réelles du JSON)
  if echo "$response" | grep -qi "donor_"; then
    echo "registered"
    return 0
  elif echo "$response" | grep -qi "ERROR.*not registered"; then
    echo "not_registered"
    return 0
  else
    echo "unknown"
    return 0
  fi
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Vérification des unités systemd ───────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
ensure_unit() {
  local unit_name="$1"
  local target="/etc/systemd/system/$unit_name"
  local restart_var="RESTART_${unit_name^^}"
  restart_var="${restart_var//./_}"

  if ! diff -q <(echo "$2") "$target" &>/dev/null; then
    echo "$2" >"$target"
    chmod 644 "$target"
    printf "  ${FG_YELLOW}⚙${RESET} \e[97m%-18s : synchronisée\e[0m\n" "$unit_name"
    systemctl daemon-reexec
    eval "$restart_var=1"
  else
    printf "  ${FG_GREEN}✔${RESET} \e[97m%-18s : déjà conforme\e[0m\n" "$unit_name"
  fi
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Force le service à être "enabled" et "active" ─────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
ensure_running_enabled() {
  local s="$1"
  local changed=0

  if ! systemctl is-enabled --quiet "$s"; then
    systemctl enable "$s" >/dev/null 2>&1
    changed=1
    printf "  ${FG_YELLOW}✚${RESET} %s activé au démarrage\n" "$s"
  fi

  if ! systemctl is-active --quiet "$s"; then
    systemctl start "$s"
    changed=1
    printf "  ${FG_YELLOW}▶${RESET} %s démarré\n" "$s"
  fi

  # Si on n’a rien changé, on l’indique
  if ((changed == 0)); then
    printf "  ${FG_GREEN}✔${RESET} %s déjà actif & activé\n" "$s"
  fi
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Installation, version, mise à jour et service ─────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
describe_component() {
  local name="$1"
  local display_name="$2"
  local version="$3"
  local latest="$4"
  local service="$5"

  # Vérifier installation
  if [[ -z "$version" ]]; then
    printf "  ${FG_RED}✖${RESET} ${FG_WHITE}${display_name} n'est pas installé, son service est inactif.${RESET}\n"
    return
  fi

  # Vérifier état du service
  local is_active
  is_active=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")

  if [[ "$is_active" != "active" ]]; then
    printf "  ${FG_RED}✖${RESET} ${FG_WHITE}${display_name} est installé mais son service est arrêté.${RESET}\n"
    return
  fi

  # Calcul de l’uptime
  local since_str="—"
  local uptime_monotonic now elapsed uptime_d uptime_h uptime_m

  uptime_monotonic=$(systemctl show -p ActiveEnterTimestampMonotonic "$service" 2>/dev/null | awk -F= '{print $2}')
  now=$(awk '{print int($1)}' /proc/uptime)

  if [[ "$uptime_monotonic" =~ ^[0-9]+$ ]]; then
    elapsed=$((now - (uptime_monotonic / 1000000)))
    uptime_d=$((elapsed / 86400))
    uptime_h=$(((elapsed % 86400) / 3600))
    uptime_m=$(((elapsed % 3600) / 60))
    since_str="depuis ${uptime_d}j${uptime_h}h${uptime_m}m"
  fi

  # Affichage final
  if [[ -z "$latest" || "$latest" == "v0.0.0" ]]; then
    printf "  ${FG_YELLOW}⚠${RESET} ${FG_WHITE}${display_name} est installé (version distante inconnue), son service est actif (${since_str}).${RESET}\n"
  elif [[ "$version" == "$latest" ]]; then
    printf "  ${FG_GREEN}✔${RESET} ${FG_WHITE}${display_name} est installé et à jour, son service est actif (${since_str}).${RESET}\n"
  else
    printf "  ${FG_YELLOW}⚠${RESET} ${FG_WHITE}${display_name} est installé mais n'est pas à jour, son service est actif (${since_str}).${RESET}\n"
  fi
}

#############################################################################################################
#############################################################################################################
#############################################################################################################
#####                                                                                                   #####
##### INITIALISATION DU SCRIPT                                                                          #####
##### Ce bloc contient toutes les étapes d’initialisation                                               #####
#####                                                                                                   #####
#############################################################################################################
#############################################################################################################
#############################################################################################################

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Résumé de configuration utilisateur ───────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}📝  Résumé de la configuration choisie${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# Adresse abrégée + type
short_addr="${MONERO_ADDRESS:0:11}…${MONERO_ADDRESS: -6}"
type="standard"
[[ $MONERO_ADDRESS =~ ^8 ]] && type="sous-adresse"
[[ $MONERO_ADDRESS =~ ^4[0-9AB] && ${#MONERO_ADDRESS} -gt 100 ]] && type="adresse intégrée"

# Adresse Tari abrégée (si configurée)
if [[ -n "$TARI_ADDRESS" ]]; then
  short_tari="${TARI_ADDRESS:0:11}…${TARI_ADDRESS: -6}"
else
  short_tari=""
fi

# Libellé lisible pour le mode de performance
case "$XMRIG_MODE" in
  perf) mode_label="performance" ;;
  eco) mode_label="économique" ;;
  *) mode_label="inconnu" ;;
esac

# Libellé lisible pour le mode de minage
case "$MINING_MODE" in
  solo) mining_label="SOLO" ;;
  pool-nano) mining_label="P2Pool NANO" ;;
  pool-mini) mining_label="P2Pool MINI" ;;
  pool-full) mining_label="P2Pool FULL" ;;
  moneroocean) mining_label="MoneroOcean" ;;
  *) mining_label="inconnu" ;;
esac

# Affichage
printf "  ${FG_GREEN}✔${RESET} Mode de minage   : %s\n" "$mining_label"
if [[ -n "$TARI_ADDRESS" ]]; then
  printf "  ${FG_GREEN}✔${RESET} Merge mining     : %s (Tari)\n" "$short_tari"
else
  printf "  ${FG_YELLOW}○${RESET} Merge mining     : désactivé\n"
fi
printf "  ${FG_GREEN}✔${RESET} Adresse Monero   : %s\n" "$short_addr"
printf "  ${FG_GREEN}✔${RESET} Type d’adresse   : %s\n" "$type"
printf "  ${FG_GREEN}✔${RESET} Mode XMRig       : %s\n" "$mode_label"
if [[ "${SSH_PORT:-0}" -gt 0 ]]; then
  ssh_msg="autorisé (port $SSH_PORT)"
else
  ssh_msg="bloqué"
fi
printf "  ${FG_GREEN}✔${RESET} Accès SSH        : %s\n" "$ssh_msg"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Dépendances ───────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🔧  Pré-requis système${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# Installation automatique de la locale UTF-8
if ! locale -a | grep -qi 'en_US.utf8'; then
  (
    apt-get install -y -qq locales &>/dev/null
    locale-gen en_US.UTF-8 &>/dev/null
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 &>/dev/null
  ) &
  spinner $! "${FG_WHITE}Installation de la locale en_US.UTF-8${RESET}"
  printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} Locale en_US.UTF-8 installée et activée\n"
else
  printf "  ${FG_GREEN}✔${RESET} Locale en_US.UTF-8 déjà présente\n"
fi
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Vérifier / créer l'utilisateur « worker »
if id -u worker &>/dev/null; then
  printf "  ${FG_GREEN}✔${RESET} utilisateur « worker » déjà présent\n"
else
  (
    adduser --disabled-password --gecos '' worker &>/dev/null
  ) &
  spinner $! "Création de l'utilisateur « worker »"
  printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} utilisateur « worker » créé\n"
fi

# Vérification synchronisation Horloge (NTP) - CRITIQUE POUR LA BLOCKCHAIN
if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
  printf "  ${FG_GREEN}✔${RESET} Horloge système synchronisée\n"
else
  (
    # Tentative de forçage de la synchro
    timedatectl set-ntp true 2>/dev/null
    systemctl restart systemd-timesyncd 2>/dev/null

    # Attente active (max 10s) pour que la synchro se fasse
    for i in {1..20}; do
      if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
        break
      fi
      sleep 0.5
    done
  ) &
  spinner $! "Synchronisation de l'horloge système (NTP)"

  # Vérification du résultat après le spinner
  if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
    printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} Horloge système synchronisée\n"
  else
    printf "\033[A\r\033[K  ${FG_YELLOW}⚠${RESET} Horloge non synchronisée (vérifiez la connexion ou le service NTP)\n"
  fi
fi

# Paquets APT de base
deps=(curl jq ufw gnupg tar unzip netcat-openbsd iproute2 ca-certificates fail2ban tor wget qrencode)

# Une seule mise à jour de l'index APT
(
  DEBIAN_FRONTEND=noninteractive \
    apt-get update -qq -o=Dpkg::Use-Pty=0 -o=APT::Color=0 &>/dev/null
) &
spinner $! "Mise à jour de l'index APT"
printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} Mise à jour de l'index APT\n"

# Parcours ordonné des paquets avec MISE À JOUR AUTOMATIQUE
APT_OPTS=(-y -qq --no-install-recommends
  -o=Dpkg::Use-Pty=0 -o=Dpkg::Progress-Fancy=0 -o=APT::Color=0)

for pkg in "${deps[@]}"; do
  # Vérifier l'état avant (Correction: ajout de || true pour ne jamais planter)
  INSTALLED=$(dpkg -s "$pkg" 2>/dev/null | grep "Status: install ok installed" || true)
  OLD_VER=$(dpkg -s "$pkg" 2>/dev/null | grep -E '^Version:' | awk '{print $2}' || true)

  # On tente d'installer/mettre à jour (Logique auto-réparatrice)
  (
    NEEDRESTART_MODE=a \
      DEBIAN_FRONTEND=noninteractive \
      apt-get install "${APT_OPTS[@]}" "$pkg" &>/dev/null ||
      (apt-get update -qq &>/dev/null && apt-get install "${APT_OPTS[@]}" "$pkg" &>/dev/null)
  ) &
  spinner $! "Vérification/Mise à jour de $pkg"

  # Vérifier nouvelle version (Correction: ajout de || true)
  NEW_VER=$(dpkg -s "$pkg" 2>/dev/null | grep -E '^Version:' | awk '{print $2}' || true)

  if [[ -z "$INSTALLED" ]]; then
    # Nouvelle installation
    if [[ -n "$NEW_VER" ]]; then
      printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} %s installé (v%s)\n" "$pkg" "$NEW_VER"
    else
      printf "\033[A\r\033[K  ${FG_RED}✖${RESET} Erreur : %s n'a pas pu être installé\n" "$pkg"
    fi
  elif [[ "$OLD_VER" != "$NEW_VER" ]]; then
    # Mise à jour effectuée
    printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} %s mis à jour (v%s → v%s)\n" "$pkg" "$OLD_VER" "$NEW_VER"
  else
    # Déjà à jour
    printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} %s est à jour (v%s)\n" "$pkg" "$NEW_VER"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Installation grpcurl (Indispensable pour la surveillance Tari)
# ─────────────────────────────────────────────────────────────────────
fetch_latest_version "grpcurl" "fullstorydev/grpcurl" GRPCURL_VERSION

if command -v grpcurl &>/dev/null; then
  INSTALLED_GRPCURL=$(grpcurl -version 2>&1 | awk '{print $NF}' | tr -d '\n\r')

  # Si quota OK (version trouvée) et version différente -> Tentative de mise à jour
  if [[ -n "$GRPCURL_VERSION" && "$GRPCURL_VERSION" != "v0.0.0" && "$INSTALLED_GRPCURL" != "$GRPCURL_VERSION" ]]; then
    printf "  ${FG_YELLOW}⇧${RESET} grpcurl    : ${INSTALLED_GRPCURL} → ${GRPCURL_VERSION}\n"

    grpcurl_ver="${GRPCURL_VERSION#v}"
    grpcurl_url="https://github.com/fullstorydev/grpcurl/releases/download/${GRPCURL_VERSION}/grpcurl_${grpcurl_ver}_linux_x86_64.tar.gz"

    if wget --timeout=10 -q "$grpcurl_url" -O /tmp/grpcurl.tar.gz 2>/dev/null && [[ -s /tmp/grpcurl.tar.gz ]]; then
      (
        tar -xzf /tmp/grpcurl.tar.gz -C /usr/local/bin grpcurl 2>/dev/null
        chmod +x /usr/local/bin/grpcurl
        rm -f /tmp/grpcurl.tar.gz
      ) &
      spinner $! "Mise à jour grpcurl"
      printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} grpcurl mis à jour vers ${GRPCURL_VERSION}\n"
    else
      printf "\033[A\r\033[K  ${FG_RED}✖${RESET} Téléchargement grpcurl échoué (quota ou réseau)\n"
      rm -f /tmp/grpcurl.tar.gz
    fi
  else
    # Quota atteint ou déjà à jour : on garde la version actuelle sans bloquer
    printf "  ${FG_GREEN}✔${RESET} grpcurl ${INSTALLED_GRPCURL} déjà prêt\n"
  fi
else
  # Cas où grpcurl n'est pas installé du tout
  if [[ -n "$GRPCURL_VERSION" && "$GRPCURL_VERSION" != "v0.0.0" ]]; then
    grpcurl_ver="${GRPCURL_VERSION#v}"
    grpcurl_url="https://github.com/fullstorydev/grpcurl/releases/download/${GRPCURL_VERSION}/grpcurl_${grpcurl_ver}_linux_x86_64.tar.gz"

    if wget --timeout=10 -q "$grpcurl_url" -O /tmp/grpcurl.tar.gz 2>/dev/null && [[ -s /tmp/grpcurl.tar.gz ]]; then
      (
        tar -xzf /tmp/grpcurl.tar.gz -C /usr/local/bin grpcurl 2>/dev/null
        chmod +x /usr/local/bin/grpcurl
        rm -f /tmp/grpcurl.tar.gz
      ) &
      spinner $! "Installation grpcurl ${GRPCURL_VERSION}"
      printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} grpcurl ${GRPCURL_VERSION} installé\n"
    else
      printf "\033[A\r\033[K  ${FG_RED}✖${RESET} Échec de l'installation grpcurl\n"
      rm -f /tmp/grpcurl.tar.gz
    fi
  else
    # grpcurl absent ET quota GitHub atteint : bloquant SEULEMENT si Tari est utilisé
    if [[ -n "${TARI_ADDRESS:-}" ]]; then
      printf "  ${FG_RED}✖  ERREUR : grpcurl est absent (indispensable pour Tari) et le quota GitHub est atteint.${RESET}\n"
      exit 1
    else
      printf "  ${FG_YELLOW}⚠${RESET} grpcurl absent (quota GitHub), mais Tari est désactivé. On continue...\n"
    fi
  fi
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Optimisation mémoire & HugePages ──────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🧠  Optimisation mémoire & HugePages${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# 1. Nettoyage préalable (Action -> Spinner)
(
  find /etc/sysctl.d/ -type f -iname '*hugepages*.conf' -exec rm -f {} \;
  sed -i '/hugetlbfs/d' /etc/fstab

  # Nettoyage GRUB spécifique HugePages
  sed -i 's/ transparent_hugepage=never//g' /etc/default/grub
  sed -i 's/transparent_hugepage=never //g' /etc/default/grub
  sed -i 's/[[:space:]]\+$//' /etc/default/grub
) &
pid=$!
spinner "$pid" "Nettoyage des anciennes configurations HugePages"

# 2. Détection matérielle (Info instantanée)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_CPUS=$(nproc)
RECOMMENDED_HUGEPAGES=$(((TOTAL_CPUS * 256 * 1024) / 2048))
RECOMMENDED_HUGEPAGES=$((RECOMMENDED_HUGEPAGES / 10 * 10))

echo -e "  ${FG_GREEN}✔${RESET} RAM détectée      : $((TOTAL_RAM_KB / 1024)) MiB"
echo -e "  ${FG_GREEN}✔${RESET} Threads CPU       : ${TOTAL_CPUS}"
echo -e "  ${FG_GREEN}✔${RESET} HugePages Cible   : ${RECOMMENDED_HUGEPAGES} pages"

# 3. Configuration Sysctl HugePages
CURRENT_HUGEPAGES=$(sysctl -n vm.nr_hugepages 2>/dev/null || echo 0)
if [ "$CURRENT_HUGEPAGES" -ne "$RECOMMENDED_HUGEPAGES" ]; then
  echo "vm.nr_hugepages=$RECOMMENDED_HUGEPAGES" >/etc/sysctl.d/90-hugepages.conf
  sysctl -w vm.nr_hugepages=$RECOMMENDED_HUGEPAGES >/dev/null
fi

# 4. Service THP (Action -> Spinner)
(
  echo never >/sys/kernel/mm/transparent_hugepage/enabled
  echo never >/sys/kernel/mm/transparent_hugepage/defrag

  THP_UNIT_FILE="/etc/systemd/system/disable-thp.service"
  if [ ! -f "$THP_UNIT_FILE" ]; then
    cat <<EOF >"$THP_UNIT_FILE"
[Unit]
Description=Disable Transparent Huge Pages (THP)
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl enable --now disable-thp.service
  fi
) &
pid=$!
spinner "$pid" "Activation Service THP (systemd)"

# 5. Configuration GRUB HugePages (Action -> Spinner)
UPDATE_GRUB_HP=false
if ! grep -q 'transparent_hugepage=never' "$GRUB_FILE"; then
  sed -i 's/^GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="transparent_hugepage=never /' "$GRUB_FILE"
  sed -i 's/GRUB_CMDLINE_LINUX="  /GRUB_CMDLINE_LINUX=" /g' "$GRUB_FILE"
  UPDATE_GRUB_HP=true
fi

if $UPDATE_GRUB_HP; then
  (update-grub >/dev/null 2>&1) &
  pid=$!
  spinner "$pid" "Mise à jour GRUB (HugePages)"
else
  echo -e "  ${FG_GREEN}✔${RESET} Mise à jour GRUB  : paramètre déjà présent"
fi

# 6. Montage Hugetlbfs & 1GB Pages (Action -> Spinner)
(
  mkdir -p /dev/hugepages
  grep -q 'hugetlbfs /dev/hugepages' /etc/fstab || echo "hugetlbfs /dev/hugepages hugetlbfs mode=1770,gid=0 0 0" >>/etc/fstab
  mountpoint -q /dev/hugepages || mount /dev/hugepages

  if grep -q pdpe1gb /proc/cpuinfo; then
    mkdir -p /mnt/hugepages_1gb
    grep -q '/mnt/hugepages_1gb' /etc/fstab || echo "nodev /mnt/hugepages_1gb hugetlbfs pagesize=1G 0 0" >>/etc/fstab
    mountpoint -q /mnt/hugepages_1gb || mount /mnt/hugepages_1gb
  fi
) &
pid=$!
spinner "$pid" "Montage hugetlbfs & 1GB"

# 7. Résultats finaux (Texte propre sans emojis internes)
ALLOCATED=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
if [ "$ALLOCATED" -ge "$RECOMMENDED_HUGEPAGES" ]; then
  echo -e "  ${FG_GREEN}✔${RESET} Pages Allouées    : ${ALLOCATED} (OK)"
else
  echo -e "  ${FG_YELLOW}⚠${RESET} Pages Allouées    : ${ALLOCATED} (en cours d'allocation)"
fi

if grep -q pdpe1gb /proc/cpuinfo; then
  echo -e "  ${FG_GREEN}✔${RESET} Pages 1GiB        : actif"
else
  echo -e "  ${FG_YELLOW}✖${RESET} Pages 1GiB        : non supporté"
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Gestion des journaux systemd ──────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🧹  Configuration de la rétention des logs systemd${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

JOURNAL_CONF="/etc/systemd/journald.conf"

# Sauvegarde du fichier original
cp "$JOURNAL_CONF" "${JOURNAL_CONF}.bak.$(date +%F-%H%M)" 2>/dev/null

# Appliquer MaxRetentionSec=24h en modifiant ou activant la ligne
(
  sed -i 's|^#\?MaxRetentionSec=.*|MaxRetentionSec=24h|' "$JOURNAL_CONF"
  systemctl restart systemd-journald
  journalctl --vacuum-time=24h &>/dev/null
) &
spinner $! "Application de la rétention journald"

printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} Rétention des logs fixée à 24h et purge effectuée\n"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Désactivation IPv6 (Soft & Hard) ──────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🚫  Désactivation IPv6 (Network Hardening)${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# 1. Nettoyage préalable (Action -> Spinner)
(
  find /etc/sysctl.d/ -type f -iname '*ipv6*.conf' -exec rm -f {} \;
  find /etc/sysctl.d/ -type f -iname '*mining*.conf' -exec rm -f {} \;

  # Nettoyage GRUB (Action silencieuse)
  sed -i 's/ ipv6.disable=1//g' /etc/default/grub
  sed -i 's/ipv6.disable=1 //g' /etc/default/grub
  sed -i 's/[[:space:]]\+$//' /etc/default/grub
) &
pid=$!
spinner "$pid" "Nettoyage des anciennes configurations IPv6"

# 2. État initial
IPV6_ALIVE=$(grep -q "inet6" <(ip addr) && echo "1" || echo "0")
if [ "$IPV6_ALIVE" -eq "1" ]; then
  echo -e "  ${FG_YELLOW}⚠${RESET} État initial      : actif (désactivation requise)"
else
  echo -e "  ${FG_GREEN}✔${RESET} État initial      : inactif"
fi

# 3. Configuration Sysctl (Action -> Spinner)
cat <<EOF >/etc/sysctl.d/99-mining-ipv6.conf
# Désactivation complète IPv6 pour mining (Latence & Tor)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

(
  sysctl --system >/dev/null 2>&1
) &
pid=$!
spinner "$pid" "Application immédiate (sysctl)"

# 4. Configuration GRUB (Action -> Spinner)
UPDATE_GRUB=false

grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" || echo 'GRUB_CMDLINE_LINUX=""' >>"$GRUB_FILE"

# Injection (non destructive)
if ! grep -q 'ipv6.disable=1' "$GRUB_FILE"; then
  sed -i 's/^GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' "$GRUB_FILE"
  sed -i 's/GRUB_CMDLINE_LINUX="  /GRUB_CMDLINE_LINUX=" /g' "$GRUB_FILE"
  UPDATE_GRUB=true
fi

if $UPDATE_GRUB; then
  (update-grub >/dev/null 2>&1) &
  pid=$!
  spinner "$pid" "Mise à jour GRUB (ipv6.disable=1)"
else
  echo -e "  ${FG_GREEN}✔${RESET} Mise à jour GRUB  : paramètre déjà présent"
fi

# 5. Résultats finaux (Texte simple)
if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" -eq "1" ]; then
  echo -e "  ${FG_GREEN}✔${RESET} Config Sysctl     : désactivé"
else
  echo -e "  ${FG_RED}✖${RESET} Config Sysctl     : échec"
fi

if ip addr | grep -q "inet6"; then
  echo -e "  ${FG_YELLOW}⚠${RESET} Interfaces Réseau : IPv6 visible (disparaîtra au reboot)"
else
  echo -e "  ${FG_GREEN}✔${RESET} Interfaces Réseau : aucune adresse IPv6 détectée"
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Pare-feu (UFW) — vérification / synchronisation ───────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🛡️   Vérification de la configuration UFW${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# Règles attendues — pas de préfixe "ufw", juste l'action et le port
declare -a WANT_RULES
if [[ "${SSH_PORT:-0}" -gt 0 ]]; then
  WANT_RULES+=("allow ${SSH_PORT}/tcp")
fi

WANT_RULES+=("deny 18080/tcp")
WANT_RULES+=("deny 18081/tcp")
WANT_RULES+=("deny 18083/tcp")
WANT_RULES+=("allow 18090/tcp") # Monero P2P (custom port)

# Ports Tari (si merge mining activé)
if [[ -n "$TARI_ADDRESS" ]]; then
  WANT_RULES+=("deny ${TARI_GRPC_PORT}/tcp")
  WANT_RULES+=("allow ${TARI_P2P_PORT}/tcp")
fi

if [[ -n "$STRATUM_PORT" ]]; then
  WANT_RULES+=("deny ${STRATUM_PORT}/tcp")
fi

case "$MINING_MODE" in
  pool-nano)
    WANT_RULES+=("allow 37890/tcp")
    WANT_RULES+=("deny 37888/tcp")
    WANT_RULES+=("deny 37889/tcp")
    ;;
  pool-mini)
    WANT_RULES+=("deny 37890/tcp")
    WANT_RULES+=("allow 37888/tcp")
    WANT_RULES+=("deny 37889/tcp")
    ;;
  pool-full)
    WANT_RULES+=("deny 37890/tcp")
    WANT_RULES+=("deny 37888/tcp")
    WANT_RULES+=("allow 37889/tcp")
    ;;
  *)
    WANT_RULES+=("deny 37890/tcp")
    WANT_RULES+=("deny 37888/tcp")
    WANT_RULES+=("deny 37889/tcp")
    ;;
esac

# Règles réellement actives dans le système (UFW)
CURRENT_RULES=$(ufw show added 2>/dev/null |
  grep -E '^ufw (allow|deny)' |
  grep -v ' (v6)' |
  awk '{print $2, $3}' |
  sort -u)

EXPECTED_RULES=$(printf "%s\n" "${WANT_RULES[@]}" | sort -u)

# Comparaison
if [[ "$CURRENT_RULES" != "$EXPECTED_RULES" ]]; then
  printf "  ${FG_RED}✖${RESET} UFW ≠ modèle — reconfiguration nécessaire\n"

  (
    ufw --force reset >/dev/null
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    for rule in "${WANT_RULES[@]}"; do
      action=$(awk '{print $1}' <<<"$rule")
      port_proto=$(awk '{print $2}' <<<"$rule")
      port="${port_proto%%/*}"
      proto="${port_proto##*/}"
      ufw "$action" proto "$proto" to any port "$port" >/dev/null
    done

    ufw --force enable >/dev/null
    systemctl enable ufw >/dev/null 2>&1
  ) &
  spinner $! "Réinitialisation UFW complète"

  printf "  ${FG_GREEN}✔${RESET} UFW synchronisé avec le modèle\n"
else
  printf "  ${FG_GREEN}✔${RESET} UFW déjà conforme\n"
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Fail2Ban ──────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🚔  Sécurisation brute-force (Fail2Ban)${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

mkdir -p /etc/fail2ban
cat <<EOF >/etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
banaction = iptables-multiport

[sshd]
enabled = true
EOF

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban &
spinner $! "Configuration & démarrage de Fail2Ban"
printf "  ${FG_GREEN}✔${RESET} Protection brute-force activée (SSH)\n"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Configuration TOR pour anonymisation des peers ────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🧅  Configuration Tor (anonymisation des peers)${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

if systemctl is-active --quiet tor; then
  printf "  ${FG_GREEN}✔${RESET} Service Tor déjà actif\n"
else
  (
    systemctl enable tor >/dev/null 2>&1
    systemctl start tor >/dev/null 2>&1
    sleep 2
  ) &
  spinner $! "Activation du service Tor"

  if systemctl is-active --quiet tor; then
    printf "  ${FG_GREEN}✔${RESET} Service Tor démarré avec succès\n"
  else
    printf "  ${FG_RED}✖${RESET} Échec du démarrage de Tor\n"
    exit 1
  fi
fi

TOR_PROXY="127.0.0.1:9050"

if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/9050" 2>/dev/null; then
  printf "  ${FG_GREEN}✔${RESET} Proxy SOCKS5 Tor opérationnel ($TOR_PROXY)\n"
else
  printf "  ${FG_RED}✖${RESET} Proxy SOCKS5 Tor inaccessible\n"
  exit 1
fi

printf "  ${FG_GREEN}✔${RESET} TOR configuré pour la découverte de peers\n"

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Monero ────────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🏗️   Déploiement du nœud Monero${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

INSTALLED_MONERO=""

if [[ "$MINING_MODE" == "moneroocean" ]]; then
  printf "\n${FG_YELLOW}${BOLD}  ⏭ Le nœud Monero n'est pas utile en mode %s.${RESET}\n" "$mining_label"
  systemctl disable monerod.service 2>/dev/null || true
  systemctl stop monerod.service 2>/dev/null || true
else

  RESTART_MONERO=0
  RESTART_MONEROD=0

  fetch_latest_version "Monero" "monero-project/monero" MONERO_VERSION

  INSTALLED_MONERO=$(find "$WORKER_HOME" -maxdepth 1 -type d -name "monero-*" |
    sed -E 's/.*monero-//' | sort -Vr | head -n1 || true)

  show_component "Monero" "$INSTALLED_MONERO" "$MONERO_VERSION"

  if [[ -z "$INSTALLED_MONERO" && (-z "$MONERO_VERSION" || "$MONERO_VERSION" == "v0.0.0") ]]; then
    printf "  ${FG_RED}✖${RESET} Aucun binaire Monero installé, et impossible de récupérer une version distante.\n"
    printf "     ${FG_RED}Arrêt du script.${RESET}\n"
    exit 1
  fi

  if [[ "$MONERO_VERSION" == "v0.0.0" || -z "$MONERO_VERSION" ]]; then
    printf "  ${FG_YELLOW}⚠${RESET} Impossible de récupérer la version distante (quota GitHub ou Internet)\n"
    MONERO_DIR="$WORKER_HOME/monero-$INSTALLED_MONERO"
  else
    if [[ "$INSTALLED_MONERO" != "$MONERO_VERSION" ]]; then
      download_and_extract \
        "https://downloads.getmonero.org/cli/monero-linux-x64-${MONERO_VERSION}.tar.bz2" \
        "$WORKER_HOME" "$MONERO_VERSION"
      rm -rf "$WORKER_HOME/monero-${INSTALLED_MONERO}" 2>/dev/null || true
      mv "$WORKER_HOME"/monero*-"$MONERO_VERSION" "$WORKER_HOME/monero-$MONERO_VERSION"
      INSTALLED_MONERO="$MONERO_VERSION"
      chown -R worker:worker "$WORKER_HOME/monero-$MONERO_VERSION"
      RESTART_MONERO=1
      MONERO_DIR="$WORKER_HOME/monero-$MONERO_VERSION"
    else
      MONERO_DIR="$WORKER_HOME/monero-$INSTALLED_MONERO"
    fi
  fi

  UNIT_MONEROD=$(
    cat <<EOF
[Unit]
Description=Monero Daemon
After=network-online.target
Wants=network-online.target

[Service]
User=worker
WorkingDirectory=$MONERO_DIR
ExecStartPre=/bin/bash -c '[ -d "$WORKER_HOME/.bitmonero" ] || mkdir -p "$WORKER_HOME/.bitmonero"'
ExecStart=$MONERO_DIR/monerod \
  --non-interactive \
  --tx-proxy=tor,127.0.0.1:9050 \
  --zmq-pub=tcp://127.0.0.1:18083 \
  --p2p-bind-port=18090 \
  --in-peers=12 \
  --add-priority-node=p2pmd.xmrvsbeast.com:18080 \
  --add-priority-node=nodes.hashvault.pro:18080 \
  --enforce-dns-checkpointing \
  --enable-dns-blocklist
Restart=always
RestartSec=10
ProtectSystem=full
NoNewPrivileges=true
LimitNOFILE=16384

[Install]
WantedBy=multi-user.target
EOF
  )

  UNIT_HASH_FILE="/etc/.last-monerod-unit"
  NEW_HASH=$(echo "$UNIT_MONEROD" | sha256sum | awk '{print $1}')
  OLD_HASH=$(cat "$UNIT_HASH_FILE" 2>/dev/null || echo "")

  if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
    echo "$NEW_HASH" >"$UNIT_HASH_FILE"
    RESTART_MONEROD=1
    printf "  ${FG_YELLOW}↻${RESET} Changement de configuration monerod – redémarrage\n"
  fi

  ensure_unit monerod.service "$UNIT_MONEROD"

  if ((RESTART_MONEROD)); then
    systemctl daemon-reload
    systemctl restart monerod
    (sleep 15) &
    spinner $! "Application de la config Monero"
  fi

  if ((RESTART_MONERO)); then
    systemctl daemon-reexec
  fi

  ensure_running_enabled monerod.service

  wait_service_port monerod.service 18081 120

  # Vérification API 18081
  if ! curl -sSf http://127.0.0.1:18081/get_info >/dev/null 2>&1; then
    if ! wait_rpc_ready; then
      echo -e "  ${FG_RED}✖${RESET} monerod lancé mais l’API 18081 ne répond pas (échec)"
      exit 1
    fi
  else
    printf "  ${FG_GREEN}✔${RESET} Port 18081 (Monero RPC) déjà ouvert\n"
  fi

  # Attente synchronisation Monero
  wait_monero_ready() {
    local delay=1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local idx=0

    local last_height=0
    local last_change_ts=$(date +%s)
    local stall_timeout=1200
    local restart_count=0

    while true; do
      # 1. Interroger l'API Monero
      local resp=$(curl -s -m 5 -H 'Content-Type: application/json' \
        http://127.0.0.1:18081/get_info 2>/dev/null)

      # 2. Si l'API ne répond pas encore (démarrage)
      if [[ -z "$resp" ]]; then
        printf "\r\033[K  ${FG_YELLOW}%s${RESET} Monero : Initialisation de l'API...   " "${spinstr:$idx:1}"
        idx=$(((idx + 1) % ${#spinstr}))
        sleep "$delay"
        continue
      fi

      # 3. Extraction des données
      local is_synced=$(echo "$resp" | jq -r '.synchronized // false')
      local height=$(echo "$resp" | jq -r '.height // 0')
      local target=$(echo "$resp" | jq -r '.target_height // 0')

      local in_peers=$(echo "$resp" | jq -r '.incoming_connections_count // 0')
      local out_peers=$(echo "$resp" | jq -r '.outgoing_connections_count // 0')
      local peers=$((in_peers + out_peers))

      # Correction visuelle des données
      ((target < height)) && target=$height
      ((target == 0)) && target=$height

      # 4. Calcul du retard (Lag)
      local lag=$((target - height))
      ((lag < 0)) && lag=0

      # 5. Définition de l'état (Affichage)
      local state="Unknown"
      if [[ "$is_synced" == "true" ]]; then
        state="Synchronized"
      elif ((peers == 0)); then
        state="Waiting for peers"
      else
        local pct="0.0"
        if ((target > 0)); then
          pct=$(awk -v h="$height" -v t="$target" 'BEGIN{printf "%.1f", (h/t)*100}')
        fi
        state="Syncing ($pct%)"
      fi

      # 6. Affichage Compact (Style Tari avec Lag)
      idx=$(((idx + 1) % ${#spinstr}))
      printf "\r\033[K  ${FG_YELLOW}%s${RESET} Monero : %s | Height: %s/%s (Lag: %s) | %s peers   " \
        "${spinstr:$idx:1}" "${state:0:15}" "$height" "$target" "$lag" "$peers"

      # 7. CONDITION DE SORTIE (STRICTE MAIS INTELLIGENTE)
      # Sécurité : On refuse de sortir si la hauteur est < 3500000 (anti-bug démarrage)
      # ET ENSUITE : Soit l'API dit True, Soit on a assez de peers (2 min) et peu de lag.
      if ((height > 3500000)) && ([[ "$is_synced" == "true" ]] || ([[ "$state" != "Waiting for peers" ]] && ((lag <= 2)) && ((peers >= 2)))); then
        printf "\r\033[K  ${FG_GREEN}✔${RESET} Monero synchronisé (Hauteur: %s)\n" "$height"
        return 0
      fi

      sleep "$delay"
    done
  }

  # Appel de la fonction et gestion du résultat
  if wait_monero_ready; then
    printf "  ${FG_GREEN}✔${RESET} Le nœud Monero est opérationnel\n"
  else
    # L'affichage détaillé a déjà été fait dans la fonction, on sort juste proprement.
    exit 1
  fi

fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Tari ──────────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}💎  Déploiement du nœud Tari (merge mining)${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# Définition du dossier persistant
TARI_DATA_DIR="$WORKER_HOME/.tari"

INSTALLED_TARI=""

if [[ -z "$TARI_ADDRESS" || "$MINING_MODE" == "moneroocean" || "$MINING_MODE" == "solo" ]]; then

  if [[ "$MINING_MODE" == "moneroocean" ]]; then
    printf "\n${FG_YELLOW}${BOLD}  ⏭ Tari est désactivé en mode MoneroOcean (nécessite P2Pool).${RESET}\n"
  elif [[ "$MINING_MODE" == "solo" ]]; then
    printf "\n${FG_YELLOW}${BOLD}  ⏭ Tari est désactivé en mode SOLO (nécessite P2Pool pour le merge mining).${RESET}\n"
  else
    printf "\n${FG_YELLOW}${BOLD}  ⏭ Merge mining Tari désactivé (aucune adresse configurée).${RESET}\n"
  fi

  systemctl disable minotari_node.service 2>/dev/null || true
  systemctl stop minotari_node.service 2>/dev/null || true
else

  RESTART_TARI=0
  RESTART_MINOTARI=0

  fetch_latest_version "Tari" "tari-project/tari" TARI_VERSION

  INSTALLED_TARI=$(find "$WORKER_HOME" -maxdepth 1 -type d -name "tari-*" |
    sed -E 's/.*tari-//' | sort -Vr | head -n1 || true)

  show_component "Tari" "$INSTALLED_TARI" "$TARI_VERSION"

  # Création du dossier persistant s'il n'existe pas
  if [[ ! -d "$TARI_DATA_DIR" ]]; then
    mkdir -p "$TARI_DATA_DIR/mainnet/config"
    chown -R worker:worker "$TARI_DATA_DIR"
  fi

  if [[ -z "$INSTALLED_TARI" && (-z "$TARI_VERSION" || "$TARI_VERSION" == "v0.0.0") ]]; then
    printf "  ${FG_RED}✖${RESET} Aucun binaire Tari installé, et impossible de récupérer une version distante.\n"
    printf "     ${FG_YELLOW}⚠${RESET} Merge mining Tari désactivé.\n"
    TARI_ADDRESS=""
  else
    if [[ "$TARI_VERSION" == "v0.0.0" || -z "$TARI_VERSION" ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} Impossible de récupérer la version distante (quota GitHub ou Internet)\n"
      TARI_DIR="$WORKER_HOME/tari-$INSTALLED_TARI"
      TARI_BIN="$TARI_DIR/minotari_node"
    else
      if [[ "$INSTALLED_TARI" != "$TARI_VERSION" ]]; then
        download_and_extract \
          "https://github.com/tari-project/tari/releases/download/${TARI_VERSION}/tari_suite-mainnet-linux-x86_64.zip" \
          "$WORKER_HOME" "$TARI_VERSION"

        rm -rf "$WORKER_HOME/tari-${INSTALLED_TARI}" 2>/dev/null || true

        INSTALLED_TARI="$TARI_VERSION"
        chown -R worker:worker "$WORKER_HOME/tari-$TARI_VERSION"
        RESTART_TARI=1
      fi

      TARI_DIR="$WORKER_HOME/tari-$INSTALLED_TARI"
      TARI_BIN="$TARI_DIR/minotari_node"
    fi

    if [[ ! -f "$TARI_BIN" ]]; then
      printf "  ${FG_RED}✖${RESET} Binaire minotari_node introuvable dans $TARI_DIR\n"
      printf "     ${FG_YELLOW}⚠${RESET} Merge mining Tari désactivé.\n"
      TARI_ADDRESS=""
    else

      # ─────────────────────────────────────────────────────────────────────
      # Génération config.toml : VERSION STABLE (TCP + DNS AUTO)
      # ─────────────────────────────────────────────────────────────────────

      CONFIG_PATH="$TARI_DATA_DIR/mainnet/config/config.toml"

      # Préparer la configuration (template)
      TARI_CONFIG=$(
        cat <<'EOFCONFIG'
#######################################################################
# CONFIGURATION GENERATED BY DIYXMR SCRIPT
# MODE: HYBRID (DNS + STATIC PEERS) | TCP
#######################################################################

[common]
# MODIFICATION : base_path pointe vers le dossier persistant
base_path = "TARI_DATA_DIR_PLACEHOLDER/mainnet"

[p2p.seeds]
dns_seed_name_servers = [
    "1.1.1.1:853/cloudflare-dns.com",
    "8.8.8.8:853/dns.google"
]

[mainnet.p2p.seeds]
# dns_seeds = ["seeds.tari.com"]
peer_seeds = [
    "44c1ebed4ec5a6b3b325601e83ff3924f89e8943e15c5e82dfffe83754482b26::/ip4/54.36.113.0/tcp/18189",
    "c00684151e75650c63a5d3e4fd4221ce19c4fbffd1a921caaecf06f8a4a65f0f::/ip4/15.235.48.4/tcp/18189",
    "02577fd02c9f1fdef52c8de153c17c1af4f29ede2495ee008b334479456e1a5c::/ip4/54.36.117.26/tcp/18189",
    "8cc21698e3930da90fd8a9663fedf9d4d56d6ecd7dedec07f8b3590e82061503::/ip4/54.36.112.71/tcp/18189",
    "94a4b29148621479b1c1dffb1a2f5680dcf2c0cfb901152e245d6ec299821f61::/ip4/91.134.83.67/tcp/18189",
    "1850155828616111f97cc739bf5f3d433d7f07edd477cbf5a3eec0dfe7547c61::/ip4/54.36.117.109/tcp/18189",
    "5819ba1c9ddc57d8c82d60b6b3e8c1d8dd369c3336c47112b7483f4ca5fef315::/ip4/15.235.44.167/tcp/18189",
    "d6a0d9c3f75ae3cb4d06e314a5f5dceb9cc7ad34f7e8be4126ee25253b039726::/ip4/15.235.44.135/tcp/18189",
    "de568a57a62bff39322fff935523c5f670e379783293c88b1c525b776b568d41::/ip4/15.235.49.151/tcp/18189",
    "fabf65440daa00a8033a7d0c966d68815f17feb6a25bc60c75bc5d4a84c41123::/ip4/15.235.49.169/tcp/18189",
    "7c8e6530294e8bb7ff45b0f39e8bf8ea4e461b3df15a2df1ba3fa3a9bcc9ef71::/ip4/15.235.224.202/tcp/18189",
    "ecf3f88c40d0b299cf0d0ff30e7ce8dd5a021c0806b8487426f0de89e4766177::/ip4/141.95.111.150/tcp/18189",
    "54e491e0d88633170a98898f5d89ccc6b4f7ec22252afc23fe645d5bab453734::/ip4/198.244.203.249/tcp/18189",
    "54e491e0d88633170a98898f5d89ccc6b4f7ec22252afc23fe645d5bab453734::/ip6/2001:41d0:803:f900::/tcp/18189",
    "94a4b29148621479b1c1dffb1a2f5680dcf2c0cfb901152e245d6ec299821f61::/ip6/2001:41d0:40d:4300::/tcp/18189",
    "7c8e6530294e8bb7ff45b0f39e8bf8ea4e461b3df15a2df1ba3fa3a9bcc9ef71::/ip6/2402:1f00:8005:ca00::/tcp/18189",
    "c00684151e75650c63a5d3e4fd4221ce19c4fbffd1a921caaecf06f8a4a65f0f::/ip6/2607:5300:205:300::d28/tcp/18189",
    "d6a0d9c3f75ae3cb4d06e314a5f5dceb9cc7ad34f7e8be4126ee25253b039726::/ip6/2607:5300:205:300::afc/tcp/18189",
    "fabf65440daa00a8033a7d0c966d68815f17feb6a25bc60c75bc5d4a84c41123::/ip6/2607:5300:205:300::5f4/tcp/18189",
    "02577fd02c9f1fdef52c8de153c17c1af4f29ede2495ee008b334479456e1a5c::/ip6/2001:41d0:701:1000::5bf/tcp/18189",
    "1850155828616111f97cc739bf5f3d433d7f07edd477cbf5a3eec0dfe7547c61::/ip6/2001:41d0:701:1000::f36/tcp/18189",
    "5819ba1c9ddc57d8c82d60b6b3e8c1d8dd369c3336c47112b7483f4ca5fef315::/ip6/2607:5300:205:300::196b/tcp/18189",
    "de568a57a62bff39322fff935523c5f670e379783293c88b1c525b776b568d41::/ip6/2607:5300:205:300::2396/tcp/18189",
    "ecf3f88c40d0b299cf0d0ff30e7ce8dd5a021c0806b8487426f0de89e4766177::/ip6/2001:41d0:701:1000::3dd/tcp/18189",
    "44c1ebed4ec5a6b3b325601e83ff3924f89e8943e15c5e82dfffe83754482b26::/ip6/2001:41d0:701:1000::43ca/tcp/18189",
    "8cc21698e3930da90fd8a9663fedf9d4d56d6ecd7dedec07f8b3590e82061503::/ip6/2001:41d0:701:1000::3e6d/tcp/18189",
    "02577fd02c9f1fdef52c8de153c17c1af4f29ede2495ee008b334479456e1a5c::/onion3/bukg4svrs4r3hdtx4s2vle6ekipi4v7bshenfwjalymvax7akivyhkyd:18141",
    "1850155828616111f97cc739bf5f3d433d7f07edd477cbf5a3eec0dfe7547c61::/onion3/miubwm3dbl5uh4ci7jgvq5jeyhr6sora4fivjm5fkjflyt543cqx2kqd:18141",
    "44c1ebed4ec5a6b3b325601e83ff3924f89e8943e15c5e82dfffe83754482b26::/onion3/kimfu5ch2lwo4wm4y6xgi5kvuqnrobdgiyis2okcc27alf3qavuruxqd:18141",
    "54e491e0d88633170a98898f5d89ccc6b4f7ec22252afc23fe645d5bab453734::/onion3/b5zgqd6emm6p2zmj7gdniysbxvmtvltrwshsyfxjoq26xqfjoicge5id:18141",
    "5819ba1c9ddc57d8c82d60b6b3e8c1d8dd369c3336c47112b7483f4ca5fef315::/onion3/f4n5yh62a3aml5y4lrf7xhqjzgqen2r75ubze2aritezw73qk2uzirad:18141",
    "7c8e6530294e8bb7ff45b0f39e8bf8ea4e461b3df15a2df1ba3fa3a9bcc9ef71::/onion3/5husjyv2zskwjh2wzbuirbq4gk5uiyx4gnn277r3yoxv4oucn72tmeyd:18141",
    "8cc21698e3930da90fd8a9663fedf9d4d56d6ecd7dedec07f8b3590e82061503::/onion3/yur5nsnkbpfvs4f5h65y652igcqjfv35okchify44kr77evkyfpnleqd:18141",
    "94a4b29148621479b1c1dffb1a2f5680dcf2c0cfb901152e245d6ec299821f61::/onion3/x4cc7t4z5bhzz2qoj5qkfje6jnisz5gvzixeygvzwgi6sg3rhpo5rlqd:18141",
    "c00684151e75650c63a5d3e4fd4221ce19c4fbffd1a921caaecf06f8a4a65f0f::/onion3/xfa5ijw7747cmjwkbjx6fhobgy4rgx5uozc3dnp7lif7gw7c3dzg6kad:18141",
    "d6a0d9c3f75ae3cb4d06e314a5f5dceb9cc7ad34f7e8be4126ee25253b039726::/onion3/kuibpj4742riknkddi4vlrdgklipf6uf5f6b4vdwsklr4iigxrm367qd:18141",
    "de568a57a62bff39322fff935523c5f670e379783293c88b1c525b776b568d41::/onion3/xwsoa6q4ijugfar22uoggu22wt6ttmtg2egkyo4fs6ptfjtq3kbrulid:18141",
    "ecf3f88c40d0b299cf0d0ff30e7ce8dd5a021c0806b8487426f0de89e4766177::/onion3/3dcfberbstruf3g2g5slacw2ls3nj6qmad2fxumqop3m65llagnhj6yd:18141",
    "fabf65440daa00a8033a7d0c966d68815f17feb6a25bc60c75bc5d4a84c41123::/onion3/k7egeg7alhhgr5vbjgatdd6g2rlvy3l6pd3kxvget2q437jqh7q6cuid:18141",
]

[base_node]
network = "mainnet"
mining_enabled = true
grpc_enabled = true
grpc_address = "/ip4/127.0.0.1/tcp/GRPC_PORT_PLACEHOLDER"

grpc_server_allow_methods = [
    "get_version",
    "check_for_updates",
    "get_sync_info",
    "get_sync_progress",
    "get_tip_info",
    "identify",
    "get_network_status",
    "list_headers",
    "get_header_by_hash",
    "get_blocks",
    "get_block_timing",
    "get_constants",
    "get_block_size",
    "get_block_fees",
    "get_tokens_in_circulation",
    "get_network_difficulty",
    "get_new_block_template",
    "get_new_block",
    "get_new_block_with_coinbases",
    "get_new_block_template_with_coinbases",
    "get_new_block_blob",
    "submit_block",
    "submit_block_blob",
    "submit_transaction",
    "search_kernels",
    "search_utxos",
    "fetch_matching_utxos",
    "get_peers",
    "get_mempool_transactions",
    "transaction_state",
    "list_connected_peers",
    "get_mempool_stats",
    "get_active_validator_nodes",
    "get_validator_node_changes",
    "get_shard_key",
    "get_template_registrations",
    "get_side_chain_utxos",
    "search_payment_references",
    "search_payment_references_via_output_hash",
]

[base_node.p2p.transport]
type = "tcp"

[base_node.p2p.transport.tcp]
listener_address = "/ip4/0.0.0.0/tcp/18189"

[base_node.state_machine]
blockchain_sync_config.initial_max_sync_latency = 2000
blockchain_sync_config.rpc_deadline = 2000
EOFCONFIG
      )

      # Remplacer les placeholders
      TARI_CONFIG="${TARI_CONFIG//TARI_DATA_DIR_PLACEHOLDER/$TARI_DATA_DIR}"
      TARI_CONFIG="${TARI_CONFIG//GRPC_PORT_PLACEHOLDER/$TARI_GRPC_PORT}"

      # Hash de la config ATTENDUE
      NEW_CONFIG_HASH=$(echo "$TARI_CONFIG" | sha256sum | awk '{print $1}')

      # Hash du fichier EXISTANT (comparer les configs réelles)
      if [[ -f "$CONFIG_PATH" ]]; then
        EXISTING_CONFIG_HASH=$(cat "$CONFIG_PATH" | sha256sum | awk '{print $1}')
      else
        EXISTING_CONFIG_HASH=""
      fi

      # Régénération CONDITIONNELLE (comparer les configs réelles, pas les hashs sauvegardés)
      if [[ "$NEW_CONFIG_HASH" != "$EXISTING_CONFIG_HASH" ]]; then
        printf "  ${FG_YELLOW}⚙${RESET} Mise à jour de la configuration Minotari\n"

        # Arrêter SEULEMENT si config changée
        if systemctl is-active --quiet minotari_node.service; then
          (
            systemctl stop minotari_node.service 2>/dev/null
            sleep 2
          ) &
          spinner $! "Arrêt du service Minotari (config modifiée)"
        fi

        # Écrire dans le dossier persistant
        mkdir -p "$TARI_DATA_DIR/mainnet/config"

        # Écrire la nouvelle config
        echo "$TARI_CONFIG" >"$CONFIG_PATH"
        chown -R worker:worker "$TARI_DATA_DIR"

        RESTART_MINOTARI=1
        printf "  ${FG_GREEN}✔${RESET} Configuration minotari mise à jour (Port gRPC ${TARI_GRPC_PORT})\n"
      else
        printf "  ${FG_GREEN}✔${RESET} Configuration minotari : déjà conforme\n"
      fi

      # ─────────────────────────────────────────────────────────────────────
      # Création du service systemd
      # ─────────────────────────────────────────────────────────────────────

      UNIT_MINOTARI=$(
        cat <<EOF
[Unit]
Description=Minotari Node (Tari merge mining - MAINNET)
After=network-online.target tor.service
Requires=network-online.target
Wants=tor.service

[Service]
User=worker
WorkingDirectory=$TARI_DIR
ExecStart=${TARI_BIN} --non-interactive-mode --network mainnet --base-path=${TARI_DATA_DIR} --config=${CONFIG_PATH}
Restart=on-failure
RestartSec=15
TimeoutStartSec=600
StandardOutput=journal
StandardError=journal
ProtectSystem=full
NoNewPrivileges=true
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
      )

      # Utiliser ensure_unit (qui gère déjà le hash)
      ensure_unit minotari_node.service "$UNIT_MINOTARI"

      if ((RESTART_TARI || RESTART_MINOTARI)); then
        systemctl daemon-reload
        systemctl restart minotari_node.service
        (sleep 15) &
        spinner $! "Application de la config Tari"
      fi

      ensure_running_enabled minotari_node.service

      # Installer les fichiers proto Tari
      install_tari_proto() {
        local PROTO_DIR="/usr/local/share/tari/proto"

        # Si tous les fichiers existent déjà, ne pas retélécharger
        if [[ -f "$PROTO_DIR/base_node.proto" ]] && [[ -f "$PROTO_DIR/sidechain_types.proto" ]]; then
          return 0
        fi

        mkdir -p "$PROTO_DIR"
        local base_url="https://raw.githubusercontent.com/tari-project/tari/development/applications/minotari_app_grpc/proto"
        local files=(
          "base_node.proto" "types.proto" "transaction.proto" "network.proto"
          "sidechain_types.proto" "block.proto" "block_header.proto"
          "chain_metadata.proto" "common.proto" "compact_block.proto"
        )

        # Télécharger les fichiers sans backgrounder
        printf "  ⠋ Installation proto Tari"
        for file in "${files[@]}"; do
          if [[ ! -f "$PROTO_DIR/$file" ]]; then
            wget -q "$base_url/$file" -O "$PROTO_DIR/$file" 2>/dev/null || true
          fi
        done
        printf "\r\033[K  ${FG_GREEN}✔${RESET} Fichiers proto Tari installés\n"
      }
      install_tari_proto

      # ─────────────────────────────────────────────────────────────────────
      # 5. Attente synchronisation Tari (Version ROBUSTE & COMPATIBLE LOGS)
      # ─────────────────────────────────────────────────────────────────────
      wait_tari_ready() {
        local delay=1
        local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local idx=0
        local grpc_wait=0
        local max_grpc_wait=60

        local last_height=0
        local last_change_ts=$(date +%s)
        local restart_count=0
        local last_sync_state=""

        while true; do
          # 1. Vérifier le service
          if ! systemctl is-active --quiet minotari_node.service; then
            printf "\r\033[K  ${FG_RED}✖${RESET} Service minotari_node arrêté\n"
            return 1
          fi

          # 2. Attendre le port gRPC
          if ! timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${TARI_GRPC_PORT}" 2>/dev/null; then
            printf "\r  ${FG_YELLOW}%s${RESET} Tari : Attente gRPC (%d/%d)...   " \
              "${spinstr:$idx:1}" "$grpc_wait" "$max_grpc_wait"
            grpc_wait=$((grpc_wait + 1))
            if ((grpc_wait > max_grpc_wait)); then
              printf "\r\033[K  ${FG_RED}✖${RESET} Port gRPC ${TARI_GRPC_PORT} inaccessible\n"
              return 1
            fi
            sleep 2
            idx=$(((idx + 1) % ${#spinstr}))
            continue
          fi
          grpc_wait=0

          # 3. Interroger l'API gRPC
          local tip_info=$(grpcurl -plaintext -max-time 5 \
            -import-path /usr/local/share/tari/proto \
            -proto base_node.proto \
            127.0.0.1:${TARI_GRPC_PORT} \
            tari.rpc.BaseNode/GetTipInfo 2>/dev/null)

          local sync_progress=$(grpcurl -plaintext -max-time 5 \
            -import-path /usr/local/share/tari/proto \
            -proto base_node.proto \
            127.0.0.1:${TARI_GRPC_PORT} \
            tari.rpc.BaseNode/GetSyncProgress 2>/dev/null)

          # Si les appels échouent, continuer d'attendre
          if [[ -z "$tip_info" || -z "$sync_progress" ]]; then
            printf "\r  ${FG_YELLOW}%s${RESET} Tari : API gRPC initialisation...   " "${spinstr:$idx:1}"
            sleep "$delay"
            idx=$(((idx + 1) % ${#spinstr}))
            continue
          fi

          # --- Extraction des données ---
          local base_node_state=$(echo "$tip_info" | jq -r '.baseNodeState // "Unknown"' 2>/dev/null || echo "Unknown")

          # On surveille l'état global (State + Description pour être sûr de voir les changements)
          local sync_state=$(echo "$sync_progress" | jq -r '.state // ""' 2>/dev/null || echo "")
          local short_desc=$(echo "$sync_progress" | jq -r '.shortDesc // ""' 2>/dev/null || echo "")
          local current_full_state="${sync_state}|${short_desc}"

          # Hauteurs
          local current_height=$(echo "$tip_info" | jq -r '.metadata.bestBlockHeight // "0"' 2>/dev/null || echo "0")
          current_height=${current_height:-0}

          local local_height=$(echo "$sync_progress" | jq -r '.localHeight // "0"' 2>/dev/null || echo "0")
          local_height=${local_height:-0}

          local tip_height=$(echo "$sync_progress" | jq -r '.tipHeight // "0"' 2>/dev/null || echo "0")
          tip_height=${tip_height:-0}

          # Peers
          local peers_info=$(grpcurl -plaintext -max-time 3 \
            -import-path /usr/local/share/tari/proto \
            -proto base_node.proto \
            127.0.0.1:${TARI_GRPC_PORT} \
            tari.rpc.BaseNode/ListConnectedPeers 2>/dev/null)
          local peers=$(echo "$peers_info" | jq '.connectedPeers | length // 0' 2>/dev/null || echo 0)
          peers=${peers:-0}

          # 4. Calcul du retard (Lag)
          local target_height=$tip_height
          ((target_height < current_height)) && target_height=$current_height # Sécurité
          local remaining=$((target_height - current_height))

          # 5. Affichage dynamique
          idx=$(((idx + 1) % ${#spinstr}))

          local display_state="${sync_state:-$short_desc}"

          if ((local_height > 0 && tip_height > 0)); then
            printf "\r\033[K  ${FG_YELLOW}%s${RESET} Tari : %s | Height: %s/%s (Lag: %s) | %s peers   " \
              "${spinstr:$idx:1}" "${display_state:0:15}" "$current_height" "$target_height" "$remaining" "$peers"
          else
            printf "\r\033[K  ${FG_YELLOW}%s${RESET} Tari : %s | %s peers   " \
              "${spinstr:$idx:1}" "${display_state:0:15}" "$peers"
          fi

          # 6. Condition de sortie (STRICTE)
          local is_synced="false"
          if [[ "$base_node_state" == "Listening" ]] ||
            [[ "$base_node_state" == "ListeningCurrent" ]] ||
            [[ "$sync_state" == "DONE" ]]; then
            is_synced="true"
          fi

          if [[ "$is_synced" == "true" ]] && ((peers >= 1)) && ((remaining <= 3)) && ((current_height > 0)); then
            printf "\r\033[K  ${FG_GREEN}✔${RESET} Tari synchronisé (Hauteur: %s)\n" "$current_height"
            return 0
          fi

          sleep "$delay"
        done
      }

      # Lancer l'attente
      wait_tari_ready
      printf "  ${FG_GREEN}✔${RESET} Le nœud Tari est opérationnel\n"

    fi
  fi
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# P2Pool ────────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}🔗  Déploiement du pool décentralisé P2Pool${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

INSTALLED_P2POOL=""

# Si l'on n'est pas en mode pool, on coupe P2Pool
if [[ "$MINING_MODE" != "pool-nano" && "$MINING_MODE" != "pool-mini" && "$MINING_MODE" != "pool-full" ]]; then
  printf "\n${FG_YELLOW}${BOLD}  ⏭ Le pool P2Pool n'est pas utile en mode %s.${RESET}\n" "$mining_label"
  systemctl disable p2pool.service 2>/dev/null || true
  systemctl stop p2pool.service 2>/dev/null || true
else
  RESTART_P2POOL=0

  # Choix des ports & peers selon le mode
  if [[ "$MINING_MODE" == "pool-nano" ]]; then
    MODE_ARG="--nano"
    PEERS_LIST="nano.p2pool.observer:37890,seed.p2pool.io:37890,node.p2pool.io:37890"
  elif [[ "$MINING_MODE" == "pool-mini" ]]; then
    MODE_ARG="--mini"
    PEERS_LIST="mini.p2pool.observer:37888,seed.p2pool.io:37888,node.p2pool.io:37888"
  else
    MODE_ARG=""
    PEERS_LIST="seed.p2pool.io:37889,node.p2pool.io:37889,xmrvsbeast.com:37889"
  fi

  fetch_latest_version "P2Pool" "SChernykh/p2pool" P2POOL_VERSION

  INSTALLED_P2POOL=$(find "$WORKER_HOME" -maxdepth 1 -type d -name "p2pool-*" |
    sed -E 's/.*p2pool-//' | sort -Vr | head -n1 || true)

  show_component "P2Pool" "$INSTALLED_P2POOL" "$P2POOL_VERSION"

  if [[ -z "$INSTALLED_P2POOL" && (-z "$P2POOL_VERSION" || "$P2POOL_VERSION" == "v0.0.0") ]]; then
    printf "  ${FG_RED}✖${RESET} Aucun binaire P2Pool installé, et version distante indisponible.\n"
    printf "     ${FG_RED}P2Pool désactivé.${RESET}\n"
    MODE_ARG="" P2POOL_BIN="" P2POOL_DIR="" P2POOL_PORT="" STRATUM_PORT=""
  else
    if [[ "$P2POOL_VERSION" == "v0.0.0" || -z "$P2POOL_VERSION" ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} Impossible de récupérer la version distante (quota GitHub ou Internet)\n"
      P2POOL_DIR="$WORKER_HOME/p2pool-$INSTALLED_P2POOL"
      P2POOL_BIN="$P2POOL_DIR/p2pool"
    else
      if [[ "$INSTALLED_P2POOL" != "$P2POOL_VERSION" ]]; then
        download_and_extract \
          "https://github.com/SChernykh/p2pool/releases/download/${P2POOL_VERSION}/p2pool-${P2POOL_VERSION}-linux-x64.tar.gz" \
          "$WORKER_HOME" "$P2POOL_VERSION"
        rm -rf "$WORKER_HOME/p2pool-${INSTALLED_P2POOL}" 2>/dev/null || true
        mv "$WORKER_HOME/p2pool-${P2POOL_VERSION}-linux-x64" "$WORKER_HOME/p2pool-$P2POOL_VERSION"
        INSTALLED_P2POOL="$P2POOL_VERSION"
        chown -R worker:worker "$WORKER_HOME/p2pool-$P2POOL_VERSION"
        RESTART_P2POOL=1
        P2POOL_DIR="$WORKER_HOME/p2pool-$P2POOL_VERSION"
        P2POOL_BIN="$P2POOL_DIR/p2pool"
      else
        P2POOL_DIR="$WORKER_HOME/p2pool-$INSTALLED_P2POOL"
        P2POOL_BIN="$P2POOL_DIR/p2pool"
      fi
    fi

    # Dossier dédié pour les stats JSON
    P2POOL_STATS_DIR="$WORKER_HOME/p2pool-stats"
    mkdir -p "$P2POOL_STATS_DIR"
    chown -R worker:worker "$P2POOL_STATS_DIR"

    # On utilise le chemin complet vers ce dossier
    P2POOL_OPTIONS="--host 127.0.0.1 --wallet $MONERO_ADDRESS $MODE_ARG --local-api --data-api $P2POOL_STATS_DIR --stratum 127.0.0.1:$STRATUM_PORT --p2p 0.0.0.0:$P2POOL_PORT"

    # Ajout des pairs
    P2POOL_OPTIONS="$P2POOL_OPTIONS --addpeers \"$PEERS_LIST\""

    # Syntaxe pour Tari
    if [[ -n "$TARI_ADDRESS" && -f "$TARI_BIN" ]]; then
      P2POOL_OPTIONS="$P2POOL_OPTIONS --merge-mine tari://127.0.0.1:${TARI_GRPC_PORT} $TARI_ADDRESS"
      printf "  ${FG_GREEN}✔${RESET} Merge mining Tari activé pour P2Pool\n"
    fi

    # Dépendances sur minotari_node SEULEMENT si merge mining actif
    if [[ -n "$TARI_ADDRESS" && -f "$TARI_BIN" ]]; then
      # Avec merge mining Tari
      UNIT_P2POOL=$(
        cat <<EOF
[Unit]
Description=P2Pool ($MINING_MODE) - Merge Mining Tari
After=network-online.target monerod.service minotari_node.service
Requires=network-online.target monerod.service minotari_node.service

[Service]
User=worker
EnvironmentFile=$CONFIG_FILE
WorkingDirectory=$P2POOL_DIR
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c '$P2POOL_BIN $P2POOL_OPTIONS'
Restart=on-failure
RestartSec=10
TimeoutStartSec=360
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
      )
    else
      UNIT_P2POOL=$(
        cat <<EOF
[Unit]
Description=P2Pool ($MINING_MODE) - Monero Only
After=network-online.target monerod.service
Requires=network-online.target monerod.service

[Service]
User=worker
EnvironmentFile=$CONFIG_FILE
WorkingDirectory=$P2POOL_DIR
ExecStartPre=/bin/sleep 2
ExecStart=/bin/bash -c '$P2POOL_BIN $P2POOL_OPTIONS'
Restart=on-failure
RestartSec=5
TimeoutStartSec=360
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
      )
    fi

    # — redémarrage si l'unité change —
    UNIT_HASH_FILE="/etc/.last-p2pool-unit"
    NEW_HASH=$(echo "$UNIT_P2POOL" | sha256sum | awk '{print $1}')
    OLD_HASH=$(cat "$UNIT_HASH_FILE" 2>/dev/null || echo "")

    if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
      echo "$NEW_HASH" >"$UNIT_HASH_FILE"
      RESTART_P2POOL=1
      printf "  ${FG_YELLOW}↻${RESET} Changement de configuration P2Pool – redémarrage\n"
    fi

    ensure_unit p2pool.service "$UNIT_P2POOL"

    # (Re)lancement
    if ((RESTART_P2POOL)); then
      systemctl daemon-reload

      # On attend que monerod soit réellement utilisable
      (wait_monero_ready) &
      pid=$!

      if spinner "$pid" "Synchronisation Monero pour P2Pool…" >/dev/null; then
        printf "  ${FG_GREEN}✔${RESET} monerod pleinement prêt pour P2Pool\n"
      else
        printf "  ${FG_RED}✖${RESET} monerod bloqué (pas de progrès depuis 20 min) – démarrage forcé de P2Pool\n"
      fi

      # AJOUT : Attendre que Tari soit prêt si merge mining activé
      if [[ -n "$TARI_ADDRESS" && -f "$TARI_BIN" ]]; then
        printf "  ${FG_YELLOW}⧖${RESET} Attente du service Tari (gRPC port ${TARI_GRPC_PORT})...\n"

        TARI_READY=0
        while [[ $TARI_READY -lt 30 ]]; do
          if systemctl is-active --quiet minotari_node.service &&
            timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${TARI_GRPC_PORT}" 2>/dev/null; then
            printf "\033[A\r\033[K  ${FG_GREEN}✔${RESET} Service Tari opérationnel (gRPC port ${TARI_GRPC_PORT} ouvert)\n"
            break
          fi
          sleep 2
          TARI_READY=$((TARI_READY + 1))
        done

        if [[ $TARI_READY -ge 30 ]]; then
          printf "\033[A\r\033[K  ${FG_YELLOW}⚠${RESET} Tari gRPC non prêt après 60s – P2Pool démarré sans merge mining\n"
          printf "  💡 Le merge mining Tari sera actif dès que le nœud répondra\n"
        fi
      fi

      (
        systemctl restart p2pool
        systemctl enable --now p2pool >/dev/null 2>&1
      ) &
      spinner $! "Application de la configuration P2Pool..."

      # Vérifie que le stratum répond
      wait_service_port p2pool.service "$STRATUM_PORT" 180 0
      rc=$?

      if [[ $rc -eq 0 ]]; then
        printf "  ${FG_GREEN}✔${RESET} Port $STRATUM_PORT (Stratum P2Pool) détecté\n"
      else
        printf "  ${FG_RED}✖${RESET} Le port $STRATUM_PORT de P2Pool ne répond pas après 3 minutes\n"
        journalctl -u p2pool.service --no-pager -n 20
        exit 1
      fi
    else
      ensure_running_enabled p2pool.service
    fi
    if systemctl is-active --quiet p2pool; then
      printf "  ${FG_GREEN}✔${RESET} Le pool P2Pool est opérationnel\n"
    fi
  fi
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# XMRig ─────────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n"
printf "${FG_CYAN}${BOLD}⛏️   Déploiement du mineur XMRig (CPU)${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

RESTART_XMRIG=0

fetch_latest_version "XMRig" "xmrig/xmrig" XMRIG_VERSION

INSTALLED_XMRIG=$(find "$WORKER_HOME" -maxdepth 1 -type d -name "xmrig-*" |
  sed -E 's/.*xmrig-//' | sort -Vr | head -n1 || true)

show_component "XMRig" "$INSTALLED_XMRIG" "$XMRIG_VERSION"

if [[ -z "$INSTALLED_XMRIG" && (-z "$XMRIG_VERSION" || "$XMRIG_VERSION" == "v0.0.0") ]]; then
  printf "  ${FG_RED}✖${RESET} Aucun binaire XMRig installé, et version distante indisponible.\n"
  printf "     ${FG_RED}Arrêt du script.${RESET}\n"
  exit 1
fi

if [[ "$XMRIG_VERSION" == "v0.0.0" || -z "$XMRIG_VERSION" ]]; then
  printf "  ${FG_YELLOW}⚠${RESET} Impossible de récupérer la version distante (quota GitHub ou Internet)\n"
  XMRIG_DIR="$WORKER_HOME/xmrig-$INSTALLED_XMRIG"
else
  if [[ "$INSTALLED_XMRIG" != "$XMRIG_VERSION" ]]; then
    download_and_extract \
      "https://github.com/xmrig/xmrig/releases/download/${XMRIG_VERSION}/xmrig-${XMRIG_VERSION#v}-linux-static-x64.tar.gz" \
      "$WORKER_HOME" "$XMRIG_VERSION"
    rm -rf "$WORKER_HOME/xmrig-${INSTALLED_XMRIG}" 2>/dev/null || true
    mv "$WORKER_HOME/xmrig-${XMRIG_VERSION#v}" "$WORKER_HOME/xmrig-$XMRIG_VERSION"
    INSTALLED_XMRIG="$XMRIG_VERSION"
    chown -R root:worker "$WORKER_HOME/xmrig-$XMRIG_VERSION"
    RESTART_XMRIG=1
    XMRIG_DIR="$WORKER_HOME/xmrig-$XMRIG_VERSION"
  else
    XMRIG_DIR="$WORKER_HOME/xmrig-$INSTALLED_XMRIG"
  fi
fi

# =========================================================================
# DÉTECTION CPU AVANCÉE & CONFIGURATION
# =========================================================================
# Détection de l'architecture et du modèle
CPU_ARCH=$(uname -m)
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | head -n1 | cut -d: -f2- | xargs)
[[ -z "$CPU_MODEL" ]] && CPU_MODEL="Unknown CPU"
CPU_THREADS=$(nproc)

# --- 1. DÉTECTION ROBUSTE DU CACHE L3 ---
# Cette partie gère les K/M/G/KiB/MiB retournés par différentes versions de lscpu
L3_CACHE_RAW=$(lscpu 2>/dev/null | grep "L3 cache" | awk '{print $3, $4}' | head -n1)
# On nettoie pour ne garder que valeur et unité
L3_VAL=$(echo "$L3_CACHE_RAW" | sed -r 's/([0-9]+).*/\1/')
L3_UNIT=$(echo "$L3_CACHE_RAW" | grep -oP '[KMGT]i?B?' | head -n1)

# Conversion en Ko (KB)
L3_CACHE_KB=0
if [[ "$L3_UNIT" =~ K ]]; then L3_CACHE_KB=$L3_VAL; fi
if [[ "$L3_UNIT" =~ M ]]; then L3_CACHE_KB=$((L3_VAL * 1024)); fi
if [[ "$L3_UNIT" =~ G ]]; then L3_CACHE_KB=$((L3_VAL * 1024 * 1024)); fi

# Fallback : si parsing échoue, utiliser la méthode simple
if [ "$L3_CACHE_KB" -eq 0 ]; then
  L3_CACHE_KB=$(lscpu --bytes 2>/dev/null | grep "L3 cache" | awk '{print $NF}' | head -n1)
  # Si c'est en bytes, convertir en KB
  [[ -n "$L3_CACHE_KB" ]] && L3_CACHE_KB=$((L3_CACHE_KB / 1024))
fi

# --- 2. CALCUL DES THREADS OPTIMAUX (Règle des 2 Mo RandomX) ---
if [ "$L3_CACHE_KB" -gt 0 ]; then
  MAX_OPTIMAL_THREADS=$((L3_CACHE_KB / 2048))
else
  # Fallback ARM ou sans L3 : on utilise tous les threads par défaut
  MAX_OPTIMAL_THREADS=$CPU_THREADS
fi

# Sécurité : ne jamais dépasser le nombre de threads physiques du CPU
if [ "$MAX_OPTIMAL_THREADS" -gt "$CPU_THREADS" ]; then
  MAX_OPTIMAL_THREADS=$CPU_THREADS
fi

# --- 3. DÉTECTION AMD 3D V-CACHE ---
is_3d_vcache_cpu() {
  if [[ "$CPU_MODEL" =~ (7950X3D|7900X3D|7800X3D|5800X3D|5900X3D|9950X3D|9900X3D) ]]; then
    return 0
  fi
  return 1
}

# --- 4. APPLICATION DE LA CONFIGURATION ---

# Options de base (Hugepages seulement sur x86)
if [[ "$CPU_ARCH" == "x86_64" ]]; then
  XMRIG_OPTS_BASE="--randomx-1gb-pages --asm=auto --print-time 30 --http-host 127.0.0.1 --http-port 18888"
else
  XMRIG_OPTS_BASE="--asm=auto --print-time 30 --http-host 127.0.0.1 --http-port 18888"
fi

XMRIG_OPTS_EXTRA=""
AFFINITY=""

if [[ "$XMRIG_MODE" == "eco" ]]; then
  # === MODE ÉCO (50% charge) ===
  THREADS=$((CPU_THREADS / 2))
  [ "$THREADS" -lt 1 ] && THREADS=1

  # Optimisation spéciale X3D en mode ÉCO :
  # On force l'usage des coeurs pairs (physiques) pour éviter la chauffe SMT
  if is_3d_vcache_cpu && [[ "$CPU_ARCH" == "x86_64" ]]; then
    AFFINITY=$(seq 0 2 $((THREADS * 2 - 2)) | paste -sd, -)
  fi

else
  # === MODE PERFORMANCE (Max Hashrate) ===

  # Règle d'Or : On prend le Max possible autorisé par le cache
  THREADS=$MAX_OPTIMAL_THREADS

fi

# Application finale
XMRIG_OPTS_EXTRA+=" --threads=$THREADS"
[[ -n "$AFFINITY" ]] && XMRIG_OPTS_EXTRA+=" --cpu-affinity=$AFFINITY"

# --- LOGGING DE DEBUG (Pour vérifier au lancement) ---
printf "\n"
printf "  ${FG_CYAN}ℹ  DÉTECTION MATÉRIELLE${RESET}\n"
printf "     Architecture    : %s\n" "$CPU_ARCH"
printf "     CPU Model       : %s\n" "$CPU_MODEL"
printf "     Cache L3 Total  : %d MB\n" "$((L3_CACHE_KB / 1024))"
printf "     Threads CPU     : %d\n" "$CPU_THREADS"
printf "     Threads Cache   : %d (Capacité RandomX)\n" "$MAX_OPTIMAL_THREADS"
printf "  ${FG_GREEN}✔  CONFIGURATION XMRIG APPLIQUÉE${RESET}\n"
printf "     Mode            : %s\n" "$XMRIG_MODE"
printf "     Threads Mining  : %d\n" "$THREADS"
[[ -n "$AFFINITY" ]] && printf "     Affinité CPU    : %s (Fixée)\n" "$AFFINITY"
printf "\n"

# Configuration selon le mode de minage
if [[ "$MINING_MODE" == "solo" ]]; then
  XMRIG_EXEC_CMD="$XMRIG_DIR/xmrig $XMRIG_OPTS_BASE $XMRIG_OPTS_EXTRA -o 127.0.0.1:18081 --daemon --coin monero --user=$MONERO_ADDRESS"
  DEPENDS_ON="monerod.service"
elif [[ "$MINING_MODE" == "moneroocean" ]]; then
  MO_POOL="${MO_POOL:-gulf.moneroocean.stream:20128}"
  XMRIG_EXEC_CMD="$XMRIG_DIR/xmrig $XMRIG_OPTS_BASE $XMRIG_OPTS_EXTRA -o $MO_POOL --tls --coin monero --user=$MONERO_ADDRESS --rig-id=$(hostname)"
  DEPENDS_ON="network-online.target"
else # pool-nano | pool-mini | pool-full
  XMRIG_EXEC_CMD="$XMRIG_DIR/xmrig $XMRIG_OPTS_BASE $XMRIG_OPTS_EXTRA -o 127.0.0.1:$STRATUM_PORT"
  DEPENDS_ON="p2pool.service"
fi

# Unité systemd dynamique
UNIT_XMRIG=$(
  cat <<EOF
[Unit]
Description=XMRig (mode $XMRIG_MODE)
After=$DEPENDS_ON
Requires=$DEPENDS_ON

[Service]
User=root
WorkingDirectory=$XMRIG_DIR
ExecStart=$XMRIG_EXEC_CMD
Restart=always
RestartSec=10
LimitMEMLOCK=infinity
Nice=-5

[Install]
WantedBy=multi-user.target
EOF
)

# Détection de modification → redémarrage requis
UNIT_HASH_FILE="/etc/.last-xmrig-unit"
NEW_HASH=$(echo "$UNIT_XMRIG" | sha256sum | awk '{print $1}')
OLD_HASH=$(cat "$UNIT_HASH_FILE" 2>/dev/null || echo "")

if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
  echo "$NEW_HASH" >"$UNIT_HASH_FILE"
  RESTART_XMRIG=1
  printf "  ${FG_YELLOW}↻${RESET} Changement de configuration XMRig – redémarrage\n"
fi

ensure_unit xmrig.service "$UNIT_XMRIG"

# Attente stratum P2Pool ou synchro monerod selon le mode
wait_stratum_ready() {
  for _ in {1..60}; do
    nc -z 127.0.0.1 "$STRATUM_PORT" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# (Re)lancement de XMRig
if ((RESTART_XMRIG)); then
  systemctl daemon-reload

  if [[ "$MINING_MODE" == "solo" ]]; then
    (wait_monero_ready) &
    spinner "$!" "Synchronisation Monero pour XMRig…" >/dev/null
  elif [[ "$MINING_MODE" == "pool-nano" || "$MINING_MODE" == "pool-mini" || "$MINING_MODE" == "pool-full" ]]; then
    (wait_stratum_ready) &
    spinner "$!" "Attente ouverture Stratum P2Pool…" >/dev/null
  fi

  systemctl restart xmrig
  systemctl enable --now xmrig >/dev/null 2>&1

  # Validation que le stratum répond côté XMRig (pool modes)
  if [[ "$MINING_MODE" == "pool-nano" || "$MINING_MODE" == "pool-mini" || "$MINING_MODE" == "pool-full" ]]; then
    if ! wait_service_port xmrig.service "$STRATUM_PORT" 90 1; then
      echo -e "  ${FG_RED}✖${RESET} XMRig lancé, mais le port $STRATUM_PORT n’a pas répondu à temps."
      exit 1
    fi
  fi
else
  ensure_running_enabled xmrig.service
fi
if systemctl is-active --quiet xmrig; then
  printf "  ${FG_GREEN}✔${RESET} Le mineur XMRig est opérationnel\n"
fi

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Affichage lisible des ports et pare-feu ───────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "\n${FG_CYAN}${BOLD}🌐  État des ports réseau et pare-feu${RESET}\n"
printf "${FG_WHITE}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"
printf "${RESET}"

ss_out=$(ss -tunlp)
ufw_out=$(ufw status)

# Liste complète des ports à afficher (pour le récap réseau)
declare -a port_infos=()

# Ajout dynamique SSH
if [[ "${SSH_PORT:-0}" -gt 0 ]]; then
  port_infos+=("$SSH_PORT SSH (Administration)")
fi

# Reste des ports fixes
port_infos+=(
  "18080 Monero (RPC public)"
  "18081 Monero (API locale)"
  "18083 Monero (ZMQ live data)"
)

# Ajout conditionnel du Stratum local
if [[ -n "$STRATUM_PORT" ]]; then
  port_infos+=("$STRATUM_PORT Mineur (Stratum local)")
fi

# Ports externes P2Pool (toujours listés)
port_infos+=(
  "37890 P2Pool nano (reseau)"
  "37888 P2Pool mini (reseau)"
  "37889 P2Pool full (reseau)"
)

for entry in "${port_infos[@]}"; do
  port="${entry%% *}"
  label="${entry#* }"

  # État réseau
  if grep -qE ":${port}\\>" <<<"$ss_out"; then
    state_net="${FG_GREEN}✅ écoute${RESET}"
  else
    state_net="${FG_RED}❌ fermé${RESET}"
  fi

  # État pare-feu UFW
  if grep -qE "\\b${port}/tcp\\b" <<<"$ufw_out"; then
    if grep -qE "\\b${port}/tcp\\b.*ALLOW" <<<"$ufw_out"; then
      state_fw="${FG_GREEN}✅ autorisé${RESET}"
    elif grep -qE "\\b${port}/tcp\\b.*DENY" <<<"$ufw_out"; then
      state_fw="${FG_RED}❌ bloqué${RESET}"
    else
      state_fw="${FG_YELLOW}❓ inconnu${RESET}"
    fi
  else
    state_fw="${FG_YELLOW}❓ non listé${RESET}"
  fi

  echo -e "📦  Port : ${port}"
  echo -e "     ├─ Service      : ${label}"
  echo -e "     ├─ État réseau  : ${state_net}"
  echo -e "     └─ Pare-feu     : ${state_fw}"
  echo
done

echo

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Fin de l'initialisation ───────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
printf "${FG_MAGENTA}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"
printf "${FG_GREEN}${BOLD}🎯  Stack déployé avec succès — prêt à miner.${RESET}\n"
printf "📊  Lancement du tableau de bord interactif…${RESET}\n"
printf "${FG_MAGENTA}${BOLD}"
printf '─%.0s' {1..64}
printf "${RESET}\n"

# Attente stylisée avec player
pause=false
duration=5
start_time=$(date +%s)

# --- MODE DÉVELOPPEUR : Démarrer en pause ---
# Décommentez la ligne ci-dessous pour que le script se mette en pause automatiquement ici
pause=true
pause_start=$(date +%s) # <--- LIGNE À DÉCOMMENTER EN DEV
# --------------------------------------------

elapsed_pause=0
[[ "$pause" == false ]] && pause_start=0
last_remaining=-1

while :; do
  now=$(date +%s)

  if ! $pause; then
    time_elapsed=$((now - start_time - elapsed_pause))
    remaining=$((duration - time_elapsed))
    if ((remaining <= 0)); then
      break
    fi

    if ((remaining != last_remaining)); then
      printf "\r\033[K${FG_CYAN}▶️   Initialisation du tableau de bord dans %2d seconde(s)… ${FG_WHITE}${BOLD}[ESPACE = pause]${RESET}" "$remaining"
      last_remaining=$remaining
    fi
  else
    printf "\r\033[K${FG_YELLOW}⏸️   Pause — appuie sur ESPACE pour reprendre…${RESET}"
  fi

  # Lecture NON BLOQUANTE avec délai très court
  if read -rsn1 -t 0.1 input; then
    if [[ "$input" == " " ]]; then
      if $pause; then
        pause=false
        now=$(date +%s)
        elapsed_pause=$((elapsed_pause + now - pause_start))
      else
        pause=true
        pause_start=$(date +%s)
      fi
      last_remaining=-1
    fi
  fi

  sleep 0.1
done

printf "\r\033[K"

printf "${FG_BLUE}🕒  Monitoring en cours${RESET}\n"

#############################################################################################################
#############################################################################################################
#############################################################################################################
#####                                                                                                   #####
##### INTERACTIONS UTILISATEUR                                                                          #####
##### Ce bloc contient tous les menus interactifs appelés depuis le tableau de bord                     #####
#####                                                                                                   #####
#############################################################################################################
#############################################################################################################
#############################################################################################################

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Confirm ───────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
confirm() {
  local prompt="$1"
  printf "\n%b⚠  %s%b\n" "$FG_YELLOW" "$prompt" "$RESET"
  while true; do
    printf "%bContinuer ? (o/n) : %b" "$FG_CYAN" "$RESET"
    read -r reply
    case "$reply" in
      [oO]) return 0 ;;
      [nN]) return 1 ;;
      *) printf "%bRéponse invalide. Tape 'o' ou 'n'.%b\n" "$FG_RED" "$RESET" ;;
    esac
  done
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Exit (E) ──────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
prompt_quit_menu() {
  clear

  BOX_WIDTH=56
  TITLE="OPTIONS DE SORTIE"

  title_len=${#TITLE}
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))
  end_pad_len=$((BOX_WIDTH - title_len - padding))
  end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

  printf "${BOLD}${FG_CYAN}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"
  printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"
  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  echo -e "  ${FG_GREEN}1)${RESET} Quitter"
  echo -e "  ${FG_YELLOW}2)${RESET} Quitter + Arrêter les services"
  echo -e "  ${FG_RED}3)${RESET} Quitter + Arrêter + Désactiver les services"
  echo -e "  ${FG_CYAN}0)${RESET} Retour au tableau de bord"

  while true; do
    read -rp $'\n➜ Ton choix (0-3) : ' choice
    case "$choice" in
      1)
        echo -e "\n${FG_GREEN}✓${RESET} Sortie (services actifs)"
        exit 0
        ;;
      2)
        echo -e "\n${FG_YELLOW}⏹${RESET}  Arrêt des services..."
        systemctl stop xmrig p2pool minotari_node monerod 2>/dev/null || true
        echo -e "${FG_GREEN}✓${RESET} Services arrêtés"
        sleep 1
        exit 0
        ;;
      3)
        echo -e "\n${FG_RED}⚠${RESET}  Confirmer ? (tape OUI) : \c"
        read -r confirm
        if [[ "$confirm" == "OUI" ]]; then
          echo -e "${FG_RED}✖${RESET}  Arrêt + désactivation..."
          systemctl stop xmrig p2pool minotari_node monerod 2>/dev/null || true
          systemctl disable xmrig p2pool minotari_node monerod 2>/dev/null || true
          echo -e "${FG_GREEN}✓${RESET} Terminé"
          sleep 1
          exit 0
        else
          echo -e "${FG_YELLOW}↩${RESET}  Annulé"
          continue
        fi
        ;;
      0)
        echo -e "\n${FG_CYAN}↩${RESET}  Retour..."
        return
        ;;
      *)
        echo -e "${FG_RED}✗${RESET} Choix invalide (0-3)"
        ;;
    esac
  done
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Clean (X) ─────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
cleanup_stack() {
  clear

  BOX_WIDTH=56
  TITLE="NETTOYAGE ET DÉSINSTALLATION"

  title_len=${#TITLE}
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))
  end_pad_len=$((BOX_WIDTH - title_len - padding))
  end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

  printf "${BOLD}${FG_CYAN}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"
  printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"
  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  echo -e "  ${FG_YELLOW}1)${RESET} Supprimer le minage ${FG_WHITE}(XMRig + P2Pool)${RESET}"
  echo -e "  ${FG_RED}2)${RESET} Supprimer les nœuds ${FG_WHITE}(Monero + Tari)${RESET}"
  echo -e "  ${FG_RED}${BOLD}3)${RESET} Supprimer le stack complet ${FG_RED}[binaires + services + nœuds + blockchains + firewall + config]${RESET}"
  echo -e "  ${FG_CYAN}0)${RESET} Retour au tableau de bord"

  while true; do
    read -rp $'\n➜ Ton choix (0-3) : ' choice
    case "$choice" in
      1)
        echo -e "\n${FG_YELLOW}⚠${RESET}  Confirmer la suppression du minage ? (OUI / Entrée pour annuler) : \c"
        read -r confirm
        if [[ "$confirm" == "OUI" ]]; then
          echo -e "${FG_YELLOW}🧹${RESET} Nettoyage en cours..."
          (
            systemctl stop xmrig p2pool >/dev/null 2>&1 || true
            systemctl disable xmrig p2pool >/dev/null 2>&1 || true
            rm -f /etc/systemd/system/{xmrig,p2pool}.service
            rm -rf "$WORKER_HOME"/xmrig-* "$WORKER_HOME"/p2pool-*
            ufw delete allow "$STRATUM_PORT"/tcp >/dev/null 2>&1 || true
            ufw delete allow 37888/tcp >/dev/null 2>&1 || true
            ufw delete allow 37889/tcp >/dev/null 2>&1 || true
            systemctl daemon-reexec
          ) &
          spinner $! "Suppression des fichiers..."
          echo -e "${FG_GREEN}✓${RESET} Stack de minage supprimé."
          sleep 2
          return
        else
          echo -e "${FG_CYAN}↩${RESET}  Annulé."
          continue
        fi
        ;;

      2)
        echo -e "\n${FG_RED}⚠${RESET}  Confirmer la suppression des nœuds ? (OUI / Entrée pour annuler) : \c"
        read -r confirm
        if [[ "$confirm" == "OUI" ]]; then
          echo -e "${FG_YELLOW}🧹${RESET} Nettoyage des nœuds en cours..."
          (
            systemctl stop monerod minotari_node >/dev/null 2>&1 || true
            systemctl disable monerod minotari_node >/dev/null 2>&1 || true
            rm -f /etc/systemd/system/{monerod,minotari_node}.service
            systemctl daemon-reexec
            rm -rf "$WORKER_HOME"/.bitmonero
            rm -rf "$WORKER_HOME"/.tari
            rm -rf "$WORKER_HOME"/monero-* "$WORKER_HOME"/tari-*
            ufw delete deny 18080/tcp >/dev/null 2>&1 || true
            ufw delete deny 18081/tcp >/dev/null 2>&1 || true
            ufw delete deny 18083/tcp >/dev/null 2>&1 || true
            ufw delete allow 18090/tcp >/dev/null 2>&1 || true
            ufw delete deny 18142/tcp >/dev/null 2>&1 || true
            ufw delete allow 18189/tcp >/dev/null 2>&1 || true
          ) &
          spinner $! "Suppression des blockchains et binaires..."
          echo -e "${FG_GREEN}✓${RESET} Nœuds Monero et Tari supprimés (Espace libéré)."
          sleep 2
          return
        else
          echo -e "${FG_CYAN}↩${RESET}  Annulé."
          continue
        fi
        ;;

      3)
        echo -e "\n${FG_RED}⚠${RESET}  Confirmer la suppression du stack complet ? (OUI / Entrée pour annuler) : \c"
        read -r confirm
        if [[ "$confirm" == "OUI" ]]; then
          echo -e "${FG_YELLOW}🧹${RESET} Nettoyage en cours..."

          local keep_ssh=0
          local ssh_state_msg="SSH bloqué (selon config)"

          if [[ "${SSH_PORT:-0}" -gt 0 ]]; then
            keep_ssh=1
            ssh_state_msg="SSH conservé (port $SSH_PORT)"
          fi

          (

            systemctl stop xmrig p2pool minotari_node monerod >/dev/null 2>&1 || true
            systemctl disable xmrig p2pool minotari_node monerod >/dev/null 2>&1 || true

            rm -f /etc/systemd/system/{xmrig,p2pool,minotari_node,monerod}.service
            systemctl daemon-reexec
            rm -rf "$WORKER_HOME"/{xmrig,p2pool,tari,monero}-*
            rm -rf "$WORKER_HOME/p2pool-stats"
            rm -rf "$WORKER_HOME/.bitmonero"
            rm -rf "$WORKER_HOME/.tari"
            rm -f "$CONFIG_FILE"
            ufw --force reset >/dev/null 2>&1
            ufw default deny incoming >/dev/null 2>&1
            ufw default allow outgoing >/dev/null 2>&1

            if [[ "$keep_ssh" -eq 1 ]]; then
              ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1
            fi

            ufw --force enable >/dev/null 2>&1

          ) &
          spinner $! "Suppression stack + Reset UFW ($ssh_state_msg)..."

          echo -e "${FG_GREEN}✓${RESET} Stack supprimé. Pare-feu réinitialisé : ${BOLD}$ssh_state_msg${RESET}."

          if [[ "$keep_ssh" -ne 1 ]] && [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
            echo -e "\n${FG_RED}⚠  ATTENTION : SSH a été coupé (car désactivé dans la config) alors que vous êtes connecté.${RESET}"
            echo -e "${FG_RED}   Pour ne pas perdre la main, tapez immédiatement : ${BOLD}ufw allow <votre-port-actuel>/tcp${RESET}"
          fi

          sleep 2
          return
        else
          echo -e "${FG_CYAN}↩${RESET}  Annulé."
          continue
        fi
        ;;

      0)
        echo -e "\n${FG_CYAN}↩${RESET}  Retour..."
        return
        ;;

      *)
        echo -e "${FG_RED}✗${RESET} Choix invalide (0-3)"
        ;;
    esac
  done
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Update (U) ────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
force_update() {
  clear

  BOX_WIDTH=56
  TITLE="MISE À JOUR COMPLÈTE"

  title_len=${#TITLE}
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))
  end_pad_len=$((BOX_WIDTH - title_len - padding))
  end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

  printf "${BOLD}${FG_CYAN}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"
  printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"
  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  echo -e "  ${FG_GREEN}1)${RESET} Lancer la mise à jour ${FG_WHITE}(Script + Binaires)${RESET}"
  echo -e "  ${FG_CYAN}0)${RESET} Retour au tableau de bord"

  while true; do
    read -rp $'\n➜ Ton choix (0-1) : ' choice
    case "$choice" in
      1)
        echo -e "\n${FG_GREEN}🚀${RESET} Démarrage de la mise à jour..."

        (sleep 3) &
        spinner $! "Téléchargement en cours..."

        echo -e "${FG_GREEN}✓${RESET} Terminé. Relance du script..."
        sleep 1
        exec "$0"
        ;;
      0)
        echo -e "\n${FG_CYAN}↩${RESET}  Retour..."
        return
        ;;
      *)
        echo -e "${FG_RED}✗${RESET} Choix invalide (0-1)"
        ;;
    esac
  done
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Config (S) ────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
edit_initial_config() {
  clear

  BOX_WIDTH=56
  TITLE="MODIFIER LA CONFIGURATION"

  # Calcul du padding centré (Identique à force_update)
  title_len=${#TITLE}
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))
  end_pad_len=$((BOX_WIDTH - title_len - padding))
  end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

  # Cadre
  printf "${BOLD}${FG_CYAN}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"
  printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"
  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  # Avertissement précis
  printf "  ${FG_YELLOW}⚠  AVERTISSEMENT :${RESET} L'accès au menu va ${BOLD}redémarrer le script${RESET}.\n"
  printf "  Si la configuration change, les services concernés redémarreront.\n\n"

  # Options (Style : 1=Vert, 0=Cyan, pas d'emojis inutiles)
  echo -e "  ${FG_GREEN}1)${RESET} Modifier la configuration ${FG_WHITE}(Redémarrage)${RESET}"
  echo -e "  ${FG_CYAN}0)${RESET} Retour au tableau de bord"

  while true; do
    read -rp $'\n➜ Ton choix (0-1) : ' choice
    case "$choice" in
      1)
        echo -e "\n${FG_GREEN}🚀${RESET} Chargement du formulaire..."

        if [[ -f "$CONFIG_FILE" ]]; then
          sed -i 's/^INITIAL_SETUP_DONE=.*/INITIAL_SETUP_DONE=editing/' "$CONFIG_FILE"
        fi

        sleep 0.5
        exec "$0"
        ;;

      0)
        echo -e "\n${FG_CYAN}↩${RESET}  Retour..."
        return
        ;;

      *)
        echo -e "${FG_RED}✗${RESET} Choix invalide (0-1)"
        ;;
    esac
  done
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Logs (L) ──────────────────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
show_logs() {

  clear

  # Largeur fixe
  BOX_WIDTH=56
  MODE_DISPLAY="${MINING_MODE:-Inconnu}"
  TITLE="LOGS EN DIRECT – $MODE_DISPLAY"

  # Calcul padding
  title_len=${#TITLE}
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))

  # Bordures
  printf "${BOLD}${FG_CYAN}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"

  printf "║%s%s%s║\n" "$pad" "$TITLE" "$(printf ' %.0s' $(seq 1 $((BOX_WIDTH - title_len - padding))))"

  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  # Message
  printf "${FG_YELLOW}↩️  Appuie sur une touche pour revenir au tableau de bord...${RESET}\n\n"

  # Couleurs
  BLUE="\033[1;34m"
  GREEN="\033[1;32m"
  RED="\033[1;31m"
  MAGENTA="\033[1;35m"
  CYAN="\033[1;36m"
  NC="\033[0m"

  case "$MINING_MODE" in
    solo)
      (
        sudo journalctl -u xmrig -u monerod -n 500 -f &
        echo $! >/tmp/logpid
      ) | while IFS= read -r line; do
        datetime=$(echo "$line" | awk '{print $1, $2, $3}')

        if [[ "$line" =~ new\ job ]]; then
          echo -e "$datetime ${GREEN}[ NEW JOB ]${NC} 📥 Nouveau bloc à miner – ton rig se met au travail en solo."
          continue
        fi
        if [[ "$line" =~ Found\ block || "$line" =~ mined\ block ]]; then
          echo -e "$datetime ${MAGENTA}[ BLOCK   ]${NC} 🎉 Ton rig a trouvé un bloc ! Il est en cours de propagation sur le réseau."
          continue
        fi
        if [[ "$line" =~ Block\ reward ]]; then
          echo -e "$datetime ${GREEN}[ REWARD  ]${NC} 🪙 Récompense enregistrée – l’un de TES blocs a été validé !"
          continue
        fi
        if [[ "$line" =~ Sync ]]; then
          echo -e "$datetime ${BLUE}[ SYNC    ]${NC} 🔄 Monerod est en train de se synchroniser avec la blockchain..."
          continue
        fi
        if [[ "$line" =~ error ]]; then
          echo -e "$datetime ${RED}[ ERROR   ]${NC} ❌ Erreur détectée : ${line##*error}"
          continue
        fi
        if [[ "$line" =~ speed\ 10s/60s/15m ]]; then
          if [[ "$line" =~ speed\ 10s/60s/15m\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ H/s ]]; then
            hs10="${BASH_REMATCH[1]}"
            hs60="${BASH_REMATCH[2]}"
            hs15="${BASH_REMATCH[3]}"
            printf "%s ${CYAN}[ HASHRATE]${NC} ⛏️ 10s: %s H/s | 60s: %s H/s | 15m: %s H/s\n" "$datetime" "$hs10" "$hs60" "$hs15"
          fi
        fi
      done &
      read -rsn1
      if [[ -f /tmp/logpid ]]; then
        pid=$(cat /tmp/logpid)
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      fi
      wait
      ;;

    pool-nano | pool-mini | pool-full)
      (
        sudo journalctl -u p2pool -u xmrig -f &
        echo $! >/tmp/logpid
      ) | while IFS= read -r line; do
        datetime=$(echo "$line" | awk '{print $1, $2, $3}')

        if [[ "$line" =~ BLOCK\ ACCEPTED ]]; then
          echo -e "$datetime ${MAGENTA}[ BLOC    ]${NC} 🥳 Bloc trouvé et accepté par le réseau Monero ! Récompense en approche."
          continue
        fi
        if [[ "$line" =~ SHARE\ FOUND ]]; then
          echo -e "$datetime ${BLUE}[ INFO    ]${NC} 🎯 Share trouvé ! Ton rig vient de soumettre un travail valide au pool."
          continue
        fi
        if [[ "$line" =~ SHARE\ ADDED ]]; then
          echo -e "$datetime ${GREEN}[ POOL    ]${NC} ✅ Share accepté et ajouté à la sharechain. Ta participation est reconnue."
          continue
        fi
        if [[ "$line" =~ Sync ]]; then
          echo -e "$datetime ${BLUE}[ SYNC    ]${NC} 🔄 Monerod est en train de se synchroniser avec la blockchain..."
          continue
        fi
        if [[ "$line" =~ error ]]; then
          echo -e "$datetime ${RED}[ ERROR   ]${NC} ❌ Erreur détectée : ${line##*error}"
          continue
        fi
        if [[ "$line" =~ speed\ 10s/60s/15m ]]; then
          if [[ "$line" =~ speed\ 10s/60s/15m\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ H/s ]]; then
            hs10="${BASH_REMATCH[1]}"
            hs60="${BASH_REMATCH[2]}"
            hs15="${BASH_REMATCH[3]}"
            printf "%s ${CYAN}[ HASHRATE]${NC} ⛏️ 10s: %s H/s | 60s: %s H/s | 15m: %s H/s\n" "$datetime" "$hs10" "$hs60" "$hs15"
          fi
        fi
      done &
      read -rsn1
      if [[ -f /tmp/logpid ]]; then
        pid=$(cat /tmp/logpid)
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      fi
      wait
      ;;

    moneroocean)
      (
        sudo journalctl -u xmrig -n 500 -f &
        echo $! >/tmp/logpid
      ) | while IFS= read -r line; do
        datetime=$(echo "$line" | awk '{print $1, $2, $3}')

        if [[ "$line" =~ new\ job\ from ]]; then
          echo -e "$datetime ${GREEN}[ NEW JOB ]${NC} 📥 Nouveau job reçu du pool MoneroOcean – ton rig se remet au travail."
          continue
        fi
        if [[ "$line" =~ submit\ result\ sent ]]; then
          echo -e "$datetime ${BLUE}[ SUBMIT  ]${NC} 🎯 Share soumis au pool."
          continue
        fi
        if [[ "$line" =~ accepted ]]; then
          echo -e "$datetime ${GREEN}[ ACCEPTED]${NC} ✅ Share accepté par MoneroOcean – récompense en cours d'accumulation !"
          continue
        fi
        if [[ "$line" =~ rejected ]]; then
          echo -e "$datetime ${RED}[ REJECTED]${NC} ⚠️ Share rejeté par le pool – vérifie ton overclock, ta stabilité… ou attends que ça se stabilise un peu."
          continue
        fi
        if [[ "$line" =~ error ]]; then
          echo -e "$datetime ${RED}[ ERROR   ]${NC} ❌ Erreur détectée : ${line##*error}"
          continue
        fi
        if [[ "$line" =~ speed\ 10s/60s/15m ]]; then
          if [[ "$line" =~ speed\ 10s/60s/15m\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ ([0-9.]+|n/a)\ H/s ]]; then
            hs10="${BASH_REMATCH[1]}"
            hs60="${BASH_REMATCH[2]}"
            hs15="${BASH_REMATCH[3]}"
            printf "%s ${CYAN}[ HASHRATE]${NC} ⛏️ 10s: %s H/s | 60s: %s H/s | 15m: %s H/s\n" "$datetime" "$hs10" "$hs60" "$hs15"
          fi
        fi
      done &
      read -rsn1
      if [[ -f /tmp/logpid ]]; then
        pid=$(cat /tmp/logpid)
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      fi
      wait
      ;;

    *)
      echo -e "${FG_RED}❌ Mode de minage inconnu : $MINING_MODE${RESET}"
      ;;
  esac
}

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Support Project (D) ───────────────────────────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
support_project() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

  clear
  BOX_WIDTH=64
  TITLE="💖  SOUTENIR MON TRAVAIL"

  title_len=$((${#TITLE} + 1))
  padding=$(((BOX_WIDTH - title_len) / 2))
  pad=$(printf ' %.0s' $(seq 1 $padding))
  extra_pad=""
  if (((BOX_WIDTH - title_len) % 2 != 0)); then extra_pad=" "; fi

  printf "${BOLD}${FG_MAGENTA}╔"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╗\n"
  printf "║%s%s%s%s║\n" "$pad" "$TITLE" "$pad" "$extra_pad"
  printf "╚"
  printf '═%.0s' $(seq 1 $BOX_WIDTH)
  printf "╝${RESET}\n\n"

  echo -e "  Ce script est maintenu bénévolement sur mon temps libre."
  echo -e "  Trois façons simples de m'encourager :"
  echo -e "  ${FG_WHITE}────────────────────────────────────────────────────────────────${RESET}"

  local tari_menu_txt=""
  local tari_desc=""
  local is_tari_dev=0

  if [[ "$TARI_ADDRESS" == "$DEV_TARI_WALLET" ]]; then
    is_tari_dev=1
    tari_menu_txt="${FG_GREEN}✅ DÉSACTIVER le 'Dev Mining' (Tari)${RESET}"
    tari_desc="${FG_GREEN}   Actuellement actif. Merci pour votre soutien ! ❤️${RESET}"
  else
    tari_menu_txt="${FG_WHITE}ACTIVER le 'Dev Mining' (Tari)${RESET}"
    tari_desc="${FG_WHITE}   Le merge mining mine Tari en parallèle via Monero (0% CPU requis).\n     Les blocs solo étant rares, offrir cette chance au dev ne vous coûte rien.${RESET}"
  fi

  local xmr_menu_txt=""
  local xmr_desc=""
  local is_xmr_dev=0

  if [[ "$MONERO_ADDRESS" == "$DEV_XMR_WALLET" ]]; then
    is_xmr_dev=1
    xmr_menu_txt="${FG_GREEN}✅ DÉSACTIVER le 'Dev Mining' (Monero)${RESET}"
    xmr_desc="${FG_GREEN}   Actuellement actif. Merci pour votre soutien ! ❤️${RESET}"
  else
    xmr_menu_txt="${FG_WHITE}Activer le 'Dev Mining' (Monero)${RESET}"
    xmr_desc="${FG_WHITE}   Lance un minage vers le wallet du développeur (24h dans le mois par exemple).\n     C'est un don de puissance ponctuel (à faire manuellement) sans impact durable.${RESET}"
  fi

  # Option 1 (Tari)
  echo -e "\n  ${FG_GREEN}1)${RESET} ${BOLD}$tari_menu_txt${RESET}"
  echo -e "  $tari_desc"

  # Option 2 (Monero)
  echo -e "\n  ${FG_GREEN}2)${RESET} ${BOLD}$xmr_menu_txt${RESET}"
  echo -e "  $xmr_desc"

  # Option 3 (Café)
  echo -e "\n  ${FG_GREEN}3)${RESET} ${BOLD}M'offrir un café (XMR)${RESET}"
  echo -e "     Affiche l'adresse publique du portefeuille du dev pour un don libre."
  echo -e "     Idéal si vous préférez contribuer directement sans utiliser le minage."

  # Option 0
  echo -e "\n  ${FG_CYAN}0)${RESET} Retour au tableau de bord"

  # --- Boucle d'interaction ---
  while true; do
    read -rp $'\n➜ Ton choix (0-3) : ' choice
    case "$choice" in
      1)
        echo -e "\n${FG_YELLOW}⚙ Traitement de la configuration Tari...${RESET}"

        if ! grep -q "^BAK_TARI_ADDRESS=" "$CONFIG_FILE"; then
          echo 'BAK_TARI_ADDRESS=""' >>"$CONFIG_FILE"
        fi

        if [[ "$is_tari_dev" -eq 1 ]]; then
          echo -e "${FG_CYAN}↩  Restauration de votre adresse Tari d'origine...${RESET}"
          local restore_addr="${BAK_TARI_ADDRESS:-}"
          sed -i "s|^TARI_ADDRESS=.*|TARI_ADDRESS=\"$restore_addr\"|" "$CONFIG_FILE"
          sed -i 's|^BAK_TARI_ADDRESS=.*|BAK_TARI_ADDRESS=""|' "$CONFIG_FILE"
          echo -e "${FG_YELLOW}⚠  Dev Mining Tari désactivé.${RESET}"
        else
          echo -e "${FG_GREEN}💖  Activation du soutien Tari...${RESET}"
          local current_user_addr="$TARI_ADDRESS"
          sed -i "s|^BAK_TARI_ADDRESS=.*|BAK_TARI_ADDRESS=\"$current_user_addr\"|" "$CONFIG_FILE"

          if grep -q "^TARI_ADDRESS=" "$CONFIG_FILE"; then
            sed -i "s|^TARI_ADDRESS=.*|TARI_ADDRESS=\"$DEV_TARI_WALLET\"|" "$CONFIG_FILE"
          else
            echo "TARI_ADDRESS=\"$DEV_TARI_WALLET\"" >>"$CONFIG_FILE"
          fi
          echo -e "${FG_GREEN}✔${RESET} Merci ! Votre puissance Tari soutient le développeur."
        fi

        echo -e "${FG_CYAN}🔄 Redémarrage du script pour appliquer...${RESET}"
        sleep 5
        exec "$0"
        ;;

      2)
        echo -e "\n${FG_YELLOW}⚙ Traitement de la configuration Monero...${RESET}"

        if ! grep -q "^BAK_MONERO_ADDRESS=" "$CONFIG_FILE"; then
          echo 'BAK_MONERO_ADDRESS=""' >>"$CONFIG_FILE"
        fi

        if [[ "$is_xmr_dev" -eq 1 ]]; then
          echo -e "${FG_CYAN}↩  Restauration de votre adresse Monero d'origine...${RESET}"

          local restore_xmr="${BAK_MONERO_ADDRESS:-}"

          if [[ -z "$restore_xmr" ]]; then
            echo -e "${FG_RED}⚠ Erreur : Pas d'adresse de sauvegarde trouvée. Veuillez remettre votre adresse dans le menu Config.${RESET}"
            sleep 3
          else
            sed -i "s|^MONERO_ADDRESS=.*|MONERO_ADDRESS=\"$restore_xmr\"|" "$CONFIG_FILE"
            sed -i 's|^BAK_MONERO_ADDRESS=.*|BAK_MONERO_ADDRESS=""|' "$CONFIG_FILE"
            echo -e "${FG_YELLOW}⚠  Dev Mining Monero désactivé.${RESET}"
          fi

        else
          echo -e "${FG_GREEN}💖  Activation du soutien Monero...${RESET}"

          local current_xmr="$MONERO_ADDRESS"
          sed -i "s|^BAK_MONERO_ADDRESS=.*|BAK_MONERO_ADDRESS=\"$current_xmr\"|" "$CONFIG_FILE"

          if grep -q "^MONERO_ADDRESS=" "$CONFIG_FILE"; then
            sed -i "s|^MONERO_ADDRESS=.*|MONERO_ADDRESS=\"$DEV_XMR_WALLET\"|" "$CONFIG_FILE"
          else
            echo "MONERO_ADDRESS=\"$DEV_XMR_WALLET\"" >>"$CONFIG_FILE"
          fi

          echo -e "${FG_GREEN}✔${RESET} Merci ! Votre puissance Monero soutient le développeur."
        fi

        echo -e "${FG_CYAN}🔄 Redémarrage du script pour appliquer...${RESET}"
        sleep 5
        exec "$0"
        ;;

      3)
        echo -e "\n${FG_GREEN}Merci pour votre soutien ! ❤️${RESET}"
        echo -e "\n${FG_WHITE}Scannez ce QR Code :${RESET}"
        qrencode -t ANSIUTF8 "$DEV_XMR_WALLET"
        echo -e "\n${FG_CYAN}Ou copiez l'adresse ci-dessous :${RESET}"
        echo -e "${BG_WHITE}${FG_BLACK} $DEV_XMR_WALLET ${RESET}"
        echo -e "\n${FG_WHITE}Appuyez sur une touche pour revenir...${RESET}"
        read -rsn1
        support_project
        return
        ;;

      0)
        return
        ;;

      *)
        echo -e "${FG_RED}❌ Choix invalide.${RESET}"
        ;;
    esac
  done
}

#############################################################################################################
#############################################################################################################
#############################################################################################################
#####                                                                                                   #####
##### TABLEAU DE BORD                                                                                   #####
##### Ce bloc gère l'affichage du tableau de bord et intercepte les touches pendant le compte à rebours #####
#####                                                                                                   #####
#############################################################################################################
#############################################################################################################
#############################################################################################################

# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
# Boucle du tableau de bord (non bloquante) ─────────────────────────────────────────────────────────────── #
# ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
REFRESH_IMMEDIATE=false
last_draw=0
while :; do
  now_sec=$(date +%s)

  if ((now_sec - LAST_VERSION_CHECK >= VERSION_CHECK_INTERVAL)); then
    refresh_latest_versions
    LAST_VERSION_CHECK=$now_sec
  fi

  if ((now_sec - last_draw >= REFRESH_INTERVAL)) || [[ "$REFRESH_IMMEDIATE" == true ]]; then
    clear
    last_draw=$now_sec
    REFRESH_IMMEDIATE=false

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # En-tête ───────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    hostname=$(hostname)
    now=$(date '+%Y-%m-%d %H:%M:%S')
    TITLE="TABLEAU DE BORD  —  $hostname  —  $now"

    BOX_WIDTH=83
    title_len=${#TITLE}
    padding=$(((BOX_WIDTH - title_len) / 2))
    pad=$(printf ' %.0s' $(seq 1 $padding))
    end_pad_len=$((BOX_WIDTH - title_len - padding))
    end_pad=$(printf ' %.0s' $(seq 1 $end_pad_len))

    printf "${BOLD}${FG_BLUE}╔"
    printf '═%.0s' $(seq 1 $BOX_WIDTH)
    printf "╗\n"

    printf "║%s%s%s║\n" "$pad" "$TITLE" "$end_pad"

    printf "╚"
    printf '═%.0s' $(seq 1 $BOX_WIDTH)
    printf "╝${RESET}\n"

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Santé du stack ────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}🩺  Santé du stack${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    # Collecte des métriques rapides
    sync_pct=0
    speed10=0

    # 1. Synchronisation du nœud Monero (Via API RPC)
    if systemctl is-active --quiet monerod; then
      info=$(curl -s -m2 http://127.0.0.1:18081/get_info 2>/dev/null || echo "")
      if [[ -n "$info" ]]; then
        h=$(jq -r '.height' <<<"$info")
        t=$(jq -r '.target_height // .height' <<<"$info")
        ((t == 0)) && t=$h
        if ((t > 0)); then
          sync_pct=$(awk "BEGIN{printf \"%.1f\", ($h/$t)*100}")
        else
          sync_pct="0.0"
        fi
      fi
    fi

    # 2. Hashrate XMRig (Via API HTTP - Ultra rapide)
    xmrig_hr_ok=0
    speed10="0"

    if xmrig_json=$(curl -s -m 0.5 http://127.0.0.1:18888/2/summary 2>/dev/null); then
      speed10=$(echo "$xmrig_json" | jq -r '.hashrate.total[0] // 0')

      (($(awk -v h="$speed10" 'BEGIN{print (h > 0)}'))) && xmrig_hr_ok=1
    fi

    # Indicateurs booléens réutilisables
    monerod_sync_ok=0
    (($(awk "BEGIN{print ($sync_pct >= 99.9)}"))) && monerod_sync_ok=1
    p2pool_ok=0
    [[ "$MINING_MODE" =~ ^pool- ]] && systemctl is-active --quiet p2pool && p2pool_ok=1

    # Sélection de l’humeur
    mood_icon="❓"
    mood_lines=()

    case "$MINING_MODE" in
      solo)
        if ((!monerod_sync_ok)); then
          mood_icon="⏳"
          mood_lines=("Synchronisation du nœud : ${sync_pct}%." "Le minage solo démarre à 100 %." "Laisse tourner la machine pour rattraper la chaîne.")
        elif ((xmrig_hr_ok)); then
          mood_icon="😄"
          mood_lines=("Minage solo actif" "Chaque hash te rapproche d’un bloc." "Uptime = Récompenses. Ne touche plus à rien !")
        elif systemctl is-active --quiet xmrig; then
          mood_icon="😐"
          mood_lines=("XMRig tourne mais pas de hashrate récent." "Vérifie l’affinité CPU / BIOS et le mode performance." "Sans hash, pas de XMR…")
        else
          mood_icon="✖️"
          mood_lines=("XMRig est arrêté." "Relance-le ou vérifie la configuration.")
        fi
        ;;

      pool-nano | pool-mini | pool-full)
        if ((!monerod_sync_ok)); then
          mood_icon="⏳"
          mood_lines=("Synchronisation du nœud : ${sync_pct}%." "P2Pool attend la fin de la synchro." "Patience, le réseau n’aime pas les demi-mesures.")
        elif ((!p2pool_ok)); then
          mood_icon="😡"
          mood_lines=("P2Pool n’est pas actif !" "Redémarre le service \`p2pool\`." "Sans P2Pool, aucune share ne partira au réseau.")
        elif ((xmrig_hr_ok)); then
          mood_icon="😄"
          mood_lines=("P2Pool ${MINING_MODE#pool-} au top" "Les shares défilent, le bloc arrive !" "Plus ça tourne, plus ça paye 🚀")
        elif systemctl is-active --quiet xmrig; then
          mood_icon="😐"
          mood_lines=("XMRig actif mais hashrate timide." "Optimise OC / refroidissement." "Tes voisins de pool comptent sur toi !")
        else
          mood_icon="✖️"
          mood_lines=("XMRig est arrêté." "Impossible d’envoyer des shares sans lui.")
        fi
        ;;

      moneroocean)
        if ((xmrig_hr_ok)); then
          mood_icon="😄"
          mood_lines=("Minage MoneroOcean OK" "Le pool auto-switch optimise tes profits." "Surveille la page de payouts pour voir tomber les XMR.")
        elif systemctl is-active --quiet xmrig; then
          mood_icon="😐"
          mood_lines=("XMRig tourne mais sans hashrate visible." "Peut-être un algo non supporté ? Vérifie la conf Ocean." "Pas de hash = pas de revenu.")
        else
          mood_icon="✖️"
          mood_lines=("XMRig est arrêté." "Relance \`xmrig-ocean\` pour reprendre le minage.")
        fi
        ;;

      *)
        mood_icon="🕵️"
        mood_lines=("Mode de minage inconnu : $MINING_MODE." "Consulte la configuration ou relance le script.")
        ;;
    esac

    # Affichage de l’humeur
    echo -e "  ${BOLD}${mood_icon} ${mood_lines[0]}${RESET}"
    for ((i = 1; i < ${#mood_lines[@]} && i < 5; i++)); do
      echo -e "     ${mood_lines[$i]}"
    done

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Configuration ─────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}📝  Configuration initiale${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    # Adresse abrégée + type
    short_addr="${MONERO_ADDRESS:0:11}…${MONERO_ADDRESS: -6}"
    type="standard"
    [[ $MONERO_ADDRESS =~ ^8 ]] && type="sous-adresse"
    [[ $MONERO_ADDRESS =~ ^4[0-9AB] && ${#MONERO_ADDRESS} -gt 100 ]] && type="adresse intégrée"

    # Adresse Tari abrégée (si configurée)
    if [[ -n "$TARI_ADDRESS" ]]; then
      short_tari="${TARI_ADDRESS:0:11}…${TARI_ADDRESS: -6}"
    else
      short_tari=""
    fi

    # Libellé lisible pour le mode de performance
    case "$XMRIG_MODE" in
      perf) mode_label="performance" ;;
      eco) mode_label="économique" ;;
      *) mode_label="inconnu" ;;
    esac

    # Libellé lisible pour le mode de minage
    case "$MINING_MODE" in
      solo) mining_label="SOLO" ;;
      pool-nano) mining_label="P2Pool NANO" ;;
      pool-mini) mining_label="P2Pool MINI" ;;
      pool-full) mining_label="P2Pool FULL" ;;
      moneroocean) mining_label="MoneroOcean" ;;
      *) mining_label="inconnu" ;;
    esac

    # Affichage
    printf "  ${FG_GREEN}✔${RESET} Mode de minage   : %s\n" "$mining_label"
    if [[ -n "$TARI_ADDRESS" ]]; then
      printf "  ${FG_GREEN}✔${RESET} Merge mining     : %s (Tari)\n" "$short_tari"
    else
      printf "  ${FG_YELLOW}○${RESET} Merge mining     : désactivé\n"
    fi
    printf "  ${FG_GREEN}✔${RESET} Adresse Monero   : %s\n" "$short_addr"
    printf "  ${FG_GREEN}✔${RESET} Type d’adresse   : %s\n" "$type"
    printf "  ${FG_GREEN}✔${RESET} Mode XMRig       : %s\n" "$mode_label"
    if [[ "${SSH_PORT:-0}" -gt 0 ]]; then
      ssh_msg="autorisé (port $SSH_PORT)"
    else
      ssh_msg="bloqué"
    fi
    printf "  ${FG_GREEN}✔${RESET} Accès SSH        : %s\n" "$ssh_msg"

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Légendes ──────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}📋  Légende des icônes${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    printf "  ${FG_YELLOW}⧖${RESET}  : En attente — synchronisation ou démarrage en cours\n"
    printf "  ${FG_GREEN}✔${RESET}  : État conforme — tout est OK\n"
    printf "  ${FG_YELLOW}⚠${RESET}  : Avertissement — nécessite une attention mineure\n"
    printf "  ${FG_RED}✖${RESET}  : Problème — fonctionnement du stack bloqué\n"

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Monero ────────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}📡  Nœud Monero${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    if [[ "$MINING_MODE" == "moneroocean" ]]; then
      printf "\n${FG_YELLOW}${BOLD}  ⏭ Le nœud Monero n'est pas utile en mode %s.${RESET}\n" "$mining_label"
    else

      status="inactive"
      icon="✖"
      color=$FG_RED
      monero_msg="${FG_WHITE}Le nœud Monero ne répond pas.${RESET}"

      if systemctl is-active --quiet monerod; then
        if info=$(curl -s -m 1 http://127.0.0.1:18081/get_info 2>/dev/null); then

          height=$(echo "$info" | jq -r '.height // 0')
          target=$(echo "$info" | jq -r '.target_height // 0')
          ((target == 0)) && target=$height

          in_peers=$(echo "$info" | jq -r '.incoming_connections_count // 0')
          out_peers=$(echo "$info" | jq -r '.outgoing_connections_count // 0')
          total_peers=$((in_peers + out_peers))

          is_synced=$(echo "$info" | jq -r '.synchronized // false')

          if [[ "$is_synced" == "true" ]] || ((height >= target - 2)); then
            icon="✔"
            color=$FG_GREEN
            status="ok"
            monero_msg="${FG_WHITE}Synchronisé ${BG_WHITE}${FG_BLACK} (Hauteur: ${height}/${target} | Peers: ${total_peers}) ${RESET}"
          elif ((total_peers > 0)); then
            icon="⧖"
            color=$FG_YELLOW
            status="warning"
            if ((target > 0)); then
              pct=$(awk "BEGIN{printf \"%.1f\", ($height/$target)*100}")
            else
              pct="0.0"
            fi
            monero_msg="${FG_WHITE}Synchro ${pct}% ${BG_WHITE}${FG_BLACK} (Hauteur: ${height}/${target} | Peers: ${total_peers}) ${RESET}"
          else
            icon="⚠"
            color=$FG_RED
            status="error"
            monero_msg="${FG_WHITE}En attente de pairs... (Peers: 0)${RESET}"
          fi
        fi
      fi

      describe_component "monerod" "Monero" "$INSTALLED_MONERO" "$MONERO_VERSION" "monerod"

      printf "  %b%s %b\n" "$color" "$icon" "$monero_msg"

      printf "  ${FG_GREEN}✔${RESET} Pour consulter les logs : $ sudo journalctl -u monerod -f\n"

    fi

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Tari ──────────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}💎 Nœud Tari${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    if [[ -z "$TARI_ADDRESS" || "$MINING_MODE" == "moneroocean" || "$MINING_MODE" == "solo" ]]; then
      if [[ "$MINING_MODE" == "moneroocean" ]]; then
        printf "\n${FG_YELLOW}${BOLD}  ⏭ Tari est désactivé en mode MoneroOcean (nécessite P2Pool).${RESET}\n"
      elif [[ "$MINING_MODE" == "solo" ]]; then
        printf "\n${FG_YELLOW}${BOLD}  ⏭ Tari est désactivé en mode SOLO (nécessite P2Pool).${RESET}\n"
      else
        printf "\n${FG_YELLOW}${BOLD}  ⏭ Le merge mining Tari n'est pas activé (aucune adresse configurée).${RESET}\n"
      fi
    else

      status="inactive"
      icon="✖"
      color=$FG_RED
      tari_msg="${FG_WHITE}Service Minotari arrêté.${RESET}"

      if systemctl is-active --quiet minotari_node; then

        if tari_progress=$(grpcurl -plaintext -max-time 1 -import-path /usr/local/share/tari/proto -proto base_node.proto 127.0.0.1:${TARI_GRPC_PORT} tari.rpc.BaseNode/GetSyncProgress 2>/dev/null); then

          tari_peers_json=$(grpcurl -plaintext -max-time 1 -import-path /usr/local/share/tari/proto -proto base_node.proto 127.0.0.1:${TARI_GRPC_PORT} tari.rpc.BaseNode/ListConnectedPeers 2>/dev/null || echo "{}")
          tari_peers=$(echo "$tari_peers_json" | jq '.connectedPeers | length // 0')

          current_h=$(echo "$tari_progress" | jq -r '.localHeight // 0')
          target_h=$(echo "$tari_progress" | jq -r '.tipHeight // 0')
          state=$(echo "$tari_progress" | jq -r '.state // "UNKNOWN"')

          ((target_h == 0)) && target_h=$current_h

          if [[ "$state" == "DONE" ]] || [[ "$state" == "Listening" ]] || [[ "$state" == "ListeningCurrent" ]]; then
            icon="✔"
            color=$FG_GREEN
            status="ok"
            tari_msg="${FG_WHITE}Synchronisé ${BG_WHITE}${FG_BLACK} (Hauteur: ${current_h}/${target_h} | Peers: ${tari_peers}) ${RESET}"
          else
            icon="⧖"
            color=$FG_YELLOW
            status="warning"
            if ((target_h > 0)); then
              pct=$(awk "BEGIN{printf \"%.1f\", ($current_h/$target_h)*100}")
            else
              pct="0.0"
            fi
            tari_msg="${FG_WHITE}Synchro ${pct}% ${BG_WHITE}${FG_BLACK} (Hauteur: ${current_h}/${target_h} | Peers: ${tari_peers}) ${RESET}"
          fi

        else

          if timeout 0.5 bash -c "echo > /dev/tcp/127.0.0.1/${TARI_GRPC_PORT}" 2>/dev/null; then
            icon="⧖"
            color=$FG_YELLOW
            status="warning"
            tari_msg="${FG_WHITE}Le nœud Tari démarre (API gRPC non prête).${RESET}"
          else
            icon="⚠"
            color=$FG_RED
            status="error"
            tari_msg="${FG_WHITE}Le nœud Tari ne répond pas (Port fermé).${RESET}"
          fi
        fi
      fi

      describe_component "minotari" "Tari" "$INSTALLED_TARI" "$TARI_VERSION" "minotari_node.service"

      printf "  %b%s %b\n" "$color" "$icon" "$tari_msg"

      mm_file="$WORKER_HOME/p2pool-stats/local/merge_mining"
      if [[ -f "$mm_file" ]]; then
        mm_state=$(jq -r '.chains[0].channel_state // "UNKNOWN"' "$mm_file" 2>/dev/null)
        mm_algo=$(jq -r '.chains[0].api // "UNKNOWN"' "$mm_file" 2>/dev/null)
        mm_diff=$(jq -r '.chains[0].difficulty // 0' "$mm_file" 2>/dev/null)
        mm_height=$(jq -r '.chains[0].height // 0' "$mm_file" 2>/dev/null)

        if [[ "$mm_state" == "READY" ]]; then
          printf "  ${FG_GREEN}✔${RESET} Merge Mining : ACTIF (%s) | P2Pool Height: ${BG_WHITE}${FG_BLACK} %s ${RESET}\n" "$mm_algo" "$mm_height"
        else
          printf "  ${FG_RED}✖${RESET} Merge Mining : ERREUR (État: %s) - Vérifier logs\n" "$mm_state"
        fi
      else
        if systemctl is-active --quiet p2pool; then
          printf "  ${FG_YELLOW}⧖${RESET} Merge Mining : En attente de P2Pool...\n"
        fi
      fi

      printf "  ${FG_GREEN}✔${RESET} Pour consulter les logs : $ sudo journalctl -u minotari_node -f\n"

    fi

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # P2Pool ────────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}⛓️  Pool P2Pool${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    if [[ "$MINING_MODE" != "pool-nano" && "$MINING_MODE" != "pool-mini" && "$MINING_MODE" != "pool-full" ]]; then
      printf "\n${FG_YELLOW}${BOLD}  ⏭ Le pool P2Pool n'est pas utile en mode %s.${RESET}\n" "$mining_label"
    else

      if [[ "$MINING_MODE" == "pool-nano" ]]; then
        POOL_DOMAIN="nano.p2pool.observer"
      elif [[ "$MINING_MODE" == "pool-mini" ]]; then
        POOL_DOMAIN="mini.p2pool.observer"
      else POOL_DOMAIN="p2pool.observer"; fi

      ADDR_START="${MONERO_ADDRESS:0:3}"
      ADDR_END="${MONERO_ADDRESS: -2}"
      POOL_URL="https://$POOL_DOMAIN/miner/$MONERO_ADDRESS"
      VISIBLE_LINK="https://$POOL_DOMAIN/miner/${ADDR_START}…${ADDR_END}"

      printf "  ${FG_GREEN}✔${RESET} Lien du pool : \e]8;;%s\e\\%s\e]8;;\e\\ \n" "$POOL_URL" "$VISIBLE_LINK"

      xvb_status=$(check_xmrvsbeast "$MONERO_ADDRESS")
      if [[ "$xvb_status" == "registered" ]]; then
        printf "  ${FG_GREEN}✔${RESET} XMRvsBEAST : inscrit (raffle active)\n"
      else
        printf "  ${FG_YELLOW}⚠${RESET} XMRvsBEAST : non inscrit → https://xmrvsbeast.com/p2pool/\n"
      fi

      describe_component "p2pool" "P2Pool" "$INSTALLED_P2POOL" "$P2POOL_VERSION" "p2pool"

      if systemctl is-active --quiet p2pool; then
        stats_file="$WORKER_HOME/p2pool-stats/local/stratum"

        if [[ -f "$stats_file" ]]; then
          p2pool_stats=$(cat "$stats_file" 2>/dev/null || echo "")

          if [[ -n "$p2pool_stats" ]]; then
            p2pool_hr=$(echo "$p2pool_stats" | jq -r '.hashrate_15m // 0' 2>/dev/null || echo "0")

            if (($(awk -v h="$p2pool_hr" 'BEGIN{print (h > 0)}'))); then
              printf "  ${FG_GREEN}✔${RESET} P2Pool Hashrate (15m) : ${BG_WHITE}${FG_BLACK} %s H/s (Sidechain) ${RESET}\n" "$p2pool_hr"
            else
              printf "  ${FG_YELLOW}⧖${RESET} P2Pool Hashrate (15m) : %s H/s (Démarrage...)\n" "$p2pool_hr"
            fi
          else
            printf "  ${FG_YELLOW}⧖${RESET} P2Pool Hashrate (15m) : 0 H/s (Démarrage...)\n"
          fi
        else
          printf "  ${FG_YELLOW}⧖${RESET} P2Pool Hashrate (15m) : 0 H/s (Initialisation fichiers...)\n"
        fi
      fi

      printf "  ${FG_GREEN}✔${RESET} Pour consulter les logs : $ sudo journalctl -u p2pool -f\n"

    fi

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # XMRig ─────────────────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}⛏️  Mineur XMRig${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    describe_component "xmrig" "XMRig" "$INSTALLED_XMRIG" "$XMRIG_VERSION" "xmrig"

    if (($(awk -v h="$speed10" 'BEGIN{print (h > 0)}'))); then
      printf "  ${FG_GREEN}✔${RESET} Hashrate (10s) actuel : ${BG_WHITE}${FG_BLACK} ${speed10} H/s ${RESET}\n"
    else
      printf "  ${FG_YELLOW}⧖${RESET} Hashrate (10s) actuel : ${speed10} H/s (Démarrage...)\n"
    fi

    printf "  ${FG_GREEN}✔${RESET} Pour consulter les logs : $ sudo journalctl -u xmrig -f\n"

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Ports et de leur état ─────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}🌐  Analyse réseau${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    # Détection des ports en écoute
    ss_out=$(ss -tunlp)

    # Détection des règles UFW
    ufw_out=$(ufw status)

    # Liste des ports à vérifier
    declare -a port_infos=(
      "18080 Monero (RPC public)"
      "18081 Monero (API locale)"
      "18083 Monero (ZMQ live data)"
    )

    # Ajout du port Stratum si défini
    if [[ -n "$STRATUM_PORT" ]]; then
      port_infos+=("$STRATUM_PORT Mineur (Stratum local)")
    fi

    # Ports P2Pool (toujours listés)
    port_infos+=(
      "37890 P2Pool nano (reseau)"
      "37888 P2Pool mini (reseau)"
      "37889 P2Pool full (reseau)"
    )

    has_unknown=false
    config_ok=true

    for info in "${port_infos[@]}"; do
      port="${info%% *}"

      # État écoute ?
      if grep -qE ":$port\\>" <<<"$ss_out"; then
        listening=true
      else
        listening=false
      fi

      # État UFW
      if grep -qE "\\b$port\\b/tcp\\b" <<<"$ufw_out"; then
        if grep -E "\\b$port/tcp\\b.*ALLOW" <<<"$ufw_out" >/dev/null; then
          fw="autorisé"
        elif grep -E "\\b$port/tcp\\b.*DENY" <<<"$ufw_out" >/dev/null; then
          fw="bloqué"
        else
          fw="inconnu"
          has_unknown=true
        fi
      else
        fw="inconnu"
        has_unknown=true
      fi

      # Déterminer si le port doit être à l'écoute
      expected_open=false
      case "$MINING_MODE" in
        solo)
          [[ "$port" == "18081" || "$port" == "18083" || "$port" == "$STRATUM_PORT" ]] && expected_open=true
          ;;
        pool-nano)
          [[ "$port" == "18081" || "$port" == "18083" || "$port" == "$STRATUM_PORT" || "$port" == "37890" ]] && expected_open=true
          ;;
        pool-mini)
          [[ "$port" == "18081" || "$port" == "18083" || "$port" == "$STRATUM_PORT" || "$port" == "37888" ]] && expected_open=true
          ;;
        pool-full)
          [[ "$port" == "18081" || "$port" == "18083" || "$port" == "$STRATUM_PORT" || "$port" == "37889" ]] && expected_open=true
          ;;
        moneroocean)
          expected_open=false
          ;;
      esac

      if [[ "$listening" != "$expected_open" ]]; then
        config_ok=false
      fi
    done

    # Résultat final
    if [[ "$config_ok" == true && "$has_unknown" == false ]]; then
      printf "  ${FG_GREEN}✔${RESET} ${FG_WHITE}La configuration réseau est conforme au modèle attendu.${RESET}\n"
    else
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}La configuration réseau n'est pas conforme au modèle attendu.${RESET}\n"
    fi

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Analyse système ───────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}🧠  Analyse système${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    # Optimisations mémoire : HugePages & THP
    HP_TOTAL=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
    HP_TOTAL=${HP_TOTAL:-0}
    HUGEPAGE_1G=$(mount | grep -q '/mnt/hugepages_1gb' && echo "1GiB✅" || echo "1GiB❌")
    THP_STATE=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
    [[ "$THP_STATE" == "never" ]] && THP="THP🚫" || THP="THP:$THP_STATE"

    # Évaluation et message final stylé
    if [[ "$HUGEPAGE_1G" == "1GiB✅" && "$THP" == "THP🚫" ]]; then
      printf "  ${FG_GREEN}✔${RESET} ${FG_WHITE}La configuration est optimisée pour un minage efficace.${RESET}\n"
    else
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}La configuration n’est pas entièrement optimisée pour le minage.${RESET}\n"
    fi

    # Vérification système : Connexion, Disque, RAM, CPU
    INTERNET_OK=$(ping -q -c1 1.1.1.1 &>/dev/null && echo 1 || echo 0)

    # Nettoyage des valeurs numériques et fallback
    DISK_USED=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    RAM_USED=$(free | awk '/Mem:/ { if ($2 > 0) printf("%d", $3/$2 * 100); else print 0 }')
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print int(100 - $8)}')

    DISK_USED=${DISK_USED:-0}
    RAM_USED=${RAM_USED:-0}
    CPU_LOAD=${CPU_LOAD:-0}

    # Déduire le mode CPU à partir du profil XMRig
    if [[ "$XMRIG_MODE" == "eco" ]]; then
      CPU_MODE="eco"
    else
      CPU_MODE="perf"
    fi

    # Seuils selon mode
    if [[ "$CPU_MODE" == "eco" ]]; then
      CPU_CRIT=25
      CPU_WARN=40
    else
      CPU_CRIT=50
      CPU_WARN=90
    fi

    # Évaluation & affichage stylé
    if [[ "$INTERNET_OK" -eq 0 ]]; then
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}Problème: pas de connexion Internet${RESET}\n"
    elif [[ "$DISK_USED" -ge 95 ]]; then
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}Problème: disque critique (${DISK_USED}%%)${RESET}\n"
    elif [[ "$RAM_USED" -ge 95 ]]; then
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}Problème: ram critique (${RAM_USED}%%)${RESET}\n"
    elif [[ "$CPU_LOAD" -lt "$CPU_CRIT" ]]; then
      printf "  ${FG_RED}✖${RESET} ${FG_WHITE}Problème: CPU trop bas (${CPU_LOAD}%%) en mode $CPU_MODE${RESET}\n"
    elif [[ "$DISK_USED" -ge 90 ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} ${FG_WHITE}Attention: disque élevé (${DISK_USED}%%), ram ${RAM_USED}%%, cpu ${CPU_LOAD}%%${RESET}\n"
    elif [[ "$RAM_USED" -ge 90 ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} ${FG_WHITE}Attention: ram élevée (${RAM_USED}%%), disque ${DISK_USED}%%, cpu ${CPU_LOAD}%%${RESET}\n"
    elif [[ "$CPU_LOAD" -lt "$CPU_WARN" ]]; then
      printf "  ${FG_YELLOW}⚠${RESET} ${FG_WHITE}Attention: CPU faible (${CPU_LOAD}%%) en mode $CPU_MODE${RESET}\n"
    else
      printf "  ${FG_GREEN}✔${RESET} ${FG_WHITE}Connecté, ressources OK (disk ${DISK_USED}%%, ram ${RAM_USED}%%, cpu ${CPU_LOAD}%%)${RESET}\n"
    fi

    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    # Raccourcis clavier ────────────────────────────────────────────────────────────────────────────────────── #
    # ///////////////////////////////////////////////////////////////////////////////////////////////////////// #
    printf "\n${FG_CYAN}${BOLD}⌨️  Raccourcis clavier${RESET}\n"
    printf "${FG_WHITE}${BOLD}"
    printf '─%.0s' {1..84}
    printf "${RESET}\n"

    btn_support=""
    if [[ "$TARI_ADDRESS" == "$DEV_TARI_WALLET" ]] || [[ "$MONERO_ADDRESS" == "$DEV_XMR_WALLET" ]]; then
      btn_support="${BG_MAGENTA}${FG_WHITE}${BOLD}[D] : soutenir le projet (ACTIF)${RESET}"
    else
      btn_support="${BOLD}[D]${RESET} : soutenir le projet"
    fi

    printf "  ${BOLD}[E]${RESET} : quitter / arrêter   │ ${BOLD}[S]${RESET} : paramètres\n"
    printf "  ${BOLD}[U]${RESET} : mettre à jour       │ ${BOLD}[X]${RESET} : détruire le stack\n"
    printf "  ${BOLD}[L]${RESET} : logs                │ %b\n" "$btn_support"
    printf "\n"

  fi

  # Compte à rebours dynamique avec détection des touches
  for ((i = REFRESH_INTERVAL; i >= 0; i--)); do
    printf "\r\e[3m🕒 Prochaine actualisation dans %2ds...\e[0m" "$i"
    sleep 1

    # Interception clavier pendant le compte à rebours
    if IFS= read -rsn1 -t 0.01 key 2>/dev/null; then
      case "$key" in
        e)
          prompt_quit_menu
          REFRESH_IMMEDIATE=true
          break
          ;;
        u)
          force_update
          REFRESH_IMMEDIATE=true
          break
          ;;
        x)
          cleanup_stack
          REFRESH_IMMEDIATE=true
          break
          ;;
        s)
          edit_initial_config
          REFRESH_IMMEDIATE=true
          break
          ;;
        l)
          show_logs
          REFRESH_IMMEDIATE=true
          break
          ;;
        d)
          support_project
          REFRESH_IMMEDIATE=true
          break
          ;;
      esac
    fi
  done
  printf "\r\033[K"
done
