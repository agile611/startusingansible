# 002_become — Escalada de privilegios con `become` en Ansible

Este ejemplo introduce el concepto de **escalada de privilegios** en Ansible
mediante la directiva `become: true`. Es la evolución natural del ejemplo
`001_apt`: los mismos paquetes se instalan, pero ahora Ansible eleva
automáticamente los permisos a `root` (usando `sudo`) para poder ejecutar
`apt install` sin necesidad de conectarse directamente como superusuario.

---

## 🗂️ Estructura del ejemplo

```
examples/002_become/
├── database.yml       # Instala default-mysql-server con become en 'database'
└── loadbalancer.yml   # Instala nginx con become en 'loadbalancer'
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
| `ansible_user` | `vagrant` | Usuario SSH con el que se conecta Ansible |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación de host SSH |

### Grupos de servidores

| Grupo | IP | Rol |
|---|---|---|
| `database` | `192.168.11.20` | Servidor de base de datos |
| `loadbalancer` | `192.168.11.30` | Balanceador de carga |
| `webserver` | `192.168.11.40` | Servidor web (no usado en este ejemplo) |

---

## 🔑 Concepto clave: `become: true`

La directiva `become: true` le indica a Ansible que debe **elevar los
privilegios** del usuario de conexión antes de ejecutar las tareas.

### ¿Cómo funciona?

```
Usuario SSH (vagrant)  →  sudo  →  root
```

1. Ansible se conecta al nodo remoto como el usuario definido (`vagrant`).
2. Antes de ejecutar cada tarea, invoca `sudo` para convertirse en `root`.
3. Las tareas que requieren permisos de administrador (como `apt install`)
   se ejecutan con éxito.

### ¿Por qué es necesario?

Sin `become: true`, el usuario `vagrant` no tiene permisos para instalar
paquetes del sistema. Ansible devolvería un error de permisos:

```
FAILED! => {"msg": "apt requires root privileges"}
```

### Comparativa con el ejemplo anterior (`001_apt`)

| Característica | `001_apt` | `002_become` |
|---|---|---|
| Usuario de conexión | `vagrant` | `vagrant` |
| Escalada de privilegios | ❌ No | ✅ `become: true` |
| Paquete MySQL | `mysql-server` | `default-mysql-server` |
| Paquete Nginx | `nginx` | `nginx` |
| Requiere sudo en el nodo | No (asume root) | Sí (eleva con sudo) |

> **Nota:** El paquete cambia de `mysql-server` a `default-mysql-server`.
> Este último es un metapaquete de Debian/Ubuntu que instala la versión
> predeterminada del sistema, siendo más portable entre distribuciones.

---

## 📋 Playbooks

### `database.yml` — Instalar MySQL con privilegios elevados

Instala el paquete `default-mysql-server` en el grupo `database` elevando
privilegios con `become: true`.

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
2. Eleva privilegios a `root` mediante `sudo` (`become: true`).
3. Ejecuta `apt update` para refrescar el índice de paquetes.
4. Ejecuta `apt install default-mysql-server` como `root`.
5. Si el paquete ya está instalado, Ansible reporta `ok` sin hacer nada
   (comportamiento **idempotente**).

---

### `loadbalancer.yml` — Instalar Nginx con privilegios elevados

Instala el paquete `nginx` en el grupo `loadbalancer` elevando privilegios
con `become: true`.

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
2. Eleva privilegios a `root` mediante `sudo` (`become: true`).
3. Ejecuta `apt update` para refrescar el índice de paquetes.
4. Ejecuta `apt install nginx` como `root`.
5. Si el paquete ya está instalado, Ansible reporta `ok` sin hacer nada.

---

## ▶️ Ejecución

> **Requisito previo:** Las máquinas virtuales deben estar levantadas con
> Vagrant, accesibles por SSH y el usuario `vagrant` debe tener permisos
> de `sudo` sin contraseña (configuración habitual en boxes de Vagrant).

### 1. Instalar MySQL en el servidor de base de datos

```bash
ansible-playbook -i hosts -u vagrant examples/002_become/database.yml
```

### 2. Instalar Nginx en el balanceador de carga

```bash
ansible-playbook -i hosts -u vagrant examples/002_become/loadbalancer.yml
```

### Desglose de los flags del comando

| Flag | Valor | Descripción |
|---|---|---|
| `-i` | `hosts` | Especifica el fichero de inventario a usar |
| `-u` | `vagrant` | Usuario SSH con el que conectarse a los nodos |
| (último arg) | `examples/002_become/*.yml` | Ruta al playbook a ejecutar |

> **Tip:** Si el usuario remoto necesita contraseña para `sudo`, se puede
> añadir el flag `--ask-become-pass` (o `-K`) al comando:
> ```bash
> ansible-playbook -i hosts -u vagrant --ask-become-pass examples/002_become/database.yml
> ```

---

## 💡 Conceptos clave aprendidos

| Concepto | Descripción |
|---|---|
| **`become: true`** | Activa la escalada de privilegios para el play completo |
| **`become_method`** | Método de escalada (por defecto: `sudo`) |
| **`become_user`** | Usuario al que escalar (por defecto: `root`) |
| **`--ask-become-pass`** | Flag para pedir la contraseña de sudo en tiempo de ejecución |
| **`default-mysql-server`** | Metapaquete Debian/Ubuntu para la versión MySQL por defecto |
| **Idempotencia** | Ansible no repite acciones si el estado ya es el deseado |

### Ámbitos donde se puede usar `become`

`become` se puede declarar en tres niveles de granularidad:

```yaml
# Nivel play (afecta a todas las tareas del play)
- hosts: database
  become: true
  tasks: ...

# Nivel tarea (afecta solo a esa tarea)
- hosts: database
  tasks:
    - name: install package
      apt: name=nginx state=present
      become: true

# Nivel bloque (afecta a un grupo de tareas)
- hosts: database
  tasks:
    - block:
        - name: install package
          apt: name=nginx state=present
      become: true
```

---

## 🔗 Recursos relacionados

- [Documentación oficial de `become`](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)
- [Documentación oficial del módulo apt](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Repositorio completo: startusingansible](https://github.com/agile611/startusingansible)