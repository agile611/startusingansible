# 004_services — Gestión de servicios con el módulo `service`

Este ejemplo introduce el módulo `service` de Ansible, que permite
**arrancar, detener, reiniciar y habilitar servicios del sistema**
(systemd/init.d). Es la evolución natural de los ejemplos anteriores:
tras instalar los paquetes con `apt` y `with_items`, ahora nos aseguramos
de que los servicios correspondientes estén **activos y habilitados**
para arrancar automáticamente con el sistema.

---

## 🗂️ Estructura del ejemplo

```
examples/004_services/
├── database.yml       # Instala MySQL y gestiona el servicio mysql
├── loadbalancer.yml   # Instala Nginx y gestiona el servicio nginx
└── webserver.yml      # Instala Apache2 + dependencias y gestiona el servicio apache2
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

## 🔑 Concepto clave: módulo `service`

El módulo `service` de Ansible permite gestionar el **estado de los
servicios del sistema operativo** (systemd, SysVinit, etc.) de forma
declarativa.

### Parámetros principales

| Parámetro | Valores posibles | Descripción |
|---|---|---|
| `name` | nombre del servicio | Nombre del servicio a gestionar |
| `state` | `started`, `stopped`, `restarted`, `reloaded` | Estado deseado del servicio |
| `enabled` | `yes` / `no` | Si debe arrancar automáticamente al inicio del sistema |

### ¿Cómo funciona?

```yaml
- name: ensure mysql is running
  service:
    name: mysql
    state: started
    enabled: yes
```

Ansible comprueba el estado actual del servicio:
- Si **no está corriendo** → lo arranca (`systemctl start mysql`).
- Si **ya está corriendo** → no hace nada (idempotente).
- Si `enabled: yes` → lo habilita en el arranque (`systemctl enable mysql`).

### Diferencia entre `state` y `enabled`

| Parámetro | Controla | Persistencia |
|---|---|---|
| `state: started` | Si el servicio está corriendo **ahora** | Solo sesión actual |
| `enabled: yes` | Si arranca **automáticamente** al reiniciar | Permanente |

> **Buena práctica:** Usar siempre ambos juntos para garantizar que el
> servicio esté activo tanto en el momento de la ejecución como tras
> un reinicio del servidor.

---

## 📋 Playbooks

### `database.yml` — Instalar MySQL y arrancar el servicio

Instala `default-mysql-server` y se asegura de que el servicio `mysql`
esté activo y habilitado en el arranque.

```yaml
---
- hosts: database
  become: true
  tasks:
    - name: install default-mysql-server
      apt: name=default-mysql-server state=present update_cache=yes

    - name: ensure mysql is running
      service:
        name: mysql
        state: started
        enabled: yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.20` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Ejecuta `apt update` + `apt install default-mysql-server`.
4. Comprueba si el servicio `mysql` está corriendo:
   - Si no → ejecuta `systemctl start mysql`.
5. Habilita el servicio para que arranque con el sistema:
   - Ejecuta `systemctl enable mysql`.

---

### `loadbalancer.yml` — Instalar Nginx y arrancar el servicio

Instala `nginx` y se asegura de que el servicio `nginx` esté activo
y habilitado en el arranque.

```yaml
---
- hosts: loadbalancer
  become: true
  tasks:
    - name: install nginx
      apt: name=nginx state=present update_cache=yes

    - name: ensure nginx is running
      service:
        name: nginx
        state: started
        enabled: yes
```

**¿Qué hace exactamente?**

1. Se conecta por SSH a `192.168.11.30` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Ejecuta `apt update` + `apt install nginx`.
4. Comprueba si el servicio `nginx` está corriendo:
   - Si no → ejecuta `systemctl start nginx`.
5. Habilita el servicio: `systemctl enable nginx`.

---

### `webserver.yml` — Instalar la pila web y arrancar Apache ⭐

Instala los cuatro paquetes de la pila web con `with_items` y se asegura
de que el servicio `apache2` esté activo y habilitado.

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

    - name: ensure apache2 is running
      service:
        name: apache2
        state: started
        enabled: yes
```

**¿Qué instala exactamente?**

| Paquete | Descripción |
|---|---|
| `apache2` | Servidor web Apache |
| `libapache2-mod-wsgi-py3` | Módulo WSGI para ejecutar apps Python en Apache |
| `python3-pip-whl` | Soporte de paquetes `.whl` para pip |
| `python3-virtualenv` | Entornos virtuales Python aislados |

**¿Qué hace exactamente paso a paso?**

1. Se conecta por SSH a `192.168.11.40` como usuario `vagrant`.
2. Eleva privilegios a `root` mediante `sudo`.
3. Itera sobre la lista de 4 paquetes e instala cada uno con `apt`.
4. Comprueba si el servicio `apache2` está corriendo:
   - Si no → ejecuta `systemctl start apache2`.
5. Habilita el servicio: `systemctl enable apache2`.

---

## ▶️ Ejecución

> **Requisito previo:** Las máquinas virtuales deben estar levantadas con
> Vagrant y el usuario `vagrant` debe tener permisos de `sudo` sin contraseña.

### 1. Instalar MySQL y arrancar el servicio en el servidor de base de datos

```bash
ansible-playbook -i hosts -u vagrant examples/004_services/database.yml
```

### 2. Instalar Nginx y arrancar el servicio en el balanceador de carga

```bash
ansible-playbook -i hosts -u vagrant examples/004_services/loadbalancer.yml
```

### 3. Instalar la pila web y arrancar Apache en el servidor web

```bash
ansible-playbook -i hosts -u vagrant examples/004_services/webserver.yml
```

### Desglose de los flags del comando

| Flag | Valor | Descripción |
|---|---|---|
| `-i` | `hosts` | Especifica el fichero de inventario a usar |
| `-u` | `vagrant` | Usuario SSH con el que conectarse a los nodos |
| (último arg) | `examples/004_services/*.yml` | Ruta al playbook a ejecutar |

---

## 💡 Conceptos clave aprendidos

| Concepto | Descripción |
|---|---|
| **Módulo `service`** | Gestiona el estado de servicios del sistema (systemd) |
| **`state: started`** | Garantiza que el servicio esté corriendo ahora |
| **`state: stopped`** | Garantiza que el servicio esté detenido |
| **`state: restarted`** | Reinicia el servicio siempre (útil tras cambios de config) |
| **`enabled: yes`** | Habilita el servicio para arrancar con el sistema |
| **`with_items`** | Bucle para instalar múltiples paquetes en una tarea |
| **`become: true`** | Escalada de privilegios a `root` mediante `sudo` |
| **Idempotencia** | Si el servicio ya corre, Ansible no hace nada |

### Evolución entre ejemplos

```
001_apt         → módulo apt básico
002_become      → añade become: true (escalada de privilegios)
003_with_items  → añade with_items (bucles sobre listas)
004_services    → añade módulo service (gestión de servicios)
```

---

## 🔗 Recursos relacionados

- [Documentación oficial del módulo `service`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)
- [Documentación oficial del módulo `apt`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html)
- [Documentación oficial de `with_items` y bucles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html)
- [Repositorio completo: startusingansible](https://github.com/agile611/startusingansible)
