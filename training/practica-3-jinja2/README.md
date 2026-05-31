# 📋 `training/practica-3-jinja2/` — Infraestructura completa con Roles y Plantillas Jinja2

## 🧭 Descripción general

La práctica `practica-3-jinja2` es el ejemplo más completo del curso: despliega una **infraestructura web de tres capas** usando la combinación más potente de Ansible — **Roles + Plantillas Jinja2**. Cada capa de la arquitectura está encapsulada en un rol independiente, y la configuración de cada servicio se genera dinámicamente mediante plantillas `.j2` que se adaptan al entorno en tiempo de ejecución.

La arquitectura desplegada es:

- 🌐 **Webserver** (`192.168.11.40`) → Roles: `apache2` + `php` + `pagina`
- 🗄️ **Database** (`192.168.11.20`) → Rol: `mariadb`
- ⚖️ **Loadbalancer** (`192.168.11.30`) → Roles: `nginx` + `users`

---

## 🗂️ Estructura del directorio

```
practica-3-jinja2/
├── main.yml                          # Punto de entrada — orquesta los 6 roles
├── inventory                         # Inventario de hosts del laboratorio
├── apache2/                          # Rol: servidor web Apache2
│   ├── defaults/main.yml             # Variables por defecto (baja precedencia)
│   ├── files/                        # Ficheros estáticos a copiar tal cual
│   ├── handlers/main.yml             # Handler: reiniciar Apache2
│   ├── tasks/main.yml                # Tareas: instalar y configurar Apache2
│   ├── templates/                    # Plantillas Jinja2 de configuración
│   └── vars/main.yml                 # Variables del rol (alta precedencia)
├── mariadb/                          # Rol: base de datos MariaDB
│   ├── defaults/main.yml             # Variables por defecto
│   ├── handlers/main.yml             # Handler: reiniciar MariaDB
│   ├── tasks/main.yml                # Tareas: instalar y configurar MariaDB
│   ├── templates/                    # Plantillas Jinja2 de configuración
│   └── vars/main.yml                 # Variables del rol
└── nginx/                            # Rol: balanceador de carga Nginx
    ├── defaults/main.yml             # Variables por defecto
    ├── handlers/main.yml             # Handler: reiniciar Nginx
    ├── tasks/main.yml                # Tareas: instalar y configurar Nginx
    ├── templates/                    # Plantillas Jinja2 de configuración
    └── vars/main.yml                 # Variables del rol
```

> Los roles `php`, `pagina` y `users` también están presentes en el directorio aunque siguen la misma estructura estándar de roles Ansible.

---

## 🗂️ Inventario `inventory`

```ini
[database]
192.168.11.20

[loadbalancer]
192.168.11.30

[webserver]
192.168.11.40
```

En esta práctica el inventario se llama `inventory` (sin extensión), no `hosts`. Esto es perfectamente válido en Ansible — el nombre del fichero de inventario es libre, lo que cambia es el argumento `-i` al ejecutar el playbook.

---

## 📄 `main.yml` — El director de orquesta (código real)

```yaml
---
- hosts: all

- name: Instalar webserver
  hosts: webserver
  become: yes
  gather_facts: yes
  roles:
    - role: apache2
    - role: php
    - role: pagina

- name: Instalar database
  hosts: database
  become: yes
  gather_facts: yes
  roles:
    - role: mariadb

- name: Instalar loadbalancer
  hosts: loadbalancer
  become: yes
  gather_facts: yes
  roles:
    - role: nginx
    - role: users
```

### Análisis línea a línea

#### El play vacío inicial: `- hosts: all`

```yaml
- hosts: all
```

Este play sin tareas ni roles tiene un propósito concreto y muy importante: **forzar la recopilación de facts (`gather_facts`) en todos los nodos al inicio**, antes de que empiece cualquier play real.

¿Por qué es necesario? Porque la plantilla Jinja2 del rol `nginx` (balanceador) necesita conocer las IPs de los nodos del grupo `webserver`. Si `gather_facts` solo se ejecutara en el play del loadbalancer, los `hostvars` de los webservers no estarían disponibles. Este play vacío garantiza que **todos los facts de todos los nodos están en memoria** cuando cualquier plantilla los necesite.

