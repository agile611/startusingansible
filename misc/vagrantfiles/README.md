# 📋 `vagrantfiles/` — Colección de Vagrantfiles para el laboratorio Ansible

## 🧭 Descripción general

El directorio `vagrantfiles/` no contiene playbooks de Ansible — es la **caja de herramientas de infraestructura** del curso. Agrupa todos los `Vagrantfile` alternativos y scripts de aprovisionamiento necesarios para levantar el laboratorio de máquinas virtuales en diferentes entornos y con diferentes sistemas operativos.

La idea es simple: el laboratorio principal usa Ubuntu 24.04 con VirtualBox y las IPs `192.168.11.x`. Si ese entorno no funciona en tu máquina (por incompatibilidades de hipervisor, versión del SO, o simplemente quieres una topología diferente), aquí tienes alternativas listas para usar. Solo hay que copiar el fichero elegido a la raíz del proyecto, renombrarlo como `Vagrantfile`, y ejecutar `vagrant up`.

---

## 🗂️ Estructura del directorio

```
vagrantfiles/
├── Vagrantfile          # ⭐ Vagrantfile principal — 4 VMs Ubuntu 24.04 para KVM/libvirt
├── UbuntuVagrantfile    # Vagrantfile alternativo — 4 VMs Ubuntu 24.04 para VirtualBox
├── Vagrantfile1804      # Vagrantfile legacy — 4 VMs Ubuntu 18.04 para VirtualBox
├── UbuntuAnsible.sh     # Script de aprovisionamiento — instala Ansible en el nodo de control
└── README.md            # Documentación del directorio
```

---

## 📄 `Vagrantfile` — Laboratorio principal para KVM/libvirt (código real)

Este es el `Vagrantfile` **principal del curso**. Levanta 4 máquinas virtuales Ubuntu 24.04 usando el proveedor **libvirt/KVM** (hipervisor nativo de Linux), que es más eficiente que VirtualBox en sistemas Linux modernos.

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 900

  # ─── ANSIBLE ───────────────────────────────────────────
  config.vm.define "ansible" do |ansible|
    ansible.vm.box     = "bento/ubuntu-24.04"
    ansible.vm.hostname = "ansible"
    ansible.vm.network "private_network", ip: "192.168.11.10"
    ansible.vm.synced_folder ".", "/vagrant", type: "rsync"
    ansible.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

  # ─── DATABASE ──────────────────────────────────────────
  config.vm.define "database" do |database|
    database.vm.box     = "bento/ubuntu-24.04"
    database.vm.hostname = "database"
    database.vm.network "private_network", ip: "192.168.11.11"
    database.vm.synced_folder ".", "/vagrant", type: "rsync"
    database.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

  # ─── LOADBALANCER ──────────────────────────────────────
  # (misma estructura, ip: "192.168.11.12")

  # ─── WEBSERVER ─────────────────────────────────────────
  # (misma estructura, ip: "192.168.11.13")

end
```

### Análisis detallado

#### Cabecera global

```ruby
Vagrant.configure("2") do |config|
  config.vm.boot_timeout = 900
```

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `Vagrant.configure("2")` | API versión 2 | Usa la API de configuración de Vagrant v2 (la actual) |
| `config.vm.boot_timeout` | `900` segundos | Tiempo máximo de espera para que la VM arranque (15 min). Necesario para VMs lentas o con poco RAM |

#### Bloque de cada VM

Cada máquina sigue exactamente el mismo patrón:

```ruby
config.vm.define "ansible" do |ansible|
  ansible.vm.box      = "bento/ubuntu-24.04"
  ansible.vm.hostname = "ansible"
  ansible.vm.network  "private_network", ip: "192.168.11.10"
  ansible.vm.synced_folder ".", "/vagrant", type: "rsync"
  ansible.vm.provider :libvirt do |v|
    v.driver        = "qemu"
    v.memory        = 512
    v.cpus          = 1
    v.graphics_type = "spice"
    v.cpu_mode      = "custom"
    v.cpu_model     = "qemu64"
  end
