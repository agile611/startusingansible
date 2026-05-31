# 📋 Ejemplo 032 — `azure`: Aprovisionamiento de infraestructura en Microsoft Azure con Ansible

## 🧭 Descripción general

Este ejemplo es el equivalente Azure del ejemplo 031 (AWS): demuestra cómo Ansible puede **crear infraestructura en la nube de Microsoft Azure** desde cero, sin tocar la consola web ni el portal de Azure. El playbook construye una pila completa de red y cómputo — grupo de recursos, red virtual, subred, interfaz de red, conjunto de disponibilidad y una máquina virtual con Debian 12 — todo en secuencia y con dependencias gestionadas mediante `when`.

La diferencia conceptual clave respecto al ejemplo 031 (AWS) es que Azure requiere **construir explícitamente toda la infraestructura de red** antes de lanzar una VM. En AWS, la VPC y la subred ya existen por defecto; en Azure, hay que crearlas paso a paso. Esto hace que el playbook sea más largo, pero también más ilustrativo del modelo de infraestructura de Azure.

El playbook se ejecuta íntegramente en `localhost` (el nodo de control), que habla con la API REST de Azure a través de los módulos `azure_rm_*` de la colección `azure.azcollection`. Las VMs creadas no necesitan tener Ansible instalado.

---

## 🗂️ Estructura del proyecto

```
032_azure/
├── README.md                   # Documentación del ejemplo
└── test_ansible_azure.yml      # ⭐ Playbook: crear infraestructura completa en Azure
```

Al igual que el ejemplo 031, este ejemplo es minimalista: no hay roles, no hay `group_vars`, no hay `site.yml`. El foco está en demostrar la integración de Ansible con la API de Azure.

---

## 🔧 Configuración previa — Prerrequisitos

Antes de ejecutar el playbook, el nodo de control necesita tener instalada la colección de Azure para Ansible y el CLI de Azure (`az`). Sigue estos pasos en orden.

---

### Paso 1 — Instalación de la colección de Azure

```bash
ansible-galaxy collection install azure.azcollection
```

La colección `azure.azcollection` proporciona todos los módulos `azure_rm_*` usados en el playbook:

| **Módulo** | **Recurso que gestiona** |
|---|---|
| `azure_rm_resourcegroup` | Grupos de recursos |
| `azure_rm_availabilityset` | Conjuntos de disponibilidad |
| `azure_rm_virtualnetwork` | Redes virtuales (VNet) |
| `azure_rm_subnet` | Subredes dentro de una VNet |
| `azure_rm_networkinterface` | Interfaces de red (NIC) |
| `azure_rm_virtualmachine` | Máquinas virtuales |

> **Nota**: La colección `azure.azcollection` también requiere instalar sus dependencias Python. Tras instalar la colección, ejecuta:
> ```bash
> pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
> ```

---

### Paso 2 — Instalación del CLI de Azure

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version
```

### Autenticación con Azure

```bash
az login
```

Este comando abre un navegador para autenticarse con tu cuenta de Azure. En entornos sin interfaz gráfica (como una VM Vagrant), usa:

```bash
az login --use-device-code
```

Devuelve un código y una URL. Abre la URL en cualquier navegador, introduce el código y la autenticación se completa. Las credenciales se guardan en `~/.azure/` y la colección `azure.azcollection` las lee automáticamente.

### Verificar que la autenticación funciona

```bash
az account show
```

Devuelve la suscripción activa, el tenant ID y el usuario autenticado. Si este comando funciona, Ansible también podrá autenticarse contra Azure.

---

## 📋 Variables del playbook

```yaml
vars:
  username: adminuser
  password: "P@ssw0rd123!"
