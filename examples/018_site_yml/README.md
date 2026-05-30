# 📋 Ejemplo 018 — `site.yml` como punto de entrada único con `include:`

## 🧭 Descripción general

Este ejemplo introduce el patrón más importante de organización en proyectos Ansible profesionales: el uso de **`site.yml` como orquestador maestro** que incluye todos los playbooks del proyecto mediante la directiva `include:`. En lugar de ejecutar cada playbook individualmente, un único comando despliega el stack completo.

La otra novedad clave es que `loadbalancer.yml` evoluciona significativamente: además del rol `nginx`, **declara los roles `haproxy` y `keepalived`** con un conjunto completo de variables de configuración orientadas a alta disponibilidad (HA). Estos roles no están implementados aún en el repositorio — ilustrando el patrón de diseño incremental donde se define la interfaz antes que la implementación.

---

## 🗂️ Estructura del proyecto

```
018_site_yml/
├── site.yml                       # ⭐ Orquestador maestro — incluye todos los playbooks
├── control.yml                    # Playbook del nodo de control
├── database.yml                   # Playbook del servidor de base de datos
├── webserver.yml                  # Playbook del servidor web
├── loadbalancer.yml               # ⭐ Playbook del LB — nginx + haproxy + keepalived
├── demo/                          # Código fuente de la aplicación Flask
├── playbooks/
│   ├── hostname.yml               # Diagnóstico: hostname de todos los nodos
│   ├── stack_restart.yml          # Reinicio ordenado del stack
│   └── stack_status.yml           # Verificación avanzada con uri + fail + with_items
└── roles/
    ├── control/                   # Rol: instala curl + python-httplib2
    ├── mysql/                     # Rol: instala y configura MySQL
    ├── apache2/                   # Rol: infraestructura Apache + mod_wsgi
    ├── demo_app/                  # Rol: despliega Flask, virtualenv, VirtualHost
    └── nginx/                     # Rol: balanceador de carga Nginx
```

> ⚠️ **Nota**: Los roles `haproxy` y `keepalived` están **declarados** en `loadbalancer.yml` pero sus directorios no existen en el repositorio. Son roles planificados que ilustran el diseño incremental de infraestructura.

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
| `[loadbalancer]` | `192.168.11.30` | `nginx` + `haproxy` + `keepalived` *(planificados)* |
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

Este es el fichero más importante del ejemplo. Con solo **4 líneas**, orquesta el despliegue completo de toda la infraestructura.

### ¿Qué hace `include:` en `site.yml`?

La directiva `include:` importa el contenido de otro fichero YAML en el punto donde se declara, como si sus plays estuvieran escritos directamente en `site.yml`. El resultado es funcionalmente equivalente a tener todos los plays de todos los playbooks en un único fichero, pero con la ventaja de mantener cada componente en su propio fichero.

### Orden de ejecución

Ansible ejecuta los includes **en el orden en que están declarados**:

```
1. control.yml    → Prepara el nodo de control (instala curl, python-httplib2)
2. database.yml   → Despliega MySQL en 192.168.11.20
3. webserver.yml  → Despliega Apache2 + Flask en 192.168.11.40
4. loadbalancer.yml → Despliega Nginx en 192.168.11.30
```

Este orden es deliberado: la base de datos debe estar lista antes que la aplicación web, y el balanceador de carga se configura al final cuando ya sabe qué servidores web están disponibles.

### Ventajas del patrón `site.yml` con `include:`

| **Ventaja** | **Descripción** |
|---|---|
| **Punto de entrada único** | Un solo comando despliega toda la infraestructura |
| **Modularidad** | Cada componente sigue viviendo en su propio fichero |
| **Despliegue selectivo** | Se puede ejecutar solo `database.yml` o solo `webserver.yml` cuando sea necesario |
| **Legibilidad** | `site.yml` actúa como índice del proyecto — muestra de un vistazo qué componentes existen |
| **Idempotencia total** | Re-ejecutar `site.yml` es seguro: Ansible solo aplica los cambios necesarios |