end
```

| **Directiva** | **Valor** | **Significado** |
|---|---|---|
| `vm.define "ansible"` | Nombre de la VM | Identificador único de la VM en Vagrant. Permite arrancar VMs individuales con `vagrant up ansible` |
| `vm.box` | `bento/ubuntu-24.04` | Imagen base de la VM descargada de Vagrant Cloud. `bento` es una colección de boxes oficiales mantenida por Chef |
| `vm.hostname` | `ansible` | Nombre de host del sistema operativo dentro de la VM |
| `vm.network "private_network"` | `ip: "192.168.11.10"` | Red privada host-only: las VMs se comunican entre sí y con el host, pero no son accesibles desde Internet |
| `vm.synced_folder ".", "/vagrant"` | `type: "rsync"` | Sincroniza el directorio actual del host (donde está el `Vagrantfile`) con `/vagrant` dentro de la VM usando rsync |
| `vm.provider :libvirt` | — | Configura el proveedor KVM/libvirt en lugar de VirtualBox |
| `v.driver = "qemu"` | `"qemu"` | Motor de virtualización QEMU (base de KVM) |
| `v.memory` | `512` MB | RAM asignada a la VM |
| `v.cpus` | `1` | Número de CPUs virtuales |
| `v.graphics_type = "spice"` | `"spice"` | Protocolo de pantalla remota (más eficiente que VNC en KVM) |
| `v.cpu_mode = "custom"` + `v.cpu_model = "qemu64"` | — | Usa un modelo de CPU genérico compatible con cualquier host, evitando problemas de migración o incompatibilidad de flags de CPU |

#### Topología de red del `Vagrantfile` principal

```
Host (tu máquina)
│
└── Red privada 192.168.11.0/24
    ├── ansible       → 192.168.11.10  (nodo de control Ansible)
    ├── database      → 192.168.11.11  (nodo gestionado: BD)
    ├── loadbalancer  → 192.168.11.12  (nodo gestionado: LB)
    └── webserver     → 192.168.11.13  (nodo gestionado: web)
```

> ⚠️ **Nota importante**: Las IPs del `Vagrantfile` principal (`.10`, `.11`, `.12`, `.13`) son diferentes de las IPs del fichero `hosts` del curso (`.10`, `.20`, `.30`, `.40`). El fichero `UbuntuVagrantfile` usa las IPs correctas del inventario.

---

## 📄 `UbuntuVagrantfile` — Laboratorio para VirtualBox (código real)

Este es el `Vagrantfile` **recomendado para Windows y macOS**, donde VirtualBox es el hipervisor más común. Usa las **IPs correctas del inventario del curso** (`192.168.11.20`, `.30`, `.40`) y añade redirección de puertos para acceder a los servicios desde el navegador del host.

```ruby
Vagrant.configure(2) do |config|

  # Máquina de control para el agente Ansible
  config.vm.define "ansible" do |ansible|
    ansible.vm.box          = "bento/ubuntu-24.04"
    ansible.vm.network      "private_network", ip: "192.168.11.10"
    ansible.vm.hostname     = "ansible"
    ansible.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    ansible.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus   = 1
    end
    ansible.vm.provision :shell, :path => "ansible.sh"
  end

  # Máquina para la base de datos
  config.vm.define "database" do |database|
    database.vm.box          = "bento/ubuntu-24.04"
    database.vm.network      "private_network", ip: "192.168.11.20"
    database.vm.hostname     = "database"
    database.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    database.vm.network      "forwarded_port", guest: 80,   host: 8081
    database.vm.network      "forwarded_port", guest: 3306, host: 3306
    database.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus   = 1
    end
  end

  # Máquina para el balanceador de carga
  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box          = "bento/ubuntu-24.04"
    loadbalancer.vm.network      "private_network", ip: "192.168.11.30"
    loadbalancer.vm.hostname     = "loadbalancer"
    loadbalancer.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    # forwarded_port: guest 80 → host 8080
    loadbalancer.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus   = 1
    end
  end

  # Máquina para el servidor web
  config.vm.define "webserver" do |webserver|
    webserver.vm.box          = "bento/ubuntu-24.04"
    webserver.vm.network      "private_network", ip: "192.168.11.40"
    webserver.vm.hostname     = "webserver"
    webserver.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    # forwarded_port: guest 80 → host 8082
    webserver.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.cpus   = 1
    end
  end