```

| **Variable** | **Valor** | **Significado** |
|---|---|---|
| `username` | `adminuser` | Usuario administrador de la VM creada |
| `password` | `P@ssw0rd123!` | Contraseña del usuario administrador |

> **⚠️ Seguridad**: En un entorno de producción, **nunca** se deben hardcodear credenciales en el playbook. La práctica correcta es usar `ansible-vault` para cifrar las variables sensibles, o pasarlas como variables de entorno. Este ejemplo es demostrativo.

---

## 📄 `test_ansible_azure.yml` — El playbook

```yaml
- name: Test Azure Connection
  hosts: localhost
  connection: local
  vars:
    username: adminuser
    password: "P@ssw0rd123!"
  tasks:
    - name: Crear un grupo de recursos
      azure_rm_resourcegroup:
        name: TestCursoAnsibleGroup
        location: westeurope
      register: rg

    - name: Crear un conjunto de disponibilidad
      azure_rm_availabilityset:
        resource_group: TestCursoAnsibleGroup
        name: miConjuntoDisponibilidad
        location: westeurope
      when: rg is succeeded

    - name: Crear una red virtual
      azure_rm_virtualnetwork:
        resource_group: TestCursoAnsibleGroup
        name: miRedVirtual
        address_prefixes: "10.0.0.0/16"
        location: westeurope
      when: rg is succeeded

    - name: Crear una subred
      azure_rm_subnet:
        resource_group: TestCursoAnsibleGroup
        name: miSubRed
        address_prefixes: "10.0.1.0/24"
        virtual_network: miRedVirtual
      when: rg is succeeded

    - name: Crear una interfaz de red
      azure_rm_networkinterface:
        resource_group: TestCursoAnsibleGroup
        name: miInterfazDeRed
        location: westeurope
        virtual_network: miRedVirtual
        subnet_name: miSubRed
      when: rg is succeeded

    - name: Crear VM con imagen de Debian 12
      azure_rm_virtualmachine:
        resource_group: TestCursoAnsibleGroup
        name: miMaquinaVirtual
        admin_username: "{{ username }}"
        admin_password: "{{ password }}"
        vm_size: Standard_B2als_v2
        network_interfaces: miInterfazDeRed
        availability_set: miConjuntoDisponibilidad
        location: westeurope
        image:
          offer: Debian-12
          publisher: Debian
          sku: 12
          version: latest
```

---

## 🔍 Flujo de ejecución tarea a tarea

```
test_ansible_azure.yml  (hosts: localhost — habla con la API REST de Azure)
│
├── [1] azure_rm_resourcegroup       → Crea el grupo de recursos "TestCursoAnsibleGroup"
│       └── register: rg              (contenedor lógico de todos los recursos)
│
├── [2] azure_rm_availabilityset     → Crea conjunto de disponibilidad
│       └── when: rg is succeeded     (garantiza HA entre VMs del mismo grupo)
│
├── [3] azure_rm_virtualnetwork      → Crea la VNet 10.0.0.0/16
│       └── when: rg is succeeded     (red privada aislada en Azure)
│
├── [4] azure_rm_subnet              → Crea la subred 10.0.1.0/24 dentro de la VNet
│       └── when: rg is succeeded     (segmento de red para las VMs)
│
├── [5] azure_rm_networkinterface    → Crea la NIC conectada a la subred
│       └── when: rg is succeeded     (interfaz de red que se asignará a la VM)
│
└── [6] azure_rm_virtualmachine      → Crea la VM Debian 12 con la NIC y el availability set
        └── Standard_B2als_v2         (2 vCPU, 4 GB RAM)
```

Cada recurso depende del anterior. El patrón `when: rg is succeeded` garantiza que si el grupo de recursos falla, ninguna tarea posterior se ejecuta — evitando errores en cascada.

---

## 🛠️ Los módulos y recursos en detalle

### `azure_rm_resourcegroup` — El contenedor de todo

```yaml
- name: Crear un grupo de recursos
  azure_rm_resourcegroup:
    name: TestCursoAnsibleGroup
    location: westeurope
  register: rg
```

En Azure, **todo recurso pertenece a un grupo de recursos**. El grupo de recursos es el contenedor lógico que agrupa todos los elementos relacionados (VNet, VMs, NICs, discos...) y permite gestionarlos, facturarlos y eliminarlos como una unidad. `westeurope` corresponde a la región de Amsterdam (Europa Occidental).

El resultado se registra en `rg`. El estado `rg is succeeded` se usa como condición en todas las tareas posteriores.

---

### `azure_rm_availabilityset` — Alta disponibilidad

```yaml
- name: Crear un conjunto de disponibilidad
  azure_rm_availabilityset:
    resource_group: TestCursoAnsibleGroup
    name: miConjuntoDisponibilidad
    location: westeurope
  when: rg is succeeded
```

Un **Availability Set** (conjunto de disponibilidad) es un mecanismo de Azure para garantizar que las VMs de un mismo grupo no fallen todas al mismo tiempo. Azure distribuye las VMs en diferentes **fault domains** (racks físicos) y **update domains** (grupos de actualización), asegurando que al menos una VM esté disponible durante mantenimientos o fallos de hardware.

| **Concepto** | **Significado** |
|---|---|
| **Fault Domain** | Rack físico independiente (alimentación y red propias) |
| **Update Domain** | Grupo de VMs que se reinician juntas en actualizaciones |
| **Beneficio** | SLA del 99.95% de disponibilidad para VMs en el mismo Availability Set |

---

### `azure_rm_virtualnetwork` — Red privada aislada

```yaml
- name: Crear una red virtual
  azure_rm_virtualnetwork:
    resource_group: TestCursoAnsibleGroup
    name: miRedVirtual
    address_prefixes: "10.0.0.0/16"
    location: westeurope
  when: rg is succeeded
