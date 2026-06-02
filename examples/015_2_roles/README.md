# 🎭 Ejemplo 015_2 — Refactorización del stack con Roles de Ansible

## 🧭 Descripción general

Este ejemplo introduce el concepto más importante de la organización en Ansible: los **Roles**. Todo el código de los ejemplos anteriores (013, 014) — que vivía en playbooks monolíticos — se refactoriza aquí en **roles reutilizables y autocontenidos**.

La novedad no es funcional (el stack hace exactamente lo mismo), sino **estructural**: cada responsabilidad se encapsula en su propio rol con su directorio `tasks/`, `handlers/`, `templates/` y `files/`. El punto de entrada único es ahora `site.yml`, que orquesta todos los roles del stack.

Además, la plantilla `nginx.conf.j2` introduce una mejora importante: usa un **bucle Jinja2** para generar dinámicamente los servidores upstream leyendo el grupo `[webserver]` del inventario.

---

## 🗂️ Estructura del proyecto

```
015_2_roles/
├── hosts                          # Inventario de máquinas
├── site.yml                       # ⭐ Playbook principal — orquesta todos los roles
└── roles/                         # Directorio de roles
    ├── control/                   # Rol para el nodo de control
    ├── mysql/                     # Rol para el servidor de base de datos
    ├── nginx/                     # Rol para el balanceador de carga
    ├── apache2/                   # Rol para el servidor web
    ├── demo_app/                  # Rol para la aplicación Flask
    ├── status-control/            # Rol de verificación del nodo de control
    ├── status-database/           # Rol de verificación de MySQL
    ├── status-loadbalancer/       # Rol de verificación de Nginx
    └── status-webserver/          # Rol de verificación de Apache2
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

| **Grupo** | **IP** | **Roles asignados** |
|---|---|---|
| `[database]` | `192.168.11.20` | `mysql` → `status-database` |
| `[loadbalancer]` | `192.168.11.30` | `nginx` → `status-loadbalancer` |
| `[webserver]` | `192.168.11.40` | `apache2` + `demo_app` → `status-webserver` |
| `[control]` | (local) | `control` → `status-control` |

---

## ⭐ El punto de entrada: `site.yml`

```yaml
---
# This is the main playbook that will be executed when running ansible-playbook site.yml
# It includes all the roles that will be applied to the different hosts in the inventory.
# Each role is responsible for a specific part of the configuration, and they are applied to the appropriate hosts based on their group membership in the inventory file.
- hosts: control
  become: true
  roles:
    - control

- hosts: database
  become: true
  roles:
    - mysql

- hosts: loadbalancer
  become: true
  roles:
    - nginx

- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app

# --- Verificación del stack (inline, igual que stack_status.yml) ---

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

### ¿Qué hace `site.yml`?

`site.yml` es el **playbook maestro** del proyecto. En lugar de tener un fichero por servidor (`loadbalancer.yml`, `webserver.yml`...), ahora hay un único punto de entrada que:

1. **Despliega** todos los nodos aplicando sus roles correspondientes.
2. **Verifica** el stack completo inline al final, con las mismas pruebas HTTP end-to-end del ejemplo 014.

La clave está en la directiva `roles:` — en lugar de listar tareas directamente, se delega toda la lógica al rol correspondiente.

### Diferencia clave: `tasks` vs `roles`

| **Antes (playbook monolítico)** | **Ahora (con roles)** |
|---|---|
| Las tareas están escritas directamente en el playbook | Las tareas viven en `roles/<nombre>/tasks/main.yml` |
| Los handlers están en el mismo fichero | Los handlers viven en `roles/<nombre>/handlers/main.yml` |
| Las plantillas están en `templates/` del proyecto | Las plantillas viven en `roles/<nombre>/templates/` |
| Difícil de reutilizar en otros proyectos | El rol es un módulo autocontenido y portable |

### Separación de responsabilidades en `webserver`

```yaml
- hosts: webserver
  become: true
  roles:
    - apache2      # Instala y configura Apache2 (infraestructura)
    - demo_app     # Despliega la aplicación Flask (código de negocio)
```

