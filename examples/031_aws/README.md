# 📋 Ejemplo 031 — `aws`: Aprovisionamiento dinámico de instancias EC2 con Ansible

## 🧭 Descripción general

Este ejemplo introduce un nuevo paradigma en la serie: **infraestructura en la nube**. Por primera vez, Ansible no gestiona máquinas que ya existen (como las VMs de Vagrant de los ejemplos anteriores), sino que **crea la infraestructura desde cero** en AWS y la gestiona dinámicamente. El playbook levanta instancias EC2, obtiene sus IPs públicas, las añade al inventario en tiempo de ejecución, guarda el inventario en un fichero y finalmente destruye las instancias — todo en un único playbook.

El concepto central que introduce este ejemplo es el **inventario dinámico**: en lugar de definir IPs fijas en un fichero `hosts` estático, Ansible consulta la API de AWS en tiempo real para descubrir qué máquinas existen y construye el inventario sobre la marcha. Esto es fundamental para entornos cloud donde las IPs cambian con cada arranque y las instancias se crean y destruyen bajo demanda.

Este ejemplo es completamente independiente del stack Linux de los ejemplos anteriores. No usa el fichero `hosts` del enunciado ni los roles MySQL/Apache/Nginx. Todo se ejecuta contra `localhost` (el nodo de control) que habla con la API de AWS a través de la colección `amazon.aws`.

---

## 🗂️ Estructura del proyecto

```
031_aws/
├── README.md           # Instrucciones de configuración de AWS CLI y colecciones
└── aws-example.yml     # ⭐ Playbook: crear EC2, inventariar, destruir
```

Este ejemplo es minimalista por diseño: no hay roles, no hay `group_vars`, no hay `site.yml`. El foco está en demostrar la integración de Ansible con la API de AWS mediante la colección `amazon.aws`.

---

## 🔧 Configuración previa — Prerrequisitos

Antes de ejecutar el playbook, el nodo de control (la máquina desde donde se ejecuta Ansible) necesita tener instaladas las colecciones de AWS, el cliente AWS CLI y una clave SSH para las instancias EC2. Sigue estos pasos en orden.

---

### Paso 1 — Instalación de las colecciones de AWS

Las colecciones de Ansible para AWS proporcionan los módulos `amazon.aws.ec2_instance`, `amazon.aws.ec2_instance_info`, etc.:

```bash
ansible-galaxy collection install amazon.cloud
ansible-galaxy collection install amazon.aws
```

| **Colección** | **Contenido** |
|---|---|
| `amazon.aws` | Módulos core de AWS: EC2, S3, VPC, IAM, RDS... |
| `amazon.cloud` | Módulos de alto nivel para servicios cloud de AWS |

---

### Paso 2 — Instalación del cliente AWS CLI en el nodo de control

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip
unzip awscliv2.zip
sudo ./aws/install
aws --version
aws configure   # Se necesita un usuario IAM con acceso programático
```

`aws configure` solicitará cuatro valores:

| **Campo** | **Descripción** |
|---|---|
| `AWS Access Key ID` | ID de la clave de acceso del usuario IAM |
| `AWS Secret Access Key` | Clave secreta del usuario IAM |
| `Default region name` | Región por defecto (ej. `eu-central-1`) |
| `Default output format` | Formato de salida (ej. `json`) |

Estos valores se guardan en `~/.aws/credentials` y `~/.aws/config`. La colección `amazon.aws` los lee automáticamente — no es necesario declararlos en el playbook.

### Verificar que la autenticación funciona

```bash
aws sts get-caller-identity
```

Devuelve el `Account`, `UserId` y `Arn` del usuario IAM configurado. Si este comando funciona, Ansible también podrá autenticarse contra AWS.

---

### Paso 3 — Creación de la clave SSH para las instancias EC2

Las instancias EC2 necesitan una clave SSH para poder acceder a ellas después de crearlas. Este comando crea el par de claves en AWS y guarda la clave privada localmente:

```bash
aws ec2 create-key-pair \
  --key-name mi-clave-ec2 \
  --query "KeyMaterial" \
  --output text > /home/vagrant/.ssh/mi-clave-ec2.pem

