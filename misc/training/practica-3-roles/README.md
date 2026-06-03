# 📋 `training/practica-3-roles/` — Infraestructura completa con Roles de Ansible

## 🧭 Descripción general

La práctica 3 representa el salto cualitativo más importante del curso: pasar de playbooks monolíticos a una arquitectura basada en **Roles de Ansible**. Un rol es la unidad de reutilización fundamental de Ansible — encapsula tareas, handlers, variables, plantillas y ficheros en una estructura de directorios estandarizada que puede aplicarse a cualquier proyecto.

Este ejemplo despliega una **infraestructura web de tres capas** completa:
- 🗄️ **Base de datos** MySQL/MariaDB en `192.168.11.20`
- ⚖️ **Balanceador de carga** Nginx en `192.168.11.30`
- 🌐 **Servidor web** Apache/Nginx en `192.168.11.40`

Cada capa está implementada como un rol independiente, orquestados todos desde un único punto de entrada: `site.yml`.

---

## 🗂️ Estructura del directorio

```
practica-3-roles/
├── site.yml                          # Punto de entrada — orquesta los tres roles
└── roles/
    ├── database/                     # Rol: gestión de la base de datos
    │   ├── tasks/
    │   │   └── main.yml              # Tareas: instalar y configurar MySQL/MariaDB
    │   ├── handlers/
    │   │   └── main.yml              # Handler: reiniciar el servicio de base de datos
    │   ├── templates/
    │   │   └── my.cnf.j2             # Plantilla Jinja2: configuración de MySQL
    │   └── vars/
    │       └── main.yml              # Variables: credenciales y parámetros de BD
    ├── loadbalancer/                 # Rol: gestión del balanceador de carga
    │   ├── tasks/
    │   │   └── main.yml              # Tareas: instalar y configurar Nginx como proxy
    │   ├── handlers/
    │   │   └── main.yml              # Handler: reiniciar Nginx
    │   └── templates/
    │       └── nginx.conf.j2         # Plantilla Jinja2: configuración del upstream
    └── webserver/                    # Rol: gestión del servidor web
        ├── tasks/
        │   └── main.yml              # Tareas: instalar Apache/Nginx y desplegar app
        ├── handlers/
        │   └── main.yml              # Handler: reiniciar el servidor web
        ├── templates/
        │   └── index.html.j2         # Plantilla Jinja2: página web dinámica
        └── vars/
            └── main.yml              # Variables: puerto, nombre de app, etc.
```

---

## 🗂️ Inventario `hosts`

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

Cada grupo del inventario corresponde exactamente a un rol: `database` → rol `database`, `loadbalancer` → rol `loadbalancer`, `webserver` → rol `webserver`.

---

## 📄 `site.yml` — El director de orquesta

`site.yml` es el **único fichero que se ejecuta directamente**. No contiene lógica de configuración — su única responsabilidad es asignar cada rol al grupo de hosts correcto.

```yaml
---
- name: Configurar base de datos
  hosts: database
  become: true
  roles:
    - database

- name: Configurar servidor web
  hosts: webserver
  become: true
  roles:
    - webserver

- name: Configurar balanceador de carga
  hosts: loadbalancer
  become: true
  roles:
    - loadbalancer
```

### ¿Por qué este orden importa?

El orden de los plays en `site.yml` define la **secuencia de despliegue**:

```
1. database    → La BD debe estar lista antes de que el webserver intente conectarse
2. webserver   → La app debe estar corriendo antes de que el LB la registre
3. loadbalancer → Se configura al final, cuando ya tiene backends disponibles
```

| **Play** | **`hosts`** | **`become`** | **Rol aplicado** | **IP destino** |
|---|---|---|---|---|
| Configurar base de datos | `database` | `true` (root) | `database` | 192.168.11.20 |
| Configurar servidor web | `webserver` | `true` (root) | `webserver` | 192.168.11.40 |
| Configurar balanceador | `loadbalancer` | `true` (root) | `loadbalancer` | 192.168.11.30 |

---

## 🗄️ Rol `database` — Base de datos MySQL/MariaDB

### `roles/database/vars/main.yml` — Variables del rol

```yaml
---
db_name: appdb
db_user: appuser
db_password: "S3cur3P@ss"
mysql_bind_address: "0.0.0.0"
```

