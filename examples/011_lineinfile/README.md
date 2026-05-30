# ✏️ Ejemplo 011 — Edición de líneas en ficheros de configuración con `lineinfile`

## 🧭 Descripción general

Este ejemplo introduce el módulo `lineinfile`, que permite **buscar y reemplazar (o insertar) líneas concretas dentro de un fichero de texto** en el nodo remoto, sin necesidad de sobrescribir el fichero completo ni usar una plantilla. Es el módulo ideal para modificar parámetros puntuales en ficheros de configuración del sistema.

La novedad principal respecto al ejemplo anterior (`010_templates`) está en `database.yml`: se añaden dos tareas nuevas — una limpieza previa de MySQL con el módulo `command`, y la configuración de MySQL para **escuchar en todas las interfaces de red** usando `lineinfile`.

> 📝 **Nota**: El nombre del directorio en el repositorio aparece como `011_lineinline` pero el módulo correcto de Ansible es `lineinfile`. Es un typo en el nombre de la carpeta.

---

## 🗂️ Estructura del proyecto

```
011_lineinfile/
├── hosts                        # Inventario de máquinas
├── control.yml                  # Playbook para el nodo de control
├── database.yml                 # Playbook para el servidor de base de datos ⭐ MODIFICADO
├── loadbalancer.yml             # Playbook para el balanceador de carga
├── webserver.yml                # Playbook para el servidor web
├── templates/
│   └── nginx.conf.j2            # Plantilla Jinja2 para configurar Nginx (igual que 010)
└── demo/
    ├── app/                     # Código fuente de la aplicación Python/Flask
    └── demo.conf                # Configuración VirtualHost de Apache
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

### ¿Qué define este inventario?

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Fuerza el uso de Python 3 en los nodos remotos |
| `ansible_user` | `vagrant` | Usuario SSH con el que Ansible se conecta |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación de host SSH (útil en laboratorio) |

Los tres grupos definen máquinas con roles diferenciados:
- **`[database]`** → `192.168.11.20` — Servidor de base de datos (MySQL)
- **`[loadbalancer]`** → `192.168.11.30` — Balanceador de carga (Nginx)
- **`[webserver]`** → `192.168.11.40` — Servidor web (Apache2 + WSGI + Flask)

---

## ⭐ La novedad principal: `database.yml` con `lineinfile`

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: Remove packages for a VM problem using mysql
      command: apt-get -y purge mysql-server mysql-client mysql-common

    - name: install mysql-server
      apt: name=mysql-server state=present update_cache=yes

    - name: ensure mysql started
      service: name=mysql state=started enabled=yes

    - name: ensure mysql listening on all ports
      lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
```

### Desglose tarea por tarea

#### 1️⃣ Limpiar instalación previa de MySQL — módulo `command`

```yaml
- name: Remove packages for a VM problem using mysql
  command: apt-get -y purge mysql-server mysql-client mysql-common
```

Ejecuta directamente el comando `apt-get purge` para **desinstalar completamente** cualquier versión previa de MySQL (incluyendo ficheros de configuración). Esto resuelve un problema conocido en entornos Vagrant donde una instalación corrupta o incompleta de MySQL puede impedir una reinstalación limpia.

- El módulo `command` ejecuta comandos de shell **sin pasar por `/bin/sh`**, por lo que no interpreta pipes ni redirecciones.
- `-y` → Confirma automáticamente la desinstalación sin pedir confirmación interactiva.
- `purge` → Elimina tanto los binarios como los ficheros de configuración (más agresivo que `remove`).

> ⚠️ El módulo `command` **no es idempotente** por defecto: se ejecuta siempre, aunque MySQL no esté instalado. En producción se combinaría con `when:` o se usaría el módulo `apt` con `state=absent` para mayor control.

#### 2️⃣ Instalar MySQL — módulo `apt`

```yaml
- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes
```

Instala `mysql-server` desde los repositorios APT, actualizando la caché antes de instalar. Tras la purga anterior, garantiza una instalación limpia y fresca.

#### 3️⃣ Arrancar MySQL — módulo `service`

```yaml
- name: ensure mysql started
  service: name=mysql state=started enabled=yes
```

Garantiza que el servicio MySQL está corriendo y habilitado para arrancar automáticamente con el sistema.

#### 4️⃣ ⭐ Configurar MySQL para escuchar en todas las interfaces — módulo `lineinfile`

```yaml
- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
```

Esta es la tarea central del ejemplo. Usa `lineinfile` para modificar una línea específica dentro del fichero `/etc/mysql/my.cnf`.

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `dest` | `/etc/mysql/my.cnf` | Fichero de configuración de MySQL a modificar |
| `regexp` | `^bind-address` | Expresión regular que identifica la línea a buscar (líneas que empiezan por `bind-address`) |
| `line` | `bind-address = 0.0.0.0` | Contenido exacto con el que se reemplaza la línea encontrada |

**¿Qué hace exactamente?**

Busca en `/etc/mysql/my.cnf` la línea que comienza por `bind-address` y la reemplaza por `bind-address = 0.0.0.0`.

Antes (configuración por defecto de MySQL):
```ini
bind-address = 127.0.0.1
```

Después (tras ejecutar `lineinfile`):
```ini
bind-address = 0.0.0.0
```

**¿Por qué es importante este cambio?**

Por defecto, MySQL solo acepta conexiones desde `localhost` (`127.0.0.1`). Al cambiar `bind-address` a `0.0.0.0`, MySQL pasa a **escuchar en todas las interfaces de red**, permitiendo que otros nodos del stack (como el servidor web en `192.168.11.40`) se conecten a la base de datos remotamente.