chmod 400 /home/vagrant/.ssh/mi-clave-ec2.pem
```

| **Comando** | **Efecto** |
|---|---|
| `aws ec2 create-key-pair` | Crea el par de claves en AWS y devuelve la clave privada |
| `--key-name mi-clave-ec2` | Nombre de la clave en AWS (se referencia en el playbook) |
| `--query "KeyMaterial"` | Extrae solo el contenido PEM de la respuesta JSON |
| `> /home/vagrant/.ssh/mi-clave-ec2.pem` | Guarda la clave privada en disco |
| `chmod 400` | Permisos de solo lectura para el propietario (SSH lo requiere) |

> **⚠️ Importante**: La clave privada (`.pem`) solo se puede descargar en el momento de creación. AWS no la almacena. Si se pierde, hay que crear un nuevo par de claves.

---

## 📋 Variables del playbook

```yaml
vars:
  key_name: mi-clave-ec2.pem
  region: eu-central-1
  instance_type: t2.micro
  image: ami-02b7d5b1e55a7b5f1   # Amazon Linux 2023 AMI, kernel 6.1, x86_64
```

| **Variable** | **Valor** | **Significado** |
|---|---|---|
| `key_name` | `mi-clave-ec2.pem` | Nombre del par de claves SSH creado en el Paso 3 |
| `region` | `eu-central-1` | Región AWS (Frankfurt) donde se crean las instancias |
| `instance_type` | `t2.micro` | Tipo de instancia (1 vCPU, 1 GB RAM — elegible para free tier) |
| `image` | `ami-02b7d5b1e55a7b5f1` | Amazon Linux 2023, kernel 6.1, arquitectura x86_64 |

> **Nota sobre la AMI**: Las AMIs son específicas por región. La AMI `ami-02b7d5b1e55a7b5f1` es válida para `eu-central-1` (Frankfurt). Si cambias la región, debes buscar el ID de AMI correspondiente en esa región.

---

## 📄 `aws-example.yml` — El playbook

```yaml
- name: Levantar instancias EC2 y configurar SSH
  hosts: localhost
  gather_facts: no
  vars:
    key_name: mi-clave-ec2.pem
    region: eu-central-1
    instance_type: t2.micro
    image: ami-02b7d5b1e55a7b5f1
  tasks:
    - name: Create instances EC2 with SSH key
      amazon.aws.ec2_instance:
        name: "{{ item }}"
        key_name: "{{ key_name }}"
        region: "{{ region }}"
        instance_type: "{{ instance_type }}"
        image_id: "{{ image }}"
        vpc_subnet_id: subnet-0426901b07d63d0f4
      loop:
        - instancia-curso-ansible-1
        - instancia-curso-ansible-2

    - name: Show public instance_types
      amazon.aws.ec2_instance_info:
        region: "{{ region }}"
      register: ec2_info

    - name: Show public IPs
      debug:
        msg: "Public IP: {{ item.public_ip_address }}"
      loop: "{{ ec2_info.instances }}"

    - name: Add instances to inventory
      add_host:
        name: "{{ item.public_ip_address }}"
        ansible_user: ec2-user
        ansible_ssh_private_key_file: "{{ key_name }}"
      loop: "{{ ec2_info.instances }}"

    - name: Save EC2 hosts to file
      copy:
        content: |
          [ec2_instances]
          {% for instance in ec2_info.instances %}
          {{ instance.public_dns_name }}    {{ instance.public_ip_address }}
          {% endfor %}
        dest: ./ec2_hosts.ini

    - name: Delete EC2 instances
      amazon.aws.ec2_instance:
        state: absent
        region: "{{ region }}"
        instance_ids: "{{ ec2_info.instances | map(attribute='id') | list }}"
      when: ec2_info.instances | length > 0
```

---

## 🔍 Flujo de ejecución tarea a tarea

```
aws-example.yml  (hosts: localhost — habla con la API de AWS)
│
├── [1] amazon.aws.ec2_instance   → Crea 2 instancias EC2 en AWS (loop)
│       ├── instancia-curso-ansible-1
│       └── instancia-curso-ansible-2
│
├── [2] amazon.aws.ec2_instance_info → Consulta la API: obtiene info de TODAS las instancias
│       └── Guarda resultado en ec2_info
│
├── [3] debug                     → Imprime la IP pública de cada instancia
│
├── [4] add_host                  → ⭐ Añade las IPs al inventario en memoria (dinámico)
│       ├── ansible_user: ec2-user
│       └── ansible_ssh_private_key_file: mi-clave-ec2.pem
│
├── [5] copy (template Jinja2)    → Genera ec2_hosts.ini con DNS + IPs de las instancias
│
└── [6] amazon.aws.ec2_instance   → Destruye todas las instancias (state: absent)
        └── when: hay instancias activas
