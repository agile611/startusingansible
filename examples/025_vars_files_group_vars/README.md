# 📋 Ejemplo 025 — `vars_files_group_vars`: Variables centralizadas con `group_vars`

## 🧭 Descripción general

Este ejemplo introduce el concepto más importante de organización de variables en Ansible a escala real: el directorio **`group_vars/`**. Hasta el ejemplo 024, las variables se pasaban como parámetros inline en los playbooks de componente (`database.yml`, `webserver.yml`), lo que significaba que las credenciales de base de datos estaban duplicadas en múltiples ficheros y acopladas a los playbooks. En este ejemplo, todas las variables se centralizan en un único fichero `group_vars/all`, que Ansible carga automáticamente para todos los hosts antes de ejecutar cualquier playbook.

El resultado es una arquitectura de variables limpia y desacoplada: los playbooks de componente (`database.yml`, `webserver.yml`, `loadbalancer.yml`) ya no contienen ningún valor concreto — solo declaran qué roles ejecutar. Toda la configuración vive en `group_vars/all`. Además, la plantilla `demo.wsgi.j2` incorpora la mejora del ejemplo 024 y añade `{{ groups.database[0] }}` como hostname de la base de datos, cerrando el ciclo de "inventario como única fuente de verdad".

---

## 🗂️ Estructura del proyecto

```
025_vars_files_group_vars/
├── site.yml                          # ⭐ import_playbook (en lugar de include)
├── control.yml
├── database.yml                      # ⭐ Variables leídas de group_vars/all
├── webserver.yml                     # ⭐ Sin variables inline — roles limpios
├── loadbalancer.yml
├── group_vars/
│   └── all                           # ⭐ NOVEDAD PRINCIPAL: fuente única de verdad
├── playbooks/
│   ├── stack_status.yml
│   └── stack_restart.yml
└── roles/
    ├── control/
    │   └── tasks/main.yml
    ├── mysql/
    │   ├── tasks/main.yml            # ⚠️ chmod 777 /etc/mysql/my.cnf (nuevo)
    │   ├── handlers/main.yml
    │   └── defaults/main.yml         # ⭐ Todos los defaults comentados
    ├── apache2/
    │   ├── tasks/main.yml            # libapache2-mod-wsgi-py3 (vuelve a Python 3)
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── demo.wsgi.j2          # ⭐ groups.database[0] como hostname de BD
    └── nginx/
        ├── tasks/main.yml            # ⭐ de-activate default explícito
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml         # ⭐ Todos los defaults comentados
```

---

## 📋 Fichero `hosts` — El inventario

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

| **Grupo** | **IP** | **Rol(es) asignado(s)** |
|---|---|---|
| `[database]` | `192.168.11.20` | `mysql` |
| `[loadbalancer]` | `192.168.11.30` | `nginx` |
| `[webserver]` | `192.168.11.40` | `apache2` + `demo_app` |

---

## ⭐ NOVEDAD PRINCIPAL: `group_vars/all`

### ¿Qué es `group_vars/`?

`group_vars/` es un directorio especial que Ansible busca automáticamente junto al fichero `hosts` (o dentro del directorio del proyecto). Cuando Ansible ejecuta un playbook, carga los ficheros de `group_vars/` **antes de ejecutar ninguna tarea**, sin que el playbook tenga que declarar nada. Las reglas de carga son:

- `group_vars/all` → se carga para **todos** los hosts del inventario
- `group_vars/<nombre_grupo>` → se carga solo para los hosts del grupo `<nombre_grupo>`
- `group_vars/<nombre_host>` → se carga solo para ese host específico (también llamado `host_vars/`)

En este ejemplo solo existe `group_vars/all`, que centraliza todas las variables compartidas del proyecto.

### `group_vars/all`

```yaml
---
#DB from role mysql
db_name: maykadb
db_user: mayka_user
db_pass: mayka_pass
db_user_host: localhost

#nginx loadbalancer configuration
sites:
  myappmayka:
    frontend: 80
    backend: 80
```

Este único fichero define **todo** lo que varía entre despliegues:

| **Variable** | **Valor** | **Usada por** |
|---|---|---|
| `db_name` | `maykadb` | Rol `mysql` (crear BD) + plantilla `demo.wsgi.j2` (URI de conexión) |
| `db_user` | `mayka_user` | Rol `mysql` (crear usuario) + plantilla `demo.wsgi.j2` |
| `db_pass` | `mayka_pass` | Rol `mysql` (contraseña) + plantilla `demo.wsgi.j2` |
| `db_user_host` | `localhost` | Rol `mysql` (permisos del usuario) |
| `sites` | `{myappmayka: {frontend: 80, backend: 80}}` | Rol `nginx` (configuración de sitios) |

