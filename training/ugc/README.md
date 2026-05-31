# 📋 `training/ugc/` — Playbook de instalación de Fastfetch desde código fuente

## 🧭 Descripción general

El directorio `training/ugc/` contiene un único playbook contribuido por la comunidad del curso (*User Generated Content*): `install-fastfetch.yml`. Este playbook demuestra un patrón avanzado y muy habitual en entornos reales — **compilar e instalar software desde su código fuente** cuando no existe un paquete `.deb` disponible en los repositorios del sistema.

El software en cuestión es [**Fastfetch**](https://github.com/fastfetch-cli/fastfetch), una herramienta de información del sistema (similar a `neofetch`) escrita en C que muestra datos del hardware y el SO de forma visual en la terminal. Al no estar en los repositorios estándar de Ubuntu/Debian, hay que compilarla con `cmake` y `make`.

---

## 🗂️ Estructura del directorio

```
training/ugc/
└── install-fastfetch.yml   # Playbook: compilar e instalar Fastfetch desde GitHub
```

---

## 🗂️ Inventario compartido: `hosts`

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=vagrant
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[database]
192.168.11.20

[loadbalancer]
192.168.11.30

[webserver]
192.168.11.40
```

El playbook usa `hosts: all`, por lo que se ejecuta en los **tres nodos** del laboratorio.

---

## 📄 `install-fastfetch.yml` — Compilar e instalar Fastfetch desde código fuente

### Código completo

```yaml
---
- name: Instalar fastfetch en las VMs del curso
  hosts: all
  become: true
  gather_facts: true

  tasks:

    - name: Actualizar la caché de paquetes
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Instalar dependencias necesarias
      apt:
        name:
          - git
          - cmake
          - build-essential
          - pkg-config
          - libgl1-mesa-dev
          - libwayland-dev
          - libx11-dev
        state: present

    - name: Clonar repositorio oficial de fastfetch
      git:
        repo: "https://github.com/fastfetch-cli/fastfetch.git"
        dest: "/tmp/fastfetch"
        version: master
        force: yes

    - name: Crear directorio build
      file:
        path: "/tmp/fastfetch/build"
        state: directory

    - name: Ejecutar cmake
      command: cmake .. chdir=/tmp/fastfetch/build

    - name: Compilar
      command: make -j"{{ ansible_processor_vcpus | default(2) }}" chdir=/tmp/fastfetch/build

    - name: Instalar
      command: make install chdir=/tmp/fastfetch/build

    - name: Verificar instalación
      command: fastfetch --version
      register: ff_version

    - name: Mostrar versión instalada
      debug:
        var: ff_version.stdout
```

---

## 🔍 Análisis tarea por tarea

### Cabecera del play

```yaml
hosts: all
become: true
gather_facts: true
```

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `hosts: all` | Todos los grupos | Actúa sobre `database`, `loadbalancer` y `webserver` |
| `become: true` | Escalada de privilegios | Todas las tareas corren como `root` |
| `gather_facts: true` | Recopilar facts | Activa la recopilación de información del sistema (necesaria para `ansible_processor_vcpus`) |

---

### Tarea 1 — Actualizar la caché de paquetes

```yaml
- name: Actualizar la caché de paquetes
  apt:
    update_cache: yes
    cache_valid_time: 3600
```

Equivale a ejecutar `apt-get update` en cada nodo. El parámetro `cache_valid_time: 3600` es un optimizador de idempotencia: si la caché tiene menos de **3600 segundos (1 hora)** de antigüedad, Ansible la omite y no vuelve a actualizarla. Esto evita actualizaciones redundantes si el playbook se ejecuta varias veces seguidas.

---

### Tarea 2 — Instalar dependencias de compilación

```yaml
- name: Instalar dependencias necesarias
  apt:
    name:
      - git
      - cmake
      - build-essential
      - pkg-config
      - libgl1-mesa-dev
      - libwayland-dev
      - libx11-dev
    state: present
```

Instala las **7 dependencias** necesarias para compilar Fastfetch desde código fuente:

| **Paquete** | **Función** |
|---|---|
| `git` | Clonar el repositorio de Fastfetch desde GitHub |
| `cmake` | Sistema de construcción multiplataforma — genera los `Makefile` |
| `build-essential` | Compilador GCC, `make` y cabeceras del kernel — el kit mínimo para compilar en C/C++ |
| `pkg-config` | Herramienta para localizar librerías del sistema durante la compilación |
| `libgl1-mesa-dev` | Cabeceras de OpenGL — para detección de GPU y aceleración gráfica |
| `libwayland-dev` | Cabeceras de Wayland — para detección del compositor gráfico |
| `libx11-dev` | Cabeceras de X11 — para detección del servidor de ventanas X |

> Las librerías `libgl1`, `libwayland` y `libx11` son opcionales en un servidor headless, pero Fastfetch las usa para detectar información gráfica del sistema.

---

### Tarea 3 — Clonar el repositorio oficial

```yaml
- name: Clonar repositorio oficial de fastfetch
  git:
    repo: "https://github.com/fastfetch-cli/fastfetch.git"
    dest: "/tmp/fastfetch"
    version: master
    force: yes
```

Descarga el código fuente de Fastfetch desde GitHub al directorio `/tmp/fastfetch` del nodo remoto.

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `repo` | URL de GitHub | Repositorio oficial de Fastfetch |
| `dest` | `/tmp/fastfetch` | Directorio de destino en el nodo remoto |
| `version: master` | Rama `master` | Usa la última versión del código en la rama principal |
| `force: yes` | Forzar | Si el directorio ya existe con cambios locales, los descarta y actualiza |

> `force: yes` garantiza idempotencia: si el playbook se ejecuta de nuevo, el repositorio se actualiza al estado limpio de `master` sin errores.

---

### Tarea 4 — Crear el directorio de compilación

```yaml
- name: Crear directorio build
  file:
    path: "/tmp/fastfetch/build"
    state: directory
```

Crea el directorio `/tmp/fastfetch/build` donde `cmake` generará los ficheros de compilación. El módulo `file` con `state: directory` es idempotente — si el directorio ya existe, no hace nada.

Esta es la estructura estándar de compilación con `cmake`:

```
/tmp/fastfetch/          ← Código fuente (clonado en tarea 3)
└── build/               ← Directorio de compilación (creado en tarea 4)
    ├── CMakeCache.txt   ← Generado por cmake (tarea 5)
    ├── Makefile         ← Generado por cmake (tarea 5)
    └── fastfetch        ← Binario compilado (tarea 6)
```

---

### Tarea 5 — Ejecutar CMake (configuración)

```yaml
- name: Ejecutar cmake
  command: cmake .. chdir=/tmp/fastfetch/build
```

Ejecuta `cmake ..` desde el directorio `build`, apuntando al directorio padre (`..`) donde está el `CMakeLists.txt` del proyecto. CMake analiza el código fuente, detecta las librerías disponibles y genera los `Makefile` optimizados para el sistema.

```
Directorio de trabajo: /tmp/fastfetch/build/
Comando ejecutado:     cmake ..
                             ↑
                       Apunta a /tmp/fastfetch/ (donde está CMakeLists.txt)
```

> `chdir=` es el parámetro del módulo `command` que cambia el directorio de trabajo antes de ejecutar el comando. Equivale a `cd /tmp/fastfetch/build && cmake ..`.

---

### Tarea 6 — Compilar (make)

```yaml
- name: Compilar
  command: make -j"{{ ansible_processor_vcpus | default(2) }}" chdir=/tmp/fastfetch/build
```

Compila el código fuente usando todos los núcleos de CPU disponibles para maximizar la velocidad.

| **Elemento** | **Valor** | **Significado** |
|---|---|---|
| `make` | Comando de compilación | Lee el `Makefile` generado por cmake y compila |
| `-j` | Flag de paralelismo | Número de trabajos paralelos de compilación |
| `ansible_processor_vcpus` | Fact del sistema | Número de CPUs virtuales del nodo (recopilado por `gather_facts: true`) |
| `\| default(2)` | Filtro Jinja2 | Si el fact no está disponible, usa 2 como valor por defecto |

**Ejemplo de expansión en las VMs del laboratorio** (1 vCPU):
```bash
make -j1 chdir=/tmp/fastfetch/build
```

**Ejemplo en una máquina con 4 CPUs:**
```bash
make -j4 chdir=/tmp/fastfetch/build
```

> Este es un ejemplo excelente del uso de **facts del sistema para optimizar la ejecución**: Ansible detecta automáticamente los recursos del nodo y adapta el comando de compilación.

---

### Tarea 7 — Instalar el binario compilado

```yaml
- name: Instalar
  command: make install chdir=/tmp/fastfetch/build
```

Copia el binario compilado y sus ficheros de datos a las rutas estándar del sistema:

```
/usr/local/bin/fastfetch        ← Binario principal
/usr/local/share/fastfetch/     ← Ficheros de configuración y assets
```

`make install` usa las rutas definidas en el `CMakeLists.txt` del proyecto. Al ejecutarse con `become: true`, tiene permisos para escribir en `/usr/local/bin/`.

---

### Tarea 8 — Verificar la instalación

```yaml
- name: Verificar instalación
  command: fastfetch --version
  register: ff_version
```

Ejecuta `fastfetch --version` para confirmar que el binario está correctamente instalado y accesible en el `PATH`. La salida se captura en la variable `ff_version`.

---

### Tarea 9 — Mostrar la versión instalada

```yaml
- name: Mostrar versión instalada
  debug:
    var: ff_version.stdout
```

Imprime en la salida de Ansible la versión de Fastfetch instalada. Ejemplo de salida esperada:

```
TASK [Mostrar versión instalada] ***********************
ok: [192.168.11.20] => {
    "ff_version.stdout": "fastfetch 2.x.x"
}
ok: [192.168.11.30] => {
    "ff_version.stdout": "fastfetch 2.x.x"
}
ok: [192.168.11.40] => {
    "ff_version.stdout": "fastfetch 2.x.x"
}
```

---

## 🚀 Flujo de ejecución completo

```
install-fastfetch.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
│  [Gathering Facts] ← Recopila ansible_processor_vcpus y otros facts
│
├── [1] apt: update_cache → cache_valid_time: 3600
│       └── Actualiza la caché apt (si tiene más de 1h de antigüedad)
│
├── [2] apt: [git, cmake, build-essential, pkg-config, libgl1, libwayland, libx11]
│       └── Instala las 7 dependencias de compilación
│
├── [3] git: fastfetch-cli/fastfetch → /tmp/fastfetch (master, force)
│       └── Clona el código fuente desde GitHub
│
├── [4] file: /tmp/fastfetch/build → state: directory
│       └── Crea el directorio de compilación
│
├── [5] command: cmake .. (chdir: /tmp/fastfetch/build)
│       └── Configura el sistema de compilación y genera Makefiles
│
├── [6] command: make -j{{ ansible_processor_vcpus | default(2) }}
│       └── Compila el código fuente en paralelo
│
├── [7] command: make install
│       └── Instala el binario en /usr/local/bin/fastfetch
│
├── [8] command: fastfetch --version → register: ff_version
│       └── Verifica que el binario funciona correctamente
│
└── [9] debug: ff_version.stdout
        └── Muestra la versión instalada en la salida de Ansible
```

---

## 🚀 Comando de ejecución

```bash
# Ejecutar en todos los nodos
ansible-playbook -i hosts -u vagrant training/ugc/install-fastfetch.yml

# Ejecutar solo en el webserver
ansible-playbook -i hosts -u vagrant training/ugc/install-fastfetch.yml --limit webserver

# Ejecutar en modo dry-run (sin cambios reales)
ansible-playbook -i hosts -u vagrant training/ugc/install-fastfetch.yml --check

# Ver la salida detallada de cada tarea
ansible-playbook -i hosts -u vagrant training/ugc/install-fastfetch.yml -v
```

---

## 💡 Conceptos clave aprendidos

- **Compilación desde código fuente con Ansible**: El patrón `git clone` → `cmake` → `make` → `make install` es la forma estándar de instalar software que no está en los repositorios del sistema. Ansible orquesta cada paso como una tarea independiente.

- **`gather_facts: true` para optimización dinámica**: El fact `ansible_processor_vcpus` permite adaptar el número de trabajos paralelos de `make` a los recursos reales de cada nodo. Sin `gather_facts`, este fact no estaría disponible.

- **Filtro `| default(valor)`**: Patrón defensivo de Jinja2 que proporciona un valor de respaldo cuando un fact o variable puede no estar definido. `ansible_processor_vcpus | default(2)` garantiza que el playbook funciona incluso si el fact no se puede detectar.

- **`chdir=` en el módulo `command`**: Permite cambiar el directorio de trabajo antes de ejecutar un comando, evitando la necesidad de encadenar `cd && comando` en una shell. Es más limpio y explícito que usar el módulo `shell`.

- **`force: yes` en el módulo `git`**: Garantiza que el repositorio siempre esté en el estado limpio de la rama especificada, descartando cualquier cambio local. Esencial para idempotencia en entornos donde el playbook puede ejecutarse múltiples veces.

- **`register` + `debug` como patrón de verificación**: Capturar la salida de un comando de verificación (`fastfetch --version`) y mostrarla con `debug` es una práctica habitual para confirmar el éxito de una instalación sin necesidad de conectarse manualmente a los nodos.

---

## 📚 Referencias

- [Fastfetch — Repositorio oficial](https://github.com/fastfetch-cli/fastfetch)
- [Ansible Docs — Módulo `git`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/git_module.html)
- [Ansible Docs — Módulo `command`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)
- [Ansible Docs — Módulo `file`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Ansible Docs — Filtros Jinja2 (`default`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html)
- [Ansible Docs — `gather_facts`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
