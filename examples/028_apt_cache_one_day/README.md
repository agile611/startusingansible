# 📋 Ejemplo 028 — `apt_cache_one_day`: Optimización del caché APT con `cache_valid_time`

## 🧭 Descripción general

Este ejemplo introduce una segunda optimización de rendimiento en Ansible, complementaria a `gather_facts: false` del ejemplo 027: el uso de **`cache_valid_time`** en el módulo `apt`. El cambio es quirúrgico — una sola línea nueva en cada rol — pero su impacto en el tiempo de despliegue es significativo cuando el playbook se ejecuta varias veces en el mismo día.

El patrón anterior (`update_cache=yes` en cada tarea `apt`) ejecutaba `apt-get update` en el servidor remoto cada vez que se instalaba un paquete, incluso si el caché ya estaba actualizado de hace 5 minutos. Con `cache_valid_time=86400`, Ansible comprueba la antigüedad del caché APT del servidor y solo ejecuta `apt-get update` si el caché tiene más de 86.400 segundos (24 horas) de antigüedad. Si el caché es más reciente, la actualización se omite completamente. El resto del proyecto (playbooks, `group_vars/all`, plantillas) es idéntico al ejemplo 027.

---

## 🗂️ Estructura del proyecto

```
028_apt_cache_one_day/
├── site.yml
├── control.yml                       # gather_facts: false (de 027)
├── database.yml                      # gather_facts: true (necesita ansible_eth0)
├── webserver.yml                     # gather_facts: false (de 027)
├── loadbalancer.yml                  # gather_facts: false (de 027)
├── group_vars/
│   └── all                           # Variables en texto plano
├── playbooks/
│   ├── stack_status.yml
│   └── stack_restart.yml
└── roles/
    ├── control/
    │   └── tasks/main.yml            # ⭐ update apt cache once day
    ├── mysql/
    │   ├── tasks/main.yml            # ⭐ update apt cache once day
    │   ├── handlers/main.yml
    │   └── defaults/main.yml
    ├── apache2/
    │   ├── tasks/main.yml            # ⭐ update apt cache once day
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml            # ⭐ update apt cache once day
    │   ├── handlers/main.yml
    │   └── templates/demo.wsgi.j2
    └── nginx/
        ├── tasks/main.yml            # ⭐ update apt cache once day
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml
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

## ⭐ NOVEDAD PRINCIPAL: `cache_valid_time=86400`

### El problema: `update_cache=yes` en cada tarea

En los ejemplos anteriores, cada tarea `apt` que instalaba paquetes incluía `update_cache=yes`:

```yaml
# Patrón ANTERIOR (ejemplos 025-027)
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes
```

Esto significa que `apt-get update` se ejecuta **dos veces** solo en el rol `mysql` — una por cada tarea `apt`. En un rol con 5 tareas `apt`, se ejecuta 5 veces. Cada `apt-get update` descarga los índices de todos los repositorios configurados, lo que puede tardar entre **5 y 30 segundos** por ejecución dependiendo de la velocidad de red.

### La solución: separar `update_cache` en una tarea dedicada con `cache_valid_time`

```yaml
# Patrón NUEVO (ejemplo 028) — primera tarea de cada rol
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

# Resto de tareas SIN update_cache
- name: install tools
  apt: name={{item}} state=present
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present
```

### ¿Cómo funciona `cache_valid_time`?

`cache_valid_time` es un parámetro del módulo `apt` que indica la antigüedad máxima aceptable del caché APT local del servidor remoto, expresada en **segundos**:

```
cache_valid_time=86400
                 ─────
                 86400 segundos = 60 × 60 × 24 = 24 horas = 1 día
```

Cuando Ansible ejecuta `apt: update_cache=yes cache_valid_time=86400`, el módulo comprueba el timestamp del fichero `/var/cache/apt/pkgcache.bin` en el servidor remoto:

```
¿Antigüedad del caché APT < 86400 segundos (24h)?
  ├── SÍ → Omitir apt-get update  →  status: ok (skipped)  →  0 segundos
  └── NO → Ejecutar apt-get update →  status: changed       →  5-30 segundos
