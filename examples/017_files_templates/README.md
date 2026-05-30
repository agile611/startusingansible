# 📋 Ejemplo 017 — Files, Templates y organización de recursos en Roles

## 🧭 Descripción general

Este ejemplo consolida la organización profesional de un proyecto Ansible centrada en el **uso correcto de ficheros estáticos (`files/`) y plantillas Jinja2 (`templates/`) dentro de los roles**. La novedad principal respecto al ejemplo 016 es que cada recurso — plantilla de configuración, fichero de código fuente, configuración de VirtualHost — **vive dentro del rol que lo necesita**, siguiendo la convención de resolución automática de rutas de Ansible.

La arquitectura del stack desplegado es idéntica a ejemplos anteriores (MySQL + Apache2/Flask + Nginx), pero la estructura interna de los roles es más limpia y autocontenida. Además, `stack_status.yml` introduce verificaciones end-to-end con `uri` + `fail` usando `with_items` e interpolación dinámica de IPs en las condiciones `when`.

---

## 🗂️ Estructura del proyecto

```
017_files_templates/
├── hosts                          # Inventario de máquinas
├── database.yml                   # Playbook del servidor de base de datos
├── webserver.yml                  # Playbook del servidor web
├── loadbalancer.yml               # Playbook del balanceador de carga
├── control.yml                    # Playbook del nodo de control
├── playbooks/
│   ├── hostname.yml               # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml          # Reinicio ordenado del stack
│   └── stack_status.yml           # ⭐ Verificación avanzada con uri + fail + with_items
└── roles/
    ├── mysql/                     # Rol BD: instala y configura MySQL
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    ├── apache2/                   # Rol web: infraestructura Apache + mod_wsgi
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    ├── demo_app/                  # Rol app: despliega Flask, virtualenv, VirtualHost
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── files/
    │       └── demo/              # Código fuente Flask + demo.conf (VirtualHost Apache)
    ├── nginx/                     # Rol LB: instala y configura Nginx
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── nginx.conf.j2      # ⭐ Plantilla dentro del rol
    └── control/                   # Rol control: instala curl + python-httplib2
        └── tasks/main.yml
```

### Convención de resolución automática de rutas en roles

Cuando un módulo Ansible se ejecuta dentro de un rol, busca los recursos en rutas predefinidas **sin necesidad de especificar rutas absolutas**:

| **Módulo** | **Busca automáticamente en** |
|---|---|
| `copy: src=demo/app/` | `roles/<nombre>/files/demo/app/` |
| `template: src=nginx.conf.j2` | `roles/<nombre>/templates/nginx.conf.j2` |
| `script: src=script.sh` | `roles/<nombre>/files/script.sh` |

Esta es la diferencia fundamental con los ejemplos anteriores, donde las rutas eran relativas al playbook raíz (`templates/nginx.conf.j2`). Ahora cada rol es completamente autocontenido.

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

## 📄 Playbooks de despliegue

### `database.yml`

```yaml
---
- hosts: database
  become: true
  roles:
    - mysql
```

### `webserver.yml`

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

En este ejemplo se vuelve a la separación de roles `apache2` + `demo_app` (frente al ejemplo 016 donde estaban consolidados). `apache2` gestiona la infraestructura del servidor web y `demo_app` gestiona el despliegue de la aplicación Flask.

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
```

La configuración de Nginx ahora está completamente encapsulada en el rol `nginx`, incluyendo su plantilla `nginx.conf.j2` en `roles/nginx/templates/`.

### `control.yml`

```yaml
---
- hosts: control
  become: true
  roles:
    - control
```

### Comandos de ejecución

```bash
# Desplegar cada componente individualmente
ansible-playbook -i hosts -u vagrant database.yml
ansible-playbook -i hosts -u vagrant webserver.yml
ansible-playbook -i hosts -u vagrant loadbalancer.yml
ansible-playbook -i hosts -u vagrant control.yml

# Verificar el estado del stack
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml

# Reiniciar el stack en orden correcto
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🎭 Los Roles

### 🗄️ Rol `mysql` — Servidor de base de datos

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

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

