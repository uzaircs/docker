#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/docker-compose.template.yml"
OUTPUT_FILE="${PROJECT_ROOT}/docker-compose.yml"
DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-abc.com}"
GENERATE_ONLY=0
SKIP_INSTALL=0
CURRENT_STEP=0
TOTAL_STEPS=7
SUDO_CMD=""

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
fi

usage() {
  cat <<EOF
Usage: ./install.sh [--domain example.com] [--generate-only] [--skip-install]

  --domain <name>   Override the default virtual host (default: abc.com)
  --generate-only   Only build docker-compose.yml, do not start containers
  --skip-install    Skip Docker installation checks
EOF
}

banner() {
  printf "\n${C_BOLD}${C_BLUE}===============================================${C_RESET}\n"
  printf "${C_BOLD}${C_BLUE} Docker Setup And Initialization Bootstrapper ${C_RESET}\n"
  printf "${C_BOLD}${C_BLUE}===============================================${C_RESET}\n\n"
}

progress() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "${C_BLUE}[%s/%s]${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

info() {
  printf "   ${C_DIM}>${C_RESET} %s\n" "$1"
}

success() {
  printf "   ${C_GREEN}[OK]${C_RESET} %s\n" "$1"
}

warn() {
  printf "   ${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"
}

fail() {
  printf "\n${C_RED}[FAIL] %s${C_RESET}\n" "$1" >&2
  exit 1
}

on_error() {
  fail "Setup stopped unexpectedly near line $1."
}

trap 'on_error "$LINENO"' ERR

yaml_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

sanitize_name() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "${value:-service}"
}

detect_virtual_port() {
  local dockerfile="$1"
  local port
  port="$(
    awk '
      BEGIN { IGNORECASE = 1 }
      $1 ~ /^EXPOSE$/ {
        value = $2
        sub(/\/.*/, "", value)
        gsub(/[^0-9]/, "", value)
        if (value != "") {
          print value
          exit
        }
      }
    ' "$dockerfile" 2>/dev/null || true
  )"
  printf '%s' "${port:-80}"
}

compose_is_available() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi

  command -v docker-compose >/dev/null 2>&1
}

run_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  docker-compose "$@"
}

ensure_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO_CMD=""
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    fail "Run this script as root or install sudo first."
  fi

  SUDO_CMD="sudo"
}

install_docker() {
  if [[ "${SKIP_INSTALL}" -eq 1 ]]; then
    warn "Skipping Docker installation by request."
    return
  fi

  if [[ "$(uname -s)" != "Linux" ]]; then
    warn "Docker auto-install is intended for Linux hosts. Skipping install on $(uname -s)."
    return
  fi

  if command -v docker >/dev/null 2>&1 && compose_is_available; then
    success "Docker and Compose are already available."
    return
  fi

  ensure_sudo

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
  fi

  local distro="${ID:-unknown}"
  info "Detected Linux distribution: ${distro}"

  case "${distro}" in
    ubuntu|debian)
      ${SUDO_CMD} apt-get update -y
      ${SUDO_CMD} apt-get install -y ca-certificates curl gnupg
      ${SUDO_CMD} install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${distro}/gpg" | ${SUDO_CMD} gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
      ${SUDO_CMD} chmod a+r /etc/apt/keyrings/docker.gpg
      printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
        "$(dpkg --print-architecture)" \
        "${distro}" \
        "${VERSION_CODENAME}" | ${SUDO_CMD} tee /etc/apt/sources.list.d/docker.list >/dev/null
      ${SUDO_CMD} apt-get update -y
      ${SUDO_CMD} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    fedora)
      ${SUDO_CMD} dnf -y install dnf-plugins-core
      ${SUDO_CMD} dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      ${SUDO_CMD} dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    rhel|centos|rocky|almalinux)
      ${SUDO_CMD} yum -y install yum-utils
      ${SUDO_CMD} yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      ${SUDO_CMD} yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    arch)
      ${SUDO_CMD} pacman -Sy --noconfirm docker docker-compose
      ;;
    *)
      warn "Unsupported distro for automatic installation: ${distro}"
      warn "Generate mode will continue, but Docker must be installed manually."
      return
      ;;
  esac

  if command -v systemctl >/dev/null 2>&1; then
    ${SUDO_CMD} systemctl enable --now docker >/dev/null 2>&1 || warn "Docker was installed, but systemd could not start it automatically."
  fi

  if [[ -n "${SUDO_USER:-}" ]] && command -v usermod >/dev/null 2>&1; then
    if ! id -nG "${SUDO_USER}" | grep -qw docker; then
      ${SUDO_CMD} usermod -aG docker "${SUDO_USER}" || warn "Could not add ${SUDO_USER} to the docker group."
      warn "${SUDO_USER} may need to sign out and back in before Docker works without sudo."
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    success "Docker installation completed."
  else
    fail "Docker installation finished without a usable docker binary."
  fi
}

ensure_supporting_directories() {
  mkdir -p \
    "${SCRIPT_DIR}/nginx/certs" \
    "${SCRIPT_DIR}/nginx/vhost.d" \
    "${SCRIPT_DIR}/nginx/html" \
    "${SCRIPT_DIR}/default-site"
  success "Supporting nginx-proxy directories are ready."
}

