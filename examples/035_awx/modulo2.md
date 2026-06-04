# 🗂️ MÓDULO 2 — Inventarios, Credenciales y Proyectos
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 2.1 | Modelo mental: los tres bloques de construcción |
| 2.2 | Inventarios: tipos, cuándo usar cada uno |
| 2.3 | Inventarios estáticos en profundidad |
| 2.4 | Inventarios en SCM (YAML versionado en Git) |
| 2.5 | Inventarios dinámicos: plugins de cloud |
| 2.6 | Credenciales: tipos, seguridad y patrones |
| 2.7 | Proyectos: estrategias de sync y pins |
| 2.8 | LAB — Inventario estático con grupos dev/stage/prod |
| 2.9 | LAB — Credenciales SSH, Vault y Cloud |
| 2.10 | LAB — Inventario dinámico AWS EC2 |
| 2.11 | LAB — Inventario dinámico Azure |
| 2.12 | LAB — Proyecto SCM con Webhook auto-sync |
| 2.13 | LAB — Inventario en SCM (YAML en Git) |
| 2.14 | Patrones avanzados y buenas prácticas |
| 2.15 | Troubleshooting del módulo |
| 2.16 | Resumen y checklist |

**Duración estimada:** 60-75 minutos  
**Tipo:** Lab intensivo  
**Prerrequisitos:** Módulo 1 completado, AWX funcionando con K3s

---

# 2.1 Modelo mental: los tres bloques de construcción

Antes de entrar en configuración, entiende el rol de cada bloque y cómo se relacionan.

```
┌─────────────────────────────────────────────────────────────────┐
│                    JOB TEMPLATE (el director)                    │
│                                                                  │
│   "Ejecuta este playbook, en estos hosts,                        │
│    con estas credenciales, usando este entorno"                  │
└──────────┬──────────────────┬──────────────────┬────────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
    ┌─────────────┐   ┌──────────────┐   ┌──────────────┐
    │  PROYECTO   │   │  INVENTARIO  │   │ CREDENCIALES │
    │             │   │              │   │              │
    │ Contiene    │   │ Contiene     │   │ Contienen    │
    │ el playbook │   │ los hosts    │   │ los secretos │
    │ (desde Git) │   │ (dónde       │   │ (cómo        │
    │             │   │  ejecutar)   │   │  conectar)   │
    └─────────────┘   └──────────────┘   └──────────────┘
           │                  │                  │
           ▼                  ▼                  ▼
    ┌─────────────┐   ┌──────────────┐   ┌──────────────┐
    │  Git repo   │   │  Hosts/IPs   │   │  SSH keys    │
    │  playbooks  │   │  Groups      │   │  Passwords   │
    │  roles      │   │  Variables   │   │  API tokens  │
    │  collections│   │  (estático,  │   │  Vault pass  │
    │             │   │   dinámico)  │   │  Cloud creds │
    └─────────────┘   └──────────────┘   └──────────────┘
```

**La pregunta que debes hacerte al configurar cada objeto:**

```
PROYECTO:    ¿De dónde viene el código? ¿Qué rama/tag/commit?
INVENTARIO:  ¿Dónde ejecuto? ¿Qué hosts? ¿Qué grupos?
CREDENCIAL:  ¿Cómo me autentico? ¿Qué secretos necesito?
```

---

# 2.2 Inventarios: tipos, cuándo usar cada uno

AWX soporta cuatro estrategias de inventario. Cada una tiene su caso de uso ideal.

## Los cuatro tipos

```
TIPO 1: ESTÁTICO (UI)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Hosts definidos manualmente en la UI de AWX
  
  ✅ Ideal para: labs, entornos pequeños y estables, PoCs
  ❌ Evitar en: infraestructura que cambia frecuentemente
  
  Ejemplo: 3 servidores on-prem que nunca cambian de IP

TIPO 2: YAML EN SCM (Git)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Fichero de inventario en el mismo repo que los playbooks
  
  ✅ Ideal para: on-prem versionado, inventarios que cambian
                 via PR/review, equipos con GitOps
  ❌ Evitar en: infraestructura cloud que crece/decrece dinámicamente
  
  Ejemplo: inventario de servidores físicos gestionado como código

TIPO 3: DINÁMICO (Plugins de cloud)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Plugin que consulta la API del cloud en tiempo real
  
  ✅ Ideal para: AWS EC2, Azure VMs, GCP Compute, VMware, etc.
  ❌ Evitar en: entornos sin API o con latencia muy alta
  
  Ejemplo: instancias EC2 con tag AnsibleManaged=true

TIPO 4: SCRIPT PERSONALIZADO (legacy)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Script ejecutable que devuelve JSON
  
  ✅ Ideal para: CMDBs propietarias, sistemas legacy sin plugin
  ❌ Evitar en: nuevos proyectos (preferir plugins nativos)
  
  Ejemplo: script que consulta una CMDB interna
```

## Tabla de decisión rápida

| Situación | Tipo recomendado |
|-----------|-----------------|
| Lab o PoC con 5-10 hosts | Estático (UI) |
| On-prem con hosts estables | YAML en SCM |
| AWS/Azure/GCP con autoscaling | Dinámico (plugin cloud) |
| VMware vSphere | Dinámico (community.vmware) |
| CMDB interna con API REST | Script personalizado o plugin custom |
| Mezcla on-prem + cloud | Múltiples fuentes en un inventario |

---

# 2.3 Inventarios estáticos en profundidad

El inventario estático es el punto de partida. Aunque en producción uses inventarios dinámicos, entender la estructura estática es fundamental porque es la misma que usan los inventarios YAML en SCM.

## Estructura de grupos y hosts

```
INVENTARIO
├── all (grupo implícito, contiene todos los hosts)
│   ├── ungrouped (hosts sin grupo explícito)
│   ├── dev
│   │   ├── dev-web1
│   │   ├── dev-web2
│   │   └── dev-db1
│   ├── stage
│   │   ├── stg-web1
│   │   └── stg-db1
│   └── prod
│       ├── prod-web1
│       ├── prod-web2
│       └── prod-db1
```

