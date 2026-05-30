# 🎭 Ejemplo 015_2 — Roles de Ansible: separación limpia de despliegue y verificación

## 🧭 Descripción general

Este ejemplo es una **refactorización y simplificación de 015_1_roles**. El stack desplegado es exactamente el mismo (MySQL + Apache2/Flask + Nginx), pero la organización del código evoluciona en dos aspectos clave:

1. **`site.yml` queda completamente limpio**: solo contiene la asignación de roles a hosts, sin ninguna tarea inline de verificación. El despliegue y la verificación son ahora responsabilidades completamente separadas.
2. **`stack_status.yml` vuelve a ser independiente y autónomo**: contiene toda la lógica de verificación del stack (nivel proceso + nivel red), sin estar mezclada con el despliegue.

El resultado es una arquitectura de playbooks más clara y mantenible: un fichero para desplegar, otro para verificar, y los roles encapsulan toda la lógica de configuración.

---

## 🗂️ Estructura del proyecto

```
015_2_roles/
├── hosts                          # Inventario de máquinas
├── site.yml                       # ⭐ Playbook de despliegue — SOLO roles, sin verificación
├── stack_status.yml               # Verificación standalone del stack (proceso + red)
└── roles/                         # Directorio de roles
    ├── mysql/                     # Rol para el servidor de base de datos
    │   ├── tasks/
    │   │   └── main.yml
    │   └── handlers/
    │       └── main.yml
    ├── nginx/                     # Rol para el balanceador de carga
    │   ├── tasks/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   └── templates/
    │       └── nginx.conf.j2
    ├── apache2/                   # Rol para el servidor web (infraestructura)
    │   ├── tasks/
    │   │   └── main.yml
    │   └── handlers/
    │       └── main.yml
    └── demo_app/                  # Rol para la aplicación Flask (despliegue)
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── files/
            └── demo/              # Código fuente de la app y configuración Apache
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

| **Grupo** | **IP** | **Rol asignado** |
|---|---|---|
| `[database]` | `192.168.11.20` | `mysql` |
| `[loadbalancer]` | `192.168.11.30` | `nginx` |
| `[webserver]` | `192.168.11.40` | `apache2` + `demo_app` |

---

## ⭐ El punto de entrada: `site.yml` — Despliegue puro

```yaml
---
- hosts: database
  become: true
  roles:
    - mysql

- hosts: loadbalancer
  become: true
  roles:
    - nginx

- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

### ¿Qué hace `site.yml`?

`site.yml` es el **playbook maestro de despliegue**. Su responsabilidad es única y clara: asignar roles a hosts. No contiene ninguna tarea inline, ninguna verificación, ningún `wait_for`, ningún `uri`. Solo declara **qué rol(es) se aplican a qué grupo de hosts**.

Esta es la diferencia más importante respecto a `015_1_roles`, donde `site.yml` incluía también toda la lógica de verificación end-to-end al final del fichero.

### Comparativa directa con 015_1

| **Aspecto** | **015_1 `site.yml`** | **015_2 `site.yml`** |
|---|---|---|
| Rol `control` | ✅ Incluido (instala `curl`, `python-httplib2`) | ❌ Eliminado |
| Roles de despliegue | `mysql`, `nginx`, `apache2`, `demo_app` | `mysql`, `nginx`, `apache2`, `demo_app` |
| Verificación inline | ✅ Bloques `wait_for`, `uri`, `fail` al final | ❌ Eliminada — vive en `stack_status.yml` |
| Líneas de código | ~80 líneas | ~16 líneas |
| Responsabilidad | Despliegue + verificación mezclados | Solo despliegue |

### Separación de responsabilidades en `webserver`

```yaml
- hosts: webserver
  become: true
  roles:
    - apache2      # Infraestructura: instala Apache, mod_wsgi, activa el servicio
    - demo_app     # Aplicación: despliega el código Flask, virtualenv, VirtualHost
```

El nodo webserver recibe **dos roles en secuencia**. `apache2` gestiona la infraestructura del servidor web y `demo_app` gestiona el despliegue de la aplicación. Esta separación permite reutilizar el rol `apache2` en otros proyectos sin arrastrar la lógica específica de `demo_app`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

---

## 🔍 `stack_status.yml` — Verificación standalone del stack

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: verify nginx service
      command: service nginx status

    - name: verify nginx is listening on 80
      wait_for: port=80 timeout=3

- hosts: webserver
  become: true
  tasks:
    - name: verify apache2 service
      command: service apache2 status

    - name: verify apache2 is listening on 80
      wait_for: port=80 timeout=3

- hosts: database
  become: true
  tasks:
    - name: verify mysql service
      command: service mysql status

    - name: verify mysql is listening on 3306
      wait_for: port=3306 timeout=3
