# 001_apt — Introducción al módulo `apt` de Ansible

Este ejemplo muestra cómo usar el módulo `apt` de Ansible para instalar
paquetes en grupos de servidores definidos en un inventario. Es el punto
de partida ideal para entender cómo Ansible gestiona software en sistemas
basados en Debian/Ubuntu.

---

## 🗂️ Estructura del ejemplo

```
examples/001_apt/
├── database.yml       # Instala MySQL en el grupo 'database'
├── loadbalancer.yml   # Instala Nginx en el grupo 'loadbalancer'
└── hostname.yml       # Obtiene el hostname de todos los servidores
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

### Variables globales (`[all:vars]`)

| Variable | Valor | Descripción |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Usa Python 3 en los nodos remotos |
| `ansible_user` | `vagrant` | Usuario SSH para conectarse |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación de host SSH |

### Grupos de servidores

| Grupo | IP | Rol |
|---|---|---|
| `database` | `192.168.11.20` | Servidor de base de datos |
| `loadbalancer` | `192.168.11.30` | Balanceador de carga |
| `webserver` | `192.168.11.40` | Servidor web (no usado en este ejemplo) |

---

## 📋 Playbooks

### `database.yml` — Instalar MySQL

Instala el paquete `mysql-server` en el grupo `database` usando el módulo
`apt`. El parámetro `update_cache=yes` equivale a ejecutar `apt update`
antes de instalar.

```yaml
---
- hosts: database
  tasks:
    - name: install mysql-server
      apt: name=mysql-server state=present update_cache=yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.20` (grupo `database`).
2. Ejecuta `apt update` para refrescar el índice de paquetes.
3. Ejecuta `apt install mysql-server` si el paquete no está ya instalado.
4. Si el paquete ya estaba instalado, Ansible reporta `ok` sin hacer nada
   (comportamiento **idempotente**).

---

### `loadbalancer.yml` — Instalar Nginx

Instala el paquete `nginx` en el grupo `loadbalancer`, también actualizando
la caché de paquetes antes de instalar.

```yaml
---
- hosts: loadbalancer
  tasks:
    - name: install nginx
      apt: name=nginx state=present update_cache=yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.30` (grupo `loadbalancer`).
2. Ejecuta `apt update` para refrescar el índice de paquetes.
3. Ejecuta `apt install nginx` si el paquete no está ya instalado.
4. Si el paquete ya estaba instalado, Ansible reporta `ok` sin hacer nada.

---

### `hostname.yml` — Obtener el hostname de todos los servidores

Ejecuta el comando `hostname` en **todos** los servidores del inventario
usando el módulo `command`. Es útil para verificar la conectividad y
confirmar la identidad de cada máquina.

```yaml
---
- hosts: all
  tasks:
    - name: get server hostname
      command: hostname
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a los tres servidores: `192.168.11.20`,
   `192.168.11.30` y `192.168.11.40`.
2. Ejecuta el comando `hostname` en cada uno.
3. Muestra el resultado en la salida estándar de Ansible.
4. No instala ni modifica nada — es una tarea de **solo lectura**.

---

## ▶️ Ejecución

> **Requisito previo:** Las máquinas virtuales deben estar levantadas con
> Vagrant y accesibles por SSH desde el nodo de control.

### 1. Instalar MySQL en el servidor de base de datos

```bash
ansible-playbook -i hosts -u vagrant examples/001_apt/database.yml
```

### 2. Instalar Nginx en el balanceador de carga

```bash
ansible-playbook -i hosts -u vagrant examples/001_apt/loadbalancer.yml
```

### 3. Verificar el hostname de todos los servidores

```bash
ansible-playbook -i hosts -u vagrant examples/001_apt/hostname.yml
```

### Desglose de los flags del comando

| Flag | Valor | Descripción |
|---|---|---|
| `-i` | `hosts` | Especifica el fichero de inventario a usar |
| `-u` | `vagrant` | Usuario SSH con el que conectarse a los nodos |
| (último arg) | `examples/001_apt/*.yml` | Ruta al playbook a ejecutar |

> **Nota:** El flag `-u vagrant` es redundante aquí porque `ansible_user=vagrant`
> ya está definido en `[all:vars]` del inventario. Se incluye explícitamente
> como buena práctica en entornos de aprendizaje.

---

## 💡 Conceptos clave aprendidos

| Concepto | Descripción |
|---|---|
| **Módulo `apt`** | Gestiona paquetes en sistemas Debian/Ubuntu |
| **`state=present`** | Garantiza que el paquete esté instalado |
| **`update_cache=yes`** | Refresca el índice de paquetes antes de instalar |
| **`hosts: all`** | Aplica la tarea a todos los grupos del inventario |
| **Módulo `command`** | Ejecuta comandos de shell arbitrarios en los nodos |
| **Inventario (`-i hosts`)** | Fichero que define los servidores y sus grupos |
| **Idempotencia** | Ansible no repite acciones si el estado ya es el deseado |

---

## 🔗 Recursos relacionados

- [Documentación oficial del módulo apt](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Documentación oficial del módulo command](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)
- [Repositorio completo: startusingansible](https://github.com/agile611/startusingansible)