```

### Impacto en el rendimiento

Con el inventario de este ejemplo y un despliegue completo:

| **Escenario** | **`update_cache=yes` (sin `cache_valid_time`)** | **`cache_valid_time=86400`** |
|---|---|---|
| Primera ejecución del día | `apt-get update` × N tareas apt | `apt-get update` × 1 (una por rol) |
| Segunda ejecución (mismo día) | `apt-get update` × N tareas apt | ✅ Omitido (caché válido) |
| Ejecución al día siguiente | `apt-get update` × N tareas apt | `apt-get update` × 1 (caché expirado) |

En la práctica, durante el desarrollo iterativo (ejecutar el playbook múltiples veces para probar cambios), el ahorro es máximo: `apt-get update` se ejecuta una sola vez al día por host, independientemente de cuántas veces se lance el playbook.

### El valor `86400` — ¿por qué 24 horas?

```
86400 = 24 × 60 × 60
```

Es la unidad natural de "un día de trabajo". El razonamiento es:

- Los repositorios APT se actualizan varias veces al día, pero los paquetes que se instalan en un playbook de infraestructura raramente cambian de versión en menos de 24 horas.
- Un caché de 24 horas garantiza que los paquetes instalados son recientes sin forzar una actualización en cada ejecución.
- Para entornos de producción donde la seguridad es crítica, se puede usar un valor menor (ej. `3600` = 1 hora).

### Comparación de la tarea `apt` antes y después

```yaml
# ANTES (ejemplos 025-027): update_cache inline en cada tarea
- name: install tools
  apt: name={{item}} state=present update_cache=yes   # ← apt-get update aquí
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes  # ← y aquí también

# DESPUÉS (ejemplo 028): una sola tarea dedicada al inicio del rol
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400         # ← solo aquí, y solo si es necesario

- name: install tools
  apt: name={{item}} state=present                     # ← sin update_cache
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present                 # ← sin update_cache
```

---

## 📄 Playbooks de componente

### `site.yml`

```yaml
---
- include: control.yml
- include: database.yml
- include: webserver.yml
- include: loadbalancer.yml
- include: playbooks/stack_status.yml
```

Sin cambios respecto al ejemplo 027.

### `control.yml`

```yaml
---
- hosts: control
  become: true
  gather_facts: false
  roles:
    - control
```

### `database.yml`

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

Mantiene `gather_facts: true` (por defecto) porque el rol `mysql` usa `{{ ansible_eth0.ipv4.address }}`.

### `webserver.yml`

```yaml
---
- hosts: webserver
  become: true
  gather_facts: false
  roles:
    - apache2
    - demo_app
```

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  gather_facts: false
  roles:
    - nginx
```

---

## 🗂️ `group_vars/all`

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

Sin cambios respecto al ejemplo 027. Variables en texto plano (sin Vault).

---

## 🛠️ Los Roles en detalle

### 🔧 Rol `control` — ⭐ `cache_valid_time=86400`

```yaml
---
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

- name: install tools
  apt: name={{item}} state=present
  with_items:
    - curl
    - python-httplib2
```

La tarea `update apt cache once day` es la primera de todas. Las instalaciones de `curl` y `python-httplib2` ya no llevan `update_cache=yes`.

---

### 🗄️ Rol `mysql` — ⭐ `cache_valid_time=86400`

```yaml
---
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

- name: install tools
  apt: name={{item}} state=present
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present

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

En los ejemplos anteriores, tanto `install tools` como `install mysql-server` llevaban `update_cache=yes`, lo que ejecutaba `apt-get update` dos veces. Ahora se ejecuta como máximo una vez (al inicio del rol), y cero veces si el caché tiene menos de 24 horas.

**Handlers:**
```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

**Defaults:**
```yaml
---
#db_name: myapp
#db_user_name: dbuser
#db_user_pass: dbpass
#db_user_host: localhost
```

---

### 🌐 Rol `apache2` — ⭐ `cache_valid_time=86400`

```yaml
---
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

- name: install web components
  apt: name={{item}} state=present
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

**Handlers:**
```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

---

### 🚀 Rol `demo_app` — ⭐ `cache_valid_time=86400`

```yaml
---
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

- name: install web components
  apt: name={{item}} state=present
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

**Plantilla `demo.wsgi.j2`:**
```jinja2
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})

import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@{{ groups.database[0] }}/{{ db_name }}'

import sys
sys.path.insert(0, '/var/www/demo')

from demo import app as application
```

Sin cambios respecto a ejemplos anteriores.

---

### ⚖️ Rol `nginx` — ⭐ `cache_valid_time=86400`

```yaml
---
- name: update apt cache once day
  apt: update_cache=yes cache_valid_time=86400

- name: install tools
  apt: name={{item}} state=present
  with_items:
    - python-httplib2

- name: install nginx
  apt: name=nginx state=present

- name: configure nginx sites
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/{{ item.key }} mode=0644
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: get active sites
  shell: ls -l /etc/nginx/sites-enabled
  register: result

- name: de-activate default
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: de-activate sites
  file: path=/etc/nginx/sites-enabled/{{ item }} state=absent
  with_items: active.stdout_lines
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

**Plantilla `nginx.conf.j2`:**
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

Genera con los valores del inventario y `group_vars/all`:

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

