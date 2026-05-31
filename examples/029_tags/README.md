# 📋 Ejemplo 029 — `tags`: Ejecución selectiva de tareas con tags

## 🧭 Descripción general

Este ejemplo introduce **tags** (etiquetas) en Ansible — el mecanismo que permite ejecutar solo un subconjunto de tareas de un playbook sin modificar el código. La novedad es quirúrgica y deliberada: el tag `deploy` se aplica exclusivamente a las tareas que copian o despliegan el código de la aplicación web, separándolas de las tareas de instalación y configuración de infraestructura.

El caso de uso que motiva este ejemplo es el ciclo de vida real de una aplicación: la infraestructura (MySQL, Apache, Nginx, paquetes del sistema) se instala una vez y raramente cambia. El código de la aplicación (`demo_app`) se despliega con frecuencia — cada vez que hay una nueva versión. Sin tags, cada despliegue de código forzaría a Ansible a recorrer todas las tareas de todos los roles, incluyendo instalaciones de paquetes y configuraciones de base de datos que no han cambiado. Con `--tags deploy`, Ansible ejecuta únicamente las tareas marcadas con `deploy`, haciendo el ciclo de despliegue de código significativamente más rápido y seguro.

El proyecto acumula todas las optimizaciones anteriores: `gather_facts: false` (ejemplo 027), `cache_valid_time=86400` (ejemplo 028), y ahora añade tags. `site.yml` vuelve a usar `ansible.builtin.import_playbook` (FQCN — Fully Qualified Collection Name), la sintaxis moderna recomendada desde Ansible 2.10.

---

## 🗂️ Estructura del proyecto

```
029_tags/
├── site.yml                          # ⭐ ansible.builtin.import_playbook (FQCN)
├── control.yml                       # gather_facts: false
├── database.yml                      # gather_facts: true (necesita ansible_eth0)
├── webserver.yml                     # gather_facts: false
├── loadbalancer.yml                  # gather_facts: false
├── group_vars/
│   └── all                           # Variables en texto plano
├── playbooks/
│   ├── stack_status.yml
│   └── stack_restart.yml
└── roles/
    ├── control/
    │   └── tasks/main.yml            # cache_valid_time=86400, sin tags
    ├── mysql/
    │   ├── tasks/main.yml            # cache_valid_time=86400, sin tags
    │   ├── handlers/main.yml
    │   └── defaults/main.yml
    ├── apache2/
    │   ├── tasks/main.yml            # ⭐ tags: ['deploy'] en de-activate default
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml            # ⭐ tags: ['deploy'] en TODAS las tareas de despliegue
    │   ├── handlers/main.yml
    │   └── templates/demo.wsgi.j2
    └── nginx/
        ├── tasks/main.yml            # cache_valid_time=86400, sin tags
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

## ⭐ NOVEDAD PRINCIPAL: Tags en Ansible

### ¿Qué son los tags?

Los tags son etiquetas de texto que se asignan a tareas, plays, roles o bloques. Cuando se ejecuta un playbook con `--tags <nombre>`, Ansible ejecuta **solo** las tareas que tienen ese tag asignado, saltándose el resto. Con `--skip-tags <nombre>`, ocurre lo contrario: se ejecutan todas las tareas excepto las que tienen ese tag.

```
Sin tags:
  Tarea 1 ✅ → Tarea 2 ✅ → Tarea 3 ✅ → Tarea 4 ✅ → Tarea 5 ✅

Con --tags deploy:
  Tarea 1 ⏭️ → Tarea 2 ⏭️ → Tarea 3 ✅ → Tarea 4 ✅ → Tarea 5 ⏭️
                                (deploy)    (deploy)
