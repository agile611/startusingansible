# 📋 Ejemplo 022 — `with_dict`: Iteración sobre diccionarios y consolidación del stack

## 🧭 Descripción general

Este ejemplo consolida y depura los patrones aprendidos en los ejemplos anteriores, poniendo el foco en el uso correcto y maduro de `with_dict` en el rol `nginx`. La diferencia más importante respecto al ejemplo 021 es **sintáctica pero significativa**: en 021 se usaba `with_dict: "{{ sites }}"` (con comillas y llaves de Jinja2), mientras que en 022 se usa la forma directa `with_dict: sites` — la sintaxis canónica de Ansible para referenciar variables en directivas de bucle.

Además, este ejemplo activa por primera vez la **sintaxis inline de variables en roles** en `database.yml` (que en el ejemplo 021 estaba comentada), consolidando el patrón `{ role: mysql, db_name: demo, ... }` como forma estándar de parametrizar roles. El `site.yml` también elimina la verificación automática integrada, separando el despliegue de la validación.

---

## 🗂️ Estructura del proyecto

```
022_with_dict/
├── site.yml                        # Orquestador maestro (solo despliegue)
├── control.yml                     # Playbook del nodo de control
├── database.yml                    # ⭐ Variables inline activas en el rol mysql
├── webserver.yml                   # Playbook del servidor web
├── loadbalancer.yml                # Playbook del balanceador de carga
├── demo/                           # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml                # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml           # Reinicio ordenado del stack
│   └── stack_status.yml            # Verificación end-to-end del stack
└── roles/
    ├── control/
    │   └── tasks/main.yml          # Instala curl y python-httplib2
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
        ├── tasks/main.yml          # ⭐ with_dict: sites (sintaxis directa)
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml       # ⭐ sites: diccionario myapp frontend/backend
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
| `[database]` | `192.168.11.20` | `mysql` (con variables inline) |
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
```

A diferencia del ejemplo 019 y 020, este `site.yml` **no incluye** `stack_status.yml` al final. La verificación del stack se realiza como operación independiente y explícita, separando claramente la fase de despliegue de la fase de validación.

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

### `database.yml` — ⭐ Variables inline activas

```yaml
---
- hosts: database
  become: true
  roles:
    - { role: mysql, db_name: demo, db_user_name: demo, db_user_pass: demo, db_user_host: '%' }
```

Esta es la primera vez en la serie que la sintaxis de variables inline está **activa** (no comentada). Las cuatro variables sobreescriben los valores de `roles/mysql/defaults/main.yml`:

| **Variable** | **Valor en `defaults/`** | **Valor inline (activo)** |
|---|---|---|
| `db_name` | `myapp` | `demo` |
| `db_user_name` | `dbuser` | `demo` |
| `db_user_pass` | `dbpass` | `demo` |
| `db_user_host` | `localhost` | `%` (cualquier host) |

El valor `'%'` en `db_user_host` es especialmente relevante: permite que el usuario `demo` se conecte a MySQL **desde cualquier host de la red**, lo que es necesario para que la aplicación Flask en el webserver pueda conectarse al servidor de base de datos en `192.168.11.20`.

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

#### `roles/control/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala `curl` (para pruebas manuales HTTP desde el nodo de control) y `python-httplib2` (necesario para que el módulo `uri` de Ansible funcione correctamente en Python 2).

---

### 🗄️ Rol `mysql` — Configuración con variables inline

#### `roles/mysql/defaults/main.yml`

```yaml
---
db_name: myapp
db_user_name: dbuser
db_user_pass: dbpass
db_user_host: localhost
```

Valores por defecto que actúan como documentación de la interfaz del rol. En este ejemplo todos son sobreescritos por las variables inline de `database.yml`.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-mysqldb

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

Puntos clave del flujo:

1. **`python-mysqldb`**: librería Python necesaria para que los módulos `mysql_db` y `mysql_user` de Ansible puedan comunicarse con MySQL.
2. **`lineinfile`**: modifica `bind-address` en `/etc/mysql/my.cnf` usando el Fact `ansible_eth0.ipv4.address` para que MySQL escuche en la IP privada del servidor (`192.168.11.20`), no en `127.0.0.1`.
3. **`mysql_db`**: crea la base de datos `demo` (valor que viene de la variable inline).
4. **`mysql_user`**: crea el usuario `demo` con contraseña `demo`, permisos totales sobre `demo.*`, y acceso desde cualquier host (`'%'`).

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

---

### ⚖️ Rol `nginx` — ⭐ `with_dict: sites` (sintaxis canónica)