## Variables en inventarios: jerarquía de precedencia

AWX respeta la misma jerarquía de variables que Ansible CLI:

```
MENOR PRECEDENCIA
     │
     ▼
  group_vars/all          → variables para todos los hosts
  group_vars/<grupo>      → variables para un grupo específico
  host_vars/<host>        → variables para un host específico
     │
     ▼
MAYOR PRECEDENCIA
```

**Ejemplo práctico de variables por grupo:**

```yaml
# Variables del grupo "all" (aplican a todos)
ansible_user: ansible
ansible_python_interpreter: /usr/bin/python3
ntp_server: ntp.empresa.com
log_level: info

# Variables del grupo "dev"
env: dev
app_port: 8080
debug_mode: true
db_host: dev-db1
replica_count: 1

# Variables del grupo "prod"
env: prod
app_port: 80
debug_mode: false
db_host: prod-db1
replica_count: 3
```

**Variables de host (sobrescriben las de grupo):**

```yaml
# Variables del host "prod-web1"
ansible_host: 10.0.1.10
ansible_port: 22
primary_node: true          # solo este host es el primario
maintenance_window: "02:00-04:00"
```

## Patrones de Limit para targeting preciso

El campo `Limit` en un Job Template permite ejecutar en un subconjunto del inventario:

```bash
# Ejemplos de patrones de Limit:

dev                    # todos los hosts del grupo dev
prod                   # todos los hosts del grupo prod
dev,stage              # hosts de dev Y stage
dev-web1               # solo este host específico
web*                   # todos los hosts cuyo nombre empieza por "web"
prod:&web              # hosts que están en prod Y en web (intersección)
prod:!prod-db1         # hosts de prod EXCEPTO prod-db1
~prod-web[0-9]+        # regex: hosts de prod que terminan en número
all                    # todos los hosts (equivale a no poner Limit)
```

---

# 2.4 Inventarios en SCM (YAML versionado en Git)

Esta es la estrategia recomendada para on-prem: el inventario vive en el mismo repo que los playbooks, se revisa como código y tiene historial de cambios.

## Estructura del repo con inventario en SCM

```
ansible-playbooks/
├── playbooks/
│   ├── deploy_web.yml
│   └── configure_db.yml
├── inventory/
│   ├── dev/
│   │   ├── hosts.yml          ← inventario del entorno dev
│   │   └── group_vars/
│   │       ├── all.yml        ← vars para todos los hosts de dev
│   │       ├── web.yml        ← vars para el grupo web en dev
│   │       └── db.yml         ← vars para el grupo db en dev
│   ├── stage/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── prod/
│       ├── hosts.yml
│       └── group_vars/
└── roles/
```

## Formato del fichero hosts.yml

```yaml
# inventory/dev/hosts.yml
---
all:
  vars:
    # Variables globales para el entorno dev
    env: dev
    ansible_user: ansible
    ansible_python_interpreter: /usr/bin/python3
    
  children:
    web:
      hosts:
        dev-web1:
          ansible_host: 192.168.1.10
          node_role: primary
        dev-web2:
          ansible_host: 192.168.1.11
          node_role: secondary
      vars:
        app_port: 8080
        nginx_worker_processes: 2
        
    db:
      hosts:
        dev-db1:
          ansible_host: 192.168.1.20
          db_role: master
      vars:
        mysql_max_connections: 100
        mysql_innodb_buffer_pool_size: 512M
        
    monitoring:
      hosts:
        dev-mon1:
          ansible_host: 192.168.1.30
```

```yaml
# inventory/prod/hosts.yml
---
all:
  vars:
    env: prod
    ansible_user: ansible
    ansible_python_interpreter: /usr/bin/python3
    
  children:
    web:
      hosts:
        prod-web1:
          ansible_host: 10.0.1.10
          node_role: primary
        prod-web2:
          ansible_host: 10.0.1.11
          node_role: secondary
        prod-web3:
          ansible_host: 10.0.1.12
          node_role: secondary
      vars:
        app_port: 80
        nginx_worker_processes: 4
        
    db:
      hosts:
        prod-db1:
          ansible_host: 10.0.2.10
          db_role: master
        prod-db2:
          ansible_host: 10.0.2.11
          db_role: replica
      vars:
        mysql_max_connections: 500
        mysql_innodb_buffer_pool_size: 4G
```

## Configurar el Inventory Source apuntando al SCM

```
AWX → Inventories → Mi Inventario → Sources → Add

  Name:             Dev Hosts (SCM)
  Source:           Sourced from a Project
  Project:          Platform Playbooks
  Inventory file:   inventory/dev/hosts.yml
  
  Update Options:
    ✅ Overwrite
    ✅ Overwrite Vars
    ✅ Update on Launch
```

---

# 2.5 Inventarios dinámicos: plugins de cloud

Los plugins dinámicos consultan la API del proveedor cloud en tiempo real. El resultado es un inventario que siempre refleja el estado actual de la infraestructura.

## Cómo funcionan los plugins

```
AWX lanza el Inventory Sync
         │
         ▼
Plugin ejecuta dentro del EE
         │
         ▼
Plugin llama a la API del cloud
(AWS DescribeInstances, Azure ListVMs, etc.)
         │
         ▼
Plugin filtra por tags/región/estado
         │
         ▼
Plugin genera grupos automáticamente
(por región, por tag, por tipo de instancia...)
         │
         ▼
AWX almacena hosts y variables en PostgreSQL
         │
         ▼
Job Template usa el inventario actualizado
```

## Plugin AWS EC2 — Configuración detallada