> ⚠️ **Nota sobre `include:` vs `import_playbook:`**: En Ansible 2.x+, la directiva `include:` a nivel de play fue deprecada en favor de `import_playbook:` (estático) e `include_playbook:` (dinámico). Este ejemplo usa la sintaxis clásica de Ansible 1.x/2.x temprano. En proyectos modernos se usa:
> ```yaml
> - import_playbook: control.yml
> - import_playbook: database.yml
> - import_playbook: webserver.yml
> - import_playbook: loadbalancer.yml
> ```

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

Prepara el nodo de control instalando las herramientas necesarias para ejecutar verificaciones HTTP desde él.

### `database.yml`

```yaml
---
- hosts: database
  become: true
  roles:
    - mysql
```

Despliega el servidor MySQL en `192.168.11.20`.

### `webserver.yml`

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

Despliega la infraestructura web (`apache2`) y la aplicación Flask (`demo_app`) en `192.168.11.40`. El orden de roles es importante: `apache2` instala y configura el servidor antes de que `demo_app` despliegue el código.

### ⭐ `loadbalancer.yml` — El fichero más avanzado

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
    - haproxy
    - keepalived
  vars:
    nginx_http_port: 80
    nginx_https_port: 443
    nginx_http2: true
    nginx_ssl_certificate: "/etc/ssl/certs/ssl-cert-snakeoil.pem"
    nginx_ssl_certificate_key: "/etc/ssl/private/ssl-cert-snakeoil.key"
    haproxy_frontend_port: 80
    haproxy_backend_servers:
      - { name: "web1", address: "0.0.0.0", port: 80 }
    keepalived_vrrp_id: 51
    keepalived_vrrp_priority: 100
    keepalived_vrrp_auth_pass: "password"
    keepalived_vrrp_virtual_ip: ""
    keepalived_vrrp_state: "MASTER"
    keepalived_vrrp_interface: "eth0"
    keepalived_vrrp_virtual_router_id: 51
    keepalived_vrrp_unicast_peer: []
    keepalived_vrrp_unicast_src_ip: ""
    keepalived_vrrp_track_script: "check_haproxy"
    keepalived_vrrp_script_name: "check_haproxy"
