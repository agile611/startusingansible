# ⏳ Ejemplo 013 — Espera activa de servicios con `wait_for`

## 🧭 Descripción general

Este ejemplo introduce el módulo `wait_for`, que permite a Ansible **pausar la ejecución de un play hasta que se cumpla una condición** — típicamente que un puerto de red esté abierto, cerrado o drenado. Es la herramienta clave para construir **orquestaciones robustas y seguras** donde cada paso espera a que el anterior haya terminado realmente antes de continuar.

La novedad principal respecto al ejemplo anterior (`012_mysql_management`) está en la carpeta `playbook/`: los ficheros `stack_restart.yml` y `stack_status.yml` incorporan `wait_for` después de cada operación de servicio, garantizando que el stack no avanza al siguiente paso hasta que el puerto correspondiente confirma el estado esperado.

En los playbooks principales (`database.yml`, `webserver.yml`, `loadbalancer.yml`) se añade además el **handler `restart mysql`** en `database.yml`, que reinicia MySQL solo cuando `lineinfile` detecta un cambio real en la configuración.

---

## 🗂️ Estructura del proyecto

```
013_wait_for/
├── hosts                          # Inventario de máquinas
├── control.yml                    # Playbook para el nodo de control
├── database.yml                   # Playbook para el servidor de base de datos ⭐ MODIFICADO
├── loadbalancer.yml               # Playbook para el balanceador de carga
├── webserver.yml                  # Playbook para el servidor web ⭐ MODIFICADO
├── templates/
│   └── nginx.conf.j2              # Plantilla Jinja2 para configurar Nginx
├── demo/
│   ├── app/                       # Código fuente de la aplicación Python/Flask
│   └── demo.conf                  # Configuración VirtualHost de Apache
└── playbook/                      # Utilidades operacionales ⭐ MODIFICADAS
    ├── hostname.yml               # Consulta el hostname de todos los nodos
    ├── stack_restart.yml          # Reinicia el stack con wait_for entre pasos ⭐
    └── stack_status.yml           # Verifica el estado de todos los servicios ⭐ NUEVO
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

## ⭐ Novedad en `database.yml` — Handler `restart mysql`

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install tools
      apt: name={{item}} state=present update_cache=yes
      with_items:
        - python3-mysqldb

    - name: install mysql-server
      apt: name=mysql-server state=present update_cache=yes

    - name: ensure mysql started
      service: name=mysql state=started enabled=yes

    - name: ensure mysql listening on all ports
      lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address line="bind-address = 0.0.0.0"
      notify: restart mysql

    - name: create demo database
      mysql_db: name=demo state=present

    - name: create demo user
      mysql_user: name=demo password=demo priv=demo.*:ALL host='%' state=present

  handlers:
    - name: restart mysql
      service: name=mysql state=restarted
```

### Diferencia respecto al ejemplo 012

La tarea `lineinfile` ahora incluye `notify: restart mysql`, y se añade el handler correspondiente al final del play.

| **Elemento** | **Ejemplo 012** | **Ejemplo 013** |
|---|---|---|
| `lineinfile` modifica `bind-address` | ✅ Sí | ✅ Sí |
| Reinicia MySQL si cambia la config | ❌ No (manual) | ✅ Sí (handler) |
| Handler `restart mysql` | ❌ No existe | ✅ Añadido |

**¿Por qué es importante este handler?**

Sin el handler, aunque `lineinfile` cambie `bind-address` en `my.cnf`, MySQL seguiría escuchando solo en `127.0.0.1` hasta el próximo reinicio manual. Con el handler, Ansible reinicia MySQL **automáticamente y solo si hubo un cambio real** en la configuración, aplicando el nuevo `bind-address = 0.0.0.0` de forma inmediata e idempotente.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant database.yml
```

---

## ⭐ Novedad en `webserver.yml` — `python3-mysqldb` en el webserver

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
        - python3-mysqldb          # ⭐ NUEVO respecto a 012

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

Se añade `python3-mysqldb` a la lista de paquetes del webserver. La aplicación Flask necesita esta librería para conectarse a MySQL desde el servidor web.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant webserver.yml
```