end
```

### Diferencias clave respecto al `Vagrantfile` principal

| **Característica** | **`Vagrantfile`** (KVM) | **`UbuntuVagrantfile`** (VirtualBox) |
|---|---|---|
| **Proveedor** | `:libvirt` (KVM/QEMU) | `"virtualbox"` |
| **IPs de red** | `.10`, `.11`, `.12`, `.13` | `.10`, `.20`, `.30`, `.40` ✅ (coincide con `hosts`) |
| **Carpeta sync** | `/vagrant` | `/home/vagrant/sync` |
| **Puertos redirigidos** | No | Sí (MySQL 3306, HTTP 8080/8081/8082) |
| **Script de aprovisionamiento** | No incluido | `ansible.sh` en el nodo `ansible` |
| **Plataforma objetivo** | Linux (nativo) | Windows / macOS / Linux |

#### Redirección de puertos (`forwarded_port`)

```ruby
database.vm.network "forwarded_port", guest: 80,   host: 8081
database.vm.network "forwarded_port", guest: 3306, host: 3306
```

La redirección de puertos permite acceder a los servicios de las VMs directamente desde el navegador o cliente del host:

| **VM** | **Puerto guest** | **Puerto host** | **Acceso desde el host** |
|---|---|---|---|
| `database` | 80 | 8081 | `http://localhost:8081` |
| `database` | 3306 | 3306 | `mysql -h 127.0.0.1 -P 3306` |
| `loadbalancer` | 80 | 8080 | `http://localhost:8080` |
| `webserver` | 80 | 8082 | `http://localhost:8082` |

---

## 📄 `Vagrantfile1804` — Laboratorio legacy Ubuntu 18.04 (código real)

Este `Vagrantfile` es la versión **más antigua y minimalista** de la colección. Usa Ubuntu 18.04 LTS (Bionic Beaver) con una topología de red diferente y nombres de VM genéricos (`alfa`, `bravo`, `charlie`).

```ruby
Vagrant.configure(2) do |config|

  config.vm.define "ansible" do |ansible|
    ansible.vm.box     = "bento/ubuntu-18.04"
    ansible.vm.network "private_network", ip: "192.168.0.254"
    ansible.vm.hostname = "ansible"
    ansible.vm.provision :shell, :path => "ansible.sh"
  end

  config.vm.define "alfa" do |alfa|
    alfa.vm.box     = "bento/ubuntu-18.04"
    alfa.vm.network "private_network", ip: "192.168.0.2"
    alfa.vm.hostname = "alfa"
    alfa.vm.provision :shell, :path => "ansible.sh"
    alfa.vm.network "forwarded_port", guest: 3306, host: 3306
  end

  config.vm.define "bravo" do |bravo|
    bravo.vm.box     = "bento/ubuntu-18.04"
    bravo.vm.network "private_network", ip: "192.168.0.3"
    bravo.vm.hostname = "bravo"
    bravo.vm.provision :shell, :path => "ansible.sh"
  end

  config.vm.define "charlie" do |charlie|
    charlie.vm.box     = "bento/ubuntu-18.04"
    charlie.vm.network "private_network", ip: "192.168.0.4"
    charlie.vm.hostname = "charlie"
    charlie.vm.provision :shell, :path => "ansible.sh"
    charlie.vm.network "forwarded_port", guest: 80, host: 80
  end

end
```

### Diferencias respecto a los Vagrantfiles modernos

| **Característica** | **`Vagrantfile1804`** | **`UbuntuVagrantfile`** |
|---|---|---|
| **SO** | Ubuntu 18.04 LTS | Ubuntu 24.04 LTS |
| **Subred** | `192.168.0.x` | `192.168.11.x` |
| **IP nodo control** | `192.168.0.254` | `192.168.11.10` |
| **Nombres de VMs** | `ansible`, `alfa`, `bravo`, `charlie` | `ansible`, `database`, `loadbalancer`, `webserver` |
| **Aprovisionamiento** | `ansible.sh` en **todas** las VMs | `ansible.sh` solo en `ansible` |
| **Configuración de RAM/CPU** | No especificada (usa defaults) | Explícita: 512 MB, 1 CPU |
| **Carpeta sincronizada** | No configurada | Sí (`/home/vagrant/sync`) |

> **¿Por qué `ansible.sh` en todas las VMs?** En la versión 18.04, el script se ejecuta en todos los nodos porque en aquella época era habitual instalar Ansible también en los nodos gestionados para facilitar la depuración. En las versiones modernas, solo se instala en el nodo de control.

