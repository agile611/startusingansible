# 📋 Ejemplo 019 — Ansible Facts: infraestructura dinámica con datos del sistema

## 🧭 Descripción general

Este ejemplo introduce uno de los conceptos más poderosos de Ansible: los **Facts**. Los Facts son variables que Ansible recopila automáticamente de cada nodo remoto al inicio de cada play (fase `Gathering Facts`), y contienen información detallada del sistema: IPs, interfaces de red, memoria, CPU, sistema operativo, etc.

La novedad clave respecto al ejemplo 018 es el uso de **`{{ ansible_eth0.ipv4.address }}`** para reemplazar IPs hardcodeadas por valores dinámicos extraídos del propio nodo. Esto hace que los playbooks sean **agnósticos a la infraestructura**: el mismo código funciona en cualquier entorno sin modificar ningún fichero. Además, `site.yml` ahora incluye `stack_status.yml` directamente, convirtiendo el despliegue + verificación en una operación atómica.

---

## 🗂️ Estructura del proyecto

```
019_facts/
├── site.yml                       # ⭐ Orquestador: despliegue + verificación en un comando
├── control.yml                    # Playbook del nodo de control
├── database.yml                   # Playbook del servidor de base de datos
├── webserver.yml                  # Playbook del servidor web
├── loadbalancer.yml               # Playbook del balanceador de carga
├── demo/                          # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml               # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml          # ⭐ Reinicio con facts: wait_for usa IP dinámica
│   └── stack_status.yml           # ⭐ Verificación con facts: wait_for usa IP dinámica
└── roles/
    ├── control/                   # Rol: instala curl + python-httplib2
    ├── mysql/                     # ⭐ Rol: usa facts para bind-address dinámico
    ├── apache2/                   # Rol: infraestructura Apache + mod_wsgi
    ├── demo_app/                  # Rol: despliega Flask, virtualenv, VirtualHost
    └── nginx/                     # Rol: balanceador de carga Nginx
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

## ⭐ Concepto central: Ansible Facts

### ¿Qué son los Facts?

Cuando Ansible se conecta a un nodo remoto, antes de ejecutar cualquier tarea, ejecuta automáticamente el módulo `setup`. Este módulo recopila cientos de variables del sistema y las pone a disposición del playbook como **facts**. Este proceso se llama **Gathering Facts** y aparece siempre como la primera tarea en la salida de `ansible-playbook`.

```
PLAY [database] ************************************************************
TASK [Gathering Facts] *****************************************************
ok: [192.168.11.20]
```

### Estructura de los Facts de red

Los facts de red siguen la estructura `ansible_<interfaz>.<familia>.<campo>`:

```
ansible_eth0
├── .ipv4
│   ├── .address      → "192.168.11.20"   ← IP de la interfaz eth0
│   ├── .netmask      → "255.255.255.0"
│   ├── .network      → "192.168.11.0"
│   └── .broadcast    → "192.168.11.255"
├── .ipv6             → Lista de direcciones IPv6
├── .macaddress       → "08:00:27:xx:xx:xx"
├── .mtu              → 1500
└── .type             → "ether"
```

### Facts más útiles

| **Fact** | **Ejemplo de valor** | **Descripción** |
|---|---|---|
| `ansible_eth0.ipv4.address` | `"192.168.11.20"` | IP de la interfaz eth0 |
| `ansible_hostname` | `"database"` | Nombre del host |
| `ansible_fqdn` | `"database.local"` | Nombre de dominio completo |
| `ansible_os_family` | `"Debian"` | Familia del SO |
| `ansible_distribution` | `"Ubuntu"` | Distribución Linux |
| `ansible_distribution_version` | `"22.04"` | Versión de la distribución |
| `ansible_memtotal_mb` | `1024` | Memoria RAM total en MB |
| `ansible_processor_vcpus` | `2` | Número de CPUs virtuales |
| `ansible_default_ipv4.address` | `"192.168.11.20"` | IP de la interfaz por defecto |
| `ansible_all_ipv4_addresses` | `["192.168.11.20", "10.0.2.15"]` | Lista de todas las IPs IPv4 |

### Cómo explorar los Facts de un nodo

```bash
# Ver TODOS los facts de un nodo específico
ansible database -i hosts -u vagrant -m setup

