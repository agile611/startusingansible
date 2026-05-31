# 📋 Extra — `extra_vagrant_files`: Colección de Vagrantfiles alternativos para el laboratorio Ansible

## 🧭 Descripción general

Este directorio no es un ejemplo de Ansible en sí mismo — es una **caja de herramientas de infraestructura**. Contiene una colección de `Vagrantfile` alternativos y scripts de aprovisionamiento que permiten levantar el laboratorio de máquinas virtuales con **diferentes sistemas operativos** y **diferentes topologías de red**, según las necesidades del alumno o del entorno del host.

La idea es simple: el `Vagrantfile` principal de la serie usa Ubuntu 22.04 con las IPs `192.168.11.x`. Si ese entorno no funciona en tu máquina (por incompatibilidades de VirtualBox, versión del SO, o simplemente quieres practicar con Debian), aquí tienes alternativas listas para usar. Solo hay que copiar el fichero elegido a la raíz del proyecto, renombrarlo como `Vagrantfile`, y ejecutar `vagrant up`.

---

## 🗂️ Estructura completa del directorio

```
extra_vagrant_files/
│
├── Vagrantfile1804          # 4 VMs con Ubuntu 18.04 LTS (Bionic Beaver)
├── Vagrantfile2004          # 4 VMs con Ubuntu 20.04 LTS (Focal Fossa)
├── Vagrantfile2104          # 4 VMs con Ubuntu 21.04 (Hirsute Hippo)
├── VagrantfileDebian        # 4 VMs con Debian 11 (Bullseye)
│
├── essential_box/           # ⭐ Vagrantfile mínimo: 1 sola VM con Ansible instalado
│   ├── Vagrantfile
│   └── install.sh
│
└── multi_agent_setup/       # ⭐ Vagrantfile avanzado: 7 VMs (2 web + 2 DB + 2 LB + 1 control)
    ├── VagrantFile
    └── install.sh
```

---

## 🔧 El script `install.sh` — Aprovisionamiento común

Tanto `essential_box` como `multi_agent_setup` usan el mismo script de aprovisionamiento shell. Es minimalista y directo:

```bash
set -eux
apt-get update
apt-get install -y --no-install-recommends ansible
```

| **Línea** | **Qué hace** |
|---|---|
| `set -eux` | `e` = para si hay error; `u` = error si variable no definida; `x` = imprime cada comando ejecutado |
| `apt-get update` | Actualiza la lista de paquetes del repositorio |
| `apt-get install -y --no-install-recommends ansible` | Instala Ansible sin paquetes recomendados opcionales (instalación mínima) |

Este script se ejecuta automáticamente durante el `vagrant up` gracias a la directiva `vm.provision :shell, :path => "install.sh"` en el `Vagrantfile`. Solo se ejecuta en el **nodo de control Ansible** (`ansible`), no en los nodos gestionados.

---

## 📄 Los Vagrantfiles alternativos por versión de SO

Estos cuatro ficheros son funcionalmente **idénticos en estructura** — solo cambia la `vm.box` (la imagen base del SO). Todos levantan el mismo conjunto de 4 máquinas virtuales con la misma topología de red.

### Topología común (4 VMs)

| **VM** | **Hostname** | **IP** | **Puerto redirigido** | **Rol** |
|---|---|---|---|---|
| `ansible` | ansible | `192.168.0.254` | — | Nodo de control Ansible |
| `alfa` | alfa | `192.168.0.2` | `3306 → 3306` | Base de datos (MySQL) |
| `bravo` | bravo | `192.168.0.3` | — | Servidor genérico |
| `charlie` | charlie | `192.168.0.4` | `80 → 80` | Servidor web (HTTP) |

> **Nota sobre IPs**: Estos Vagrantfiles alternativos usan el rango `192.168.0.x`, mientras que el `Vagrantfile` principal de la serie usa `192.168.11.x`. Si usas estos ficheros alternativos, **debes actualizar el inventario `hosts`** con las IPs correspondientes.

---

### `Vagrantfile1804` — Ubuntu 18.04 LTS (Bionic Beaver)

