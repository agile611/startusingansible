# 🧩 Ejemplo 010 — Plantillas Jinja2 con Ansible (`template` module)

## 🧭 Descripción general

Este ejemplo introduce el concepto más potente de Ansible para la gestión de configuraciones: **las plantillas Jinja2**. A diferencia del módulo `copy` (que transfiere ficheros estáticos), el módulo `template` permite generar ficheros de configuración **dinámicamente**, interpolando variables e iterando sobre el inventario en tiempo de ejecución.

La novedad principal respecto al ejemplo anterior (`009_files`) es la incorporación de la carpeta `templates/` con el fichero `nginx.conf.j2`, que genera automáticamente la configuración de Nginx como balanceador de carga apuntando a **todos los servidores web definidos en el inventario**.

---

## 🗂️ Estructura del proyecto

```
010_templates/
├── hosts                        # Inventario de máquinas
├── control.yml                  # Playbook para el nodo de control
├── database.yml                 # Playbook para el servidor de base de datos
├── loadbalancer.yml             # Playbook para el balanceador de carga ⭐ MODIFICADO
├── webserver.yml                # Playbook para el servidor web
├── templates/
│   └── nginx.conf.j2            # Plantilla Jinja2 para configurar Nginx ⭐ NUEVO
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

> ⚠️ `StrictHostKeyChecking=no` es práctico en laboratorios con Vagrant, pero **no se recomienda en producción** por razones de seguridad.

---

## ⭐ La novedad principal: plantilla `templates/nginx.conf.j2`

Este es el fichero central y la razón de ser del ejemplo. Es una **plantilla Jinja2** que Ansible procesa antes de copiarla al nodo remoto.

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

### ¿Qué hace esta plantilla?

Genera dinámicamente la configuración de Nginx como **proxy inverso y balanceador de carga**. Vamos línea por línea:

#### Bloque `upstream demo { ... }`
Define un grupo de servidores backend llamado `demo` al que Nginx distribuirá el tráfico.

```jinja2
{% for server in groups.webserver %}
    server {{ server }};
{% endfor %}
```

- `groups.webserver` → Variable mágica de Ansible que contiene la **lista de todos los hosts del grupo `[webserver]`** definidos en el inventario.
- El bucle `{% for ... %}` itera sobre cada IP del grupo y genera una línea `server <IP>;` por cada una.
- `{{ server }}` → Sintaxis Jinja2 para **interpolar** el valor de la variable.

Con el inventario actual (un solo webserver en `192.168.11.40`), el fichero generado en el nodo remoto sería:

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

> 💡 **La potencia real**: si añadieras más IPs al grupo `[webserver]` en el fichero `hosts`, la configuración de Nginx se generaría automáticamente con todos ellos, sin tocar la plantilla. Ansible escala el balanceo de carga **sin cambiar ni una línea de código**.

#### Bloque `server { listen 80; ... }`
Define el servidor virtual de Nginx que:
- Escucha en el puerto `80` (HTTP)
- Redirige todo el tráfico (`location /`) al grupo `upstream demo` mediante `proxy_pass`

---

## 📜 Playbook `loadbalancer.yml` ⭐ — El más modificado

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

### Desglose tarea por tarea

| **Tarea** | **Módulo** | **Descripción** |
|---|---|---|
| Instalar Nginx | `apt` | Instala `nginx` actualizando la caché APT |
| Arrancar Nginx | `service` | Inicia el servicio y lo habilita en el arranque |
| Configurar sitio Nginx | `template` ⭐ | Procesa `nginx.conf.j2` y lo despliega en `sites-available/demo` |
| Desactivar sitio por defecto | `file` (absent) | Elimina el enlace simbólico `sites-enabled/default` |
| Activar sitio demo | `file` (link) | Crea enlace simbólico `sites-enabled/demo → sites-available/demo` |

#### La tarea clave: módulo `template`

```yaml
- name: configure nginx site
  template: src=templates/nginx.conf.j2 dest=/etc/nginx/sites-available/demo mode=0644
  notify: restart nginx