Las variables definen los parámetros de la base de datos. Al estar en `vars/main.yml`, tienen **alta precedencia** en Ansible y no pueden ser sobreescritas accidentalmente desde el inventario.

### `roles/database/tasks/main.yml` — Tareas

```yaml
---
- name: Instalar MariaDB
  apt:
    name:
      - mariadb-server
      - python3-mysqldb
    state: present
    update_cache: yes

- name: Asegurar que MariaDB está iniciado y habilitado
  service:
    name: mariadb
    state: started
    enabled: yes

- name: Crear base de datos de la aplicación
  mysql_db:
    name: "{{ db_name }}"
    state: present

- name: Crear usuario de base de datos
  mysql_user:
    name: "{{ db_user }}"
    password: "{{ db_password }}"
    priv: "{{ db_name }}.*:ALL"
    host: "%"
    state: present

- name: Desplegar configuración de MariaDB
  template:
    src: my.cnf.j2
    dest: /etc/mysql/mariadb.conf.d/50-server.cnf
    owner: root
    group: root
    mode: "0644"
  notify: Reiniciar MariaDB
```

**Flujo de ejecución del rol `database`:**

```
[1] apt: instala mariadb-server + python3-mysqldb
         └── python3-mysqldb es el conector Python necesario para los módulos mysql_db y mysql_user
[2] service: arranca mariadb y lo habilita en el arranque del sistema
[3] mysql_db: crea la base de datos "appdb"
[4] mysql_user: crea el usuario "appuser" con acceso desde cualquier host (host: "%")
[5] template: despliega my.cnf.j2 → /etc/mysql/mariadb.conf.d/50-server.cnf
              └── notify: si el fichero cambia, dispara el handler "Reiniciar MariaDB"
```

### `roles/database/handlers/main.yml` — Handlers

```yaml
---
- name: Reiniciar MariaDB
  service:
    name: mariadb
    state: restarted
```

El handler solo se ejecuta **una vez al final del play**, y únicamente si alguna tarea lo notificó con `notify`. Si la plantilla `my.cnf.j2` no cambia (segunda ejecución del playbook), el handler no se dispara — esto es idempotencia en acción.

### `roles/database/templates/my.cnf.j2` — Plantilla de configuración

```jinja2
[mysqld]
bind-address        = {{ mysql_bind_address }}
datadir             = /var/lib/mysql
socket              = /run/mysqld/mysqld.sock

# Configuración de rendimiento
max_connections     = 100
innodb_buffer_pool_size = 256M

# Logging
general_log         = 0
general_log_file    = /var/log/mysql/mysql.log
```

La variable `{{ mysql_bind_address }}` se sustituye por el valor de `vars/main.yml` (`0.0.0.0`), lo que permite que MariaDB acepte conexiones desde cualquier interfaz de red — necesario para que el webserver en `.40` pueda conectarse a la BD en `.20`.

---

## ⚖️ Rol `loadbalancer` — Balanceador de carga Nginx

### `roles/loadbalancer/tasks/main.yml` — Tareas

```yaml
---
- name: Instalar Nginx
  apt:
    name: nginx
    state: present
    update_cache: yes

- name: Asegurar que Nginx está iniciado y habilitado
  service:
    name: nginx
    state: started
    enabled: yes

- name: Desplegar configuración del balanceador
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/loadbalancer.conf
    owner: root
    group: root
    mode: "0644"
  notify: Reiniciar Nginx

- name: Activar el sitio del balanceador
  file:
    src: /etc/nginx/sites-available/loadbalancer.conf
    dest: /etc/nginx/sites-enabled/loadbalancer.conf
    state: link
  notify: Reiniciar Nginx

- name: Desactivar el sitio por defecto de Nginx
  file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Reiniciar Nginx
```

**Flujo de ejecución del rol `loadbalancer`:**

```
[1] apt: instala nginx
[2] service: arranca nginx y lo habilita en el arranque
[3] template: despliega nginx.conf.j2 → /etc/nginx/sites-available/loadbalancer.conf
[4] file (link): crea symlink en sites-enabled para activar el sitio
[5] file (absent): elimina el sitio "default" para evitar conflictos de puertos
    └── Los tres pasos [3][4][5] notifican al handler "Reiniciar Nginx"
```

### `roles/loadbalancer/handlers/main.yml` — Handlers

```yaml
---
- name: Reiniciar Nginx
  service:
    name: nginx
    state: restarted
```

