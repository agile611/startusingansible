# 📋 Ejemplo 024 — `continued`: Plantilla WSGI dinámica e inventario como fuente de verdad

## 🧭 Descripción general

Este ejemplo introduce dos novedades fundamentales respecto al ejemplo 023. La primera y más importante es la **plantilla `demo.wsgi.j2`**: en lugar de copiar un fichero `.wsgi` estático, Ansible genera el fichero de arranque WSGI de la aplicación Flask dinámicamente, inyectando las credenciales de base de datos (`db_user`, `db_pass`, `db_name`) como variables de entorno en tiempo de despliegue. Esto elimina por completo las credenciales hardcodeadas del código fuente de la aplicación.

La segunda novedad está en el rol `mysql`: el `bind-address` ya no usa `{{ ansible_eth0.ipv4.address }}` (un Ansible Fact que requiere que el nodo reporte su propia IP), sino `{{ groups.database[0] }}` — la IP del primer nodo del grupo `[database]` del inventario. Esto convierte el **inventario en la única fuente de verdad** para la dirección del servidor de base de datos, tanto para la configuración de MySQL como para la cadena de conexión de la aplicación.

---

## 🗂️ Estructura del proyecto

```
024_continued/
├── site.yml                          # Orquestador maestro (despliegue + verificación)
├── control.yml                       # Playbook del nodo de control
├── database.yml                      # BD: demo/demo/demo con host '%'
├── webserver.yml                     # ⭐ Variables inline: db_user, db_pass, db_name → demo_app
├── loadbalancer.yml                  # Playbook del balanceador de carga
├── playbooks/
│   ├── hostname.yml                  # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml             # Reinicio ordenado del stack
│   └── stack_status.yml              # ⭐ Verificación completa con item.item
└── roles/
    ├── control/
    │   └── tasks/main.yml            # curl + python-httplib2
    ├── mysql/
    │   ├── tasks/main.yml            # ⭐ NOVEDAD: bind-address = groups.database[0]
    │   ├── handlers/main.yml
    │   └── defaults/main.yml
    ├── apache2/
    │   ├── tasks/main.yml            # ⚠️ libapache2-mod-wsgi (sin -py3)
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml            # ⭐ NOVEDAD: template demo.wsgi.j2
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── templates/
    │   │   └── demo.wsgi.j2          # ⭐ NOVEDAD PRINCIPAL: DATABASE_URI dinámica
    │   └── files/
    └── nginx/
        ├── tasks/main.yml            # Patrón selective removal (heredado de 023)
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml         # sites: myapp (vuelve al nombre sin timestamp)
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
| `[database]` | `192.168.11.20` | `mysql` (credenciales `demo/demo/demo`) |
| `[loadbalancer]` | `192.168.11.30` | `nginx` (sitio `myapp`) |
| `[webserver]` | `192.168.11.40` | `apache2` + `demo_app` |

---

## ⭐ El orquestador maestro: `site.yml`

```yaml
---
- include: control.yml
- include: database.yml
- include: webserver.yml
- include: loadbalancer.yml
- include: playbooks/stack_status.yml
```

El `site.yml` mantiene el patrón de orquestación atómica: el despliegue completo incluye la verificación automática del stack al final. Si `stack_status.yml` falla, el playbook reporta error y el operador sabe que el despliegue no está en estado correcto.

---

## 📄 Playbooks de componente

### `control.yml`

```yaml
---
- hosts: control
  become: true
  roles:
    - control
```

### `database.yml`

```yaml
---
- hosts: database
  become: true
  roles:
    - { role: mysql, db_name: demo, db_user_name: demo, db_user_pass: demo, db_user_host: '%' }
```

Crea la base de datos `demo` y el usuario `demo` con contraseña `demo`, con acceso desde cualquier host (`%`). Estas mismas credenciales se pasan al rol `demo_app` en `webserver.yml` para construir la cadena de conexión.

### `webserver.yml` — ⭐ Variables inline para la plantilla WSGI

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - { role: demo_app, db_user: demo, db_pass: demo, db_name: demo }
```

