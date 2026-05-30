# 📋 Ejemplo 016 — Tasks, Handlers e `import_playbook`

## 🧭 Descripción general

Este ejemplo introduce dos conceptos clave que elevan la organización del proyecto Ansible a un nivel profesional:

1. **`import_playbook`**: permite que `site.yml` sea un **orquestador maestro** que importa y ejecuta otros playbooks en secuencia, en lugar de contener toda la lógica directamente.
2. **Consolidación del rol `apache2`**: el rol absorbe las responsabilidades del antiguo rol `demo_app` — ahora un único rol gestiona tanto la infraestructura Apache como el despliegue de la aplicación Flask.

Además, el rol `mysql` incorpora mejoras robustas: espera activa con `until/retries` para asegurar que MySQL arranca correctamente, y uso de `debug` para inspeccionar el estado del servicio durante la ejecución.

---

## 🗂️ Estructura del proyecto

```
016_tasks_handlers/
├── hosts                          # Inventario de máquinas
├── site.yml                       # ⭐ Orquestador maestro con import_playbook
├── control.yml                    # Playbook del nodo de control
├── database.yml                   # Playbook del servidor de base de datos
├── loadbalancer.yml               # Playbook del balanceador de carga (tareas inline)
├── webserver.yml                  # Playbook del servidor web
├── templates/
│   └── nginx.conf.j2              # Plantilla Jinja2 para Nginx (nivel raíz)
├── demo/                          # Código fuente de la app Flask
├── playbooks/
│   ├── hostname.yml               # Diagnóstico: ping + hostname de todos los nodos
│   ├── stack_restart.yml          # Reinicio ordenado del stack
│   └── stack_status.yml           # ⭐ Verificación avanzada con uri + fail + loop
└── roles/
    ├── mysql/                     # Rol BD: instala y configura MySQL 8.0
    ├── apache2/                   # ⭐ Rol web: Apache + Flask + virtualenv (todo en uno)
    ├── control/                   # Rol nodo control: curl + python3-httplib2
    ├── demo_app/                  # Rol vacío (lógica migrada a apache2)
    └── nginx/                     # Rol vacío (lógica en loadbalancer.yml inline)
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

| **Grupo** | **IP** | **Rol / Playbook asignado** |
|---|---|---|
| `[database]` | `192.168.11.20` | Rol `mysql` |
| `[loadbalancer]` | `192.168.11.30` | Tareas inline Nginx en `loadbalancer.yml` |
| `[webserver]` | `192.168.11.40` | Rol `apache2` (incluye app Flask) |
| `[control]` | nodo local | Rol `control` |

---

## ⭐ La novedad principal: `site.yml` con `import_playbook`

```yaml
---
- import_playbook: playbooks/hostname.yml
- import_playbook: database.yml
- import_playbook: webserver.yml
- import_playbook: loadbalancer.yml
- import_playbook: control.yml
- import_playbook: playbooks/stack_restart.yml
- import_playbook: playbooks/stack_status.yml
```

### ¿Qué hace `import_playbook`?

`import_playbook` es una directiva de Ansible que **incluye otro fichero de playbook completo** en tiempo de parseo (estático). Cuando Ansible ejecuta `site.yml`, lo que realmente hace es:

1. Leer `site.yml`.
2. Sustituir cada `import_playbook` por el contenido completo del fichero referenciado.
3. Ejecutar todos los plays resultantes en secuencia, de arriba a abajo.

El resultado es que **`site.yml` actúa como un índice o tabla de contenidos** del despliegue completo, sin contener ninguna lógica propia.

### Secuencia de ejecución al lanzar `site.yml`

| **Orden** | **Fichero importado** | **Acción** |
|---|---|---|
| 1 | `playbooks/hostname.yml` | Ping + diagnóstico de hostnames en todos los nodos |
| 2 | `database.yml` | Despliega MySQL en `192.168.11.20` |
| 3 | `webserver.yml` | Despliega Apache + Flask en `192.168.11.40` |
| 4 | `loadbalancer.yml` | Despliega Nginx en `192.168.11.30` |
| 5 | `control.yml` | Prepara el nodo de control |
| 6 | `playbooks/stack_restart.yml` | Reinicia el stack en orden correcto |
| 7 | `playbooks/stack_status.yml` | Verifica que todo el stack responde correctamente |

### Diferencia entre `import_playbook` e `include_playbook`

| **Característica** | **`import_playbook`** (estático) | **`include_playbook`** (dinámico) |
|---|---|---|
| Momento de resolución | En tiempo de parseo (antes de ejecutar) | En tiempo de ejecución |
| Soporte de variables en el nombre | ❌ No | ✅ Sí |
| Visibilidad para `--list-tasks` | ✅ Sí | ❌ No |
| Uso recomendado | Estructura fija del proyecto | Inclusión condicional o dinámica |

### Comando de ejecución

```bash
# Ejecutar el despliegue + verificación completo
ansible-playbook -i hosts -u vagrant site.yml

