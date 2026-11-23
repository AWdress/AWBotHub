#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${AWBOTNEST_DIR:-}"
DEPLOY_MODE="${AWBOTNEST_MODE:-}"
WEB_PORT="${AWBOTNEST_PORT:-}"
PLATFORM_PORT="${AWBOTNEST_PLATFORM_PORT:-}"
IMAGE="${AWBOTNEST_IMAGE:-awdress/awbothub:latest}"
COMPOSE_SERVICE="${AWBOTNEST_SERVICE:-}"

info() { printf '\n[AWBotHub] %s\n' "$1"; }
fail() { printf '\n[AWBotHub] 安装失败：%s\n' "$1" >&2; exit 1; }

[[ "${IMAGE}" =~ ^[A-Za-z0-9][A-Za-z0-9._:/@-]*$ ]] || fail "镜像地址格式不正确。"
[[ -z "${COMPOSE_SERVICE}" || "${COMPOSE_SERVICE}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "Compose 服务名格式不正确。"

compose_tmp=""
docker_installer=""
cleanup() {
  [[ -z "${compose_tmp}" ]] || rm -f -- "${compose_tmp}"
  [[ -z "${docker_installer}" ]] || rm -f -- "${docker_installer}"
  return 0
}
trap cleanup EXIT

[[ "$(uname -s)" == "Linux" ]] || fail "一键安装脚本目前只支持 Linux 服务器。"
[[ "${EUID}" -eq 0 ]] || fail "请使用 sudo 运行安装命令。"

normalize_arch() {
  case "${1,,}" in
    x86_64|amd64) printf '%s' 'amd64' ;;
    aarch64|arm64) printf '%s' 'arm64' ;;
    *) fail "不支持的处理器架构：$1。镜像支持 x86_64 和 ARM64，不支持 32 位 ARM。" ;;
  esac
}

HOST_ARCH="$(normalize_arch "$(uname -m)")"
DOCKER_PLATFORM="linux/${HOST_ARCH}"

if [[ -r /dev/tty && -w /dev/tty ]]; then
  if [[ -z "${INSTALL_DIR}" ]]; then
    printf '安装位置 [/opt/AWBotNest]：' >/dev/tty
    IFS= read -r INSTALL_DIR </dev/tty || true
  fi
  if [[ -z "${DEPLOY_MODE}" ]]; then
    printf '网络模式 [bridge/host，默认 bridge]：' >/dev/tty
    IFS= read -r DEPLOY_MODE </dev/tty || true
  fi
  if [[ -z "${WEB_PORT}" && "${DEPLOY_MODE,,}" != "host" ]]; then
    printf '访问端口（bridge 映射端口） [18001]：' >/dev/tty
    IFS= read -r WEB_PORT </dev/tty || true
  fi
  if [[ -z "${PLATFORM_PORT}" ]]; then
    printf '系统监听端口（默认 18001） [18001]：' >/dev/tty
    IFS= read -r PLATFORM_PORT </dev/tty || true
  fi
fi

INSTALL_DIR="${INSTALL_DIR:-/opt/AWBotNest}"
DEPLOY_MODE="${DEPLOY_MODE:-bridge}"
WEB_PORT="${WEB_PORT:-18001}"
PLATFORM_PORT="${PLATFORM_PORT:-18001}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
RUNTIME_OVERRIDE="${INSTALL_DIR}/docker-compose.awbotnest-runtime.yml"

case "${DEPLOY_MODE,,}" in
  bridge|host) DEPLOY_MODE="${DEPLOY_MODE,,}" ;;
  *) fail "网络模式只能是 bridge 或 host。" ;;
esac

