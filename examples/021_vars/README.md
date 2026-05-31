# 📋 Ejemplo 021 — `vars`: Variables de rol inline y diccionarios estructurados

## 🧭 Descripción general

Este ejemplo profundiza en el sistema de variables de Ansible introduciendo dos conceptos nuevos y complementarios. El primero es la **asignación de variables inline al invocar un rol** (sintaxis `{ role: mysql, db_name: demo, ... }`), que permite parametrizar un rol directamente desde el playbook sin necesidad de ficheros externos. El segundo — y más importante — es el uso de **variables de tipo diccionario** (`dict`) en `defaults/`, que permite agrupar configuraciones relacionadas bajo una única variable estructurada y recorrerlas con `with_dict`.

La gran novedad visible en el rol `nginx` es que ya no gestiona un único sitio hardcodeado: ahora itera sobre un **diccionario de sitios** (`sites`), generando dinámicamente un fichero de configuración Nginx por cada entrada del diccionario. Esto convierte el rol en un balanceador multi-sitio completamente genérico.

---

## 🗂️ Estructura del proyecto

```
021_vars/
├── site.yml                        # Orquestador maestro
├── control.yml                     # Playbook del nodo de control
├── database.yml                    # Playbook del servidor de base de datos
├── webserver.yml                   # Playbook del servidor web
├── loadbalancer.yml                # Playbook del balanceador de carga
├── demo/                           # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml                # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml           # Reinicio ordenado del stack
│   └── stack_status.yml            # Verificación end-to-end del stack
└── roles/
    ├── control/
    │   └── tasks/main.yml
    ├── mysql/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   ├── files/my.cnf
    │   ├── vars/main.yml           # Vacío (reservado)
    │   └── defaults/main.yml       # ⭐ db_name, db_user_name, db_user_pass, db_user_host, db_host_ipv4
    ├── apache2/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── defaults/main.yml       # Vacío (reservado)
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   ├── files/
    │   ├── vars/main.yml           # Vacío (reservado)
    │   └── defaults/main.yml       # Vacío (reservado)
    └── nginx/
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        ├── vars/main.yml           # Vacío (reservado)
        └── defaults/main.yml       # ⭐ sites: diccionario de sitios (NOVEDAD PRINCIPAL)
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

## ⭐ El orquestador maestro: `site.yml`

```yaml
---
- include: control.yml
- include: database.yml
- include: webserver.yml
- include: loadbalancer.yml
- include: playbooks/stack_status.yml
```

Despliega todo el stack en orden y ejecuta la verificación automática al final.

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

### `database.yml` — ⭐ Sintaxis inline comentada

```yaml
---
- hosts: database
  become: true
  roles:
#    - { role: mysql, db_name: demo, db_user_name: demo, db_user_pass: demo, db_user_host: '%' }
    - { role: mysql }
```

Esta es la primera novedad del ejemplo: la línea comentada muestra la **sintaxis de variables inline** para un rol. Al descomentar esa línea, las variables `db_name`, `db_user_name`, `db_user_pass` y `db_user_host` se pasan directamente al rol `mysql` en el momento de invocarlo, sobreescribiendo los valores de `defaults/main.yml`.

En la versión activa (`- { role: mysql }`) no se pasan variables inline, por lo que el rol usa sus propios valores de `defaults/`.

### `webserver.yml`

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

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

### 🗄️ Rol `mysql` — Variables con nombres más descriptivos

#### `roles/mysql/defaults/main.yml`

```yaml
---
db_name: myapp
db_user_name: dbuser
db_user_pass: dbpass
db_user_host: localhost
db_host_ipv4: 3.144.5.82
```

Respecto al ejemplo 020, los nombres de las variables han evolucionado para ser más explícitos (`db_user_name` en lugar de `db_user`, `db_user_pass` en lugar de `db_password`). Aparece también `db_host_ipv4` como variable configurable para la dirección de escucha de MySQL — en el ejemplo 020 se usaba directamente el fact `ansible_eth0.ipv4.address`.

> ⚠️ **Nota importante:** El valor por defecto de `db_host_ipv4` (`3.144.5.82`) es una IP pública de ejemplo. En un entorno real siempre se sobreescribiría con la IP real del servidor de base de datos, bien mediante variables inline, `group_vars/`, o `--extra-vars`.

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

- name: chmod cnf
  copy: src=files/my.cnf dest=/etc/mysql/my.cnf owner=mysql group=mysql mode=0700

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ db_host_ipv4 }}"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create database
  mysql_db: name={{ db_name }} state=present

- name: create user
  mysql_user: name={{ db_user_name }} password={{ db_user_pass }} priv={{ db_name }}.*:ALL
              host='{{ db_user_host }}' state=present
```