#### Flujo de ejecución

1. Instala `python-mysqldb` — librería Python necesaria para que Ansible gestione MySQL con los módulos `mysql_db` y `mysql_user`.
2. Instala el servidor MySQL.
3. Modifica `bind-address` en `/etc/mysql/my.cnf` a `0.0.0.0` para aceptar conexiones remotas desde el webserver. Si cambia, dispara el handler `restart mysql`.
4. Arranca MySQL y lo habilita en el boot.
5. Crea la base de datos `demo`.
6. Crea el usuario `demo` con contraseña `demo` y permisos totales sobre `demo.*` desde cualquier host (`host='%'`).

---

### 🌐 Rol `apache2` — Infraestructura del servidor web

```yaml
# roles/apache2/tasks/main.yml
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

```yaml
# roles/apache2/handlers/main.yml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

#### Flujo de ejecución

1. Instala Apache2 y el módulo WSGI para Python 2 (`libapache2-mod-wsgi`).
2. Activa el módulo `mod_wsgi` — necesario para que Apache ejecute aplicaciones Python/Flask. Si cambia, dispara `restart apache2`.
3. Elimina el VirtualHost por defecto de Apache para evitar conflictos con el sitio de la demo.
4. Arranca Apache y lo habilita en el boot.

> ⚠️ **Nota**: Este rol usa `libapache2-mod-wsgi` (Python 2). En entornos modernos se usa `libapache2-mod-wsgi-py3`. Este ejemplo refleja una versión del curso orientada a Python 2.

---

### 🚀 Rol `demo_app` — Despliegue de la aplicación Flask

```yaml
# roles/demo_app/tasks/main.yml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-pip
    - python-virtualenv
    - python-mysqldb

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
  file: src=/etc/apache2/sites-available/demo.conf dest=/etc/apache2/sites-enabled/demo.conf state=link
  notify: restart apache2
```

```yaml
# roles/demo_app/handlers/main.yml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

#### Flujo de ejecución

1. Instala las dependencias Python necesarias para la aplicación (`pip`, `virtualenv`, `mysqldb`).
2. **Copia el código fuente** de la app Flask desde `roles/demo_app/files/demo/app/` a `/var/www/demo` en el servidor. Ansible resuelve automáticamente la ruta `src=demo/app/` buscando en `roles/demo_app/files/`.
3. **Copia el VirtualHost** de Apache desde `roles/demo_app/files/demo/demo.conf` a `/etc/apache2/sites-available/`.
4. **Crea el virtualenv** e instala las dependencias de `requirements.txt` con el módulo `pip`.
5. **Activa el VirtualHost** creando un enlace simbólico en `sites-enabled/`.

#### ⭐ Resolución automática de `src` en el módulo `copy`

```yaml
copy: src=demo/app/ dest=/var/www/demo mode=0755
```

Ansible busca `demo/app/` en este orden de prioridad:
1. `roles/demo_app/files/demo/app/` ← **Aquí lo encuentra**
2. `files/demo/app/` (directorio `files/` relativo al playbook)

Esto hace que el rol sea **completamente portable**: se puede copiar a cualquier proyecto y funcionará sin cambiar ninguna ruta.

---

### ⚖️ Rol `nginx` — Balanceador de carga

```yaml
# roles/nginx/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-httplib2

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

#### ⭐ La plantilla dentro del rol: `roles/nginx/templates/nginx.conf.j2`

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

La clave de este ejemplo es que `nginx.conf.j2` **vive dentro del rol** en `roles/nginx/templates/`. Cuando el módulo `template` recibe `src=nginx.conf.j2`, Ansible lo busca automáticamente en `roles/nginx/templates/nginx.conf.j2`.

Con el inventario actual, la plantilla genera:

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

Si se añaden más hosts al grupo `[webserver]`, Nginx los balancearía automáticamente en round-robin sin modificar ningún fichero.

#### Flujo de ejecución

