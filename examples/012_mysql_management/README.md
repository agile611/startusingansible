# 🗄️ Ejemplo 012 — Gestión de MySQL con módulos nativos de Ansible

## 🧭 Descripción general

Este ejemplo introduce los módulos nativos de Ansible para gestionar bases de datos MySQL directamente desde los playbooks: `mysql_db` y `mysql_user`. En lugar de ejecutar comandos SQL manualmente o usar scripts externos, Ansible puede **crear bases de datos, usuarios y asignar permisos** de forma declarativa e idempotente.

Además, este ejemplo incorpora una carpeta `playbook/` con utilidades operacionales reutilizables: un playbook para **limpiar la base de datos**, otro para **reiniciar el stack completo en orden seguro**, y uno para **consultar el hostname** de todos los nodos.

La novedad principal respecto al ejemplo anterior (`011_lineinfile`) está en `database.yml`: se añade `python3-mysqldb` como dependencia y se crean la base de datos `demo` y el usuario `demo` con permisos completos usando los módulos `mysql_db` y `mysql_user`.

---

## 🗂️ Estructura del proyecto

```
012_mysql_management/
├── hosts                          # Inventario de máquinas
├── control.yml                    # Playbook para el nodo de control
├── database.yml                   # Playbook para el servidor de base de datos ⭐ MODIFICADO
├── loadbalancer.yml               # Playbook para el balanceador de carga
├── webserver.yml                  # Playbook para el servidor web
├── templates/
│   └── nginx.conf.j2              # Plantilla Jinja2 para configurar Nginx (igual que 010/011)
├── demo/
│   ├── app/                       # Código fuente de la aplicación Python/Flask
│   └── demo.conf                  # Configuración VirtualHost de Apache
└── playbook/                      # ⭐ NUEVO — Utilidades operacionales
    ├── clean-database.yml         # Elimina la base de datos y usuario demo
    ├── stack_restart.yml          # Reinicia todos los servicios del stack en orden seguro
    └── hostname.yml               # Consulta el hostname de todos los nodos
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

## ⭐ La novedad principal: `database.yml` con `mysql_db` y `mysql_user`

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install tools
      apt: name={{item}} state=present update_cache=yes
      with_items:
        - python3-mysqldb
        - mysql-server

    - name: ensure mysql started
      service: name=mysql state=started enabled=yes

    - name: ensure mysql listening on all ports
      lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"

    - name: create demo database
      mysql_db: name=demo state=present

    - name: create demo user
      mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present
```

### Desglose tarea por tarea

#### 1️⃣ Instalar dependencias — módulo `apt` con `with_items`

```yaml
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb
    - mysql-server
```

Instala dos paquetes en una sola tarea usando el bucle `with_items`:

| **Paquete** | **Descripción** |
|---|---|
| `python3-mysqldb` | Librería Python para conectarse a MySQL. **Imprescindible** para que los módulos `mysql_db` y `mysql_user` de Ansible funcionen, ya que los usa internamente para comunicarse con el servidor MySQL |
| `mysql-server` | El servidor de base de datos MySQL |

> 🔑 **Punto crítico**: Sin `python3-mysqldb` instalado en el nodo remoto, los módulos `mysql_db` y `mysql_user` fallarían con un error de dependencia. Esta librería es el puente entre Ansible y MySQL.

#### 2️⃣ Arrancar MySQL — módulo `service`

```yaml
- name: ensure mysql started
  service: name=mysql state=started enabled=yes
```

Garantiza que el servicio MySQL está corriendo y habilitado para arrancar automáticamente con el sistema.

#### 3️⃣ Abrir MySQL a conexiones remotas — módulo `lineinfile`

```yaml
- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
```

Modifica `/etc/mysql/my.cnf` para que MySQL escuche en todas las interfaces de red (`0.0.0.0`) en lugar de solo en `localhost` (`127.0.0.1`). Heredado del ejemplo `011_lineinfile`.

#### 4️⃣ ⭐ Crear la base de datos — módulo `mysql_db`

```yaml
- name: create demo database
  mysql_db: name=demo state=present
```

Crea la base de datos `demo` en MySQL si no existe. Es **idempotente**: si la base de datos ya existe, no hace nada ni reporta error.

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `name` | `demo` | Nombre de la base de datos a crear |
| `state` | `present` | Garantiza que la base de datos existe (`absent` la eliminaría) |

