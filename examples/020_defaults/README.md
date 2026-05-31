# 📋 Ejemplo 020 — `defaults/`: Variables por defecto en Roles

## 🧭 Descripción general

Este ejemplo introduce el directorio **`defaults/`** dentro de los roles de Ansible, que permite definir **variables con la prioridad más baja** del sistema de precedencia de variables de Ansible. La idea central es que un rol declare sus propios valores por defecto sensatos, que pueden ser sobreescritos fácilmente desde cualquier nivel superior: `vars/`, `group_vars/`, `host_vars/`, o directamente en el playbook con `vars:`.

La gran diferencia respecto al ejemplo 019 es que las configuraciones que antes estaban hardcodeadas en las tareas (nombre de la base de datos, usuario, contraseña, puerto, nombre de la app) ahora viven en `roles/<nombre>/defaults/main.yml`, haciendo los roles **completamente reutilizables y configurables** sin modificar su código interno.

---

## 🗂️ Estructura del proyecto

```
020_defaults/
├── site.yml                       # Orquestador maestro
├── control.yml                    # Playbook del nodo de control
├── database.yml                   # Playbook del servidor de base de datos
├── webserver.yml                  # Playbook del servidor web
├── loadbalancer.yml               # Playbook del balanceador de carga
├── demo/                          # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml               # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml          # Reinicio ordenado del stack
│   └── stack_status.yml           # Verificación avanzada del stack
└── roles/
    ├── control/
    │   ├── tasks/main.yml
    │   └── defaults/main.yml      # ⭐ Variables por defecto del rol control
    ├── mysql/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   ├── files/my.cnf
    │   └── defaults/main.yml      # ⭐ db_name, db_user, db_password, db_port
    ├── apache2/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── defaults/main.yml      # ⭐ apache_port
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   ├── files/
    │   └── defaults/main.yml      # ⭐ app_name, app_path, app_port
    └── nginx/
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml      # ⭐ nginx_port, backend_group
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

## ⭐ Concepto central: el directorio `defaults/`

### ¿Qué es `defaults/main.yml`?

Cada rol en Ansible puede tener un directorio `defaults/` con un fichero `main.yml`. Las variables definidas aquí tienen la **prioridad más baja** de todo el sistema de variables de Ansible — son los valores de "último recurso" que se usan cuando nadie más ha definido esa variable.

```
roles/
└── mysql/
    └── defaults/
        └── main.yml    ← Variables con prioridad MÍNIMA
```

### `defaults/` vs `vars/`

| **Directorio** | **Prioridad** | **Propósito** |
|---|---|---|
| `roles/<rol>/defaults/main.yml` | ⬇️ **Muy baja** (15 de 22) | Valores por defecto sobreescribibles — interfaz pública del rol |
| `roles/<rol>/vars/main.yml` | ⬆️ **Alta** (18 de 22) | Variables internas del rol — difíciles de sobreescribir |

La regla práctica es:
- Usa **`defaults/`** para todo lo que quieras que el usuario del rol pueda configurar fácilmente.
- Usa **`vars/`** para constantes internas que no deben cambiar.

### Jerarquía de precedencia de variables (simplificada)

```
Prioridad MAYOR (gana siempre)
  ↑  --extra-vars en línea de comandos
  ↑  vars: en el play
  ↑  host_vars/
  ↑  group_vars/
  ↑  roles/<rol>/vars/main.yml
  ↓  roles/<rol>/defaults/main.yml   ← defaults/ está aquí (muy baja)
Prioridad MENOR (se sobreescribe fácilmente)
```

Esto significa que si defines `db_name: demo` en `defaults/main.yml` del rol `mysql`, cualquier nivel superior puede sobreescribirlo sin modificar el rol.

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

Idéntico al ejemplo 019: despliega todo el stack y verifica automáticamente al final con `stack_status.yml`.

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

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
```

---

## 🛠️ Los Roles con `defaults/`

### 🗄️ Rol `mysql` — ⭐ Variables por defecto de base de datos

#### `roles/mysql/defaults/main.yml`

```yaml
---
db_name: demo
db_user: demo
db_password: demo
db_port: 3306
```