Esta es la clave del flujo de datos del ejemplo: las variables `db_user`, `db_pass` y `db_name` se pasan inline al rol `demo_app`, que las usa para renderizar la plantilla `demo.wsgi.j2`. Así, la cadena de conexión a la base de datos se construye en tiempo de despliegue con los valores correctos, sin que la aplicación necesite conocerlos de antemano.

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
```

---

## 🛠️ Los Roles en detalle

### 🔧 Rol `control` — Herramientas de red

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala `curl` para pruebas HTTP manuales y `python-httplib2` como dependencia del módulo `uri` de Ansible.

---

### 🗄️ Rol `mysql` — ⭐ NOVEDAD: `groups.database[0]` como `bind-address`

#### `roles/mysql/defaults/main.yml`

```yaml
---
db_name: myapp
db_user_name: dbuser
db_user_pass: dbpass
db_user_host: localhost
```

Los defaults documentan la interfaz del rol. En este ejemplo son sobreescritos por las variables inline de `database.yml`.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb
    - mysql-server

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ groups.database[0] }}"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create database
  mysql_db: name={{ db_name }} state=present

- name: create user
  mysql_user: name={{ db_user_name }} password={{ db_user_pass }} priv={{ db_name }}.*:ALL
              host='{{ db_user_host }}' state=present
```

#### La novedad clave: `groups.database[0]` vs `ansible_eth0.ipv4.address`

Esta es la diferencia más importante respecto al ejemplo 023 en el rol `mysql`:

| **Aspecto** | **Ejemplo 023** | **Ejemplo 024** |
|---|---|---|
| **Expresión usada** | `{{ ansible_eth0.ipv4.address }}` | `{{ groups.database[0] }}` |
| **Fuente del dato** | Ansible Fact del nodo remoto | Inventario (`hosts`) |
| **Requiere `gather_facts`** | ✅ Sí | ❌ No |
| **Fuente de verdad** | El propio servidor | El inventario centralizado |
| **Valor con este inventario** | `192.168.11.20` (reportado por el nodo) | `192.168.11.20` (leído del inventario) |

`groups.database[0]` accede al **primer elemento de la lista del grupo `[database]`** del inventario. Con el inventario proporcionado, `groups.database` es la lista `['192.168.11.20']`, por lo que `groups.database[0]` resuelve a `192.168.11.20`.

El resultado práctico es el mismo: MySQL escucha en `192.168.11.20` en lugar de `0.0.0.0`. Pero la filosofía es diferente: el inventario es la única fuente de verdad para las IPs, no los Facts del sistema. Esto hace el rol más predecible y menos dependiente de la configuración de red del servidor.

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

---

### 🌐 Rol `apache2`

```yaml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

> ⚠️ **Nota importante:** Este rol instala `libapache2-mod-wsgi` (sin el sufijo `-py3`), que es el módulo WSGI para Python 2. Los ejemplos anteriores usaban `libapache2-mod-wsgi-py3`. Esto puede causar problemas si la aplicación Flask está escrita para Python 3. Es un detalle a tener en cuenta si el despliegue falla con errores de importación de módulos Python.

---

### 🚀 Rol `demo_app` — ⭐ NOVEDAD PRINCIPAL: plantilla `demo.wsgi.j2`

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

La diferencia clave respecto al ejemplo 023 está en la tarea `copy demo.wsgi`, que en este ejemplo es un `template` en lugar de un `copy`:

| **Tarea** | **Ejemplo 023** | **Ejemplo 024** |
|---|---|---|
| Despliegue del fichero WSGI | `copy: src=demo.wsgi` (fichero estático) | ⭐ `template: src=demo.wsgi.j2` (renderizado dinámico) |
| Credenciales en el WSGI | Hardcodeadas en el fichero fuente | ⭐ Inyectadas como variables Ansible |

#### `roles/demo_app/templates/demo.wsgi.j2` — ⭐ El fichero más importante del ejemplo

```jinja2
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})

import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@db01/{{ db_name }}'

import sys
sys.path.insert(0, '/var/www/demo')

from demo import app as application
```

Este fichero es el punto de entrada WSGI de la aplicación Flask. Apache2 con `mod_wsgi` lo ejecuta para arrancar la aplicación. Línea por línea:

**Línea 1-2 — Activación del virtualenv:**
```python
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})
```
Activa el entorno virtual Python creado por `pip` en `/var/www/demo/.venv`. Esto garantiza que la aplicación usa las dependencias instaladas en el virtualenv (Flask, MySQL connector, etc.) y no las del sistema.

**Línea 4-5 — Inyección de la cadena de conexión como variable de entorno:**
```python
import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@db01/{{ db_name }}'
```
Esta es la línea que Ansible renderiza con las variables del playbook. Con los valores de `webserver.yml` (`db_user: demo`, `db_pass: demo`, `db_name: demo`), el fichero generado en el servidor contiene:
```python
os.environ['DATABASE_URI'] = 'mysql://demo:demo@db01/demo'
```
La aplicación Flask lee `DATABASE_URI` del entorno para conectarse a la base de datos. El hostname `db01` debe estar resuelto en `/etc/hosts` o DNS del servidor web.

**Línea 7-8 — Configuración del path de Python:**
```python
import sys
sys.path.insert(0, '/var/www/demo')
```
Añade el directorio de la aplicación al path de Python para que `from demo import app` funcione correctamente.

**Línea 10 — Importación de la aplicación Flask:**
```python
from demo import app as application
```
Importa el objeto `app` de Flask y lo expone como `application`, que es el nombre que `mod_wsgi` espera encontrar en el fichero WSGI.

#### Flujo completo de datos de credenciales

```
hosts (inventario)
  └── database.yml
        └── role: mysql
              db_name: demo
              db_user_name: demo   ─────────────────────────────────────────┐
              db_user_pass: demo                                             │
              db_user_host: '%'                                              │
                                                                             │