1. Instala `python-httplib2` — dependencia para el módulo `uri` de Ansible.
2. Instala Nginx.
3. **Procesa la plantilla** `nginx.conf.j2` y despliega el resultado en `/etc/nginx/sites-available/demo`. Si cambia, dispara `restart nginx`.
4. Elimina el site por defecto de Nginx.
5. Activa el site de la demo con un enlace simbólico.
6. Arranca Nginx y lo habilita en el boot.

---

### 🛠️ Rol `control` — Nodo de control

```yaml
# roles/control/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala `curl` y `python-httplib2` en el nodo de control. `python-httplib2` es la dependencia que necesita el módulo `uri` de Ansible para realizar peticiones HTTP.

---

## 📄 Playbook `playbooks/hostname.yml` — Diagnóstico de conectividad

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

Ejecuta el comando `hostname` en **todos los nodos del inventario** para verificar la conectividad SSH y obtener el nombre de cada máquina. Es la prueba de conectividad más básica antes de un despliegue.

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

## 🔄 Playbook `playbooks/stack_restart.yml` — Reinicio ordenado

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
    - wait_for: port=3306 state=started

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

El reinicio sigue un **orden inverso al arranque** para evitar errores de dependencia:

| **Fase** | **Nodo** | **Acción** | **`wait_for` state** | **Descripción** |
|---|---|---|---|---|
| 1. Bajar LB | `loadbalancer` | Nginx `stopped` | `drained` | Espera a que las conexiones activas terminen (graceful) |
| 2. Bajar Web | `webserver` | Apache `stopped` | `stopped` | Espera a que el puerto 80 deje de estar accesible |
| 3. Reiniciar BD | `database` | MySQL `restarted` | `started` | Espera a que el puerto 3306 esté disponible |
| 4. Subir Web | `webserver` | Apache `started` | *(started)* | Espera a que el puerto 80 esté accesible |
| 5. Subir LB | `loadbalancer` | Nginx `started` | *(started)* | Espera a que el puerto 80 esté accesible |

### Estados de `wait_for`

| **`state`** | **Descripción** |
|---|---|
| `started` | Espera a que el puerto esté abierto y aceptando conexiones TCP |
| `stopped` | Espera a que el puerto deje de estar accesible |
| `drained` | Espera a que todas las conexiones activas se cierren antes de confirmar la parada |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🔍 Playbook `playbooks/stack_status.yml` — Verificación avanzada en capas

Este es el playbook de verificación más completo del ejemplo. Combina tres niveles de comprobación:

```yaml
---
# NIVEL 1: Proceso + Red (desde cada nodo)
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

# NIVEL 2: End-to-end (desde el nodo de control, a través del loadbalancer)
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

# NIVEL 3: Backend directo (desde el loadbalancer, saltando el LB)
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

### Tres niveles de verificación

| **Nivel** | **Ejecutado desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| **1. Proceso + Red** | Cada nodo (localhost) | Sus propios puertos | Servicio activo + puerto TCP abierto |
| **2. End-to-end** | `control` | `loadbalancer` (puerto 80) | Stack completo de extremo a extremo |
| **3. Backend directo** | `loadbalancer` | `webserver` (bypass LB) | Flask responde directamente en `/` y `/db` |

### ⭐ `with_items` con `groups.<grupo>` — Iteración sobre el inventario

```yaml
uri: url=http://{{item}} return_content=yes
with_items: groups.loadbalancer
register: lb_index
```

`with_items: groups.loadbalancer` itera sobre la lista de IPs del grupo `[loadbalancer]` del inventario. En cada iteración, `{{item}}` contiene la IP del nodo. El resultado de todas las iteraciones se guarda en `lb_index.results` como una lista.

> ⚠️ **Nota sintáctica**: `with_items: groups.loadbalancer` (sin comillas ni llaves) es la sintaxis de **Ansible 1.x**. En Ansible 2.x+ la sintaxis correcta es `with_items: "{{ groups.loadbalancer }}"` o `loop: "{{ groups.loadbalancer }}"`. Este ejemplo muestra la evolución histórica de la sintaxis de Ansible.

### ⭐ `fail` con `when` e interpolación dinámica de IP