```yaml
# inventory/aws_ec2.yml
# Este fichero va en tu repo Git y se referencia desde AWX

---
plugin: amazon.aws.aws_ec2

# Regiones a consultar
regions:
  - eu-west-1
  - eu-west-2
  - us-east-1

# Filtros: solo instancias con estos tags y en estado running
filters:
  tag:AnsibleManaged:
    - "true"
  instance-state-name:
    - running

# Cómo conectar a los hosts
# Preferir IP privada si estamos en la misma VPC/VPN
hostnames:
  - private-ip-address
  - public-ip-address
  - dns-name

# Componer variables de host desde atributos de EC2
compose:
  ansible_host: private_ip_address
  instance_type: instance_type
  aws_region: placement.region
  aws_az: placement.availability_zone

# Crear grupos automáticamente desde tags
keyed_groups:
  # Grupo por tag Environment: tag_Environment_dev, tag_Environment_prod
  - prefix: tag
    key: tags
    
  # Grupo por región: aws_eu_west_1
  - prefix: aws
    key: placement.region
    separator: "_"
    
  # Grupo por tipo de instancia: type_t3_medium
  - prefix: type
    key: instance_type
    separator: "_"
    
  # Grupo por tag Role: role_web, role_db, role_app
  - prefix: role
    key: tags.Role

# Grupos estáticos adicionales basados en condiciones
groups:
  # Grupo "large_instances" para instancias con mucha RAM
  large_instances: instance_type in ['m5.xlarge', 'm5.2xlarge', 'r5.xlarge']
  
  # Grupo "eu_hosts" para instancias en Europa
  eu_hosts: placement.region.startswith('eu-')
```

## Plugin Azure Resource Manager — Configuración detallada

```yaml
# inventory/azure_rm.yml
---
plugin: azure.azcollection.azure_rm

# Filtrar por grupos de recursos
include_vm_resource_groups:
  - rg-production
  - rg-staging

# Excluir VMs en estado deallocated
exclude_host_filters:
  - powerstate != 'running'

# Componer variables desde atributos de Azure
compose:
  ansible_host: private_ipv4_addresses[0]
  vm_size: hw_machine_type
  azure_location: location
  azure_resource_group: resource_group

# Grupos por tags de Azure
keyed_groups:
  - prefix: tag
    key: tags
  - prefix: location
    key: location
  - prefix: os
    key: os_disk.operating_system_type
```

## Plugin GCP Compute — Configuración básica

```yaml
# inventory/gcp_compute.yml
---
plugin: google.cloud.gcp_compute

# Proyectos GCP a consultar
projects:
  - mi-proyecto-gcp-prod

# Zonas (o usar "zones: []" para todas)
zones:
  - europe-west1-b
  - europe-west1-c

# Filtros
filters:
  - status = RUNNING
  - labels.ansible_managed = true

# Componer variables
compose:
  ansible_host: networkInterfaces[0].networkIP
  gcp_zone: zone
  gcp_machine_type: machineType

# Grupos por labels de GCP
keyed_groups:
  - prefix: label
    key: labels
  - prefix: zone
    key: zone
```

---

# 2.6 Credenciales: tipos, seguridad y patrones

Las credenciales son el componente más sensible de AWX. Entender cómo funcionan internamente te ayuda a diseñar un sistema seguro.

## Cómo AWX protege las credenciales

```
ALMACENAMIENTO:
  Credencial guardada → cifrada con AES-256 en PostgreSQL
  La clave de cifrado es la SECRET_KEY de AWX
  Nadie puede ver el valor real desde la UI (campo enmascarado)

INYECCIÓN EN TIEMPO DE EJECUCIÓN:
  Job lanzado → Task Service descifra la credencial
  Se inyecta de forma efímera en el contenedor EE:
  
  SSH Key     → fichero temporal /tmp/awx_xxx (chmod 600)
                se borra al terminar el job
                
  Passwords   → variable de entorno efímera
                no aparece en logs
                
  Cloud creds → variables de entorno (AWS_ACCESS_KEY_ID, etc.)
                disponibles solo durante la ejecución
                
  Vault pass  → variable de entorno ANSIBLE_VAULT_PASSWORD
                o fichero temporal

VISIBILIDAD:
  Admin de AWX: puede ver que existe la credencial, no su valor
  Usuario con Use: puede usar la credencial en templates, no verla
  Usuario con Read: puede ver que existe, no su valor
  Nadie: puede exportar el valor en texto plano desde la UI
```

## Tipo 1: Machine (SSH)

El tipo más usado. Para conectar a hosts Linux/Unix.

```
Campos:
  Username:                ansible (usuario SSH en los hosts)
  Password:                (alternativa a SSH key, menos seguro)
  SSH Private Key:         contenido de la clave privada (-----BEGIN...)
  SSH Private Key Passphrase: si la clave tiene passphrase
  Privilege Escalation Method: sudo / su / pbrun / pfexec / doas
  Privilege Escalation Username: root (o el usuario de escalada)
  Privilege Escalation Password: (si sudo requiere password)
```

**Generar una clave SSH dedicada para AWX:**

```bash
# Generar clave ED25519 (más moderna y segura que RSA)
ssh-keygen -t ed25519 \
  -C "awx-automation-$(date +%Y%m%d)" \
  -f ~/.ssh/awx_automation \
  -N ""  # sin passphrase para automatización

# Ver la clave privada (esto va en AWX)
cat ~/.ssh/awx_automation

# Ver la clave pública (esto va en los hosts)
cat ~/.ssh/awx_automation.pub

# Distribuir la clave pública a los hosts
# Opción 1: manualmente
ssh-copy-id -i ~/.ssh/awx_automation.pub ansible@192.168.1.10

# Opción 2: con un playbook de bootstrap
# (ver ejemplo más abajo)
```

**Playbook de bootstrap para distribuir la clave:**

