# 📋 Ejemplo 023 — `selective_removal`: Eliminación selectiva de sitios Nginx obsoletos

## 🧭 Descripción general

Este ejemplo introduce el patrón de **eliminación selectiva** (*selective removal*) en la gestión de sitios Nginx. El problema que resuelve es concreto: cuando el diccionario `sites` cambia entre ejecuciones del playbook (por ejemplo, se renombra un sitio de `myapp` a `myapp20211216`), los ficheros de configuración y enlaces simbólicos del sitio antiguo quedan huérfanos en el servidor — Nginx los sigue sirviendo aunque ya no estén definidos en Ansible.

La solución implementada en el rol `nginx` combina tres tareas encadenadas que forman un patrón de **reconciliación de estado**:

1. **Leer** el estado real del sistema con `shell: ls /etc/nginx/sites-enabled` → `register: result`
2. **Comparar** cada sitio activo contra el diccionario `sites` con `when: item not in sites`
3. **Eliminar** solo los sitios que ya no están en el diccionario con `file: state=absent`

Este patrón garantiza que el estado del servidor siempre converge exactamente con lo declarado en el diccionario `sites`, sin dejar residuos de configuraciones anteriores.

---

## 🗂️ Estructura del proyecto

```
023_selective_removal/
├── site.yml                        # Orquestador maestro (despliegue + verificación)
├── control.yml                     # Playbook del nodo de control
├── database.yml                    # ⭐ Variables inline: db eureka / user eurekademo
├── webserver.yml                   # Playbook del servidor web
├── loadbalancer.yml                # Playbook del balanceador de carga
├── demo/                           # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml                # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml           # Reinicio ordenado del stack
│   └── stack_status.yml            # Verificación end-to-end del stack
└── roles/
    ├── control/
    │   └── tasks/main.yml          # curl + python-httplib2
    ├── mysql/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── defaults/main.yml       # db_name, db_user_name, db_user_pass, db_user_host
    ├── apache2/
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── files/
    └── nginx/
        ├── tasks/main.yml          # ⭐ NOVEDAD: shell + register + when + selective removal
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml       # ⭐ sites: myapp20211216 (nombre con timestamp)
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
| `[database]` | `192.168.11.20` | `mysql` (con variables inline `eureka`) |
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

Vuelve al patrón del ejemplo 020: el `site.yml` incluye la verificación automática del stack al final del despliegue, garantizando atomicidad — el despliegue no se considera exitoso si `stack_status.yml` falla.

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

### `database.yml` — Variables inline con base de datos `eureka`

```yaml
---
- hosts: database
  become: true
  roles:
    - { role: mysql, db_name: eureka, db_user_name: eurekademo, db_user_pass: eurekademo, db_user_host: '%' }
```

Respecto al ejemplo 022 (que usaba `db_name: demo`), este ejemplo cambia completamente las credenciales de la base de datos:

| **Variable** | **Ejemplo 022** | **Ejemplo 023** |
|---|---|---|
| `db_name` | `demo` | `eureka` |
| `db_user_name` | `demo` | `eurekademo` |
| `db_user_pass` | `demo` | `eurekademo` |
| `db_user_host` | `%` | `%` |

Este cambio ilustra exactamente el caso de uso del patrón de eliminación selectiva: si el nombre de la base de datos o del sitio cambia entre ejecuciones, los recursos antiguos deben limpiarse. El nombre `eureka` es una referencia al servicio de descubrimiento de microservicios, sugiriendo que el ejemplo simula un entorno de aplicación más realista.

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

### 🔧 Rol `control` — Herramientas de red

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala `curl` para pruebas HTTP manuales y `python-httplib2` para el módulo `uri` de Ansible.

---

### 🗄️ Rol `mysql` — Configuración con credenciales `eureka`

#### `roles/mysql/defaults/main.yml`

```yaml
---
db_name: myapp
db_user_name: dbuser
db_user_pass: dbpass
db_user_host: localhost
```

Los defaults actúan como documentación de la interfaz del rol. En este ejemplo todos son sobreescritos por las variables inline de `database.yml`.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

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

Con las variables inline activas, las últimas dos tareas crean:
- Base de datos: `eureka`
- Usuario: `eurekademo` con contraseña `eurekademo`, permisos totales sobre `eureka.*` desde cualquier host (`%`)

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

---

### ⚖️ Rol `nginx` — ⭐ NOVEDAD PRINCIPAL: eliminación selectiva

Este es el rol central del ejemplo. Introduce el patrón de reconciliación de estado para limpiar sitios obsoletos.

#### `roles/nginx/defaults/main.yml`

```yaml
---
sites:
  myapp20211216:
    frontend: 80
    backend: 80
