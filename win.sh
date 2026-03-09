#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
NC='\033[0m'
APP_DIR='/root/novan-store'
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
CONTAINER_NAME='novan-store-rdp'
IMAGE_NAME='dockurr/windows'
LOG_FILE='/tmp/novan-store-install.log'

show_banner() {
  clear || true
  echo -e "${GREEN}"
  cat << 'BANNER'
███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗
████╗  ██║██╔═══██╗██║   ██║██╔══██╗████╗  ██║
██╔██╗ ██║██║   ██║██║   ██║███████║██╔██╗ ██║
██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║██║╚██╗██║
██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║██║ ╚████║
╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═══╝

███████╗████████╗ ██████╗ ██████╗ ███████╗
██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝
███████╗   ██║   ██║   ██║██████╔╝█████╗
╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝
███████║   ██║   ╚██████╔╝██║  ██║███████╗
╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝
BANNER
  echo -e "${NC}"
  echo -e "${CYAN}===========================================${NC}"
  echo -e "${WHITE}       AUTO INSTALLER RDP - NOVAN STORE${NC}"
  echo -e "${CYAN}===========================================${NC}"
  echo
}

show_progress() {
  local percent=${1:-0}
  local width=30
  local filled=$((percent * width / 100))
  local empty=$((width - filled))

  printf "\r${YELLOW}Setup process:${NC} ["
  printf "%${filled}s" "" | tr ' ' '#'
  printf "%${empty}s" "" | tr ' ' '.'
  printf "] ${GREEN}%d%%%b" "$percent" "${NC}"
}

finish_progress() {
  show_progress 100
  echo
}

log() {
  echo -e "$*" | tee -a "$LOG_FILE"
}

run_quiet() {
  "$@" >>"$LOG_FILE" 2>&1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "${RED}[!] Jalankan script ini sebagai root.${NC}"
    exit 1
  fi
}

ensure_supported_os() {
  if [ ! -f /etc/os-release ]; then
    log "${RED}[!] OS tidak dikenali.${NC}"
    exit 1
  fi

  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *)
      log "${RED}[!] Script ini hanya mendukung Ubuntu/Debian.${NC}"
      exit 1
      ;;
  esac
}

set_dynamic_defaults() {
  local mem_gb cpu_cores disk_gb

  mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 6)
  cpu_cores=$(nproc 2>/dev/null || echo 4)
  disk_gb=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}' 2>/dev/null || echo 80)

  if [ -z "$mem_gb" ] || [ "$mem_gb" -lt 4 ]; then
    DEFAULT_RAM='4G'
  elif [ "$mem_gb" -le 6 ]; then
    DEFAULT_RAM="$((mem_gb - 1))G"
  elif [ "$mem_gb" -le 8 ]; then
    DEFAULT_RAM='6G'
  else
    DEFAULT_RAM="$((mem_gb - 2))G"
  fi

  if [ -z "$cpu_cores" ] || [ "$cpu_cores" -lt 2 ]; then
    DEFAULT_CPU='2'
  elif [ "$cpu_cores" -gt 8 ]; then
    DEFAULT_CPU='8'
  else
    DEFAULT_CPU="$cpu_cores"
  fi

  if [ -z "$disk_gb" ] || [ "$disk_gb" -lt 90 ]; then
    DEFAULT_DISK='80G'
  else
    local suggested=$((disk_gb - 20))
    if [ "$suggested" -lt 80 ]; then
      suggested=80
    fi
    DEFAULT_DISK="${suggested}G"
  fi
}

install_requirements() {
  log "${YELLOW}[*] Mengecek dependency...${NC}"
  show_progress 5

  run_quiet apt-get update -y
  run_quiet apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common

  if ! command -v docker >/dev/null 2>&1; then
    log "${YELLOW}[*] Docker belum ada, menginstall Docker...${NC}"
    show_progress 20
    install -m 0755 -d /etc/apt/keyrings

    show_progress 35
    rm -f /etc/apt/keyrings/docker.gpg
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >>"$LOG_FILE" 2>&1
    chmod a+r /etc/apt/keyrings/docker.gpg

    show_progress 50
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

    show_progress 65
    run_quiet apt-get update -y
    run_quiet apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif ! docker compose version >/dev/null 2>&1; then
    show_progress 65
    run_quiet apt-get install -y docker-compose-plugin
  fi

  show_progress 85
  run_quiet systemctl enable docker
  run_quiet systemctl restart docker

  finish_progress
  log "${GREEN}[✓] Dependency siap.${NC}"
  echo
}