```

---

## 🛠️ Los módulos y técnicas en detalle

### `amazon.aws.ec2_instance` — Crear y destruir instancias EC2

```yaml
- name: Create instances EC2 with SSH key
  amazon.aws.ec2_instance:
    name: "{{ item }}"
    key_name: "{{ key_name }}"
    region: "{{ region }}"
    instance_type: "{{ instance_type }}"
    image_id: "{{ image }}"
    vpc_subnet_id: subnet-0426901b07d63d0f4
  loop:
    - instancia-curso-ansible-1
    - instancia-curso-ansible-2
```

El módulo `amazon.aws.ec2_instance` es el equivalente cloud de `apt` o `service` — gestiona el ciclo de vida de instancias EC2. Con `loop`, Ansible llama al módulo dos veces, una por cada nombre de instancia.

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `name` | `instancia-curso-ansible-1` | Nombre de la instancia (tag `Name` en AWS) |
| `key_name` | `mi-clave-ec2.pem` | Par de claves SSH para acceso posterior |
| `region` | `eu-central-1` | Región AWS donde se lanza la instancia |
| `instance_type` | `t2.micro` | Hardware de la instancia |
| `image_id` | `ami-02b7d5b1e55a7b5f1` | Sistema operativo (Amazon Linux 2023) |
| `vpc_subnet_id` | `subnet-0426901b07d63d0f4` | Subred VPC donde se lanza la instancia |

El mismo módulo con `state: absent` destruye las instancias al final del playbook.

---

### `amazon.aws.ec2_instance_info` — Inventario dinámico desde AWS

```yaml
- name: Show public instance_types
  amazon.aws.ec2_instance_info:
    region: "{{ region }}"
  register: ec2_info
```

Consulta la API de AWS y devuelve información completa de todas las instancias en la región. El resultado registrado en `ec2_info` contiene una lista `instances` con objetos que incluyen `public_ip_address`, `public_dns_name`, `instance_id`, `state`, etc.

Este es el núcleo del **inventario dinámico**: en lugar de tener IPs hardcodeadas en un fichero `hosts`, Ansible pregunta a AWS "¿qué instancias tienes?" y construye el inventario con la respuesta.

---

### `add_host` — Inventario dinámico en memoria

```yaml
- name: Add instances to inventory
  add_host:
    name: "{{ item.public_ip_address }}"
    ansible_user: ec2-user
    ansible_ssh_private_key_file: "{{ key_name }}"
  loop: "{{ ec2_info.instances }}"
```

`add_host` es el módulo que materializa el inventario dinámico. Añade hosts al inventario de Ansible **en tiempo de ejecución**, sin necesidad de un fichero `hosts` estático. Los hosts añadidos con `add_host` están disponibles para plays posteriores en el mismo playbook.

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `name` | IP pública de la instancia | Identificador del host en el inventario |
| `ansible_user` | `ec2-user` | Usuario SSH de Amazon Linux (equivalente a `ubuntu` en Ubuntu) |
| `ansible_ssh_private_key_file` | `mi-clave-ec2.pem` | Clave privada para autenticarse por SSH |

---

### `copy` con plantilla Jinja2 — Generar el fichero de inventario

```yaml
- name: Save EC2 hosts to file
  copy:
    content: |
      [ec2_instances]
      {% for instance in ec2_info.instances %}
      {{ instance.public_dns_name }}    {{ instance.public_ip_address }}
      {% endfor %}
    dest: ./ec2_hosts.ini
```

Genera un fichero `ec2_hosts.ini` en el directorio actual con el DNS y la IP de cada instancia. El resultado tiene este aspecto:

```ini
[ec2_instances]
ec2-18-184-12-45.eu-central-1.compute.amazonaws.com    18.184.12.45
ec2-3-68-99-201.eu-central-1.compute.amazonaws.com     3.68.99.201
```

Este fichero puede usarse como inventario estático en ejecuciones posteriores:

```bash
ansible-playbook -i ec2_hosts.ini otro_playbook.yml
```

---

### Destrucción de instancias con `when`

```yaml
- name: Delete EC2 instances
  amazon.aws.ec2_instance:
    state: absent
    region: "{{ region }}"
    instance_ids: "{{ ec2_info.instances | map(attribute='id') | list }}"
  when: ec2_info.instances | length > 0
