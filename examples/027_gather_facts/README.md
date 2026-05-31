# 📋 Ejemplo 027 — `gather_facts`: Control del rendimiento con `gather_facts`

## 🧭 Descripción general

Este ejemplo introduce una optimización de rendimiento fundamental en Ansible: el control explícito de **`gather_facts`**. Por defecto, antes de ejecutar cualquier tarea en un host, Ansible ejecuta automáticamente el módulo `setup` para recopilar más de 300 variables del sistema (CPU, memoria, red, distribución del SO, etc.) — un proceso que puede tardar entre 1 y 5 segundos por host. En proyectos con decenas o cientos de nodos, este tiempo se acumula significativamente.

En este ejemplo, `gather_facts: false` se aplica selectivamente a los playbooks y tareas de verificación que **no necesitan facts del sistema** para funcionar. El resultado es un despliegue más rápido sin sacrificar funcionalidad. La única excepción deliberada es el rol `mysql`, que sí necesita `ansible_eth0.ipv4.address` para configurar el `bind-address` de MySQL — y por tanto mantiene `gather_facts` activo (comportamiento por defecto).

El resto del proyecto (`group_vars/all`, roles, plantillas) es idéntico al ejemplo 026, confirmando que `gather_facts` es una optimización ortogonal que no afecta a la lógica de configuración.

---

## 🗂️ Estructura del proyecto

```
027_gather_facts/
├── site.yml                          # Orquestador maestro (include)
├── control.yml                       # ⭐ gather_facts: false
├── database.yml                      # ✅ gather_facts: true (por defecto — necesita ansible_eth0)
├── webserver.yml                     # ⭐ gather_facts: false
├── loadbalancer.yml                  # ⭐ gather_facts: false
├── group_vars/
│   └── all                           # Variables centralizadas (texto plano, igual que 025)
├── playbooks/
│   ├── stack_status.yml              # ⭐ gather_facts: false en la mayoría de plays
│   └── stack_restart.yml             # gather_facts: true (por defecto — necesita ansible_eth0)
└── roles/
    ├── control/
    │   └── tasks/main.yml
    ├── mysql/
    │   ├── tasks/main.yml            # Usa {{ ansible_eth0.ipv4.address }}
    │   ├── handlers/main.yml
    │   └── defaults/main.yml
    ├── apache2/
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/demo.wsgi.j2
    └── nginx/
        ├── tasks/main.yml
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

## ⭐ NOVEDAD PRINCIPAL: `gather_facts: false`

### ¿Qué es `gather_facts`?

Cuando Ansible conecta a un host para ejecutar un playbook, lo primero que hace (antes de cualquier tarea del usuario) es ejecutar el módulo `setup` de forma implícita. Este módulo recopila **facts** — variables automáticas que describen el estado del sistema:

```
ansible_os_family: "Debian"
ansible_distribution: "Ubuntu"
ansible_distribution_version: "22.04"
ansible_architecture: "x86_64"
ansible_processor_count: 2
ansible_memtotal_mb: 1024
ansible_eth0:
  ipv4:
    address: "192.168.11.20"
    netmask: "255.255.255.0"
ansible_hostname: "database"
ansible_fqdn: "database.local"
ansible_date_time:
  iso8601: "2026-05-31T10:40:00Z"
... (más de 300 variables en total)
```

Este proceso de recopilación tarda típicamente entre **1 y 5 segundos por host**, dependiendo del hardware y la latencia de red.

### El coste de `gather_facts` por defecto

Con el inventario de este ejemplo (3 hosts) y un despliegue completo con `site.yml` que ejecuta múltiples plays por host:

```
site.yml
  ├── control.yml      → 1 play sobre 1 host  → gather_facts (1-5s)
  ├── database.yml     → 1 play sobre 1 host  → gather_facts (1-5s)
  ├── webserver.yml    → 1 play sobre 1 host  → gather_facts (1-5s)
  ├── loadbalancer.yml → 1 play sobre 1 host  → gather_facts (1-5s)
  └── stack_status.yml → 5 plays sobre 3 hosts → gather_facts (5-25s)
                                                ─────────────────────
                                                Total: 9-45s solo en facts