```ruby
Vagrant.configure(2) do |config|
  config.vm.define "ansible" do |ansible|
    ansible.vm.box = "bento/ubuntu-18.04"
    ansible.vm.network "private_network", ip: "192.168.0.254"
    ansible.vm.hostname = "ansible"
    ansible.vm.provision :shell, :path => "ansible.sh"
  end
  config.vm.define "alfa" do |alfa|
    alfa.vm.box = "bento/ubuntu-18.04"
    alfa.vm.network "private_network", ip: "192.168.0.2"
    alfa.vm.hostname = "alfa"
    alfa.vm.provision :shell, :path => "ansible.sh"
    alfa.vm.network "forwarded_port", guest: 3306, host: 3306
  end
  config.vm.define "bravo" do |bravo|
    bravo.vm.box = "bento/ubuntu-18.04"
    bravo.vm.network "private_network", ip: "192.168.0.3"
    bravo.vm.hostname = "bravo"
    bravo.vm.provision :shell, :path => "ansible.sh"
  end
  config.vm.define "charlie" do |charlie|
    charlie.vm.box = "bento/ubuntu-18.04"
    charlie.vm.network "private_network", ip: "192.168.0.4"
    charlie.vm.hostname = "charlie"
    charlie.vm.provision :shell, :path => "ansible.sh"
    charlie.vm.network "forwarded_port", guest: 80, host: 80
  end
end
```

- **Box**: `bento/ubuntu-18.04` — imagen Ubuntu 18.04 de la colección Bento (Vagrant boxes oficiales de Chef)
- **Uso**: Entornos donde Ubuntu 22.04 no es compatible con la versión de VirtualBox instalada

---

### `Vagrantfile2004` — Ubuntu 20.04 LTS (Focal Fossa)

Estructura idéntica al anterior, cambiando únicamente:

```ruby
ansible.vm.box = "bento/ubuntu-20.04"
# (igual para alfa, bravo, charlie)
```

- **Box**: `bento/ubuntu-20.04`
- **Uso**: Alternativa estable y ampliamente soportada, LTS con soporte hasta 2025

---

### `Vagrantfile2104` — Ubuntu 21.04 (Hirsute Hippo)

```ruby
ansible.vm.box = "ubuntu/hirsute64"
# (igual para alfa, bravo, charlie)
```

- **Box**: `ubuntu/hirsute64` — imagen oficial de Canonical (no Bento)
- **Uso**: Versión intermedia no-LTS; útil para probar comportamientos en versiones más recientes del kernel
- ⚠️ Ubuntu 21.04 llegó a End of Life en enero 2022 — solo para laboratorio

---

### `VagrantfileDebian` — Debian 11 (Bullseye)

```ruby
ansible.vm.box = "debian/bullseye64"
# (igual para alfa, bravo, charlie)
```

- **Box**: `debian/bullseye64` — imagen oficial de Debian
- **Uso**: Practicar Ansible en Debian en lugar de Ubuntu. Los módulos `apt`, `service`, etc. funcionan igual, pero hay diferencias en rutas de configuración y nombres de paquetes

---

## 📦 `essential_box/` — La VM mínima: un solo nodo

Este subdirectorio contiene el `Vagrantfile` más simple de toda la colección: **una única máquina virtual** con Ansible instalado. Es el punto de partida ideal para quien empieza desde cero.

### `essential_box/Vagrantfile`

```ruby
Vagrant.configure(2) do |config|
  config.vm.box = "bento/ubuntu-18.04"
  config.vm.network "private_network", ip: "192.168.33.10"
  config.vm.hostname = "client.vagrant.local"
  config.vm.provision :shell, :path => "install.sh"
  config.vm.provider "virtualbox" do |v|
    v.memory = 512
    v.cpus = 1
    v.name = "webserver"
  end
end
```

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `vm.box` | `bento/ubuntu-18.04` | Imagen base Ubuntu 18.04 |
| `vm.network` | `192.168.33.10` | Red privada host-only |
| `vm.hostname` | `client.vagrant.local` | Nombre DNS interno de la VM |
| `vm.provision` | `install.sh` | Instala Ansible automáticamente al levantar |
| `v.memory` | `512` MB | RAM asignada a la VM |
| `v.cpus` | `1` | Núcleos de CPU asignados |
| `v.name` | `webserver` | Nombre visible en la interfaz de VirtualBox |