Este es el rol central del ejemplo. La diferencia respecto al ejemplo 021 es la sintaxis de `with_dict`.

#### `roles/nginx/defaults/main.yml`

```yaml
---
sites:
  myapp:
    frontend: 80
    backend: 80
```

El diccionario `sites` define un único sitio llamado `myapp` que escucha en el puerto 80 y reenvía al backend en el puerto 80. Para añadir más sitios basta con añadir entradas al diccionario:

```yaml
sites:
  myapp:
    frontend: 80
    backend: 80
  api:
    frontend: 8080
    backend: 8080
  admin:
    frontend: 9090
    backend: 3000
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

- name: configure nginx sites
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/{{ item.key }} mode=0644
  with_dict: sites
  notify: restart nginx

- name: de-activate default nginx site
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: activate nginx sites
  file: src=/etc/nginx/sites-available/{{ item.key }}
        dest=/etc/nginx/sites-enabled/{{ item.key }}
        state=link
  with_dict: sites
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

#### ⭐ Diferencia de sintaxis: 021 vs 022

| **Ejemplo 021** | **Ejemplo 022** |
|---|---|
| `with_dict: "{{ sites }}"` | `with_dict: sites` |

Ambas formas son funcionalmente equivalentes en versiones antiguas de Ansible, pero `with_dict: sites` es la **sintaxis canónica** recomendada para directivas de bucle — la variable se referencia directamente por nombre sin envoltura Jinja2. La forma con `{{ }}` es más propia de valores dentro de módulos (`template:`, `copy:`, etc.).

#### Cómo funciona `with_dict: sites` paso a paso

Con el diccionario por defecto (`myapp`, frontend `80`, backend `80`), Ansible itera una sola vez con:

```
item.key   = "myapp"
item.value = { frontend: 80, backend: 80 }
item.value.frontend = 80
item.value.backend  = 80
```

Las tareas que usan `with_dict` ejecutan **una iteración por cada sitio** del diccionario:

| **Tarea** | **Resultado con `myapp`** |
|---|---|
| `configure nginx sites` | Genera `/etc/nginx/sites-available/myapp` desde la plantilla |
| `activate nginx sites` | Crea enlace `/etc/nginx/sites-enabled/myapp → sites-available/myapp` |

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

Con los valores del inventario y los defaults, la plantilla genera el fichero `/etc/nginx/sites-available/myapp`:

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

El bloque `upstream` itera sobre `groups.webserver` (todos los servidores del grupo `[webserver]` del inventario), añadiendo una línea `server IP:puerto` por cada uno. Con múltiples webservers, Nginx distribuiría la carga automáticamente entre todos ellos.

#### `roles/nginx/handlers/main.yml`

```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
```

---

### 🌐 Rol `apache2` — Servidor web base

#### `roles/apache2/tasks/main.yml`

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

Instala Apache2 con el módulo WSGI (necesario para servir aplicaciones Python/Flask), desactiva el sitio por defecto y arranca el servicio.

#### `roles/apache2/handlers/main.yml`

```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

---

### 🚀 Rol `demo_app` — Aplicación Flask

#### `roles/demo_app/tasks/main.yml`

```yaml
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
  file: src=/etc/apache2/sites-available/demo.conf
        dest=/etc/apache2/sites-enabled/demo.conf
        state=link
  notify: restart apache2
```

Flujo de despliegue de la aplicación:

1. Instala `python-pip`, `python-virtualenv` y `python-mysqldb` (conector Python→MySQL).
2. Copia el código fuente de la app Flask a `/var/www/demo/`.
3. Copia el VirtualHost de Apache para la app.
4. Crea un entorno virtual Python en `/var/www/demo/.venv` e instala las dependencias de `requirements.txt`.
5. Activa el sitio creando un enlace simbólico en `sites-enabled/`.

Cada tarea dispara `notify: restart apache2`, pero Apache solo se reinicia **una vez al final** del play gracias al sistema de handlers de Ansible.

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

Reinicio ordenado y seguro del stack completo en cinco fases:

| **Fase** | **Nodo** | **Acción** | **Condición de avance** |
|---|---|---|---|
| 1 | `loadbalancer` | Para Nginx | Puerto 80 drenado (sin conexiones activas) |
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
      wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 timeout=1

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

#### ⭐ Novedad en la verificación backend: `item.item`

La verificación directa desde el loadbalancer hacia cada webserver usa una condición más estricta que en el ejemplo 021:

```yaml
# Ejemplo 021 — verificación genérica
when: "'Hello, from sunny' not in item.content"

# Ejemplo 022 — verificación específica por servidor
when: "'Hello, from sunny {{item.item}}!' not in item.content"
```

