[![Agile611](https://www.agile611.com/wp-content/uploads/2020/09/cropped-logo-header.png)](http://www.agile611.com/)

# Agile611 — Ansible Training

Repositorio de ejemplos prácticos para aprender Ansible.  
Usa **Docker** o **Vagrant** como entorno de laboratorio.

---

## 📋 Requisitos

| Herramienta | Opción A — Docker | Opción B — Vagrant |
|---|---|---|
| `git` | ✅ | ✅ |
| Docker >= 24.x | ✅ | ❌ |
| Docker Compose >= 2.x | ✅ | ❌ |
| Vagrant | ❌ | ✅ |
| VirtualBox | ❌ | ✅ |

```bash
git clone https://www.github.com/agile611/startusingansible.git
cd startusingansible
```

---

## 🏗️ Arquitectura del Entorno

```
┌─────────────────────────────────────────────────┐
│              red: 10.11.12.0/24                 │
│                                                 │
│  ansible       10.11.12.10  (nodo control)      │
│  database      10.11.12.20  (MySQL/MariaDB)     │
│  loadbalancer  10.11.12.30  (Nginx LB)          │
│  webserver     10.11.12.40  (Apache)            │
└─────────────────────────────────────────────────┘
```

---

## 🐳 Opción A — Docker

### 🔨 Construir y publicar la imagen (desde cero)

Si necesitas reconstruir la imagen base y publicarla en Docker Hub:

```bash
# Construir la imagen sin caché
docker build --no-cache -t guillemhs/ansible-node-systemd .

# Etiquetar como latest
docker tag guillemhs/ansible-node-systemd guillemhs/ansible-node-systemd:latest

# Publicar en Docker Hub
docker push guillemhs/ansible-node-systemd:latest
```

> Necesitas tener sesión iniciada en Docker Hub (`docker login`) antes de hacer el push.

---

### Arranque rápido

```bash
# 1. Genera las claves SSH
mkdir -p ssh
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""

# 2. Limpia redes residuales
docker network prune -f

# 3. Arranca los contenedores
docker compose up -d

# 4. Espera a que sshd esté listo
sleep 3

# 5. Distribuye las claves SSH
./setup-ssh.sh

# 6. Verifica el estado
docker compose ps
```

### `setup-ssh.sh`

Este script copia la clave privada al nodo de control e inyecta la clave pública en todos los nodos gestionados:

```bash
#!/bin/bash
# setup-ssh.sh
# Distributes SSH keys between the Ansible control node and managed nodes

set -e

SSH_DIR="./ssh"
CONTROL_NODE="ansible"
MANAGED_NODES=("database" "loadbalancer" "webserver")

echo "🔑 Setting up SSH keys..."

# --- Control node ---
echo "📋 Copying private key to control node: $CONTROL_NODE"
docker exec "$CONTROL_NODE" bash -c "
  mkdir -p /home/vagrant/.ssh &&
  chmod 700 /home/vagrant/.ssh &&
  cp /home/vagrant/.ssh/host_keys/id_rsa /home/vagrant/.ssh/id_rsa &&
  cp /home/vagrant/.ssh/host_keys/id_rsa.pub /home/vagrant/.ssh/id_rsa.pub &&
  chmod 600 /home/vagrant/.ssh/id_rsa &&
  chown -R vagrant:vagrant /home/vagrant/.ssh
"

# --- Managed nodes ---
PUB_KEY=$(cat "$SSH_DIR/id_rsa.pub")

for container in "${MANAGED_NODES[@]}"; do
  echo "🔓 Injecting public key into: $container"
  docker exec "$container" bash -c "
    mkdir -p /home/vagrant/.ssh &&
    chmod 700 /home/vagrant/.ssh &&
    echo '$PUB_KEY' >> /home/vagrant/.ssh/authorized_keys &&
    chmod 600 /home/vagrant/.ssh/authorized_keys &&
    chown -R vagrant:vagrant /home/vagrant/.ssh
  "
done

echo "✅ SSH setup complete."
```

```bash
chmod +x setup-ssh.sh
./setup-ssh.sh
```

### Acceder al nodo de control

```bash
docker exec -it ansible bash
```

### Gestión de contenedores

| Acción | Comando |
|---|---|
| Ver estado | `docker compose ps` |
| Parar todo | `docker compose down` |
| Reiniciar un nodo | `docker compose restart webserver` |
| Entrar en un nodo | `docker exec -it database bash` |
| Ver logs | `docker compose logs -f ansible` |
| Limpieza total | `docker compose down --rmi all --volumes --remove-orphans && docker system prune -af` |

> Tras la limpieza total, `docker images`, `docker ps -a` y `docker volume ls`
> deben devolver listas vacías.

---

### ⚙️ Configuración avanzada — `build-docker-compose.yml`

Para laboratorios más complejos o desarrollo local intensivo,
usa `build-docker-compose.yml` en lugar del `docker-compose.yml` estándar.
Este fichero construye la imagen localmente en vez de descargarla del registro.

| Característica | `docker-compose.yml` | `build-docker-compose.yml` |
|---|---|---|
| Imagen | Descargada del registro | ✅ Construida localmente |
| Volúmenes compartidos | Mínimos | ✅ Host + workspace sync |
| **Ideal para** | Pruebas rápidas | Desarrollo y laboratorios |

```bash
docker compose -f build-docker-compose.yml build
docker compose -f build-docker-compose.yml up -d
```

---

## 📦 Opción B — Vagrant (carpeta vagrantfiles)

```bash
# Arranca las 4 VMs (ansible, database, loadbalancer, webserver)
vagrant up
vagrant ssh ansible

# Genera clave SSH y cópiala a las VMs
ssh-keygen
ssh-copy-id vagrant@10.11.12.20
ssh-copy-id vagrant@10.11.12.30
ssh-copy-id vagrant@10.11.12.40
```

> Si se solicita contraseña: usuario `vagrant`, contraseña `vagrant`.

### Prioridad de configuración de Ansible

```
1. $ANSIBLE_CONFIG     (variable de entorno)
2. ./ansible.cfg       (carpeta actual)
3. ~/.ansible.cfg      (home del usuario)
4. /etc/ansible/ansible.cfg
```

---

## 🧪 Verificar el Entorno

### Fichero de inventario (`hosts`)

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=vagrant
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[database]
10.11.12.20

[loadbalancer]
10.11.12.30

[webserver]
10.11.12.40
```

### Ping a todos los nodos

```bash
ansible -i hosts -u vagrant -m ping all
```

Respuesta esperada:

```
10.11.12.20 | SUCCESS => { "ping": "pong" }
10.11.12.30 | SUCCESS => { "ping": "pong" }
10.11.12.40 | SUCCESS => { "ping": "pong" }
```

---

## 🚀 Primer Playbook

Crea `request.yml`:

```yaml
---
- hosts: webserver
  tasks:
    - name: What system are you?
      command: uname -a
      register: info
    - name: Print full output
      debug:
        var: info
    - name: Print stdout only
      debug:
        var: info.stdout
    - name: What is your hostname?
      command: hostname
      register: info
    - name: Print hostname
      debug:
        var: info.stdout
```

```bash
# Listar hosts y tareas sin ejecutar
ansible-playbook -i hosts request.yml --list-hosts --list-tasks

# Ejecutar el playbook
ansible-playbook -i hosts request.yml
```

---

## 📚 Ejemplos — carpeta `examples/`

Los ejemplos están numerados y ordenados por dificultad creciente.
Cada carpeta contiene su propio `playbook.yml`, `hosts` y recursos necesarios.

| Ejemplo | Concepto |
|---|---|
| `001` – `010` | Comandos básicos, módulos `ping`, `command`, `debug` |
| `011` – `020` | Variables, `register`, `facts`, `set_fact` |
| `021` – `030` | Roles, `handlers`, `notify`, `tags` |
| `031` – `033` | Templates Jinja2, ficheros dinámicos |
| `034` | Condicionales `when` |
| `035`+ | Bucles, `with_items`, `loop`, `include_tasks` |

Estructura de ejecución de cualquier ejemplo:

```bash
cd examples/<número_ejemplo>
ansible-playbook -i hosts -u vagrant playbook.yml
```

---

## 🔧 Solución de Problemas

### Docker: "No route to host"
```bash
ip route | grep 10.11.12
# Si aparece virbr* con la misma subred:
sudo virsh net-destroy <nombre>
sudo virsh net-undefine <nombre>
```

### Docker: "Pool overlaps with other one"
```bash
docker network prune -f
docker compose up -d
```

### Docker: SSH rechazado
```bash
docker exec -it ansible bash -c "systemctl status ssh"
# Si es necesario, regenera claves y reinicia:
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""
docker compose down && docker compose up -d
./setup-ssh.sh
```

### Vagrant: problemas de aprovisionamiento
- Desactiva proxies o VPNs activos antes de arrancar el entorno.
- Descarga la box manualmente si el aprovisionamiento falla.

---

## 📄 Licencia

Publicado por [Agile611](http://www.agile611.com/) bajo licencia
**Creative Commons Attribution-NonCommercial 4.0 International**.

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC_BY--NC_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/)

README escrito por [Guillem Hernández Sola](https://www.linkedin.com/in/guillemhs/).

**Contacto:**
- 🌐 [agile611.com](http://www.agile611.com/)
- 📍 Carrer Laureà Miró 309, 08950 Esplugues de Llobregat (Barcelona)