```

La **Virtual Network (VNet)** es el equivalente Azure de una VPC en AWS. Define el espacio de direcciones IP privado (`10.0.0.0/16` = 65.536 IPs disponibles) dentro del cual se crean las subredes y las VMs. El tráfico dentro de una VNet es completamente privado y aislado de otras VNets y de Internet por defecto.

---

### `azure_rm_subnet` — Segmentación de la red

```yaml
- name: Crear una subred
  azure_rm_subnet:
    resource_group: TestCursoAnsibleGroup
    name: miSubRed
    address_prefixes: "10.0.1.0/24"
    virtual_network: miRedVirtual
  when: rg is succeeded
```

La subred `10.0.1.0/24` (256 IPs) es un segmento dentro de la VNet `10.0.0.0/16`. Las VMs se conectan a subredes, no directamente a la VNet. Las subredes permiten segmentar la red por función (frontend, backend, base de datos) y aplicar reglas de seguridad (NSG) a nivel de subred.

---

### `azure_rm_networkinterface` — La tarjeta de red de la VM

```yaml
- name: Crear una interfaz de red
  azure_rm_networkinterface:
    resource_group: TestCursoAnsibleGroup
    name: miInterfazDeRed
    location: westeurope
    virtual_network: miRedVirtual
    subnet_name: miSubRed
  when: rg is succeeded
```

En Azure, las VMs no se conectan directamente a la subred — lo hacen a través de una **Network Interface (NIC)**. La NIC es el objeto que tiene la IP privada asignada y que se adjunta a la VM. Este diseño permite, por ejemplo, mover una NIC de una VM a otra, o asignar múltiples NICs a una misma VM.

---

### `azure_rm_virtualmachine` — La máquina virtual

```yaml
- name: Crear VM con imagen de Debian 12
  azure_rm_virtualmachine:
    resource_group: TestCursoAnsibleGroup
    name: miMaquinaVirtual
    admin_username: "{{ username }}"
    admin_password: "{{ password }}"
    vm_size: Standard_B2als_v2
    network_interfaces: miInterfazDeRed
    availability_set: miConjuntoDisponibilidad
    location: westeurope
    image:
      offer: Debian-12
      publisher: Debian
      sku: 12
      version: latest
```

La tarea final crea la VM conectando todos los recursos anteriores:

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `name` | `miMaquinaVirtual` | Nombre de la VM en Azure |
| `admin_username` | `adminuser` | Usuario administrador (acceso SSH/RDP) |
| `admin_password` | `P@ssw0rd123!` | Contraseña del administrador |
| `vm_size` | `Standard_B2als_v2` | 2 vCPU AMD, 4 GB RAM (burstable, económico) |
| `network_interfaces` | `miInterfazDeRed` | NIC creada en el paso anterior |
| `availability_set` | `miConjuntoDisponibilidad` | Availability Set para alta disponibilidad |
| `image.offer` | `Debian-12` | Nombre de la oferta de imagen en Azure Marketplace |
| `image.publisher` | `Debian` | Editor de la imagen |
| `image.sku` | `12` | SKU específico (versión Debian 12 Bookworm) |
| `image.version` | `latest` | Última versión disponible de la imagen |

> **`Standard_B2als_v2`**: Es un tamaño de VM "burstable" de la serie B de Azure. Usa procesadores AMD EPYC, tiene 2 vCPU y 4 GB de RAM. Es ideal para cargas de trabajo de desarrollo y pruebas con uso de CPU intermitente, y tiene un coste muy bajo (~$30/mes en westeurope).

---

## 🚀 Comandos de ejecución

### Ejecutar el playbook completo

```bash
ansible-playbook -i hosts -u vagrant test_ansible_azure.yml
```

> **Nota**: El playbook usa `hosts: localhost` y `connection: local`, por lo que el fichero `-i hosts` es técnicamente opcional. Ansible ejecuta todas las tareas en el nodo de control local, que habla con la API REST de Azure.

### Ejecutar con variables externas (más seguro que hardcodear)

```bash
ansible-playbook -i hosts -u vagrant test_ansible_azure.yml \
  -e "username=miusuario" \
  -e "password=MiPassword123!"
```

### Listar las tareas sin ejecutar

```bash
ansible-playbook -i hosts -u vagrant test_ansible_azure.yml --list-tasks
```

### Verificar sintaxis del playbook

```bash
ansible-playbook -i hosts -u vagrant test_ansible_azure.yml --syntax-check
```

### Conectarse a la VM creada (por SSH)

```bash
ssh adminuser@<IP_PUBLICA_DE_LA_VM>
```

> La IP pública de la VM se puede obtener desde el portal de Azure o con:
> ```bash
> az vm show -d -g TestCursoAnsibleGroup -n miMaquinaVirtual --query publicIps -o tsv
> ```

### Eliminar todos los recursos creados

La forma más eficiente de limpiar todos los recursos es eliminar el grupo de recursos completo:

```bash
az group delete --name TestCursoAnsibleGroup --yes --no-wait
```

O con Ansible, añadiendo una tarea con `state: absent`:

```yaml
- name: Eliminar grupo de recursos
  azure_rm_resourcegroup:
    name: TestCursoAnsibleGroup
    state: absent