validate_port() {
  local name="$1" value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || fail "${name}必须是数字。"
  (( ${#value} <= 5 )) || fail "${name}必须在 1 到 65535 之间。"
  value=$((10#${value}))
  (( value >= 1 && value <= 65535 )) || fail "${name}必须在 1 到 65535 之间。"
  printf '%s' "${value}"
}

WEB_PORT="$(validate_port '访问端口' "${WEB_PORT}")"
PLATFORM_PORT="$(validate_port '系统监听端口' "${PLATFORM_PORT}")"
if [[ "${DEPLOY_MODE}" == "host" ]]; then
  # Host network has no published-port mapping; the app listens directly on
  # the selected platform port on the host.
  WEB_PORT="${PLATFORM_PORT}"
fi
command -v curl >/dev/null 2>&1 || fail "服务器缺少 curl，请先安装 curl 后重试。"

# Bind paths belong to the daemon host, not the Docker CLI host. Only the
# ordinary local Linux socket can be established safely by this installer.
require_local_docker_endpoint() {
  local endpoint socket_path resolved_socket
  [[ ! -e /.dockerenv && ! -e /run/.containerenv ]] || fail "请 SSH 到运行 Docker 服务的 Linux 宿主机执行，不要在容器终端运行一键安装。"
  if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
    command -v docker >/dev/null 2>&1 || fail "无法确认 Docker context。请 SSH 到 Docker 所在 Linux 主机运行一键安装。"
    endpoint="$(docker context inspect "${DOCKER_CONTEXT}" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || fail "无法确认 Docker context。请 SSH 到 Docker 所在 Linux 主机运行一键安装。"
  elif [[ -n "${DOCKER_HOST:-}" ]]; then
    endpoint="${DOCKER_HOST}"
  elif command -v docker >/dev/null 2>&1; then
    endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || fail "无法确认 Docker context。请 SSH 到 Docker 所在 Linux 主机运行一键安装。"
  else
    endpoint='unix:///var/run/docker.sock'
  fi
  case "${endpoint}" in
    unix:///var/run/docker.sock|unix:///run/docker.sock) ;;
    *) fail "一键安装仅支持本机 Linux Docker 服务，不支持远程或 Docker Desktop。请 SSH 到 Docker 所在 Linux 主机运行；特殊部署请使用手动 Compose。" ;;
  esac
  socket_path="${endpoint#unix://}"
  if [[ -e "${socket_path}" || -L "${socket_path}" ]]; then
    [[ -S "${socket_path}" && ! -L "${socket_path}" ]] || fail "无法确认本机 Docker 套接字，请检查 Docker 服务；远程或 Docker Desktop 请使用手动 Compose。"
    resolved_socket="$(readlink -f -- "${socket_path}" 2>/dev/null)" || fail "无法确认本机 Docker 套接字，请检查 Docker 服务。"
    [[ "${resolved_socket}" == /run/docker.sock || "${resolved_socket}" == /var/run/docker.sock ]] || fail "无法确认本机 Docker 套接字，请使用手动 Compose。"
  elif [[ "${1:-}" == required ]]; then
    fail "本机 Docker 套接字不存在，请先启动本机 Linux Docker 服务。"
  fi
}

require_linux_docker_daemon() {
  local daemon_type operating_system
  daemon_type="$(docker info --format '{{.OSType}}|{{.OperatingSystem}}' 2>/dev/null)" || fail "无法确认 Docker 服务器类型。"
  [[ "${daemon_type}" == linux\|?* ]] || fail "一键安装需要本机 Linux Docker 服务，请使用手动 Compose。"
  operating_system="${daemon_type#linux|}"
  [[ "${operating_system,,}" != *'docker desktop'* ]] || fail "一键安装不支持 Docker Desktop，请 SSH 到 Docker 所在 Linux 主机运行，或使用手动 Compose。"
}

require_local_docker_endpoint

if ! command -v docker >/dev/null 2>&1; then
  info "未检测到 Docker，正在安装 Docker..."
  docker_installer="$(mktemp)"
  curl -fsSL https://get.docker.com -o "${docker_installer}"
  sh "${docker_installer}"
fi

# Recheck after installing Docker, before starting any service: an existing
# CLI configuration may select a remote daemon even without DOCKER_HOST.
require_local_docker_endpoint
if docker info >/dev/null 2>&1; then
  require_local_docker_endpoint required
  require_linux_docker_daemon
fi
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker >/dev/null 2>&1 || true
fi
docker info >/dev/null 2>&1 || fail "Docker 服务没有正常运行。"
require_local_docker_endpoint required
require_linux_docker_daemon

# Use the Docker server's architecture rather than the CLI host's. This also
# overrides an inherited DOCKER_DEFAULT_PLATFORM or an old Compose setting.
docker_server="$(docker info --format '{{.OSType}} {{.Architecture}}')" || fail "无法读取 Docker 服务器架构。"
read -r docker_os docker_arch docker_extra <<<"${docker_server}"
[[ "${docker_os:-}" == "linux" && -n "${docker_arch:-}" && -z "${docker_extra:-}" ]] || fail "需要 Linux Docker 服务器，无法识别当前服务器：${docker_server}"
DOCKER_ARCH="$(normalize_arch "${docker_arch}")"
DOCKER_PLATFORM="linux/${DOCKER_ARCH}"
info "已识别 Docker 架构：${DOCKER_PLATFORM}"

if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose=(docker-compose)
else
  fail "未检测到 Docker Compose。"
fi

info "准备安装目录 ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/plugins" "${INSTALL_DIR}/sessions" "${INSTALL_DIR}/data"

compose_files=(-f "${COMPOSE_FILE}")

# Bind a stable host factor read-only; never derive a license from an ephemeral
# container hostname/MAC and never copy this factor into the transferable data.
HOST_ID_SOURCE=""
for host_id_candidate in /etc/machine-id /var/lib/dbus/machine-id; do
  if [[ -f "${host_id_candidate}" && ! -L "${host_id_candidate}" && -r "${host_id_candidate}" ]]; then
    host_id_value="$(<"${host_id_candidate}")"
    if [[ "${host_id_value}" =~ ^[a-fA-F0-9]{32}$ && ! "${host_id_value}" =~ ^0+$ ]]; then
      HOST_ID_SOURCE="${host_id_candidate}"
      break
    fi
  fi
done
unset host_id_value

append_host_id_mount() {
  [[ -n "${HOST_ID_SOURCE}" ]] || return 0
  printf '      - type: bind\n        source: %s\n        target: /run/awbothub/host-machine-id\n        read_only: true\n        bind:\n          create_host_path: false\n' "${HOST_ID_SOURCE}"
}

select_compose_service() {
  # Inspect only the base file: an earlier failed run may have left an invalid
  # runtime override. Preserve the real service key and its Compose identity.
  local services service candidate="" candidates=0 selected_found=0
  services="$("${compose[@]}" -f "${COMPOSE_FILE}" config --services)" || fail "无法读取现有 Compose 的服务列表；原配置未修改。"
  while IFS= read -r service; do
    [[ -n "${service}" ]] || continue
    if [[ -n "${COMPOSE_SERVICE}" && "${service}" == "${COMPOSE_SERVICE}" ]]; then
      selected_found=1
    fi
    case "${service}" in
      awbothub|awbotnest)
        candidate="${service}"
        candidates=$((candidates + 1))
        ;;
    esac
  done <<<"${services}"
  if [[ -n "${COMPOSE_SERVICE}" ]]; then
    [[ "${selected_found}" -eq 1 ]] || fail "现有 Compose 中没有服务 ${COMPOSE_SERVICE}；请检查 AWBOTNEST_SERVICE，原配置未修改。"
  else
    [[ "${candidates}" -eq 1 ]] || fail "无法唯一确定 AWBotHub 服务；请用 AWBOTNEST_SERVICE 指定现有 Compose 中的服务名，原配置未修改。"
    COMPOSE_SERVICE="${candidate}"
  fi
}

write_generated_compose() {
  # Keep the installer marker, service key and data mounts stable for upgrades.
  if [[ "${DEPLOY_MODE}" == "host" ]]; then
    cat >"${COMPOSE_FILE}" <<EOF
# Generated by the AWBotNest one-click installer.
services:
  ${COMPOSE_SERVICE}:
    image: ${IMAGE}
    platform: ${DOCKER_PLATFORM}
    container_name: AWBotHub
    restart: always
    network_mode: host
    environment:
      - TZ=Asia/Shanghai
      - AWBOTNEST_WEB_PORT=${PLATFORM_PORT}
    healthcheck:
      test: ["CMD", "python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.getenv('AWBOTNEST_WEB_PORT', '18001') + '/api/health', timeout=3)"]
      interval: 30s
      timeout: 5s
      start_period: 20s
      retries: 3
    volumes:
      - ./plugins:/app/plugins
      - ./sessions:/app/sessions
      - ./data:/app/data
EOF
    append_host_id_mount >>"${COMPOSE_FILE}"
  else
    cat >"${COMPOSE_FILE}" <<EOF
# Generated by the AWBotNest one-click installer.
services:
  ${COMPOSE_SERVICE}:
    image: ${IMAGE}
    platform: ${DOCKER_PLATFORM}
    container_name: AWBotHub
    restart: always
    environment:
      - TZ=Asia/Shanghai
      - AWBOTNEST_WEB_PORT=${PLATFORM_PORT}
    ports:
      - "${WEB_PORT}:${PLATFORM_PORT}"
    healthcheck:
      test: ["CMD", "python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.getenv('AWBOTNEST_WEB_PORT', '18001') + '/api/health', timeout=3)"]
      interval: 30s
      timeout: 5s
      start_period: 20s
      retries: 3
    volumes:
      - ./plugins:/app/plugins
      - ./sessions:/app/sessions
      - ./data:/app/data
EOF
    append_host_id_mount >>"${COMPOSE_FILE}"
  fi
}

custom_image_override() {
  if [[ -n "${AWBOTNEST_IMAGE:-}" ]]; then
    printf '%s' "${IMAGE}"
    return
  fi

  # Read Compose's normalized service model, not raw YAML or another service's
  # image. Unknown output, missing awk or a config failure preserves the user's
  # selection. Only the old official unpinned image may switch automatically.
  command -v awk >/dev/null 2>&1 || return 0
  local legacy_image
  if legacy_image="$("${compose[@]}" -f "${COMPOSE_FILE}" config 2>/dev/null | awk -v selected="${COMPOSE_SERVICE}" '
    /^[^[:space:]#]/ {
      services = ($0 ~ /^services:[[:space:]]*$/)
      target = 0
      next
    }
    services && /^  [^[:space:]]/ {
      name = $0
      sub(/^  /, "", name)
      sub(/:[[:space:]]*$/, "", name)
      first = substr(name, 1, 1)
      last = substr(name, length(name), 1)
      if (length(name) >= 2 && ((first == "\"" && last == "\"") ||
          (first == sprintf("%c", 39) && last == first))) {
        name = substr(name, 2, length(name) - 2)
      }
      target = (name == selected)
      if (target) targets++
      next
    }
    services && target && /^    image:[[:space:]]*/ {
      images++
      value = $0
      sub(/^    image:[[:space:]]*/, "", value)
      sub(/[[:space:]]+$/, "", value)
      first = substr(value, 1, 1)
      last = substr(value, length(value), 1)
      if (length(value) >= 2 && ((first == "\"" && last == "\"") ||
          (first == sprintf("%c", 39) && last == first))) {
        value = substr(value, 2, length(value) - 2)
      }
    }
    END {
      if (targets == 1 && images == 1 &&
          (value == "awdress/awbotnest_v2" || value == "awdress/awbotnest_v2:latest")) {
        print "legacy-latest"
      }
    }
  ')" && [[ "${legacy_image}" == "legacy-latest" ]]; then
    printf '%s' "${IMAGE}"
  fi
  return 0
}

require_compose_overrides() {
  # Custom files must replace, not merge, the selected service's ports and
  # network attachment. !override was added in Compose 2.24.4; legacy
  # docker-compose cannot interpret it. Check before touching an old override.
  local version major minor patch
  version="$("${compose[@]}" version --short 2>/dev/null)" || version=""
  if [[ "${version}" =~ ^v?([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})([-+].*)?$ ]]; then
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    patch=$((10#${BASH_REMATCH[3]}))
    if (( major > 2 || (major == 2 && (minor > 24 || (minor == 24 && patch >= 4))) )); then
      return 0
    fi
  fi
  fail "自定义 Compose 的网络和端口切换需要 Docker Compose v2.24.4 或更新版本。请更新 Docker Compose 插件，用 docker compose version 确认后重试；原配置未修改。"
}

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  COMPOSE_SERVICE="${COMPOSE_SERVICE:-awbotnest}"
  write_generated_compose
else
  [[ ! -L "${COMPOSE_FILE}" ]] || fail "配置是符号链接，请手动修改端口，避免覆盖链接。"
  select_compose_service
  if [[ "$(sed -n '1p' "${COMPOSE_FILE}")" == "# Generated by the AWBotNest one-click installer." ]]; then
    compose_backup="$(mktemp "${COMPOSE_FILE}.bak.XXXXXX")"
    cp -p -- "${COMPOSE_FILE}" "${compose_backup}"
    write_generated_compose
    info "已按 ${DEPLOY_MODE} 模式更新安装器配置。原配置备份：${compose_backup}"
  else
    # Do not rewrite a user-maintained Compose file.  Apply the selected
    # network/port policy through a separate override that survives upgrades.
    require_compose_overrides
    [[ ! -L "${RUNTIME_OVERRIDE}" ]] || fail "运行模式覆盖文件是符号链接，请手动检查；原配置未修改。"
    [[ ! -e "${RUNTIME_OVERRIDE}" || -f "${RUNTIME_OVERRIDE}" ]] || fail "运行模式覆盖文件不是普通文件，请手动检查；原配置未修改。"
    image_override="$(custom_image_override)"
    compose_tmp="$(mktemp "${INSTALL_DIR}/.docker-compose.awbotnest-runtime.XXXXXX.yml")"
    cat >"${compose_tmp}" <<EOF
# Generated by the AWBotNest one-click installer. Do not edit the base file.
services:
  ${COMPOSE_SERVICE}:
EOF
    if [[ -n "${image_override}" ]]; then
      printf '    image: %s\n' "${image_override}" >>"${compose_tmp}"
    fi
    cat >>"${compose_tmp}" <<EOF
    platform: ${DOCKER_PLATFORM}
    networks: !reset []
    environment:
      TZ: Asia/Shanghai
      AWBOTNEST_WEB_PORT: "${PLATFORM_PORT}"
EOF
    if [[ "${DEPLOY_MODE}" == "host" ]]; then
      cat >>"${compose_tmp}" <<'EOF'
    network_mode: host
    ports: !reset []
EOF
    else
      cat >>"${compose_tmp}" <<EOF
    network_mode: bridge
    ports: !override
      - "${WEB_PORT}:${PLATFORM_PORT}"
EOF
    fi
    if [[ -n "${HOST_ID_SOURCE}" ]]; then
      printf '    volumes:\n' >>"${compose_tmp}"
      append_host_id_mount >>"${compose_tmp}"
    fi
    compose_files+=( -f "${compose_tmp}" )
  fi
fi

"${compose[@]}" "${compose_files[@]}" config -q || fail "Compose 配置校验失败，请检查网络模式和端口设置。"
if [[ -n "${compose_tmp}" ]]; then
  mv -f -- "${compose_tmp}" "${RUNTIME_OVERRIDE}"
  compose_tmp=""
  compose_files=(-f "${COMPOSE_FILE}" -f "${RUNTIME_OVERRIDE}")
  info "检测到自定义 Compose，已为服务 ${COMPOSE_SERVICE} 生成运行模式覆盖文件：${RUNTIME_OVERRIDE}"
fi

info "正在拉取最新镜像并启动 AWBotHub..."
"${compose[@]}" "${compose_files[@]}" pull "${COMPOSE_SERVICE}"
"${compose[@]}" "${compose_files[@]}" up -d "${COMPOSE_SERVICE}"

server_ip=""
if command -v hostname >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
server_ip="${server_ip:-服务器IP}"

printf '\nAWBotHub 已启动。\n'
printf '镜像架构：%s\n' "${DOCKER_PLATFORM}"
printf '网络模式：%s\n' "${DEPLOY_MODE}"
printf '访问地址：http://%s:%s\n' "${server_ip}" "${WEB_PORT}"
if [[ "${DEPLOY_MODE}" == "bridge" && "${WEB_PORT}" != "${PLATFORM_PORT}" ]]; then
  printf '宿主映射端口：%s（容器内系统端口：%s）\n' "${WEB_PORT}" "${PLATFORM_PORT}"
fi
printf '安装目录：%s\n' "${INSTALL_DIR}"
printf '首次打开网页后，请按页面提示设置管理员用户名和密码。\n\n'