```

El nombre del sitio ha cambiado de `myapp` (ejemplo 022) a `myapp20211216` (con timestamp de fecha). Este cambio de nombre es precisamente el escenario que motiva el patrón de eliminación selectiva: si en el servidor aún existe un enlace simbólico `/etc/nginx/sites-enabled/myapp` del despliegue anterior, Nginx lo seguiría sirviendo aunque ya no esté en el diccionario `sites`.

#### `roles/nginx/tasks/main.yml` — ⭐ El patrón completo

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

#### Análisis detallado del patrón de eliminación selectiva

El corazón del ejemplo son estas tres tareas encadenadas:

**Paso 1 — Leer el estado real del sistema:**

```yaml
- name: get active sites
  shell: ls /etc/nginx/sites-enabled
  register: result
```

El módulo `shell` ejecuta `ls /etc/nginx/sites-enabled` en el servidor remoto y guarda la salida en la variable `result`. La variable registrada tiene esta estructura:

```json
{
  "stdout": "default\nmyapp\nmyapp20211216",
  "stdout_lines": ["default", "myapp", "myapp20211216"],
  "stderr": "",
  "rc": 0
}
```

`result.stdout_lines` es una lista con un elemento por línea de salida — es decir, un elemento por cada fichero encontrado en `sites-enabled/`.

**Paso 2 — Comparar y eliminar selectivamente:**

```yaml
- name: de-activate sites
  file: path=/etc/nginx/sites-enabled/{{ item }} state=absent
  with_items: "{{ result.stdout_lines }}"
  when: item not in sites
  notify: restart nginx
```

Esta tarea itera sobre cada fichero encontrado en `sites-enabled/` y lo elimina **solo si su nombre no está en el diccionario `sites`**. La condición `when: item not in sites` usa el operador `not in` de Python/Jinja2 para comprobar si el nombre del fichero existe como clave en el diccionario.

Ejemplo de ejecución con estado previo `[default, myapp, myapp20211216]` y `sites = {myapp20211216: ...}`:

| **Fichero en `sites-enabled/`** | **¿Está en `sites`?** | **Acción** |
|---|---|---|
| `default` | ❌ No | 🗑️ Eliminado (`state=absent`) |
| `myapp` | ❌ No (era el nombre anterior) | 🗑️ Eliminado (`state=absent`) |
| `myapp20211216` | ✅ Sí | ⏭️ Ignorado (`when` es `false`) |

**Paso 3 — Activar los sitios del diccionario:**

```yaml
- name: activate nginx sites
  file: src=/etc/nginx/sites-available/{{ item.key }}
        dest=/etc/nginx/sites-enabled/{{ item.key }}
        state=link
  with_dict: "{{ sites }}"
  notify: restart nginx
```

Crea el enlace simbólico para cada sitio del diccionario. Si el enlace ya existe (segunda ejecución), Ansible lo deja intacto — idempotencia garantizada.

#### Flujo completo del rol nginx con estado previo

```
Estado inicial del servidor (ejecución anterior con 'myapp'):
  /etc/nginx/sites-enabled/
    ├── default          (sitio por defecto de Nginx)
    └── myapp            (sitio del ejemplo 022)

Ejecución del rol nginx (ejemplo 023, sites = {myapp20211216}):

  1. [configure nginx sites]
     → Genera /etc/nginx/sites-available/myapp20211216

  2. [get active sites]
     → result.stdout_lines = ["default", "myapp"]

  3. [de-activate sites] — itera sobre ["default", "myapp"]
     → "default" not in sites → ELIMINA /etc/nginx/sites-enabled/default
     → "myapp"   not in sites → ELIMINA /etc/nginx/sites-enabled/myapp

  4. [activate nginx sites]
     → Crea enlace /etc/nginx/sites-enabled/myapp20211216

Estado final del servidor:
  /etc/nginx/sites-enabled/
    └── myapp20211216    (único sitio activo, exactamente lo declarado)
```

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

Con los valores del diccionario (`myapp20211216`, frontend `80`, backend `80`) y el inventario, genera:

```nginx
upstream myapp20211216 {
    server 192.168.11.40:80;
}

server {
    listen 80;

    location / {
        proxy_pass http://myapp20211216;
    }
}
```

#### `roles/nginx/handlers/main.yml`

```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
```

Nginx solo se reinicia una vez al final del play, aunque múltiples tareas hayan disparado `notify: restart nginx`. Esto es especialmente importante en este rol: la eliminación de sitios obsoletos y la activación de nuevos sitios son operaciones separadas, pero Nginx solo se recarga una vez cuando ambas han terminado.

---

### 🌐 Rol `apache2`

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

---

### 🚀 Rol `demo_app`

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

| **Fase** | **Nodo** | **Acción** | **Condición de avance** |
|---|---|---|---|
| 1 | `loadbalancer` | Para Nginx | Puerto 80 drenado |
| 2 | `webserver` | Para Apache | Puerto 80 cerrado |
| 3 | `database` | Reinicia MySQL | Puerto 3306 activo en IP real |
| 4 | `webserver` | Arranca Apache | Puerto 80 activo |
| 5 | `loadbalancer` | Arranca Nginx | Puerto 80 activo |

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
```

