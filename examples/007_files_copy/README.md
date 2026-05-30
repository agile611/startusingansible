# 007 – Files & Copy con Ansible

Este ejemplo muestra cómo Ansible gestiona **ficheros y directorios** en los servidores
remotos: copiar ficheros estáticos, renderizar plantillas Jinja2, crear directorios,
establecer permisos y eliminar ficheros. Es el conjunto de operaciones más habitual
en cualquier despliegue real.

---

## 📁 Estructura del ejemplo

```
007_files_copy/
├── playbook.yml              # Playbook principal
├── group_vars/
│   └── all.yml               # Variables compartidas
└── roles/
    └── filemanager/
        ├── tasks/
        │   └── main.yml      # Tareas de gestión de ficheros
        ├── files/
        │   └── motd.txt      # Fichero estático a copiar
        └── templates/
            └── config.j2     # Plantilla Jinja2 a renderizar
```

---

## 🗂️ Inventario: `hosts`

El fichero `hosts` (en la raíz del repositorio) define las máquinas gestionadas:

```ini
[webservers]
192.168.56.11

[dbservers]
192.168.56.12

[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=~/.vagrant.d/insecure_private_key
ansible_python_interpreter=/usr/bin/python3
```

| Grupo        | IP             | Rol asignado     |
|--------------|----------------|------------------|
| `webservers` | 192.168.56.11  | Servidor Apache  |
| `dbservers`  | 192.168.56.12  | Servidor MySQL   |

- Las IPs corresponden a máquinas virtuales **Vagrant** levantadas localmente.
- Se usa la clave SSH insegura de Vagrant (entorno de desarrollo).
- Se fuerza el intérprete Python 3 para evitar warnings de deprecación.

---

## ▶️ Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

| Parámetro      | Significado                                              |
|----------------|----------------------------------------------------------|
| `-i hosts`     | Usa el fichero `hosts` como inventario                   |
| `-u vagrant`   | Se conecta a las máquinas con el usuario `vagrant`       |
| `playbook.yml` | Playbook principal a ejecutar                            |

---

## 📋 Playbook principal: `playbook.yml`

```yaml
---
- hosts: all
  become: yes
  roles:
    - filemanager
```

- Se aplica a **todos los hosts** del inventario (`webservers` + `dbservers`).
- `become: yes` permite escribir en rutas del sistema que requieren `root`.
- Delega toda la lógica al role `filemanager`.

---

## ⚙️ Role: `filemanager`

### Tareas: `roles/filemanager/tasks/main.yml`

```yaml
---
# 1. Crear un directorio en el servidor remoto
- name: Crear directorio de configuración
  file:
    path: /etc/myapp
    state: directory
    owner: root
    group: root
    mode: '0755'

# 2. Copiar un fichero estático al servidor remoto
- name: Copiar fichero MOTD
  copy:
    src: motd.txt
    dest: /etc/motd
    owner: root
    group: root
    mode: '0644'

# 3. Renderizar una plantilla Jinja2 y desplegarla
- name: Desplegar fichero de configuración desde plantilla
  template:
    src: config.j2
    dest: /etc/myapp/config.conf
    owner: root
    group: root
    mode: '0640'

# 4. Crear un fichero vacío (equivalente a touch)
- name: Crear fichero de log vacío
  file:
    path: /var/log/myapp.log
    state: touch
    owner: root
    group: root
    mode: '0664'

# 5. Eliminar un fichero del servidor remoto
- name: Eliminar fichero temporal
  file:
    path: /tmp/obsolete.conf
    state: absent
```

---

## 🔍 Análisis tarea por tarea

### 1. Crear directorio — módulo `file`

```yaml
file:
  path: /etc/myapp
  state: directory
  owner: root
  group: root
  mode: '0755'
```

- `state: directory` → crea el directorio si no existe.
- Si ya existe, Ansible solo ajusta `owner`, `group` y `mode` si difieren.
- **Idempotente:** ejecutarlo varias veces no produce efectos secundarios.

---

### 2. Copiar fichero estático — módulo `copy`

```yaml
copy:
  src: motd.txt
  dest: /etc/motd
  owner: root
  group: root
  mode: '0644'
```

- `src:` busca el fichero en `roles/filemanager/files/motd.txt` automáticamente.
- `dest:` es la ruta absoluta en el servidor remoto.
- Ansible calcula el **checksum MD5** del fichero: si el destino ya tiene el mismo
  contenido, la tarea marca `ok` (sin cambio) y no transfiere nada.
- Útil para ficheros **estáticos** que no necesitan variables.

---

### 3. Renderizar plantilla — módulo `template`

```yaml
template:
  src: config.j2
  dest: /etc/myapp/config.conf
  owner: root
  group: root
  mode: '0640'
```