```yaml
# playbooks/bootstrap_ssh.yml
# Ejecutar UNA VEZ con credenciales de admin para preparar los hosts
---
- name: Bootstrap SSH para AWX
  hosts: all
  become: true
  
  vars:
    awx_public_key: "{{ lookup('file', '~/.ssh/awx_automation.pub') }}"
    ansible_user_for_awx: ansible
    
  tasks:
    - name: Crear usuario ansible si no existe
      ansible.builtin.user:
        name: "{{ ansible_user_for_awx }}"
        shell: /bin/bash
        create_home: true
        system: false
        
    - name: Configurar sudo sin password para usuario ansible
      ansible.builtin.copy:
        content: "{{ ansible_user_for_awx }} ALL=(ALL) NOPASSWD:ALL\n"
        dest: "/etc/sudoers.d/{{ ansible_user_for_awx }}"
        mode: '0440'
        validate: 'visudo -cf %s'
        
    - name: Crear directorio .ssh
      ansible.builtin.file:
        path: "/home/{{ ansible_user_for_awx }}/.ssh"
        state: directory
        owner: "{{ ansible_user_for_awx }}"
        group: "{{ ansible_user_for_awx }}"
        mode: '0700'
        
    - name: Añadir clave pública de AWX
      ansible.builtin.authorized_key:
        user: "{{ ansible_user_for_awx }}"
        key: "{{ awx_public_key }}"
        state: present
        exclusive: false
```

## Tipo 2: Ansible Vault

Para descifrar variables y ficheros cifrados con `ansible-vault`.

```
Campos:
  Vault Password:    la contraseña usada para cifrar
  Vault Identifier:  el vault ID (default, prod, dev...)
                     debe coincidir con el ID usado al cifrar
```

**Ejemplo de uso con múltiples vault IDs:**

```bash
# Cifrar con vault ID específico
ansible-vault encrypt_string 'MiPasswordBD' \
  --vault-id prod@prompt \
  --name 'db_password'

# Resultado en el playbook:
# db_password: !vault |
#   $ANSIBLE_VAULT;1.2;AES256;prod
#   38653061386665623835303763...

# En AWX: crear dos credenciales Vault
# Credencial 1: Vault ID "dev",  password para dev
# Credencial 2: Vault ID "prod", password para prod
# Ambas se pueden adjuntar al mismo Job Template
```

**Fichero de variables cifrado completo:**

```bash
# Crear fichero de secrets
cat > vars/prod_secrets.yml << 'EOF'
db_password: SuperSecretDB123!
api_key: sk-prod-xxxxxxxxxxxx
smtp_password: MailPass456!
EOF

# Cifrar el fichero completo
ansible-vault encrypt vars/prod_secrets.yml \
  --vault-id prod@prompt

# El fichero queda cifrado en el repo
# AWX lo descifra automáticamente con la credencial Vault adjunta
```

## Tipo 3: Cloud Credentials

### Amazon Web Services

```
Campos:
  Access Key:    AKIAIOSFODNN7EXAMPLE
  Secret Key:    wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  
  Alternativa recomendada: usar IAM Roles (sin credenciales estáticas)
  Si AWX corre en EC2: usar Instance Profile
  Si AWX corre en K8s: usar IRSA (IAM Roles for Service Accounts)
```

**Política IAM mínima para inventario dinámico EC2:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWXInventoryReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

**Política IAM para despliegue (más permisos):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWXDeployPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:DescribeRegions",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "secretsmanager:GetSecretValue",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "*"
    }
  ]
}
```

### Microsoft Azure

```
Campos:
  Subscription ID:  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Client ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  (App Registration)
  Client Secret:    el secret del Service Principal
  Tenant ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Crear Service Principal con Azure CLI:**

```bash
# Login en Azure
az login

# Crear Service Principal con rol de Reader (para inventario)
az ad sp create-for-rbac \
  --name "awx-automation-sp" \
  --role "Reader" \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>"

# Output:
# {
#   "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",      ← Client ID
#   "displayName": "awx-automation-sp",
#   "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",    ← Client Secret
#   "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"      ← Tenant ID
# }

# Para despliegue (más permisos), usar rol Contributor en el RG:
az role assignment create \
  --assignee <appId> \
  --role "Contributor" \
  --scope "/subscriptions/<SUB_ID>/resourceGroups/rg-production"
```

## Tipo 4: Source Control

Para repos Git privados.

```
Opción A: HTTPS con token
  Username:  tu-usuario-github
  Password:  ghp_xxxxxxxxxxxx  (Personal Access Token)
  
Opción B: SSH
  SSH Private Key: clave privada (la pública como Deploy Key en GitHub)
```

**Crear Deploy Key en GitHub (recomendado para repos privados):**

```bash
# Generar clave específica para el repo
ssh-keygen -t ed25519 \
  -C "awx-deploy-key-$(date +%Y%m%d)" \
  -f ~/.ssh/awx_deploy_key \
  -N ""

# La clave pública va en GitHub:
# Repo → Settings → Deploy keys → Add deploy key
# Title: AWX Deploy Key
# Key: (contenido de awx_deploy_key.pub)
# Allow write access: NO (solo lectura para AWX)

# La clave privada va en AWX:
# Credentials → Add → Type: Source Control
# SSH Private Key: (contenido de awx_deploy_key)
```

## Tipo 5: Custom Credential Types

Cuando necesitas un secreto que no encaja en los tipos estándar. Por ejemplo: un token de API, credenciales de una CMDB, o configuración de un proxy.

```
Estructura de un Custom Credential Type:

  INPUTS (JSONSchema):
    Define los campos que el usuario rellena
    
  INJECTOR:
    Define cómo se inyectan en el job
    (como variables de entorno o como fichero)
```

**Ejemplo: Custom Credential para API de Monitoring**

```json
// INPUTS (JSONSchema)
{
  "fields": [
    {
      "id": "api_url",
      "type": "string",
      "label": "URL de la API",
      "help_text": "Ejemplo: https://monitoring.empresa.com"
    },
    {
      "id": "api_token",
      "type": "string",
      "label": "Token de API",
      "secret": true,
      "help_text": "Token de autenticación Bearer"
    },
    {
      "id": "org_id",
      "type": "string",
      "label": "ID de Organización",
      "help_text": "ID numérico de la organización en el sistema"
    }
  ],
  "required": ["api_url", "api_token"]
}
```