```

Con `gather_facts: false` en los plays que no lo necesitan:

```
  ├── control.yml      → gather_facts: false  → 0s
  ├── database.yml     → gather_facts: true   → 1-5s  (necesita ansible_eth0)
  ├── webserver.yml    → gather_facts: false  → 0s
  ├── loadbalancer.yml → gather_facts: false  → 0s
  └── stack_status.yml → false en 4 de 5 plays → ~1s
                                                ─────────────────────
                                                Total: ~2-6s en facts
                                                Ahorro: ~7-39s
```

### Regla de decisión: ¿cuándo usar `gather_facts: false`?

| **Condición** | **`gather_facts`** | **Razón** |
|---|---|---|
| El play usa `{{ ansible_eth0.ipv4.address }}` | `true` (por defecto) | Necesita la IP del host |
| El play usa `{{ ansible_distribution }}` | `true` (por defecto) | Necesita la distro del SO |
| El play usa `{{ ansible_memtotal_mb }}` | `true` (por defecto) | Necesita datos de hardware |
| El play solo instala paquetes, copia ficheros, gestiona servicios | `false` | No necesita facts del sistema |
| El play solo verifica puertos o URLs | `false` | No necesita facts del sistema |
| El play solo gestiona usuarios o grupos | `false` | No necesita facts del sistema |

---

## 📄 Playbooks de componente — Análisis de `gather_facts`

### `site.yml`

```yaml
---
- include: control.yml
- include: database.yml
- include: webserver.yml
- include: loadbalancer.yml
- include: playbooks/stack_status.yml
```

Sin cambios respecto al ejemplo 026.

---

### `control.yml` — ⭐ `gather_facts: false`

```yaml
---
- hosts: control
  become: true
  gather_facts: false
  roles:
    - control
```

El rol `control` solo instala `curl` y `python-httplib2` con `apt`. No necesita ningún fact del sistema — `apt` funciona sin conocer la distribución porque ya sabemos que es Ubuntu. `gather_facts: false` elimina la fase de recopilación de facts en este host.

---

### `database.yml` — ✅ `gather_facts: true` (por defecto, sin declarar)

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

Este es el único playbook de componente que **no declara** `gather_facts: false`. La razón es explícita en el rol `mysql`:

```yaml
- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
```

La tarea usa `{{ ansible_eth0.ipv4.address }}` para configurar el `bind-address` de MySQL con la IP real del servidor de base de datos. Esta variable solo está disponible si `gather_facts` está activo. Con el inventario proporcionado, resuelve a `192.168.11.20`.

> **Nota de diseño:** Este es el ejemplo perfecto de por qué `gather_facts: false` debe aplicarse con criterio. Si se desactivara en `database.yml`, el despliegue fallaría con `undefined variable: ansible_eth0`.

---

### `webserver.yml` — ⭐ `gather_facts: false`

```yaml
---
- hosts: webserver
  become: true
  gather_facts: false
  roles:
    - apache2
    - demo_app
```

Los roles `apache2` y `demo_app` no usan ningún fact del sistema:
- `apache2`: instala paquetes, activa módulos, gestiona el servicio.
- `demo_app`: copia ficheros, renderiza la plantilla `demo.wsgi.j2`, configura virtualenv.

La plantilla `demo.wsgi.j2` usa `{{ db_user }}`, `{{ db_pass }}`, `{{ groups.database[0] }}` y `{{ db_name }}` — todas variables de `group_vars/all` o del inventario, no facts del sistema.

---

### `loadbalancer.yml` — ⭐ `gather_facts: false`

```yaml
---
- hosts: loadbalancer
  become: true
  gather_facts: false
  roles:
    - nginx
