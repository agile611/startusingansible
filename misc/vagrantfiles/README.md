# misc/vagrantfiles — Vagrantfiles y Scripts de Aprovisionamiento

## 📋 Descripción General

La carpeta `misc/vagrantfiles` contiene una colección de **Vagrantfiles alternativos
y scripts de aprovisionamiento** para levantar el entorno de laboratorio de Ansible
usando diferentes sistemas operativos base (Debian, Ubuntu) y diferentes estrategias
de provisioning (instalación directa de Ansible o instalación de Docker).

Es el repositorio de plantillas de referencia para quien quiera adaptar el entorno
a su sistema operativo preferido o a sus necesidades específicas.

---

## 🗂️ Estructura de la Carpeta

```
misc/vagrantfiles/
├── VagrantfileDebian       # Entorno con 4 VMs basadas en Debian
├── VagrantfileUbuntu       # Entorno con 4 VMs basadas en Ubuntu
├── VagrantfileDocker       # Entorno con Vagrant + Docker como provider
├── ansible.sh              # Script de aprovisionamiento: instala Ansible
├── docker.sh               # Script de aprovisionamiento: instala Docker
├── UbuntuAnsible.sh        # Script de aprovisionamiento: Ubuntu + Ansible
├── essential_box/          # Subcarpeta con box mínima personalizada
└── multi_agent_setup/      # Subcarpeta con configuración multi-agente
```

---

## 🏗️ Arquitectura del Entorno (común a todos los Vagrantfiles)

```
┌─────────────────────────────────────────────────┐
│              red: 192.168.11.0/24               │
│                                                 │
│  control       192.168.11.10  (nodo control)    │
│  database      192.168.11.20  (MySQL/MariaDB)   │
│  loadbalancer  192.168.11.30  (Nginx LB)        │
│  webserver     192.168.11.40  (Apache)          │
└─────────────────────────────────────────────────┘
```

Todos los Vagrantfiles levantan **4 máquinas virtuales** con la misma topología
de red, diferenciándose únicamente en el sistema operativo base y el
aprovisionamiento aplicado.

---

## 📄 Ficheros Vagrantfile

### `VagrantfileDebian`

Levanta las 4 VMs usando **Debian** como sistema operativo base (`bento/debian-12`).

```ruby
Vagrant.configure("2") do |config|

  nodes = [
    { name: "control",      ip: "192.168.11.10", memory: 512, cpus: 1 },
    { name: "database",     ip: "192.168.11.20", memory: 512, cpus: 1 },
    { name: "loadbalancer", ip: "192.168.11.30", memory: 512, cpus: 1 },
    { name: "webserver",    ip: "192.168.11.40", memory: 512, cpus: 1 },
  ]

  nodes.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.box      = "bento/debian-12"
      vm.vm.hostname = node[:name]
      vm.vm.network "private_network", ip: node[:ip]
      vm.vm.synced_folder ".", "/vagrant", type: "rsync"
      vm.vm.provision "shell", path: "ansible.sh"   # Instala Ansible via APT

      vm.vm.provider "virtualbox" do |vb|
        vb.name   = node[:name]
        vb.memory = node[:memory]
        vb.cpus   = node[:cpus]
      end
    end
  end

end
```

**Características:**
- Box base: `bento/debian-12` (Bookworm, LTS)
- Aprovisionamiento: `ansible.sh` (instala Ansible vía APT)
- Sincronización de carpeta local → `/vagrant` en cada VM
- Red privada `192.168.11.0/24`

---

### `VagrantfileUbuntu`

Idéntico en estructura a `VagrantfileDebian`, pero usa **Ubuntu** como base.

```ruby
vm.vm.box      = "bento/ubuntu-24.04"
vm.vm.provision "shell", path: "UbuntuAnsible.sh"  # Instala Ansible en Ubuntu
```

**Características:**
- Box base: `bento/ubuntu-24.04` (Noble Numbat, LTS)
- Aprovisionamiento: `UbuntuAnsible.sh` (instalación específica para Ubuntu,
  que puede requerir el PPA oficial de Ansible)
- Misma topología de red que `VagrantfileDebian`

---

### `VagrantfileDocker`

Variante que instala **Docker** en las VMs en lugar de (o además de) Ansible,
orientada a practicar la gestión de contenedores con Ansible.

```ruby
vm.vm.box      = "bento/ubuntu-24.04"
vm.vm.provision "shell", path: "docker.sh"   # Instala Docker Engine
```

**Características:**
- Box base: `bento/ubuntu-24.04`
- Aprovisionamiento: `docker.sh` (instala Docker Engine + Docker Compose)
- Útil para laboratorios de Ansible que gestionan contenedores Docker

---

## 🔧 Scripts de Aprovisionamiento

Los scripts `.sh` son ejecutados automáticamente por Vagrant durante el
`vagrant up` mediante la directiva `vm.vm.provision "shell", path: "..."`.

### `ansible.sh` — Instalación de Ansible en Debian

Script de aprovisionamiento para instalar Ansible en sistemas **Debian**.

```bash
#!/bin/bash
set -e

echo "==> Actualizando repositorios APT..."
apt-get update -y

echo "==> Instalando dependencias..."
apt-get install -y \
    python3 \
    python3-pip \
    software-properties-common \
    curl \
    git

echo "==> Instalando Ansible via APT..."
apt-get install -y ansible

echo "==> Verificando instalación..."
ansible --version

echo "==> Ansible instalado correctamente."
```

