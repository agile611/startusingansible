# 📋 `training/` — Colección de playbooks de entrenamiento Ansible

## 🧭 Descripción general

El directorio `training/` es una **biblioteca de playbooks didácticos** diseñada para aprender Ansible módulo a módulo. Cada fichero `.yml` es un ejemplo autocontenido que demuestra un concepto concreto: gestión de paquetes, escalada de privilegios, bucles, facts del sistema, handlers, condicionales y etiquetas.

No hay un playbook "principal" — cada fichero es independiente y se ejecuta de forma individual. El inventario compartido por todos es el que se define a continuación.

---

## 🗂️ Inventario compartido: `hosts`

Todos los playbooks de este directorio usan el mismo inventario:

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

### Parámetros del inventario explicados

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Usa Python 3 en los nodos remotos |
| `ansible_user` | `vagrant` | Usuario SSH para conectarse a los nodos |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la confirmación manual de fingerprint SSH (útil en laboratorios) |
| `[database]` | `192.168.11.20` | Nodo de base de datos |
| `[loadbalancer]` | `192.168.11.30` | Nodo balanceador de carga |
| `[webserver]` | `192.168.11.40` | Nodo servidor web |

### Estructura del laboratorio

```
Nodo de control (donde corre ansible-playbook)
│
├── SSH → 192.168.11.20  [database]
├── SSH → 192.168.11.30  [loadbalancer]
└── SSH → 192.168.11.40  [webserver]
```

---

## 🗂️ Estructura del directorio

```
training/
├── apt-install.yml        # Instalar paquetes con apt
├── apt-uninstall.yml      # Desinstalar paquetes con apt
├── apt-update.yml         # Actualizar el sistema completo
├── become_method.yml      # Escalada de privilegios con sudo
├── become_sola_tarea.yml  # become aplicado solo a una tarea específica
├── become_user.yml        # Ejecutar tareas como un usuario específico
├── facts.yml              # Explorar ansible_facts del sistema
├── handlers.yml           # Handlers: acciones reactivas a cambios
├── loops.yml              # Bucles con with_items
├── tags.yml               # Etiquetas para ejecución selectiva
└── when.yml               # Condicionales basados en facts
```

---

## 📄 `apt-install.yml` — Instalar paquetes con apt

Este playbook instala dos paquetes (`curl` y `vim`) en el grupo `webserver` usando el módulo `ansible.builtin.apt`.

```yaml
- name: Instal·lar paquets amb apt
  hosts: webserver
  become: yes
  tasks:

    - name: Instal·lar curl
      ansible.builtin.apt:
        name: curl
        state: present
        update_cache: yes

    - name: Instal·lar vim
      ansible.builtin.apt:
        name: vim
        state: present
```

### Flujo de ejecución

```
apt-install.yml  →  hosts: webserver  (192.168.11.40)
│
├── [1] apt: curl → state: present + update_cache: yes
│       └── Actualiza la caché apt y luego instala curl
│           Si curl ya está instalado → no hace nada (idempotente)
│
└── [2] apt: vim → state: present
        └── Instala vim (sin actualizar caché, ya actualizada en paso 1)
            Si vim ya está instalado → no hace nada (idempotente)
```

### Conceptos clave

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `hosts: webserver` | Grupo webserver | Solo actúa sobre `192.168.11.40` |
| `become: yes` | Escalada de privilegios | Ejecuta como `root` (necesario para instalar paquetes) |
| `state: present` | Presente | Instala el paquete si no está instalado |
| `update_cache: yes` | Actualizar caché | Equivale a `apt-get update` antes de instalar |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant apt-install.yml
```

---

## 📄 `apt-uninstall.yml` — Desinstalar paquetes con apt

Este playbook desinstala `curl` y `vim` del grupo `webserver` en una sola tarea, usando una lista de paquetes y limpiando completamente sus rastros.

```yaml
- name: Desinstal·lar paquets amb apt
  hosts: webserver
  become: yes
  tasks:

    - name: Eliminar curl i vim
      ansible.builtin.apt:
        name:
          - curl
          - vim
        state: absent
        purge: yes
        autoremove: yes
```

### Flujo de ejecución

```
apt-uninstall.yml  →  hosts: webserver  (192.168.11.40)
│
└── [1] apt: [curl, vim] → state: absent
        ├── purge: yes      → Elimina también ficheros de configuración
        └── autoremove: yes → Elimina dependencias huérfanas