```yaml
- fail: msg="index failed to return content"
  when: "'Hello, from sunny {{item.item}}!' not in item.content"
  with_items: "{{app_index.results}}"
```

| **Variable** | **Descripción** |
|---|---|
| `item` | Cada resultado del loop anterior (un objeto con `.content`, `.status`, `.item`, etc.) |
| `item.content` | El cuerpo de la respuesta HTTP devuelta por el módulo `uri` |
| `item.item` | La IP del webserver que generó este resultado (el `{{item}}` del loop de `uri`) |
| `not in` | Operador de pertenencia de Jinja2 — devuelve `true` si el string NO está en el contenido |

La condición `when` con `not in` hace que `fail` se dispare si el contenido esperado **no está presente** en la respuesta. Es la forma de implementar **pruebas de aceptación** en Ansible: si la app no responde con el texto correcto, el playbook falla con un mensaje descriptivo.

La interpolación `{{item.item}}` en la condición `when` es especialmente poderosa: permite construir el mensaje esperado dinámicamente incluyendo la IP del servidor que respondió, haciendo la verificación específica por nodo.

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **016** | **017** |
|---|---|---|
| Roles `apache2` + `demo_app` | Consolidados en `apache2` | Separados de nuevo |
| Plantilla `nginx.conf.j2` | En `templates/` raíz del proyecto | ⭐ Dentro del rol `roles/nginx/templates/` |
| Ficheros de la app Flask | En `roles/apache2/files/` | En `roles/demo_app/files/` |
| Resolución de rutas en `copy` | Ruta relativa al playbook | ⭐ Automática desde `roles/<nombre>/files/` |
| Resolución de rutas en `template` | Ruta relativa al playbook | ⭐ Automática desde `roles/<nombre>/templates/` |
| Sintaxis de loops | `loop:` (moderna) | `with_items:` (clásica) |
| Verificación `stack_status.yml` | `loop` + `uri` + `fail` | `with_items` + `uri` + `fail` con `item.item` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`files/` dentro del rol**: Los ficheros estáticos copiados con `copy` deben vivir en `roles/<nombre>/files/`. Ansible los resuelve automáticamente sin especificar rutas absolutas.
- **`templates/` dentro del rol**: Las plantillas Jinja2 usadas con `template` deben vivir en `roles/<nombre>/templates/`. La resolución automática hace los roles completamente portables.
- **Portabilidad de roles**: Un rol con sus `files/` y `templates/` propios puede copiarse a cualquier proyecto y funcionará sin modificar ninguna ruta — es la esencia de la reutilización en Ansible.
- **`with_items: groups.<grupo>`**: Permite iterar dinámicamente sobre los hosts de un grupo del inventario, haciendo los playbooks de verificación escalables horizontalmente.
- **`item.item` en resultados de loop**: Cuando se itera sobre `register.results`, `item.item` contiene el valor original del `{{item}}` del loop que generó ese resultado. Permite construir condiciones `when` específicas por nodo.
- **`not in` en condiciones `when`**: Operador de pertenencia de Jinja2 que permite verificar si un string está (o no está) dentro de otro. Fundamental para pruebas de aceptación basadas en contenido HTTP.
- **`wait_for: state=drained`**: Espera a que todas las conexiones activas de un puerto se cierren antes de continuar — permite apagados graceful del loadbalancer sin interrumpir peticiones en curso.
- **Separación infraestructura / aplicación**: Mantener `apache2` (infraestructura) y `demo_app` (aplicación) como roles separados maximiza la reutilización: el rol `apache2` puede usarse en cualquier proyecto que necesite Apache + WSGI.

---

## 📚 Referencias

- [Ansible Docs — Roles: files and templates directories](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#role-directory-structure)
- [Ansible Docs — ansible.builtin.copy module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Ansible Docs — ansible.builtin.template module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — ansible.builtin.uri module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Ansible Docs — ansible.builtin.fail module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/fail_module.html)
- [Ansible Docs — ansible.builtin.wait_for module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
- [Jinja2 — Tests: `in` operator](https://jinja.palletsprojects.com/en/3.1.x/templates/#tests)
