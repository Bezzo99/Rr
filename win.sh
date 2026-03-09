#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
NC='\033[0m'

APP_DIR="/root/novan-store"
STORAGE_DIR="$APP_DIR/windows"
COMPOSE_FILE="$APP_DIR/compose.yml"
IMAGE_NAME="${IMAGE_NAME:-bezzo99/rr}"
CONTAINER_NAME="novan-store-rdp"
LOG_FILE="/tmp/novan-store-install.log"
FORCE_NO_KVM="${FORCE_NO_KVM:-0}"

trap 'echo; echo -e "${RED}[!] Gagal di baris $LINENO. Cek log: $LOG_FILE${NC}"; exit 1' ERR
exec > >(tee -a "$LOG_FILE") 2>&1

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
  local percent="${1:-0}"
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

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}[!] Jalankan script ini sebagai root.${NC}"
    exit 1
  fi
}

require_supported_os() {
  if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}[!] /etc/os-release tidak ditemukan. OS tidak didukung.${NC}"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  DIST_ID="${ID:-}"
  DIST_CODENAME="${VERSION_CODENAME:-}"

  case "$DIST_ID" in
    ubuntu|debian) ;;
    *)
      echo -e "${RED}[!] Script ini hanya mendukung Ubuntu/Debian. Terdeteksi: ${DIST_ID:-unknown}.${NC}"
      exit 1
      ;;
  esac

  if [[ -z "$DIST_CODENAME" ]]; then
    echo -e "${RED}[!] VERSION_CODENAME tidak ditemukan pada OS ini.${NC}"
    exit 1
  fi
}

ensure_base_packages() {
  echo -e "${YELLOW}[*] Menyiapkan dependency dasar...${NC}"
  show_progress 5
  apt-get update -y >/dev/null 2>&1
  show_progress 15
  apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common >/dev/null 2>&1
  finish_progress
}

install_docker_repo() {
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg

  curl -fsSL "https://download.docker.com/linux/${DIST_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DIST_ID} ${DIST_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
}

start_enable_docker() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  else
    service docker start >/dev/null 2>&1 || true
  fi
}

install_requirements() {
  echo -e "${YELLOW}[*] Mengecek dependency...${NC}"
  show_progress 5
  ensure_base_packages

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Docker belum ada, menginstall Docker...${NC}"
    show_progress 20
    install_docker_repo
    show_progress 45
    apt-get update -y >/dev/null 2>&1
    show_progress 70
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
    show_progress 90
    start_enable_docker
  else
    show_progress 70
    if ! docker compose version >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1
      apt-get install -y docker-compose-plugin >/dev/null 2>&1 || apt-get install -y docker-compose >/dev/null 2>&1
    fi
    show_progress 90
    start_enable_docker
  fi

  if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[!] Docker terinstall tapi daemon belum aktif.${NC}"
    exit 1
  fi

  finish_progress
  echo -e "${GREEN}[✓] Dependency siap.${NC}"
  echo
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo -e "${RED}[!] Docker Compose tidak tersedia.${NC}"
    exit 1
  fi
}

check_virtualization() {
  local cpuvirt=0
  if grep -Eq '(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
    cpuvirt=1
  fi

  if [[ ! -e /dev/kvm ]]; then
    echo -e "${RED}[!] /dev/kvm tidak ditemukan.${NC}"
    if [[ "$FORCE_NO_KVM" == "1" ]]; then
      echo -e "${YELLOW}[!] FORCE_NO_KVM=1 aktif, script tetap dilanjutkan.${NC}"
    else
      echo -e "${RED}[!] VPS ini tidak cocok untuk image Windows berbasis KVM.${NC}"
      echo -e "${YELLOW}[!] Gunakan VPS yang support nested virtualization / KVM, atau jalankan dengan FORCE_NO_KVM=1 bila ingin tetap coba.${NC}"
      exit 1
    fi
  fi

  if [[ "$cpuvirt" -eq 0 ]]; then
    echo -e "${YELLOW}[!] Flag virtualisasi CPU (vmx/svm) tidak terdeteksi.${NC}"
  fi

  mkdir -p /dev/net
  if [[ ! -c /dev/net/tun ]]; then
    mknod /dev/net/tun c 10 200 >/dev/null 2>&1 || true
    chmod 666 /dev/net/tun >/dev/null 2>&1 || true
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
  echo -e "${WHITE}|  7 | Windows 8.1 Enterprise  |${NC}"
  echo -e "${WHITE}|  8 | Windows 7 Enterprise    |${NC}"
  echo -e "${WHITE}|  9 | Windows Vista Ultimate  |${NC}"
  echo -e "${WHITE}| 10 | Windows XP Professional |${NC}"
  echo -e "${WHITE}| 11 | Windows Server 2022     |${NC}"
  echo -e "${WHITE}| 12 | Windows Server 2019     |${NC}"
  echo -e "${WHITE}| 13 | Windows Server 2016     |${NC}"
  echo -e "${WHITE}| 14 | Windows Server 2012     |${NC}"
  echo -e "${WHITE}| 15 | Windows Server 2008     |${NC}"
  echo -e "${CYAN}+----+-------------------------+${NC}"
  echo
}