webserver.yml                                                                │
  └── role: demo_app                                                         │
        db_user: demo  ─────────────────────────────────────────────────────┤
        db_pass: demo  ─────────────────────────────────────────────────────┤
        db_name: demo  ─────────────────────────────────────────────────────┤
              │                                                              │
              ▼                                                              │
        demo.wsgi.j2 (template)                                             │
              │                                                              │
              ▼ (renderizado por Ansible)                                    │
        demo.wsgi (fichero en /var/www/demo/)                               │
              │                                                              │
              ▼                                                              │
        os.environ['DATABASE_URI'] = 'mysql://demo:demo@db01/demo'          │
              │                                                              │
              ▼                                                              │
        Flask app ──── conecta a ────► MySQL en 192.168.11.20 ◄────────────┘
                                        (bind-address = groups.database[0])
```

---

### ⚖️ Rol `nginx` — Patrón selective removal (heredado de 023)

#### `roles/nginx/defaults/main.yml`

```yaml
---
sites:
  myapp:
    frontend: 80
    backend: 80
```

El nombre del sitio vuelve a `myapp` (sin timestamp), simplificando el nombre respecto al ejemplo 023 (`myapp20211216`).

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
  register: active

- name: de-activate sites
  file: path=/etc/nginx/sites-enabled/{{ item }} state=absent
  with_items: "{{ active.stdout_lines }}"
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

El patrón de eliminación selectiva se mantiene idéntico al ejemplo 023. La variable de registro ahora se llama `active` (en lugar de `result`), lo que hace el código más legible — `active.stdout_lines` comunica claramente que contiene los sitios actualmente activos.

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

Con los valores del diccionario `sites` y el inventario, genera:

```nginx
upstream myapp {
    server 192.168.11.40:80;
}

server {
    listen 80;

    location / {
        proxy_pass http://myapp;
    }
}
```

#### `roles/nginx/handlers/main.yml`

```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
```

---

## 📄 Playbooks de mantenimiento

### `playbooks/hostname.yml`

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

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

El reinicio sigue el orden correcto para evitar errores de conexión: primero se para el tráfico entrante (Nginx), luego la capa de aplicación (Apache), se reinicia la base de datos, y se levanta todo en orden inverso.

| **Fase** | **Nodo** | **Acción** | **Condición de avance** |
|---|---|---|---|
| 1 | `loadbalancer` | Para Nginx | Puerto 80 drenado (sin conexiones activas) |
| 2 | `webserver` | Para Apache | Puerto 80 cerrado |
| 3 | `database` | Reinicia MySQL | Puerto 3306 activo en IP real (via Fact) |
| 4 | `webserver` | Arranca Apache | Puerto 80 activo |
| 5 | `loadbalancer` | Arranca Nginx | Puerto 80 activo |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

### `playbooks/stack_status.yml` — ⭐ Verificación completa con `item.item`

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
      with_items: groups.loadbalancer
      register: lb_index

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{lb_index.results}}"

    - name: verify end-to-end db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: groups.loadbalancer
      register: lb_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{lb_db.results}}"

- hosts: loadbalancer
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      with_items: groups.webserver
      register: app_index

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny {{item.item}}!' not in item.content"
      with_items: "{{app_index.results}}"

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: groups.webserver
      register: app_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from {{item.item}}!' not in item.content"
      with_items: "{{app_db.results}}"
```

#### La novedad: verificación directa del backend con `item.item`

Este `stack_status.yml` es el más completo de la serie. La diferencia respecto al ejemplo 023 es que las tareas de verificación del backend desde el loadbalancer están **completamente activas** y usan el patrón `item.item` para validar el contenido de la respuesta:

```yaml
- fail: msg="index failed to return content"
  when: "'Hello, from sunny {{item.item}}!' not in item.content"
  with_items: "{{app_index.results}}"
```

Cuando se usa `register` con `with_items`, cada elemento de `results` tiene esta estructura:

```json
{
  "item": "192.168.11.40",
  "content": "Hello, from sunny 192.168.11.40!",
  "status": 200,
  ...
}
```

- `item.item` → la IP del webserver que se usó en la petición HTTP (`192.168.11.40`)
- `item.content` → el cuerpo de la respuesta HTTP

La condición `when: "'Hello, from sunny {{item.item}}!' not in item.content"` verifica que la respuesta del webserver con IP `192.168.11.40` contiene exactamente `Hello, from sunny 192.168.11.40!`. Esto garantiza que **cada webserver responde con su propia IP**, detectando casos donde el balanceador podría estar enviando todas las peticiones al mismo backend.

#### Verificación en cuatro capas

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer:80` | `"Hello, from sunny"` en la respuesta |
| End-to-end DB | `control` | `loadbalancer:80/db` | `"Database Connected from"` en la respuesta |
| Backend index | `loadbalancer` | cada `webserver:80` | `"Hello, from sunny <IP_webserver>!"` exacto |
| Backend DB | `loadbalancer` | cada `webserver:80/db` | `"Database Connected from <IP_webserver>!"` exacto |

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
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### Despliegue con credenciales de base de datos diferentes

```bash
# Sobreescribir las credenciales de BD en tiempo de ejecución
ansible-playbook -i hosts -u vagrant site.yml \
  -e "db_name=produccion db_user_name=produser db_user_pass=s3cur3pass"
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **023** | **024** |
|---|---|---|
| Fichero WSGI | `copy` estático (credenciales hardcodeadas) | ⭐ `template` dinámico (`demo.wsgi.j2`) |
| Credenciales en WSGI | Fijas en el fichero fuente | ⭐ Variables Ansible inyectadas en tiempo de despliegue |
| `bind-address` MySQL | `{{ ansible_eth0.ipv4.address }}` (Fact del nodo) | ⭐ `{{ groups.database[0] }}` (inventario como fuente de verdad) |
| Nombre del sitio Nginx | `myapp20211216` (con timestamp) | `myapp` (simplificado) |
| Variable de registro nginx | `result` | `active` (más descriptivo) |
| Verificación backend en `stack_status` | Comentada | ⭐ Activa con `item.item` |
| `mod_wsgi` de Apache | `libapache2-mod-wsgi-py3` | `libapache2-mod-wsgi` (Python 2) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Plantillas para ficheros de configuración con secretos**: El módulo `template` de Ansible es la forma correcta de gestionar ficheros que contienen credenciales, URLs de conexión o cualquier valor que varía entre entornos. La plantilla `demo.wsgi.j2` es el patrón canónico: el fichero fuente en el repositorio no contiene ningún secreto, y los valores reales se inyectan en el momento del despliegue.

- **`groups.database[0]` como referencia de inventario**: Usar `groups.<nombre_grupo>[índice]` para referenciar la IP de un nodo desde otro nodo es un patrón muy común en Ansible. Permite que la configuración de un servicio (MySQL `bind-address`) y la cadena de conexión de la aplicación (`DATABASE_URI`) sean consistentes con el inventario, sin duplicar IPs en múltiples ficheros.

- **`item.item` en resultados de `register` + `with_items`**: Cuando se combina `register` con `with_items`, cada elemento de `results` guarda en `item.item` el valor original del iterador. Esto permite construir condiciones de verificación que relacionan la petición (la IP del servidor al que se hizo) con la respuesta esperada (que debe contener esa misma IP).

- **Variables de entorno como interfaz entre Ansible y la aplicación**: El patrón `os.environ['DATABASE_URI'] = '...'` en el fichero WSGI es la forma estándar de pasar configuración a aplicaciones Python sin modificar el código fuente. Ansible gestiona los valores; la aplicación los lee del entorno. Esta separación de responsabilidades es fundamental en el modelo [12-Factor App](https://12factor.net/config).

- **Idempotencia de la plantilla WSGI**: Si se ejecuta el playbook dos veces con las mismas variables, la tarea `copy demo.wsgi` reportará `ok` (sin cambios) porque el contenido renderizado es idéntico. Solo si cambian las variables (`db_user`, `db_pass`, `db_name`) Ansible detectará un cambio, actualizará el fichero y disparará el handler `restart apache2`.

---

## 📚 Referencias

- [Ansible Docs — `template` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Magic variables (`groups`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#information-about-ansible-magic-variables)
- [Ansible Docs — Registering variables con `with_items`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#registering-variables-with-a-loop)
- [mod_wsgi — Quick Configuration Guide](https://modwsgi.readthedocs.io/en/develop/user-guides/quick-configuration-guide.html)
- [12-Factor App — Config](https://12factor.net/config)
