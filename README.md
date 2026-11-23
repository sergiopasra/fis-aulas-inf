# Software de las aulas de informática (Ansible)

Un único conjunto de playbooks para instalar el software de las asignaturas en:

| Máquinas | Modo | Cómo |
|---|---|---|
| Equipos físicos (Ubuntu 22.04) | **push** desde el nodo central | `ansible-playbook site.yml` |
| VM remota (Ubuntu 26.04) | **pull** desde este repo git privado | `sudo aulas-update` |

Soporta las familias **Debian/Ubuntu** y **RedHat** (RHEL, Alma, Rocky). Todas las
asignaturas se instalan en todas las máquinas.

## Estructura

```
site.yml                      playbook único (push y pull)
group_vars/all/main.yml       versiones (uv, Python) y rutas (/opt/aulas)
group_vars/all/packages.yml   pkg_map: nombre lógico -> paquete real por distro
inventories/aulas/hosts.yml   equipos físicos (modo push)
roles/base                    preparación de la distro y paquetes básicos
roles/syspkgs                 ÚNICA forma de instalar paquetes del sistema
roles/python                  ÚNICA forma de instalar Python y entornos (uv)
roles/vscode                  ejemplo de app con repositorio de terceros
roles/asig_*                  un rol por asignatura
scripts/bootstrap-pull.sh     preparación (una vez) de una máquina en modo pull
scripts/aulas-update          actualización manual en modo pull
tests/run-containers.sh       pruebas en contenedores (Ubuntu 22/26, Alma 9/10)
```

Las variables van en `group_vars/` **junto a `site.yml`** (no dentro del
inventario) para que se carguen igual en modo push y en modo pull.

## Añadir una asignatura

1. Copia un rol de ejemplo: `cp -r roles/asig_metodos_numericos roles/asig_nueva`
   y renombra las variables `asig_metodos_numericos_*` → `asig_nueva_*`.
2. En `defaults/main.yml` pon:
   - paquetes del sistema con **nombres lógicos**; si el nombre difiere entre
     distros, añádelo a `group_vars/all/packages.yml` (un solo sitio);
   - paquetes Python (admiten especificadores, p. ej. `numpy>=2,<3`).
3. En `tasks/main.yml` usa solo los roles comunes:
   ```yaml
   - ansible.builtin.include_role: { name: syspkgs }
     vars: { syspkgs_names: "{{ asig_nueva_syspkgs }}" }

   - ansible.builtin.include_role: { name: python, tasks_from: venv }
     vars:
       python_venv_name: nueva               # -> /opt/aulas/venvs/nueva
       python_venv_python: "3.13"            # opcional; debe estar en python_versions
       python_venv_packages: "{{ asig_nueva_pypkgs }}"
       python_venv_jupyter_kernel: true      # opcional; kernel visible en Jupyter/VS Code
   ```
4. Mantén en `meta/main.yml` las dependencias `base` y `python` (vienen en la copia):
   así `--tags asig_nueva` instala también lo común, que se ejecuta una sola vez.
5. Añade el rol a `site.yml` con su tag.

Si algo es inevitablemente distinto por distro, usa
`include_tasks: "{{ ansible_facts['os_family'] }}.yml"` con `Debian.yml` y
`RedHat.yml` (ver `roles/vscode`).

## Python (uv)

- `uv` se instala desde el binario oficial en `/opt/aulas/uv-<versión>` y se enlaza en `/usr/local/bin`.
- Las versiones de `python_versions` se instalan en `/opt/aulas/python`, independientes del Python de la distro.
- Cada asignatura tiene su venv en `/opt/aulas/venvs/<nombre>` (de root, solo lectura para alumnos).
  El paquete se resuelve con `uv pip compile` y se aplica con `uv pip sync`, así el venv
  refleja exactamente la lista: quitar un paquete de la lista lo desinstala. El lock
  resultante queda en `/opt/aulas/venvs/.specs/<nombre>.txt`.
- Los alumnos: `source /opt/aulas/venvs/<nombre>/bin/activate`, o crean su propio entorno
  con los mismos Python: `uv venv --python 3.12 ~/mi-entorno`.

## Modo push (equipos físicos)

Requisitos en el nodo central: `uv tool install --python 3.13 ansible-core==2.21.6`.
Requisitos en cada equipo: usuario `ansible` (ver `inventories/aulas/hosts.yml`) con la
clave SSH del nodo central y `sudo` sin contraseña.

```bash
ansible-playbook site.yml --limit aula1-pc01.example.ucm.es --check --diff   # simular
ansible-playbook site.yml --limit aula1                                      # un aula
ansible-playbook site.yml --tags asig_metodos_numericos                      # una asignatura
```

## Modo pull (VM)

1. Genera una clave **solo para este repo**: `ssh-keygen -t ed25519 -N '' -f aulas_deploy_key`
   y añade `aulas_deploy_key.pub` como *deploy key* de **solo lectura** en el servidor git.
2. Copia a la VM `scripts/bootstrap-pull.sh`, `scripts/aulas-update` y la clave privada, y ejecuta una vez:
   ```bash
   sudo ./bootstrap-pull.sh git@git.example.es:aulas/aulas_inf.git ./aulas_deploy_key main
   rm ./aulas_deploy_key
   ```
   Instala git, uv y `ansible-core` aislado en `/opt/aulas/tools`, guarda la clave en
   `/etc/aulas/deploy_key` y la configuración en `/etc/aulas/pull.conf`.
3. Cada vez que se quiera actualizar:
   ```bash
   sudo aulas-update                                # todo
   sudo aulas-update --tags asig_programacion       # una asignatura
   sudo aulas-update --check --diff                 # simular
   ```
   El registro queda en `/var/log/aulas-update.log`.

No guardes secretos en este repositorio: cualquiera con root en la VM puede leer la deploy key.

## Pruebas

```bash
tests/run-containers.sh                 # Ubuntu 22.04/26.04, AlmaLinux 9/10 (podman)
tests/run-containers.sh ubuntu:26.04    # solo una
```

Cada prueba ejecuta el flujo pull completo contra una instantánea local del repo,
lo aplica dos veces (la segunda debe dar `changed=0`) e importa numpy/scipy/matplotlib.
Logs en `tests/logs/`.