El nombre del sitio Nginx es ahora `myappmayka`, coherente con el nombre de la base de datos `maykadb` y el usuario `mayka_user`. Esto sugiere que el ejemplo representa el despliegue de una aplicación específica ("mayka"), y que todos los nombres de recursos son consistentes entre sí.

### Flujo de variables: de `group_vars/all` a los roles

```
group_vars/all
  ├── db_name: maykadb ──────────────────────────────────────────────────────┐
  ├── db_user: mayka_user ────────────────────────────────────────────────── │ ──┐
  ├── db_pass: mayka_pass ────────────────────────────────────────────────── │ ──┤
  ├── db_user_host: localhost ─────────────────────────────────────────────── │ ──┤
  └── sites: {myappmayka: ...} ────────────────────────────────────────────── │ ──┤──┐
                                                                              │   │  │
  database.yml                                                                │   │  │
    └── role: mysql                                                           │   │  │
          db_user_name: "{{ db_user }}"  ◄──────────────────────────────────┘   │  │
          db_user_pass: "{{ db_pass }}"  ◄──────────────────────────────────────┘  │
          (db_name, db_user_host leídos directamente de group_vars/all)            │
                                                                                    │
  webserver.yml                                                                     │
    └── role: demo_app                                                              │
          └── demo.wsgi.j2                                                          │
                └── DATABASE_URI = mysql://{{ db_user }}:{{ db_pass }}             │
                                         @{{ groups.database[0] }}/{{ db_name }}   │
                    (todas las variables resueltas desde group_vars/all)            │
                                                                                    │
  loadbalancer.yml                                                                  │
    └── role: nginx                                                                 │
          └── sites: {{ sites }}  ◄─────────────────────────────────────────────────┘
                (myappmayka con frontend:80 y backend:80)
```

---

## 📄 Playbooks de componente — Limpios y desacoplados

### `site.yml` — ⭐ `import_playbook` en lugar de `include`

```yaml
---
- import_playbook: control.yml
- import_playbook: database.yml
- import_playbook: webserver.yml
- import_playbook: loadbalancer.yml
- import_playbook: playbooks/stack_status.yml
```

La diferencia entre `import_playbook` e `include` es importante:

| **Directiva** | **Cuándo se procesa** | **Soporte de tags** | **Uso recomendado** |
|---|---|---|---|
| `include` (deprecado) | En tiempo de ejecución (dinámico) | Limitado | Ejemplos anteriores |
| `import_playbook` | En tiempo de parseo (estático) | ✅ Completo | ⭐ Este ejemplo en adelante |

Con `import_playbook`, Ansible carga y valida todos los playbooks incluidos **antes de ejecutar ninguna tarea**. Esto permite usar `--tags` y `--list-tasks` sobre el `site.yml` completo, lo que no era posible con `include`.

### `database.yml` — Variables leídas de `group_vars/all`

```yaml
---
- hosts: database
  become: true
  roles:
    - role: mysql
      db_user_name: "{{ db_user }}"
      db_user_pass: "{{ db_pass }}"
      db_user_host: '%'
```

Comparado con el ejemplo 024 (`db_name: demo, db_user_name: demo, db_user_pass: demo`), este playbook ya no contiene valores hardcodeados. Las variables `{{ db_user }}` y `{{ db_pass }}` se resuelven desde `group_vars/all` en tiempo de ejecución. El rol recibe `db_user_name` y `db_user_pass` como parámetros inline (para mapear los nombres de variable del grupo al nombre de parámetro del rol), mientras que `db_name` y `db_user_host` se leen directamente de `group_vars/all` por el rol.

> **Nota sobre `db_user_host: '%'`:** El playbook sobreescribe `db_user_host` a `'%'` (cualquier host) en lugar de usar el valor `localhost` de `group_vars/all`. Esto es necesario para que el webserver (`192.168.11.40`) pueda conectarse a MySQL en el servidor de base de datos (`192.168.11.20`).

### `webserver.yml` — El playbook más limpio de la serie

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

Este es el playbook más limpio de todos los ejemplos de la serie. No contiene ninguna variable — ni inline ni `vars_files`. Los roles `apache2` y `demo_app` obtienen todas las variables que necesitan directamente de `group_vars/all`. Esto es el objetivo final de la centralización de variables: los playbooks de componente solo declaran *qué* hacer, no *con qué valores*.

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
```

El rol `nginx` obtiene el diccionario `sites` directamente de `group_vars/all` — sin parámetros inline, sin `vars_files`.

### `control.yml`

```yaml
---
- hosts: control
  become: true
  roles:
    - control