**Handlers:**
```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
```

**Defaults:**
```yaml
#---
#sites:
#  myapp:
#    frontend: 80
#    backend: 80
```

---

## 📄 Playbooks de mantenimiento

### `playbooks/stack_status.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  gather_facts: false
  tasks:
    - name: verify nginx service
      command: service nginx status
    - name: verify nginx is listening on 80
      wait_for: port=80 timeout=1

- hosts: webserver
  become: true
  gather_facts: false
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
  gather_facts: false
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
  gather_facts: false
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_index

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_db
```

Sin cambios respecto al ejemplo 027. `gather_facts: false` en todos los plays excepto `database`.

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

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

Sin cambios respecto al ejemplo 027.

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
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

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### Forzar actualización del caché APT ignorando `cache_valid_time`

Si se necesita forzar `apt-get update` aunque el caché sea reciente (por ejemplo, para instalar una versión de paquete recién publicada):

```bash
# Sobreescribir cache_valid_time a 0 fuerza siempre la actualización
ansible -i hosts all -u vagrant -b -m apt -a "update_cache=yes cache_valid_time=0"

# O simplemente ejecutar apt-get update manualmente en todos los hosts
ansible -i hosts all -u vagrant -b -m apt -a "update_cache=yes"
```

### Comprobar la antigüedad del caché APT en los servidores

```bash
# Ver el timestamp del caché APT en todos los hosts
ansible -i hosts all -u vagrant -b -m command \
  -a "stat /var/cache/apt/pkgcache.bin"

# Ver la fecha de última actualización en formato legible
ansible -i hosts all -u vagrant -b -m shell \
  -a "ls -la /var/cache/apt/pkgcache.bin"
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **027** | **028** |
|---|---|---|
| **`update_cache` en tareas `apt`** | `update_cache=yes` en cada tarea | ⭐ Eliminado de todas las tareas de instalación |
| **Actualización del caché APT** | En cada tarea `apt` que instala paquetes | ⭐ Una sola tarea dedicada por rol con `cache_valid_time=86400` |
| **Ejecuciones repetidas el mismo día** | `apt-get update` × N tareas por rol | ⭐ `apt-get update` omitido (caché válido) |
| **Primera ejecución del día** | `apt-get update` × N tareas por rol | `apt-get update` × 1 por rol |
| **`gather_facts`** | `false` en plays sin facts | Sin cambios (heredado de 027) |
| **`group_vars/all`** | Texto plano | Sin cambios |
| **Roles y plantillas** | Sin cambios | Sin cambios (solo la tarea `apt` inicial) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`cache_valid_time` como idempotencia de red**: La idempotencia es el principio central de Ansible — ejecutar un playbook dos veces debe producir el mismo resultado que ejecutarlo una vez. `cache_valid_time` extiende este principio a las operaciones de red: si el caché ya está actualizado, no hay razón para volver a descargarlo. Es idempotencia aplicada a la gestión de paquetes.

- **Separar la actualización del caché de la instalación de paquetes**: El patrón `update_cache=yes` inline en cada tarea `apt` mezcla dos responsabilidades distintas: "asegúrate de que el caché está actualizado" y "instala este paquete". Separarlas en una tarea dedicada al inicio del rol hace el código más legible y eficiente.

- **`86400` como convención de "una vez al día"**: El valor `86400` (segundos en un día) es la convención estándar en la comunidad Ansible para `cache_valid_time`. Aparece en la documentación oficial, en roles de Ansible Galaxy y en la mayoría de proyectos de infraestructura como código. Memorizarlo como "24 × 60 × 60" es útil.

- **Composición de optimizaciones**: Este ejemplo demuestra cómo las optimizaciones se acumulan. El ejemplo 027 introdujo `gather_facts: false` (ahorra 1-5s por host en la fase de facts). El ejemplo 028 añade `cache_valid_time=86400` (ahorra 5-30s por rol en la fase de instalación). Juntas, estas dos optimizaciones pueden reducir el tiempo de un despliegue iterativo en varios minutos.

- **`cache_valid_time` no afecta a la instalación**: `cache_valid_time` solo controla si se ejecuta `apt-get update`. La instalación del paquete (`state=present`) sigue siendo idempotente de forma independiente — si el paquete ya está instalado, Ansible no lo reinstala, independientemente del valor de `cache_valid_time`.

---

## 📚 Referencias

- [Ansible Docs — `apt` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Ansible Docs — `apt` module: `cache_valid_time` parameter](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html#parameter-cache_valid_time)
- [Ansible Docs — Performance tuning](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Ubuntu Manpage — `apt-get update`](https://manpages.ubuntu.com/manpages/focal/en/man8/apt-get.8.html)