#### Topología de red del `Vagrantfile1804`

```
Host (tu máquina)
│
└── Red privada 192.168.0.0/24
    ├── ansible  → 192.168.0.254  (nodo de control)
    ├── alfa     → 192.168.0.2    (nodo gestionado — BD, puerto 3306 redirigido)
    ├── bravo    → 192.168.0.3    (nodo gestionado)
    └── charlie  → 192.168.0.4    (nodo gestionado — web, puerto 80 redirigido)
```

---

## 🔧 `UbuntuAnsible.sh` — Script de aprovisionamiento (código real)

Este script shell es el **aprovisionador del nodo de control Ansible**. Se ejecuta automáticamente durante el `vagrant up` gracias a la directiva `vm.provision :shell, :path => "ansible.sh"` en el `Vagrantfile`. Su único objetivo es dejar el nodo `ansible` listo para ejecutar playbooks.

```bash
# Script to install Ansible on a Ubuntu system
apt-get update

# Install required packages
apt install software-properties-common -y

# Add Ansible PPA and install Ansible
apt-add-repository ppa:ansible/ansible
apt-get install ansible net-tools -y

# Add vagrant user to sudoers
echo " vagrant ALL=(ALL) NOPASSWD:ALL " | sudo tee /etc/sudoers.d/vagrant
```

### Análisis línea a línea

| **Comando** | **Qué hace** |
|---|---|
| `apt-get update` | Actualiza la lista de paquetes disponibles en los repositorios |
| `apt install software-properties-common -y` | Instala `add-apt-repository`, necesario para añadir PPAs de terceros |
| `apt-add-repository ppa:ansible/ansible` | Añade el **PPA oficial de Ansible** mantenido por el equipo de Ansible. Garantiza obtener la versión más reciente en lugar de la versión antigua incluida en los repositorios de Ubuntu |
| `apt-get install ansible net-tools -y` | Instala Ansible y `net-tools` (incluye `ifconfig`, `netstat`, útiles para diagnóstico de red) |
| `echo "vagrant ALL=(ALL) NOPASSWD:ALL" \| sudo tee /etc/sudoers.d/vagrant` | Añade el usuario `vagrant` al fichero de sudoers sin contraseña, necesario para que Ansible pueda ejecutar tareas con `become: yes` sin interrupciones |

### ¿Por qué el PPA oficial y no el repositorio de Ubuntu?

```
Repositorio Ubuntu 24.04:  ansible 2.10.x  (versión antigua)
PPA ppa:ansible/ansible:   ansible 2.17.x  (versión actual)
```

El PPA oficial garantiza que el nodo de control tenga la versión más reciente de Ansible con todas las correcciones de bugs y módulos actualizados.

---

## 🔄 Flujo completo: de cero al laboratorio listo

```
1. Elegir el Vagrantfile adecuado para tu entorno
   ├── Linux con KVM  → usar Vagrantfile      (renombrar a Vagrantfile)
   ├── Windows/macOS  → usar UbuntuVagrantfile (renombrar a Vagrantfile)
   └── Ubuntu 18.04   → usar Vagrantfile1804   (renombrar a Vagrantfile)

2. Copiar el fichero elegido a la raíz del proyecto
   cp vagrantfiles/UbuntuVagrantfile ./Vagrantfile

3. Levantar todas las VMs
   vagrant up

   ┌─────────────────────────────────────────────────────┐
   │  Vagrant descarga bento/ubuntu-24.04 (~1 GB)        │
   │  Crea 4 VMs: ansible + database + loadbalancer +    │
   │              webserver                              │
   │  Ejecuta UbuntuAnsible.sh en la VM "ansible":       │
   │    → apt-get update                                 │
   │    → instala software-properties-common             │
   │    → añade ppa:ansible/ansible                      │
   │    → instala ansible + net-tools                    │
   │    → configura sudoers para vagrant                 │
   └─────────────────────────────────────────────────────┘

4. Conectarse al nodo de control
   vagrant ssh ansible

5. Verificar que Ansible está instalado
   ansible --version

6. Ejecutar playbooks contra el laboratorio
   ansible-playbook -i hosts -u vagrant <playbook>.yml
```

---