```

---

## 🛠️ Los Roles en detalle

### 🔧 Rol `control`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Sin cambios respecto a ejemplos anteriores.

---

### 🗄️ Rol `mysql` — ⚠️ `chmod 777` y defaults comentados

#### `roles/mysql/defaults/main.yml`

```yaml
---
#db_name: myapp
#db_user_name: dbuser
#db_user_pass: dbpass
#db_user_host: localhost
```

Todos los defaults están **comentados**. Esto es una declaración explícita de que este rol ya no tiene valores por defecto — todas las variables deben venir de `group_vars/all` o de parámetros inline del playbook. Si se ejecuta el rol sin proporcionar estas variables, Ansible fallará con un error de variable indefinida, lo cual es el comportamiento correcto: fuerza al operador a configurar explícitamente las credenciales.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: chmod 777 /etc/mysql/my.cnf
  command: chmod 777 /etc/mysql/my.cnf
  notify: restart mysql

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create database
  mysql_db: name={{ db_name }} state=present

- name: create user
  mysql_user: name={{ db_user_name }} password={{ db_user_pass }} priv={{ db_name }}.*:ALL
              host='{{ db_user_host }}' state=present
```

La novedad respecto al ejemplo 024 es la tarea `chmod 777 /etc/mysql/my.cnf`:

```yaml
- name: chmod 777 /etc/mysql/my.cnf
  command: chmod 777 /etc/mysql/my.cnf
  notify: restart mysql
```

> ⚠️ **Nota de seguridad:** `chmod 777` sobre `/etc/mysql/my.cnf` da permisos de lectura, escritura y ejecución a todos los usuarios del sistema. Esto es una práctica de laboratorio/desarrollo para evitar errores de permisos con el módulo `lineinfile` en entornos Vagrant. **No debe usarse en producción** — el fichero de configuración de MySQL debería tener permisos `640` (root:mysql) como máximo.

El rol vuelve a usar `{{ ansible_eth0.ipv4.address }}` para el `bind-address` (en lugar de `groups.database[0]` del ejemplo 024), lo que indica que este ejemplo prioriza la demostración del patrón `group_vars` sobre la consistencia del `bind-address`.

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

---

### 🌐 Rol `apache2` — Vuelve a `libapache2-mod-wsgi-py3`

```yaml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

Vuelve a instalar `libapache2-mod-wsgi-py3` (Python 3), corrigiendo la regresión del ejemplo 024 que usaba `libapache2-mod-wsgi` (Python 2).

---

### 🚀 Rol `demo_app` — ⭐ `demo.wsgi.j2` con `groups.database[0]`

#### `roles/demo_app/tasks/main.yml`

```yaml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: copy demo app source
  copy: src=demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy demo.wsgi
  template: src=demo.wsgi.j2 dest=/var/www/demo/demo.wsgi mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf
        dest=/etc/apache2/sites-enabled/demo.conf
        state=link
  notify: restart apache2
```

#### `roles/demo_app/templates/demo.wsgi.j2` — ⭐ La plantilla más completa de la serie

```jinja2
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})

import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@{{ groups.database[0] }}/{{ db_name }}'

import sys
sys.path.insert(0, '/var/www/demo')

from demo import app as application
```

Esta es la versión más completa de la plantilla WSGI en toda la serie. La diferencia clave respecto al ejemplo 024 es el hostname de la base de datos:

| **Ejemplo** | **Hostname en `DATABASE_URI`** | **Fuente del dato** |
|---|---|---|
| 024 | `db01` (hardcodeado) | Ninguna — valor literal en la plantilla |
| **025** | `{{ groups.database[0] }}` | ⭐ Inventario (`hosts`) |

Con el inventario proporcionado, `{{ groups.database[0] }}` resuelve a `192.168.11.20`. El fichero generado en el servidor contiene:

```python
os.environ['DATABASE_URI'] = 'mysql://mayka_user:mayka_pass@192.168.11.20/maykadb'
```

Ahora **ningún valor está hardcodeado** en la plantilla. Todas las variables provienen de `group_vars/all` y del inventario:

| **Placeholder en la plantilla** | **Fuente** | **Valor resuelto** |
|---|---|---|
| `{{ db_user }}` | `group_vars/all` | `mayka_user` |
| `{{ db_pass }}` | `group_vars/all` | `mayka_pass` |
| `{{ groups.database[0] }}` | Inventario (`hosts`) | `192.168.11.20` |
| `{{ db_name }}` | `group_vars/all` | `maykadb` |

---

### ⚖️ Rol `nginx` — ⭐ `de-activate default` explícito y defaults comentados

#### `roles/nginx/defaults/main.yml`

```yaml
#---
#sites:
#  myapp:
#    frontend: 80
#    backend: 80
```

Al igual que en el rol `mysql`, todos los defaults están comentados. El diccionario `sites` ahora viene exclusivamente de `group_vars/all`.

#### `roles/nginx/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-httplib2