```

### ¿Qué hace `stack_status.yml`?

Este playbook realiza una **verificación en dos niveles** para cada nodo del stack:

1. **Nivel proceso** (`command: service <servicio> status`): Comprueba que el proceso del servicio está activo en el sistema operativo.
2. **Nivel red** (`wait_for: port=<puerto> timeout=3`): Comprueba que el puerto está abierto y aceptando conexiones TCP.

| **Nodo** | **Servicio verificado** | **Puerto** | **`timeout`** |
|---|---|---|---|
| `loadbalancer` | nginx | 80 | 3 segundos |
| `webserver` | apache2 | 80 | 3 segundos |
| `database` | mysql | 3306 | 3 segundos |

### Diferencia con 015_1 `stack_status.yml`

En `015_1`, el fichero `stack_status.yml` incluía además pruebas HTTP end-to-end con `uri` y `fail` (verificación de contenido de respuesta). En `015_2`, esas pruebas han sido eliminadas de este fichero — la verificación es más simple y se centra solo en proceso y puerto.

> 💡 **¿Por qué `timeout=3` en lugar de `timeout=1`?** Un timeout de 3 segundos es más tolerante con entornos lentos o máquinas virtuales con recursos limitados, reduciendo falsos negativos en la verificación.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant stack_status.yml
```

---

## 🎭 Los Roles — Estructura y contenido

### Estructura estándar de un rol

```
roles/<nombre>/
├── tasks/
│   └── main.yml      # Lista de tareas del rol
├── handlers/
│   └── main.yml      # Handlers (acciones disparadas por notify)
├── templates/
│   └── *.j2          # Plantillas Jinja2
├── files/
│   └── ...           # Ficheros estáticos
├── vars/
│   └── main.yml      # Variables del rol (alta prioridad)
├── defaults/
│   └── main.yml      # Variables por defecto (sobreescribibles)
└── meta/
    └── main.yml      # Metadatos y dependencias entre roles
```

> 💡 **Resolución automática de rutas**: Dentro de un rol, el módulo `template` busca en `roles/<nombre>/templates/` y el módulo `copy` busca en `roles/<nombre>/files/` automáticamente, sin necesidad de especificar rutas absolutas.

---

### 🗄️ Rol `mysql` — Servidor de base de datos

```yaml
# roles/mysql/tasks/main.yml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: chmod cnf
  command: chmod 777 /etc/mysql/my.cnf

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

#### Flujo de ejecución del rol `mysql`

1. Instala `python3-mysqldb` — librería Python necesaria para que Ansible gestione MySQL con los módulos `mysql_db` y `mysql_user`.
2. Instala el servidor MySQL.
3. Da permisos de escritura a `/etc/mysql/my.cnf` con `chmod 777` para que `lineinfile` pueda modificarlo (workaround para entornos Vagrant).
4. Cambia `bind-address` a `0.0.0.0` para que MySQL acepte conexiones desde cualquier interfaz de red — necesario para que el webserver (`192.168.11.40`) pueda conectarse al database (`192.168.11.20`). Si este valor cambia, dispara el handler `restart mysql`.
5. Asegura que MySQL está arrancado y habilitado en el arranque del sistema.
6. Crea la base de datos `demo`.
7. Crea el usuario `demo` con contraseña `demo` y permisos totales sobre `demo.*` desde cualquier host (`host='%'`).

---

### ⚖️ Rol `nginx` — Balanceador de carga

```yaml
# roles/nginx/tasks/main.yml
---
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

#### Plantilla `nginx.conf.j2` — Bucle Jinja2 dinámico

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

En lugar de hardcodear la IP del webserver, la plantilla usa un **bucle Jinja2** que itera sobre el grupo `[webserver]` del inventario. Con el inventario actual genera:

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

Si el inventario tuviera múltiples webservers, Nginx los balancearía automáticamente en round-robin sin modificar ningún fichero manualmente.

| **Sintaxis Jinja2** | **Descripción** |
|---|---|
| `{% for server in groups.webserver %}` | Inicio del bucle — itera sobre las IPs del grupo `[webserver]` |
| `{{ server }}` | Imprime la IP del webserver en la iteración actual |
| `{% endfor %}` | Fin del bucle |
| `groups.webserver` | Variable mágica de Ansible con la lista de hosts del grupo `[webserver]` |

#### Flujo de ejecución del rol `nginx`

1. Instala Nginx.
2. Procesa la plantilla `nginx.conf.j2` y despliega el resultado en `/etc/nginx/sites-available/demo`. Si el contenido cambia, dispara `restart nginx`.
3. Elimina el enlace simbólico del site por defecto de Nginx para que no interfiera.
4. Crea un enlace simbólico `sites-available/demo` → `sites-enabled/demo` para activar la configuración.
5. Asegura que Nginx está arrancado y habilitado en el arranque.

---

### 🌐 Rol `apache2` — Servidor web (infraestructura)