El nodo webserver recibe **dos roles en secuencia**. Esta separación es intencional y muy importante:
- `apache2` gestiona la infraestructura del servidor web (instalación, módulos, arranque).
- `demo_app` gestiona el despliegue de la aplicación (código fuente, virtualenv, VirtualHost).

Esto permite reutilizar el rol `apache2` en otros proyectos sin arrastrar la lógica específica de `demo_app`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

---

## 🎭 Los Roles — Estructura y funcionamiento

Un **rol** en Ansible es un directorio con una estructura de subdirectorios estandarizada. Ansible los descubre automáticamente por nombre cuando se usa la directiva `roles:`.

### Estructura estándar de un rol

```
roles/<nombre>/
├── tasks/
│   └── main.yml      # Lista de tareas del rol
├── handlers/
│   └── main.yml      # Handlers (reiniciar servicios, etc.)
├── templates/
│   └── *.j2          # Plantillas Jinja2
├── files/
│   └── *             # Archivos estáticos a copiar
├── defaults/
│   └── main.yml      # Variables por defecto del rol
└── vars/
    └── main.yml      # Variables del rol (precedencia más alta)
```

Cada rol es **autocontenido**: todas sus dependencias (tareas, handlers, archivos, plantillas) viven dentro del directorio del rol.

---

## 🔧 Rol `control` — Nodo de control

**Propósito**: Instalar herramientas de diagnóstico en el nodo de control.

### `roles/control/tasks/main.yml`

```yaml
# tasks file for control
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
```

**¿Qué hace?**: Instala `curl` para diagnósticos. El módulo `uri` que usamos en las verificaciones no requiere dependencias adicionales.

**Comando de ejecución**:
```bash
ansible-playbook -i hosts site.yml
```

---

## 📊 Rol `mysql` — Servidor de base de datos

**Propósito**: Instalar MySQL/MariaDB, configurarlo para escuchar en todas las interfaces, y crear la base de datos de demostración.

### `roles/mysql/tasks/main.yml`

```yaml
# tasks file for mysql
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - default-mysql-server
    - python3-mysqldb

- name: install mysql-server
  apt: name=default-mysql-server state=present update_cache=yes

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/mariadb.conf.d/50-server.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
  notify: restart mysql

- name: create demo database
  mysql_db: name=demo state=present

- name: create demo user
  mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present

- name: ensure mysql started
  service: name=mysql state=started enabled=yes
```

### `roles/mysql/handlers/main.yml`

```yaml
# handlers file for mysql
---
- name: restart mysql
  service: name=mysql state=restarted
```

**¿Qué hace?**:
- Instala MySQL/MariaDB y `python3-mysqldb` (para que Ansible pueda interactuar con MySQL)
- Configura MySQL para escuchar en todas las interfaces (`bind-address = 0.0.0.0`)
- Crea la base de datos `demo` y el usuario `demo` con permisos completos
- Arranca MySQL y lo configura para iniciarse automáticamente

**El handler**: Se ejecuta automáticamente cuando `lineinfile` detecta un cambio en la configuración.

---

## ⚙️ Rol `nginx` — Balanceador de carga

**Propósito**: Instalar Nginx, generar su configuración de proxy reverso dinámicamente, y asegurarse de que está en ejecución.

### `roles/nginx/tasks/main.yml`

```yaml
# tasks file for nginx
---
- name: install nginx
  apt: name=nginx state=present update_cache=yes

- name: configure nginx site
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
  notify: restart nginx

- name: de-activate default nginx site
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: activate demo nginx site
  file: src=/etc/nginx/sites-available/demo dest=/etc/nginx/sites-enabled/demo state=link
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

### `roles/nginx/handlers/main.yml`

```yaml
# handlers file for nginx
---
- name: restart nginx
  service: name=nginx state=restarted
```

### `roles/nginx/templates/nginx.conf.j2` — **La plantilla con bucle Jinja2**

```jinja2
upstream demo {
{% for server in groups.webserver %}
    server {{ server }};
{% endfor %}
}