- name: install nginx
  apt: name=nginx state=present update_cache=yes

- name: configure nginx sites
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/{{ item.key }} mode=0644
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: get active sites
  shell: ls /etc/nginx/sites-enabled
  register: result

- name: de-activate default
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: de-activate sites
  file: path=/etc/nginx/sites-enabled/{{ item }} state=absent
  with_items: "{{ result.stdout_lines }}"
  when: item not in sites
  notify: restart nginx

- name: activate nginx sites
  file: src=/etc/nginx/sites-available/{{ item.key }}
        dest=/etc/nginx/sites-enabled/{{ item.key }}
        state=link
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

La novedad respecto al ejemplo 023 es la tarea `de-activate default`:

```yaml
- name: de-activate default
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx
```

Esta tarea elimina explícitamente el sitio `default` de Nginx (el que viene preinstalado con el paquete `nginx`). En los ejemplos anteriores, el sitio `default` se eliminaba implícitamente por el patrón `when: item not in sites` — si `default` no estaba en el diccionario `sites`, se eliminaba en el bucle. En este ejemplo se hace explícitamente, lo que es más claro y robusto: garantiza que el sitio `default` siempre se elimina, independientemente de si `ls /etc/nginx/sites-enabled` lo lista o no.

#### `roles/nginx/templates/nginx.conf.j2`

```jinja2
upstream {{ item.key }} {
{% for server in groups.webserver %}
    server {{ server }}:{{ item.value.backend }};
{% endfor %}
}

server {
    listen {{ item.value.frontend }};

    location / {
        proxy_pass http://{{ item.key }};
    }
}
```

Con los valores de `group_vars/all` (`sites.myappmayka`) y el inventario, genera:

```nginx
upstream myappmayka {
    server 192.168.11.40:80;
}

server {
    listen 80;

    location / {
        proxy_pass http://myappmayka;
    }
}
```

---

## 📄 Playbooks de mantenimiento

### `playbooks/stack_restart.yml`

```yaml
---
# Bring stack down
- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=stopped
    - wait_for: port=80 state=drained

- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=stopped
    - wait_for: port=80 state=stopped

# Restart mysql
- hosts: database
  become: true
  tasks:
    - service: name=mysql state=restarted
    - wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 state=started

# Bring stack up
- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=started
    - wait_for: port=80

- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=started
    - wait_for: port=80
```

| **Fase** | **Nodo** | **Acción** | **Condición de avance** |
|---|---|---|---|
| 1 | `loadbalancer` | Para Nginx | Puerto 80 drenado |
| 2 | `webserver` | Para Apache | Puerto 80 cerrado |
| 3 | `database` | Reinicia MySQL | Puerto 3306 activo |
| 4 | `webserver` | Arranca Apache | Puerto 80 activo |
| 5 | `loadbalancer` | Arranca Nginx | Puerto 80 activo |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### `playbooks/stack_status.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: verify nginx service
      command: service nginx status
    - name: verify nginx is listening on 80
      wait_for: port=80 timeout=1

- hosts: webserver
  become: true
  tasks:
    - name: verify apache2 service
      command: service apache2 status
    - name: verify apache2 is listening on 80
      wait_for: port=80 timeout=1

- hosts: database
  become: true
  tasks:
    - name: verify mysql service
      command: service mysql status
    - name: verify mysql is listening on 3306
      wait_for: port=3306 timeout=1

- hosts: control
  tasks:
    - name: verify end-to-end index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_index

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{lb_index.results}}"

    - name: verify end-to-end db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{lb_db.results}}"

- hosts: loadbalancer
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_index

    # Verificación de contenido comentada (simplificada)

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_db
```

La verificación de contenido del backend (`fail` con `item.item`) está comentada en este ejemplo, simplificando la validación para centrarse en la demostración del patrón `group_vars`. Las verificaciones activas son:

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer:80` | `"Hello, from sunny"` en la respuesta |
| End-to-end DB | `control` | `loadbalancer:80/db` | `"Database Connected from"` en la respuesta |
| Backend index | `loadbalancer` | cada `webserver:80` | Solo que responde (sin validar contenido) |
| Backend DB | `loadbalancer` | cada `webserver:80/db` | Solo que responde (sin validar contenido) |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🚀 Comandos de ejecución

