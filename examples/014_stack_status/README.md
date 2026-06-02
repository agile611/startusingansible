# 🔍 Ejemplo 014 — Verificación end-to-end del stack con `uri` y `fail`

## 🧭 Descripción general

Este ejemplo introduce dos módulos nuevos de Ansible: `uri` y `fail`. Juntos permiten construir **pruebas de integración automatizadas** directamente desde los playbooks — Ansible hace peticiones HTTP reales al stack desplegado y verifica que las respuestas contienen el contenido esperado, fallando explícitamente si algo no funciona.

La novedad principal respecto al ejemplo anterior (`013_wait_for`) está en `playbooks/stack_status.yml`: además de verificar que los puertos están abiertos con `wait_for`, ahora se realizan **pruebas HTTP end-to-end** desde el nodo de control hacia el loadbalancer, y desde el loadbalancer hacia los webservers, comprobando tanto la ruta `/` (aplicación) como la ruta `/db` (conectividad con base de datos).

---

## 🗂️ Estructura del proyecto

```
014_stack_status/
├── hosts                          # Inventario de máquinas
├── site.yml                       # Orchestración completa del stack
├── control.yml                    # Playbook para el nodo de control
├── database.yml                   # Playbook para el servidor de base de datos
├── loadbalancer.yml               # Playbook para el balanceador de carga
├── webserver.yml                  # Playbook para el servidor web
├── templates/
│   └── nginx.conf.j2              # Plantilla Jinja2 para configurar Nginx
├── demo/
│   ├── app/                       # Código fuente de la aplicación Python/Flask
│   └── demo.conf                  # Configuración VirtualHost de Apache
└── playbooks/                     # Utilidades operacionales
    ├── hostname.yml               # Consulta el hostname de todos los nodos
    ├── stack_restart.yml          # Reinicia el stack con wait_for entre pasos
    └── stack_status.yml           # Verificación completa del stack
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

## 📜 `control.yml` — Herramientas de diagnóstico

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

Instala herramientas de diagnóstico en el nodo de control. El módulo `uri` usa la librería HTTP de Python estándar para realizar peticiones HTTP hacia el loadbalancer durante las pruebas end-to-end de `stack_status.yml`.

| **Paquete** | **Descripción** |
|---|---|
| `curl` | Herramienta de línea de comandos para peticiones HTTP |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant control.yml
```

---

## 📜 `loadbalancer.yml` — Nginx y configuración de balanceo

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

Instala Nginx, activa el sitio de demostración y configura los handlers para reiniciar el servicio cuando cambian los archivos de configuración. El nodo loadbalancer actúa como proxy reverso hacia los webservers.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

---

## 📜 `database.yml` — MySQL/MariaDB y base de datos

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install tools
      apt: name={{item}} state=present update_cache=yes
      with_items:
        - python3-mysqldb
        - default-mysql-server

    - name: ensure mysql started
      service: name=mysql state=started enabled=yes

    - name: ensure mysql listening on all ports
      lineinfile: dest=/etc/mysql/mariadb.conf.d/50-server.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
      notify: restart mysql

    - name: create demo database
      mysql_db: name=demo state=present

    - name: create demo user
      mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present

  handlers:
    - name: restart mysql
      service: name=mysql state=restarted
```

Instala MySQL/MariaDB (a través de `default-mysql-server`), lo configura para escuchar en todas las interfaces, crea la base de datos `demo` y el usuario `demo` con permisos completos. El handler reinicia MySQL automáticamente si `lineinfile` detecta un cambio en `bind-address`.

**Nota**: En sistemas Debian/Ubuntu modernos, la ruta de configuración es `/etc/mysql/mariadb.conf.d/50-server.cnf` en lugar de `/etc/mysql/my.cnf`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
```

---

## 📜 `webserver.yml` — Apache2 + WSGI + Flask

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
        - python3-pip-whl
        - python3-virtualenv
        - python3-mysqldb

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

Instala Apache2 con soporte WSGI, Flask mediante virtualenv, y conectividad a MySQL. Copia la aplicación de demostración y configura el sitio virtual.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## ⭐ La novedad principal: `playbooks/stack_status.yml` con `uri` y `fail`

```yaml
---
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

- hosts: control
  tasks:
    - name: verify end-to-end index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_index

    - name: fail if index failed to return content
      fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{lb_index.results}}"

    - name: verify end-to-end db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_db

    - name: fail if db failed to return content 
      fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{lb_db.results}}"

- hosts: loadbalancer
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_index

    - name: verify backend index response
      fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{app_index.results}}"

    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_db

    - name: verify backend db response
      fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{app_db.results}}"
```

Este playbook es el núcleo del ejemplo. Realiza una **verificación completa del stack en cinco fases**, combinando comprobaciones a nivel de proceso, de red y de contenido HTTP.

---

### Fase 1 — Verificación de servicios y puertos (nivel proceso + red)

Las tres primeras secciones son idénticas en estructura para cada nodo:

```yaml
- name: verify <servicio>
  command: service <servicio> status        # nivel proceso

- name: verify <servicio> is listening on <puerto>
  wait_for: port=<puerto> timeout=1         # nivel red
```

| **Nodo** | **Servicio** | **Puerto** | **`timeout`** |
|---|---|---|---|
| `loadbalancer` | nginx | 80 | 1 segundo |
| `webserver` | apache2 | 80 | 1 segundo |
| `database` | mysql | 3306 | 1 segundo |

> 💡 `timeout=1` es intencionalmente muy corto — es una verificación de diagnóstico rápido, no una espera de arranque. Si el servicio no responde en 1 segundo, el playbook falla inmediatamente.

---

### Fase 2 — Prueba HTTP end-to-end desde el nodo de control

```yaml
- hosts: control
  tasks:
    - name: verify end-to-end index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_index

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{lb_index.results}}"
```

#### Módulo `uri`

El módulo `uri` realiza una **petición HTTP real** desde el nodo donde se ejecuta hacia la URL especificada.

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `url` | `http://{{item}}` | URL destino — se itera sobre las IPs del grupo `loadbalancer` |
| `return_content` | `yes` | Incluye el cuerpo de la respuesta HTTP en el resultado |

`with_items: "{{ groups.loadbalancer }}"` itera sobre todas las IPs del grupo `[loadbalancer]` del inventario (en este caso, `192.168.11.30`), haciendo una petición a cada una.

`register: lb_index` guarda el resultado completo de cada petición HTTP (código de estado, cabeceras, cuerpo) en la variable `lb_index` para usarla en la tarea siguiente.

#### Módulo `fail`

```yaml
- fail: msg="index failed to return content"
  when: "'Hello, from sunny' not in item.content"
  with_items: "{{lb_index.results}}"
```

El módulo `fail` **fuerza el fallo del playbook** con un mensaje personalizado si se cumple la condición `when`.

| **Elemento** | **Descripción** |
|---|---|
| `msg` | Mensaje de error que se muestra si el play falla |
| `when` | Condición Jinja2 que evalúa si el contenido esperado **no está** en la respuesta |
| `with_items: "{{lb_index.results}}"` | Itera sobre los resultados de cada petición HTTP registrada |
| `item.content` | El cuerpo HTML de la respuesta HTTP guardado por `register` |

**¿Qué verifica exactamente?**

- Petición a `http://192.168.11.30/` → el cuerpo debe contener `Hello, from sunny`
- Petición a `http://192.168.11.30/db` → el cuerpo debe contener `Database Connected from`

Si cualquiera de estas cadenas no aparece en la respuesta, el play falla con el mensaje de error correspondiente.

---

### Fase 3 — Prueba HTTP end-to-end de la ruta `/db` desde el nodo de control

```yaml
    - name: verify end-to-end db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.loadbalancer }}"
      register: lb_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{lb_db.results}}"
```

Idéntico al bloque anterior pero apuntando a la ruta `/db`, que en la aplicación Flask realiza una consulta real a MySQL y devuelve el hostname del servidor. Verifica que **la conectividad completa loadbalancer → webserver → MySQL** funciona correctamente de extremo a extremo.

---

### Fase 4 — Prueba HTTP directa desde el loadbalancer a los webservers

```yaml
- hosts: loadbalancer
  tasks:
    - name: verify backend index response
      uri: url=http://{{item}} return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_index

    - fail: msg="index failed to return content"
      when: "'Hello, from sunny' not in item.content"
      with_items: "{{app_index.results}}"
```

Ahora el origen de las peticiones es el **nodo loadbalancer** (`192.168.11.30`) y el destino son los **webservers** (`192.168.11.40`). Esto verifica la conectividad directa entre el balanceador y la capa de aplicación, **sin pasar por Nginx**, útil para aislar problemas.

---

### Fase 5 — Prueba HTTP directa de `/db` desde el loadbalancer a los webservers

```yaml
    - name: verify backend db response
      uri: url=http://{{item}}/db return_content=yes
      with_items: "{{ groups.webserver }}"
      register: app_db

    - fail: msg="db failed to return content"
      when: "'Database Connected from' not in item.content"
      with_items: "{{app_db.results}}"
```

Verifica que la ruta `/db` funciona correctamente en cada webserver individual, comprobando que **Apache + Flask + MySQL** están correctamente integrados en el backend.

---

### Mapa completo de verificaciones de `stack_status.yml`

```
FASE 1 — Nivel proceso y red
  loadbalancer: service nginx status + wait_for :80
  webserver:    service apache2 status + wait_for :80
  database:     service mysql status + wait_for :3306

FASE 2 — HTTP end-to-end (control → loadbalancer)
  control → http://192.168.11.30/     → "Hello, from sunny"
  control → http://192.168.11.30/db   → "Database Connected from"

FASE 3 — HTTP directo (loadbalancer → webserver)
  loadbalancer → http://192.168.11.40/     → "Hello, from sunny"
  loadbalancer → http://192.168.11.40/db   → "Database Connected from"
```

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml
```

---

## 📜 `playbooks/stack_restart.yml` — Reinicio seguro del stack

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

Reinicia todos los servicios del stack en orden seguro, usando `wait_for` para confirmar cada transición de estado antes de continuar al siguiente paso.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml
```