# Ejecutar solo un playbook específico
ansible-playbook -i hosts -u vagrant database.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 📄 Playbook `playbooks/hostname.yml` — Diagnóstico inicial

```yaml
---
- hosts: all
  tasks:
    - name: Ping to servers
      ping:
    - name: Get hostname
      command: hostname
      register: hostname
    - name: Show hostname with message
      debug:
        msg: "The hostname of this server is {{ hostname.stdout }}"
```

Este playbook se ejecuta **contra todos los nodos del inventario** (`hosts: all`) y realiza tres acciones:

1. **`ping`**: Verifica que Ansible puede conectarse a cada nodo vía SSH y que Python está disponible. No es un ping ICMP — es el módulo de conectividad de Ansible.
2. **`command: hostname`**: Ejecuta el comando `hostname` en cada nodo y guarda la salida en la variable `hostname`.
3. **`debug`**: Imprime en pantalla el hostname de cada nodo con un mensaje formateado, usando `hostname.stdout` para acceder a la salida del comando registrado.

Es una herramienta de diagnóstico rápido para confirmar que el inventario es correcto y todos los nodos son accesibles antes de iniciar el despliegue.

---

## 📄 `database.yml` — Despliegue de MySQL

```yaml
---
- hosts: database
  become: true
  roles:
    - mysql
```

Aplica el rol `mysql` al grupo `[database]` con privilegios de superusuario.

---

## 📄 `webserver.yml` — Despliegue del servidor web

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
```

A diferencia de ejemplos anteriores donde se usaban dos roles (`apache2` + `demo_app`), aquí el rol `apache2` **absorbe toda la responsabilidad**: instala Apache, configura mod_wsgi, despliega el código Flask, crea el virtualenv y activa el VirtualHost.

---

## 📄 `loadbalancer.yml` — Nginx con tareas inline y handlers

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: install tools
      apt: name={{item}} state=present update_cache=yes
      loop:
        - python3-httplib2

    - name: install nginx
      apt: name=nginx state=present update_cache=yes

    - name: ensure nginx started
      service: name=nginx state=started enabled=yes

    - name: configure nginx site
      template: src=templates/nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
      notify: restart nginx

    - name: de-activate default nginx site
      file: path=/etc/nginx/sites-enabled/default state=absent
      notify: restart nginx

    - name: activate demo nginx site
      file: src=/etc/nginx/sites-available/demo dest=/etc/nginx/sites-enabled/demo state=link
      notify: restart nginx

  handlers:
    - name: restart nginx
      service: name=nginx state=restarted
```

### Puntos destacados de `loadbalancer.yml`

- **`python3-httplib2`** se instala en el loadbalancer — es la dependencia que necesita el módulo `uri` de Ansible para hacer peticiones HTTP desde este nodo.
- Las tareas de configuración de Nginx usan `notify: restart nginx` para disparar el handler solo cuando hay cambios reales.
- El handler `restart nginx` está definido **inline** en el mismo fichero (no en un rol), lo que es perfectamente válido en Ansible.
- La plantilla `nginx.conf.j2` se referencia desde `templates/nginx.conf.j2` (ruta relativa al playbook raíz).

### Plantilla `templates/nginx.conf.j2`

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

El bucle `{% for server in groups.webserver %}` itera sobre las IPs del grupo `[webserver]` del inventario. Con el inventario actual genera:

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

Si se añadieran más webservers al inventario, Nginx los balancearía automáticamente en round-robin.

---

## 📄 `control.yml` — Preparación del nodo de control

```yaml
---
- hosts: control
  become: true
  roles:
    - control
```

Aplica el rol `control`, que instala `curl` y `python3-httplib2` en el nodo de control.

---

## 🎭 Los Roles

### 🗄️ Rol `mysql` — Servidor de base de datos (mejorado)

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server-8.0 state=present update_cache=yes

- name: ensure mysql started properly
  service: name=mysql state=started enabled=yes
  register: mysql_status
  until: mysql_status is success
  retries: 5
  delay: 5