```yaml
# INJECTOR (cómo se inyectan en el job)
env:
  MONITORING_API_URL: "{{ api_url }}"
  MONITORING_API_TOKEN: "{{ api_token }}"
  MONITORING_ORG_ID: "{{ org_id }}"

# Uso en el playbook:
# - name: Crear alerta en monitoring
#   uri:
#     url: "{{ lookup('env', 'MONITORING_API_URL') }}/api/alerts"
#     headers:
#       Authorization: "Bearer {{ lookup('env', 'MONITORING_API_TOKEN') }}"
```

---

# 2.7 Proyectos: estrategias de sync y pins

Un Proyecto en AWX es un puntero a un repositorio Git. La estrategia de sincronización determina cuándo y cómo AWX actualiza el contenido.

## Opciones de sincronización

```
OPCIÓN 1: Manual
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  El operador hace clic en "Sync" manualmente
  ✅ Máximo control
  ❌ Puede quedar desactualizado

OPCIÓN 2: Update on Launch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AWX sincroniza el repo antes de cada ejecución
  ✅ Siempre usa el código más reciente
  ❌ Añade latencia al inicio de cada job
  ✅ Ideal para: dev y stage

OPCIÓN 3: Webhook (recomendado)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GitHub/GitLab notifica a AWX en cada push
  AWX sincroniza inmediatamente
  ✅ Rápido, automático, sin latencia en el job
  ✅ Ideal para: dev y stage con CI/CD

OPCIÓN 4: SCM Polling
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AWX comprueba el repo cada N minutos
  ✅ No requiere webhook (útil si AWX no es accesible desde internet)
  ❌ Latencia hasta N minutos
```

## Estrategia de pins por entorno

La estrategia más robusta para producción: cada entorno apunta a una referencia Git diferente.

```
ENTORNO DEV
  Project SCM Branch: develop
  Update on Launch: ✅
  → Siempre usa el último commit de develop
  → Rápido feedback para desarrolladores

ENTORNO STAGE
  Project SCM Branch: main
  Webhook: ✅ (sincroniza en cada merge a main)
  → Usa el código que pasó code review
  → Estable para pruebas de integración

ENTORNO PROD
  Project SCM Tag: v1.6.3
  Update on Launch: ❌
  → Tag inmutable: siempre el mismo código
  → Actualizar solo cuando se promueve una release
  → Máxima reproducibilidad y auditoría
```

**Flujo de promoción:**

```
develop ──── PR/Review ────► main ──── Tag ────► v1.6.3
   │                           │                    │
   ▼                           ▼                    ▼
AWX Dev                    AWX Stage            AWX Prod
(auto-sync)               (webhook)            (pin manual)
```

## Opciones importantes del Proyecto

```yaml
# Opciones de SCM en AWX Projects:

Clean: true
# Elimina ficheros no rastreados por Git antes de sync
# Evita que ficheros locales contaminen el workspace
# ✅ Siempre activar

Delete on Update: true
# Borra el directorio de trabajo y vuelve a clonar
# Más lento pero garantiza estado limpio
# ✅ Activar en entornos donde hubo problemas de estado sucio

Update Revision on Launch: true
# Fija el commit exacto en el momento del launch
# El job siempre usa ese commit aunque el repo cambie durante la ejecución
# ✅ Activar en stage y prod para reproducibilidad

Allow Branch Override: false
# Permite que el Job Template sobreescriba la rama del proyecto
# ❌ Desactivar en prod para evitar ejecuciones accidentales en ramas incorrectas
```

---

# 2.8 LAB — Inventario estático con grupos dev/stage/prod

*Construimos el inventario base que usaremos en todos los módulos siguientes.*

## Paso 1 — Crear el Inventario

```
AWX UI → Inventories → Add → Inventory

  Name:         Env Inventory
  Description:  Inventario multi-entorno para labs
  Organization: MiEmpresa
  
  Variables:    (dejar vacío por ahora)
  
  → Save
```

## Paso 2 — Crear los grupos

```
Env Inventory → Groups → Add

  Name:        dev
  Description: Entorno de desarrollo
  Variables:
    env: dev
    app_port: 8080
    debug_mode: true
    db_host: dev-db1
    replica_count: 1
    log_level: debug
  → Save

Groups → Add
  Name:        stage
  Description: Entorno de staging/preproducción
  Variables:
    env: stage
    app_port: 8080
    debug_mode: false
    db_host: stg-db1
    replica_count: 2
    log_level: info
  → Save

Groups → Add
  Name:        prod
  Description: Entorno de producción
  Variables:
    env: prod
    app_port: 80
    debug_mode: false
    db_host: prod-db1
    replica_count: 3
    log_level: warning
  → Save
```

## Paso 3 — Añadir subgrupos (web y db dentro de cada entorno)

```
# Dentro del grupo "dev":
dev → Groups → Add
  Name: dev_web
  Variables:
    server_role: web
    nginx_worker_processes: 2
  → Save

dev → Groups → Add
  Name: dev_db
  Variables:
    server_role: db
    mysql_max_connections: 100
  → Save
```

## Paso 4 — Añadir hosts

```
# Hosts del grupo dev_web
dev_web → Hosts → Add
  Name: dev-web1
  Variables:
    ansible_host: 192.168.1.10
    ansible_user: ansible
    node_role: primary
  → Save

dev_web → Hosts → Add
  Name: dev-web2
  Variables:
    ansible_host: 192.168.1.11
    ansible_user: ansible
    node_role: secondary
  → Save

# Hosts del grupo dev_db
dev_db → Hosts → Add
  Name: dev-db1
  Variables:
    ansible_host: 192.168.1.20
    ansible_user: ansible
    db_role: master
  → Save

# Para el lab sin hosts reales, usar localhost:
# (añadir al grupo dev)
dev → Hosts → Add
  Name: localhost
  Variables:
    ansible_connection: local
    ansible_python_interpreter: "{{ ansible_playbook_python }}"
    env: dev
    server_role: test
  → Save
```

## Paso 5 — Verificar la estructura via API

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Listar inventarios
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/inventories/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for inv in data['results']:
    print(f'ID: {inv[\"id\"]} | Name: {inv[\"name\"]} | Hosts: {inv[\"total_hosts\"]}')