---

## ⭐ La novedad principal: `playbook/stack_restart.yml` con `wait_for`

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

### ¿Qué hace `wait_for`?

El módulo `wait_for` **bloquea la ejecución del playbook** en el nodo donde se ejecuta hasta que se cumple la condición especificada sobre un puerto de red. Si la condición no se cumple en el tiempo de espera (`timeout`, por defecto 300 segundos), el play falla con error.

### Parámetros usados en este ejemplo

| **Parámetro** | **Valores posibles** | **Descripción** |
|---|---|---|
| `port` | `80`, `3306` | Puerto TCP a monitorizar |
| `state` | `started`, `stopped`, `drained` | Condición que debe cumplirse |
| `timeout` | número en segundos | Tiempo máximo de espera (por defecto 300s) |

### Los tres estados de `wait_for`

| **`state`** | **Significado** | **Cuándo usarlo** |
|---|---|---|
| `started` | Espera hasta que el puerto **está abierto** y acepta conexiones | Después de arrancar un servicio, para confirmar que está listo |
| `stopped` | Espera hasta que el puerto **está cerrado** y no acepta conexiones | Después de parar un servicio, para confirmar que ha terminado |
| `drained` | Espera hasta que el puerto **no tiene conexiones activas** (las existentes terminan) | Antes de parar un balanceador, para un apagado graceful sin cortar peticiones en vuelo |

### Secuencia detallada del reinicio con `wait_for`

```
1. loadbalancer: nginx stopped
   └── wait_for port=80 state=drained   → espera a que no haya conexiones activas en :80

2. webserver: apache2 stopped
   └── wait_for port=80 state=stopped   → espera a que el puerto :80 esté completamente cerrado

3. database: mysql restarted
   └── wait_for port=3306 state=started → espera a que MySQL esté escuchando en :3306

4. webserver: apache2 started
   └── wait_for port=80                 → espera a que Apache esté escuchando en :80 (state=started implícito)

5. loadbalancer: nginx started
   └── wait_for port=80                 → espera a que Nginx esté escuchando en :80
```

**¿Por qué `drained` en el loadbalancer y `stopped` en el webserver?**

- El **loadbalancer** (Nginx) es el punto de entrada del tráfico. Usar `state=drained` permite que las peticiones HTTP que ya están siendo procesadas terminen correctamente antes de parar Nginx, evitando cortes bruscos para los usuarios.
- El **webserver** (Apache) ya no recibe tráfico nuevo (el loadbalancer está parado). Usar `state=stopped` simplemente confirma que el puerto ha quedado libre antes de reiniciar MySQL.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/stack_restart.yml
```

---

## ⭐ Nuevo: `playbook/stack_status.yml` — Verificación del estado del stack

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

Este playbook de **diagnóstico y verificación** comprueba que todos los servicios del stack están activos y escuchando en sus puertos correspondientes. Para cada nodo realiza dos comprobaciones:

#### Doble verificación por nodo

| **Nodo** | **Tarea 1 — `command`** | **Tarea 2 — `wait_for`** |
|---|---|---|
| `loadbalancer` | `service nginx status` → verifica que el proceso está activo | `port=80 timeout=3` → verifica que el puerto está abierto |
| `webserver` | `service apache2 status` → verifica que el proceso está activo | `port=80 timeout=3` → verifica que el puerto está abierto |
| `database` | `service mysql status` → verifica que el proceso está activo | `port=3306 timeout=3` → verifica que el puerto está abierto |

**¿Por qué dos comprobaciones por servicio?**

- `service <nombre> status` verifica que el **proceso del sistema operativo** está corriendo (nivel de proceso).
- `wait_for port=X timeout=3` verifica que el servicio está **realmente aceptando conexiones de red** en el puerto esperado (nivel de red).

Un servicio puede estar "corriendo" según systemd pero no haber terminado de arrancar y aún no estar escuchando en el puerto. La combinación de ambas comprobaciones garantiza una verificación completa.

> 💡 `timeout=3` es un valor muy bajo (3 segundos) pensado para diagnóstico rápido: si el puerto no responde en 3 segundos, el playbook falla inmediatamente indicando que algo va mal, en lugar de esperar los 300 segundos por defecto.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/stack_status.yml
```