```

### El tag `deploy` en este ejemplo

El tag `deploy` se aplica a las tareas que constituyen el **despliegue de la aplicación web** — las operaciones que deben ejecutarse cada vez que hay una nueva versión del código, sin necesidad de reinstalar la infraestructura subyacente:

| **Rol** | **Tarea** | **Tag** | **Razón** |
|---|---|---|---|
| `apache2` | `de-activate default apache site` | `deploy` | Parte de la activación del sitio de la app |
| `demo_app` | `copy demo app source` | `deploy` | Copia el código fuente de la app |
| `demo_app` | `copy demo.wsgi` | `deploy` | Renderiza la configuración WSGI |
| `demo_app` | `copy apache virtual host config` | `deploy` | Copia la configuración del VirtualHost |
| `demo_app` | `setup python virtualenv` | `deploy` | Instala dependencias Python de la app |
| `demo_app` | `activate demo apache site` | `deploy` | Activa el sitio en Apache |

Las tareas **sin** tag `deploy` son las de infraestructura base, que solo se ejecutan en el despliegue completo:

| **Rol** | **Tareas sin tag** |
|---|---|
| `apache2` | `update apt cache`, `install web components`, `ensure mod_wsgi enabled`, `ensure apache2 started` |
| `demo_app` | `update apt cache`, `install web components` |
| `mysql` | Todas las tareas |
| `nginx` | Todas las tareas |
| `control` | Todas las tareas |

### Flujo de ejecución: completo vs. solo `deploy`

```
ansible-playbook site.yml                    (despliegue completo)
  ├── control.yml    → instala curl, python-httplib2
  ├── database.yml   → instala MySQL, crea BD y usuario
  ├── webserver.yml
  │   ├── apache2    → instala Apache, mod_wsgi, desactiva default ← (deploy)
  │   └── demo_app   → instala paquetes, copia código ← (deploy), configura WSGI ← (deploy)
  ├── loadbalancer.yml → instala Nginx, configura sitios
  └── stack_status.yml → verificación end-to-end
  Tiempo estimado: 3-8 minutos

ansible-playbook site.yml --tags deploy      (solo despliegue de código)
  ├── control.yml    → ⏭️ (sin tareas con tag deploy)
  ├── database.yml   → ⏭️ (sin tareas con tag deploy)
  ├── webserver.yml
  │   ├── apache2    → ✅ de-activate default apache site
  │   └── demo_app   → ✅ copy demo app source
  │                  → ✅ copy demo.wsgi
  │                  → ✅ copy apache virtual host config
  │                  → ✅ setup python virtualenv
  │                  → ✅ activate demo apache site
  ├── loadbalancer.yml → ⏭️ (sin tareas con tag deploy)
  └── stack_status.yml → ⏭️ (sin tareas con tag deploy)
  Tiempo estimado: 15-30 segundos
```

---

## 📄 `site.yml` — ⭐ `ansible.builtin.import_playbook` (FQCN)

```yaml
---
- ansible.builtin.import_playbook: control.yml
- ansible.builtin.import_playbook: database.yml
- ansible.builtin.import_playbook: webserver.yml
- ansible.builtin.import_playbook: loadbalancer.yml
- ansible.builtin.import_playbook: playbooks/stack_status.yml
```

Este ejemplo vuelve a `import_playbook` (como en el ejemplo 025), pero ahora usando el **FQCN** (Fully Qualified Collection Name): `ansible.builtin.import_playbook` en lugar de la forma corta `import_playbook`.

| **Sintaxis** | **Ejemplo** | **Estado** |
|---|---|---|
| `include` | `- include: database.yml` | Deprecado (ejemplos 026-028) |
| `import_playbook` | `- import_playbook: database.yml` | Válido |
| `ansible.builtin.import_playbook` | `- ansible.builtin.import_playbook: database.yml` | ⭐ Recomendado (FQCN) |

El FQCN es la forma canónica desde Ansible 2.10. Especifica explícitamente que el módulo pertenece a la colección `ansible.builtin`, eliminando ambigüedades cuando hay múltiples colecciones instaladas con módulos del mismo nombre.

La importancia de `import_playbook` (estático) para los tags es crítica: como los playbooks se cargan en tiempo de parseo, Ansible puede construir el árbol completo de tareas y aplicar el filtro de tags **antes de ejecutar nada**. Con `include` (dinámico), los tags no funcionan correctamente sobre playbooks incluidos.

---

## 📄 Playbooks de componente

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

Mantiene `gather_facts: true` (por defecto) — necesario para `{{ ansible_eth0.ipv4.address }}` en el rol `mysql`.

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

Sin cambios respecto al ejemplo 028.

---

## 🛠️ Los Roles en detalle

### 🔧 Rol `control` — Sin tags

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

Sin tags — las herramientas de control son infraestructura base, no código de aplicación.

---

### 🗄️ Rol `mysql` — Sin tags

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

Sin tags — la base de datos es infraestructura, no código de aplicación. Un despliegue `--tags deploy` no toca MySQL.

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

### 🌐 Rol `apache2` — ⭐ Una tarea con tag `deploy`

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
  tags: [ 'deploy' ]
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

Solo la tarea `de-activate default apache site` lleva el tag `deploy`. La lógica es que desactivar el sitio por defecto de Apache es parte del proceso de activación del sitio de la aplicación — sin este paso, Apache serviría el sitio `default` en lugar de `demo.conf`.

Las tareas de instalación (`update apt cache`, `install web components`, `ensure mod_wsgi enabled`, `ensure apache2 started`) son infraestructura y no llevan tag.

**Handlers:**
```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