# Filtrar facts por patrón
ansible database -i hosts -u vagrant -m setup -a "filter=ansible_eth*"

# Ver solo facts de red
ansible database -i hosts -u vagrant -m setup -a "filter=ansible_*_ipv4*"
```

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

La diferencia clave respecto al ejemplo 018 es la **quinta línea**: `stack_status.yml` ahora forma parte del despliegue. Esto significa que un único comando despliega toda la infraestructura **y** verifica automáticamente que todo funciona correctamente al final.

### Flujo de ejecución completo con `site.yml`

```
1. control.yml          → Prepara el nodo de control
2. database.yml         → Despliega MySQL (con bind-address dinámico via facts)
3. webserver.yml        → Despliega Apache2 + Flask
4. loadbalancer.yml     → Despliega Nginx
5. stack_status.yml     → ⭐ Verifica automáticamente que todo el stack funciona
```

Si cualquier verificación de `stack_status.yml` falla, el playbook termina con error, informando exactamente qué componente no responde correctamente.

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

## 🛠️ Los Roles

### 🛠️ Rol `control`

```yaml
# roles/control/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - curl
    - python-httplib2
```

Instala `curl` y `python-httplib2` en el nodo de control. `python-httplib2` es la dependencia que necesita el módulo `uri` de Ansible para realizar peticiones HTTP desde el nodo de control.

---

### 🗄️ Rol `mysql` — ⭐ El rol estrella de este ejemplo

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb
    - mysql-server

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: copy original config file
  copy: src=files/my.cnf dest=/etc/mysql/my.cnf owner=mysql group=mysql mode=0700

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
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

#### ⭐ El uso de Facts: `{{ ansible_eth0.ipv4.address }}`

```yaml
lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
            line="bind-address = {{ ansible_eth0.ipv4.address }}"
```

Esta es la línea más importante del ejemplo. En lugar de hardcodear `bind-address = 0.0.0.0` (como en ejemplos anteriores), Ansible usa el fact `ansible_eth0.ipv4.address` para obtener la IP real de la interfaz `eth0` del nodo de base de datos.

**¿Por qué es mejor?**

| **Enfoque** | **Código** | **Problema** |
|---|---|---|
| IP hardcodeada | `bind-address = 0.0.0.0` | Escucha en todas las interfaces — inseguro |
| IP del inventario hardcodeada | `bind-address = 192.168.11.20` | Rompe si cambia la IP del servidor |
| ⭐ **Fact dinámico** | `bind-address = {{ ansible_eth0.ipv4.address }}` | Siempre correcto, sin mantenimiento |

Con el fact dinámico, MySQL escucha **solo en la IP real de `eth0`** del servidor, no en todas las interfaces. Si el servidor cambia de IP, el playbook seguirá funcionando sin modificar ningún fichero.

#### ⭐ Nuevo patrón: `copy` de fichero base + `lineinfile`

```yaml
- name: copy original config file
  copy: src=files/my.cnf dest=/etc/mysql/my.cnf owner=mysql group=mysql mode=0700

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
  notify: restart mysql
