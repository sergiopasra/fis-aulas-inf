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
roles/julia                   Julia desde los binarios oficiales (versión en group_vars)
roles/vscode                  VS Code (repositorio de Microsoft); disponible para incluir desde una asignatura
roles/asig_<codigo>_<nombre>  un rol por asignatura (p. ej. asig_800520_fisica_computacional)
scripts/bootstrap-pull.sh     preparación (una vez) de una máquina en modo pull
scripts/aulas-update          actualización manual en modo pull
tests/run-containers.sh       pruebas en contenedores (Ubuntu 22/26, Alma 9/10)
```

Las variables van en `group_vars/` **junto a `site.yml`** (no dentro del
inventario) para que se carguen igual en modo push y en modo pull.

## Añadir una asignatura

Convención de nombres: `asig_<codigo>_<nombre>` (código de la asignatura en el plan
de estudios, nombre en minúsculas y sin tildes), p. ej. `asig_800520_fisica_computacional`.
Las variables del rol llevan ese mismo prefijo y el venv se llama `<codigo>_<nombre>`.

1. Copia un rol existente: `cp -r roles/asig_800520_fisica_computacional roles/asig_<codigo>_<nombre>`
   y renombra las variables `asig_800520_fisica_computacional_*` con el nuevo prefijo.
2. En `defaults/main.yml` pon:
   - paquetes del sistema con **nombres lógicos**; si el nombre difiere entre
     distros, añádelo a `group_vars/all/packages.yml` (un solo sitio);
   - paquetes Python (admiten especificadores, p. ej. `numpy>=2,<3`).
3. En `tasks/main.yml` usa solo los roles comunes:
   ```yaml
   - ansible.builtin.include_role: { name: syspkgs }
     vars: { syspkgs_names: "{{ asig_<codigo>_<nombre>_syspkgs }}" }

   - ansible.builtin.include_role: { name: python, tasks_from: venv }
     vars:
       python_venv_name: <codigo>_<nombre>   # -> /opt/aulas/venvs/<codigo>_<nombre>
       python_venv_python: "3.13"            # opcional; debe estar en python_versions
       python_venv_packages: "{{ asig_<codigo>_<nombre>_pypkgs }}"
       python_venv_jupyter_kernel: true      # opcional; kernel visible en Jupyter/VS Code
   ```
4. Mantén en `meta/main.yml` las dependencias `base` y `python` (vienen en la copia):
   así `--tags asig_<codigo>_<nombre>` instala también lo común, que se ejecuta una sola vez.
5. Añade el rol a `site.yml` con su tag.

Aplicaciones comunes ya disponibles para incluir desde una asignatura:
`ansible.builtin.include_role: { name: julia }` y `{ name: vscode }`.

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
ansible-playbook site.yml --tags asig_800520_fisica_computacional            # una asignatura
```

## Modo pull (VM)

El repositorio es público y se clona por HTTPS, así que no hace falta ninguna
credencial (muchas redes bloquean el SSH saliente, incluso por el puerto 443).

1. Copia a la VM `scripts/bootstrap-pull.sh` y `scripts/aulas-update` (en el mismo
   directorio) y ejecuta una vez:
   ```bash
   sudo ./bootstrap-pull.sh
   ```
   Instala git, uv y `ansible-core` aislado en `/opt/aulas/tools`, guarda la
   configuración en `/etc/aulas/pull.conf` e instala `aulas-update`. Admite otra URL
   y rama: `sudo ./bootstrap-pull.sh <repo_url> [rama]`.
2. Cada vez que se quiera actualizar:
   ```bash
   sudo aulas-update                                # todo
   sudo aulas-update --tags asig_800520_fisica_computacional   # una asignatura
   sudo aulas-update --check --diff                 # simular
   ```
   El registro queda en `/var/log/aulas-update.log`.

Como el repositorio es público, **no guardes en él ningún secreto**.

Para un fork **privado** accesible por SSH, usa una *deploy key* de solo lectura:
`sudo ./bootstrap-pull.sh -k ./deploy_key git@github.com:usuario/repo.git` (la clave se
guarda en `/etc/aulas/deploy_key` y `aulas-update` la usa automáticamente).

## Pruebas

```bash
tests/run-containers.sh                 # Ubuntu 22.04/26.04, AlmaLinux 9/10 (podman)
tests/run-containers.sh ubuntu:26.04    # solo una
```

Cada prueba ejecuta el flujo pull completo contra una instantánea local del repo,
lo aplica dos veces (la segunda debe dar `changed=0`) e importa numpy/scipy/matplotlib.
Logs en `tests/logs/`.