- `src:` busca la plantilla en `roles/filemanager/templates/config.j2`.
- Ansible procesa la plantilla con el motor **Jinja2**, sustituyendo variables.
- El fichero resultante se despliega en `dest:` del servidor remoto.
- Si el contenido renderizado cambia respecto al fichero existente → `changed`.

---

### 4. Crear fichero vacío — módulo `file` con `state: touch`

```yaml
file:
  path: /var/log/myapp.log
  state: touch
```

- Equivalente al comando `touch` de Linux.
- Crea el fichero si no existe; si ya existe, actualiza su timestamp.
- Útil para garantizar que un fichero de log existe antes de que la aplicación arranque.

---

### 5. Eliminar fichero — módulo `file` con `state: absent`

```yaml
file:
  path: /tmp/obsolete.conf
  state: absent
```

- Elimina el fichero si existe.
- Si no existe, Ansible marca `ok` sin error (idempotente).
- Funciona también con directorios (los elimina recursivamente).

---

## 📄 Fichero estático: `roles/filemanager/files/motd.txt`

```
Bienvenido al servidor gestionado por Ansible.
Acceso autorizado únicamente.
```

- Fichero de texto plano sin variables.
- Se copia tal cual al destino `/etc/motd`.
- `/etc/motd` es el **Message Of The Day**: se muestra al hacer login por SSH.

---

## 📄 Plantilla: `roles/filemanager/templates/config.j2`

```jinja2
# Configuración generada automáticamente por Ansible
# No editar manualmente

[general]
app_name = {{ app_name }}
environment = {{ environment }}
debug = {{ debug_mode }}

[network]
host = {{ app_host }}
port = {{ app_port }}
```

- Las variables entre `{{ }}` son sustituidas por Ansible en tiempo de ejecución.
- Los valores provienen de `group_vars/all.yml`.
- El comentario `# No editar manualmente` es una buena práctica para evitar
  que alguien modifique un fichero que Ansible sobreescribirá en el próximo run.

---

## 📦 Variables: `group_vars/all.yml`

```yaml
---
app_name: myapp
environment: production
debug_mode: false
app_host: 0.0.0.0
app_port: 8080
```

- Centraliza toda la configuración de la aplicación.
- Cambiar `environment` de `production` a `staging` aquí afecta a todos los hosts.
- Al ser `group_vars/all.yml`, aplica a **todos los grupos** del inventario.

---

## 🧩 Flujo completo del playbook

```
ansible-playbook -i hosts -u vagrant playbook.yml
        │
        ├── Play 1 → all hosts (192.168.56.11 + 192.168.56.12)
        │       │
        │       ├── task 1: file      → crear /etc/myapp/          (directory)
        │       ├── task 2: copy      → copiar motd.txt → /etc/motd
        │       ├── task 3: template  → renderizar config.j2 → /etc/myapp/config.conf
        │       ├── task 4: file      → crear /var/log/myapp.log   (touch)
        │       └── task 5: file      → eliminar /tmp/obsolete.conf (absent)
        │
        └── Resultado: ambos servidores con la misma configuración de ficheros
```

---

## 🔑 Diferencia clave: `copy` vs `template`

| Característica        | `copy`                          | `template`                          |
|-----------------------|---------------------------------|--------------------------------------|
| **Tipo de fichero**   | Estático (sin variables)        | Dinámico (con variables Jinja2)      |
| **Ubicación `src`**   | `roles/<role>/files/`           | `roles/<role>/templates/`            |
| **Procesamiento**     | Copia binaria directa           | Renderizado Jinja2 antes de copiar   |
| **Uso típico**        | Binarios, imágenes, certs, txt  | Configs, scripts, ficheros `.conf`   |
| **Detección cambios** | Checksum del fichero original   | Checksum del fichero renderizado     |

---

## 💡 Conceptos clave aprendidos

| Concepto                  | Descripción                                                              |
|---------------------------|--------------------------------------------------------------------------|
| **Módulo `file`**         | Crea, elimina directorios/ficheros y gestiona permisos                   |
| **Módulo `copy`**         | Copia ficheros estáticos desde el controlador al host remoto             |
| **Módulo `template`**     | Renderiza plantillas Jinja2 e inyecta variables antes de copiar          |
| **`state: directory`**    | Garantiza que un directorio existe                                       |
| **`state: touch`**        | Garantiza que un fichero existe (lo crea vacío si no existe)             |
| **`state: absent`**       | Garantiza que un fichero/directorio NO existe (lo elimina si existe)     |
| **Idempotencia**          | Todas las operaciones son seguras de repetir sin efectos secundarios     |
| **`files/` vs `templates/`** | Separación clara entre ficheros estáticos y dinámicos dentro del role |

---

## ✅ Requisitos previos

- Vagrant instalado con las dos VMs levantadas (`vagrant up`)
- Ansible instalado en la máquina de control
- Conectividad SSH a `192.168.56.11` y `192.168.56.12`
- Sistema operativo Debian/Ubuntu en las VMs