```

### Diferencia entre `state: absent` y `purge: yes`

| **Opción** | **Qué elimina** |
|---|---|
| `state: absent` | El binario y ficheros del paquete |
| `purge: yes` | También los ficheros de configuración en `/etc/` |
| `autoremove: yes` | Dependencias instaladas automáticamente que ya no son necesarias |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant apt-uninstall.yml
```

---

## 📄 `apt-update.yml` — Actualizar el sistema completo

Este playbook actualiza el sistema completo en **todos los nodos** (`hosts: all`): actualiza la caché apt, actualiza todos los paquetes instalados y elimina los paquetes huérfanos.

```yaml
- name: Actualitzar el sistema
  hosts: all
  become: yes
  tasks:

    - name: Actualitzar caché apt
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Actualitzar tots els paquets
      ansible.builtin.apt:
        upgrade: yes

    - name: Eliminar paquets orfes
      ansible.builtin.apt:
        autoremove: yes
```

### Flujo de ejecución

```
apt-update.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] update_cache: yes + cache_valid_time: 3600
│       └── Actualiza la caché apt solo si tiene más de 1 hora de antigüedad
│           (evita actualizaciones innecesarias si se ejecuta varias veces)
│
├── [2] upgrade: yes
│       └── Actualiza todos los paquetes instalados a su última versión disponible
│           Equivale a: apt-get upgrade
│
└── [3] autoremove: yes
        └── Elimina paquetes instalados como dependencias que ya no son necesarios
            Equivale a: apt-get autoremove
```

### Parámetro `cache_valid_time`

`cache_valid_time: 3600` es un optimizador de idempotencia: si la caché apt tiene menos de 3600 segundos (1 hora) de antigüedad, Ansible **no la actualiza de nuevo**. Esto es muy útil cuando el playbook se ejecuta varias veces seguidas en un pipeline CI/CD.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant apt-update.yml
```

---

## 📄 `become_method.yml` — Escalada de privilegios con sudo

Este playbook muestra cómo configurar explícitamente el **método de escalada de privilegios** (`become_method: sudo`) y verifica qué usuario está activo durante la ejecución.

```yaml
- name: Usar su en lugar de sudo
  hosts: all
  become: yes
  become_method: sudo
  tasks:
    - name: Verificar el usuario actual
      command: whoami
      register: resultado

    - name: Mostrar el usuario actual
      debug:
        msg: "El usuario actual es {{ resultado.stdout }}"
```

### Flujo de ejecución

```
become_method.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] command: whoami
│       └── Ejecuta el comando whoami en el nodo remoto
│           El resultado se guarda en la variable "resultado"
│           Con become: yes + become_method: sudo → whoami devuelve "root"
│
└── [2] debug: msg
        └── Imprime en pantalla el contenido de resultado.stdout
            Salida esperada: "El usuario actual es root"
```

### Métodos de escalada disponibles en Ansible

| **`become_method`** | **Comando equivalente** | **Cuándo usarlo** |
|---|---|---|
| `sudo` (por defecto) | `sudo -u root` | La mayoría de sistemas Linux modernos |
| `su` | `su - root` | Sistemas sin sudo configurado |
| `pbrun` | `pbrun` | Entornos con PowerBroker |
| `pfexec` | `pfexec` | Solaris |
| `doas` | `doas` | OpenBSD / sistemas minimalistas |

### Concepto `register`

`register: resultado` captura la salida del módulo `command` en una variable. Esta variable tiene la estructura:

```yaml
resultado:
  stdout: "root"        # Salida estándar del comando
  stderr: ""            # Salida de error
  rc: 0                 # Código de retorno (0 = éxito)
```

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant become_method.yml
```

---

## 📄 `become_sola_tarea.yml` — `become` aplicado a una sola tarea

Este playbook demuestra que `become: yes` **no tiene que aplicarse al playbook completo** — puede aplicarse únicamente a la tarea que lo necesita.

```yaml
- name: Become de una sola tarea
  hosts: all
  tasks:
    - name: Ping a los hosts
      ping:

    - name: Install joe editor
      apt:
        name: joe
        state: present
      become: yes
```

### Flujo de ejecución