> ⚠️ **Nota:** Las tareas de verificación `fail` para el backend directo están **comentadas** en este ejemplo (`#`), lo que significa que la verificación desde el loadbalancer hacia los webservers solo comprueba que se recibe *alguna* respuesta HTTP, pero no valida el contenido. Esto puede ser intencional para simplificar la validación durante el desarrollo del patrón de eliminación selectiva.

Verificación en cuatro capas:

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer:80` | `"Hello, from sunny"` en la respuesta |
| End-to-end DB | `control` | `loadbalancer:80/db` | `"Database Connected from"` en la respuesta |
| Backend directo | `loadbalancer` | cada `webserver:80` | Solo que responde (sin validar contenido) |

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

### Simular un cambio de nombre de sitio (caso de uso principal)

```bash
# Primera ejecución: despliega con el sitio 'myapp20211216' (por defecto)
ansible-playbook -i hosts -u vagrant loadbalancer.yml

# Segunda ejecución: cambia el nombre del sitio — el antiguo se elimina automáticamente
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e '{"sites": {"myapp20220101": {"frontend": 80, "backend": 80}}}'
# → myapp20211216 se elimina de sites-enabled/
# → myapp20220101 se crea en sites-available/ y se enlaza en sites-enabled/
```

### Desplegar múltiples sitios con eliminación selectiva

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e '{"sites": {"app_v2": {"frontend": 80, "backend": 80}, "api_v2": {"frontend": 8080, "backend": 8080}}}'
# → Todos los sitios no listados aquí serán eliminados de sites-enabled/
```

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **022** | **023** |
|---|---|---|
| Nombre del sitio Nginx | `myapp` | ⭐ `myapp20211216` (con timestamp) |
| Limpieza de sitios obsoletos | ❌ No existe — residuos manuales | ⭐ Automática con `shell` + `register` + `when: not in` |
| `get active sites` | No existe | ⭐ `shell: ls /etc/nginx/sites-enabled` → `register: result` |
| `de-activate sites` | No existe | ⭐ `file: state=absent` + `when: item not in sites` |
| Credenciales BD | `demo/demo` | ⭐ `eureka/eurekademo` (más realistas) |
| `stack_status` en `site.yml` | No incluido | ⭐ Incluido (verificación automática) |
| Verificación backend en `stack_status` | Activa con `item.item` | Comentada (simplificada) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Patrón de reconciliación de estado** (`shell` + `register` + `when: not in`): Leer el estado real del sistema, compararlo con el estado deseado declarado en Ansible, y actuar solo sobre las diferencias. Este es el núcleo del enfoque de **infraestructura declarativa**: el servidor siempre converge al estado exacto definido en el código, sin residuos de configuraciones anteriores.

- **`shell` + `register`**: El módulo `shell` ejecuta un comando arbitrario en el nodo remoto y `register` captura su salida completa en una variable. `result.stdout_lines` convierte la salida de texto en una lista Python, una por línea — ideal para iterar sobre ficheros, procesos o cualquier salida de comandos de sistema.

- **`when: item not in dict`**: El operador `not in` de Jinja2/Python comprueba si un valor existe como **clave** en un diccionario (o como elemento en una lista). Aplicado a `with_items` sobre la lista de ficheros del sistema, permite filtrar exactamente qué elementos deben eliminarse.

- **`file: state=absent`**: La forma idiomática de Ansible para eliminar un fichero, directorio o enlace simbólico. Es idempotente: si el fichero ya no existe, la tarea simplemente reporta `ok` sin error.

- **Idempotencia del patrón completo**: La secuencia `get active sites` → `de-activate sites` → `activate nginx sites` es completamente idempotente. En la segunda ejecución con el mismo diccionario `sites`: `get active sites` devuelve solo `myapp20211216`, `de-activate sites` no encuentra nada que eliminar (todos los sitios activos están en `sites`), y `activate nginx sites` verifica que el enlace ya existe.

- **Nombres de sitio con timestamp**: Usar nombres como `myapp20211216` en lugar de `myapp` es una práctica de gestión de configuración que facilita el seguimiento de versiones desplegadas. Cada cambio de nombre fuerza una limpieza del sitio anterior, garantizando que no haya configuraciones mezcladas.

---

## 📚 Referencias

- [Ansible Docs — `shell` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/shell_module.html)
- [Ansible Docs — Registering variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#registering-variables)
- [Ansible Docs — Conditionals (`when`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [Ansible Docs — `file` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Ansible Docs — `with_dict` loop](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#with-dict)
- [Jinja2 — `in` operator](https://jinja.palletsprojects.com/en/3.1.x/templates/#comparisons)