pick_version() {
  CHOICE="${CHOICE:-}"
  if [[ -z "$CHOICE" ]]; then
    read -rp "Pilih versi Windows [1-15]: " CHOICE
  fi

  case "$CHOICE" in
    1) VERSION="11" ;;
    2) VERSION="11e" ;;
    3) VERSION="10" ;;
    4) VERSION="10l" ;;
    5) VERSION="10e" ;;
    6) VERSION="8.1" ;;
    7) VERSION="8.1e" ;;
    8) VERSION="7e" ;;
    9) VERSION="vista" ;;
    10) VERSION="xp" ;;
    11) VERSION="2022" ;;
    12) VERSION="2019" ;;
    13) VERSION="2016" ;;
    14) VERSION="2012" ;;
    15) VERSION="2008" ;;
    *) echo -e "${RED}[!] Pilihan tidak valid.${NC}"; exit 1 ;;
  esac
}

validate_size() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+([GgMm])$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

validate_cores() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

ask_config() {
  echo

  read -rp "Docker Image [default bezzo99/rr]: " IMAGE_NAME_INPUT
  IMAGE_NAME="${IMAGE_NAME_INPUT:-${IMAGE_NAME:-bezzo99/rr}}"

  read -rp "RAM Windows [default 4G]: " RAM_SIZE_INPUT
  RAM_SIZE="$(validate_size "${RAM_SIZE_INPUT:-${RAM_SIZE:-4G}}" "4G")"

  read -rp "CPU Core [default 2]: " CPU_CORES_INPUT
  CPU_CORES="$(validate_cores "${CPU_CORES_INPUT:-${CPU_CORES:-2}}" "2")"

  read -rp "Disk Size [default 64G]: " DISK_SIZE_INPUT
  DISK_SIZE="$(validate_size "${DISK_SIZE_INPUT:-${DISK_SIZE:-64G}}" "64G")"

  read -rp "RDP Username [default Docker]: " USERNAME_INPUT
  USERNAME="${USERNAME_INPUT:-${USERNAME:-Docker}}"

  read -rp "RDP Password [default admin123]: " PASSWORD_INPUT
  PASSWORD="${PASSWORD_INPUT:-${PASSWORD:-admin123}}"

  if [[ ${#PASSWORD} -lt 6 ]]; then
    echo -e "${RED}[!] Password minimal 6 karakter.${NC}"
    exit 1
  fi
}

make_compose() {
  mkdir -p "$STORAGE_DIR"
  cd "$APP_DIR"

  cat > "$COMPOSE_FILE" <<EOF
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
EOF

  if [[ -e /dev/kvm ]]; then
    sed -i '/devices:/a\      - /dev/kvm' "$COMPOSE_FILE"
  fi
}

verify_image() {
  echo -e "${YELLOW}[*] Mengecek image Docker...${NC}"
  docker manifest inspect "$IMAGE_NAME" >/dev/null 2>&1 || {
    echo -e "${RED}[!] Image Docker ${IMAGE_NAME} tidak ditemukan / tidak bisa diakses.${NC}"
    exit 1
  }
}

run_container() {
  cd "$APP_DIR"

  echo
  echo -e "${YELLOW}[*] Menjalankan container Windows...${NC}"

  show_progress 20
  compose_cmd down >/dev/null 2>&1 || true

  show_progress 45
  compose_cmd pull >/dev/null

  show_progress 75
  compose_cmd up -d >/dev/null

  show_progress 90
  sleep 5
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo -e "${RED}[!] Container gagal berjalan.${NC}"
    docker ps -a || true
    docker logs "$CONTAINER_NAME" --tail 100 || true
    exit 1
  fi

  finish_progress
}

get_ip_addr() {
  local ip=""
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -z "$ip" ]]; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1)"
  fi
  printf '%s' "$ip"
}

show_result() {
  local ip_addr
  ip_addr="$(get_ip_addr)"

  echo
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${GREEN}              INSTALL SELESAI${NC}"
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${WHITE}IP VPS     : ${YELLOW}${ip_addr:-tidak terdeteksi}${NC}"
  echo -e "${WHITE}Web Viewer : ${YELLOW}http://${ip_addr:-IP-VPS}:8006${NC}"
  echo -e "${WHITE}RDP Host   : ${YELLOW}${ip_addr:-IP-VPS}:3389${NC}"
  echo -e "${WHITE}Username   : ${YELLOW}${USERNAME}${NC}"
  echo -e "${WHITE}Password   : ${YELLOW}${PASSWORD}${NC}"
  echo -e "${WHITE}Folder     : ${YELLOW}${APP_DIR}${NC}"
  echo -e "${WHITE}Log File   : ${YELLOW}${LOG_FILE}${NC}"
  echo -e "${GREEN}===========================================${NC}"
}

main() {
  require_root
  require_supported_os
  show_banner
  install_requirements
  check_virtualization
  show_menu
  pick_version
  ask_config
  verify_image
  make_compose
  run_container
  show_result
}

main "$@"