**Diferencia clave respecto al resto**: Este es el único `Vagrantfile` que configura explícitamente los recursos de VirtualBox (`memory`, `cpus`, `name`) mediante el bloque `config.vm.provider "virtualbox"`. Es el más adecuado para máquinas host con poca RAM.

### `essential_box/install.sh`

```bash
set -eux
apt-get update
apt-get install -y --no-install-recommends ansible
```

---

## 🖧 `multi_agent_setup/` — El laboratorio completo: 7 VMs

Este es el `Vagrantfile` más avanzado de la colección. Levanta **7 máquinas virtuales** organizadas en tres capas de infraestructura más el nodo de control, simulando un entorno real de producción con alta disponibilidad.

### `multi_agent_setup/VagrantFile`

```ruby
Vagrant.configure(2) do |config|
  config.vm.define "webserver01" do |webserver01|
    webserver01.vm.box = "bento/ubuntu-18.04"
    webserver01.vm.network "private_network", ip: "192.168.0.6"
    webserver01.vm.hostname = "webserver01"
  end
  config.vm.define "webserver02" do |webserver02|
    webserver02.vm.box = "bento/ubuntu-18.04"
    webserver02.vm.network "private_network", ip: "192.168.0.9"
    webserver02.vm.hostname = "webserver02"
  end
  config.vm.define "database01" do |database01|
    database01.vm.box = "bento/ubuntu-18.04"
    database01.vm.network "private_network", ip: "192.168.0.5"
    database01.vm.hostname = "database01"
  end
  config.vm.define "database02" do |database02|
    database02.vm.box = "bento/ubuntu-18.04"
    database02.vm.network "private_network", ip: "192.168.0.8"
    database02.vm.hostname = "database02"
  end
  config.vm.define "loadbalancer01" do |loadbalancer01|
    loadbalancer01.vm.box = "bento/ubuntu-18.04"
    loadbalancer01.vm.network "private_network", ip: "192.168.0.4"
    loadbalancer01.vm.hostname = "loadbalancer01"
  end
  config.vm.define "loadbalancer02" do |loadbalancer02|
    loadbalancer02.vm.box = "bento/ubuntu-18.04"
    loadbalancer02.vm.network "private_network", ip: "192.168.0.7"
    loadbalancer02.vm.hostname = "loadbalancer02"
  end
  config.vm.define "ansible" do |ansible|
    ansible.vm.box = "bento/ubuntu-18.04"
    ansible.vm.network "private_network", ip: "192.168.0.254"
    ansible.vm.hostname = "ansible"
    ansible.vm.provision :shell, :path => "install.sh"
  end
end
```

### Topología de 7 VMs

| **VM** | **Hostname** | **IP** | **Capa** | **Rol** |
|---|---|---|---|---|
| `loadbalancer01` | loadbalancer01 | `192.168.0.4` | Capa 1 — Entrada | Balanceador de carga primario |
| `loadbalancer02` | loadbalancer02 | `192.168.0.7` | Capa 1 — Entrada | Balanceador de carga secundario |
| `webserver01` | webserver01 | `192.168.0.6` | Capa 2 — Aplicación | Servidor web primario |
| `webserver02` | webserver02 | `192.168.0.9` | Capa 2 — Aplicación | Servidor web secundario |
| `database01` | database01 | `192.168.0.5` | Capa 3 — Datos | Base de datos primaria |
| `database02` | database02 | `192.168.0.8` | Capa 3 — Datos | Base de datos secundaria (réplica) |
| `ansible` | ansible | `192.168.0.254` | Control | Nodo de control Ansible |

