# 🐳 Entorno Docker para prácticas de Ansible

Entorno basado en **Docker** que sustituye Vagrant/VirtualBox para simular
4 nodos Ubuntu 24.04 interconectados vía SSH. Compatible al 100% con los
repositorios del curso [startusingansible](https://git.agile611.com/Agile611/startusingansible)
y [wordpress-ansible](https://git.agile611.com/Agile611/wordpress-ansible).

---

## 📋 Requisitos

- Docker >= 24.x
- Docker Compose >= 2.x
- Git

---

## 🗺️ Arquitectura

```
┌─────────────────────────────────────────────────┐
│              red: 192.168.11.0/24               │
│                                                 │
│  ansible       192.168.11.10  (nodo control)   │
│  database      192.168.11.20  (MySQL/MariaDB)   │
│  loadbalancer  192.168.11.30  (Nginx LB)        │
│  webserver     192.168.11.40  (Apache/WordPress)│
└─────────────────────────────────────────────────┘
```

---

## 🚀 Despliegue inicial

### 1. Clona este repositorio

```bash
git clone https://git.agile611.com/Agile611/startusingansible.git
cd startusingansible
```

### 2. Genera las claves SSH

```bash
mkdir -p ssh
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""
```

### 3. Elimina redes Docker residuales

```bash
docker network prune -f
```

### 4. Construye y arranca los contenedores

```bash
docker compose build
docker compose up -d
```

### 5. Verifica que todo funciona

```bash
docker compose ps

ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.20
ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.30
ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.40
```

---

## 📦 Repo 1 — startusingansible

> https://git.agile611.com/Agile611/startusingansible

### Acceder al nodo de control

```bash
docker exec -it ansible bash
```

### Crear el inventario

```bash
mkdir -p example_ansible/hosts
cat > example_ansible/hosts/all << 'EOF'
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
EOF
```

### Test de conectividad (ping a todos los nodos)

```bash
cd example_ansible
ansible -i hosts/all -m ping all
```

Respuesta esperada:
```
192.168.11.20 | SUCCESS => { "ping": "pong" }
192.168.11.30 | SUCCESS => { "ping": "pong" }
192.168.11.40 | SUCCESS => { "ping": "pong" }
```

### Primer playbook — request.yml

```yaml
---
- hosts: webserver
  tasks:
    - name: What system are you?
      command: uname -a
      register: info

    - name: print var
      debug:
        var: info

    - name: print field
      debug:
        var: info.stdout

    - name: What your name?
      command: hostname
      register: info

    - name: Give me your name
      debug:
        var: info.stdout
```

```bash
# Lista hosts y tareas sin ejecutar
ansible-playbook -i hosts/all request.yml --list-hosts --list-tasks

# Ejecuta el playbook
ansible-playbook -i hosts/all request.yml
```

### Ejemplos adicionales (carpeta examples/)

```bash
# Listar los ejemplos disponibles
ls examples/

# Ejecutar un ejemplo concreto
ansible-playbook -i hosts/all examples/<nombre_ejemplo>.yml
```

---

## 🌐 Repo 2 — wordpress-ansible

> https://git.agile611.com/Agile611/wordpress-ansible

### Clona el repo dentro del contenedor ansible

```bash
docker exec -it ansible bash

git clone https://git.agile611.com/Agile611/wordpress-ansible.git
cd wordpress-ansible
```

### Estructura del proyecto

```
wordpress-ansible/
├── collections/
├── group_vars/
├── inventory/
│   └── hosts
├── roles/
├── secrets/
├── site.yml
└── ansible.sh
```

### Comprueba el inventario (inventory/hosts)

Verifica que las IPs coinciden con los contenedores:

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

### Instala las colecciones necesarias

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

### Ejecuta el despliegue completo de WordPress

```bash
# Previsualiza las tareas
ansible-playbook -i inventory/hosts site.yml --list-tasks

# Ejecuta el despliegue
ansible-playbook -i inventory/hosts site.yml
```

### Ejecuta solo un rol concreto (tag)

```bash
# Ejemplo: solo el rol de base de datos
ansible-playbook -i inventory/hosts site.yml --tags database

# Ejemplo: solo el rol de webserver
ansible-playbook -i inventory/hosts site.yml --tags webserver
```

### Verifica el despliegue

```bash
# Comprueba que MySQL corre en el nodo database
ansible -i inventory/hosts database -m shell -a "systemctl status mysql"

# Comprueba que Nginx corre en el loadbalancer
ansible -i inventory/hosts loadbalancer -m shell -a "systemctl status nginx"

# Comprueba que WordPress responde en el webserver
ansible -i inventory/hosts webserver -m shell -a "curl -s http://localhost | head -5"
```

---

## 🛠️ Gestión de los contenedores

| Acción | Comando |
|---|---|
| Ver estado | `docker compose ps` |
| Parar todo | `docker compose down` |
| Reiniciar un nodo | `docker compose restart webserver` |
| Entrar en un nodo | `docker exec -it database bash` |
| Ver logs | `docker compose logs -f ansible` |
| Limpieza total | `docker compose down && docker system prune -a --volumes -f` |

---

## 🔧 Solución de problemas

### Error: "No route to host"

```bash
# Comprueba si hay redes en conflicto
ip route | grep 192.168.11

# Si aparece virbr* con la misma subred, elimínala
sudo virsh net-list --all
sudo virsh net-destroy <nombre>
sudo virsh net-undefine <nombre>
```

### Error: "Pool overlaps with other one"

```bash
docker network prune -f
docker compose up -d
```

### SSH rechazado

```bash
# Verifica que el contenedor corre y tiene el puerto 22 activo
docker exec -it ansible bash -c "systemctl status ssh"

# Regenera las claves si es necesario
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""
docker compose down && docker compose up -d
```

---

## 📄 Licencia
Este archivo README fue escrito originalmente por [Guillem Hernández Sola](https://www.linkedin.com/in/guillemhs/) y se publica igualmente en el dominio público.
Basado en material de [Agile611](http://www.agile611.com/) bajo licencia
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).
