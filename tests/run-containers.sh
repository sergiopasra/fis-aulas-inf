#!/usr/bin/env bash
# Prueba el modo pull completo (bootstrap-pull.sh + aulas-update) en contenedores
# de varias distribuciones, usando una instantánea del árbol de trabajo como
# repositorio git local. Comprueba también la idempotencia (2ª ejecución changed=0).
#
#   tests/run-containers.sh                      # todas las imágenes
#   tests/run-containers.sh ubuntu:26.04         # solo una
set -euo pipefail

ENGINE=${ENGINE:-podman}
IMAGES=("$@")
[[ ${#IMAGES[@]} -gt 0 ]] || IMAGES=(ubuntu:22.04 ubuntu:26.04 almalinux:9 almalinux:10)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SNAP=$(mktemp -d)
LOGDIR=${LOGDIR:-$ROOT/tests/logs}
mkdir -p "$LOGDIR"
trap 'rm -rf "$SNAP"' EXIT

# Instantánea del árbol de trabajo (incluye cambios sin commit)
tar -C "$ROOT" --exclude=.git --exclude=tests/logs -cf - . | tar -C "$SNAP" -xf -
git -C "$SNAP" init -q -b main
git -C "$SNAP" add -A
git -C "$SNAP" -c user.name=test -c user.email=test@localhost commit -qm snapshot

read -r -d '' INNER <<'SH' || true
set -euo pipefail
git config --global --add safe.directory '*' 2>/dev/null || true
touch /tmp/dummy_key
/src/scripts/bootstrap-pull.sh file:///src /tmp/dummy_key main
echo "######## EJECUCIÓN 1 ########"
aulas-update
echo "######## EJECUCIÓN 2 (idempotencia) ########"
aulas-update | tee /tmp/run2.log
sed "s/\x1b\[[0-9;]*m//g" /tmp/run2.log | grep -Eq "localhost +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0" \
    || { echo "FALLO: la segunda ejecución no es idempotente"; exit 1; }
echo "######## COMPROBACIONES ########"
/opt/aulas/venvs/metodos_numericos/bin/python -c "import numpy, scipy, matplotlib; print('numpy', numpy.__version__)"
/opt/aulas/venvs/programacion/bin/python -V
ls /usr/local/share/jupyter/kernels
command -v code gfortran gnuplot
SH

rc=0
for img in "${IMAGES[@]}"; do
    log="$LOGDIR/${img//[:\/]/_}.log"
    echo ">>> $img  (log: $log)"
    if $ENGINE run --rm --label aulas-test -v "$SNAP:/src:ro,Z" "$img" bash -c "$INNER" >"$log" 2>&1; then
        echo "    OK"
    else
        echo "    FALLO (ver $log)"; rc=1
    fi
done
exit $rc