- name: read mysql_status
  debug: var=mysql_status

- name: ensure mysql listening on all ports
  lineinfile:
    dest: /etc/mysql/my.cnf
    regexp: '^\[mysqld\]'
    line: "[mysqld]\nbind-address = 0.0.0.0"
  notify: restart mysql

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

#### Novedades respecto a ejemplos anteriores

**1. Versión explícita de MySQL:**
```yaml
apt: name=mysql-server-8.0 state=present
```
Se especifica `mysql-server-8.0` en lugar de `mysql-server` genérico, garantizando una versión concreta y reproducible.

**2. Espera activa con `until/retries/delay`:**
```yaml
- name: ensure mysql started properly
  service: name=mysql state=started enabled=yes
  register: mysql_status
  until: mysql_status is success
  retries: 5
  delay: 5
```

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `register: mysql_status` | Variable | Guarda el resultado de la tarea |
| `until` | `mysql_status is success` | Condición de éxito |
| `retries` | `5` | Máximo 5 intentos |
| `delay` | `5` | 5 segundos entre intentos |

MySQL 8.0 puede tardar varios segundos en arrancar completamente. Este patrón evita que las tareas siguientes (crear BD, crear usuario) fallen porque MySQL aún no está listo.

**3. Módulo `debug` para inspección:**
```yaml
- name: read mysql_status
  debug: var=mysql_status
```
Imprime en pantalla el contenido completo de la variable `mysql_status`. Es una técnica de **observabilidad** — permite ver exactamente qué devolvió el módulo `service` durante la ejecución, útil para depuración.

**4. `lineinfile` con bloque multilinea:**
```yaml
lineinfile:
  dest: /etc/mysql/my.cnf
  regexp: '^\[mysqld\]'
  line: "[mysqld]\nbind-address = 0.0.0.0"
```
En lugar de buscar la línea `bind-address` directamente, busca la sección `[mysqld]` y la reemplaza añadiendo `bind-address = 0.0.0.0` justo debajo. Es una técnica más robusta para ficheros de configuración con secciones INI.

---

### 🌐 Rol `apache2` — Servidor web + aplicación Flask (consolidado)

```yaml
# roles/apache2/tasks/main.yml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  loop:
    - apache2
    - python3-pip
    - python3-virtualenv
    - python3-venv
    - python3-mysqldb
    - libapache2-mod-wsgi-py3

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: copy demo app source
  copy: src=demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: initialize virtualenv
  shell: python3 -m venv /var/www/demo/.venv creates=/var/www/demo/.venv

- name: source virtualenv and install app dependencies
  shell: . /var/www/demo/.venv/bin/activate && pip install -r /var/www/demo/requirements.txt
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf dest=/etc/apache2/sites-enabled/demo.conf state=link
  notify: restart apache2
```

```yaml
# roles/apache2/handlers/main.yml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

#### Flujo de ejecución del rol `apache2`

1. Instala Apache2 y todas sus dependencias Python/WSGI.
2. Arranca Apache y lo habilita en el boot.
3. Activa el módulo `mod_wsgi` — necesario para que Apache ejecute aplicaciones Python/Flask.
4. Copia el código fuente de la app Flask a `/var/www/demo`.
5. Copia el fichero de configuración del VirtualHost Apache.
6. **Crea el virtualenv** con `python3 -m venv` usando el parámetro `creates=` para que sea idempotente (no lo recrea si ya existe).
7. **Instala dependencias** activando el virtualenv con `shell` y ejecutando `pip install`.
8. **Instala dependencias de nuevo** con el módulo `pip` de Ansible (doble instalación — patrón de robustez).
9. Elimina el VirtualHost por defecto de Apache.
10. Activa el VirtualHost de la demo con un enlace simbólico.

#### Novedad: doble instalación del virtualenv

```yaml
# Método 1: shell nativo
- name: initialize virtualenv
  shell: python3 -m venv /var/www/demo/.venv creates=/var/www/demo/.venv

- name: source virtualenv and install app dependencies
  shell: . /var/www/demo/.venv/bin/activate && pip install -r /var/www/demo/requirements.txt