```

El rol `nginx` no usa facts del sistema. Toda su configuración proviene del diccionario `sites` de `group_vars/all` y de `groups.webserver` del inventario.

---

## 🗄️ `group_vars/all` — Texto plano (vuelve desde el vault del ejemplo 026)

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

Este ejemplo vuelve a `group_vars/all` en texto plano (como en el ejemplo 025), abandonando el cifrado Vault del ejemplo 026. El objetivo es aislar la demostración de `gather_facts` sin la complejidad adicional de `--ask-vault-pass`.

---

## 🛠️ Los Roles en detalle

### 🗄️ Rol `mysql` — Necesita facts (`ansible_eth0`)

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

La tarea crítica es `ensure mysql listening on all ports`. Modifica `/etc/mysql/my.cnf` para que MySQL escuche en la IP real del servidor (`192.168.11.20`) en lugar de solo en `localhost`. Esto es necesario para que el webserver (`192.168.11.40`) pueda conectarse a MySQL a través de la red.

**Flujo de variables en este rol:**

| **Variable** | **Fuente** | **Valor resuelto** |
|---|---|---|
| `{{ ansible_eth0.ipv4.address }}` | Facts del sistema (gather_facts) | `192.168.11.20` |
| `{{ db_name }}` | `group_vars/all` | `maykadb` |
| `{{ db_user_name }}` | Parámetro inline en `database.yml` → `{{ db_user }}` de `group_vars/all` | `mayka_user` |
| `{{ db_user_pass }}` | Parámetro inline en `database.yml` → `{{ db_pass }}` de `group_vars/all` | `mayka_pass` |
| `{{ db_user_host }}` | Parámetro inline en `database.yml` | `%` |

#### `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service: name=mysql state=restarted
```

#### `roles/mysql/defaults/main.yml`

```yaml
---
#db_name: myapp
#db_user_name: dbuser
#db_user_pass: dbpass
#db_user_host: localhost
```

Defaults comentados — todas las variables deben venir de `group_vars/all` o de parámetros inline.

---

### 🌐 Rol `apache2` — No necesita facts

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

Sin cambios respecto a ejemplos anteriores. Ninguna tarea usa variables de facts.

---

### 🚀 Rol `demo_app` — No necesita facts

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

#### `roles/demo_app/templates/demo.wsgi.j2`

```jinja2
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})

import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@{{ groups.database[0] }}/{{ db_name }}'

import sys
sys.path.insert(0, '/var/www/demo')

from demo import app as application
```

Todas las variables de la plantilla provienen de `group_vars/all` y del inventario — ninguna de facts del sistema. Por eso `webserver.yml` puede usar `gather_facts: false` sin problema.

---

### ⚖️ Rol `nginx` — No necesita facts

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

Sin cambios respecto al ejemplo 026. Toda la configuración proviene de `group_vars/all` (`sites`) y del inventario (`groups.webserver`).

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

---

## 📄 Playbooks de mantenimiento

### `playbooks/stack_status.yml` — ⭐ `gather_facts: false` aplicado por play

```yaml
---
- hosts: loadbalancer
  become: true
  gather_facts: false          # ⭐ Solo verifica servicio y puerto
  tasks:
    - name: verify nginx service
      command: service nginx status
    - name: verify nginx is listening on 80
      wait_for: port=80 timeout=1

- hosts: webserver
  become: true
  gather_facts: false          # ⭐ Solo verifica servicio y puerto
  tasks:
    - name: verify apache2 service
      command: service apache2 status
    - name: verify apache2 is listening on 80
      wait_for: port=80 timeout=1

- hosts: database
  become: true
                               # ✅ gather_facts: true (por defecto)
                               # Podría necesitar facts en futuras tareas
  tasks:
    - name: verify mysql service
      command: service mysql status
    - name: verify mysql is listening on 3306
      wait_for: port=3306 timeout=1

- hosts: control
  gather_facts: false          # ⭐ Solo hace peticiones HTTP
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
  gather_facts: false          # ⭐ Solo hace peticiones HTTP al backend
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

La distribución de `gather_facts` en `stack_status.yml`:

| **Play** | **Hosts** | **`gather_facts`** | **Razón** |
|---|---|---|---|
| Verificar nginx | `loadbalancer` | `false` | Solo `service status` + `wait_for` |
| Verificar apache2 | `webserver` | `false` | Solo `service status` + `wait_for` |
| Verificar mysql | `database` | `true` (por defecto) | Consistencia con el rol mysql |
| Verificar end-to-end | `control` | `false` | Solo peticiones `uri` HTTP |
| Verificar backend | `loadbalancer` | `false` | Solo peticiones `uri` HTTP |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

### `playbooks/stack_restart.yml` — `gather_facts: true` (por defecto)

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

