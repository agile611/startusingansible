# 003_with_items — Instalación de múltiples paquetes con `with_items`

Este ejemplo introduce el bucle `with_items` de Ansible, que permite
instalar **múltiples paquetes en una sola tarea** en lugar de repetir
el módulo `apt` una vez por paquete. Es la evolución natural de los
ejemplos anteriores: se mantiene `become: true` para la escalada de
privilegios y se añade un nuevo playbook para el grupo `webserver`, que
instala la pila necesaria para servir una aplicación Python con Apache.

---

## 🗂️ Estructura del ejemplo

```
examples/003_with_items/
├── database.yml       # Instala default-mysql-server en 'database'
├── loadbalancer.yml   # Instala nginx en 'loadbalancer'
└── webserver.yml      # Instala apache2 + dependencias Python en 'webserver'
hosts                  # Inventario con los grupos y variables de conexión
```

---

## 🖥️ Inventario (`hosts`)

El fichero `hosts` define los grupos de servidores y las variables globales
de conexión SSH:

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

### Grupos de servidores

| Grupo | IP | Rol |
|---|---|---|
| `database` | `192.168.11.20` | Servidor de base de datos |
| `loadbalancer` | `192.168.11.30` | Balanceador de carga |
| `webserver` | `192.168.11.40` | Servidor web con Python/Apache |

---

## 🔑 Concepto clave: `with_items`

`with_items` es un bucle de Ansible que **itera sobre una lista de valores**
y ejecuta la tarea una vez por cada elemento. La variable especial `{{item}}`
se sustituye en cada iteración por el valor correspondiente de la lista.

### ¿Cómo funciona?

```yaml
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3
    - python3-pip-whl
    - python3-virtualenv
```

Ansible expande esto internamente como si fueran 4 tareas independientes:

```
apt install apache2
apt install libapache2-mod-wsgi-py3
apt install python3-pip-whl
apt install python3-virtualenv
```

### Ventajas frente a repetir tareas

| Enfoque | Código | Mantenimiento |
|---|---|---|
| Una tarea por paquete | Verboso, muchas líneas | Difícil de escalar |
| `with_items` | Compacto, una sola tarea | Añadir un paquete = una línea |

> **Nota moderna:** A partir de Ansible 2.5, la forma recomendada es usar
> `loop` en lugar de `with_items`. Ambas son equivalentes para listas simples:
> ```yaml
> loop:
>   - apache2
>   - nginx
> ```
> `with_items` sigue funcionando y es muy común encontrarla en código existente.

---

## 📋 Playbooks

### `database.yml` — Instalar MySQL

Instala `default-mysql-server` en el grupo `database` con privilegios
elevados. Igual que en el ejemplo `002_become`.

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install default-mysql-server
      apt: name=default-mysql-server state=present update_cache=yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.20` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Ejecuta `apt update` y luego `apt install default-mysql-server`.

---

### `loadbalancer.yml` — Instalar Nginx

Instala `nginx` en el grupo `loadbalancer` con privilegios elevados.
Igual que en el ejemplo `002_become`.

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: install nginx
      apt: name=nginx state=present update_cache=yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.30` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Ejecuta `apt update` y luego `apt install nginx`.

---

### `webserver.yml` — Instalar la pila web con `with_items` ⭐

Este es el playbook nuevo y central del ejemplo. Instala cuatro paquetes
en el grupo `webserver` usando un bucle `with_items`.

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
```

**¿Qué instala exactamente?**

| Paquete | Descripción |
|---|---|
| `apache2` | Servidor web Apache — sirve las peticiones HTTP |
| `libapache2-mod-wsgi-py3` | Módulo WSGI para Apache — permite ejecutar apps Python (Django, Flask…) |
| `python3-pip-whl` | Soporte de paquetes `.whl` para pip — gestión de dependencias Python |
| `python3-virtualenv` | Herramienta para crear entornos virtuales Python aislados |

**¿Qué hace exactamente paso a paso?**

1. Se conecta por SSH a `192.168.11.40` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Itera sobre la lista de 4 paquetes:
   - En cada iteración, `{{item}}` se sustituye por el nombre del paquete.
   - Ejecuta `apt update` + `apt install <paquete>` para cada uno.
4. Si algún paquete ya está instalado, Ansible reporta `ok` y lo omite
   (comportamiento **idempotente**).

---

## ▶️ Ejecución

> **Requisito previo:** Las máquinas virtuales deben estar levantadas con
> Vagrant y el usuario `vagrant` debe tener permisos de `sudo` sin contraseña.

### 1. Instalar MySQL en el servidor de base de datos

```bash
ansible-playbook -i hosts -u vagrant examples/003_with_items/database.yml
```

### 2. Instalar Nginx en el balanceador de carga

```bash
ansible-playbook -i hosts -u vagrant examples/003_with_items/loadbalancer.yml
```

### 3. Instalar la pila web en el servidor web

```bash
ansible-playbook -i hosts -u vagrant examples/003_with_items/webserver.yml
```

### Desglose de los flags del comando

| Flag | Valor | Descripción |
|---|---|---|
| `-i` | `hosts` | Especifica el fichero de inventario a usar |
| `-u` | `vagrant` | Usuario SSH con el que conectarse a los nodos |
| (último arg) | `examples/003_with_items/*.yml` | Ruta al playbook a ejecutar |

---

## 💡 Conceptos clave aprendidos

| Concepto | Descripción |
|---|---|
| **`with_items`** | Bucle que itera sobre una lista y ejecuta la tarea por cada elemento |
| **`{{item}}`** | Variable especial que contiene el valor actual del bucle |
| **`loop`** | Alternativa moderna a `with_items` (Ansible ≥ 2.5) |
| **`become: true`** | Escalada de privilegios a `root` mediante `sudo` |
| **`state=present`** | Garantiza que el paquete esté instalado |
| **`update_cache=yes`** | Refresca el índice `apt` antes de instalar |
| **Idempotencia** | Ansible no reinstala paquetes que ya están presentes |

### Evolución entre ejemplos

```
001_apt         → módulo apt básico, sin privilegios explícitos
002_become      → añade become: true para escalada de privilegios
003_with_items  → añade with_items para instalar múltiples paquetes
                  + nuevo playbook para el grupo webserver
```

---

## 🔗 Recursos relacionados

- [Documentación oficial de `with_items` y bucles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html)
- [Documentación oficial del módulo `apt`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Documentación oficial de `become`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)
- [Repositorio completo: startusingansible](https://github.com/agile611/startusingansible)