# Método 2: módulo pip de Ansible
- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
```

Se usan **dos enfoques en paralelo** para garantizar que el virtualenv y las dependencias quedan instaladas correctamente, independientemente de la versión de Python o del sistema operativo. El módulo `pip` de Ansible es más declarativo e idempotente; el método `shell` es más explícito y compatible con entornos donde el módulo `pip` puede tener problemas.

#### Parámetro `creates` en el módulo `shell`

```yaml
shell: python3 -m venv /var/www/demo/.venv creates=/var/www/demo/.venv
```

`creates` es un parámetro de control de idempotencia para el módulo `shell`. Le dice a Ansible: *"si este fichero/directorio ya existe, no ejecutes este comando"*. Evita recrear el virtualenv en cada ejecución del playbook.

---

### 🛠️ Rol `control` — Nodo de control

```yaml
# roles/control/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  loop:
    - curl
    - python3-httplib2
```

Instala `curl` (herramienta de línea de comandos HTTP) y `python3-httplib2` (librería Python necesaria para que el módulo `uri` de Ansible realice peticiones HTTP desde el nodo de control).

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

El reinicio sigue un **orden inverso al arranque** para evitar errores:

| **Fase** | **Acción** | **`wait_for` state** | **Descripción** |
|---|---|---|---|
| 1. Parar LB | Nginx `stopped` | `drained` | Espera a que las conexiones activas terminen antes de confirmar parada |
| 2. Parar Web | Apache `stopped` | `stopped` | Espera a que el puerto 80 deje de estar accesible |
| 3. Reiniciar BD | MySQL `restarted` | `started` | Espera a que el puerto 3306 esté disponible |
| 4. Arrancar Web | Apache `started` | *(default: started)* | Espera a que el puerto 80 esté accesible |
| 5. Arrancar LB | Nginx `started` | *(default: started)* | Espera a que el puerto 80 esté accesible |

### Estados de `wait_for`

| **`state`** | **Descripción** |
|---|---|
| `started` | Espera a que el puerto esté abierto y aceptando conexiones |
| `stopped` | Espera a que el puerto deje de estar accesible |
| `drained` | Espera a que todas las conexiones activas se cierren (graceful shutdown) |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🔍 Playbook `playbooks/stack_status.yml` — Verificación avanzada

Este es el playbook de verificación más completo del curso. Combina verificación de proceso, red y aplicación en múltiples capas.

```yaml
---
# Nivel 1: Proceso + Red
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

# Nivel 2: Aplicación (desde el loadbalancer, directamente a los webservers)
- hosts: loadbalancer
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      loop: "{{ groups.webserver }}"
      register: app_index

    - fail: msg="index failed to return content"
      when: ("Hello, from sunny " ~ item.content ~ "!") in item.content
      loop: "{{app_index.results}}"

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      loop: "{{ groups.webserver }}"
      register: app_db

    - fail: msg="db failed to return content"
      when: ("Database Connected from " ~ item.content ~ "!") in item.content
      loop: "{{app_db.results}}"

# Nivel 3: End-to-end (desde el nodo de control, a través del loadbalancer)
- hosts: control
  tasks:
    - name: get elements from loadbalancer group
      debug: var=groups.loadbalancer

    - name: verify end-to-end connectivity to loadbalancer
      uri: url=http://{{item}} return_content=yes
      loop: "{{ groups.loadbalancer }}"
      register: lb_connectivity

    - fail: msg="index failed to return content"
      when: ("Hello, from sunny " ~ item.content ~ "!") in item.content
      loop: "{{lb_connectivity.results}}"

    - name: verify end-to-end db response
      uri: url=http://{{item}}/db return_content=yes
      loop: "{{ groups.loadbalancer }}"
      register: lb_db

    - fail: msg="db failed to return content"
      when: ("Database Connected from ..." ) in item.content
      loop: "{{lb_db.results}}"
```

### Tres niveles de verificación

| **Nivel** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| **1. Proceso + Red** | Cada nodo (localhost) | Sus propios puertos | Servicio activo + puerto abierto |
| **2. Aplicación** | `loadbalancer` | `webserver` directo (bypass LB) | Flask responde en `/` y `/db` |
| **3. End-to-end** | `control` | `loadbalancer` | Todo el stack de extremo a extremo |

### El módulo `uri` con `loop` y `return_content`

```yaml
- name: verify backend index response
  uri: url=http://{{item}} return_content=yes
  loop: "{{ groups.webserver }}"
  register: app_index
```

| **Parámetro** | **Descripción** |
|---|---|
| `url=http://{{item}}` | URL construida dinámicamente con cada IP del loop |
| `return_content=yes` | Incluye el cuerpo de la respuesta HTTP en el resultado registrado |
| `loop: "{{ groups.webserver }}"` | Itera sobre todas las IPs del grupo `[webserver]` |
| `register: app_index` | Guarda **todos** los resultados del loop en una lista bajo `app_index.results` |