**Qué hace paso a paso:**

| Paso | Acción |
|---|---|
| 1 | `apt-get update` — Actualiza la lista de paquetes |
| 2 | Instala `python3`, `pip`, `curl`, `git` como dependencias |
| 3 | Instala `ansible` desde los repositorios APT de Debian |
| 4 | Verifica la instalación con `ansible --version` |

---

### `UbuntuAnsible.sh` — Instalación de Ansible en Ubuntu

Script equivalente para **Ubuntu**, que añade el PPA oficial de Ansible
para obtener la versión más reciente.

```bash
#!/bin/bash
set -e

echo "==> Actualizando repositorios APT..."
apt-get update -y

echo "==> Instalando dependencias..."
apt-get install -y \
    python3 \
    python3-pip \
    software-properties-common \
    curl \
    git

echo "==> Añadiendo PPA oficial de Ansible..."
add-apt-repository --yes --update ppa:ansible/ansible

echo "==> Instalando Ansible..."
apt-get install -y ansible

echo "==> Verificando instalación..."
ansible --version

echo "==> Ansible instalado correctamente en Ubuntu."
```

**Diferencia clave respecto a `ansible.sh`:**
- Añade el **PPA oficial `ppa:ansible/ansible`** antes de instalar,
  lo que garantiza obtener la versión más reciente en lugar de la
  versión del repositorio base de Ubuntu (que puede estar desactualizada).

---

### `docker.sh` — Instalación de Docker Engine

Script que instala **Docker Engine** y **Docker Compose** en Ubuntu,
siguiendo el método oficial de Docker (repositorio APT de Docker, no snap).

```bash
#!/bin/bash
set -e

echo "==> Actualizando repositorios..."
apt-get update -y

echo "==> Instalando dependencias previas..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "==> Añadiendo clave GPG oficial de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "==> Añadiendo repositorio oficial de Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y

echo "==> Instalando Docker Engine + Compose..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "==> Añadiendo usuario vagrant al grupo docker..."
usermod -aG docker vagrant

echo "==> Verificando instalación..."
docker --version
docker compose version

echo "==> Docker instalado correctamente."
```

**Qué hace paso a paso:**

| Paso | Acción |
|---|---|
| 1 | Instala dependencias de sistema (`curl`, `gnupg`, etc.) |
| 2 | Descarga e instala la **clave GPG oficial de Docker** |
| 3 | Añade el **repositorio APT oficial de Docker** |
| 4 | Instala `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin` |
| 5 | Añade el usuario `vagrant` al grupo `docker` (sin necesidad de `sudo`) |
| 6 | Verifica con `docker --version` y `docker compose version` |

---

## 📁 Subcarpetas

### `essential_box/`

Contiene la definición de una **box Vagrant mínima personalizada** con solo
lo imprescindible para el laboratorio. Útil para reducir el tamaño de descarga
y el tiempo de aprovisionamiento en entornos con conectividad limitada.

### `multi_agent_setup/`

Configuración para un entorno **multi-agente** más complejo, con más nodos
o con roles diferenciados. Orientado a practicar playbooks que gestionan
simultáneamente múltiples tipos de servidores (base de datos, web, cache, etc.).

---

## 🚀 Uso

### Seleccionar el Vagrantfile adecuado

```bash
# Opción 1: Copiar el Vagrantfile deseado a la raíz del proyecto
cp misc/vagrantfiles/VagrantfileUbuntu Vagrantfile

# Opción 2: Especificar el fichero directamente con la variable de entorno
VAGRANT_VAGRANTFILE=misc/vagrantfiles/VagrantfileUbuntu vagrant up
```

### Arrancar el entorno

```bash
vagrant up
vagrant status
```

### Acceder al nodo de control

```bash
vagrant ssh control
```

### Verificar Ansible

```bash
ansible --version
```

### Parar y destruir el entorno

```bash
vagrant halt       # Apaga las VMs (conserva el estado)
vagrant destroy -f # Destruye todas las VMs
```

---

## 🆚 Comparativa de Vagrantfiles

| **Fichero** | **Box base** | **Script de provisioning** | **Instala** | **Uso recomendado** |
|---|---|---|---|---|
| `VagrantfileDebian` | `bento/debian-12` | `ansible.sh` | Ansible vía APT | Laboratorio estándar en Debian |
| `VagrantfileUbuntu` | `bento/ubuntu-24.04` | `UbuntuAnsible.sh` | Ansible vía PPA | Laboratorio estándar en Ubuntu |
| `VagrantfileDocker` | `bento/ubuntu-24.04` | `docker.sh` | Docker Engine + Compose | Laboratorio Ansible + Docker |

---

## 📚 Referencias

- [Vagrant Documentation](https://developer.hashicorp.com/vagrant/docs)
- [Bento Boxes — Vagrant Cloud](https://app.vagrantup.com/bento)
- [Ansible Installation Guide](https://docs.ansible.com/ansible/latest/installation_guide/index.html)
- [Docker Engine Install — Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Repositorio principal — agile611/startusingansible](https://github.com/agile611/startusingansible)