Estas cuatro variables definen la **interfaz configurable** del rol `mysql`. Cualquier proyecto que use este rol puede sobreescribirlas sin tocar el código del rol.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb
    - mysql-server

- name: copy original config file
  copy: src=files/my.cnf dest=/etc/mysql/my.cnf owner=mysql group=mysql mode=0700

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create demo database
  mysql_db: name={{ db_name }} state=present

- name: create demo user
  mysql_user: name={{ db_user }} password={{ db_password }}
              priv={{ db_name }}.*:ALL host='%' state=present
```

#### Diferencia clave respecto al ejemplo 019

| **019 (hardcodeado)** | **020 (con defaults)** |
|---|---|
| `mysql_db: name=demo` | `mysql_db: name={{ db_name }}` |
| `mysql_user: name=demo password=demo` | `mysql_user: name={{ db_user }} password={{ db_password }}` |
| `priv=demo.*:ALL` | `priv={{ db_name }}.*:ALL` |

Las tareas ahora referencian variables en lugar de valores literales. El valor real viene de `defaults/main.yml` — pero puede sobreescribirse desde cualquier nivel superior.

#### Cómo sobreescribir los defaults en el playbook

```yaml
# database.yml — sobreescribir defaults del rol mysql
- hosts: database
  become: true
  vars:
    db_name: myapp_production
    db_user: myapp_user
    db_password: "s3cr3t_p4ssw0rd"
  roles:
    - mysql
```

O desde `group_vars/database.yml`:

```yaml
# group_vars/database.yml
db_name: myapp_production
db_user: myapp_user
db_password: "s3cr3t_p4ssw0rd"
```

---

### 🌐 Rol `apache2` — Variables por defecto del servidor web

#### `roles/apache2/defaults/main.yml`

```yaml
---
apache_port: 80
```

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

La variable `apache_port` se usa en la plantilla del VirtualHost de `demo_app` para configurar el puerto en el que Apache escucha, permitiendo cambiar el puerto sin modificar ningún fichero de configuración.

---

### 🚀 Rol `demo_app` — Variables por defecto de la aplicación

#### `roles/demo_app/defaults/main.yml`

```yaml
---
app_name: demo
app_path: /var/www/demo
app_port: 80
```

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
  copy: src=demo/app/ dest={{ app_path }} mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements={{ app_path }}/requirements.txt
       virtualenv={{ app_path }}/.venv
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/{{ app_name }}.conf
        dest=/etc/apache2/sites-enabled/{{ app_name }}.conf
        state=link
  notify: restart apache2
```

#### Diferencia clave respecto al ejemplo 019

| **019 (hardcodeado)** | **020 (con defaults)** |
|---|---|
| `dest=/var/www/demo` | `dest={{ app_path }}` |
| `requirements=/var/www/demo/requirements.txt` | `requirements={{ app_path }}/requirements.txt` |
| `virtualenv=/var/www/demo/.venv` | `virtualenv={{ app_path }}/.venv` |
| `src=.../demo.conf` | `src=.../{{ app_name }}.conf` |
| `dest=.../demo.conf` | `dest=.../{{ app_name }}.conf` |

El rol `demo_app` ahora puede desplegar **cualquier aplicación Flask** simplemente cambiando `app_name` y `app_path` — sin modificar el rol.

---

### ⚖️ Rol `nginx` — Variables por defecto del balanceador

#### `roles/nginx/defaults/main.yml`

```yaml
---
nginx_port: 80
backend_group: webserver
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

- name: configure nginx site
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
  notify: restart nginx

- name: de-activate default nginx site
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: activate demo nginx site
  file: src=/etc/nginx/sites-available/demo
        dest=/etc/nginx/sites-enabled/demo
        state=link
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

#### Plantilla `roles/nginx/templates/nginx.conf.j2` — con defaults

```jinja2
upstream demo {
{% for server in groups[backend_group] %}
    server {{ server }};
{% endfor %}
}

