#!/usr/bin/env bash
# Prepara una máquina (p.ej. la VM remota) para el modo pull.
# Se ejecuta UNA vez, como root:
#   sudo ./bootstrap-pull.sh                       # repo público por HTTPS (por defecto)
#   sudo ./bootstrap-pull.sh [-k clave] [repo_url] [rama]
# Ejemplos:
#   sudo ./bootstrap-pull.sh
#   sudo ./bootstrap-pull.sh https://github.com/sergiopasra/fis-aulas-inf.git main
#   sudo ./bootstrap-pull.sh -k ./deploy_key git@github.com:usuario/repo-privado.git
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/sergiopasra/fis-aulas-inf.git"
UV_VERSION="0.13.9"
ANSIBLE_CORE_VERSION="2.21.6"
ANSIBLE_PYTHON="3.13"          # ansible-core >= 2.20 necesita Python >= 3.12 en el nodo de control
AULAS_ROOT=/opt/aulas
CONF_DIR=/etc/aulas

usage() {
    echo "Uso: $0 [-k clave_privada_deploy] [repo_url] [rama]" >&2
    echo "  -k  solo para repositorios privados por SSH (git@...)" >&2
    exit 1
}
KEY_SRC=""
while getopts "k:h" opt; do
    case $opt in
        k) KEY_SRC=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -le 2 ]] || usage
REPO_URL=${1:-$DEFAULT_REPO_URL}
BRANCH=${2:-main}
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root" >&2; exit 1; }
if [[ -n $KEY_SRC && ! -r $KEY_SRC ]]; then
    echo "No se puede leer la clave $KEY_SRC" >&2; exit 1
fi
if [[ -z $KEY_SRC && $REPO_URL != http* ]]; then
    echo "AVISO: URL SSH sin clave (-k); solo funcionará si root ya tiene acceso." >&2
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[[ -r ${SCRIPT_DIR}/aulas-update ]] || { echo "Falta aulas-update junto a este script" >&2; exit 1; }

echo ">> Paquetes mínimos (git, curl, python3)"
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q git curl ca-certificates python3 python3-apt openssh-client
elif command -v dnf >/dev/null; then
    # EL9+ trae curl-minimal (incompatible con el paquete curl): solo si falta
    command -v curl >/dev/null || extra=curl-minimal
    dnf install -y -q git-core ca-certificates python3 openssh-clients ${extra:-}
else
    echo "Gestor de paquetes no soportado" >&2; exit 1
fi

echo ">> uv ${UV_VERSION}"
ARCH=$(uname -m)
UV_DIR="${AULAS_ROOT}/uv-${UV_VERSION}"
UV_TGZ="uv-${ARCH}-unknown-linux-gnu.tar.gz"
UV_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_TGZ}"
if [[ ! -x ${UV_DIR}/uv ]]; then
    install -d -m 0755 "$UV_DIR"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$UV_TGZ" "$UV_URL"
    curl -fsSL -o "$tmp/$UV_TGZ.sha256" "$UV_URL.sha256"
    (cd "$tmp" && sha256sum -c "$UV_TGZ.sha256")
    tar -xzf "$tmp/$UV_TGZ" -C "$UV_DIR" --strip-components=1
    rm -rf "$tmp"
fi
ln -sf "${UV_DIR}/uv" /usr/local/bin/uv
ln -sf "${UV_DIR}/uvx" /usr/local/bin/uvx

echo ">> ansible-core ${ANSIBLE_CORE_VERSION} (aislado en ${AULAS_ROOT}/tools)"
UV_TOOL_DIR="${AULAS_ROOT}/tools" \
UV_TOOL_BIN_DIR=/usr/local/bin \
UV_PYTHON_INSTALL_DIR="${AULAS_ROOT}/tools/python" \
UV_PYTHON_PREFERENCE=only-managed \
    /usr/local/bin/uv tool install --force --python "$ANSIBLE_PYTHON" \
        "ansible-core==${ANSIBLE_CORE_VERSION}"

echo ">> Configuración en ${CONF_DIR}"
install -d -m 0700 "$CONF_DIR"
if [[ -n $KEY_SRC ]]; then
    install -m 0600 "$KEY_SRC" "${CONF_DIR}/deploy_key"
fi
cat > "${CONF_DIR}/pull.conf" <<CONF
# Configuración de aulas-update (generada por bootstrap-pull.sh)
REPO_URL="${REPO_URL}"
BRANCH="${BRANCH}"
CONF
chmod 0600 "${CONF_DIR}/pull.conf"

install -m 0755 "${SCRIPT_DIR}/aulas-update" /usr/local/sbin/aulas-update

echo
echo "Listo. Para instalar/actualizar el software ejecuta:  sudo aulas-update"
