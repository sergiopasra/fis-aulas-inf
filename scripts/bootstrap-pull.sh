#!/usr/bin/env bash
# Prepara una máquina (p.ej. la VM remota) para el modo pull.
# Se ejecuta UNA vez, como root:
#   sudo ./bootstrap-pull.sh <repo_url> <clave_privada_deploy> [rama]
# Ejemplo:
#   sudo ./bootstrap-pull.sh git@gitlab.example.es:aulas/aulas_inf.git ./aulas_deploy_key main
set -euo pipefail

UV_VERSION="0.13.9"
ANSIBLE_CORE_VERSION="2.21.6"
ANSIBLE_PYTHON="3.13"          # ansible-core >= 2.20 necesita Python >= 3.12 en el nodo de control
AULAS_ROOT=/opt/aulas
CONF_DIR=/etc/aulas

usage() { echo "Uso: $0 <repo_url> <clave_privada_deploy> [rama]" >&2; exit 1; }
[[ $# -ge 2 ]] || usage
REPO_URL=$1
KEY_SRC=$2
BRANCH=${3:-main}
[[ $EUID -eq 0 ]] || { echo "Ejecutar como root" >&2; exit 1; }
[[ -r $KEY_SRC ]] || { echo "No se puede leer la clave $KEY_SRC" >&2; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

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
install -m 0600 "$KEY_SRC" "${CONF_DIR}/deploy_key"
cat > "${CONF_DIR}/pull.conf" <<CONF
# Configuración de aulas-update (generada por bootstrap-pull.sh)
REPO_URL="${REPO_URL}"
BRANCH="${BRANCH}"
CONF
chmod 0600 "${CONF_DIR}/pull.conf"

install -m 0755 "${SCRIPT_DIR}/aulas-update" /usr/local/sbin/aulas-update

echo
echo "Listo. Para instalar/actualizar el software ejecuta:  sudo aulas-update"