```
become_sola_tarea.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] ping:  (sin become)
│       └── Se ejecuta como el usuario "vagrant"
│           Solo verifica conectividad — no necesita privilegios
│
└── [2] apt: joe → state: present  (con become: yes)
        └── Se ejecuta como "root" (sudo)
            Instala el editor joe — requiere privilegios de root
```

### Principio de mínimo privilegio

Este patrón es una **buena práctica de seguridad**: solo escala privilegios en las tareas que realmente lo necesitan. Comparativa:

| **Enfoque** | **Riesgo** | **Cuándo usar** |
|---|---|---|
| `become: yes` en el play | Mayor — todo corre como root | Playbooks de administración del sistema |
| `become: yes` por tarea | Menor — privilegios mínimos | Playbooks mixtos (lectura + escritura) |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant become_sola_tarea.yml
```

---

## 📄 `become_user.yml` — Ejecutar tareas como un usuario específico

Este playbook muestra cómo ejecutar tareas **como un usuario específico** (distinto de `root`) usando `become_user`. El caso de uso es PostgreSQL, que requiere ejecutar comandos como el usuario `postgres`.

```yaml
- name: ejecutar tareas con un usuario especifico
  hosts: all
  become: yes
  become_user: postgres
  tasks:
    - name: Crear base de datos
      postgresql_db:
        name: mi_base_de_datos
        state: present
```

### Flujo de ejecución

```
become_user.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
└── [1] postgresql_db: mi_base_de_datos → state: present
        ├── become: yes       → Escala privilegios
        ├── become_user: postgres → Cambia al usuario "postgres" (no a root)
        └── Crea la base de datos "mi_base_de_datos" si no existe
            Si ya existe → no hace nada (idempotente)
```

### Diferencia entre `become_user` y `become`

| **Configuración** | **Usuario de ejecución** | **Caso de uso** |
|---|---|---|
| `become: yes` (sin `become_user`) | `root` | Administración del sistema |
| `become: yes` + `become_user: postgres` | `postgres` | Gestión de bases de datos PostgreSQL |
| `become: yes` + `become_user: www-data` | `www-data` | Gestión de ficheros de Apache/Nginx |

> ⚠️ **Nota**: Este playbook requiere que PostgreSQL esté instalado en los nodos y que la colección `community.postgresql` esté disponible. En el laboratorio Vagrant base, sirve como ejemplo de sintaxis.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant become_user.yml
```

---

## 📄 `facts.yml` — Explorar `ansible_facts` del sistema

Este playbook muestra cómo acceder a los **facts** que Ansible recopila automáticamente de cada nodo: sistema operativo, nombre del host, versión del kernel y versión de Ansible.

```yaml
- name: Mirar los ansible_facts
  hosts: all
  become: yes
  tasks:
    - name: Verificar los hechos de Ansible
      ansible.builtin.debug:
        var: ansible_facts

    - name: Mostrar sistema operativo
      ansible.builtin.debug:
        msg: "El sistema operativo es {{ ansible_facts['os_family'] }}"

    - name: Mostrar el nombre del host
      ansible.builtin.debug:
        msg: "El nombre del host es {{ ansible_facts['nodename'] }}"

    - name: Mostrar la versión del kernel
      ansible.builtin.debug:
        msg: "La versión del kernel es {{ ansible_facts['kernel'] }}"

    - name: Mostrar la versión de Ansible
      ansible.builtin.debug:
        msg: "La versión de Ansible es {{ ansible_version.full }}"
```

### Flujo de ejecución

```
facts.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
│  [Gathering Facts] ← Ansible recopila automáticamente toda la info del nodo
│
├── [1] debug: var: ansible_facts
│       └── Imprime el diccionario completo de facts (muy verboso)
│           Útil para descubrir qué facts están disponibles
│
├── [2] debug: ansible_facts['os_family']
│       └── Ejemplo de salida: "Debian" (Ubuntu/Debian) o "RedHat" (CentOS/RHEL)
│
├── [3] debug: ansible_facts['nodename']
│       └── Nombre del host del nodo remoto (ej: "ubuntu-focal")
│
├── [4] debug: ansible_facts['kernel']
│       └── Versión del kernel Linux (ej: "5.4.0-182-generic")
│
└── [5] debug: ansible_version.full
        └── Versión de Ansible instalada en el nodo de control
            (ansible_version es una variable especial, no un fact del nodo)
```

### Facts más utilizados en Ansible