```

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `src` | `templates/nginx.conf.j2` | Ruta local a la plantilla Jinja2 (en la máquina de control) |
| `dest` | `/etc/nginx/sites-available/demo` | Ruta destino en el nodo remoto (fichero ya renderizado) |
| `mode` | `0644` | Permisos del fichero resultante |

> 🔑 **Diferencia clave entre `copy` y `template`**:
> - `copy` → transfiere el fichero **tal cual**, sin procesar.
> - `template` → **renderiza primero** la plantilla Jinja2 sustituyendo variables y ejecutando bucles, y luego transfiere el resultado.

#### Handler: restart nginx
Se ejecuta **una sola vez al final** del play si cualquiera de las tareas notificó un cambio, reiniciando Nginx para aplicar la nueva configuración.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

---

## 📜 Playbook `webserver.yml` — Sin cambios respecto a 009

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

Instala Apache2 + mod_wsgi, despliega la aplicación Flask en `/var/www/demo`, configura el VirtualHost y gestiona los enlaces simbólicos de `sites-enabled`. Idéntico al ejemplo `009_files`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## 📜 Playbook `database.yml` — Sin cambios

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

Instala MySQL y garantiza que el servicio está arrancado y habilitado en el arranque.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
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

Para desplegar toda la infraestructura, se ejecutan los playbooks en orden:

```bash
# 1. Preparar el nodo de control
ansible-playbook -i hosts -u vagrant control.yml

# 2. Desplegar la base de datos
ansible-playbook -i hosts -u vagrant database.yml

# 3. Desplegar el servidor web con la aplicación
ansible-playbook -i hosts -u vagrant webserver.yml

# 4. Desplegar el balanceador de carga con la configuración dinámica
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
      │  (generado dinámicamente por nginx.conf.j2)
      ▼
192.168.11.40 [webserver]
  Apache2 + mod_wsgi
  └── /var/www/demo (.venv Flask app)
      │
      ▼
192.168.11.20 [database]
  MySQL Server
```

---

## 🔍 Comparativa: `copy` vs `template`

| **Característica** | **Módulo `copy`** | **Módulo `template`** |
|---|---|---|
| Tipo de fichero | Estático | Dinámico (Jinja2) |
| Interpola variables | ❌ No | ✅ Sí |
| Soporta bucles `for` | ❌ No | ✅ Sí |
| Soporta condicionales `if` | ❌ No | ✅ Sí |
| Acceso a `groups`, `hostvars` | ❌ No | ✅ Sí |
| Caso de uso | Ficheros de config fijos | Configs que dependen del inventario |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `template`**: Renderiza plantillas Jinja2 antes de copiarlas al nodo remoto, permitiendo configuraciones dinámicas basadas en el inventario.
- **Sintaxis Jinja2 en Ansible**:
  - `{{ variable }}` → Interpolación de variables
  - `{% for item in lista %}` → Bucles de iteración
  - `{% if condicion %}` → Condicionales
- **`groups.webserver`**: Variable mágica de Ansible que expone la lista de hosts de un grupo del inventario, accesible desde cualquier plantilla o playbook.
- **Escalabilidad automática**: Añadir más servidores al grupo `[webserver]` en `hosts` regenera automáticamente la configuración de Nginx en el siguiente `ansible-playbook`, sin modificar ningún otro fichero.
- **Carpeta `templates/`**: Convención estándar de Ansible para almacenar ficheros `.j2`. El módulo `template` busca en esta carpeta por defecto cuando se usan roles.
- **Handlers con `notify`**: Reinician Nginx una sola vez al final del play, aunque múltiples tareas hayan notificado cambios.

---

## 📚 Referencias

- [Ansible Docs — ansible.builtin.template module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Templating (Jinja2)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Docs — Magic Variables (groups, hostvars)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Jinja2 — Template Designer Documentation](https://jinja.palletsprojects.com/en/3.1.x/templates/)
- [Ansible Docs — Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
