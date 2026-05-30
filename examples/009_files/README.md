# 🗂️ Ejemplo 009 — Gestión de ficheros, servicios y despliegue de aplicación web con Ansible

## 🧭 Descripción general

Este ejemplo es uno de los más completos del repositorio. Muestra cómo usar Ansible para **desplegar una infraestructura completa de tres capas** (base de datos, balanceador de carga y servidor web) usando playbooks separados por rol, junto con la gestión de ficheros, módulos de servicio, virtualenvs Python y configuración de Apache con WSGI.

La estructura divide las responsabilidades en **cuatro playbooks independientes**, uno por cada tipo de nodo, más una carpeta `demo/` con el código de la aplicación y una carpeta `playbook/` con utilidades adicionales.

---

## 🗂️ Estructura del proyecto

```
009_files/
├── hosts                  # Inventario de máquinas
├── control.yml            # Playbook para el nodo de control
├── database.yml           # Playbook para el servidor de base de datos
├── loadbalancer.yml       # Playbook para el balanceador de carga
├── webserver.yml          # Playbook para el servidor web (el más completo)
├── demo/
│   ├── app/               # Código fuente de la aplicación Python/Flask
│   │   └── requirements.txt
│   └── demo.conf          # Configuración VirtualHost de Apache
└── playbook/
    ├── hostname.yml       # Utilidad: muestra el hostname de cada nodo
    └── stack_restart.yml  # Utilidad: reinicia todos los servicios del stack
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

> ⚠️ `StrictHostKeyChecking=no` es práctico en laboratorios con Vagrant, pero **no se recomienda en producción** por razones de seguridad.

---

## 📜 Playbook `control.yml` — Nodo de control

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

### ¿Qué hace?

Instala herramientas básicas de sistema en el nodo de control usando el módulo `apt`.

- **`become: true`** → Ejecuta con privilegios `sudo`
- **`with_items`** → Itera sobre una lista de paquetes (en este caso solo `curl`)
- **`update_cache: yes`** → Equivale a `apt update` antes de instalar
- **`state: present`** → Instala el paquete si no está ya presente (idempotente)

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant control.yml
```

---

## 📜 Playbook `database.yml` — Servidor de base de datos

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install mysql-server
      apt: name=mysql-server state=present update_cache=yes

    - name: ensure mysql started
      service: name=mysql state=started enabled=yes
```

### ¿Qué hace?

Instala y arranca MySQL en el nodo `192.168.11.20`.

| **Tarea** | **Módulo** | **Descripción** |
|---|---|---|
| Instalar MySQL | `apt` | Instala `mysql-server` actualizando la caché APT |
| Arrancar MySQL | `service` | Inicia el servicio y lo habilita para arranque automático |

- **`state: started`** → Garantiza que el servicio está corriendo
- **`enabled: yes`** → Lo registra en el arranque del sistema (`systemctl enable`)

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
```

---

## 📜 Playbook `loadbalancer.yml` — Balanceador de carga

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: install nginx
      apt: name=nginx state=present update_cache=yes

    - name: ensure nginx started
      service: name=nginx state=started enabled=yes