"

# Listar grupos del inventario (ajusta el ID)
INV_ID=2
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/inventories/${INV_ID}/groups/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for g in data['results']:
    print(f'  Grupo: {g[\"name\"]}')
"

# Listar todos los hosts del inventario
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/inventories/${INV_ID}/hosts/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for h in data['results']:
    print(f'  Host: {h[\"name\"]} | Enabled: {h[\"enabled\"]}')
"
```

## Paso 6 — Probar el Limit en un Job Template

```
# Crear un Job Template de prueba con el inventario
Templates → Add → Job Template
  Name: Test Inventory Limit
  Inventory: Env Inventory
  Project: Platform Playbooks
  Playbook: playbooks/hello_awx.yml
  Credentials: Platform SSH
  
  Options:
    ✅ Prompt on Launch para: Limit
  
  → Save → Launch

# En el diálogo de launch:
Limit: dev          → ejecuta solo en hosts del grupo dev
Limit: dev_web      → solo en webservers de dev
Limit: dev-web1     → solo en ese host específico
Limit: dev,stage    → en dev y stage simultáneamente
Limit: web*         → todos los hosts cuyo nombre empieza por "web"
```

---

# 2.9 LAB — Credenciales SSH, Vault y Cloud

## Parte A — Credencial SSH (Machine)

### Crear la clave SSH

```bash
# En tu máquina local o en el servidor AWX
ssh-keygen -t ed25519 \
  -C "awx-platform-$(date +%Y%m%d)" \
  -f ~/.ssh/awx_platform \
  -N ""

echo "=== CLAVE PRIVADA (va en AWX) ==="
cat ~/.ssh/awx_platform

echo ""
echo "=== CLAVE PÚBLICA (va en los hosts) ==="
cat ~/.ssh/awx_platform.pub
```

### Distribuir la clave pública a los hosts

```bash
# Para cada host que quieras gestionar con AWX:
ssh-copy-id -i ~/.ssh/awx_platform.pub ansible@192.168.1.10
ssh-copy-id -i ~/.ssh/awx_platform.pub ansible@192.168.1.11
ssh-copy-id -i ~/.ssh/awx_platform.pub ansible@192.168.1.20

# Verificar que funciona
ssh -i ~/.ssh/awx_platform ansible@192.168.1.10 "echo '✅ SSH OK'"
```

### Crear la credencial en AWX

```
Credentials → Add

  Name:         Platform SSH
  Description:  Clave SSH principal para hosts gestionados
  Organization: MiEmpresa
  Credential Type: Machine
  
  Username:     ansible
  SSH Private Key: [pegar contenido de ~/.ssh/awx_platform]
  
  Privilege Escalation:
    Method:   sudo
    Username: root (dejar vacío para usar el mismo usuario)
    Password: (dejar vacío si sudo no requiere password)
  
  → Save
```

### Verificar la credencial

```bash
# AWX tiene un endpoint para verificar credenciales
# (no expone el valor, solo confirma que existe y es válida)
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/credentials/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cred in data['results']:
    print(f'ID: {cred[\"id\"]} | Name: {cred[\"name\"]} | Type: {cred[\"credential_type\"]}')
"
```

## Parte B — Credencial Ansible Vault

### Crear ficheros cifrados con Vault

```bash
# Instalar ansible si no lo tienes
pip install ansible-core

# Crear un fichero de variables secretas
mkdir -p vars
cat > vars/secrets_dev.yml << 'EOF'
db_password: DevPass123!
api_key: dev-api-key-xxxx
smtp_password: DevMail456!
EOF

# Cifrar el fichero con vault ID "dev"
ansible-vault encrypt vars/secrets_dev.yml \
  --vault-id dev@prompt
# Introduce la contraseña: VaultPasswordDev123!

# Verificar que está cifrado
head -3 vars/secrets_dev.yml
# $ANSIBLE_VAULT;1.2;AES256;dev
# 38653061386665623835303763...

# Crear fichero de secrets para prod
cat > vars/secrets_prod.yml << 'EOF'
db_password: ProdPass789!
api_key: prod-api-key-yyyy
smtp_password: ProdMail012!
EOF

ansible-vault encrypt vars/secrets_prod.yml \
  --vault-id prod@prompt
# Introduce la contraseña: VaultPasswordProd456!
```

### Crear las credenciales Vault en AWX

```
Credentials → Add

  Name:         Vault Dev
  Description:  Vault password para entorno dev
  Organization: MiEmpresa
  Credential Type: Ansible Vault
  
  Vault Password:    VaultPasswordDev123!
  Vault Identifier:  dev
  
  → Save

Credentials → Add

  Name:         Vault Prod
  Description:  Vault password para entorno prod
  Organization: MiEmpresa
  Credential Type: Ansible Vault
  
  Vault Password:    VaultPasswordProd456!
  Vault Identifier:  prod
  
  → Save
```

### Usar Vault en un playbook

```yaml
# playbooks/deploy_with_secrets.yml
---
- name: Deploy con secrets de Vault
  hosts: "{{ target_env | default('dev') }}"
  become: true
  
  vars_files:
    - "../vars/secrets_{{ env }}.yml"
    
  tasks:
    - name: Mostrar entorno (sin mostrar secrets)
      ansible.builtin.debug:
        msg: "Desplegando en entorno: {{ env }}"
        
    - name: Configurar base de datos
      ansible.builtin.template:
        src: db.conf.j2
        dest: /etc/app/db.conf
        mode: '0600'
      vars:
        # db_password viene del fichero Vault
        database_url: "mysql://app:{{ db_password }}@{{ db_host }}/appdb"
        
    - name: Verificar conexión a BD (sin exponer password)
      ansible.builtin.command:
        cmd: "mysql -u app -p{{ db_password }} -h {{ db_host }} -e 'SELECT 1'"
      register: db_check
      changed_when: false
      no_log: true  # ← IMPORTANTE: evita que el password aparezca en logs
      
    - name: Resultado de verificación
      ansible.builtin.debug:
        msg: "Conexión BD: {{ 'OK' if db_check.rc == 0 else 'FALLO' }}"