```
- hosts: all          ← Recopila facts de .20, .30 y .40 ANTES de todo
- hosts: webserver    ← Ahora puede usar facts de cualquier nodo
- hosts: database     ← Ídem
- hosts: loadbalancer ← Puede usar hostvars[webserver] con seguridad
```

#### Los tres plays principales

| **Play** | **`hosts`** | **Roles aplicados** | **IP destino** |
|---|---|---|---|
| Instalar webserver | `webserver` | `apache2` → `php` → `pagina` | 192.168.11.40 |
| Instalar database | `database` | `mariadb` | 192.168.11.20 |
| Instalar loadbalancer | `loadbalancer` | `nginx` → `users` | 192.168.11.30 |

Todos los plays comparten:
- `become: yes` → Escalada de privilegios a `root` para todas las tareas
- `gather_facts: yes` → Recopilación de facts del sistema (aunque ya se hizo en el play inicial, aquí se refresca para el contexto del play)

---

## 🌐 Rol `apache2` — Servidor web

### `apache2/tasks/main.yml`

```yaml
---
- name: Instalar Apache2
  apt:
    name: apache2
    state: present
    update_cache: yes

- name: Asegurar que Apache2 está activo y habilitado
  service:
    name: apache2
    state: started
    enabled: yes

- name: Desplegar virtualhost desde plantilla
  template:
    src: virtualhost.conf.j2
    dest: /etc/apache2/sites-available/app.conf
    owner: root
    group: root
    mode: "0644"
  notify: Reiniciar Apache2

- name: Activar el virtualhost
  command: a2ensite app.conf
  notify: Reiniciar Apache2

- name: Desactivar el virtualhost por defecto
  command: a2dissite 000-default.conf
  notify: Reiniciar Apache2
```

### `apache2/handlers/main.yml`

```yaml
---
- name: Reiniciar Apache2
  service:
    name: apache2
    state: restarted
```

### `apache2/defaults/main.yml`

```yaml
---
apache2_port: 80
apache2_server_name: "{{ inventory_hostname }}"
apache2_document_root: /var/www/html
apache2_server_admin: webmaster@localhost
```

Las variables en `defaults/` tienen la **precedencia más baja** de todas las variables de Ansible. Esto significa que pueden ser sobreescritas desde el inventario, desde `group_vars`, desde `vars/main.yml` del propio rol, o desde la línea de comandos con `-e`. Son los valores "por defecto razonables" que el usuario puede personalizar sin tocar el rol.

### `apache2/templates/virtualhost.conf.j2`

```jinja2
<VirtualHost *:{{ apache2_port }}>
    ServerAdmin {{ apache2_server_admin }}
    ServerName {{ apache2_server_name }}
    DocumentRoot {{ apache2_document_root }}

    <Directory {{ apache2_document_root }}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

**Resultado generado** en `192.168.11.40`:

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName 192.168.11.40
    DocumentRoot /var/www/html
    ...
</VirtualHost>
```

---

## 🐘 Rol `php` — Módulo PHP para Apache

Este rol instala PHP y sus módulos necesarios para que Apache pueda servir páginas dinámicas.

### `php/tasks/main.yml`

```yaml
---
- name: Instalar PHP y módulos necesarios
  apt:
    name:
      - php
      - php-mysql
      - libapache2-mod-php
    state: present
    update_cache: yes

- name: Habilitar módulo PHP en Apache
  command: a2enmod php8.1
  notify: Reiniciar Apache2
```

> `php-mysql` es el conector PHP-MariaDB que permite a la aplicación web conectarse a la base de datos en `192.168.11.20`.

---

## 📄 Rol `pagina` — Despliegue de la aplicación web

Este rol despliega el contenido de la aplicación web usando una plantilla Jinja2 que genera HTML dinámico con información del servidor.

### `pagina/tasks/main.yml`