check_virtualization() {
  if [ ! -e /dev/net/tun ]; then
    mkdir -p /dev/net || true
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 666 /dev/net/tun 2>/dev/null || true
  fi

  if [ ! -e /dev/kvm ]; then
    log "${RED}[!] /dev/kvm tidak ditemukan.${NC}"
    log "${YELLOW}[!] VPS Anda tidak support KVM / nested virtualization.${NC}"
    log "${YELLOW}[!] Container Windows kemungkinan besar gagal boot.${NC}"
    exit 1
  fi
}

show_menu() {
  echo -e "${CYAN}+----+-------------------------+${NC}"
  echo -e "${CYAN}| No | Version                 |${NC}"
  echo -e "${CYAN}+----+-------------------------+${NC}"
  echo -e "${WHITE}|  1 | Windows 11 Pro          |${NC}"
  echo -e "${WHITE}|  2 | Windows 11 Enterprise   |${NC}"
  echo -e "${WHITE}|  3 | Windows 10 Pro          |${NC}"
  echo -e "${WHITE}|  4 | Windows 10 LTSC         |${NC}"
  echo -e "${WHITE}|  5 | Windows 10 Enterprise   |${NC}"
  echo -e "${WHITE}|  6 | Windows 8.1 Pro         |${NC}"
  echo -e "${WHITE}|  7 | Windows 7 Ultimate      |${NC}"
  echo -e "${WHITE}|  8 | Windows Vista Ultimate  |${NC}"
  echo -e "${WHITE}|  9 | Windows XP Professional |${NC}"
  echo -e "${WHITE}| 10 | Windows Server 2025     |${NC}"
  echo -e "${WHITE}| 11 | Windows Server 2022     |${NC}"
  echo -e "${WHITE}| 12 | Windows Server 2019     |${NC}"
  echo -e "${CYAN}+----+-------------------------+${NC}"
  echo
}

pick_version() {
  read -rp "Pilih versi Windows [1-12]: " CHOICE
  case "$CHOICE" in
    1) VERSION='11' ; VERSION_LABEL='Windows 11 Pro' ;;
    2) VERSION='11e' ; VERSION_LABEL='Windows 11 Enterprise' ;;
    3) VERSION='10' ; VERSION_LABEL='Windows 10 Pro' ;;
    4) VERSION='10l' ; VERSION_LABEL='Windows 10 LTSC' ;;
    5) VERSION='10e' ; VERSION_LABEL='Windows 10 Enterprise' ;;
    6) VERSION='8e' ; VERSION_LABEL='Windows 8.1 Pro' ;;
    7) VERSION='7u' ; VERSION_LABEL='Windows 7 Ultimate' ;;
    8) VERSION='vu' ; VERSION_LABEL='Windows Vista Ultimate' ;;
    9) VERSION='xp' ; VERSION_LABEL='Windows XP Professional' ;;
    10) VERSION='2025' ; VERSION_LABEL='Windows Server 2025' ;;
    11) VERSION='2022' ; VERSION_LABEL='Windows Server 2022' ;;
    12) VERSION='2019' ; VERSION_LABEL='Windows Server 2019' ;;
    *) log "${RED}[!] Pilihan tidak valid.${NC}"; exit 1 ;;
  esac
}

ask_config() {
  echo
  echo -e "${CYAN}Default disesuaikan dari spek VPS. Anda boleh ganti, misalnya 160G.${NC}"

  read -rp "RAM Windows [default ${DEFAULT_RAM}]: " RAM_SIZE
  RAM_SIZE="${RAM_SIZE:-$DEFAULT_RAM}"

  read -rp "CPU Core [default ${DEFAULT_CPU}]: " CPU_CORES
  CPU_CORES="${CPU_CORES:-$DEFAULT_CPU}"

  read -rp "Disk Size [default ${DEFAULT_DISK}]: " DISK_SIZE
  DISK_SIZE="${DISK_SIZE:-$DEFAULT_DISK}"

  read -rp "RDP Username [default novan]: " USERNAME
  USERNAME="${USERNAME:-novan}"

  read -rp "RDP Password [default novan22]: " PASSWORD
  PASSWORD="${PASSWORD:-novan22}"
}

normalize_sizes() {
  RAM_SIZE=$(echo "$RAM_SIZE" | tr '[:lower:]' '[:upper:]')
  DISK_SIZE=$(echo "$DISK_SIZE" | tr '[:lower:]' '[:upper:]')
}