| **Fact** | **Ejemplo de valor** | **Uso típico** |
|---|---|---|
| `ansible_facts['os_family']` | `Debian` / `RedHat` | Condicionales para gestión de paquetes |
| `ansible_facts['distribution']` | `Ubuntu` / `CentOS` | Condicionales más específicos |
| `ansible_facts['nodename']` | `web-01` | Personalizar configuraciones por host |
| `ansible_facts['kernel']` | `5.4.0-182-generic` | Verificar compatibilidad de módulos de kernel |
| `ansible_facts['default_ipv4']['address']` | `192.168.11.40` | Obtener la IP del nodo dinámicamente |
| `ansible_facts['memtotal_mb']` | `2048` | Ajustar configuraciones según RAM disponible |
| `ansible_version.full` | `2.16.3` | Verificar compatibilidad de módulos Ansible |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant facts.yml
```

---

## 📄 `handlers.yml` — Handlers: acciones reactivas a cambios

Este playbook demuestra el concepto de **handler**: una tarea especial que solo se ejecuta si otra tarea produce un cambio real en el sistema. El caso de uso clásico es reiniciar Nginx solo cuando su configuración cambia.

```yaml
- name: Prueba de handlers
  hosts: webserver
  become: yes
  tasks:
    - name: Copiar archivo de configuración
      copy:
        src: nginx.conf
        dest: /etc/nginx/nginx.conf
      notify:
        - Reiniciar Nginx

  handlers:
    - name: Reiniciar Nginx
      service:
        name: nginx
        state: restarted
```

### Flujo de ejecución

```
handlers.yml  →  hosts: webserver  (192.168.11.40)
│
├── [1] copy: nginx.conf → /etc/nginx/nginx.conf
│       ├── Si el fichero CAMBIA → marca el handler "Reiniciar Nginx" como pendiente
│       └── Si el fichero NO cambia (idéntico) → handler NO se ejecuta
│
└── [Al final del play] Handler: "Reiniciar Nginx"
        ├── Se ejecuta SOLO si fue notificado
        └── service: nginx → state: restarted
            Reinicia el servicio Nginx para aplicar la nueva configuración
```

### ¿Por qué usar handlers en lugar de una tarea normal?

| **Enfoque** | **Comportamiento** | **Problema** |
|---|---|---|
| Tarea `service: restarted` normal | Reinicia **siempre** | Reinicio innecesario si la config no cambió |
| Handler con `notify` | Reinicia **solo si hay cambio** | ✅ Correcto — idempotente y eficiente |

> **Regla de oro**: Los handlers se ejecutan **una sola vez al final del play**, aunque sean notificados múltiples veces. Esto evita reinicios repetidos si varias tareas modifican la misma configuración.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant handlers.yml
```

> ⚠️ **Nota**: Este playbook requiere que el fichero `nginx.conf` exista en el directorio de trabajo del nodo de control (junto al playbook). El fichero de referencia está disponible en `misc/nginx.conf`.

---

## 📄 `loops.yml` — Bucles con `with_items`

Este playbook demuestra cómo usar **bucles** en Ansible para crear múltiples usuarios del sistema en una sola tarea, iterando sobre una lista de diccionarios.

```yaml
- name: Prueba de multiples usuarios
  hosts: all
  become: yes
  tasks:
    - name: Instalar el paquete 'python3-passlib'
      apt:
        name: python3-passlib
        state: present

    - name: lista multiples usuarios
      user:
        name: "{{ item.name }}"
        password: "{{ item.password }}"
        state: present
      with_items:
        - { name: usuario1, password: "contrasena1" }
        - { name: usuario2, password: "contrasena2" }
        - { name: usuario3, password: "contrasena3" }
```

### Flujo de ejecución

```
loops.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] apt: python3-passlib → state: present
│       └── Instala la librería necesaria para hashear contraseñas
│           (el módulo user de Ansible la necesita para cifrar passwords)
│
└── [2] user: → with_items (3 iteraciones)
        ├── Iteración 1: user: name=usuario1, password=contrasena1
        ├── Iteración 2: user: name=usuario2, password=contrasena2
        └── Iteración 3: user: name=usuario3, password=contrasena3
            Crea los 3 usuarios del sistema en los 3 nodos
```

### Sintaxis moderna: `loop` vs `with_items`

`with_items` es la sintaxis clásica. Desde Ansible 2.5+, la sintaxis recomendada es `loop`:

```yaml
# Sintaxis clásica (aún válida)
with_items:
  - { name: usuario1, password: "contrasena1" }

# Sintaxis moderna (recomendada)
loop:
  - { name: usuario1, password: "contrasena1" }
```

Ambas son equivalentes para listas simples. `loop` es más potente y extensible.

### Acceso a elementos del bucle

| **Expresión** | **Valor** | **Descripción** |
|---|---|---|
| `{{ item }}` | `{name: usuario1, password: contrasena1}` | El elemento completo |
| `{{ item.name }}` | `usuario1` | Campo `name` del diccionario |
| `{{ item.password }}` | `contrasena1` | Campo `password` del diccionario |

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant loops.yml
```

---

## 📄 `tags.yml` — Etiquetas para ejecución selectiva

Este playbook demuestra el uso de **tags** (etiquetas) para ejecutar solo partes específicas de un playbook sin modificar el código.

```yaml
- name: Instalar editor Joe
  hosts: all
  become: yes
  tasks:
    - name: Instalar Joe
      apt:
        name: joe
        state: present
      tags: install

    - name: Mostrar versión de Joe
      shell: ls -lah /usr/bin/joe
      tags: version
```

### Flujo de ejecución

```
tags.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] apt: joe → state: present   [tag: install]
│       └── Instala el editor de texto Joe
│
└── [2] shell: ls -lah /usr/bin/joe  [tag: version]
        └── Lista el binario de Joe con detalles (tamaño, permisos, fecha)
            Sirve para verificar que la instalación fue correcta
```

### Comandos con tags

```bash
# Ejecutar TODAS las tareas (comportamiento normal)
ansible-playbook -i hosts -u vagrant tags.yml

# Ejecutar SOLO las tareas con tag "install"
ansible-playbook -i hosts -u vagrant tags.yml --tags install

# Ejecutar SOLO las tareas con tag "version"
ansible-playbook -i hosts -u vagrant tags.yml --tags version

# Ejecutar todas EXCEPTO las tareas con tag "install"
ansible-playbook -i hosts -u vagrant tags.yml --skip-tags install

# Listar todas las tags disponibles sin ejecutar nada
ansible-playbook -i hosts -u vagrant tags.yml --list-tags
```

### ¿Cuándo usar tags?

| **Caso de uso** | **Ejemplo** |
|---|---|
| Ejecutar solo la instalación | `--tags install` |
| Ejecutar solo la verificación | `--tags version` |
| Saltarse tareas lentas en desarrollo | `--skip-tags install` |
| Pipelines CI/CD con etapas separadas | `--tags deploy`, `--tags test` |

---

## 📄 `when.yml` — Condicionales basados en facts

Este es el playbook más complejo del directorio. Demuestra cómo usar **condicionales `when`** para ejecutar tareas solo en nodos que cumplan una condición específica: instalar Nginx únicamente en el servidor con IP `192.168.11.40`.

```yaml
- name: Instala Nginx cuando la maquina tenga la ip 192.168.11.40
  hosts: all
  become: yes
  tasks:
    - name: Obtener la dirección IP de la interfaz eth1
      command: ip addr show eth1
      register: ip_output

    - name: Extraer la dirección IP de la salida del comando
      set_fact:
        ip_address: "{{ ip_output.stdout | regex_search('inet (\\d+\\.\\d+\\.\\d+\\.\\d+)', '\\1') }}"

    - name: Imprimir la dirección IP obtenida
      debug:
        msg: "La dirección IP de eth1 es {{ ip_address }}"

    - name: Instalar Nginx si la IP es 192.168.11.40
      apt:
        name: nginx
        state: present
      when: ip_address == ['192.168.11.40']

    - name: Verificar la instalación de Nginx
      command: nginx -v
      register: nginx_version
      when: ip_address == ['192.168.11.40']

    - name: Desinstala nginx
      apt:
        name: nginx
        state: absent
      when: ip_address == ['192.168.11.40']