**Diferencia clave respecto a los otros Vagrantfiles**: Los nodos gestionados (`webserver01/02`, `database01/02`, `loadbalancer01/02`) **no tienen `vm.provision`** — Ansible no se instala en ellos. Solo el nodo de control (`ansible`) ejecuta `install.sh`. Esto refleja la arquitectura real de Ansible: solo el nodo de control necesita Ansible instalado.

### Inventario `hosts` adaptado para `multi_agent_setup`

Si usas este `VagrantFile`, el inventario de Ansible debería ser:

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=vagrant
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[webserver]
192.168.0.6
192.168.0.9

[database]
192.168.0.5
192.168.0.8

[loadbalancer]
192.168.0.4
192.168.0.7
```

---

## 🚀 Comandos de uso

### Levantar el laboratorio con un Vagrantfile alternativo

```bash
# 1. Copiar el Vagrantfile elegido a la raíz del proyecto
cp extra_vagrant_files/Vagrantfile2004 ./Vagrantfile

# 2. Levantar todas las VMs
vagrant up

# 3. Levantar solo una VM específica
vagrant up ansible
vagrant up alfa

# 4. Ver el estado de todas las VMs
vagrant status

# 5. Conectarse por SSH a una VM
vagrant ssh ansible
vagrant ssh alfa
```

### Levantar el laboratorio mínimo (`essential_box`)

```bash
cd extra_vagrant_files/essential_box
vagrant up
vagrant ssh
```

### Levantar el laboratorio completo de 7 VMs (`multi_agent_setup`)

```bash
cd extra_vagrant_files/multi_agent_setup
vagrant up

# Levantar solo el nodo de control (para ahorrar recursos)
vagrant up ansible

# Levantar solo los webservers
vagrant up webserver01 webserver02
```

### Verificar conectividad Ansible tras levantar el lab

```bash
# Desde dentro del nodo ansible (vagrant ssh ansible)
ansible all -i hosts -u vagrant -m ping
```

### Ejecutar playbooks con el inventario adaptado

```bash
ansible-playbook -i hosts -u vagrant site.yml
ansible-playbook -i hosts -u vagrant site.yml --limit webserver
ansible-playbook -i hosts -u vagrant site.yml --limit database
```

---

## 🔍 Comparativa de todos los Vagrantfiles

| **Fichero** | **SO Base** | **Nº VMs** | **IPs** | **Ansible instalado en** | **Caso de uso** |
|---|---|---|---|---|---|
| `Vagrantfile1804` | Ubuntu 18.04 | 4 | `192.168.0.x` | Todas las VMs | Lab alternativo Ubuntu 18 |
| `Vagrantfile2004` | Ubuntu 20.04 | 4 | `192.168.0.x` | Todas las VMs | Lab alternativo Ubuntu 20 |
| `Vagrantfile2104` | Ubuntu 21.04 | 4 | `192.168.0.x` | Todas las VMs | Lab alternativo Ubuntu 21 |
| `VagrantfileDebian` | Debian 11 | 4 | `192.168.0.x` | Todas las VMs | Lab con Debian Bullseye |
| `essential_box/Vagrantfile` | Ubuntu 18.04 | **1** | `192.168.33.10` | La única VM | Inicio desde cero, 512MB RAM |
| `multi_agent_setup/VagrantFile` | Ubuntu 18.04 | **7** | `192.168.0.x` | Solo `ansible` | Arquitectura real 3 capas |

---

## 💡 Conceptos clave aprendidos

- **Vagrant multi-machine**: La directiva `config.vm.define "nombre" do |nombre|` dentro de un único `Vagrantfile` permite definir múltiples VMs con configuraciones independientes. Esto es la base de todos los laboratorios de la serie.

- **`forwarded_port`**: La directiva `vm.network "forwarded_port", guest: X, host: X` redirige un puerto de la VM al host. En los Vagrantfiles alternativos, el puerto `3306` (MySQL) de `alfa` y el puerto `80` (HTTP) de `charlie` son accesibles directamente desde el navegador o cliente del host.

- **`vm.provision :shell`**: Ejecuta un script shell automáticamente durante el primer `vagrant up`. Es la forma más simple de aprovisionamiento — instala Ansible en el nodo de control sin intervención manual.

- **`set -eux` en