### El módulo `fail` con condición `when`

```yaml
- fail: msg="index failed to return content"
  when: ("Hello, from sunny " ~ item.content ~ "!") in item.content
  loop: "{{app_index.results}}"
```

El módulo `fail` **detiene el playbook con un error** si la condición `when` es verdadera. Aquí verifica que el contenido de la respuesta HTTP contiene el texto esperado de la aplicación Flask. El operador `~` en Jinja2 es la concatenación de strings.

### `debug` para inspección de variables de inventario

```yaml
- name: get elements from loadbalancer group
  debug: var=groups.loadbalancer
```

Imprime en pantalla la lista de IPs del grupo `[loadbalancer]` tal como las ve Ansible en ese momento de la ejecución. Es una técnica de depuración para confirmar que las variables de inventario tienen los valores esperados.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🔄 Flujo completo de despliegue

```bash
# Opción A: Despliegue completo con un solo comando
ansible-playbook -i hosts -u vagrant site.yml

# Opción B: Despliegue paso a paso
# 1. Diagnóstico inicial
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml

# 2. Desplegar servicios
ansible-playbook -i hosts -u vagrant database.yml
ansible-playbook -i hosts -u vagrant webserver.yml
ansible-playbook -i hosts -u vagrant loadbalancer.yml
ansible-playbook -i hosts -u vagrant control.yml

# 3. Reiniciar el stack en orden correcto
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml

# 4. Verificar el stack completo
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **015_2** | **016** |
|---|---|---|
| Punto de entrada | `site.yml` con roles directos | `site.yml` con `import_playbook` |
| Organización de playbooks | Ficheros sueltos | Orquestados desde `site.yml` |
| Roles `apache2` + `demo_app` | Separados | Consolidados en `apache2` |
| Versión MySQL | `mysql-server` genérico | `mysql-server-8.0` explícito |
| Arranque MySQL | `service: state=started` simple | `until/retries/delay` con espera activa |
| Diagnóstico de variables | No | `debug: var=mysql_status` + `debug: var=groups.loadbalancer` |
| Verificación | Proceso + red | Proceso + red + aplicación + end-to-end |
| Virtualenv | Módulo `pip` | `shell` nativo + módulo `pip` (doble robustez) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`import_playbook`**: Permite construir un orquestador maestro (`site.yml`) que importa y ejecuta otros playbooks en secuencia. Separa la estructura del proyecto de la lógica de cada componente.
- **`loop` vs `with_items`**: `loop` es la sintaxis moderna y recomendada en Ansible 2.5+. `with_items` sigue funcionando pero está en proceso de deprecación.
- **`debug: var=`**: Imprime el valor de cualquier variable Ansible en pantalla durante la ejecución. Fundamental para depuración y observabilidad.
- **`until/retries/delay` en `service`**: Patrón de espera activa para servicios que tardan en arrancar (como MySQL 8.0). Evita race conditions entre tareas.
- **`creates` en `shell`**: Hace idempotente un comando shell comprobando si un fichero/directorio ya existe antes de ejecutarlo.
- **`return_content: yes` en `uri`**: Incluye el cuerpo de la respuesta HTTP en el resultado, permitiendo verificar el contenido de la aplicación, no solo el código de estado.
- **`fail` con `when`**: Permite detener el playbook con un mensaje de error personalizado si una condición no se cumple. Es la base de las pruebas de aceptación en Ansible.
- **Verificación en tres capas**:
  - **Nivel proceso**: `service status` — ¿está corriendo el servicio?
  - **Nivel red**: `wait_for` — ¿está el puerto abierto?
  - **Nivel aplicación**: `uri` + `fail` — ¿responde la app con el contenido correcto?
- **`groups.<nombre_grupo>`**: Variable mágica de Ansible que contiene la lista de hosts de un grupo del inventario. Usada en loops para iterar dinámicamente sobre nodos.

---

## 📚 Referencias

- [Ansible Docs — import_playbook](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/import_playbook_module.html)
- [Ansible Docs — Loops (loop vs with_items)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html)
- [Ansible Docs — ansible.builtin.debug module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/debug_module.html)
- [Ansible Docs — ansible.builtin.fail module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/fail_module.html)
- [Ansible Docs — ansible.builtin.uri module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Ansible Docs — Retrying tasks (until)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#retrying-a-task-until-a-condition-is-met)
- [Jinja2 — String concatenation operator (~)](https://jinja.palletsprojects.com/en/3.1.x/templates/#math)