```yaml
# roles/apache2/tasks/main.yml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3
    - python-pip-whl
    - python3-virtualenv
    - python3-mysqldb

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

#### Flujo de ejecución del rol `apache2`

1. Instala Apache2 y todas sus dependencias para servir aplicaciones Python/WSGI con acceso a MySQL.
2. Activa el módulo `mod_wsgi` para que Apache pueda ejecutar aplicaciones Python. Si cambia, dispara `restart apache2`.
3. Elimina el VirtualHost por defecto de Apache para evitar conflictos con el sitio de la demo.
4. Asegura que Apache está arrancado y habilitado en el arranque.

| **Paquete** | **Descripción** |
|---|---|
| `apache2` | Servidor web Apache |
| `libapache2-mod-wsgi-py3` | Módulo WSGI para Python 3 — permite a Apache ejecutar apps Flask |
| `python-pip-whl` | Soporte para instalación de paquetes Python con pip |
| `python3-virtualenv` | Entornos virtuales Python aislados |
| `python3-mysqldb` | Conector MySQL para Python 3 |

---

### 🚀 Rol `demo_app` — Aplicación Flask (despliegue)

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
  copy: src=files/demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=files/demo/demo.conf dest=/etc/apache2/sites-available mode=0755
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

#### Flujo de ejecución del rol `demo_app`

1. Instala las dependencias Python necesarias para la aplicación.
2. Copia el código fuente de la aplicación Flask desde `roles/demo_app/files/demo/app/` al directorio `/var/www/demo` del servidor. Si cambia, dispara `restart apache2`.
3. Copia el fichero de configuración del VirtualHost de Apache (`demo.conf`) a `/etc/apache2/sites-available/`. Si cambia, dispara el handler.
4. Crea un entorno virtual Python en `/var/www/demo/.venv` e instala las dependencias de `requirements.txt` con pip. Si cambia, dispara el handler.
5. Activa el VirtualHost creando un enlace simbólico en `sites-enabled/`.

---

## 🔄 Flujo completo de despliegue y operación

### Despliegue completo del stack

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

Despliega todos los nodos en orden: primero MySQL, luego Nginx, luego Apache2 + demo_app.

### Verificación del stack (sin redesplegar)

```bash
ansible-playbook -i hosts -u vagrant stack_status.yml
```

Comprueba que todos los servicios están activos y sus puertos abiertos.

---

## 🏗️ Evolución entre ejemplos: 013 → 014 → 015_1 → 015_2

| **Aspecto** | **013** | **014** | **015_1** | **015_2** |
|---|---|---|---|---|
| Organización | Playbooks monolíticos por servidor | Playbooks monolíticos + `stack_status.yml` | Roles + `site.yml` con verificación inline | Roles + `site.yml` limpio |
| Punto de entrada | Múltiples ficheros | Múltiples ficheros | `site.yml` (despliegue + verificación) | `site.yml` (solo despliegue) |
| Verificación | `wait_for` en `stack_status.yml` | `uri` + `fail` en `stack_status.yml` | Inline en `site.yml` (uri + fail) | `wait_for` en `stack_status.yml` separado |
| Separación de responsabilidades | ❌ | Parcial | Parcial | ✅ Completa |
| Reutilización de código | ❌ | ❌ | ✅ Roles | ✅ Roles |
| Escalado horizontal | IP hardcodeada | IP hardcodeada | Bucle Jinja2 en plantilla | Bucle Jinja2 en plantilla |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Separación de responsabilidades**: `site.yml` solo despliega. `stack_status.yml` solo verifica. Cada fichero tiene una única responsabilidad clara — principio fundamental de mantenibilidad.
- **`site.yml` como playbook maestro mínimo**: El patrón ideal es que `site.yml` sea lo más declarativo y conciso posible, delegando toda la lógica a los roles.
- **Roles autocontenidos**: Cada rol encapsula todo lo necesario para su función (tareas, handlers, plantillas, ficheros). Son portables y reutilizables en cualquier proyecto.
- **Múltiples roles por nodo**: Un mismo host puede recibir varios roles en secuencia (`apache2` + `demo_app`), separando infraestructura de aplicación.
- **Bucle Jinja2 `{% for %}`**: La plantilla `nginx.conf.j2` genera dinámicamente los servidores upstream leyendo el inventario, haciendo el stack escalable horizontalmente sin tocar código.
- **`wait_for` como verificación de red**: Confirma que un puerto está abierto y aceptando conexiones TCP. Es la prueba mínima necesaria para saber que un servicio está operativo a nivel de red.
- **`become: true` a nivel de play**: Aplicar `become: true` en el play (no en cada tarea individual) hace que todas las tareas del play se ejecuten con privilegios de superusuario, simplificando el código.

---

## 📚 Referencias

- [Ansible Docs — Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Docs — ansible.builtin.template module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — ansible.builtin.wait_for module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
- [Jinja2 — Template Designer Documentation (for loops)](https://jinja.palletsprojects.com/en/3.1.x/templates/#for)
- [Ansible Docs — ansible.builtin.service module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