### Despliegue completo + verificación automática

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

### Despliegue de componentes individuales

```bash
ansible-playbook -i hosts -u vagrant control.yml
ansible-playbook -i hosts -u vagrant database.yml
ansible-playbook -i hosts -u vagrant webserver.yml
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### Cambiar las credenciales de base de datos para un entorno diferente

Con el patrón `group_vars`, cambiar las credenciales para un entorno de staging o producción es tan simple como modificar `group_vars/all` o sobreescribir con `-e`:

```bash
# Sobreescribir variables de group_vars/all en tiempo de ejecución
ansible-playbook -i hosts -u vagrant site.yml \
  -e "db_name=proddb db_user=produser db_pass=s3cur3pass"
```

### Listar todas las tareas antes de ejecutar (gracias a `import_playbook`)

```bash
ansible-playbook -i hosts -u vagrant site.yml --list-tasks
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **024** | **025** |
|---|---|---|
| **Ubicación de variables** | Inline en playbooks (`database.yml`, `webserver.yml`) | ⭐ `group_vars/all` (fuente única de verdad) |
| **Playbooks de componente** | Contienen valores hardcodeados | ⭐ Solo declaran roles — sin valores |
| **`demo.wsgi.j2` hostname BD** | `db01` (hardcodeado) | ⭐ `{{ groups.database[0] }}` (del inventario) |
| **Defaults de roles** | Valores por defecto activos | ⭐ Comentados (fuerzan configuración explícita) |
| **`site.yml`** | `include` (deprecado) | ⭐ `import_playbook` (estático, soporta tags) |
| **`mod_wsgi` de Apache** | `libapache2-mod-wsgi` (Python 2) | ⭐ `libapache2-mod-wsgi-py3` (Python 3) |
| **Eliminar sitio `default` Nginx** | Implícito (vía bucle `when: not in`) | ⭐ Explícito (`de-activate default`) |
| **Credenciales BD** | `demo/demo/demo` | `maykadb/mayka_user/mayka_pass` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`group_vars/` como fuente única de verdad**: El directorio `group_vars/` es el mecanismo estándar de Ansible para centralizar variables. Ansible lo carga automáticamente — no requiere ninguna declaración en los playbooks. El fichero `group_vars/all` es especial: se aplica a todos los hosts del inventario, independientemente del grupo al que pertenezcan.

- **Separación de configuración y lógica**: Los playbooks de componente (`database.yml`, `webserver.yml`) solo declaran *qué roles ejecutar*. Los valores concretos viven en `group_vars/all`. Esta separación es el principio de diseño más importante para proyectos Ansible mantenibles: cambiar las credenciales de base de datos solo requiere editar `group_vars/all`, sin tocar ningún playbook.

- **`import_playbook` vs `include`**: `import_playbook` procesa los playbooks incluidos en tiempo de parseo (estático), lo que permite usar `--tags`, `--list-tasks` y `--check` sobre el `site.yml` completo. `include` (deprecado) los procesaba en tiempo de ejecución, limitando estas capacidades.

- **Defaults de rol comentados como contrato explícito**: Comentar los defaults de un rol es una forma de documentar que el rol *requiere* que las variables sean proporcionadas externamente. Es preferible a dejar defaults incorrectos que podrían usarse accidentalmente en producción.

- **`groups.database[0]` en plantillas**: Usar `groups.<grupo>[0]` en plantillas Jinja2 permite que la dirección de un servicio (como la IP del servidor de base de datos) se derive automáticamente del inventario. Esto garantiza que la cadena de conexión de la aplicación siempre apunte al servidor correcto, sin duplicar la IP en múltiples ficheros.

- **Precedencia de variables en Ansible**: Cuando la misma variable se define en múltiples lugares, Ansible aplica un orden de precedencia. En este ejemplo: los parámetros inline del rol (`db_user_name: "{{ db_user }}"` en `database.yml`) tienen mayor precedencia que `group_vars/all`, que a su vez tiene mayor precedencia que los `defaults` del rol.

---

## 📚 Referencias

- [Ansible Docs — `group_vars` y `host_vars`](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables)
- [Ansible Docs — Variable precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Ansible Docs — `import_playbook`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/import_playbook_module.html)
- [Ansible Docs — `template` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Magic variables (`groups`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#information-about-ansible-magic-variables)