```

### Adjuntar múltiples credenciales a un Job Template

```
Templates → Add → Job Template
  Name: Deploy con Vault
  Inventory: Env Inventory
  Project: Platform Playbooks
  Playbook: playbooks/deploy_with_secrets.yml
  
  Credentials:
    + Platform SSH    (tipo Machine)
    + Vault Dev       (tipo Ansible Vault)
    + Vault Prod      (tipo Ansible Vault)
    
  # AWX aplica automáticamente el vault correcto
  # según el vault ID en el fichero cifrado
  
  → Save
```

## Parte C — Credencial AWS (para inventario dinámico)

### Crear usuario IAM en AWS

```bash
# Con AWS CLI (o desde la consola AWS)

# Crear usuario IAM
aws iam create-user --user-name awx-inventory-reader

# Crear política de solo lectura para EC2
aws iam create-policy \
  --policy-name AWXInventoryReadOnly \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    }]
  }'

# Adjuntar política al usuario
aws iam attach-user-policy \
  --user-name awx-inventory-reader \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWXInventoryReadOnly

# Crear access key
aws iam create-access-key --user-name awx-inventory-reader
# Guarda el AccessKeyId y SecretAccessKey
```

### Crear la credencial AWS en AWX

```
Credentials → Add

  Name:         AWS Inventory ReadOnly
  Description:  Credencial de solo lectura para inventario EC2
  Organization: MiEmpresa
  Credential Type: Amazon Web Services
  
  Access Key:   AKIAIOSFODNN7EXAMPLE
  Secret Key:   wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  
  # STS Token: dejar vacío (no usamos credenciales temporales aquí)
  
  → Save
```

---

# 2.10 LAB — Inventario dinámico AWS EC2

## Paso 1 — Crear el fichero de plugin en el repo

```bash
# En tu repo Git, crear el fichero de configuración del plugin
mkdir -p inventory
cat > inventory/aws_ec2.yml << 'EOF'
---
plugin: amazon.aws.aws_ec2

regions:
  - eu-west-1

filters:
  tag:AnsibleManaged:
    - "true"
  instance-state-name:
    - running

hostnames:
  - private-ip-address
  - public-ip-address

compose:
  ansible_host: private_ip_address
  instance_env: tags.Environment | default('unknown')
  instance_role: tags.Role | default('unknown')

keyed_groups:
  - prefix: env
    key: tags.Environment
    separator: "_"
  - prefix: role
    key: tags.Role
    separator: "_"
  - prefix: region
    key: placement.region
    separator: "_"

groups:
  web_servers: "'web' in tags.get('Role', '')"
  db_servers: "'db' in tags.get('Role', '')"
EOF

# Commit y push al repo
git add inventory/aws_ec2.yml
git commit -m "feat: añadir plugin de inventario dinámico AWS EC2"
git push origin main
```

## Paso 2 — Asegurarse de que el EE tiene la colección amazon.aws

```bash
# Verificar qué colecciones tiene el EE por defecto
kubectl exec -n awx deployment/awx-task -c awx-task -- \
  ansible-galaxy collection list | grep amazon

# Si no aparece amazon.aws, necesitas un EE personalizado
# Ver Módulo 3 para crear EEs personalizados

# El EE por defecto de AWX (awx-ee) suele incluir amazon.aws
# Verificar la versión
kubectl exec -n awx deployment/awx-task -c awx-task -- \
  ansible-galaxy collection list amazon.aws
```

## Paso 3 — Crear el Inventario dinámico en AWX

```
Inventories → Add → Inventory

  Name:         AWS Production
  Description:  Inventario dinámico de instancias EC2
  Organization: MiEmpresa
  
  → Save

AWS Production → Sources → Add

  Name:             EC2 eu-west-1
  Source:           Amazon EC2
  Credential:       AWS Inventory ReadOnly
  
  # Alternativa: usar el fichero del repo
  # Source:         Sourced from a Project
  # Project:        Platform Playbooks
  # Inventory file: inventory/aws_ec2.yml
  
  Regions:          eu-west-1
  
  Instance Filters: tag:AnsibleManaged=true
  
  Only Group By:    tag:Environment, tag:Role
  
  Update Options:
    ✅ Overwrite
    ✅ Overwrite Vars
    ✅ Update on Launch
    Cache Timeout: 300
  
  → Save → Sync Now
```

## Paso 4 — Verificar el resultado del sync

```bash
# Ver el log del sync en AWX UI:
# AWS Production → Sources → EC2 eu-west-1 → (icono historial)

