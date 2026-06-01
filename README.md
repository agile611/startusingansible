[![Agile611](https://www.agile611.com/wp-content/uploads/2020/09/cropped-logo-header.png)](http://www.agile611.com/)

# Agile611 Ansible Training

Este repositorio contiene los ejemplos de código de las herramientas de gestión de configuración Ansible. Utiliza Vagrant o Docker para demostrar estas herramientas en la práctica.

---

## Requisitos

### Opción A — Docker
- **git**: Necesario para clonar el código.
- **Docker** >= 24.x
- **Docker Compose** >= 2.x

### Opción B — Vagrant + VirtualBox
- **git**: Necesario para clonar el código.
- **Vagrant**: Este repositorio usa una box de Vagrant basada en Debian, y se usará APT para instalar Ansible.
- **VirtualBox**: Es el motor para virtualizar el entorno.

---

## Código de ejemplo

Clona el repositorio:

```bash
git clone https://www.github.com/agile611/startusingansible.git
```
---

## Opción A — Configuración con Docker

### Arquitectura

```
┌─────────────────────────────────────────────────┐
│              red: 192.168.11.0/24               │
│                                                 │
│  ansible       192.168.11.10  (nodo control)    │
│  database      192.168.11.20  (MySQL/MariaDB)   │
│  loadbalancer  192.168.11.30  (Nginx LB)        │
│  webserver     192.168.11.40  (Apache/WordPress)│
└─────────────────────────────────────────────────┘
```

### Despliegue inicial

**1. Genera las claves SSH:**

```bash
mkdir -p ssh
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""
```

**2. Elimina redes Docker residuales:**

```bash
docker network prune -f
```

**3. Construye y arranca los contenedores:**

```bash
docker compose build
docker compose up -d
```

**4. Verifica que todo funciona:**

```bash
docker compose ps

ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.20
ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.30
ssh -i ssh/id_rsa -o StrictHostKeyChecking=no vagrant@192.168.11.40
```

### Acceder al nodo de control

```bash
docker exec -it ansible bash
```

### Gestión de los contenedores

| Acción | Comando |
|---|---|
| Ver estado | `docker compose ps` |
| Parar todo | `docker compose down` |
| Reiniciar un nodo | `docker compose restart webserver` |
| Entrar en un nodo | `docker exec -it database bash` |
| Ver logs | `docker compose logs -f ansible` |
| Limpieza total | `docker compose down --rmi all --volumes --remove-orphans && docker system prune -af` |

### Verificar limpieza completa

Después de ejecutar la limpieza, verifica que todo esté limpio:

```bash
docker compose down --rmi all --volumes --remove-orphans && docker system prune -af
```

Comprueba que ha quedado limpio:

```bash
docker images
docker ps -a
docker volume ls
```

Los tres comandos deberían retornar listas vacías.

---

### Configuración avanzada con `build-docker-compose.yml`

Si necesitas una configuración más robusta con características avanzadas, utiliza el archivo `build-docker-compose.yml` en lugar del `docker-compose.yml` estándar.

#### Diferencias principales

| Característica | `docker-compose.yml` | `build-docker-compose.yml` |
|---|---|---|
| Volúmenes compartidos | Mínimos | ✅ Volúmenes host, workspace sync |
| tmpfs (RAM disk) | No | ✅ `/run`, `/run/lock`, `/tmp` |
| Capabilities | No | ✅ `NET_ADMIN` para laboratorios |
| DNS personalizado | No | ✅ Google DNS (8.8.8.8) |
| Modo privilegiado | No | ✅ Acceso completo a recursos |
| Ideal para | Pruebas rápidas | Desarrollo y laboratorios |

#### Cuándo usar `build-docker-compose.yml`

- **Desarrollo local intensivo**: Necesitas acceso completo a recursos del sistema.
- **Laboratorios de networking**: Requiere `NET_ADMIN` para manipular interfaces de red.
- **Sincronización de archivos**: Sincroniza cambios locales con los contenedores en tiempo real.
- **Simulación de entornos reales**: Comportamiento más cercano a máquinas virtuales.

#### Uso de `build-docker-compose.yml`

Para usar la configuración avanzada, especifica el archivo al ejecutar Docker Compose:

```bash
docker compose -f build-docker-compose.yml build
docker compose -f build-docker-compose.yml up -d
```

O crea un alias para simplificar:

```bash
alias dc-build='docker compose -f build-docker-compose.yml'
dc-build ps
dc-build logs -f ansible
```

#### Características principales

**1. Volúmenes compartidos**
```yaml
volumes:
  - ./ssh:/home/vagrant/.ssh/host_keys       # Claves SSH persistentes
  - .:/home/vagrant/workspace                # Sincroniza proyecto completo
  - /home/vagrant/sync:/home/vagrant/sync    # Directorio de sincronización
```

**2. tmpfs (sistema de archivos en RAM)**
```yaml
tmpfs:
  - /run
  - /run/lock
  - /tmp
```
Mejora el rendimiento de operaciones de lectura/escritura frecuentes.

**3. Capabilities y privilegios**
```yaml
privileged: true                    # Acceso root completo
cgroup: host                        # Acceso a cgroups del host
cap_add:
  - NET_ADMIN                       # Permisos de administración de red
```

**4. DNS personalizado**
```yaml
dns:
  - 8.8.8.8
  - 8.8.4.4
```

---

## Probar el entorno

Configura el inventario de Ansible en el nodo de control:

```bash
mkdir example_ansible
nano example_ansible/hosts
```

**Genera un fichero hosts** y añade:

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

Comprueba que todo funciona:

```bash
cd example_ansible
ansible -i hosts -u vagrant -m ping all
```

Respuesta esperada:

```
192.168.11.20 | SUCCESS => { "ping": "pong" }
192.168.11.30 | SUCCESS => { "ping": "pong" }
192.168.11.40 | SUCCESS => { "ping": "pong" }
```

---

## Configuración inicial y primer fichero YAML

Crea el fichero `request.yml`:

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

Ejecuta el playbook:

```bash
ansible-playbook -i hosts/all request.yml --list-hosts --list-tasks
ansible-playbook -i hosts/all request.yml
```

### Ejemplos adicionales

Hay varios ejemplos disponibles en la carpeta `examples/`, que cubren diferentes aspectos del uso de Ansible.

---

## Opción B — Configuración con Vagrant

### Configuración inicial

Inicia el entorno, que requiere cuatro boxes (Ansible, Loadbalancer, Database, Webserver):

```bash
vagrant up
vagrant ssh ansible
```

Crea una clave SSH para conectarte a las VMs sin contraseña:

```bash
ssh-keygen
cat /home/vagrant/.ssh/id_rsa.pub
```

Copia la clave pública a las VMs y configura las authorized keys:

```bash
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.20
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.30
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.40
```

Verifica la conexión SSH:

```bash
ssh vagrant@192.168.11.20
```

Si se solicita contraseña, el usuario es `vagrant` y la contraseña es `vagrant`.

### Nota importante

El orden de prioridad del fichero de configuración es el siguiente:

1. **ANSIBLE_CONFIG** (variable de entorno)
2. **ansible.cfg** (carpeta actual)
3. **~/.ansible.cfg** (home del usuario)
4. **/etc/ansible/ansible.cfg** (fichero general)

---

## Solución de problemas

### Vagrant: problemas de aprovisionamiento

Si encuentras problemas al aprovisionar la box, puedes descargarla directamente y añadirla a Vagrant.

### Problemas de red comunes

Si tienes proxies o VPNs activos en tu máquina, es posible que Vagrant o Docker no puedan aprovisionar el entorno correctamente. Comprueba tu conectividad antes de empezar.

### Docker: "No route to host"

```bash
# Comprueba si hay rutas en conflicto
ip route | grep 192.168.11

# Si aparece virbr* con la misma subred, elimínala
sudo virsh net-list --all
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
# Verifica que el contenedor corre y tiene SSH activo
docker exec -it ansible bash -c "systemctl status ssh"

# Regenera las claves si es necesario
ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N ""
docker compose down && docker compose up -d
```

---

## Soporte

Este tutorial ha sido publicado en el dominio público por [Agile611](http://www.agile611.com/) bajo la licencia Creative Commons Attribution-NonCommercial 4.0 International.

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC_BY--NC_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/)

Este fichero README fue escrito originalmente por [Guillem Hernández Sola](https://www.linkedin.com/in/guillemhs/) y se publica igualmente en el dominio público.

Contacta con Agile611 para más información.

* [Agile611](http://www.agile611.com/)
* Carrer Laureà Miró 309
* 08950 Esplugues de Llobregat (Barcelona)