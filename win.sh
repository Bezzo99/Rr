#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
NC='\033[0m'

show_banner() {
  clear
  echo -e "${GREEN}"
  cat << "EOF"
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
EOF
  echo -e "${NC}"
  echo -e "${CYAN}===========================================${NC}"
  echo -e "${WHITE}       AUTO INSTALLER RDP - NOVAN STORE${NC}"
  echo -e "${CYAN}===========================================${NC}"
  echo
}

show_progress() {
  local percent=$1
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

run_quiet() {
  "$@" >/dev/null 2>&1
}

install_requirements() {
  echo -e "${YELLOW}[*] Mengecek dependency...${NC}"
  show_progress 5

  if ! command -v curl >/dev/null 2>&1; then
    run_quiet apt-get update -y
    run_quiet apt-get install -y curl
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Docker belum ada, menginstall Docker...${NC}"

    show_progress 10
    run_quiet apt-get update -y

    show_progress 20
    run_quiet apt-get install -y ca-certificates gnupg lsb-release apt-transport-https software-properties-common

    show_progress 35
    install -m 0755 -d /etc/apt/keyrings

    show_progress 45
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1 || true
    chmod a+r /etc/apt/keyrings/docker.gpg

    show_progress 55
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

    show_progress 65
    run_quiet apt-get update -y

    show_progress 80
    run_quiet apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    show_progress 90
    run_quiet systemctl enable docker
    run_quiet systemctl start docker
  else
    show_progress 80
    if ! docker compose version >/dev/null 2>&1; then
      run_quiet apt-get update -y
      run_quiet apt-get install -y docker-compose-plugin
    fi
    show_progress 95
  fi

  finish_progress
  echo -e "${GREEN}[✓] Dependency siap.${NC}"
  echo
}

check_kvm() {
  if [ ! -e /dev/kvm ]; then
    echo -e "${RED}[!] /dev/kvm tidak ditemukan.${NC}"
    echo -e "${YELLOW}[!] VPS kemungkinan tidak support KVM.${NC}"
    echo -e "${YELLOW}[!] Script tetap lanjut, tapi Windows bisa gagal jalan.${NC}"
    echo
    sleep 2
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
  read -rp "Pilih versi Windows [1-15]: " CHOICE

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

ask_config() {
  echo
  read -rp "RAM Windows [default 4G]: " RAM_SIZE
  RAM_SIZE="${RAM_SIZE:-4G}"

  read -rp "CPU Core [default 2]: " CPU_CORES
  CPU_CORES="${CPU_CORES:-2}"

  read -rp "Disk Size [default 64G]: " DISK_SIZE
  DISK_SIZE="${DISK_SIZE:-64G}"

  read -rp "RDP Username [default Docker]: " USERNAME
  USERNAME="${USERNAME:-Docker}"

  read -rp "RDP Password [default admin123]: " PASSWORD
  PASSWORD="${PASSWORD:-admin123}"
}

make_compose() {
  mkdir -p /root/novan-store/windows
  cd /root/novan-store

  cat > compose.yml <<EOF
services:
  windows:
    image: bezzo99/rr
    container_name: novan-store-rdp
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
    restart: always
    stop_grace_period: 2m
EOF
}

run_container() {
  cd /root/novan-store

  echo
  echo -e "${YELLOW}[*] Menjalankan container Windows...${NC}"

  show_progress 20
  docker compose down >/dev/null 2>&1 || true

  show_progress 40
  docker compose pull >/dev/null 2>&1 || true

  show_progress 75
  docker compose up -d >/dev/null 2>&1

  finish_progress
}

show_result() {
  IP_ADDR=$(hostname -I | awk '{print $1}')

  echo
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${GREEN}              INSTALL SELESAI${NC}"
  echo -e "${GREEN}===========================================${NC}"
  echo -e "${WHITE}IP VPS     : ${YELLOW}${IP_ADDR}${NC}"
  echo -e "${WHITE}Web Viewer : ${YELLOW}http://${IP_ADDR}:8006${NC}"
  echo -e "${WHITE}RDP Host   : ${YELLOW}${IP_ADDR}:3389${NC}"
  echo -e "${WHITE}Username   : ${YELLOW}${USERNAME}${NC}"
  echo -e "${WHITE}Password   : ${YELLOW}${PASSWORD}${NC}"
  echo -e "${WHITE}Folder     : ${YELLOW}/root/novan-store${NC}"
  echo -e "${GREEN}===========================================${NC}"
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] Jalankan script ini sebagai root.${NC}"
    exit 1
  fi

  show_banner
  install_requirements
  check_kvm
  show_menu
  pick_version
  ask_config
  make_compose
  run_container
  show_result
}

main