server {
    listen {{ nginx_port }};

    location / {
        proxy_pass http://demo;
    }
}
```

#### Diferencia clave respecto al ejemplo 019

| **019 (hardcodeado)** | **020 (con defaults)** |
|---|---|
| `listen 80;` | `listen {{ nginx_port }};` |
| `groups.webserver` | `groups[backend_group]` |

La variable `backend_group` en `groups[backend_group]` usa **notación de corchetes** para acceder dinámicamente al grupo del inventario cuyo nombre está almacenado en la variable. Con el valor por defecto `webserver`, genera exactamente el mismo resultado que antes — pero ahora puede apuntar a cualquier grupo del inventario.

---

## 📄 Playbook `playbooks/hostname.yml`

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

## 🔄 Playbook `playbooks/stack_restart.yml`

```yaml
---
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

- hosts: database
  become: true
  tasks:
    - service: name=mysql state=restarted
    - wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 state=started

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

Mantiene el patrón del ejemplo 019 con `host={{ ansible_eth0.ipv4.address }}` para verificar MySQL en su IP real.

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🔍 Playbook `playbooks/stack_status.yml`

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
      when: "'Database Connected' not in item.content"
      with_items: "{{app_db.results}}"
```

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

### Sobreescribir defaults desde la línea de comandos

```bash
# Desplegar con una base de datos diferente
ansible-playbook -i hosts -u vagrant database.yml \
  -e "db_name=myapp db_user=myuser db_password=mypass"

# Desplegar Nginx en un puerto diferente
ansible-playbook -i hosts -u vagrant loadbalancer.yml \
  -e "nginx_port=8080"

# Desplegar la app en una ruta diferente
ansible-playbook -i hosts -u vagrant webserver.yml \
  -e "app_name=myapp app_path=/var/www/myapp"
```

> ⭐ `--extra-vars` (`-e`) tiene la **prioridad más alta** de todo el sistema de variables de Ansible, por lo que siempre sobreescribe los `defaults/`.

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **019** | **020** |
|---|---|---|
| Nombre de BD | `name=demo` (hardcodeado) | ⭐ `name={{ db_name }}` (desde `defaults/`) |
| Usuario de BD | `name=demo password=demo` (hardcodeado) | ⭐ `name={{ db_user }} password={{ db_password }}` |
| Ruta de la app | `/var/www/demo` (hardcodeada) | ⭐ `{{ app_path }}` (desde `defaults/`) |
| Nombre de la app | `demo.conf` (hardcodeado) | ⭐ `{{ app_name }}.conf` (desde `defaults/`) |
| Puerto de Nginx | `listen 80` (hardcodeado) | ⭐ `listen {{ nginx_port }}` (desde `defaults/`) |
| Grupo backend Nginx | `groups.webserver` (hardcodeado) | ⭐ `groups[backend_group]` (desde `defaults/`) |
| Reutilización de roles | Baja — roles acoplados a `demo` | ⭐ Alta — roles configurables para cualquier proyecto |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`defaults/main.yml`**: El directorio de variables con prioridad más baja en Ansible. Define la **interfaz pública configurable** de un rol — los parámetros que el usuario del rol puede ajustar sin modificar su código interno.
- **`defaults/` vs `vars/`**: `defaults/` es para valores sobreescribibles (interfaz del rol); `vars/` es para constantes internas del rol. La diferencia es de intención y prioridad.
- **Roles reutilizables**: Al parametrizar nombres, rutas y puertos con variables en `defaults/`, el mismo rol puede usarse para desplegar múltiples aplicaciones o entornos sin duplicar código.
- **`groups[variable]`**: La notación de corchetes permite acceder a un grupo del inventario cuyo nombre está almacenado en una variable (`groups[backend_group]`), haciendo las plantillas Jinja2 dinámicas respecto al grupo de servidores backend.
- **`--extra-vars` (`-e`)**: La forma más directa de sobreescribir `defaults/` desde la línea de comandos, con la prioridad más alta del sistema. Ideal para despliegues en diferentes entornos (dev, staging, prod) con un único playbook.
- **Separación entre código e configuración**: Los roles definen el *cómo* (tareas); `defaults/` define el *qué* (parámetros). Esta separación es el principio fundamental de los roles reutilizables en Ansible.

---

## 📚 Referencias

- [Ansible Docs — Defaults variables in roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html#role-defaults)
- [Ansible Docs — Variable precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Ansible Docs — Using variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html)
- [Ansible Docs — Special Variables — `groups`](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