```yaml
---
- name: Desplegar página principal desde plantilla
  template:
    src: index.php.j2
    dest: /var/www/html/index.php
    owner: www-data
    group: www-data
    mode: "0644"

- name: Eliminar index.html por defecto
  file:
    path: /var/www/html/index.html
    state: absent
```

### `pagina/templates/index.php.j2`

```jinja2
<!DOCTYPE html>
<html>
<head>
    <title>Aplicación Web - {{ inventory_hostname }}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; }
        .info { background: white; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="info">
        <h1>🚀 Servidor Web Activo</h1>
        <table>
            <tr><td><strong>Hostname:</strong></td><td>{{ inventory_hostname }}</td></tr>
            <tr><td><strong>IP:</strong></td><td>{{ ansible_default_ipv4.address }}</td></tr>
            <tr><td><strong>SO:</strong></td><td>{{ ansible_distribution }} {{ ansible_distribution_version }}</td></tr>
            <tr><td><strong>Kernel:</strong></td><td>{{ ansible_kernel }}</td></tr>
            <tr><td><strong>CPUs:</strong></td><td>{{ ansible_processor_vcpus }}</td></tr>
            <tr><td><strong>RAM:</strong></td><td>{{ ansible_memtotal_mb }} MB</td></tr>
        </table>
        <?php
        // Conexión a la base de datos
        $conn = new mysqli("{{ hostvars[groups['database'][0]]['ansible_default_ipv4']['address'] }}", "appuser", "S3cur3P@ss", "appdb");
        if ($conn->connect_error) {
            echo "<p style='color:red'>❌ BD no disponible</p>";
        } else {
            echo "<p style='color:green'>✅ Conectado a MariaDB</p>";
        }
        ?>
    </div>
</body>
</html>
```

Esta plantilla es el ejemplo más avanzado de Jinja2 en toda la práctica. Combina:

| **Expresión Jinja2** | **Significado** |
|---|---|
| `{{ inventory_hostname }}` | Nombre/IP del nodo actual según el inventario |
| `{{ ansible_default_ipv4.address }}` | IP principal del nodo (fact del sistema) |
| `{{ ansible_distribution }}` | Distribución Linux (ej: `Ubuntu`) |
| `{{ ansible_memtotal_mb }}` | RAM total en MB (fact del sistema) |
| `{{ hostvars[groups['database'][0]]['ansible_default_ipv4']['address'] }}` | IP del primer nodo del grupo `database` — accede a facts de **otro nodo** |

La última expresión es la más poderosa: desde la plantilla del webserver, se accede a la IP de la base de datos consultando los `hostvars` del grupo `database`. Esto es posible gracias al play `- hosts: all` inicial que recopiló los facts de todos los nodos.

---

## 🗄️ Rol `mariadb` — Base de datos

### `mariadb/tasks/main.yml`

```yaml
---
- name: Instalar MariaDB y conector Python
  apt:
    name:
      - mariadb-server
      - python3-mysqldb
    state: present
    update_cache: yes

- name: Asegurar que MariaDB está activo y habilitado
  service:
    name: mariadb
    state: started
    enabled: yes

- name: Desplegar configuración desde plantilla
  template:
    src: 50-server.cnf.j2
    dest: /etc/mysql/mariadb.conf.d/50-server.cnf
    owner: root
    group: root
    mode: "0644"
  notify: Reiniciar MariaDB

- name: Crear base de datos de la aplicación
  mysql_db:
    name: "{{ db_name }}"
    state: present

- name: Crear usuario de la aplicación
  mysql_user:
    name: "{{ db_user }}"
    password: "{{ db_password }}"
    priv: "{{ db_name }}.*:ALL"
    host: "%"
    state: present
```

### `mariadb/handlers/main.yml`

```yaml
---
- name: Reiniciar MariaDB
  service:
    name: mariadb
    state: restarted
```

### `mariadb/defaults/main.yml`

```yaml
---
db_name: appdb
db_user: appuser
db_password: "S3cur3P@ss"
mysql_bind_address: "0.0.0.0"
mysql_max_connections: 100
```

### `mariadb/templates/50-server.cnf.j2`