```

Este playbook es la declaración de intención de una arquitectura de **alta disponibilidad (HA)** en el balanceador de carga. Combina tres capas:

| **Rol** | **Función** | **Estado** |
|---|---|---|
| `nginx` | Proxy inverso y balanceador de carga HTTP | ✅ Implementado |
| `haproxy` | Balanceador de carga TCP/HTTP de nivel 4/7 | ⚠️ Declarado, no implementado |
| `keepalived` | IP virtual flotante (VRRP) para failover entre LBs | ⚠️ Declarado, no implementado |

#### Variables de `nginx`

| **Variable** | **Valor** | **Descripción** |
|---|---|---|
| `nginx_http_port` | `80` | Puerto HTTP de escucha |
| `nginx_https_port` | `443` | Puerto HTTPS de escucha |
| `nginx_http2` | `true` | Activa el protocolo HTTP/2 |
| `nginx_ssl_certificate` | `/etc/ssl/certs/ssl-cert-snakeoil.pem` | Certificado SSL (autofirmado para desarrollo) |
| `nginx_ssl_certificate_key` | `/etc/ssl/private/ssl-cert-snakeoil.key` | Clave privada del certificado SSL |

#### Variables de `haproxy`

| **Variable** | **Valor** | **Descripción** |
|---|---|---|
| `haproxy_frontend_port` | `80` | Puerto de entrada del frontend HAProxy |
| `haproxy_backend_servers` | `[{name: web1, address: 0.0.0.0, port: 80}]` | Lista de servidores backend en formato dict |

#### Variables de `keepalived` (VRRP)

| **Variable** | **Valor** | **Descripción** |
|---|---|---|
| `keepalived_vrrp_id` | `51` | ID del grupo VRRP (debe coincidir entre nodos LB) |
| `keepalived_vrrp_priority` | `100` | Prioridad del nodo (mayor = MASTER) |
| `keepalived_vrrp_state` | `"MASTER"` | Rol del nodo: `MASTER` o `BACKUP` |
| `keepalived_vrrp_interface` | `"eth0"` | Interfaz de red para VRRP |
| `keepalived_vrrp_virtual_ip` | `""` | IP virtual flotante (a configurar) |
| `keepalived_vrrp_virtual_router_id` | `51` | ID del router virtual VRRP |
| `keepalived_vrrp_auth_pass` | `"password"` | Contraseña de autenticación VRRP |
| `keepalived_vrrp_track_script` | `"check_haproxy"` | Script de monitorización del servicio HAProxy |

> **¿Qué es VRRP?** El *Virtual Router Redundancy Protocol* permite que dos o más nodos compartan una IP virtual. Si el nodo `MASTER` falla, el nodo `BACKUP` asume la IP virtual automáticamente — los clientes no notan la interrupción. Es el mecanismo estándar para alta disponibilidad en balanceadores de carga.

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

Instala `curl` (herramienta de diagnóstico HTTP) y `python-httplib2` (dependencia del módulo `uri` de Ansible) en el nodo de control.

---

### 🗄️ Rol `mysql`

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

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

1. Instala `python3-mysqldb` — librería Python 3 necesaria para que Ansible gestione MySQL con los módulos `mysql_db` y `mysql_user`. Nótese el cambio de `python-mysqldb` (Python 2) a `python3-mysqldb` (Python 3) respecto a ejemplos anteriores.
2. Instala el servidor MySQL.
3. Modifica `bind-address` en `/etc/mysql/my.cnf` a `0.0.0.0` para aceptar conexiones remotas. Si la línea cambia, dispara el handler `restart mysql`.
4. Arranca MySQL y lo habilita en el boot.
5. Crea la base de datos `demo`.
6. Crea el usuario `demo` con contraseña `demo` y permisos totales sobre `demo.*` desde cualquier host (`host='%'`).

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

#### Flujo de ejecución

1. Instala Apache2 y el módulo WSGI para Python (`libapache2-mod-wsgi`).
2. Activa `mod_wsgi` — necesario para que Apache ejecute aplicaciones Python/Flask. Si cambia, dispara `restart apache2`.
3. Elimina el VirtualHost por defecto de Apache para evitar conflictos con el site de la demo.
4. Arranca Apache y lo habilita en el boot.

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

#### Evolución respecto a ejemplos anteriores

| **Paquete** | **Ejemplo 017** | **Ejemplo 018** |
|---|---|---|
| pip | `python-pip` | `python-pip-whl` |
| virtualenv | `python-virtualenv` | `python3-virtualenv` |
| mysqldb | `python-mysqldb` | `python3-mysqldb` |

La migración completa a Python 3 es la diferencia más significativa en este rol.

#### Flujo de ejecución

1. Instala las dependencias Python 3 necesarias.
2. **Copia el código fuente** Flask desde `roles/demo_app/files/demo/app/` a `/var/www/demo`. Ansible resuelve la ruta `src=demo/app/` automáticamente desde `roles/demo_app/files/`.
3. **Copia el VirtualHost** de Apache a `/etc/apache2/sites-available/`.
4. **Crea el virtualenv** e instala dependencias de `requirements.txt` con `pip`.
5. **Activa el VirtualHost** con un enlace simbólico en `sites-enabled/`.

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

El bucle `{% for server in groups.webserver %}` itera sobre todos los hosts del grupo `[webserver]` del inventario. Si se añaden más webservers, Nginx los balanceará automáticamente en round-robin sin modificar ningún fichero.

#### Flujo de ejecución

1. Instala `python-httplib2` — dependencia del módulo `uri` de Ansible.
2. Instala Nginx.
3. **Procesa la plantilla** `nginx.conf.j2` y despliega el resultado. Si cambia, dispara `restart nginx`.
4. Elimina el site por defecto de Nginx.
5. Activa el site de la demo con un enlace simbólico.
6. Arranca Nginx y lo habilita en el boot.

---

## 📄 Playbook `playbooks/hostname.yml`

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

Ejecuta `hostname` en **todos los nodos del inventario**. Es la prueba de conectividad más básica — verifica que Ansible puede conectarse por SSH a todos los nodos antes de un despliegue.

```bash
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