`item.item` contiene el valor original sobre el que se iteró (la IP del webserver). Esto significa que la verificación comprueba que la respuesta HTTP del webserver `192.168.11.40` contiene literalmente `"Hello, from sunny 192.168.11.40!"` — validando no solo que el servidor responde, sino que responde **con su propia identidad**. Esto detecta casos donde un servidor podría estar devolviendo una respuesta cacheada o incorrecta de otro nodo.

La misma lógica aplica a la verificación de base de datos: `'Database Connected from {{item.item}}!'`.

Verificación completa en cuatro capas:

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer:80` | `"Hello, from sunny"` en la respuesta |
| End-to-end DB | `control` | `loadbalancer:80/db` | `"Database Connected from"` en la respuesta |
| Backend directo index | `loadbalancer` | cada `webserver:80` | `"Hello, from sunny 192.168.11.40!"` (IP específica) |
| Backend directo DB | `loadbalancer` | cada `webserver:80/db` | `"Database Connected from 192.168.11.40!"` (IP específica) |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🚀 Comandos de ejecución

### Despliegue completo

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

### Sobreescribir el diccionario `sites` desde la línea de comandos

```bash
# Desplegar un sitio en puerto alternativo
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e '{"sites": {"myapp": {"frontend": 8080, "backend": 80}}}'

# Desplegar múltiples sitios
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e '{"sites": {"app1": {"frontend": 80, "backend": 80}, "app2": {"frontend": 8080, "backend": 8080}}}'
```

### Sobreescribir variables de base de datos

```bash
ansible-playbook -i hosts -u vagrant database.yml \
  -e "db_name=production db_user_name=produser db_user_pass=s3cr3t db_user_host=%"
```

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **021** | **022** |
|---|---|---|
| Variables inline en `database.yml` | Comentadas (inactivas) | ⭐ Activas: `db_user_host: '%'` |
| Sintaxis `with_dict` en nginx | `with_dict: "{{ sites }}"` | ⭐ `with_dict: sites` (canónica) |
| `stack_status` en `site.yml` | Incluido automáticamente | ⭐ Separado (solo bajo demanda) |
| Verificación backend | Genérica (`'Hello, from sunny'`) | ⭐ Específica por IP (`'Hello, from sunny {{item.item}}!'`) |
| Nombre del sitio Nginx | `myappguillem` | ⭐ `myapp` (simplificado) |
| `db_host_ipv4` en mysql | Variable configurable | Vuelve a usar `ansible_eth0.ipv4.address` (Fact) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`with_dict: nombre_variable`** (sin `{{ }}`): La sintaxis canónica para iterar sobre diccionarios en directivas de bucle de Ansible. Expone `item.key` (clave del diccionario) e `item.value` (valor, que puede ser a su vez un diccionario anidado con `item.value.propiedad`).

- **Variables inline activas `{ role: mysql, var: valor }`**: Cuando se pasan variables inline al invocar un rol, estas sobreescriben los `defaults/` del rol con la **prioridad de variables de play**, que es superior a `defaults/` pero inferior a `--extra-vars`. Es la forma más explícita y localizada de configurar un rol para un contexto específico.

- **`db_user_host: '%'`**: El valor `'%'` en MySQL significa "cualquier host". Es necesario cuando la aplicación y la base de datos están en servidores distintos — sin este valor, MySQL rechazaría conexiones remotas aunque el `bind-address` esté configurado correctamente.

- **`item.item` en verificaciones anidadas**: Cuando se usa `with_items` sobre los resultados de un `register`, `item` es el objeto resultado y `item.item` es el valor original de la iteración que generó ese resultado. Permite verificaciones específicas por servidor, no solo genéricas.

- **Separación despliegue/verificación**: Eliminar `stack_status.yml` del `site.yml` es una decisión de diseño válida cuando la verificación es costosa o cuando se quiere controlar explícitamente cuándo se valida el estado del sistema.

- **Idempotencia con `with_dict`**: Las tareas de nginx (configurar + activar sitios) son idempotentes: ejecutarlas múltiples veces produce el mismo resultado. Si el fichero de configuración ya existe con el mismo contenido, Ansible no lo modifica ni reinicia nginx.

---

## 📚 Referencias

- [Ansible Docs — `with_dict` loop](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html#with-dict)
- [Ansible Docs — Passing variables to roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#passing-variables-to-roles)
- [Ansible Docs — Registering variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#registering-variables)
- [Ansible Docs — `uri` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Ansible Docs — `fail` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/fail_module.html)
- [MySQL Docs — Account names and host specification](https://dev.mysql.com/doc/refman/8.0/en/account-names.html)