```jinja2
[mysqld]
# Configuración de red
bind-address            = {{ mysql_bind_address }}
port                    = 3306

# Configuración de rendimiento
max_connections         = {{ mysql_max_connections }}
innodb_buffer_pool_size = {{ (ansible_memtotal_mb * 0.3) | int }}M

# Rutas estándar
datadir                 = /var/lib/mysql
socket                  = /run/mysqld/mysqld.sock
pid-file                = /run/mysqld/mysqld.pid

# Logging
log_error               = /var/log/mysql/error.log
```

El fragmento más destacado es:

```jinja2
innodb_buffer_pool_size = {{ (ansible_memtotal_mb * 0.3) | int }}M
```

Esto calcula dinámicamente el tamaño del buffer pool de InnoDB como el **30% de la RAM total del nodo**, usando el fact `ansible_memtotal_mb` y el filtro Jinja2 `| int` para convertir el resultado a entero. En una VM con 1024 MB de RAM, generaría:

```ini
innodb_buffer_pool_size = 307M
```

Este es un ejemplo perfecto de **configuración adaptativa**: el mismo playbook genera una configuración de MariaDB diferente y optimizada para cada servidor según sus recursos reales.

---

## ⚖️ Rol `nginx` — Balanceador de carga

### `nginx/tasks/main.yml`

```yaml
---
- name: Instalar Nginx
  apt:
    name: nginx
    state: present
    update_cache: yes

- name: Asegurar que Nginx está activo y habilitado
  service:
    name: nginx
    state: started
    enabled: yes

- name: Desplegar configuración del balanceador desde plantilla
  template:
    src: loadbalancer.conf.j2
    dest: /etc/nginx/sites-available/loadbalancer.conf
    owner: root
    group: root
    mode: "0644"
  notify: Reiniciar Nginx

- name: Activar el sitio del balanceador
  file:
    src: /etc/nginx/sites-available/loadbalancer.conf
    dest: /etc/nginx/sites-enabled/loadbalancer.conf
    state: link
  notify: Reiniciar Nginx

- name: Eliminar sitio por defecto de Nginx
  file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Reiniciar Nginx
```

### `nginx/handlers/main.yml`

```yaml
---
- name: Reiniciar Nginx
  service:
    name: nginx
    state: restarted
```

### `nginx/defaults/main.yml`

```yaml
---
nginx_port: 80
nginx_worker_processes: "{{ ansible_processor_vcpus }}"
nginx_worker_connections: 1024
```

`nginx_worker_processes` se inicializa directamente con el fact `ansible_processor_vcpus`, adaptando Nginx al número real de CPUs del nodo.

### `nginx/templates/loadbalancer.conf.j2`

```jinja2
worker_processes {{ nginx_worker_processes }};

events {
    worker_connections {{ nginx_worker_connections }};
}

http {
    upstream webservers {
{% for host in groups['webserver'] %}
        server {{ hostvars[host]['ansible_default_ipv4']['address'] }};
{% endfor %}
    }

    server {
        listen {{ nginx_port }};

        location / {
            proxy_pass         http://webservers;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        }
    }
}
```

**Resultado generado** para el inventario del laboratorio (1 webserver, 1 vCPU):

```nginx
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    upstream webservers {
        server 192.168.11.40;
    }

    server {
        listen 80;
        location / {
            proxy_pass         http://webservers;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        }
    }
}
```

El bucle Jinja2 `{% for host in groups['webserver'] %}` itera sobre todos los hosts del grupo `webserver`. Si el inventario tuviera 3 webservers, el bloque `upstream` tendría 3 entradas automáticamente — sin tocar la plantilla.

---

## 👥 Rol `users` — Gestión de usuarios del sistema

Este rol crea los usuarios del sistema necesarios para la operación del balanceador (usuarios de administración, monitorización, etc.).

### `users/tasks/main.yml`

```yaml
---
- name: Crear usuarios del sistema desde lista
  user:
    name: "{{ item.name }}"
    shell: "{{ item.shell | default('/bin/bash') }}"
    groups: "{{ item.groups | default('') }}"
    state: present
  loop: "{{ system_users }}"

- name: Desplegar claves SSH autorizadas
  authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.ssh_key }}"
    state: present
  loop: "{{ system_users }}"
  when: item.ssh_key is defined
```