server {
    listen 80;

    location / {
        proxy_pass http://demo;
    }
}
```

**¿Qué hace esta plantilla?**

La **novedad clave** de este ejemplo: en lugar de hardcodear `server 192.168.11.40;`, la plantilla lee dinámicamente el grupo `[webserver]` del inventario y genera las líneas de configuración automáticamente.

Si añadieras más hosts al grupo `[webserver]`, Nginx se reconfiguraría automáticamente sin cambiar la plantilla. Esto es **infraestructura como código declarativa**: no describes valores específicos, sino cómo generarlos.

**Traducción de la plantilla**:
- `{% for server in groups.webserver %}` — Itera sobre las IPs del grupo `[webserver]` del inventario
- `server {{ server }};` — Genera una línea `server <IP>;` para cada nodo webserver

Resultado:
```nginx
upstream demo {
    server 192.168.11.40;
}
```

**¿Qué hace el rol?**:
- Instala Nginx
- Genera la configuración del proxy reverso usando la plantilla
- Desactiva el sitio por defecto
- Activa el sitio de demostración
- Los handlers reinician Nginx cuando cambia la configuración

---

## 🌐 Rol `apache2` — Servidor web (infraestructura)

**Propósito**: Instalar Apache2, habilitar el módulo WSGI, y preparar la infraestructura.

### `roles/apache2/tasks/main.yml`

```yaml
# tasks file for apache2
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3
    - python3-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

### `roles/apache2/handlers/main.yml`

```yaml
# handlers file for apache2
---
- name: restart apache2
  service: name=apache2 state=restarted
```

**¿Qué hace?**:
- Instala Apache2, WSGI, y herramientas de Python
- Habilita el módulo WSGI en Apache2
- Desactiva el sitio por defecto (que escucha en el puerto 80)
- Arranca Apache2

---

## 📦 Rol `demo_app` — Aplicación Flask (código de negocio)

**Propósito**: Desplegar la aplicación Flask de demostración y configurar su VirtualHost en Apache2.

### `roles/demo_app/tasks/main.yml`

```yaml
# tasks file for demo_app
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: copy demo app source
  copy: src=files/demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=files/demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf dest=/etc/apache2/sites-enabled/demo.conf state=link
  notify: restart apache2
```

### `roles/demo_app/handlers/main.yml`

```yaml
# handlers file for demo_app
---
- name: restart apache2
  service: name=apache2 state=restarted
```

**¿Qué hace?**:
- Copia el código fuente de la aplicación Flask a `/var/www/demo`
- Copia la configuración del VirtualHost de Apache2
- Crea un virtualenv de Python e instala las dependencias (`requirements.txt`)
- Activa el sitio (`demo.conf`)
- Reinicia Apache2 cuando cambia algo

**¿Por qué separar `apache2` y `demo_app`?**

- `apache2` es **reutilizable**: puede usarse en cualquier proyecto que necesite un servidor web
- `demo_app` es **específico del proyecto**: contiene la lógica de despliegue de esta aplicación en particular

Esta separación es lo que hace que Ansible sea verdaderamente modular.

---

## ✅ Roles de verificación — `status-*`

Después de desplegar todos los nodos, `site.yml` ejecuta cuatro roles de verificación para comprobar que el stack funciona correctamente.

### Rol `status-database`

#### `roles/status-database/tasks/main.yml`

```yaml
---
# tasks file for status-database
- name: verify mysql service
  command: service mysql status

- name: verify mysql is listening on 3306
  wait_for: port=3306 timeout=1
```

### Rol `status-webserver`

#### `roles/status-webserver/tasks/main.yml`

```yaml
---
# tasks file for status-webserver
- name: verify apache2 service
  command: service apache2 status

- name: verify apache2 is listening on 80
  wait_for: port=80 timeout=1
```

### Rol `status-loadbalancer`

#### `roles/status-loadbalancer/tasks/main.yml`