**`lineinfile` es idempotente**: si la línea ya tiene el valor `bind-address = 0.0.0.0`, no modifica el fichero ni reporta cambios.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
```

---

## 📜 Playbook `loadbalancer.yml` — Sin cambios respecto a 010

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: install nginx
      apt: name=nginx state=present update_cache=yes

    - name: ensure nginx started
      service: name=nginx state=started enabled=yes

    - name: configure nginx site
      template: src=templates/nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
      notify: restart nginx

    - name: de-activate default nginx site
      file: path=/etc/nginx/sites-enabled/default state=absent
      notify: restart nginx

    - name: activate demo nginx site
      file: src=/etc/nginx/sites-available/demo dest=/etc/nginx/sites-enabled/demo state=link
      notify: restart nginx

  handlers:
    - name: restart nginx
      service: name=nginx state=restarted
```

Instala Nginx, despliega la configuración de proxy inverso generada desde la plantilla `nginx.conf.j2` y gestiona los enlaces simbólicos de `sites-enabled`. Idéntico al ejemplo `010_templates`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

---

## 📜 Playbook `webserver.yml` — Sin cambios respecto a 010

```yaml
---
- hosts: webserver
  become: true
  tasks:
    - name: install web components
      apt: name={{item}} state=present update_cache=yes
      with_items:
        - apache2
        - libapache2-mod-wsgi-py3
        - python-pip-whl
        - python3-virtualenv

    - name: ensure apache2 started
      service: name=apache2 state=started enabled=yes

    - name: ensure mod_wsgi enabled
      apache2_module: state=present name=wsgi
      notify: restart apache2

    - name: copy demo app source
      copy: src=demo/app/ dest=/var/www/demo mode=0755
      notify: restart apache2

    - name: copy apache virtual host config
      copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
      notify: restart apache2

    - name: setup python virtualenv
      pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
      notify: restart apache2

    - name: de-activate default apache site
      file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
      notify: restart apache2

    - name: activate demo apache site
      file: src=/etc/apache2/sites-available/demo.conf dest=/etc/apache2/sites-enabled/demo.conf state=link
      notify: restart apache2

  handlers:
    - name: restart apache2
      service: name=apache2 state=restarted
```

Instala Apache2 + mod_wsgi, despliega la aplicación Flask en `/var/www/demo`, configura el VirtualHost y gestiona los enlaces simbólicos. Idéntico al ejemplo `010_templates`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## 📜 Playbook `control.yml` — Sin cambios

```yaml
---
- hosts: control
  become: true
  tasks:
    - name: install tools
      apt: name={{item}} state=present update_cache=yes
      with_items:
        - curl
```

Instala herramientas básicas (`curl`) en el nodo de control.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant control.yml
```

---

## 🔄 Flujo completo de despliegue del stack

```bash
# 1. Preparar el nodo de control
ansible-playbook -i hosts -u vagrant control.yml

# 2. Desplegar la base de datos (con lineinfile para abrir acceso remoto)
ansible-playbook -i hosts -u vagrant database.yml

# 3. Desplegar el servidor web con la aplicación
ansible-playbook -i hosts -u vagrant webserver.yml

# 4. Desplegar el balanceador de carga
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

### Diagrama de la arquitectura desplegada

```
[Cliente HTTP]
      │
      ▼ :80
192.168.11.30 [loadbalancer]
  Nginx — proxy_pass → upstream demo
      │
      ▼
192.168.11.40 [webserver]
  Apache2 + mod_wsgi
  └── /var/www/demo (.venv Flask app)
      │
      ▼ :3306 (bind-address = 0.0.0.0 ← lineinfile)
192.168.11.20 [database]
  MySQL Server (accesible remotamente)
```

---

## 🔍 ¿Cuándo usar `lineinfile` vs otras alternativas?

| **Situación** | **Módulo recomendado** |
|---|---|
| Modificar una línea concreta en un fichero existente | `lineinfile` ✅ |
| Generar un fichero de configuración completo dinámicamente | `template` |
| Copiar un fichero estático sin cambios | `copy` |
| Insertar un bloque de varias líneas | `blockinfile` |
| Modificar ficheros XML/JSON estructurados | `xml` / `json_patch` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `lineinfile`**: Busca una línea en un fichero mediante una expresión regular (`regexp`) y la reemplaza por el valor de `line`. Si no la encuentra, la añade al final. Es **idempotente** por diseño.
- **`regexp` con ancla `^`**: El patrón `^bind-address` busca líneas que **empiezan** por `bind-address`, evitando falsos positivos en comentarios o líneas similares.
- **`bind-address = 0.0.0.0`**: Configuración de MySQL para aceptar conexiones desde cualquier IP, necesaria en arquitecturas multi-nodo donde la base de datos está en un servidor separado.
- **Módulo `command`**: Ejecuta comandos arbitrarios en el nodo remoto. Útil para operaciones sin módulo Ansible equivalente, pero sacrifica idempotencia.
- **`apt-get purge`**: Elimina paquetes y sus ficheros de configuración, garantizando una instalación limpia en entornos de laboratorio con Vagrant.

---

## 📚 Referencias

- [Ansible Docs — ansible.builtin.lineinfile module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html)
- [Ansible Docs — ansible.builtin.command module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)
- [Ansible Docs — ansible.builtin.blockinfile module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/blockinfile_module.html)
- [MySQL Docs — bind-address configuration](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_bind_address)