---

## 🎯 `site.yml` — Orquestación completa del stack

```yaml
---
- ansible.builtin.import_playbook: control.yml
- ansible.builtin.import_playbook: database.yml
- ansible.builtin.import_playbook: webserver.yml
- ansible.builtin.import_playbook: loadbalancer.yml
- ansible.builtin.import_playbook: playbooks/stack_status.yml
- ansible.builtin.import_playbook: playbooks/stack_restart.yml
- ansible.builtin.import_playbook: playbooks/stack_status.yml
```

Archivo maestro que orquesta el despliegue completo del stack de forma automatizada:

1. Prepara el nodo de control
2. Instala la base de datos
3. Instala el servidor web
4. Instala el balanceador de carga
5. Verifica que el stack funciona correctamente
6. Reinicia el stack en orden seguro
7. Verifica nuevamente que el stack funciona correctamente

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant site.yml
```

Este comando ejecuta el flujo completo de despliegue y verificación en una sola llamada.

## 🔄 Flujo completo de despliegue del stack

### Opción 1: Despliegue paso a paso

```bash
# 1. Preparar el nodo de control
ansible-playbook -i hosts -u vagrant control.yml

# 2. Desplegar la base de datos
ansible-playbook -i hosts -u vagrant database.yml

# 3. Desplegar el servidor web
ansible-playbook -i hosts -u vagrant webserver.yml

# 4. Desplegar el balanceador de carga
ansible-playbook -i hosts -u vagrant loadbalancer.yml
```

### Opción 2: Despliegue automático completo

```bash
# Despliegue + verificación + reinicio + verificación en una sola llamada
ansible-playbook -i hosts -u vagrant site.yml
```

### Comandos de operación del stack (una vez desplegado)

```bash
# Verificación completa del stack (servicios + HTTP end-to-end)
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml

# Reiniciar el stack completo en orden seguro
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml

# Consultar hostname de todos los nodos
ansible-playbook -i hosts -u vagrant playbooks/hostname.yml
```

---

## 🔍 Niveles de verificación en `stack_status.yml`

| **Nivel** | **Módulo** | **Qué verifica** | **Desde** | **Hacia** |
|---|---|---|---|---|
| Proceso OS | `command` | El servicio systemd está activo | cada nodo | sí mismo |
| Red TCP | `wait_for` | El puerto está abierto y acepta conexiones | cada nodo | sí mismo |
| HTTP app | `uri` + `fail` | La respuesta HTTP contiene el texto esperado | `control` | `loadbalancer` |
| HTTP DB | `uri` + `fail` | La ruta `/db` conecta con MySQL correctamente | `control` | `loadbalancer` |
| HTTP backend | `uri` + `fail` | El webserver responde directamente sin Nginx | `loadbalancer` | `webserver` |
| HTTP backend DB | `uri` + `fail` | Flask + MySQL funcionan en el backend | `loadbalancer` | `webserver` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `uri`**: Realiza peticiones HTTP desde el nodo Ansible hacia una URL. Con `return_content=yes` captura el cuerpo de la respuesta para inspeccionarlo. El módulo utiliza la librería HTTP estándar de Python sin requerir dependencias adicionales en versiones modernas.
- **Módulo `fail`**: Fuerza el fallo explícito del playbook con un mensaje personalizado cuando se cumple la condición `when`. Es la herramienta estándar para implementar **aserciones** en Ansible.
- **`register`**: Guarda el resultado de una tarea en una variable para usarla en tareas posteriores. En combinación con `uri`, permite inspeccionar el contenido de las respuestas HTTP.
- **`when` con `not in`**: Condición Jinja2 que evalúa si una cadena de texto **no está contenida** en otra. Patrón estándar para verificar contenido de respuestas HTTP.
- **`groups.loadbalancer` / `groups.webserver`**: Variables mágicas de Ansible que exponen las listas de hosts de cada grupo del inventario, usadas aquí con `with_items` para iterar sobre las IPs de cada capa del stack.
- **Pruebas en dos capas**: Verificar tanto `control → loadbalancer` como `loadbalancer → webserver` permite **aislar problemas**: si la prueba desde control falla pero la del loadbalancer pasa, el problema está en Nginx; si ambas fallan, el problema está en Apache o MySQL.
- **Verificación multi-nivel**: El playbook `stack_status.yml` implementa verificaciones en cinco fases (procesos, puertos, HTTP end-to-end, HTTP directo) para garantizar que cada componente del stack funciona correctamente de forma aislada y integrada.

---

## 📚 Referencias

- [Ansible Docs — ansible.builtin.uri module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/uri_module.html)
- [Ansible Docs — ansible.builtin.fail module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/fail_module.html)
- [Ansible Docs — Registering variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#registering-variables)
- [Ansible Docs — Conditionals (when)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [Ansible Docs — ansible.builtin.wait_for module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