---

## 📜 `playbook/hostname.yml` — Sin cambios respecto a 012

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

Ejecuta `hostname` en todos los nodos del inventario. Útil para verificar conectividad SSH y nombres de host.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook/hostname.yml
```

---

## 📜 Playbook `loadbalancer.yml` — Sin cambios respecto a 012

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

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loadbalancer.yml
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

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant control.yml
```

---

## 🔄 Flujo completo de despliegue del stack

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

### Comandos de operación del stack (una vez desplegado)

```bash
# Verificar el estado de todos los servicios
ansible-playbook -i hosts -u vagrant playbook/stack_status.yml

# Reiniciar el stack completo en orden seguro con wait_for
ansible-playbook -i hosts -u vagrant playbook/stack_restart.yml

# Consultar hostname de todos los nodos
ansible-playbook -i hosts -u vagrant playbook/hostname.yml
```

### Diagrama del reinicio orquestado con `wait_for`

```
[stack_restart.yml]

FASE 1 — PARADA ORDENADA
  loadbalancer :80  → nginx stopped → wait_for drained  ✓
  webserver    :80  → apache2 stopped → wait_for stopped ✓

FASE 2 — REINICIO BASE DE DATOS
  database     :3306 → mysql restarted → wait_for started ✓

FASE 3 — ARRANQUE ORDENADO
  webserver    :80  → apache2 started → wait_for started ✓
  loadbalancer :80  → nginx started   → wait_for started ✓
```

---

## 🔍 Comparativa: sin `wait_for` vs con `wait_for`

| **Aspecto** | **Sin `wait_for`** | **Con `wait_for`** |
|---|---|---|
| Velocidad | ⚡ Más rápido (no espera) | 🐢 Ligeramente más lento |
| Fiabilidad | ❌ Puede fallar si el siguiente paso empieza antes de que el servicio esté listo | ✅ Garantiza que cada servicio está realmente listo antes de continuar |
| Apagado graceful | ❌ Puede cortar conexiones activas | ✅ `state=drained` espera a que terminen las conexiones en curso |
| Diagnóstico | ❌ Difícil saber si un servicio falló al arrancar | ✅ Falla explícitamente si el puerto no responde en el `timeout` |
| Uso recomendado | Entornos de laboratorio simples | Entornos de producción o staging |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `wait_for`**: Pausa la ejecución del playbook hasta que un puerto TCP cumple la condición especificada (`started`, `stopped`, `drained`). Es la herramienta estándar para sincronizar operaciones multi-servicio en Ansible.
- **`state=drained`**: Estado especial que espera a que todas las conexiones activas en un puerto terminen antes de continuar. Esencial para apagados graceful de balanceadores de carga sin interrumpir peticiones en vuelo.
- **`timeout=3` para diagnóstico**: Un timeout corto en `stack_status.yml` convierte `wait_for` en una herramienta de verificación rápida: falla inmediatamente si el servicio no responde, en lugar de esperar el timeout por defecto de 300 segundos.
- **Handler `restart mysql`**: La tarea `lineinfile` ahora notifica al handler, que reinicia MySQL automáticamente solo si la configuración cambió. Combina idempotencia con aplicación inmediata del cambio.
- **`python3-mysqldb` en el webserver**: La aplicación Flask necesita esta librería para conectarse a MySQL. Se añade al webserver para completar la integración de la capa de aplicación con la base de datos.
- **Doble verificación de servicios**: Combinar `command: service X status` (nivel de proceso) con `wait_for: port=X` (nivel de red) garantiza que un servicio no solo está "corriendo" sino que realmente acepta conexiones.

---

## 📚 Referencias

- [Ansible Docs — ansible.builtin.wait_for module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/wait_for_module.html)
- [Ansible Docs — Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Ansible Docs — ansible.builtin.service module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [Ansible Docs — ansible.builtin.command module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)