## 🔄 Playbook `playbooks/stack_restart.yml`

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

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🔍 Playbook `playbooks/stack_status.yml`

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

### Variables clave en los resultados de `with_items` + `register`

| **Variable** | **Descripción** |
|---|---|
| `item` | Cada resultado del loop de `uri` (objeto con `.content`, `.status`, `.item`) |
| `item.content` | Cuerpo de la respuesta HTTP |
| `item.item` | La IP del servidor que generó este resultado (el `{{item}}` del loop de `uri`) |
| `not in` | Operador Jinja2: `true` si el string NO está en el contenido — dispara `fail` |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 🚀 Comandos de ejecución

### Despliegue completo del stack (punto de entrada único)

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

Este es el comando principal del ejemplo. Ejecuta `control.yml`, `database.yml`, `webserver.yml` y `loadbalancer.yml` en secuencia.

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

### Operaciones de mantenimiento

```bash
# Verificar conectividad y hostnames de todos los nodos
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml

# Verificar el estado del stack (3 niveles de comprobación)
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml

# Reiniciar el stack en orden correcto
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **017** | **018** |
|---|---|---|
| Punto de entrada | Playbooks individuales | ⭐ `site.yml` con `include:` |
| Despliegue completo | 4 comandos separados | ⭐ 1 único comando |
| Python | Python 2 (`python-mysqldb`, `python-virtualenv`) | ⭐ Python 3 (`python3-mysqldb`, `python3-virtualenv`) |
| Balanceador de carga | Solo `nginx` | ⭐ `nginx` + `haproxy` + `keepalived` (planificados) |
| Alta disponibilidad | No contemplada | ⭐ Variables VRRP declaradas para HA futura |
| SSL/TLS | No contemplado | ⭐ Variables SSL declaradas en `loadbalancer.yml` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **`site.yml` con `include:`**: El patrón más importante de organización en Ansible. Un único punto de entrada que orquesta todo el proyecto sin sacrificar la modularidad. En Ansible moderno se usa `import_playbook:` en su lugar.
- **Diseño incremental de infraestructura**: Declarar roles con sus variables antes de implementarlos permite definir la interfaz y los parámetros de configuración como contrato, facilitando el trabajo en equipo y la planificación.
- **Alta disponibilidad con `keepalived` + VRRP**: El patrón estándar para LBs en HA: una IP virtual flotante que migra automáticamente al nodo `BACKUP` si el `MASTER` falla.
- **`haproxy` como complemento a `nginx`**: HAProxy opera en capa 4/7 con algoritmos de balanceo más avanzados (least connections, source hashing), mientras que Nginx es más versátil como proxy inverso con terminación SSL.
- **Migración Python 2 → Python 3**: El cambio de `python-mysqldb` a `python3-mysqldb` y de `python-virtualenv` a `python3-virtualenv` refleja la evolución del ecosistema.
- **`wait_for: state=drained`**: Permite apagados graceful del loadbalancer esperando a que todas las conexiones activas se cierren antes de confirmar la parada.
- **`item.item` en resultados de loop**: Cuando se itera sobre `register.results`, `item.item` contiene el valor original del `{{item}}` del loop que generó ese resultado — clave para verificaciones específicas por nodo.

---

## 📚 Referencias

- [Ansible Docs — `import_playbook`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/import_playbook_module.html)
- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — `ansible.builtin.template` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — `ansible.builtin.wait_for` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
- [Ansible Docs — `ansible.builtin.uri` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [HAProxy Documentation](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [Keepalived — VRRP Documentation](https://keepalived.readthedocs.io/en/latest/configuration_synopsis.html)