#### 5️⃣ ⭐ Crear el usuario de base de datos — módulo `mysql_user`

```yaml
- name: create demo user
  mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present
```

Crea el usuario `demo` en MySQL con permisos completos sobre la base de datos `demo`, accesible desde cualquier host.

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `name` | `demo` | Nombre del usuario MySQL a crear |
| `password` | `demo` | Contraseña del usuario |
| `priv` | `demo.*:ALL` | Permisos: `ALL` sobre todas las tablas (`*`) de la base de datos `demo` |
| `host` | `'%'` | Permite conexiones desde **cualquier host** (no solo localhost) |
| `state` | `present` | Garantiza que el usuario existe (`absent` lo eliminaría) |

La sintaxis `priv=demo.*:ALL` se traduce al SQL equivalente:
```sql
GRANT ALL PRIVILEGES ON demo.* TO 'demo'@'%' IDENTIFIED BY 'demo';
```

> ⚠️ En un entorno de producción, `password=demo` y `host='%'` serían configuraciones inseguras. Para producción se usarían contraseñas fuertes gestionadas con Ansible Vault y hosts específicos en lugar de `%`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
```

---

## ⭐ Carpeta `playbook/` — Utilidades operacionales

Esta es la otra gran novedad del ejemplo: una colección de playbooks auxiliares para operar el stack una vez desplegado.

---

### 🧹 `playbook/clean-database.yml` — Limpiar base de datos y usuario

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: create demo database
      mysql_db: name=demo state=absent

    - name: create demo user
      mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=absent
```

El espejo exacto de las tareas de creación en `database.yml`, pero con `state=absent` en ambas tareas. Elimina la base de datos `demo` y el usuario `demo` de MySQL.

| **Tarea** | **Módulo** | **`state`** | **Efecto** |
|---|---|---|---|
| Eliminar base de datos | `mysql_db` | `absent` | Borra la base de datos `demo` y todos sus datos |
| Eliminar usuario | `mysql_user` | `absent` | Revoca todos los permisos y elimina el usuario `demo` |

> 💡 Este playbook ilustra perfectamente la **dualidad `present`/`absent`** de los módulos de Ansible: el mismo módulo que crea un recurso puede eliminarlo simplemente cambiando el valor de `state`.

#### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/clean-database.yml
```

---

### 🔄 `playbook/stack_restart.yml` — Reinicio ordenado del stack

```yaml
---
# Bring stack down
- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=stopped

- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=stopped

# Restart mysql
- hosts: database
  become: true
  tasks:
    - service: name=mysql state=restarted

# Bring stack up
- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=started

- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=started
```

Este playbook **orquesta el reinicio completo del stack en un orden seguro**, con múltiples plays dentro de un mismo fichero YAML. El orden es crítico para evitar errores de conexión durante el reinicio.

#### Secuencia de operaciones

```
1. PARAR    loadbalancer  → nginx stopped       (deja de aceptar tráfico externo)
2. PARAR    webserver     → apache2 stopped     (para la capa de aplicación)
3. REINICIAR database     → mysql restarted     (reinicia la base de datos sin tráfico activo)
4. ARRANCAR webserver     → apache2 started     (levanta la capa de aplicación)
5. ARRANCAR loadbalancer  → nginx started       (vuelve a aceptar tráfico externo)
```

**¿Por qué este orden?**

- Se para primero el **loadbalancer** para que no lleguen nuevas peticiones mientras se reinicia.
- Se para el **webserver** antes de reiniciar MySQL para evitar errores de conexión a la base de datos.
- Se reinicia **MySQL** con el stack de aplicación parado.
- Se levanta el stack en orden inverso: primero la aplicación, luego el balanceador.

> 📝 El comentario `# Restart mysql - commented problem with the VMs` en el código original indica que en el entorno Vagrant puede haber problemas al reiniciar MySQL, pero la lógica de orquestación es correcta.

#### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/stack_restart.yml
```

---

### 🔎 `playbook/hostname.yml` — Consultar hostname de todos los nodos

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

Un playbook de diagnóstico que ejecuta el comando `hostname` en **todos los nodos del inventario** (`hosts: all`) y muestra el resultado. Útil para verificar que Ansible puede conectarse a todos los nodos y para confirmar los nombres de host configurados.

> 💡 `hosts: all` es un grupo especial de Ansible que incluye automáticamente **todos los hosts definidos en el inventario**, independientemente del grupo al que pertenezcan.

#### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/hostname.yml
```