`stack_restart.yml` mantiene `gather_facts: true` (por defecto) porque el play de `database` usa `{{ ansible_eth0.ipv4.address }}` en la tarea `wait_for`. Desactivar `gather_facts` aquí causaría un error de variable indefinida.

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

### Ver los facts disponibles en un host (diagnóstico)

```bash
# Ver TODOS los facts de un host
ansible -i hosts 192.168.11.20 -u vagrant -m setup

# Filtrar solo los facts de red
ansible -i hosts 192.168.11.20 -u vagrant -m setup -a "filter=ansible_eth*"

# Filtrar solo los facts del SO
ansible -i hosts 192.168.11.20 -u vagrant -m setup -a "filter=ansible_distribution*"

# Ver cuánto tiempo tarda gather_facts en un host
time ansible -i hosts 192.168.11.20 -u vagrant -m setup > /dev/null
```

### Medir el impacto de `gather_facts: false`

```bash
# Con gather_facts (comportamiento por defecto)
time ansible-playbook -i hosts -u vagrant webserver.yml

# Comparar con gather_facts: false (como en este ejemplo)
# (ya está configurado en webserver.yml)
time ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **026** | **027** |
|---|---|---|
| **`gather_facts` en `control.yml`** | `true` (por defecto) | ⭐ `false` |
| **`gather_facts` en `webserver.yml`** | `true` (por defecto) | ⭐ `false` |
| **`gather_facts` en `loadbalancer.yml`** | `true` (por defecto) | ⭐ `false` |
| **`gather_facts` en `database.yml`** | `true` (por defecto) | ✅ `true` (por defecto — necesita `ansible_eth0`) |
| **`gather_facts` en `stack_status.yml`** | `true` en todos los plays | ⭐ `false` en 4 de 5 plays |
| **`group_vars/all`** | Cifrado con Vault (AES-256) | Texto plano (simplificado para el ejemplo) |
| **Tiempo de despliegue** | Mayor (facts en todos los hosts) | ⭐ Menor (facts solo donde son necesarios) |
| **Roles y plantillas** | Sin cambios | Sin cambios |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`gather_facts: false` como optimización de rendimiento**: Desactivar la recopilación de facts en plays que no los necesitan es la forma más sencilla de reducir el tiempo de ejecución de un playbook. En entornos con muchos hosts, el ahorro puede ser de minutos.

- **Facts vs. variables de inventario**: Los facts (`ansible_eth0`, `ansible_distribution`, etc.) son variables recopiladas dinámicamente del host en tiempo de ejecución. Las variables de inventario (`group_vars/all`, parámetros inline) son estáticas y siempre están disponibles, independientemente de `gather_facts`. Esta distinción es clave para decidir cuándo desactivar `gather_facts`.

- **Granularidad por play**: `gather_facts` se configura a nivel de play (bloque `- hosts:`), no a nivel de playbook ni de rol. Esto permite tener `gather_facts: false` en algunos plays de `site.yml` y `gather_facts: true` en otros, con control granular.

- **`ansible_eth0` como dependencia implícita**: Cualquier tarea que use `{{ ansible_eth0.ipv4.address }}` (o cualquier otra variable `ansible_*`) crea una dependencia implícita en `gather_facts: true`. Si se desactiva `gather_facts` en un play que contiene estas variables, Ansible fallará con `undefined variable`. Es importante auditar los roles antes de desactivar `gather_facts`.

- **`gather_facts: false` en plays de verificación**: Los playbooks de verificación (`stack_status.yml`) son los candidatos más obvios para `gather_facts: false`, ya que típicamente solo verifican puertos, servicios o URLs — ninguna de estas operaciones requiere facts del sistema.

- **`setup` como módulo explícito**: Si se necesitan facts en un play con `gather_facts: false`, se pueden recopilar selectivamente con `- name: gather facts; setup: filter=ansible_eth*`. Esto es más eficiente que activar `gather_facts: true` completo cuando solo se necesita un subconjunto de variables.

---

## 📚 Referencias

- [Ansible Docs — `gather_facts`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html#disabling-facts)
- [Ansible Docs — `setup` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/setup_module.html)
- [Ansible Docs — Facts and magic variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
- [Ansible Docs — Performance tuning](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html#performance-tuning)