---

### 🚀 Rol `demo_app` — ⭐ Todas las tareas de despliegue con tag `deploy`

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
  tags: [ 'deploy' ]
  notify: restart apache2

- name: copy demo.wsgi
  template: src=demo.wsgi.j2 dest=/var/www/demo/demo.wsgi mode=0755
  tags: [ 'deploy' ]
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  tags: [ 'deploy' ]
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  tags: [ 'deploy' ]
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf
        dest=/etc/apache2/sites-enabled/demo.conf
        state=link
  tags: [ 'deploy' ]
  notify: restart apache2
```

Este rol es el núcleo del ejemplo. La separación es clara:

| **Tarea** | **Tag** | **Tipo** | **Ejecuta con `--tags deploy`** |
|---|---|---|---|
| `update apt cache once day` | — | Infraestructura | ❌ No |
| `install web components` | — | Infraestructura | ❌ No |
| `copy demo app source` | `deploy` | Código de app | ✅ Sí |
| `copy demo.wsgi` | `deploy` | Configuración de app | ✅ Sí |
| `copy apache virtual host config` | `deploy` | Configuración de app | ✅ Sí |
| `setup python virtualenv` | `deploy` | Dependencias de app | ✅ Sí |
| `activate demo apache site` | `deploy` | Activación de app | ✅ Sí |

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

**Handlers:**
```yaml
---
- name: restart apache2
  service: name=apache2 state=restarted
```

---

### ⚖️ Rol `nginx` — Sin tags

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

Sin tags — Nginx es el balanceador de carga (infraestructura), no el servidor de la aplicación. Su configuración no cambia con cada despliegue de código.

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

**Handlers:**
```yaml
---
- name: restart nginx
  service: name=nginx state=restarted
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

Sin cambios respecto al ejemplo 028.

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

Sin cambios respecto al ejemplo 028.

---

## 🚀 Comandos de ejecución

### Despliegue completo de infraestructura + aplicación

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

Ejecuta todas las tareas: instala paquetes, configura servicios, despliega el código de la aplicación y verifica el stack.

### ⭐ Despliegue solo del código de la aplicación (`--tags deploy`)

```bash
ansible-playbook -i hosts -u vagrant site.yml --tags deploy
```

Ejecuta únicamente las tareas marcadas con `tags: ['deploy']`:
- `de-activate default apache site` (rol `apache2`)
- `copy demo app source` (rol `demo_app`)
- `copy demo.wsgi` (rol `demo_app`)
- `copy apache virtual host config` (rol `demo_app`)
- `setup python virtualenv` (rol `demo_app`)
- `activate demo apache site` (rol `demo_app`)

Ideal para despliegues de nuevas versiones de la aplicación sin tocar la infraestructura.

### Excluir el despliegue de la aplicación (`--skip-tags deploy`)

```bash
ansible-playbook -i hosts -u vagrant site.yml --skip-tags deploy
```

Ejecuta todas las tareas excepto las marcadas con `deploy`. Útil para actualizar la infraestructura (paquetes del sistema, configuración de MySQL, Nginx) sin redesplegar el código de la aplicación.

### Listar todas las tareas y sus tags antes de ejecutar

```bash
ansible-playbook -i hosts -u vagrant site.yml --list-tasks
```