# Via API: ver hosts descubiertos
INV_ID=3  # ajusta al ID de tu inventario AWS
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/inventories/${INV_ID}/hosts/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total hosts: {data[\"count\"]}')
for h in data['results'][:5]:
    print(f'  - {h[\"name\"]}')
    # Mostrar algunas variables
    vars_data = json.loads(h.get('variables', '{}'))
    if vars_data:
        print(f'    vars: {list(vars_data.keys())[:3]}')
"

# Ver grupos creados automáticamente
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/inventories/${INV_ID}/groups/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total grupos: {data[\"count\"]}')
for g in data['results']:
    print(f'  - {g[\"name\"]}')
"
```

## Paso 5 — Tags recomendados para las instancias EC2

Para que el inventario dinámico funcione bien, tus instancias EC2 deben tener estos tags:

```
Tag: AnsibleManaged = true     (requerido por el filtro)
Tag: Environment    = dev      (crea grupo env_dev)
Tag: Environment    = stage    (crea grupo env_stage)
Tag: Environment    = prod     (crea grupo env_prod)
Tag: Role           = web      (crea grupo role_web)
Tag: Role           = db       (crea grupo role_db)
Tag: Role           = app      (crea grupo role_app)
Tag: Name           = prod-web1 (nombre descriptivo)
```

**Aplicar tags con AWS CLI:**

```bash
# Aplicar tags a una instancia
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags \
    Key=AnsibleManaged,Value=true \
    Key=Environment,Value=prod \
    Key=Role,Value=web \
    Key=Name,Value=prod-web1

# Aplicar tags a múltiples instancias
aws ec2 create-tags \
  --resources i-1234567890abcdef0 i-0987654321fedcba0 \
  --tags Key=AnsibleManaged,Value=true Key=Environment,Value=prod
```

---

# 2.11 LAB — Inventario dinámico Azure

## Paso 1 — Fichero de plugin Azure en el repo

```yaml
# inventory/azure_rm.yml
---
plugin: azure.azcollection.azure_rm

# Filtrar por grupos de recursos específicos
include_vm_resource_groups:
  - rg-production
  - rg-staging

# Solo VMs en estado running
exclude_host_filters:
  - powerstate != 'running'

# Componer variables de host
compose:
  ansible_host: private_ipv4_addresses[0] if private_ipv4_addresses else public_ipv4_addresses[0]
  vm_size: hw_machine_type
  azure_location: location
  azure_resource_group: resource_group
  azure_environment: tags.Environment | default('unknown')
  azure_role: tags.Role | default('unknown')

# Grupos por tags de Azure
keyed_groups:
  - prefix: env
    key: tags.Environment
    separator: "_"
  - prefix: role
    key: tags.Role
    separator: "_"
  - prefix: location
    key: location
    separator: "_"
  - prefix: os
    key: os_disk.operating_system_type
    separator: "_"

# Grupos condicionales
groups:
  linux_vms: os_disk.operating_system_type == 'Linux'
  windows_vms: os_disk.operating_system_type == 'Windows'
  production_vms: tags.get('Environment') == 'prod'
```

## Paso 2 — Crear el Inventario Azure en AWX

```
Inventories → Add → Inventory
  Name:         Azure Production
  Organization: MiEmpresa
  → Save

Azure Production → Sources → Add
  Name:       Azure VMs
  Source:     Microsoft Azure Resource Manager
  Credential: Azure Service Principal
  
  # Opción: usar fichero del repo
  # Source:         Sourced from a Project
  # Project:        Platform Playbooks
  # Inventory file: inventory/azure_rm.yml
  
  Update Options:
    ✅ Overwrite
    ✅ Overwrite Vars
    ✅ Update on Launch
  
  → Save → Sync Now
```

---

# 2.12 LAB — Proyecto SCM con Webhook auto-sync

*Configuramos sincronización automática: cada push al repo actualiza el contenido en AWX.*

## Paso 1 — Crear el Proyecto en AWX

```
Projects → Add

  Name:         Platform Playbooks
  Description:  Repositorio principal de playbooks y roles
  Organization: MiEmpresa
  Source Control Type: Git
  
  Source Control URL:    https://github.com/tuorg/ansible-playbooks.git
  Source Control Branch: main
  
  Source Control Credential: (si el repo es privado, añadir credencial SCM)
  
  Source Control Options:
    ✅ Clean
    ✅ Delete on Update
    ☐ Update Revision on Launch  (activar en stage/prod)
    ☐ Allow Branch Override      (desactivar en prod)
  
  → Save
```

AWX sincronizará automáticamente al guardar. Verifica que el estado muestra **Successful**.

## Paso 2 — Habilitar el Webhook en AWX

```
Projects → Platform Playbooks → Edit

  Options:
    ✅ Enable Webhook
    Webhook Service: GitHub  (o GitLab)
    
  → Save

# AWX genera:
#   Webhook URL:    http://<AWX_IP>:30080/api/v2/projects/<ID>/update/
#   Webhook Key:    un token secreto aleatorio
# 
# Copia ambos valores, los necesitas en el paso siguiente
```

## Paso 3 — Configurar el Webhook en GitHub

```
GitHub → Tu Repo → Settings → Webhooks → Add webhook

  Payload URL:   http://<AWX_IP>:30080/api/v2/projects/<ID>/update/
  Content type:  application/json
  Secret:        [el Webhook Key copiado de AWX]
  
  Which events would you like to trigger this webhook?
    ● Just the push event
  
  Active: ✅
  
  → Add webhook
```

## Paso 4 — Verificar el Webhook

```bash
# Hacer un cambio en el repo y hacer push
echo "# Test webhook $(date)" >> README.md
git add README.md
git commit -m "test: verificar webhook AWX"
git push origin main

# En AWX, observar:
# Projects → Platform Playbooks
# Debe aparecer un nuevo sync job ejecutándose automáticamente

# Via API: ver el historial de syncs del proyecto
PROJECT_ID=1  # ajusta
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/projects/${PROJECT_ID}/project_updates/?order_by=-id&page_size=3" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for job in data['results']:
    print(f'ID: {job[\"id\"]} | Status: {job[\"status\"]} | Started: {job[\"started\"]}')
"
```

## Paso 5 — Configurar proyectos por entorno (pins)

```
# Proyecto para Dev (siempre la rama develop)
Projects → Add
  Name:         Platform Playbooks (Dev)
  SCM URL:      https://github.com/tuorg/ansible-playbooks.git
  SCM Branch:   develop
  Options:
    ✅ Clean
    ✅ Delete on Update
    ✅ Update on Launch      ← siempre fresco en dev
  → Save

# Proyecto para Stage (rama main)
Projects → Add
  Name:         Platform Playbooks (Stage)
  SCM URL:      https://github.com/tuorg/ansible-playbooks.git
  SCM Branch:   main
  Options:
    ✅ Clean
    ✅ Delete on Update
    ✅ Enable Webhook        ← auto-sync en cada merge a main
  → Save

# Proyecto para Prod (tag inmutable)
Projects → Add
  Name:         Platform Playbooks (Prod)
  SCM URL:      https://github.com/tuorg/ansible-playbooks.git
  SCM Branch:   v1.6.3      ← tag específico, inmutable
  Options:
    ✅ Clean
    ✅ Delete on Update
    ☐ Update on Launch      ← NO actualizar automáticamente en prod
    ✅ Update Revision on Launch  ← fijar el commit exacto
  → Save
```