```

Destruye todas las instancias usando sus IDs. El filtro Jinja2 `map(attribute='id') | list` extrae solo los IDs de la lista de objetos `ec2_info.instances`. La condición `when: ec2_info.instances | length > 0` evita que el módulo falle si no hay instancias que destruir.

---

## 🚀 Comandos de ejecución

### Ejecutar el playbook completo

```bash
ansible-playbook -i hosts -u vagrant aws-example.yml
```

> **Nota**: El playbook usa `hosts: localhost`, por lo que el fichero `-i hosts` es técnicamente opcional para este playbook. Ansible ejecutará todas las tareas en el nodo de control local, que habla con la API de AWS.

### Ejecutar sin destruir las instancias al final

Para mantener las instancias activas después de la ejecución (útil para conectarse a ellas), comenta o elimina la última tarea `Delete EC2 instances` antes de ejecutar.

### Conectarse a una instancia EC2 creada

```bash
ssh -i /home/vagrant/.ssh/mi-clave-ec2.pem ec2-user@<IP_PUBLICA>
```

### Usar el fichero de inventario generado

```bash
ansible-playbook -i ec2_hosts.ini otro_playbook.yml \
  --private-key /home/vagrant/.ssh/mi-clave-ec2.pem \
  -u ec2-user
```

### Listar las tareas del playbook sin ejecutar

```bash
ansible-playbook -i hosts -u vagrant aws-example.yml --list-tasks
```

---

## 🏗️ Comparativa: Inventario estático vs. Inventario dinámico

| **Aspecto** | **Estático (ejemplos 025-029)** | **Dinámico (ejemplo 031)** |
|---|---|---|
| **Definición de hosts** | Fichero `hosts` con IPs fijas | API de AWS consultada en tiempo real |
| **IPs** | Fijas y conocidas de antemano | Asignadas por AWS al crear la instancia |
| **Escalabilidad** | Manual (añadir IPs a mano) | Automática (descubre todas las instancias) |
| **Creación de infraestructura** | Preexistente (Vagrant) | ⭐ Ansible la crea (`ec2_instance`) |
| **Destrucción de infraestructura** | Manual | ⭐ Ansible la destruye (`state: absent`) |
| **Módulo de inventario** | Fichero `hosts` | `add_host` + `ec2_instance_info` |
| **Entorno** | Local (VirtualBox) | ⭐ Cloud (AWS) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Infrastructure as Code (IaC) con Ansible**: Este ejemplo va más allá de la gestión de configuración — Ansible crea y destruye infraestructura cloud. El mismo playbook que aprovisiona las instancias también las destruye, cerrando el ciclo completo de vida de la infraestructura.

- **Inventario dinámico**: En entornos cloud, las IPs son efímeras. El inventario dinámico resuelve este problema consultando la API del proveedor cloud en tiempo real. `amazon.aws.ec2_instance_info` + `add_host` es el patrón estándar para inventario dinámico en AWS con Ansible.

- **`hosts: localhost`**: El playbook se ejecuta en `localhost` (el nodo de control), no en los nodos gestionados. Ansible habla con la API REST de AWS directamente desde el nodo de control usando las credenciales de `aws configure`. Las instancias EC2 no necesitan tener Ansible instalado.

- **Colecciones de Ansible (`amazon.aws`)**: Las colecciones son la forma moderna de distribuir módulos, plugins y roles en Ansible. `amazon.aws` es la colección oficial de AWS, mantenida por Red Hat y la comunidad. Se instala con `ansible-galaxy collection install`.

- **FQCN en módulos de colecciones**: Los módulos de colecciones siempre se referencian con su FQCN completo: `amazon.aws.ec2_instance`, `amazon.aws.ec2_instance_info`. Esto distingue los módulos de colecciones de los módulos built-in de Ansible.

- **Filtros Jinja2 para transformar datos**: `{{ ec2_info.instances | map(attribute='id') | list }}` es un ejemplo de pipeline de filtros Jinja2: `map` extrae el atributo `id` de cada objeto, y `list` convierte el resultado en una lista Python. Este patrón es fundamental para trabajar con datos estructurados en Ansible.

- **Idempotencia en cloud**: `amazon.aws.ec2_instance` con `state: absent` es idempotente — si las instancias ya no existen, no falla. La condición `when: ec2_info.instances | length > 0` añade una capa extra de seguridad.

---

## 📚 Referencias

- [Ansible Docs — `amazon.aws` collection](https://docs.ansible.com/ansible/latest/collections/amazon/aws/index.html)
- [Ansible Docs — `amazon.aws.ec2_instance` module](https://docs.ansible.com/ansible/latest/collections/amazon/aws/ec2_instance_module.html)
- [Ansible Docs — `amazon.aws.ec2_instance_info` module](https://docs.ansible.com/ansible/latest/collections/amazon/aws/ec2_instance_info_module.html)
- [Ansible Docs — `add_host` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/add_host_module.html)
- [Ansible Docs — Dynamic Inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_dynamic_inventory.html)
- [AWS Docs — AWS CLI Installation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [AWS Docs — EC2 Key Pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
- [AWS Docs — Amazon Linux 2023 AMIs](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html)