### `users/defaults/main.yml`

```yaml
---
system_users:
  - name: deploy
    shell: /bin/bash
    groups: sudo
    ssh_key: "ssh-rsa AAAA..."
  - name: monitor
    shell: /bin/bash
    groups: ""
```

El módulo `loop` itera sobre la lista `system_users`, creando cada usuario con sus atributos. El filtro `| default('/bin/bash')` proporciona un valor de respaldo si el atributo `shell` no está definido para un usuario concreto. La directiva `when: item.ssh_key is defined` solo despliega la clave SSH si el usuario tiene una definida.

---

## 🔄 Flujo de ejecución completo de `main.yml`

```
ansible-playbook -i inventory -u vagrant main.yml
│
│  ══════════════════════════════════════════════════════
│  PLAY 0: - hosts: all  (sin nombre, sin tareas)
│  hosts: all → 192.168.11.20 + .30 + .40
│  ══════════════════════════════════════════════════════
│  [Gathering Facts] en los 3 nodos simultáneamente
│  └── Carga hostvars de todos los nodos en memoria
│
│  ══════════════════════════════════════════════════════
│  PLAY 1: Instalar webserver
│  hosts: webserver (192.168.11.40)
│  ══════════════════════════════════════════════════════
│  ROL apache2:
│  ├── apt: instala apache2
│  ├── service: arranca y habilita apache2
│  ├── template: virtualhost.conf.j2 → /etc/apache2/sites-available/app.conf
│  ├── command: a2ensite app.conf
│  └── command: a2dissite 000-default.conf
│      └── [handler] Reiniciar Apache2
│  ROL php:
│  ├── apt: instala php + php-mysql + libapache2-mod-php
│  └── command: a2enmod php8.1
│      └── [handler] Reiniciar Apache2
│  ROL pagina:
│  ├── template: index.php.j2 → /var/www/html/index.php
│  │   └── Usa hostvars[groups['database'][0]] para la IP de la BD
│  └── file: elimina /var/www/html/index.html
│
│  ══════════════════════════════════════════════════════
│  PLAY 2: Instalar database
│  hosts: database (192.168.11.20)
│  ══════════════════════════════════════════════════════
│  ROL mariadb:
│  ├── apt: instala mariadb-server + python3-mysqldb
│  ├── service: arranca y habilita mariadb
│  ├── template: 50-server.cnf.j2 → /etc/mysql/mariadb.conf.d/50-server.cnf
│  │   └── Calcula innodb_buffer_pool_size = RAM * 0.3
│  ├── mysql_db: crea base de datos "appdb"
│  └── mysql_user: crea usuario "appuser" con acceso desde cualquier host
│      └── [handler] Reiniciar MariaDB
│
│  ══════════════════════════════════════════════════════
│  PLAY 3: Instalar loadbalancer
│  hosts: loadbalancer (192.168.11.30)
│  ══════════════════════════════════════════════════════
│  ROL nginx:
│  ├── apt: instala nginx
│  ├── service: arranca y habilita nginx
│  ├── template: loadbalancer.conf.j2 → /etc/nginx/sites-available/loadbalancer.conf
│  │   └── Genera upstream con IPs de todos los hosts del grupo webserver
│  ├── file (link): activa el sitio en sites-enabled
│  └── file (absent): elimina el sitio default
│      └── [handler] Reiniciar Nginx
│  ROL users:
│  ├── user: crea usuarios del sistema (loop sobre system_users)
│  └── authorized_key: despliega claves SSH (cuando ssh_key está definida)
│
└── PLAY RECAP ──────────────────────────────────────────
    192.168.11.20  : ok=6  changed=4  unreachable=0  failed=0
    192.168.11.30  : ok=7  changed=5  unreachable=0  failed=0
    192.168.11.40  : ok=8  changed=6  unreachable=0  failed=0
```

---

## 🚀 Comandos de ejecución

### Despliegue completo de la infraestructura
```bash
ansible-playbook -i inventory -u vagrant main.yml
```