#### Diferencia clave respecto al ejemplo 020

| **020** | **021** |
|---|---|
| `db_user` | `db_user_name` (más descriptivo) |
| `db_password` | `db_user_pass` (más descriptivo) |
| `ansible_eth0.ipv4.address` (fact) | `{{ db_host_ipv4 }}` (variable configurable) |
| `host='%'` (hardcodeado) | `host='{{ db_user_host }}'` (configurable) |

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

---

### ⚖️ Rol `nginx` — ⭐ NOVEDAD PRINCIPAL: diccionario `sites` + `with_dict`

Este es el rol más importante del ejemplo. Introduce el uso de **variables de tipo diccionario** para gestionar múltiples sitios de forma genérica.

#### `roles/nginx/defaults/main.yml`

```yaml
---
sites:
  myappguillem:
    frontend: 80
    backend: 80
```

La variable `sites` es un **diccionario YAML** donde:
- La **clave** (`myappguillem`) es el nombre del sitio — se usará como nombre del fichero de configuración y del upstream de Nginx.
- El **valor** es otro diccionario con dos propiedades:
  - `frontend`: puerto en el que Nginx escucha peticiones entrantes.
  - `backend`: puerto al que Nginx reenvía las peticiones a los servidores web.

Para añadir un segundo sitio bastaría con añadir otra entrada al diccionario:

```yaml
sites:
  myappguillem:
    frontend: 80
    backend: 80
  otherapp:
    frontend: 8080
    backend: 8080
```

#### `roles/nginx/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-httplib2

- name: install nginx
  apt: name=nginx state=present update_cache=yes

- name: de-active former served sites
  file: name=/etc/nginx/sites-enabled/{{ item.key }} state=absent
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: configure sites nginx
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/{{ item.key }} mode=0644
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: de-activate default nginx site
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: activate sites nginx
  file: src=/etc/nginx/sites-available/{{ item.key }}
        dest=/etc/nginx/sites-enabled/{{ item.key }}
        state=link
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

#### Cómo funciona `with_dict`

`with_dict` itera sobre cada par clave-valor del diccionario `sites`. En cada iteración, Ansible expone:
- `item.key` → el nombre del sitio (ej. `myappguillem`)
- `item.value` → el sub-diccionario con `frontend` y `backend`
- `item.value.frontend` → el puerto de escucha (ej. `80`)
- `item.value.backend` → el puerto del backend (ej. `80`)

El flujo de tareas para **cada sitio** del diccionario es:
1. **Eliminar** el enlace simbólico anterior en `sites-enabled/` (limpieza idempotente).
2. **Generar** el fichero de configuración en `sites-available/` desde la plantilla Jinja2.
3. **Eliminar** el sitio por defecto de Nginx.
4. **Activar** el sitio creando un enlace simbólico en `sites-enabled/`.

#### Plantilla `roles/nginx/templates/nginx.conf.j2`

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

Con el diccionario por defecto (`myappguillem`, frontend `80`, backend `80`) y el inventario dado, esta plantilla genera:

```nginx
upstream myappguillem {
    server 192.168.11.40:80;
}

server {
    listen 80;

    location / {
        proxy_pass http://myappguillem;
    }
}
```

#### Diferencia clave respecto al ejemplo 020

| **Aspecto** | **020** | **021** |
|---|---|---|
| Número de sitios | 1 (hardcodeado `demo`) | ⭐ N sitios (diccionario `sites`) |
| Nombre del upstream | `demo` (fijo) | ⭐ `{{ item.key }}` (dinámico) |
| Puerto de escucha | `{{ nginx_port }}` | ⭐ `{{ item.value.frontend }}` |
| Puerto del backend | implícito (80) | ⭐ `{{ item.value.backend }}` |
| Iteración | ninguna | ⭐ `with_dict: "{{ sites }}"` |
| Escalabilidad | requiere modificar el rol | ⭐ añadir una entrada al diccionario |

#### `roles/nginx/handlers/main.yml`

```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
```

---

### 🌐 Rol `apache2` — Sin cambios relevantes

#### `roles/apache2/tasks/main.yml`

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

> Pequeña mejora respecto al ejemplo 020: usa `libapache2-mod-wsgi-py3` (módulo WSGI para Python 3) en lugar de `libapache2-mod-wsgi`.

#### `roles/apache2/handlers/main.yml`

```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

---

### 🚀 Rol `demo_app` — Sin cambios relevantes

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

#### `roles/demo_app/handlers/main.yml`

```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
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

El orden de reinicio es deliberado y seguro:

1. **Parar Nginx** (loadbalancer) → drena conexiones activas antes de parar.
2. **Parar Apache** (webserver) → espera a que el puerto 80 quede libre.
3. **Reiniciar MySQL** (database) → espera a que el puerto 3306 esté disponible.
4. **Arrancar Apache** (webserver) → espera a que el puerto 80 esté activo.
5. **Arrancar Nginx** (loadbalancer) → espera a que el puerto 80 esté activo.

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

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

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{app_index.results}}"

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{app_db.results}}"
```

Realiza una verificación completa en cuatro capas:

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer` | respuesta HTTP con `"Hello, from sunny"` |
| End-to-end DB | `control` | `loadbalancer/db` | respuesta HTTP con `"Database Connected from"` |
| Backend directo | `loadbalancer` | cada `webserver` | respuesta HTTP directa sin pasar por Nginx |

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

### Sobreescribir variables inline desde el playbook (descomentar en `database.yml`)

```yaml
# database.yml
- hosts: database
  become: true
  roles:
    - { role: mysql, db_name: demo, db_user_name: demo, db_user_pass: demo, db_user_host: '%' }
```

### Sobreescribir variables desde la línea de comandos

```bash
# Desplegar con credenciales de base de datos personalizadas
ansible-playbook -i hosts -u vagrant database.yml \
  -e "db_name=myapp db_user_name=myuser db_user_pass=s3cr3t db_user_host=%"

# Desplegar Nginx con un sitio en puerto diferente
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e '{"sites": {"myapp": {"frontend": 8080, "backend": 80}}}'

# Operaciones de mantenimiento
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

> ⭐ Para sobreescribir una variable de tipo diccionario compleja desde `-e`, usa la **sintaxis JSON** como se muestra arriba.

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **020** | **021** |
|---|---|---|
| Variables de MySQL | `db_user`, `db_password` | ⭐ `db_user_name`, `db_user_pass`, `db_user_host` (más descriptivos) |
| IP de escucha MySQL | `ansible_eth0.ipv4.address` (fact) | ⭐ `db_host_ipv4` (variable configurable) |
| Configuración Nginx | una variable por parámetro | ⭐ diccionario `sites` con `frontend`/`backend` |
| Iteración Nginx | ninguna | ⭐ `with_dict: "{{ sites }}"` |
| Número de sitios Nginx | 1 (hardcodeado) | ⭐ N sitios (entradas del diccionario) |
| Sintaxis de rol | `- nombre_rol` | ⭐ `- { role: nombre, var: valor }` (inline) |
| Variables en `vars/` | no existían | ⭐ ficheros creados (vacíos, listos para usar) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Variables inline en roles** (`{ role: mysql, db_name: demo, ... }`): Permiten pasar variables directamente al invocar un rol en el playbook, sobreescribiendo los `defaults/`. Es la forma más explícita y localizada de parametrizar un rol — ideal cuando diferentes plays necesitan el mismo rol con configuraciones distintas.

- **Variables de tipo diccionario en `defaults/`**: Agrupar variables relacionadas bajo una clave común (`sites`) hace la configuración más legible y estructurada. En lugar de tener `nginx_site_name`, `nginx_frontend_port` y `nginx_backend_port` como variables sueltas, se agrupan bajo `sites.myapp.frontend` y `sites.myapp.backend`.

- **`with_dict`**: Itera sobre un diccionario YAML exponiendo `item.key` (la clave) e `item.value` (el valor, que puede ser a su vez un diccionario). Permite que una sola tarea opere sobre múltiples entidades configuradas en el diccionario.

- **Roles multi-sitio**: Combinando `with_dict` y la variable `sites`, el rol `nginx` puede gestionar cualquier número de sitios sin modificar su código. Añadir un nuevo sitio es tan simple como añadir una entrada al diccionario `sites`.

- **`item.key` en nombres de fichero**: Usar `{{ item.key }}` como nombre de fichero de configuración (`/etc/nginx/sites-available/{{ item.key }}`) garantiza que cada sitio tenga su propio fichero, evitando colisiones y facilitando la gestión individual.

- **`vars/main.yml` vacío**: La presencia de ficheros `vars/main.yml` vacíos (con solo un comentario) es una convención de buenas prácticas: indica que el directorio existe y está listo para recibir variables internas del rol en el futuro, sin necesidad de crearlo después.

---

## 📚 Referencias

- [Ansible Docs — Passing variables to roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#passing-variables-to-roles)
- [Ansible Docs — `with_dict` loop](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#with-dict)
- [Ansible Docs — Variable types: dictionaries](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#creating-valid-variable-names)
- [Ansible Docs — Variable precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Jinja2 — Accessing dictionary values](https://jinja.palletsprojects.com/en/3.1.x/templates/#variables)
