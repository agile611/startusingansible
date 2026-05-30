# 📁 Ansible Example 007 — Files & Copy

Este ejemplo muestra cómo usar Ansible para **gestionar ficheros y copiarlos** a hosts remotos.
A continuación se explica la estructura del inventario, el playbook y cómo ejecutarlo.

---

## 🗂️ Inventario (`hosts`)

El fichero `hosts` define los grupos de máquinas y las variables globales de conexión.

### Variables globales (`[all:vars]`)

| Variable | Valor | Descripción |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Fuerza el uso de Python 3 en los hosts remotos |
| `ansible_user` | `vagrant` | Usuario SSH con el que se conecta Ansible |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación del fingerprint del host (útil en entornos de laboratorio) |

### Grupos de hosts

| Grupo | IP |
|---|---|
| `[database]` | `192.168.11.20` |
| `[loadbalancer]` | `192.168.11.30` |
| `[webserver]` | `192.168.11.40` |

---

## 📄 Estructura del ejemplo `007_files_copy`

El ejemplo trabaja con los módulos principales de Ansible para gestión de ficheros:

### Módulos utilizados

- **`copy`** — Copia ficheros desde el nodo de control (tu máquina) al host remoto.
- **`file`** — Gestiona atributos de ficheros y directorios (permisos, propietario, creación, borrado).
- **`template`** — Copia ficheros Jinja2 (`.j2`) al host remoto renderizando variables.
- **`fetch`** — Descarga ficheros desde el host remoto al nodo de control (inverso al `copy`).

---

## 🔍 Qué hace el Playbook paso a paso

### 1. Copiar un fichero al host remoto (`copy`)

```yaml
- name: Copy a file to remote host
  copy:
    src: files/example.txt
    dest: /tmp/example.txt
    owner: vagrant
    group: vagrant
    mode: '0644'
```

- **`src`**: ruta local del fichero (relativa al playbook).
- **`dest`**: ruta destino en el host remoto.
- **`owner` / `group`**: propietario y grupo del fichero en el remoto.
- **`mode`**: permisos en notación octal (`0644` = lectura/escritura para owner, solo lectura para el resto).

---

### 2. Crear un directorio en el host remoto (`file`)

```yaml
- name: Create a directory
  file:
    path: /tmp/mydir
    state: directory
    mode: '0755'
```

- **`state: directory`** indica que debe existir como directorio.
- Si no existe, Ansible lo crea. Si ya existe, no hace nada (idempotente).

---

### 3. Copiar con contenido inline (`copy` con `content`)

```yaml
- name: Create file with inline content
  copy:
    content: "Hello from Ansible!\n"
    dest: /tmp/hello.txt
    mode: '0644'
```

- En lugar de copiar un fichero local, **escribe directamente el contenido** especificado en `content`.

---

### 4. Usar un template Jinja2 (`template`)

```yaml
- name: Deploy template
  template:
    src: templates/mytemplate.j2
    dest: /tmp/mytemplate.txt
```

- El fichero `.j2` puede contener variables como `{{ ansible_hostname }}` o `{{ inventory_hostname }}`.
- Ansible las **sustituye por sus valores reales** antes de copiar el fichero al remoto.

---

### 5. Descargar un fichero del host remoto (`fetch`)

```yaml
- name: Fetch file from remote
  fetch:
    src: /tmp/example.txt
    dest: fetched/
    flat: yes
```

- **`flat: yes`** guarda el fichero directamente en `fetched/` sin crear subdirectorios con el nombre del host.
- Sin `flat`, la ruta sería `fetched/<hostname>/tmp/example.txt`.

---

### 6. Eliminar un fichero (`file` con `state: absent`)

```yaml
- name: Remove a file
  file:
    path: /tmp/hello.txt
    state: absent
```

- **`state: absent`** elimina el fichero si existe. Si no existe, no hace nada.

---

## ▶️ Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

| Parámetro | Descripción |
|---|---|
| `-i hosts` | Especifica el fichero de inventario |
| `-u vagrant` | Usuario SSH (aunque ya está definido en `hosts`, aquí se puede sobreescribir) |
| `playbook.yml` | Nombre del fichero playbook a ejecutar |

> **Nota:** Como el inventario ya define `ansible_user=vagrant` y la clave SSH, el flag `-u vagrant` es redundante pero no causa conflicto.

---

## 💡 Conceptos clave del ejemplo

- **Idempotencia**: todos los módulos (`copy`, `file`, `template`) solo realizan cambios si el estado actual del sistema difiere del deseado. Ejecutar el playbook varias veces produce el mismo resultado.
- **`src` relativo**: las rutas en `src` son relativas al directorio donde está el playbook.
- **Permisos con `mode`**: siempre en formato string (`'0644'`) para evitar interpretaciones erróneas de Python con el cero inicial.
- **`template` vs `copy`**: usa `copy` para ficheros estáticos y `template` cuando necesites insertar variables dinámicas.

---

## 🗃️ Estructura de ficheros del ejemplo

```
007_files_copy/
├── hosts                  # Inventario
├── playbook.yml           # Playbook principal
├── files/
│   └── example.txt        # Fichero estático a copiar
└── templates/
    └── mytemplate.j2      # Template Jinja2 con variables
```