### Despliegue solo de un componente específico
```bash
# Solo el servidor web (Apache + PHP + página)
ansible-playbook -i inventory -u vagrant main.yml --limit webserver

# Solo la base de datos
ansible-playbook -i inventory -u vagrant main.yml --limit database

# Solo el balanceador
ansible-playbook -i inventory -u vagrant main.yml --limit loadbalancer
```

### Dry-run — Ver qué cambiaría sin aplicar nada
```bash
ansible-playbook -i inventory -u vagrant main.yml --check
```

### Verificar sintaxis antes de ejecutar
```bash
ansible-playbook -i inventory -u vagrant main.yml --syntax-check
```

### Ejecución con salida detallada (debug)
```bash
ansible-playbook -i inventory -u vagrant main.yml -v
```

### Ejecución con salida muy detallada (ver valores de variables)
```bash
ansible-playbook -i inventory -u vagrant main.yml -vvv
```

---

## 💡 Conceptos clave aprendidos

- **Play vacío `- hosts: all` para pre-cargar facts**: El patrón de abrir `main.yml` con un play sin tareas que apunta a `all` es una técnica fundamental cuando las plantillas Jinja2 de un nodo necesitan acceder a `hostvars` de otros nodos. Sin este play inicial, los facts de los nodos que aún no han sido procesados no estarían disponibles.

- **`defaults/main.yml` vs `vars/main.yml`**: Los `defaults` son valores de baja precedencia pensados para ser sobreescritos por el usuario (personalización). Las `vars` son valores de alta precedencia que el rol impone y que no deben cambiarse externamente. La elección entre uno y otro es una decisión de diseño del rol.

- **Plantillas Jinja2 con cálculos dinámicos**: El fragmento `{{ (ansible_memtotal_mb * 0.3) | int }}M` en la configuración de MariaDB demuestra que las plantillas pueden contener **expresiones matemáticas** aplicadas sobre facts del sistema. El mismo playbook genera configuraciones diferentes y optimizadas para cada servidor.

- **`hostvars` y `groups` para referencias cruzadas entre nodos**: La expresión `{{ hostvars[groups['database'][0]]['ansible_default_ipv4']['address'] }}` en la plantilla PHP accede a la IP de la base de datos desde la plantilla del webserver. Esto elimina la necesidad de hardcodear IPs y hace la infraestructura completamente dinámica.

- **Bucles `{% for %}` en plantillas para escalabilidad automática**: El bloque `upstream` de Nginx se construye iterando sobre `groups['webserver']`. Añadir un segundo webserver al inventario (`192.168.11.41`) haría que el balanceador lo incluyera automáticamente en la siguiente ejecución del playbook.

- **`loop` con `| default()` en tareas**: El módulo `user` con `loop` y filtros `| default()` es el patrón estándar para gestionar listas de recursos (usuarios, paquetes, ficheros) de forma declarativa y concisa.

- **Orden de roles dentro de un play**: En el play del webserver, el orden `apache2` → `php` → `pagina` es deliberado: Apache debe estar instalado antes de habilitar el módulo PHP, y PHP debe estar disponible antes de desplegar el fichero `.php` de la aplicación.

- **`gather_facts: yes` explícito**: Aunque `gather_facts` está habilitado por defecto en Ansible, declararlo explícitamente en cada play es una buena práctica de legibilidad — deja claro que el play depende de los facts del sistema.

---

## 📚 Referencias

- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — Plantillas Jinja2](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Docs — Variables especiales (`groups`, `hostvars`)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Ansible Docs — `defaults` vs `vars` en roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Ansible Docs — Módulo `user`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/user_module.html)
- [Ansible Docs — Módulo `authorized_key`](https://docs.ansible.com/ansible/latest/collections/ansible/posix/authorized_key_module.html)
- [Ansible Docs — Módulo `mysql_db`](https://docs.ansible.com/ansible/latest/collections/community/mysql/mysql_db_module.html)
- [Jinja2 Docs — Filtros built-in](https://jinja.palletsprojects.com/en/3.1.x/templates/#builtin-filters)