generate_services_file() {
  local services_file="$1"
  local found_projects=0
  local project_index=0
  local skipped_without_dockerfile=0
  local dir_path=""

  : > "${services_file}"

  while IFS= read -r -d '' dir_path; do
    local dir_name service_name dockerfile_path virtual_host virtual_port
    dir_name="$(basename "${dir_path}")"

    if [[ "${dir_name}" == "$(basename "${SCRIPT_DIR}")" ]]; then
      continue
    fi

    dockerfile_path="${dir_path}/Dockerfile"
    if [[ ! -f "${dockerfile_path}" ]]; then
      skipped_without_dockerfile=$((skipped_without_dockerfile + 1))
      continue
    fi

    project_index=$((project_index + 1))
    found_projects=$((found_projects + 1))
    service_name="$(sanitize_name "${dir_name}")"
    virtual_port="$(detect_virtual_port "${dockerfile_path}")"

    if [[ "${project_index}" -eq 1 ]]; then
      virtual_host="${DEFAULT_DOMAIN}"
    else
      virtual_host="${service_name}.${DEFAULT_DOMAIN}"
    fi

    cat >> "${services_file}" <<EOF
  ${service_name}:
    build:
      context: $(yaml_quote "./${dir_name}")
      dockerfile: Dockerfile
    container_name: ${service_name}-app
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: $(yaml_quote "${virtual_host}")
      VIRTUAL_PORT: $(yaml_quote "${virtual_port}")
    expose:
      - $(yaml_quote "${virtual_port}")
    networks:
      - proxy

EOF

    info "Attached project ${dir_name} -> ${virtual_host} (port ${virtual_port})"
  done < <(find "${PROJECT_ROOT}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 | sort -z)

  if [[ "${found_projects}" -eq 0 ]]; then
    cat >> "${services_file}" <<EOF
  default-site:
    image: nginx:alpine
    container_name: default-site
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: $(yaml_quote "${DEFAULT_DOMAIN}")
      VIRTUAL_PORT: '80'
    volumes:
      - $(yaml_quote "./docker/default-site:/usr/share/nginx/html:ro")
    networks:
      - proxy

EOF
    warn "No Dockerfile-based projects were found. A default landing page will answer for ${DEFAULT_DOMAIN}."
  else
    success "Prepared ${found_projects} app service(s) from ${PROJECT_ROOT}."
  fi

  if [[ "${skipped_without_dockerfile}" -gt 0 ]]; then
    info "Skipped ${skipped_without_dockerfile} directory(s) without a Dockerfile."
  fi
}

render_compose_file() {
  local services_file="$1"
  local temp_file stack_name backup_file

  stack_name="$(sanitize_name "$(basename "${PROJECT_ROOT}")")"
  temp_file="$(mktemp)"

  awk \
    -v stack_name="${stack_name}" \
    -v default_domain="${DEFAULT_DOMAIN}" \
    -v services_file="${services_file}" '
      {
        gsub(/__STACK_NAME__/, stack_name)
        gsub(/__DEFAULT_DOMAIN__/, default_domain)
      }
      /__AUTO_SERVICES__/ {
        while ((getline line < services_file) > 0) {
          print line
        }
        close(services_file)
        next
      }
      { print }
    ' "${TEMPLATE_FILE}" > "${temp_file}"

  if [[ -f "${OUTPUT_FILE}" ]] && cmp -s "${temp_file}" "${OUTPUT_FILE}"; then
    rm -f "${temp_file}"
    success "docker-compose.yml is already up to date."
    return
  fi

  if [[ -f "${OUTPUT_FILE}" ]]; then
    backup_file="${OUTPUT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${OUTPUT_FILE}" "${backup_file}"
    info "Backed up the previous compose file to ${backup_file}"
  fi

  mv "${temp_file}" "${OUTPUT_FILE}"
  success "Wrote ${OUTPUT_FILE}"
}

start_stack() {
  if [[ "${GENERATE_ONLY}" -eq 1 ]]; then
    warn "Generate-only mode enabled. Containers were not started."
    return
  fi

  if ! compose_is_available; then
    warn "Docker Compose is not available yet, so the stack was not started."
    return
  fi

  (
    cd "${PROJECT_ROOT}"
    run_compose up -d --build
  )
  success "Docker stack is up and running."
}

print_summary() {
  printf "\n${C_BOLD}${C_GREEN}Setup complete.${C_RESET}\n"
  printf "   Project root : %s\n" "${PROJECT_ROOT}"
  printf "   Compose file : %s\n" "${OUTPUT_FILE}"
  printf "   Main domain  : %s\n" "${DEFAULT_DOMAIN}"
  printf "   Proxy image  : nginxproxy/nginx-proxy\n\n"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        shift
        [[ $# -gt 0 ]] || fail "Missing value after --domain"
        DEFAULT_DOMAIN="$1"
        ;;
      --generate-only)
        GENERATE_ONLY=1
        ;;
      --skip-install)
        SKIP_INSTALL=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
    shift
  done

  [[ -f "${TEMPLATE_FILE}" ]] || fail "Template file not found at ${TEMPLATE_FILE}"

  banner

  progress "Checking directory layout"
  info "Script directory : ${SCRIPT_DIR}"
  info "Project root     : ${PROJECT_ROOT}"
  info "Compose output   : ${OUTPUT_FILE}"
  success "Parent directory detected successfully."

  progress "Installing Docker when required"
  install_docker

  progress "Preparing nginx-proxy support folders"
  ensure_supporting_directories

  progress "Scanning the parent directory for Docker projects"
  local services_file
  services_file="$(mktemp)"
  generate_services_file "${services_file}"

  progress "Rendering the main docker-compose file"
  render_compose_file "${services_file}"
  rm -f "${services_file}"

  progress "Starting or refreshing the Docker stack"
  start_stack

  progress "Finishing with a quick summary"
  print_summary
}

main "$@"