```

---

## 🏗️ Comparativa: AWS (031) vs. Azure (032)

| **Aspecto** | **031 — AWS** | **032 — Azure** |
|---|---|---|
| **Colección Ansible** | `amazon.aws` | `azure.azcollection` |
| **CLI de autenticación** | `aws configure` | `az login` |
| **Contenedor lógico** | No requerido (cuenta AWS) | ⭐ Resource Group obligatorio |
| **Red por defecto** | VPC y subnets por defecto existen | ⭐ Hay que crear VNet y subnet |
| **Interfaz de red** | Implícita en la subnet | ⭐ NIC explícita y separada |
| **Alta disponibilidad** | Auto Scaling Groups / AZs | ⭐ Availability Sets |
| **Imagen de VM** | AMI ID (`ami-02b7d5b1e55a7b5f1`) | offer/publisher/sku/version |
| **Sistema operativo** | Amazon Linux 2023 | Debian 12 (Bookworm) |
| **Tamaño de VM** | `t2.micro` (1 vCPU, 1 GB) | `Standard_B2als_v2` (2 vCPU, 4 GB) |
| **Inventario dinámico** | ⭐ `add_host` + `ec2_instance_info` | No implementado en este ejemplo |
| **Destrucción automática** | ⭐ `state: absent` al final | Manual (`az group delete`) |
| **Complejidad de red** | Baja (subnet preexistente) | ⭐ Alta (VNet → Subnet → NIC → VM) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Modelo de recursos de Azure**: En Azure, todo recurso tiene una jerarquía clara: `Suscripción → Resource Group → Recurso`. El Resource Group es obligatorio y actúa como unidad de gestión, facturación y ciclo de vida. Eliminar el Resource Group elimina todos sus recursos.

- **Infraestructura de red explícita**: A diferencia de AWS (donde existe una VPC por defecto), en Azure hay que crear explícitamente la VNet, la subred y la NIC antes de poder lanzar una VM. Esto da más control pero requiere más pasos.

- **Dependencias con `when: rg is succeeded`**: El patrón `register: rg` + `when: rg is succeeded` implementa un **circuit breaker** simple: si el grupo de recursos no se crea correctamente, ninguna tarea posterior se ejecuta. Esto evita errores en cascada y mensajes de error confusos.

- **`connection: local`**: La directiva `connection: local` en el play indica a Ansible que no intente conectarse por SSH a ningún host — todas las tareas se ejecutan localmente en el nodo de control. Es equivalente a `hosts: localhost` pero más explícito sobre el método de conexión.

- **Módulos `azure_rm_*`**: Los módulos de la colección `azure.azcollection` siguen la convención `azure_rm_<recurso>`. Son **idempotentes**: si el recurso ya existe con la configuración especificada, el módulo no hace nada y reporta `ok`. Si el recurso no existe, lo crea (`changed`). Si el recurso existe con una configuración diferente, lo actualiza.

- **Imágenes en Azure Marketplace**: Las imágenes de VM en Azure se identifican por cuatro campos: `publisher` (quién publica la imagen), `offer` (nombre del producto), `sku` (variante específica) y `version`. Esto es más descriptivo que los AMI IDs de AWS, que son opacos y específicos por región.

- **Buenas prácticas de seguridad**: El playbook hardcodea credenciales en el fichero YAML, lo cual es una mala práctica. En producción se debe usar `ansible-vault encrypt_string` para cifrar contraseñas, o variables de entorno con `lookup('env', 'AZURE_PASSWORD')`.

---

## 📚 Referencias

- [Ansible Docs — `azure.azcollection`](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/index.html)
- [Ansible Docs — `azure_rm_resourcegroup`](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_rm_resourcegroup_module.html)
- [Ansible Docs — `azure_rm_virtualmachine`](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_rm_virtualmachine_module.html)
- [Ansible Docs — `azure_rm_virtualnetwork`](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/azure_rm_virtualnetwork_module.html)
- [Microsoft Docs — Azure CLI Installation](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [Microsoft Docs — Azure VM Sizes — Serie B](https://learn.microsoft.com/en-us/azure/virtual-machines/bv2-series)
- [Microsoft Docs — Availability Sets](https://learn.microsoft.com/en-us/azure/virtual-machines/availability-set-overview)
- [Microsoft Docs — Azure Virtual Network](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview)
- [Ansible Docs — `ansible-vault`](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