### `roles/loadbalancer/templates/nginx.conf.j2` — Plantilla de configuración

```jinja2
upstream webservers {
{% for host in groups['webserver'] %}
    server {{ hostvars[host]['ansible_host'] | default(host) }};
{% endfor %}
}

server {
    listen 80;

    location / {
        proxy_pass http://webservers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Esta plantilla es el corazón del balanceador. Usa **dos variables mágicas de Ansible** para construir dinámicamente la lista de backends:

| **Variable Jinja2** | **Significado** |
|---|---|
| `groups['webserver']` | Lista de todos los hosts del grupo `webserver` del inventario |
| `hostvars[host]['ansible_host']` | IP o hostname de cada host, obtenida de los facts |

**Resultado generado** para el inventario del laboratorio:

```nginx
upstream webservers {
    server 192.168.11.40;
}

server {
    listen 80;
    location / {
        proxy_pass http://webservers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

> Si se añadieran más hosts al grupo `webserver` en el inventario, el bucle `{% for %}` los incluiría automáticamente en el bloque `upstream` sin modificar la plantilla.

---

## 🌐 Rol `webserver` — Servidor web de aplicación

### `roles/webserver/vars/main.yml` — Variables del rol

```yaml
---
app_name: "Mi Aplicación Web"
app_port: 80
server_admin: "admin@example.com"
```

### `roles/webserver/tasks/main.yml` — Tareas

```yaml
---
- name: Instalar Apache2
  apt:
    name: apache2
    state: present
    update_cache: yes

- name: Asegurar que Apache está iniciado y habilitado
  service:
    name: apache2
    state: started
    enabled: yes

- name: Desplegar página web principal
  template:
    src: index.html.j2
    dest: /var/www/html/index.html
    owner: www-data
    group: www-data
    mode: "0644"
  notify: Reiniciar Apache
```

**Flujo de ejecución del rol `webserver`:**

```
[1] apt: instala apache2
[2] service: arranca apache2 y lo habilita en el arranque
[3] template: despliega index.html.j2 → /var/www/html/index.html
              └── notify: si el HTML cambia, dispara "Reiniciar Apache"
```

### `roles/webserver/handlers/main.yml` — Handlers

```yaml
---
- name: Reiniciar Apache
  service:
    name: apache2
    state: restarted
```

### `roles/webserver/templates/index.html.j2` — Plantilla HTML dinámica

```jinja2
<!DOCTYPE html>
<html>
<head>
    <title>{{ app_name }}</title>
</head>
<body>
    <h1>Bienvenido a {{ app_name }}</h1>
    <p>Servidor: <strong>{{ inventory_hostname }}</strong></p>
    <p>IP: <strong>{{ ansible_default_ipv4.address }}</strong></p>
    <p>Sistema Operativo: {{ ansible_distribution }} {{ ansible_distribution_version }}</p>
    <p>Administrador: {{ server_admin }}</p>
</body>
</html>
```

**Resultado generado** en el nodo `192.168.11.40`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Mi Aplicación Web</title>
</head>
<body>
    <h1>Bienvenido a Mi Aplicación Web</h1>
    <p>Servidor: <strong>192.168.11.40</strong></p>
    <p>IP: <strong>192.168.11.40</strong></p>
    <p>Sistema Operativo: Ubuntu 22.04</p>
    <p>Administrador: admin@example.com</p>
</body>
</html>
```

Las variables `ansible_default_ipv4.address`, `ansible_distribution` y `ansible_distribution_version` son **facts del sistema** recopilados automáticamente por Ansible al inicio del play.

---

## 🔄 Flujo de ejecución completo de `site.yml`

```
ansible-playbook -i hosts -u vagrant site.yml
│
│  ══════════════════════════════════════════
│  PLAY 1: Configurar base de datos
│  hosts: database (192.168.11.20)
│  ══════════════════════════════════════════
│  [Gathering Facts]
│  ├── [task] apt: instala mariadb-server + python3-mysqldb
│  ├── [task] service: arranca y habilita mariadb
│  ├── [task] mysql_db: crea base de datos "appdb"
│  ├── [task] mysql_user: crea usuario "appuser"
│  └── [task] template: despliega my.cnf.j2
│              └── [handler] Reiniciar MariaDB (si hubo cambios)
│
│  ══════════════════════════════════════════
│  PLAY 2: Configurar servidor web
│  hosts: webserver (192.168.11.40)
│  ══════════════════════════════════════════
│  [Gathering Facts]
│  ├── [task] apt: instala apache2
│  ├── [task] service: arranca y habilita apache2
│  └── [task] template: despliega index.html.j2
│              └── [handler] Reiniciar Apache (si hubo cambios)
│
│  ══════════════════════════════════════════
│  PLAY 3: Configurar balanceador de carga
│  hosts: loadbalancer (192.168.11.30)
│  ══════════════════════════════════════════
│  [Gathering Facts]
│  ├── [task] apt: instala nginx
│  ├── [task] service: arranca y habilita nginx
│  ├── [task] template: despliega nginx.conf.j2 (con IPs del grupo webserver)
│  ├── [task] file (link): activa el sitio en sites-enabled
│  └── [task] file (absent): elimina el sitio default
│              └── [handler] Reiniciar Nginx (si hubo cambios)
│
└── PLAY RECAP ─────────────────────────────
    192.168.11.20  : ok=5  changed=3  unreachable=0  failed=0
    192.168.11.30  : ok=5  changed=3  unreachable=0  failed=0
    192.168.11.40  : ok=3  changed=2  unreachable=0  failed=0
```

---

## 🚀 Comandos de ejecución

### Despliegue completo de la infraestructura
```bash
ansible-playbook -i hosts -u vagrant site.yml
```

### Despliegue solo de un rol específico (con tags)
```bash
# Solo la base de datos
ansible-playbook -i hosts -u vagrant site.yml --limit database

# Solo el servidor web
ansible-playbook -i hosts -u vagrant site.yml --limit webserver

# Solo el balanceador
ansible-playbook -i hosts -u vagrant site.yml --limit loadbalancer
```

### Dry-run — Ver qué cambiaría sin aplicar cambios
```bash
ansible-playbook -i hosts -u vagrant site.yml --check
```

### Ejecución con salida detallada
```bash
ansible-playbook -i hosts -u vagrant site.yml -v
```

### Verificar la sintaxis antes de ejecutar
```bash
ansible-playbook -i hosts -u vagrant site.yml --syntax-check
```

---

## 💡 Conceptos clave aprendidos

- **Estructura de un Rol**: Un rol es un directorio con subdirectorios estandarizados (`tasks/`, `handlers/`, `templates/`, `vars/`, `files/`, `defaults/`, `meta/`). Ansible los carga automáticamente por convención de nombres — no hace falta declarar `include` manualmente.

- **`site.yml` como punto de entrada único**: El patrón de tener un `site.yml` que orquesta todos los roles es la práctica estándar en proyectos Ansible reales. Permite desplegar toda la infraestructura con un único comando.

- **Separación de responsabilidades**: Cada rol es completamente independiente y autocontenido. El rol `database` no sabe nada del `webserver`, y viceversa. Esto permite reutilizar roles en otros proyectos sin modificaciones.

- **`vars/main.yml` vs `defaults/main.yml`**: Las variables en `vars/` tienen alta precedencia y son para valores que no deben sobreescribirse. Las variables en `defaults/` (no usadas aquí) tienen baja precedencia y son para valores por defecto que el usuario puede personalizar.

- **Handlers y notificaciones**: El sistema `notify` / `handlers` garantiza que los servicios solo se reinician cuando su configuración cambia realmente. En la segunda ejecución del playbook (idempotencia), si nada ha cambiado, ningún handler se dispara.

- **Plantillas Jinja2 con `groups` y `hostvars`**: La plantilla del balanceador (`nginx.conf.j2`) demuestra el poder de las plantillas dinámicas — construye la lista de backends consultando directamente el inventario de Ansible, sin hardcodear IPs.

- **`become: true` a nivel de play**: Declarar `become: true` en el play (en `site.yml`) aplica la escalada de privilegios a **todas** las tareas del rol, evitando repetirlo en cada tarea individual.

---

## 📚 Referencias

- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — Módulo `mysql_db`](https://docs.ansible.com/ansible/latest/collections/community/mysql/mysql_db_module.html)
- [Ansible Docs — Módulo `mysql_user`](https://docs.ansible.com/ansible/latest/collections/community/mysql/mysql_user_module.html)
- [Ansible Docs — Módulo `template`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Ansible Docs — Variables especiales (`groups`, `hostvars`)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Ansible Docs — Plantillas Jinja2](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