---

## 📜 Playbook `loadbalancer.yml` — Sin cambios respecto a 011

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

Instala Nginx, despliega la configuración de proxy inverso generada desde la plantilla `nginx.conf.j2` y gestiona los enlaces simbólicos de `sites-enabled`. Idéntico al ejemplo `011_lineinfile`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

---

## 📜 Playbook `webserver.yml` — Sin cambios respecto a 011

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

Instala Apache2 + mod_wsgi, despliega la aplicación Flask en `/var/www/demo`, configura el VirtualHost y gestiona los enlaces simbólicos. Idéntico al ejemplo `011_lineinfile`.

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

# 2. Desplegar la base de datos con usuario y permisos
ansible-playbook -i hosts -u vagrant database.yml

# 3. Desplegar el servidor web con la aplicación
ansible-playbook -i hosts -u vagrant webserver.yml

# 4. Desplegar el balanceador de carga
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

### Comandos de operación del stack (una vez desplegado)

```bash
# Verificar conectividad y hostnames de todos los nodos
ansible-playbook -i hosts -u vagrant playbook/hostname.yml

# Reiniciar todos los servicios del stack en orden seguro
ansible-playbook -i hosts -u vagrant playbook/stack_restart.yml

# Limpiar la base de datos y el usuario demo
ansible-playbook -i hosts -u vagrant playbook/clean-database.yml
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
      ▼ :3306 (bind-address = 0.0.0.0)
192.168.11.20 [database]
  MySQL Server
  └── DB: demo  /  User: demo@% (ALL PRIVILEGES)
```

---

## 🔍 Comparativa de módulos de gestión de MySQL

| **Módulo** | **Función** | **Parámetros clave** | **Idempotente** |
|---|---|---|---|
| `mysql_db` | Crear / eliminar bases de datos | `name`, `state` | ✅ Sí |
| `mysql_user` | Crear / eliminar usuarios y permisos | `name`, `password`, `priv`, `host`, `state` | ✅ Sí |
| `lineinfile` | Modificar parámetros en `my.cnf` | `dest`, `regexp`, `line` | ✅ Sí |
| `command` | Ejecutar SQL o comandos arbitrarios | `cmd` | ❌ No por defecto |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `mysql_db`**: Gestiona bases de datos MySQL de forma declarativa. Con `state=present` las crea, con `state=absent` las elimina. Requiere `python3-mysqldb` instalado en el nodo remoto.
- **Módulo `mysql_user`**: Gestiona usuarios MySQL y sus permisos. La sintaxis `priv=db.*:ALL` es equivalente a `GRANT ALL PRIVILEGES ON db.*`. El parámetro `host='%'` permite conexiones desde cualquier IP.
- **`python3-mysqldb`**: Librería Python que actúa como conector entre Ansible y MySQL. Sin ella, los módulos `mysql_db` y `mysql_user` no pueden funcionar.
- **Dualidad `present`/`absent`**: El mismo módulo puede crear o destruir un recurso simplemente cambiando el valor de `state`. Esto permite tener playbooks de "setup" y "cleanup" con código casi idéntico.
- **Múltiples plays en un fichero**: Un fichero YAML puede contener varios plays apuntando a grupos distintos (`loadbalancer`, `webserver`, `database`), ejecutándose secuencialmente. Esto permite orquestar operaciones multi-nodo en orden controlado, como en `stack_restart.yml`.
- **`hosts: all`**: Grupo especial de Ansible que incluye todos los hosts del inventario, útil para tareas de diagnóstico o configuración global.
- **Carpeta `playbook/`**: Convención para separar los playbooks de **despliegue inicial** (en la raíz) de los playbooks de **operación y mantenimiento** (en `playbook/`), mejorando la organización del proyecto.

---

## 📚 Referencias

- [Ansible Docs — community.mysql.mysql_db module](https://docs.ansible.com/ansible/latest/collections/community/mysql/mysql_db_module.html)
- [Ansible Docs — community.mysql.mysql_user module](https://docs.ansible.com/ansible/latest/collections/community/mysql/mysql_user_module.html)
- [Ansible Docs — ansible.builtin.service module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [Ansible Docs — Multiple plays in a playbook](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html#playbook-execution)
- [MySQL Docs — GRANT statement](https://dev.mysql.com/doc/refman/8.0/en/grant.html)