Muestra el árbol completo de tareas con sus tags asignados. Funciona correctamente gracias a `ansible.builtin.import_playbook` (estático).

### Listar solo las tareas que se ejecutarían con un tag específico

```bash
ansible-playbook -i hosts -u vagrant site.yml --tags deploy --list-tasks
```

### Listar todos los tags disponibles en el playbook

```bash
ansible-playbook -i hosts -u vagrant site.yml --list-tags
```

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

### Despliegue de componentes individuales con tag

```bash
# Solo desplegar la app en el webserver
ansible-playbook -i hosts -u vagrant webserver.yml --tags deploy

# Despliegue completo del webserver (infraestructura + app)
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **028** | **029** |
|---|---|---|
| **Tags** | Ninguno | ⭐ Tag `deploy` en tareas de despliegue de app |
| **Despliegue de código sin infraestructura** | Imposible sin modificar el código | ⭐ `--tags deploy` |
| **`site.yml`** | `include` | ⭐ `ansible.builtin.import_playbook` (FQCN) |
| **`cache_valid_time=86400`** | En todos los roles | Sin cambios (heredado de 028) |
| **`gather_facts: false`** | En plays sin facts | Sin cambios (heredado de 027) |
| **`group_vars/all`** | Texto plano | Sin cambios |
| **Roles mysql y nginx** | Sin tags | Sin tags (infraestructura, no cambia con deploys) |
| **Rol `demo_app`** | Sin tags | ⭐ 5 tareas con `tags: ['deploy']` |
| **Rol `apache2`** | Sin tags | ⭐ 1 tarea con `tags: ['deploy']` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Tags como mecanismo de ejecución selectiva**: Los tags permiten ejecutar subconjuntos de tareas sin modificar el código del playbook. Son la forma estándar en Ansible de implementar el concepto de "modo de despliegue" — distinguir entre un despliegue completo (infraestructura + código) y un despliegue incremental (solo código).

- **La distinción infraestructura vs. aplicación**: El diseño de tags en este ejemplo refleja una distinción arquitectónica fundamental: la infraestructura (paquetes del SO, configuración de servicios, base de datos) es estable y cambia poco; el código de la aplicación es volátil y cambia frecuentemente. Los tags materializan esta distinción en el código de automatización.

- **`import_playbook` es necesario para que los tags funcionen en `site.yml`**: Con `include` (dinámico), Ansible no conoce el contenido de los playbooks incluidos hasta el momento de ejecutarlos, lo que impide aplicar filtros de tags sobre ellos. Con `import_playbook` (estático), Ansible carga todo el árbol de tareas en tiempo de parseo y puede aplicar `--tags` correctamente sobre cualquier tarea de cualquier playbook incluido.

- **FQCN (`ansible.builtin.import_playbook`)**: El Fully Qualified Collection Name es la forma canónica de referenciar módulos en Ansible 2.10+. Especifica explícitamente la colección (`ansible.builtin`) y el módulo (`import_playbook`), eliminando ambigüedades. Es la sintaxis recomendada para proyectos nuevos y para linting con `ansible-lint`.

- **Tags como documentación implícita**: Asignar el tag `deploy` a un conjunto de tareas documenta implícitamente qué operaciones constituyen "un despliegue de la aplicación". Cualquier persona que lea el código puede ejecutar `--list-tags` para entender qué operaciones están disponibles sin leer todas las tareas una a una.

- **`--list-tasks` + `--list-tags` como herramientas de exploración**: Antes de ejecutar un playbook desconocido, `--list-tasks` y `--list-tags` permiten entender qué va a hacer sin ejecutar nada. Son equivalentes al `--dry-run` de otros sistemas, pero más informativos.

---

## 📚 Referencias

- [Ansible Docs — Tags](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html)
- [Ansible Docs — `ansible.builtin.import_playbook`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/import_playbook_module.html)
- [Ansible Docs — Special tags: `always` y `never`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html#special-tags-always-and-never)
- [Ansible Docs — Tagging roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html#adding-tags-to-roles)
- [Ansible Docs — FQCN (Fully Qualified Collection Names)](https://docs.ansible.com/ansible/latest/collections_guide/collections_using_playbooks.html)