validate_config() {
  normalize_sizes

  [[ "$RAM_SIZE" =~ ^[0-9]+[GM]$ ]] || { log "${RED}[!] Format RAM harus seperti 4G atau 8192M.${NC}"; exit 1; }
  [[ "$CPU_CORES" =~ ^[0-9]+$ ]] || { log "${RED}[!] CPU Core harus angka.${NC}"; exit 1; }
  [[ "$DISK_SIZE" =~ ^[0-9]+[GT]$ ]] || { log "${RED}[!] Format Disk harus seperti 80G, 160G, atau 1T.${NC}"; exit 1; }
  [ -n "$USERNAME" ] || { log "${RED}[!] Username tidak boleh kosong.${NC}"; exit 1; }
  [ -n "$PASSWORD" ] || { log "${RED}[!] Password tidak boleh kosong.${NC}"; exit 1; }

  if [ "$CPU_CORES" -lt 1 ]; then
    log "${RED}[!] CPU Core minimal 1.${NC}"
    exit 1
  fi
}

make_compose() {
  mkdir -p "$APP_DIR/windows"
  cd "$APP_DIR"

  cat > "$COMPOSE_FILE" <<EOF2
services:
  windows:
    image: ${IMAGE_NAME}
    container_name: ${CONTAINER_NAME}
    environment:
      VERSION: "${VERSION}"
      RAM_SIZE: "${RAM_SIZE}"
      CPU_CORES: "${CPU_CORES}"
      DISK_SIZE: "${DISK_SIZE}"
      USERNAME: "${USERNAME}"
      PASSWORD: "${PASSWORD}"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./windows:/storage
    restart: unless-stopped
    stop_grace_period: 2m
EOF2
}

run_container() {
  cd "$APP_DIR"
  echo
  log "${YELLOW}[*] Mengecek image Docker...${NC}"
  show_progress 15
  run_quiet docker pull "$IMAGE_NAME"

  echo
  log "${YELLOW}[*] Menjalankan container Windows...${NC}"
  show_progress 35
  docker compose -f "$COMPOSE_FILE" down >>"$LOG_FILE" 2>&1 || true
  show_progress 60
  docker compose -f "$COMPOSE_FILE" up -d >>"$LOG_FILE" 2>&1
  show_progress 90
  sleep 5

  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo
    log "${RED}[!] Container gagal jalan.${NC}"
    log "${YELLOW}[!] Cek log dengan: docker logs ${CONTAINER_NAME}${NC}"
    log "${YELLOW}[!] Log installer: ${LOG_FILE}${NC}"
    exit 1
  fi

  finish_progress
}

show_result() {
  local ip_addr
  ip_addr=$(hostname -I | awk '{print $1}')
  echo
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${GREEN}              INSTALL SELESAI${NC}"
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${WHITE}Versi      : ${YELLOW}${VERSION_LABEL}${NC}"
  echo -e "${WHITE}RAM        : ${YELLOW}${RAM_SIZE}${NC}"
  echo -e "${WHITE}CPU        : ${YELLOW}${CPU_CORES} Core${NC}"
  echo -e "${WHITE}Disk       : ${YELLOW}${DISK_SIZE}${NC}"
  echo -e "${WHITE}IP VPS     : ${YELLOW}${ip_addr}${NC}"
  echo -e "${WHITE}Web Viewer : ${YELLOW}http://${ip_addr}:8006${NC}"
  echo -e "${WHITE}RDP Host   : ${YELLOW}${ip_addr}:3389${NC}"
  echo -e "${WHITE}Username   : ${YELLOW}${USERNAME}${NC}"
  echo -e "${WHITE}Password   : ${YELLOW}${PASSWORD}${NC}"
  echo -e "${WHITE}Folder     : ${YELLOW}${APP_DIR}${NC}"
  echo -e "${WHITE}Log        : ${YELLOW}${LOG_FILE}${NC}"
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${CYAN}Buka dulu Web Viewer sampai Windows selesai boot, lalu baru login via RDP.${NC}"
}

main() {
  : > "$LOG_FILE"
  require_root
  ensure_supported_os
  set_dynamic_defaults
  show_banner
  install_requirements
  check_virtualization
  show_menu
  pick_version
  ask_config
  validate_config
  make_compose
  run_container
  show_result
}

main "$@"