## 🚀 Comandos Vagrant esenciales

### Gestión del laboratorio completo

```bash
# Levantar todas las VMs
vagrant up

# Levantar solo una VM específica
vagrant up ansible
vagrant up database

# Apagar todas las VMs (sin destruirlas)
vagrant halt

# Destruir todas las VMs (libera espacio en disco)
vagrant destroy -f

# Ver el estado de todas las VMs
vagrant status
```

### Acceso a las VMs

```bash
# Conectarse al nodo de control Ansible
vagrant ssh ansible

# Conectarse a un nodo gestionado
vagrant ssh database
vagrant ssh loadbalancer
vagrant ssh webserver
```

### Re-aprovisionamiento

```bash
# Volver a ejecutar el script de aprovisionamiento (UbuntuAnsible.sh)
vagrant provision ansible

# Destruir y recrear desde cero
vagrant destroy -f && vagrant up
```

---

## 📊 Comparativa de todos los Vagrantfiles

| **Fichero** | **SO** | **Proveedor** | **Subred** | **IPs** | **Aprovisionamiento** |
|---|---|---|---|---|---|
| `Vagrantfile` | Ubuntu 24.04 | KVM/libvirt | `192.168.11.x` | `.10/.11/.12/.13` | No incluido |
| `UbuntuVagrantfile` | Ubuntu 24.04 | VirtualBox | `192.168.11.x` | `.10/.20/.30/.40` ✅ | `ansible.sh` en nodo control |
| `Vagrantfile1804` | Ubuntu 18.04 | VirtualBox | `192.168.0.x` | `.254/.2/.3/.4` | `ansible.sh` en todas las VMs |

✅ = IPs que coinciden exactamente con el fichero `hosts` del curso

---

## 💡 Conceptos clave aprendidos

- **`Vagrantfile` como código de infraestructura**: El `Vagrantfile` es Ruby puro — permite usar variables, bucles y condicionales para definir entornos complejos de forma declarativa. Es el equivalente de Vagrant a un `docker-compose.yml`.

- **`vm.define` para multi-máquina**: La directiva `config.vm.define "nombre"` dentro de un único `Vagrantfile` permite definir múltiples VMs con configuraciones independientes. Cada VM puede tener su propio SO, red, recursos y script de aprovisionamiento.

- **`vm.provision :shell, :path`**: El aprovisionamiento shell ejecuta un script bash automáticamente al crear la VM. Es la forma más directa de preparar el entorno sin necesidad de conectarse manualmente.

- **`vm.synced_folder` con `type: "rsync"`**: La sincronización rsync copia el directorio del host a la VM en el momento del `vagrant up`. A diferencia de la sincronización bidireccional de VirtualBox, rsync es unidireccional (host → VM) pero más compatible y eficiente en KVM.

- **`forwarded_port` para acceso desde el host**: La redirección de puertos permite acceder a los servicios de las VMs (`http://localhost:8080`) sin necesidad de conocer las IPs de la red privada, lo que facilita el desarrollo y la depuración.

- **PPA oficial de Ansible**: Usar `ppa:ansible/ansible` en lugar del paquete del repositorio de Ubuntu garantiza tener siempre la versión más reciente de Ansible con todos los módulos y correcciones actualizados.

- **`sudoers` sin contraseña para `vagrant`**: La línea `vagrant ALL=(ALL) NOPASSWD:ALL` es imprescindible para que Ansible pueda ejecutar tareas con `become: yes` de forma no interactiva. Sin esto, Ansible se quedaría esperando una contraseña que nunca llega.

---

## 📚 Referencias

- [Vagrant Docs — Multi-Machine](https://developer.hashicorp.com/vagrant/docs/multi-machine)
- [Vagrant Docs — Networking](https://developer.hashicorp.com/vagrant/docs/networking)
- [Vagrant Docs — Shell Provisioner](https://developer.hashicorp.com/vagrant/docs/provisioning/shell)
- [Vagrant Docs — Synced Folders](https://developer.hashicorp.com/vagrant/docs/synced-folders)
- [Vagrant Cloud — bento/ubuntu-24.04](https://app.vagrantup.com/bento/boxes/ubuntu-24.04)
- [Ansible PPA oficial](https://launchpad.net/~ansible/+archive/ubuntu/ansible)