```

### ¿Qué hace?

Instala y arranca Nginx en el nodo `192.168.11.30`, que actuará como balanceador de carga o proxy inverso hacia los servidores web.

| **Tarea** | **Módulo** | **Descripción** |
|---|---|---|
| Instalar Nginx | `apt` | Instala `nginx` actualizando la caché APT |
| Arrancar Nginx | `service` | Inicia el servicio y lo habilita para arranque automático |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

---

## 📜 Playbook `webserver.yml` — Servidor web ⭐ (el más completo)

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

### ¿Qué hace? — Desglose tarea por tarea

#### 1️⃣ Instalar componentes web
Instala con `apt` los paquetes necesarios para servir una aplicación Python:
- `apache2` → Servidor web
- `libapache2-mod-wsgi-py3` → Módulo WSGI para Python 3 en Apache
- `python-pip-whl` → Soporte de wheels para pip
- `python3-virtualenv` → Herramienta para crear entornos virtuales Python

#### 2️⃣ Arrancar Apache2
Garantiza que Apache está corriendo y habilitado en el arranque del sistema.

#### 3️⃣ Activar módulo mod_wsgi
Usa el módulo `apache2_module` para habilitar `wsgi` en Apache.
Lanza el handler `restart apache2` si hay cambios.

#### 4️⃣ Copiar el código fuente de la app
Usa el módulo `copy` para transferir el directorio `demo/app/` desde la máquina de control al nodo remoto en `/var/www/demo` con permisos `0755`.
Lanza el handler `restart apache2` si hay cambios.

#### 5️⃣ Copiar la configuración de Apache (VirtualHost)
Copia `demo/demo.conf` a `/etc/apache2/sites-available/` para definir el VirtualHost de la aplicación.
Lanza el handler `restart apache2` si hay cambios.

#### 6️⃣ Instalar dependencias Python en virtualenv
Usa el módulo `pip` para instalar los paquetes listados en `requirements.txt` dentro del entorno virtual `/var/www/demo/.venv`.
Lanza el handler `restart apache2` si hay cambios.

#### 7️⃣ Desactivar el sitio Apache por defecto
Usa el módulo `file` con `state=absent` para **eliminar** el enlace simbólico del sitio por defecto de Apache (`000-default.conf`), dejando de servir la página de bienvenida de Apache.

#### 8️⃣ Activar el sitio de la demo
Usa el módulo `file` con `state=link` para **crear un enlace simbólico** desde `sites-available/demo.conf` hacia `sites-enabled/demo.conf`, activando así el VirtualHost de la aplicación.

#### 🔔 Handler: restart apache2
Se ejecuta **una sola vez al final** del play si cualquiera de las tareas anteriores notificó un cambio. Reinicia Apache para aplicar todas las configuraciones.

> 💡 Los handlers son el mecanismo de Ansible para evitar reinicios innecesarios: aunque 5 tareas notifiquen el mismo handler, Apache solo se reinicia **una vez** al final.

### Resumen de módulos usados en `webserver.yml`

| **Módulo** | **Uso en este playbook** |
|---|---|
| `apt` | Instalar paquetes del sistema |
| `service` | Arrancar y habilitar Apache2 |
| `apache2_module` | Activar módulo `wsgi` en Apache |
| `copy` | Copiar ficheros/directorios al nodo remoto |
| `pip` | Instalar dependencias Python en virtualenv |
| `file` | Eliminar ficheros y crear enlaces simbólicos |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## 🔄 Flujo completo de despliegue del stack

Para desplegar toda la infraestructura, se ejecutan los playbooks en orden:

```bash
# 1. Preparar el nodo de control
ansible-playbook -i hosts -u vagrant control.yml

# 2. Desplegar la base de datos
ansible-playbook -i hosts -u vagrant database.yml

# 3. Desplegar el balanceador de carga
ansible-playbook -i hosts -u vagrant loadbalancer.yml

# 4. Desplegar el servidor web con la aplicación
ansible-playbook -i hosts -u vagrant webserver.yml
```

### Diagrama de la arquitectura desplegada

```
[Máquina de control - Ansible]
        │
        ├──► 192.168.11.20 [database]      → MySQL Server
        │
        ├──► 192.168.11.30 [loadbalancer]  → Nginx (proxy/balanceador)
        │                                        │
        └──► 192.168.11.40 [webserver]     → Apache2 + mod_wsgi
                                                 └── /var/www/demo (.venv Flask app)
```

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Playbooks por rol**: Separar la lógica en ficheros independientes por tipo de servidor hace el código más mantenible y reutilizable.
- **Módulo `copy`**: Transfiere ficheros y directorios desde la máquina de control a los nodos remotos, con control de permisos.
- **Módulo `file`**: Gestiona la existencia de ficheros, directorios y **enlaces simbólicos** (`state=link`, `state=absent`, `state=directory`).
- **Módulo `apache2_module`**: Activa/desactiva módulos de Apache de forma idempotente (equivale a `a2enmod`/`a2dismod`).
- **Módulo `pip` con `virtualenv`**: Instala dependencias Python aisladas en un entorno virtual, sin contaminar el sistema.
- **Handlers con `notify`**: Permiten ejecutar acciones (como reiniciar un servicio) **una sola vez al final** del play, aunque múltiples tareas lo soliciten.
- **`with_items`**: Itera sobre una lista para aplicar la misma tarea a múltiples elementos (paquetes, usuarios, etc.).
- **`become: true`**: Escalada de privilegios necesaria para instalar paquetes y modificar configuraciones del sistema.

---

## 📚 Referencias

- [Ansible Docs — ansible.builtin.copy module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Ansible Docs — ansible.builtin.file module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html)
- [Ansible Docs — ansible.builtin.service module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [Ansible Docs — ansible.builtin.pip module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/pip_module.html)
- [Ansible Docs — community.general.apache2_module](https://docs.ansible.com/ansible/latest/collections/community/general/apache2_module_module.html)
- [Ansible Docs — Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