```

### Flujo de ejecución detallado

```
when.yml  →  hosts: all  (192.168.11.20 + .30 + .40)
│
├── [1] command: ip addr show eth1
│       └── Ejecuta el comando en cada nodo y guarda la salida en "ip_output"
│
├── [2] set_fact: ip_address
│       └── Aplica un filtro regex a ip_output.stdout para extraer la IP
│           Patrón: busca "inet X.X.X.X" y captura solo los dígitos
│           Resultado: ip_address = ['192.168.11.40'] (lista con un elemento)
│
├── [3] debug: ip_address
│       └── Imprime la IP detectada en cada nodo
│
├── [4] apt: nginx → state: present
│       └── CONDICIÓN: when: ip_address == ['192.168.11.40']
│           ✅ 192.168.11.40 (webserver) → instala Nginx
│           ⏭️  192.168.11.20 (database)  → SKIP
│           ⏭️  192.168.11.30 (loadbalancer) → SKIP
│
├── [5] command: nginx -v
│       └── CONDICIÓN: misma que [4]
│           ✅ Solo en webserver → verifica que Nginx responde
│
└── [6] apt: nginx → state: absent
        └── CONDICIÓN: misma que [4]
            ✅ Solo en webserver → desinstala Nginx (limpieza del ejemplo)
```

### Conceptos avanzados utilizados

| **Concepto** | **Módulo/Sintaxis** | **Función** |
|---|---|---|
| Captura de salida | `register: ip_output` | Guarda el stdout del comando en una variable |
| Fact personalizado | `set_fact: ip_address` | Crea una variable nueva a partir de datos procesados |
| Filtro regex | `\| regex_search(...)` | Extrae un patrón de texto de una cadena |
| Condicional | `when: ip_address == [...]` | Ejecuta la tarea solo si la condición es verdadera |

> **¿Por qué `ip_address == ['192.168.11.40']` (lista) y no `== '192.168.11.40'` (string)?**
> El filtro `regex_search` con grupo de captura devuelve una **lista** en Ansible, no una cadena. Por eso la comparación es contra `['192.168.11.40']`.

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant when.yml
```

---

## 🔍 Resumen de todos los playbooks

| **Fichero** | **`hosts`** | **Concepto principal** | **Módulos usados** |
|---|---|---|---|
| `apt-install.yml` | `webserver` | Instalar paquetes | `ansible.builtin.apt` |
| `apt-uninstall.yml` | `webserver` | Desinstalar paquetes con purge | `ansible.builtin.apt` |
| `apt-update.yml` | `all` | Actualizar sistema completo | `ansible.builtin.apt` |
| `become_method.yml` | `all` | Escalada de privilegios con sudo | `command`, `debug` |
| `become_sola_tarea.yml` | `all` | `become` por tarea individual | `ping`, `apt` |
| `become_user.yml` | `all` | Ejecutar como usuario específico | `postgresql_db` |
| `facts.yml` | `all` | Explorar `ansible_facts` | `ansible.builtin.debug` |
| `handlers.yml` | `webserver` | Handlers reactivos a cambios | `copy`, `service` |
| `loops.yml` | `all` | Bucles con `with_items` | `apt`, `user` |
| `tags.yml` | `all` | Ejecución selectiva con tags | `apt`, `shell` |
| `when.yml` | `all` | Condicionales con `when` | `command`, `set_fact`, `debug`, `apt` |

---

## 💡 Conceptos clave aprendidos

- **Idempotencia**: Todos los módulos `apt` y `user` son idempotentes — ejecutar el playbook múltiples veces produce el mismo resultado sin efectos secundarios.

- **`become` granular**: `become: yes` puede aplicarse al play completo o a tareas individuales. Aplicarlo solo donde es necesario sigue el principio de mínimo privilegio.

- **`register` + `set_fact`**: El patrón `register` → `set_fact` → `when` es la forma estándar de tomar decisiones basadas en el estado real del sistema, no en suposiciones.

- **Handlers vs tareas normales**: Los handlers solo se ejecutan si hay un cambio real y se ejecutan una sola vez al final del play, evitando reinicios innecesarios de servicios.

- **`cache_valid_time`**: Optimiza la idempotencia de `apt update` evitando actualizaciones de caché redundantes en ejecuciones sucesivas.

- **Tags para pipelines**: Las etiquetas permiten dividir un playbook en etapas ejecutables de forma independiente, ideal para pipelines CI/CD con fases de `install`, `configure`, `test` y `deploy`.

---

## 📚 Referencias

- [Ansible Docs — `ansible.builtin.apt`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Ansible Docs — Privilege Escalation (`become`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)
- [Ansible Docs — Gathering Facts](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
- [Ansible Docs — Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Ansible Docs — Loops](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html)
- [Ansible Docs — Tags](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html)
- [Ansible Docs — Conditionals (`when`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