```

Este es un patrón de dos pasos muy común en Ansible:

1. **`copy`**: Despliega un fichero de configuración base conocido y controlado (desde `roles/mysql/files/my.cnf`). Esto garantiza que el fichero siempre parte de un estado conocido, independientemente de lo que haya en el servidor.
2. **`lineinfile`**: Modifica quirúrgicamente una línea específica del fichero copiado usando una expresión regular (`regexp=^bind-address`) para localizar la directiva y reemplazarla con el valor dinámico.

**¿Por qué no usar solo una plantilla Jinja2?**
- `copy` + `lineinfile` es útil cuando el fichero de configuración es grande y complejo, y solo se necesita modificar una o pocas directivas.
- Una plantilla Jinja2 requeriría replicar todo el contenido del fichero en la plantilla.
- Este patrón es más mantenible cuando el fichero base cambia frecuentemente entre versiones del software.

#### Flujo de ejecución completo

1. Instala `python3-mysqldb` y `mysql-server`.
2. **Copia `my.cnf` base** desde `roles/mysql/files/my.cnf` al servidor con permisos `0700` (solo lectura/escritura para el usuario `mysql`).
3. **Modifica `bind-address`** en el `my.cnf` copiado usando el fact `ansible_eth0.ipv4.address`. Si cambia, dispara `restart mysql`.
4. Arranca MySQL y lo habilita en el boot.
5. Crea la base de datos `demo`.
6. Crea el usuario `demo` con permisos totales sobre `demo.*` desde cualquier host.

---

### 🌐 Rol `apache2`

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

Sin cambios respecto al ejemplo 018. Instala Apache2 + `mod_wsgi`, desactiva el VirtualHost por defecto y arranca el servicio.

---

### 🚀 Rol `demo_app`

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

Sin cambios respecto al ejemplo 018. Despliega el código Flask, configura el virtualenv Python 3 y activa el VirtualHost de Apache.

---

### ⚖️ Rol `nginx`

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

#### Plantilla `roles/nginx/templates/nginx.conf.j2`

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

Sin cambios respecto al ejemplo 018. La plantilla itera sobre `groups.webserver` para generar el bloque `upstream` dinámicamente.

---

## 📄 Playbook `playbooks/hostname.yml`

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

Ejecuta `hostname` en todos los nodos del inventario. Prueba de conectividad básica antes de cualquier despliegue.

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

## 🔄 Playbook `playbooks/stack_restart.yml` — ⭐ Con Facts

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

#### ⭐ `wait_for` con `host={{ ansible_eth0.ipv4.address }}`

```yaml
wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 state=started
```

En ejemplos anteriores, `wait_for` sin el parámetro `host` verificaba `localhost` (127.0.0.1). Ahora usa el fact `ansible_eth0.ipv4.address` para verificar que MySQL está escuchando en la **IP real de la interfaz de red**, que es exactamente la IP configurada en `bind-address`. Esto es coherente con el cambio en el rol `mysql`: si MySQL escucha en `192.168.11.20` (no en `0.0.0.0`), la verificación debe hacerse contra esa IP.

| **Fase** | **Nodo** | **Acción** | **`wait_for`** | **Descripción** |
|---|---|---|---|---|
| 1. Bajar LB | `loadbalancer` | Nginx `stopped` | `port=80 state=drained` | Espera cierre graceful de conexiones |
| 2. Bajar Web | `webserver` | Apache `stopped` | `port=80 state=stopped` | Espera que el puerto 80 deje de estar accesible |
| 3. Reiniciar BD | `database` | MySQL `restarted` | `host={{ ansible_eth0.ipv4.address }} port=3306 state=started` | ⭐ Verifica la IP real del nodo |
| 4. Subir Web | `webserver` | Apache `started` | `port=80` | Espera que el puerto 80 esté accesible |
| 5. Subir LB | `loadbalancer` | Nginx `started` | `port=80` | Espera que el puerto 80 esté accesible |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🔍 Playbook `playbooks/stack_status.yml` — ⭐ Con Facts y sintaxis modernizada

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
      wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 timeout=1

# NIVEL 2: End-to-end (desde el nodo de control, a través del loadbalancer)
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

# NIVEL 3: Backend directo (desde el loadbalancer, saltando el LB)
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

### Diferencias respecto al ejemplo 018

| **Aspecto** | **018** | **019** |
|---|---|---|
| `wait_for` en MySQL | `port=3306` (verifica localhost) | ⭐ `host={{ ansible_eth0.ipv4.address }} port=3306` |
| Sintaxis `with_items` en `uri` | `with_items: groups.loadbalancer` (sin llaves) | ⭐ `with_items: "{{ groups.loadbalancer }}"` (sintaxis moderna) |
| Condición `when` backend | `'Hello, from sunny {{item.item}}!'` (con IP específica) | `'Hello, from sunny'` (más genérico) |

### Tres niveles de verificación

| **Nivel** | **Ejecutado desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| **1. Proceso + Red** | Cada nodo (localhost) | Sus propios puertos | Servicio activo + puerto TCP abierto |
| **2. End-to-end** | `control` | `loadbalancer` (puerto 80) | Stack completo de extremo a extremo |
| **3. Backend directo** | `loadbalancer` | `webserver` (bypass LB) | Flask responde directamente en `/` y `/db` |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🚀 Comandos de ejecución

### Despliegue completo + verificación automática

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

Este es el comando principal. Despliega todo el stack **y** ejecuta `stack_status.yml` al final para verificar que todo funciona. Si algo falla, el playbook termina con error indicando exactamente qué componente no responde.

### Despliegue de componentes individuales

```bash
# Solo el nodo de control
ansible-playbook -i hosts -u vagrant control.yml