```yaml
---
# tasks file for status-loadbalancer
- name: verify nginx service
  command: service nginx status

- name: verify nginx is listening on 80
  wait_for: port=80 timeout=1

- name: verify backend index response
  uri: url=http://{{item}} return_content=yes
  with_items: "{{ groups.webserver }}"
  register: app_index

- name: verify backend index response
  fail: msg="index failed to return content"
  when: "'Hello, from sunny' not in item.content"
  with_items: "{{app_index.results}}"

- name: verify backend db response
  uri: url=http://{{item}}/db return_content=yes
  with_items: "{{ groups.webserver }}"
  register: app_db

- name: verify backend db response
  fail: msg="db failed to return content"
  when: "'Database Connected from' not in item.content"
  with_items: "{{app_db.results}}"
```

### Rol `status-control`

#### `roles/status-control/tasks/main.yml`

```yaml
---
- name: verify end-to-end index response
  uri: url=http://{{item}} return_content=yes
  with_items: "{{ groups.loadbalancer }}"
  register: lb_index

- name: verify end-to-end index response
  fail: msg="index failed to return content"
  when: "'Hello, from sunny' not in item.content"
  with_items: "{{lb_index.results}}"

- name: verify end-to-end db response
  uri: url=http://{{item}}/db return_content=yes
  with_items: "{{ groups.loadbalancer }}"
  register: lb_db

- name: verify end-to-end db response
  fail: msg="db failed to return content"
  when: "'Database Connected from' not in item.content"
  with_items: "{{lb_db.results}}"
```

**¿Qué verifican estos roles?**

| **Rol** | **Verifica** | **Desde** | **Hacia** |
|---|---|---|---|
| `status-database` | MySQL escucha en puerto 3306 | `database` | sí mismo |
| `status-webserver` | Apache2 escucha en puerto 80 | `webserver` | sí mismo |
| `status-loadbalancer` | Nginx escucha, conecta con webservers | `loadbalancer` | webservers |
| `status-control` | Acceso end-to-end al stack completo | `control` | loadbalancer |

---

## 🚀 Flujo de ejecución completo

```bash
# 1. Despliegue del control + database + loadbalancer + webserver + verificación
ansible-playbook -i hosts -u vagrant site.yml
```

**¿Qué ocurre internamente?**

1. **Nodo control** ← Aplica rol `control` (instala curl)
2. **Nodo database** ← Aplica rol `mysql` (instala MySQL, crea DB)
3. **Nodo loadbalancer** ← Aplica rol `nginx` (instala Nginx, genera configuración)
4. **Nodo webserver** ← Aplica rol `apache2` + `demo_app` (instala Apache2, Flask, app)
5. **Verificación de database** ← Aplica rol `status-database` (comprueba MySQL)
6. **Verificación de webserver** ← Aplica rol `status-webserver` (comprueba Apache2)
7. **Verificación de loadbalancer** ← Aplica rol `status-loadbalancer` (HTTP directo a webservers)
8. **Verificación de control** ← Aplica rol `status-control` (HTTP end-to-end)

Si algo falla en algún paso, el playbook completo se detiene y muestra el error.

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Roles**: Módulos autocontenidos de Ansible que encapsulan tareas, handlers, plantillas y archivos. Son la unidad de reutilización en Ansible.
- **Directivas `roles:`**: Declara qué roles se aplican a qué hosts. El orden importa: se ejecutan en secuencia.
- **Plantillas dinámicas con Jinja2**: La plantilla `nginx.conf.j2` genera configuración basada en datos del inventario. Esto es **infraestructura declarativa**.
- **Separación de responsabilidades**: `apache2` (infraestructura) se separa de `demo_app` (aplicación) para maximizar la reutilización.
- **Roles de verificación**: Los roles de `status-*` se ejecutan al final para garantizar que el despliegue fue exitoso.
- **Estructura estándar**: Todos los roles respetan la estructura estándar de Ansible (`tasks/`, `handlers/`, `templates/`, `files/`, etc.), lo que hace el código predecible y mantenible.

---

## 📚 Referencias

- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — Role directory structure](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#role-directory-structure)
- [Ansible Docs — Jinja2 Templates](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Docs — groups variable](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#using-inventory-in-a-playbook)
│   └── main.yml      # Handlers del rol (notify/listen)
├── templates/
│   └── *.j2          # Plantillas Jinja2 (referenciadas por nombre, sin ruta)
├── files/
│   └── ...           # Ficheros estáticos (referenciados por nombre, sin ruta)
├── vars/
│   └── main.yml      # Variables del rol (alta prioridad)
├── defaults/
│   └── main.yml      # Variables por defecto (baja prioridad, sobreescribibles)
└── meta/
    └── main.yml      # Metadatos y dependencias entre roles
```

> 💡 **Resolución automática de rutas**: Dentro de un rol, el módulo `template` busca en `roles/<nombre>/templates/` y el módulo `copy` busca en `roles/<nombre>/files/` automáticamente. No hace falta especificar rutas absolutas.

---

## 🔧 Rol `control` — Preparación del nodo de control

```yaml
# roles/control/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala las herramientas necesarias en el nodo de control. `python-httplib2` es la dependencia requerida por el módulo `uri` de Ansible para realizar peticiones HTTP durante las pruebas end-to-end de `stack_status.yml`.

| **Paquete** | **Descripción** |
|---|---|
| `curl` | Herramienta CLI para peticiones HTTP |
| `python-httplib2` | Librería HTTP para Python, requerida por el módulo `uri` |

---

## 🗄️ Rol `mysql` — Servidor de base de datos

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: chmod cnf
  command: chmod 777 /etc/mysql/my.cnf

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create demo database
  mysql_db: name=demo state=present

- name: create demo user
  mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present
```

```yaml
# roles/mysql/handlers/main.yml
---
- name: restart mysql
  service: name=mysql state=restarted
```

### Flujo de ejecución del rol `mysql`

1. Instala `python3-mysqldb` (librería Python necesaria para que Ansible gestione MySQL).
2. Instala el servidor MySQL.
3. Da permisos de escritura a `/etc/mysql/my.cnf` con `chmod 777` para que `lineinfile` pueda modificarlo.
4. Cambia `bind-address` a `0.0.0.0` para que MySQL acepte conexiones desde cualquier interfaz de red — necesario para que el webserver (`192.168.11.40`) pueda conectarse al database (`192.168.11.20`). Si este valor cambia, dispara el handler `restart mysql`.
5. Asegura que MySQL está arrancado y habilitado en el arranque del sistema.
6. Crea la base de datos `demo`.
7. Crea el usuario `demo` con contraseña `demo` y permisos totales sobre `demo.*` desde cualquier host (`host='%'`).

> ⚠️ **Nota sobre `chmod 777`**: Esta tarea es un workaround para entornos de laboratorio Vagrant. En producción, se usaría `become: true` con los permisos adecuados en lugar de dar permisos globales al fichero de configuración.

---

## ⚖️ Rol `nginx` — Balanceador de carga

```yaml
# roles/nginx/tasks/main.yml
---
- name: install nginx
  apt: name=nginx state=present update_cache=yes

- name: configure nginx site
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
  notify: restart nginx

- name: de-activate default nginx site
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: activate demo nginx site
  file: src=/etc/nginx/sites-available/demo dest=/etc/nginx/sites-enabled/demo state=link
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

```yaml
# roles/nginx/handlers/main.yml
---
- name: restart nginx
  service: name=nginx state=restarted
```

### Flujo de ejecución del rol `nginx`

1. Instala Nginx.
2. Procesa la plantilla `nginx.conf.j2` y despliega el resultado en `/etc/nginx/sites-available/demo`. Si el contenido cambia, dispara el handler `restart nginx`.
3. Elimina el enlace simbólico del site por defecto de Nginx (`default`) para que no interfiera.
4. Crea un enlace simbólico de `sites-available/demo` → `sites-enabled/demo` para activar la configuración.
5. Asegura que Nginx está arrancado y habilitado en el arranque.

> 💡 **Resolución de plantillas en roles**: `src=nginx.conf.j2` (sin ruta) funciona porque Ansible busca automáticamente en `roles/nginx/templates/nginx.conf.j2`.

---

## ⭐ La plantilla `nginx.conf.j2` — Bucle Jinja2 dinámico

```jinja2
upstream demo {
{% for server in groups.webserver %}
    server {{ server }};
{% endfor %}
}

server {
    listen 80;

    location / {
        proxy_pass http://demo;
    }
}
```

Esta es la **mejora más importante** respecto a los ejemplos anteriores. En lugar de hardcodear la IP del webserver (`server 192.168.11.40;`), la plantilla usa un **bucle Jinja2** que itera sobre el grupo `[webserver]` del inventario.

### ¿Qué genera este bucle?

Con el inventario actual (un solo webserver en `192.168.11.40`), Ansible procesa la plantilla y genera:

```nginx
upstream demo {
    server 192.168.11.40;
}

server {
    listen 80;

    location / {
        proxy_pass http://demo;
    }
}
```

### ¿Por qué es importante el bucle?

Si el inventario tuviera **múltiples webservers**:

```ini
[webserver]
192.168.11.40
192.168.11.41
192.168.11.42
```

La plantilla generaría automáticamente:

```nginx
upstream demo {
    server 192.168.11.40;
    server 192.168.11.41;
    server 192.168.11.42;
}
```

Nginx distribuiría el tráfico entre los tres servidores en **round-robin** sin necesidad de modificar ningún fichero de configuración manualmente. Solo con añadir IPs al inventario, el stack escala horizontalmente.

| **Sintaxis Jinja2** | **Descripción** |
|---|---|
| `{% for server in groups.webserver %}` | Inicio del bucle — itera sobre las IPs del grupo `[webserver]` |
| `{{ server }}` | Imprime el valor actual de la iteración (la IP del webserver) |
| `{% endfor %}` | Fin del bucle |
| `groups.webserver` | Variable mágica de Ansible que expone la lista de hosts del grupo `[webserver]` |

---

## 🌐 Rol `apache2` — Servidor web (infraestructura)

```yaml
# roles/apache2/tasks/main.yml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3
    - python-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

```yaml
# roles/apache2/handlers/main.yml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

### Flujo de ejecución del rol `apache2`

1. Instala Apache2 y todas sus dependencias para servir aplicaciones Python/WSGI con acceso a MySQL.
2. Activa el módulo `mod_wsgi` para que Apache pueda ejecutar aplicaciones Python. Si cambia, dispara el handler `restart apache2`.
3. Elimina el VirtualHost por defecto de Apache para evitar conflictos con el sitio de la demo.
4. Asegura que Apache está arrancado y habilitado en el arranque.

| **Paquete** | **Descripción** |
|---|---|
| `apache2` | Servidor web Apache |
| `libapache2-mod-wsgi-py3` | Módulo WSGI para Python 3 — permite a Apache ejecutar apps Flask |
| `python-pip-whl` | Soporte para instalación de paquetes Python con pip |
| `python3-virtualenv` | Entornos virtuales Python aislados |
| `python3-mysqldb` | Conector MySQL para Python 3 |

---

## 🚀 Rol `demo_app` — Aplicación Flask (despliegue)

```yaml
# roles/demo_app/tasks/main.yml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: copy demo app source
  copy: src=files/demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=files/demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf dest=/etc/apache2/sites-enabled/demo.conf state=link
  notify: restart apache2
```

```yaml
# roles/demo_app/handlers/main.yml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

### Flujo de ejecución del rol `demo_app`

1. Instala las dependencias Python necesarias para la aplicación.
2. Copia el código fuente de la aplicación Flask desde `roles/demo_app/files/demo/app/` al directorio `/var/www/demo` del servidor. Si cambia, dispara el handler `restart apache2`.
3. Copia el fichero de configuración del VirtualHost de Apache (`demo.conf`) a `/etc/apache2/sites-available/`. Si cambia, dispara el handler.
4. Crea un entorno virtual Python en `/var/www/demo/.venv` e instala las dependencias de `requirements.txt` con pip. Si cambia, dispara el handler.
5. Activa el VirtualHost creando un enlace simbólico en `sites-enabled/`.

> 💡 **Resolución de ficheros en roles**: `src=files/demo/app/` (sin ruta absoluta) funciona porque Ansible busca automáticamente en `roles/demo_app/files/`.

---

## 🔍 Rol `status` — Estructura vacía (sin implementar)

El rol `status` existe como directorio con la estructura estándar generada por `ansible-galaxy init` (carpetas `defaults/`, `handlers/`, `meta/`, `tests/`, `vars/`), pero **no tiene `tasks/main.yml`** — es una plantilla vacía preparada para una futura implementación que encapsularía la lógica de verificación del stack actualmente inline en `site.yml`.

---

## 📜 `stack_status.yml` — Verificación standalone del stack

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

Es el mismo playbook de verificación del ejemplo 014, mantenido como fichero independiente para poder ejecutar las pruebas sin redesplegar el stack completo.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant stack_status.yml
```

---

## 🔄 Flujo completo de despliegue y operación

### Despliegue completo del stack (un solo comando)

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

`site.yml` despliega todos los nodos en orden y ejecuta la verificación end-to-end automáticamente al final.

### Verificación del stack sin redesplegar

```bash
ansible-playbook -i hosts -u vagrant stack_status.yml
```

### Reiniciar el stack en orden seguro

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### Consultar hostname de todos los nodos

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

## 🏗️ Comparativa: antes vs después de los roles

| **Aspecto** | **Antes (playbooks monolíticos)** | **Ahora (con roles)** |
|---|---|---|
| Punto de entrada | Múltiples ficheros (`loadbalancer.yml`, `webserver.yml`...) | Un único `site.yml` |
| Tareas | Inline en el playbook | En `roles/<nombre>/tasks/main.yml` |
| Handlers | Inline en el playbook | En `roles/<nombre>/handlers/main.yml` |
| Plantillas | En `templates/` del proyecto | En `roles/<nombre>/templates/` |
| Ficheros estáticos | En `demo/` del proyecto | En `roles/<nombre>/files/` |
| Reutilización | Difícil — código acoplado al proyecto | Fácil — rol portable a cualquier proyecto |
| Escalado de webservers | IP hardcodeada en la plantilla | Bucle Jinja2 lee el inventario dinámicamente |
| Separación de responsabilidades | Una capa por fichero | Múltiples roles por nodo posible (`apache2` + `demo_app`) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Roles**: Unidad de organización y reutilización en Ansible. Encapsulan tareas, handlers, plantillas y ficheros en un directorio autocontenido con estructura estandarizada.
- **`roles:` en un play**: Directiva que aplica uno o más roles a un grupo de hosts. Ansible carga automáticamente `tasks/main.yml`, `handlers/main.yml`, etc. del rol.
- **Resolución automática de rutas**: Dentro de un rol, `template` busca en `templates/` y `copy` busca en `files/` sin necesidad de especificar rutas absolutas.
- **Múltiples roles por nodo**: Un mismo host puede recibir varios roles en secuencia (`apache2` + `demo_app`), lo que permite separar infraestructura de aplicación.
- **`site.yml` como playbook maestro**: Patrón estándar en Ansible para tener un único punto de entrada que orquesta todo el stack.
- **Bucle Jinja2 `{% for %}`**: Permite generar configuraciones dinámicas basadas en el inventario. La plantilla `nginx.conf.j2` genera automáticamente tantos `server` en el `upstream` como hosts haya en el grupo `[webserver]`, haciendo el stack escalable horizontalmente sin tocar código.
- **`ansible-galaxy init`**: Herramienta que genera la estructura de directorios estándar de un rol. El rol `status` es un ejemplo de estructura generada pero aún sin implementar.

---

## 📚 Referencias

- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — ansible-galaxy init](https://docs.ansible.com/ansible/latest/cli/ansible-galaxy.html)
- [Jinja2 — Template Designer Documentation (for loops)](https://jinja.palletsprojects.com/en/3.1.x/templates/#for)
- [Ansible Docs — ansible.builtin.template module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — ansible.builtin.uri module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