# Solo la base de datos
ansible-playbook -i hosts -u vagrant database.yml

# Solo el servidor web
ansible-playbook -i hosts -u vagrant webserver.yml

# Solo el balanceador de carga
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

### Exploración de Facts

```bash
# Ver TODOS los facts de un nodo
ansible database -i hosts -u vagrant -m setup

# Filtrar solo facts de red
ansible database -i hosts -u vagrant -m setup -a "filter=ansible_eth*"

# Ver la IP de eth0 de todos los nodos
ansible all -i hosts -u vagrant -m setup -a "filter=ansible_eth0"
```

### Operaciones de mantenimiento

```bash
# Verificar conectividad y hostnames
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml

# Verificar el estado del stack
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml

# Reiniciar el stack en orden correcto
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **018** | **019** |
|---|---|---|
| `site.yml` | Incluye 4 playbooks de despliegue | ⭐ Incluye 4 playbooks + `stack_status.yml` |
| `bind-address` en MySQL | `0.0.0.0` (hardcodeado) | ⭐ `{{ ansible_eth0.ipv4.address }}` (dinámico) |
| `wait_for` en MySQL | `port=3306` (localhost) | ⭐ `host={{ ansible_eth0.ipv4.address }} port=3306` |
| Fichero `my.cnf` | Modificado directamente con `lineinfile` | ⭐ Copiado desde `files/` + modificado con `lineinfile` |
| Sintaxis `with_items` | `with_items: groups.loadbalancer` (sin llaves) | ⭐ `with_items: "{{ groups.loadbalancer }}"` (moderna) |
| Verificación post-despliegue | Manual (comando separado) | ⭐ Automática (incluida en `site.yml`) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Ansible Facts**: Variables recopiladas automáticamente por el módulo `setup` al inicio de cada play. Contienen información detallada del sistema: IPs, interfaces, memoria, CPU, SO, etc.
- **`ansible_eth0.ipv4.address`**: Fact que contiene la IP de la interfaz `eth0` del nodo remoto. Permite eliminar IPs hardcodeadas de los playbooks, haciéndolos portables entre entornos.
- **`ansible_default_ipv4.address`**: Alternativa más robusta a `ansible_eth0.ipv4.address` — devuelve la IP de la interfaz de red por defecto, independientemente de su nombre (`eth0`, `ens33`, `enp0s3`, etc.). Recomendado en entornos modernos donde el nombre de la interfaz puede variar.
- **Patrón `copy` base + `lineinfile`**: Primero se despliega un fichero de configuración conocido y controlado, luego se modifica quirúrgicamente una directiva específica. Combina la reproducibilidad de `copy` con la precisión de `lineinfile`.
- **`wait_for: host=<fact>`**: Usar un fact en el parámetro `host` de `wait_for` garantiza que la verificación se hace contra la IP real donde el servicio está escuchando, no contra localhost.
- **`site.yml` con verificación integrada**: Incluir `stack_status.yml` en `site.yml` convierte el despliegue en una operación atómica con verificación automática — si algo falla, se detecta inmediatamente.
- **Sintaxis moderna de `with_items`**: `with_items: "{{ groups.loadbalancer }}"` (con llaves dobles y comillas) es la sintaxis correcta en Ansible 2.x+, frente a la sintaxis antigua `with_items: groups.loadbalancer`.
- **`ansible -m setup`**: Comando esencial para explorar los facts disponibles en un nodo antes de usarlos en playbooks.

---

## 📚 Referencias

- [Ansible Docs — Discovering variables: facts and magic variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
- [Ansible Docs — ansible.builtin.setup module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/setup_module.html)
- [Ansible Docs — ansible.builtin.wait_for module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
- [Ansible Docs — ansible.builtin.lineinfile module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html)
- [Ansible Docs — Special Variables (magic variables)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
