# 📦 MÓDULO 6 — Inventarios Dinámicos, Proyectos y Gestión de Configuración
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 6.1 | Modelo mental: el inventario como fuente de verdad |
| 6.2 | Tipos de inventarios en AWX |
| 6.3 | Inventarios estáticos: estructura y variables |
| 6.4 | Inventarios dinámicos: fuentes externas |
| 6.5 | Smart Inventories: filtros sobre inventarios existentes |
| 6.6 | Constructed Inventories: lógica avanzada de agrupación |
| 6.7 | Proyectos: gestión del código de automatización |
| 6.8 | Ramas, tags y pins de versión en proyectos |
| 6.9 | Collections y roles en el proyecto |
| 6.10 | LAB — Inventario dinámico AWS EC2 |
| 6.11 | LAB — Inventario dinámico con script personalizado |
| 6.12 | LAB — Smart Inventory para targeting por facts |
| 6.13 | LAB — Constructed Inventory con grupos dinámicos |
| 6.14 | LAB — Proyecto con múltiples ramas y pin de versión |
| 6.15 | LAB — Pipeline de validación de playbooks en CI |
| 6.16 | Patrones avanzados y buenas prácticas |
| 6.17 | Troubleshooting del módulo |
| 6.18 | Resumen y checklist |

**Duración estimada:** 60-75 minutos
**Tipo:** Lab + configuración de fuentes de datos
**Prerrequisitos:** Módulos 1-5 completados

---

# 6.1 Modelo mental: el inventario como fuente de verdad

El inventario es la respuesta a la pregunta más fundamental de la automatización: **¿sobre qué hosts ejecuto esto?** Si el inventario es incorrecto, toda la automatización construida encima es incorrecta.

```
INVENTARIO ESTÁTICO (el punto de partida):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Defines los hosts manualmente en AWX o en un fichero INI/YAML.
  
  Ventaja:  simple, predecible, sin dependencias externas
  Problema: se desincroniza con la realidad
            si aprovisiones un nuevo servidor, hay que añadirlo a mano
            si terminas una instancia, hay que quitarla a mano
            en infraestructura cloud esto escala muy mal

INVENTARIO DINÁMICO (el estándar en producción):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AWX consulta una fuente externa (AWS, Azure, GCP, VMware,
  Kubernetes, CMDB, etc.) y construye el inventario automáticamente.
  
  Ventaja:  siempre refleja la realidad
            nuevos hosts aparecen solos
            hosts terminados desaparecen solos
            los grupos se crean a partir de tags/metadata real
  
  El inventario dinámico ES la fuente de verdad porque
  refleja lo que realmente existe, no lo que alguien escribió.

SMART / CONSTRUCTED INVENTORY (la capa de lógica):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Crea vistas filtradas o agrupaciones lógicas sobre inventarios
  existentes, sin duplicar datos.
  
  Ejemplo:
    Inventario base: todos los hosts de AWS (2000 hosts)
    Smart Inventory: solo hosts con tag Environment=prod (150 hosts)
    Constructed:     grupos por combinación de tags y facts
```

---

# 6.2 Tipos de inventarios en AWX

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TIPOS DE INVENTARIO EN AWX                        │
├──────────────────┬──────────────────────────────────────────────────┤
│ Inventory        │ Estático o con fuentes dinámicas adjuntas         │
│ Smart Inventory  │ Filtro sobre inventarios existentes               │
│ Constructed Inv. │ Grupos dinámicos con lógica Jinja2                │
└──────────────────┴──────────────────────────────────────────────────┘

INVENTORY (el tipo base):
  Puede ser puramente estático (hosts añadidos a mano)
  o tener una o más "Inventory Sources" que lo pueblan dinámicamente.
  Las dos formas pueden coexistir en el mismo inventario.

SMART INVENTORY:
  No contiene hosts propios.
  Es un filtro sobre uno o más inventarios existentes.
  Ejemplo: hosts donde ansible_distribution == "Ubuntu"
  Se actualiza automáticamente cuando cambia el inventario base.

CONSTRUCTED INVENTORY:
  Más potente que Smart Inventory.
  Permite crear grupos dinámicos con lógica Jinja2.
  Puede combinar variables, facts y condiciones complejas.
  Ejemplo: grupo "prod_ubuntu_web" = hosts que son prod + ubuntu + web
```

---

# 6.3 Inventarios estáticos: estructura y variables

## Estructura de un inventario estático bien diseñado

```yaml
# inventory/hosts.yml
# Formato YAML (recomendado sobre INI para inventarios complejos)
---
all:
  vars:
    # Variables globales para todos los hosts
    ansible_user:           ansible
    ansible_ssh_private_key_file: ~/.ssh/platform_key
    ansible_python_interpreter: /usr/bin/python3

  children:

    # ── Entorno de desarrollo ──────────────────────────────────
    dev:
      vars:
        environment:        dev
        app_port:           8080
        log_level:          debug
        db_host:            db-dev.empresa.com
        vault_id:           dev
      children:
        dev_web:
          vars:
            role:           web
            nginx_workers:  2
          hosts:
            dev-web1:
              ansible_host: 10.0.1.11
              server_id:    1
            dev-web2:
              ansible_host: 10.0.1.12
              server_id:    2
        dev_db:
          vars:
            role:           db
            pg_max_conn:    100
          hosts:
            dev-db1:
              ansible_host: 10.0.1.21
              pg_primary:   true

    # ── Entorno de staging ────────────────────────────────────
    stage:
      vars:
        environment:        stage
        app_port:           8080
        log_level:          info
        db_host:            db-stage.empresa.com
        vault_id:           stage
      children:
        stage_web:
          vars:
            role:           web
            nginx_workers:  4
          hosts:
            stage-web1:
              ansible_host: 10.0.2.11
            stage-web2:
              ansible_host: 10.0.2.12
        stage_db:
          vars:
            role:           db
            pg_max_conn:    200
          hosts:
            stage-db1:
              ansible_host: 10.0.2.21
              pg_primary:   true
            stage-db2:
              ansible_host: 10.0.2.22
              pg_primary:   false

    # ── Entorno de producción ─────────────────────────────────
    prod:
      vars:
        environment:        prod
        app_port:           443
        log_level:          warning
        db_host:            db-prod.empresa.com
        vault_id:           prod
        backup_enabled:     true
      children:
        prod_web:
          vars:
            role:           web
            nginx_workers:  8
          hosts:
            prod-web1:
              ansible_host: 10.0.3.11
              az:           eu-west-1a
            prod-web2:
              ansible_host: 10.0.3.12
              az:           eu-west-1b
            prod-web3:
              ansible_host: 10.0.3.13
              az:           eu-west-1c
        prod_db:
          vars:
            role:           db
            pg_max_conn:    500
          hosts:
            prod-db1:
              ansible_host: 10.0.3.21
              pg_primary:   true
              az:           eu-west-1a
            prod-db2:
              ansible_host: 10.0.3.22
              pg_primary:   false
              az:           eu-west-1b
```

## Cargar el inventario estático en AWX

```
Inventories → Add → Inventory
  Name:         Env Inventory
  Organization: MiEmpresa
  → Save

# Opción A: Añadir hosts manualmente via UI
Inventories → Env Inventory → Hosts → Add
  Name:         dev-web1
  Variables:
    ansible_host: 10.0.1.11
    server_id: 1
  → Save

# Opción B: Importar desde el proyecto SCM (recomendado)
Inventories → Env Inventory → Sources → Add
  Name:         SCM - hosts.yml
  Source:       Sourced from a Project
  Project:      Platform Playbooks
  Inventory File: inventory/hosts.yml
  Update Options:
    ✅ Update on Project Update
    ✅ Overwrite
    ✅ Overwrite Variables
  → Save → Sync
```

---

# 6.4 Inventarios dinámicos: fuentes externas

## Fuentes de inventario disponibles en AWX

```
CLOUD:
  Amazon Web Services EC2
  Microsoft Azure Resource Manager
  Google Compute Engine
  VMware vCenter
  OpenStack

PLATAFORMAS:
  Red Hat Satellite / Foreman
  Red Hat Insights
  ServiceNow CMDB
  Terraform State

CONTENEDORES:
  Kubernetes / OpenShift

CUSTOM:
  Script ejecutable (cualquier lenguaje)
  Fichero en proyecto SCM (YAML/JSON/INI)
```

## Cómo funciona una Inventory Source

```
FLUJO DE SINCRONIZACIÓN:
  
  1. AWX ejecuta el plugin de inventario (o script)
  2. El plugin consulta la API de la fuente (AWS, Azure, etc.)
  3. La respuesta se transforma en grupos y hosts
  4. Los hosts se añaden al inventario de AWX
  5. Las variables de los hosts se pueblan con metadata de la fuente
  
  CUÁNDO SE SINCRONIZA:
    → Manualmente: Inventories → Source → Sync
    → Automáticamente: "Update on Launch" (antes de cada job)
    → Programado: via Schedule en la Inventory Source
    → Via API: POST /api/v2/inventory_sources/ID/update/
```

---

# 6.5 Smart Inventories: filtros sobre inventarios existentes

```
CASO DE USO:
  Tienes un inventario grande con 500 hosts de múltiples entornos.
  Quieres crear un "inventario de producción" que solo tenga
  los hosts de prod, sin duplicar datos.

SMART INVENTORY:
  Es un filtro que se aplica sobre el inventario base.
  Usa la sintaxis de búsqueda de AWX (Ansible facts o variables).
  Se actualiza automáticamente.

FILTROS DISPONIBLES:
  Por nombre de host:       name__icontains=prod
  Por grupo:                groups__name=prod_web
  Por variable de host:     variables__environment=prod
  Por fact cacheado:        ansible_distribution=Ubuntu
  Por combinación:          variables__environment=prod AND groups__name=web
```

```
Inventories → Add → Smart Inventory

  Name:         Smart - Prod Web Servers
  Description:  Solo servidores web de producción
  Organization: MiEmpresa

  Smart Host Filter:
    groups__name=prod_web

  → Save

# Verificar cuántos hosts tiene
Inventories → Smart - Prod Web Servers → Hosts
# Debe mostrar solo los hosts del grupo prod_web
```

---

# 6.6 Constructed Inventories: lógica avanzada de agrupación

Los Constructed Inventories son la evolución de los Smart Inventories. Permiten crear grupos dinámicos con lógica Jinja2 compleja.

```
DIFERENCIA CON SMART INVENTORY:
  Smart:       filtra hosts existentes (subset)
  Constructed: crea NUEVOS GRUPOS a partir de condiciones
               puede combinar múltiples inventarios
               soporta lógica Jinja2 compleja
```

```yaml
# Definición de un Constructed Inventory
# Se configura en el campo "Source vars" del inventario

---
# Fuentes de datos
plugin: constructed

# Inventarios base a combinar
sources:
  - inventory: "Env Inventory"

# Grupos construidos con lógica Jinja2
groups:
  # Grupo: servidores Ubuntu en producción
  prod_ubuntu:
    - ansible_distribution == "Ubuntu"
    - environment == "prod"

  # Grupo: servidores con más de 8GB de RAM
  high_memory:
    - ansible_memtotal_mb | int > 8192

  # Grupo: servidores web de cualquier entorno
  all_web_servers:
    - role == "web"

  # Grupo: servidores que necesitan patching urgente
  needs_patching:
    - ansible_kernel is version('5.15', '<')

  # Grupo combinado: prod + web + ubuntu
  prod_web_ubuntu:
    - environment == "prod"
    - role == "web"
    - ansible_distribution == "Ubuntu"

# Variables adicionales para los grupos construidos
compose:
  # Crear variable derivada
  full_hostname: inventory_hostname + "." + domain | default("empresa.com")
  is_production: environment == "prod"
  backup_priority: "high" if environment == "prod" else "low"
```

---

# 6.7 Proyectos: gestión del código de automatización

## Estructura de un proyecto bien organizado

```
platform-playbooks/                    ← raíz del repo Git
├── .github/
│   └── workflows/
│       └── ci.yml                     ← CI de validación
├── ansible.cfg                        ← configuración de Ansible
├── collections/
│   └── requirements.yml               ← colecciones necesarias
├── roles/
│   └── requirements.yml               ← roles externos
├── inventory/
│   ├── hosts.yml                      ← inventario estático
│   ├── group_vars/
│   │   ├── all.yml                    ← vars para todos
│   │   ├── dev.yml                    ← vars del grupo dev
│   │   ├── stage.yml
│   │   └── prod.yml
│   └── host_vars/
│       └── prod-web1.yml              ← vars específicas de host
├── playbooks/
│   ├── provision_infra.yml
│   ├── configure_app.yml
│   ├── deploy_web.yml
│   ├── run_tests.yml
│   ├── rollback_app.yml
│   └── post_deploy_notify.yml
├── roles/
│   ├── webapp/
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   │   ├── app.conf.j2
│   │   │   └── nginx.conf.j2
│   │   ├── vars/
│   │   │   └── main.yml
│   │   └── defaults/
│   │       └── main.yml
│   └── nginx/
│       └── ...
├── vars/
│   ├── common.yml                     ← variables compartidas
│   └── secrets.yml                    ← variables cifradas con Vault
└── README.md
```

## ansible.cfg del proyecto

```ini
# ansible.cfg
[defaults]
# Inventario por defecto (sobreescrito por AWX)
inventory           = inventory/hosts.yml

# Colecciones instaladas en el EE
collections_paths   = ~/.ansible/collections:/usr/share/ansible/collections

# Roles
roles_path          = roles

# Fact caching
fact_caching        = redis
fact_caching_connection = redis://localhost:6379/0
fact_caching_timeout = 86400

# Performance
forks               = 20
gathering           = smart
gather_subset       = min

# Output
stdout_callback     = yaml
bin_ansible_callbacks = true

# Seguridad
host_key_checking   = true
deprecation_warnings = true

[ssh_connection]
# Reutilizar conexiones SSH (mucho más rápido)
ssh_args            = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new
pipelining          = true
control_path_dir    = /tmp/ansible-ssh-%%h-%%p-%%r

[persistent_connection]
connect_timeout     = 30
command_timeout     = 30
```

## Tipos de proyectos en AWX

```
SCM Type: Git (el más común)
  → AWX clona/actualiza el repo en cada sync
  → Soporta: GitHub, GitLab, Bitbucket, Gitea, cualquier Git
  → Autenticación: SSH key, token HTTPS, usuario/contraseña

SCM Type: Subversion
  → Para repos SVN legacy
  → Menos común en entornos modernos

SCM Type: Red Hat Insights
  → Integración con Red Hat Insights
  → Playbooks de remediación automática

SCM Type: Manual
  → Los playbooks se copian manualmente al servidor AWX
  → Solo para labs o entornos sin acceso a Git
  → NO recomendado para producción
```

---

# 6.8 Ramas, tags y pins de versión en proyectos

## El problema de usar "main" en producción

```
PROBLEMA:
  Si el proyecto apunta a la rama "main" y alguien hace
  un commit con un bug, el próximo sync actualiza los playbooks
  y el siguiente job de producción usa el código bugueado.

SOLUCIÓN: Pins de versión por entorno

  Proyecto Dev:   rama main     (siempre el código más reciente)
  Proyecto Stage: rama main     (igual, para probar antes de tagear)
  Proyecto Prod:  tag v2.0.0    (versión específica, inmutable)
```

## Configurar proyectos por entorno

```
# Proyecto para desarrollo (siempre la última versión)
Projects → Add
  Name:     Platform Playbooks (Dev)
  SCM URL:  https://github.com/empresa/platform-playbooks.git
  SCM Branch/Tag/Commit: main
  Update Options:
    ✅ Clean
    ✅ Update Revision on Launch  ← siempre actualiza antes de ejecutar
  → Save

# Proyecto para producción (versión fija)
Projects → Add
  Name:     Platform Playbooks (Prod)
  SCM URL:  https://github.com/empresa/platform-playbooks.git
  SCM Branch/Tag/Commit: v2.0.0   ← tag específico
  Update Options:
    ✅ Clean
    ☐  Update Revision on Launch  ← NO actualizar automáticamente
  → Save
```

## Permitir override de rama en el Job Template

```
Projects → Platform Playbooks (Dev) → Edit
  Options: ✅ Allow Branch Override
  → Save

# Ahora en el Job Template:
Templates → Web App Deploy → Edit
  Project: Platform Playbooks (Dev)
  SCM Branch: (dejar vacío para usar la del proyecto)
  Options: ✅ Prompt on Launch para SCM Branch
  → Save

# Al lanzar el job, el operador puede especificar:
# SCM Branch: feature/nueva-funcionalidad
# Útil para: probar una rama específica sin cambiar el proyecto
```

## Workflow de promoción de versiones

```bash
# Script: promote_to_prod.sh
# Promueve una versión a producción creando un tag Git
# y actualizando el proyecto de AWX

AWX_URL="http://localhost:30080"
AWX_TOKEN="tu-token-admin"
GITHUB_TOKEN="tu-github-token"
REPO="empresa/platform-playbooks"
VERSION="$1"  # ej: v2.1.0
PROD_PROJECT_ID="5"  # ID del proyecto de prod en AWX

if [ -z "$VERSION" ]; then
    echo "Uso: $0 <version>"
    echo "Ejemplo: $0 v2.1.0"
    exit 1
fi

echo "Promoviendo versión ${VERSION} a producción..."

# 1. Crear el tag en GitHub
echo "Creando tag ${VERSION} en GitHub..."
curl -s \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${REPO}/releases" \
    -d "{
        \"tag_name\":         \"${VERSION}\",
        \"target_commitish\": \"main\",
        \"name\":             \"Release ${VERSION}\",
        \"body\":             \"Promovido a producción el $(date +%Y-%m-%d)\",
        \"draft\":            false,
        \"prerelease\":       false
    }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'html_url' in data:
    print(f'✅ Release creado: {data[\"html_url\"]}')
else:
    print(f'❌ Error: {data}')
    import sys; sys.exit(1)
"

# 2. Actualizar el proyecto de AWX para que apunte al nuevo tag
echo "Actualizando proyecto AWX Prod a ${VERSION}..."
curl -s \
    -H "Authorization: Bearer ${AWX_TOKEN}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    "http://localhost:30080/api/v2/projects/${PROD_PROJECT_ID}/" \
    -d "{\"scm_branch\": \"${VERSION}\"}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'id' in data:
    print(f'✅ Proyecto actualizado a: {data[\"scm_branch\"]}')
else:
    print(f'❌ Error: {data}')
"

# 3. Sincronizar el proyecto
echo "Sincronizando proyecto..."
curl -s \
    -H "Authorization: Bearer ${AWX_TOKEN}" \
    -X POST \
    "http://localhost:30080/api/v2/projects/${PROD_PROJECT_ID}/update/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'✅ Sync lanzado: Job ID {data.get(\"id\", \"N/A\")}')
"

echo "Promoción completada. Verificar en AWX antes de lanzar el deploy."
```

---

# 6.9 Collections y roles en el proyecto

## requirements.yml para colecciones

```yaml
# collections/requirements.yml
---
collections:
  # Colecciones de Ansible Galaxy (versiones fijadas)
  - name: community.general
    version: ">=9.3.0,<10.0.0"

  - name: ansible.posix
    version: ">=1.5.0,<2.0.0"

  - name: community.mysql
    version: ">=3.8.0,<4.0.0"

  - name: community.crypto
    version: ">=2.18.0,<3.0.0"

  - name: amazon.aws
    version: ">=8.0.0,<9.0.0"

  # Colección desde un repo Git privado
  - name: empresa.internal_tools
    source: https://github.com/empresa/ansible-collection-internal.git
    type: git
    version: v1.2.0

  # Colección desde un Automation Hub privado
  - name: empresa.security_hardening
    source: https://hub.empresa.com/api/galaxy/
    version: ">=2.0.0"
```

## requirements.yml para roles externos

```yaml
# roles/requirements.yml
---
roles:
  # Rol de Ansible Galaxy
  - name: geerlingguy.nginx
    version: 3.2.0

  - name: geerlingguy.postgresql
    version: 4.0.0

  # Rol desde un repo Git
  - name: empresa.base_hardening
    src: https://github.com/empresa/ansible-role-hardening.git
    version: v2.1.0
    scm: git

  # Rol desde Automation Hub
  - name: empresa.monitoring_agent
    src: https://hub.empresa.com/api/galaxy/content/published/
    version: ">=1.0.0"
```

## Configurar AWX para instalar requirements automáticamente

```
Projects → Platform Playbooks → Edit

  Options:
    ✅ Update Revision on Launch
    ✅ Allow Branch Override

# AWX instala automáticamente las colecciones y roles
# definidos en collections/requirements.yml y roles/requirements.yml
# durante la sincronización del proyecto.

# Verificar que las colecciones se instalaron:
# Projects → Platform Playbooks → (ver el log del último sync)
```

---

# 6.10 LAB — Inventario dinámico AWS EC2

## Paso 1 — Crear la credencial AWS

```
Credentials → Add
  Name:         AWS ReadOnly
  Description:  Credencial de solo lectura para inventario dinámico EC2
  Organization: MiEmpresa
  Type:         Amazon Web Services

  Access Key:   AKIAIOSFODNN7EXAMPLE
  Secret Key:   wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

  → Save
```

## Paso 2 — Crear el inventario con fuente EC2

```
Inventories → Add → Inventory
  Name:         AWS Production
  Organization: MiEmpresa
  → Save

Inventories → AWS Production → Sources → Add
  Name:         EC2 eu-west-1
  Source:       Amazon EC2

  Credential:   AWS ReadOnly
  Region:       eu-west-1

  Instance Filters:
    tag:Environment=prod
    instance-state-name=running

  Overwrite:        ✅
  Overwrite Vars:   ✅
  Update on Launch: ✅

  Source Variables:
    ---
    # Configuración del plugin aws_ec2
    regions:
      - eu-west-1
      - eu-west-2

    filters:
      tag:Environment: prod
      instance-state-name: running

    keyed_groups:
      # Grupo por tipo de instancia
      - key: instance_type
        prefix: instance_type

      # Grupo por tag Role
      - key: tags.Role
        prefix: role
        separator: "_"

      # Grupo por AZ
      - key: placement.availability_zone
        prefix: az

      # Grupo por tag Environment
      - key: tags.Environment
        prefix: env

    compose:
      # Usar la IP privada para conectar
      ansible_host: private_ip_address

      # Variables derivadas de los tags
      environment:  tags.Environment | default("unknown")
      app_role:     tags.Role | default("unknown")
      app_version:  tags.AppVersion | default("unknown")

  → Save → Sync Now
```

## Paso 3 — Verificar el inventario dinámico

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver el estado del último sync
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventory_sources/?name=EC2+eu-west-1" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    src = data['results'][0]
    print(f'Source: {src[\"name\"]}')
    print(f'Status: {src[\"status\"]}')
    print(f'Last updated: {src.get(\"last_updated\", \"nunca\")}')
    print(f'Last job: {src.get(\"last_job\", {}).get(\"status\", \"N/A\")}')
"

# Ver los hosts del inventario
INV_ID=2  # ajusta
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/hosts/?page_size=10" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total hosts: {data[\"count\"]}')
for host in data['results'][:10]:
    vars_preview = str(host.get('variables', '{}'))[:80]
    print(f'  {host[\"name\"]:30} | {vars_preview}')
"

# Ver los grupos creados automáticamente
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/groups/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Grupos creados: {data[\"count\"]}')
for group in data['results']:
    print(f'  {group[\"name\"]:40} | Hosts: {group[\"total_hosts\"]}')
"
```

## Paso 4 — Usar el inventario dinámico en un Job Template

```
Templates → Web App Deploy → Edit
  Inventory: AWS Production
  Limit:     role_web  (grupo creado automáticamente por el tag Role=web)
  → Save

# Al lanzar el job, AWX:
# 1. Sincroniza el inventario (si Update on Launch está activo)
# 2. Ejecuta el playbook solo en los hosts del grupo role_web
# 3. Los hosts son exactamente los que están corriendo en AWS en ese momento
```

---

# 6.11 LAB — Inventario dinámico con script personalizado

*Cuando la fuente de inventario no tiene plugin nativo en AWX, usamos un script personalizado.*

## Paso 1 — Crear el script de inventario

```python
#!/usr/bin/env python3
# inventory/scripts/cmdb_inventory.py
# Script de inventario dinámico que consulta una CMDB interna
# Debe devolver JSON con el formato de inventario de Ansible

import json
import sys
import os
import requests
from datetime import datetime

# Configuración (desde variables de entorno para seguridad)
CMDB_URL   = os.environ.get('CMDB_URL',   'https://cmdb.empresa.com/api')
CMDB_TOKEN = os.environ.get('CMDB_TOKEN', '')
ENVIRONMENT = os.environ.get('CMDB_ENVIRONMENT', 'prod')

def get_hosts_from_cmdb():
    """Consulta la CMDB y devuelve la lista de hosts."""
    headers = {
        'Authorization': f'Bearer {CMDB_TOKEN}',
        'Content-Type': 'application/json'
    }

    try:
        resp = requests.get(
            f"{CMDB_URL}/servers",
            headers=headers,
            params={'environment': ENVIRONMENT, 'status': 'active'},
            timeout=30
        )
        resp.raise_for_status()
        return resp.json()['servers']
    except requests.exceptions.RequestException as e:
        # En caso de error, devolver inventario vacío (no fallar)
        print(f"Warning: CMDB no disponible: {e}", file=sys.stderr)
        return []

def build_inventory(hosts):
    """Construye el inventario en formato Ansible."""
    inventory = {
        '_meta': {
            'hostvars': {}
        },
        'all': {
            'children': ['ungrouped']
        }
    }

    for host in hosts:
        hostname = host['fqdn']
        ip       = host['ip_address']
        role     = host.get('role', 'unknown')
        env      = host.get('environment', 'unknown')
        location = host.get('datacenter', 'unknown')
        os_type  = host.get('os', 'linux')

        # Variables del host
        inventory['_meta']['hostvars'][hostname] = {
            'ansible_host':    ip,
            'cmdb_id':         host.get('id'),
            'cmdb_role':       role,
            'environment':     env,
            'datacenter':      location,
            'os_type':         os_type,
            'last_seen':       host.get('last_seen', ''),
            'owner_team':      host.get('owner_team', 'unknown'),
            'maintenance_mode': host.get('maintenance_mode', False)
        }

        # Añadir al grupo por rol
        role_group = f"role_{role}"
        if role_group not in inventory:
            inventory[role_group] = {'hosts': [], 'vars': {'cmdb_role': role}}
        inventory[role_group]['hosts'].append(hostname)

        # Añadir al grupo por entorno
        env_group = f"env_{env}"
        if env_group not in inventory:
            inventory[env_group] = {'hosts': [], 'vars': {'environment': env}}
        inventory[env_group]['hosts'].append(hostname)

        # Añadir al grupo por datacenter
        dc_group = f"dc_{location}"
        if dc_group not in inventory:
            inventory[dc_group] = {'hosts': []}
        inventory[dc_group]['hosts'].append(hostname)

        # Excluir hosts en modo mantenimiento
        if not host.get('maintenance_mode', False):
            if 'active_hosts' not in inventory:
                inventory['active_hosts'] = {'hosts': []}
            inventory['active_hosts']['hosts'].append(hostname)

        # Añadir children al grupo all
        for group in [role_group, env_group, dc_group]:
            if group not in inventory['all'].get('children', []):
                inventory['all'].setdefault('children', []).append(group)

    return inventory

def main():
    # Soporte para --list y --host (requerido por Ansible)
    if len(sys.argv) == 2 and sys.argv[1] == '--list':
        hosts = get_hosts_from_cmdb()
        inventory = build_inventory(hosts)
        print(json.dumps(inventory, indent=2))

    elif len(sys.argv) == 3 and sys.argv[1] == '--host':
        # AWX puede llamar con --host <hostname> para obtener vars específicas
        # Si _meta está en --list, esto no es necesario pero debe responder
        print(json.dumps({}))

    else:
        print("Uso: cmdb_inventory.py --list | --host <hostname>",
              file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
```

## Paso 2 — Crear la credencial para el script

```
Credentials → Add
  Name:         CMDB API Token
  Type:         Custom   (o usar tipo genérico con campos extra)
  
  # Si usas un tipo de credencial personalizado (ver sección avanzada):
  # Input Configuration:
  fields:
    - id: cmdb_url
      type: string
      label: CMDB URL
    - id: cmdb_token
      type: string
      label: CMDB Token
      secret: true
  
  # Injector Configuration:
  env:
    CMDB_URL:   "{{ cmdb_url }}"
    CMDB_TOKEN: "{{ cmdb_token }}"
  
  → Save
```

## Paso 3 — Crear el Inventory Source con el script

```
# El script debe estar en el repo Git del proyecto

# En el repo:
# inventory/scripts/cmdb_inventory.py  (el script de arriba)
# inventory/scripts/cmdb_inventory.cfg (configuración opcional)

# En AWX:
Inventories → CMDB Inventory → Sources → Add
  Name:         CMDB Script
  Source:       Sourced from a Project
  Project:      Platform Playbooks
  Inventory File: inventory/scripts/cmdb_inventory.py

  Credential:   CMDB API Token
  
  Environment Variables:
    CMDB_ENVIRONMENT: prod

  Update Options:
    ✅ Overwrite
    ✅ Overwrite Variables
    ✅ Update on Launch

  → Save → Sync
```

---

# 6.12 LAB — Smart Inventory para targeting por facts

*Crear un Smart Inventory que filtre hosts por facts cacheados en Redis.*

## Prerequisito: Fact Cache habilitado

```
# Verificar que el fact cache está activo
# En ansible.cfg del proyecto:
[defaults]
fact_caching = redis
fact_caching_connection = redis://localhost:6379/0
fact_caching_timeout = 86400

# Ejecutar un job con gather_facts: true para poblar el cache
# El job debe haber corrido al menos una vez en todos los hosts
```

## Paso 1 — Crear Smart Inventories por distribución

```
# Smart Inventory: solo servidores Ubuntu
Inventories → Add → Smart Inventory
  Name:         Smart - Ubuntu Servers
  Organization: MiEmpresa
  Smart Host Filter:
    ansible_distribution=Ubuntu
  → Save

# Smart Inventory: solo servidores con kernel antiguo (necesitan patching)
Inventories → Add → Smart Inventory
  Name:         Smart - Needs Kernel Update
  Organization: MiEmpresa
  Smart Host Filter:
    ansible_kernel__lt=5.15.0
  → Save

# Smart Inventory: servidores prod con más de 8GB RAM
Inventories → Add → Smart Inventory
  Name:         Smart - Prod High Memory
  Organization: MiEmpresa
  Smart Host Filter:
    variables__environment=prod AND ansible_memtotal_mb__gt=8192
  → Save
```

## Paso 2 — Verificar los hosts del Smart Inventory

```bash
# Ver cuántos hosts tiene el Smart Inventory
SMART_INV_ID=5  # ajusta
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${SMART_INV_ID}/hosts/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Hosts en el Smart Inventory: {data[\"count\"]}')
for host in data['results'][:10]:
    print(f'  {host[\"name\"]}')
"
```

## Paso 3 — Usar el Smart Inventory en un Job Template de patching

```yaml
# playbooks/patch_kernel.yml
---
- name: Actualizar kernel en servidores que lo necesitan
  hosts: all    # el Smart Inventory ya filtra los hosts correctos
  become: true
  gather_facts: true

  vars:
    target_kernel: "5.15.0"
    reboot_after_patch: "{{ reboot_after_patch | default(false) | bool }}"

  tasks:
    - name: Mostrar versión actual del kernel
      ansible.builtin.debug:
        msg: "Kernel actual: {{ ansible_kernel }} en {{ inventory_hostname }}"
      tags: [always]

    - name: Actualizar el kernel
      ansible.builtin.package:
        name: linux-image-generic
        state: latest
      register: kernel_update
      tags: [patch]

    - name: Reiniciar si se actualizó el kernel
      ansible.builtin.reboot:
        reboot_timeout: 300
        msg: "Reiniciando para aplicar nuevo kernel"
      when:
        - kernel_update.changed
        - reboot_after_patch | bool
      tags: [patch, reboot]

    - name: Mostrar nueva versión del kernel
      ansible.builtin.debug:
        msg: "Nuevo kernel: {{ ansible_kernel }}"
      tags: [always]
```

```
Templates → Add → Job Template
  Name:         Patch Kernel - Needs Update
  Inventory:    Smart - Needs Kernel Update   ← usa el Smart Inventory
  Playbook:     playbooks/patch_kernel.yml
  → Save
```

---

# 6.13 LAB — Constructed Inventory con grupos dinámicos

## Paso 1 — Crear el fichero de configuración del Constructed Inventory

```yaml
# inventory/constructed/prod_groups.yml
---
plugin: constructed

# Inventarios base
strict: false

# Grupos construidos con lógica Jinja2
groups:
  # Servidores web de producción
  prod_web:
    - environment == "prod"
    - role == "web"

  # Servidores de base de datos de producción
  prod_db:
    - environment == "prod"
    - role == "db"

  # Servidores que necesitan atención (en mantenimiento o con problemas)
  needs_attention:
    - maintenance_mode | default(false) | bool

  # Servidores con alta carga (si tienes el fact cacheado)
  high_load:
    - ansible_processor_vcpus | default(0) | int < 4
    - environment == "prod"

  # Servidores por zona de disponibilidad
  az_a:
    - az | default("") == "eu-west-1a"

  az_b:
    - az | default("") == "eu-west-1b"

  az_c:
    - az | default("") == "eu-west-1c"

# Variables derivadas (compose)
compose:
  # Nombre completo del host
  fqdn: inventory_hostname + ".empresa.com"

  # Prioridad de backup
  backup_priority: >-
    "critical" if (environment == "prod" and role == "db")
    else "high" if environment == "prod"
    else "low"

  # Flag de producción
  is_production: environment == "prod"

  # Endpoint de monitorización
  monitoring_url: '"http://monitoring.empresa.com/host/" + inventory_hostname'
```

## Paso 2 — Crear el Constructed Inventory en AWX

```
Inventories → Add → Constructed Inventory
  Name:         Constructed - Prod Groups
  Organization: MiEmpresa
  
  Input Inventories:
    + Env Inventory
    + AWS Production   (si tienes inventario AWS)
  
  Source vars:
    (pegar el contenido del fichero prod_groups.yml)
  
  Update Options:
    ✅ Overwrite
    ✅ Overwrite Variables
  
  → Save → Sync
```

## Paso 3 — Verificar los grupos construidos

```bash
# Ver los grupos del Constructed Inventory
CONST_INV_ID=6  # ajusta
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${CONST_INV_ID}/groups/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Grupos construidos: {data[\"count\"]}')
for group in data['results']:
    print(f'  {group[\"name\"]:40} | Hosts: {group[\"total_hosts\"]}')
"

# Ver las variables derivadas de un host
HOST_NAME="prod-web1"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${CONST_INV_ID}/hosts/?name=${HOST_NAME}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    host = data['results'][0]
    import json as j
    vars_dict = j.loads(host.get('variables', '{}'))
    print(f'Variables de {host[\"name\"]}:')
    for k, v in vars_dict.items():
        print(f'  {k}: {v}')
"
```

---

# 6.14 LAB — Proyecto con múltiples ramas y pin de versión

## Paso 1 — Estructura de ramas en Git

```
ESTRATEGIA DE RAMAS:

  main          → código estable, listo para producción
  develop       → integración de features
  feature/*     → desarrollo de nuevas funcionalidades
  hotfix/*      → correcciones urgentes de producción
  release/v*    → preparación de release (freeze de features)

TAGS:
  v1.0.0, v1.1.0, v2.0.0, ...  → versiones de producción
  v2.0.0-rc1, v2.0.0-rc2       → release candidates para staging
```

## Paso 2 — Crear proyectos por entorno en AWX

```bash
AWX_URL="http://localhost:30080"
AWX_TOKEN="tu-token-admin"
REPO_URL="https://github.com/empresa/platform-playbooks.git"

# Función para crear proyecto
create_project() {
    local name="$1"
    local branch="$2"
    local update_on_launch="$3"
    local org_id=1

    curl -s \
        -H "Authorization: Bearer ${AWX_TOKEN}" \
        -H "Content-Type: application/json" \
        -X POST \
        "${AWX_URL}/api/v2/projects/" \
        -d "{
            \"name\":                    \"${name}\",
            \"organization\":            ${org_id},
            \"scm_type\":                \"git\",
            \"scm_url\":                 \"${REPO_URL}\",
            \"scm_branch\":              \"${branch}\",
            \"scm_clean\":               true,
            \"scm_update_on_launch\":    ${update_on_launch},
            \"scm_update_cache_timeout\": 60,
            \"allow_override\":          true
        }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'id' in data:
    print(f'✅ Proyecto creado: {data[\"name\"]} (ID: {data[\"id\"]}, Branch: {data[\"scm_branch\"]})')
else:
    print(f'❌ Error: {data}')
"
}

# Proyecto para desarrollo (rama main, siempre actualizado)
create_project "Platform Playbooks (Dev)"   "main"   "true"

# Proyecto para staging (rama main, actualizado al lanzar)
create_project "Platform Playbooks (Stage)" "main"   "true"

# Proyecto para producción (tag fijo, NO actualizar automáticamente)
create_project "Platform Playbooks (Prod)"  "v2.0.0" "false"
```

## Paso 3 — Actualizar el pin de versión de producción

```bash
#!/bin/bash
# script: update_prod_version.sh
# Actualiza el pin de versión del proyecto de producción

AWX_URL="http://localhost:30080"
AWX_TOKEN="tu-token-admin"
PROD_PROJECT_ID=5
NEW_VERSION="$1"

if [ -z "$NEW_VERSION" ]; then
    echo "Uso: $0 <version>"
    echo "Ejemplo: $0 v2.1.0"
    exit 1
fi

echo "Actualizando proyecto de producción a ${NEW_VERSION}..."

# Actualizar la rama/tag del proyecto
UPDATE_RESP=$(curl -s \
    -H "Authorization: Bearer ${AWX_TOKEN}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    "${AWX_URL}/api/v2/projects/${PROD_PROJECT_ID}/" \
    -d "{\"scm_branch\": \"${NEW_VERSION}\"}")

CURRENT_BRANCH=$(echo "$UPDATE_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('scm_branch', 'error'))
")

if [ "$CURRENT_BRANCH" = "$NEW_VERSION" ]; then
    echo "✅ Proyecto actualizado a: ${NEW_VERSION}"
else
    echo "❌ Error actualizando el proyecto"
    exit 1
fi

# Sincronizar el proyecto con el nuevo tag
echo "Sincronizando..."
SYNC_RESP=$(curl -s \
    -H "Authorization: Bearer ${AWX_TOKEN}" \
    -X POST \
    "${AWX_URL}/api/v2/projects/${PROD_PROJECT_ID}/update/")

SYNC_JOB_ID=$(echo "$SYNC_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('id', 'error'))
")

echo "✅ Sync lanzado: Job ID ${SYNC_JOB_ID}"

# Esperar a que termine el sync
MAX_WAIT=120
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS=$(curl -s \
        -H "Authorization: Bearer ${AWX_TOKEN}" \
        "${AWX_URL}/api/v2/project_updates/${SYNC_JOB_ID}/" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))")

    if [ "$STATUS" = "successful" ]; then
        echo "✅ Proyecto sincronizado correctamente con ${NEW_VERSION}"
        exit 0
    elif [ "$STATUS" = "failed" ] || [ "$STATUS" = "error" ]; then
        echo "❌ Sync falló: ${STATUS}"
        exit 1
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "⏰ Timeout esperando el sync"
exit 1
```

---

# 6.15 LAB — Pipeline de validación de playbooks en CI

*Validar la calidad del código de automatización antes de que llegue a AWX.*

## Paso 1 — Configurar el pipeline de CI completo

```yaml
# .github/workflows/validate-playbooks.yml
---
name: Validate Ansible Playbooks

on:
  push:
    branches: [main, develop, 'feature/**', 'release/**']
  pull_request:
    branches: [main, develop]

jobs:

  # ── JOB 1: Lint con ansible-lint ─────────────────────────────
  ansible-lint:
    name: 🔍 Ansible Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar dependencias
        run: |
          pip install ansible-core ansible-lint

      - name: Crear ansible.cfg para CI
        run: |
          cat > ansible.cfg << 'EOF'
          [defaults]
          roles_path = roles
          collections_paths = ~/.ansible/collections
          host_key_checking = false
          EOF

      - name: Instalar colecciones requeridas
        run: |
          if [ -f collections/requirements.yml ]; then
            ansible-galaxy collection install -r collections/requirements.yml
          fi

      - name: Ejecutar ansible-lint
        run: |
          ansible-lint --show-relpath --profile production
        env:
          ANSIBLE_FORCE_COLOR: "1"

  # ── JOB 2: Syntax check de todos los playbooks ───────────────
  syntax-check:
    name: 📝 Syntax Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar ansible-core
        run: pip install ansible-core

      - name: Instalar colecciones
        run: |
          if [ -f collections/requirements.yml ]; then
            ansible-galaxy collection install -r collections/requirements.yml
          fi

      - name: Verificar sintaxis de todos los playbooks
        run: |
          FAILED=0
          for playbook in playbooks/*.yml; do
            echo "Verificando: $playbook"
            if ansible-playbook --syntax-check "$playbook" \
                -i "localhost," \
                -e "ansible_connection=local" \
                -e "target_group=localhost" \
                -e "release_tag=v0.0.0" \
                -e "environment=dev" \
                -e "app_version=v0.0.0" 2>&1; then
              echo "  ✅ OK: $playbook"
            else
              echo "  ❌ FAIL: $playbook"
              FAILED=$((FAILED + 1))
            fi
          done
          exit $FAILED

  # ── JOB 3: Molecule tests (si están configurados) ─────────────
  molecule-test:
    name: 🧪 Molecule Tests
    runs-on: ubuntu-latest
    if: hashFiles('roles/*/molecule/default/molecule.yml') != ''
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar dependencias de Molecule
        run: |
          pip install ansible-core molecule molecule-plugins[docker]

      - name: Ejecutar Molecule tests
        run: |
          for role_dir in roles/*/; do
            if [ -d "${role_dir}molecule/default" ]; then
              echo "Testing role: ${role_dir}"
              cd "${role_dir}"
              molecule test
              cd -
            fi
          done

  # ── JOB 4: Validar estructura del inventario ──────────────────
  validate-inventory:
    name: 📋 Validate Inventory
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar ansible-core
        run: pip install ansible-core

      - name: Validar inventario estático
        run: |
          if [ -f inventory/hosts.yml ]; then
            ansible-inventory -i inventory/hosts.yml --list > /dev/null
            echo "✅ Inventario válido"
            ansible-inventory -i inventory/hosts.yml --graph
          fi

  # ── JOB 5: Verificar requirements.yml ────────────────────────
  validate-requirements:
    name: 📦 Validate Requirements
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar ansible-core
        run: pip install ansible-core

      - name: Verificar collections/requirements.yml
        run: |
          if [ -f collections/requirements.yml ]; then
            python3 -c "
          import yaml, sys
          with open('collections/requirements.yml') as f:
              data = yaml.safe_load(f)
          collections = data.get('collections', [])
          print(f'Colecciones declaradas: {len(collections)}')
          errors = 0
          for col in collections:
              if 'version' not in col:
                  print(f'  ⚠️  Sin versión fijada: {col[\"name\"]}')
                  errors += 1
              else:
                  print(f'  ✅ {col[\"name\"]}: {col[\"version\"]}')
          if errors > 0:
              print(f'ERROR: {errors} colecciones sin versión fijada')
              sys.exit(1)
          "
          fi

  # ── JOB 6: Notificar a AWX si todo pasa (solo en main) ────────
  notify-awx:
    name: 🚀 Notify AWX
    runs-on: ubuntu-latest
    needs: [ansible-lint, syntax-check, validate-inventory, validate-requirements]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    steps:
      - name: Sincronizar proyecto en AWX
        env:
          AWX_URL:   ${{ secrets.AWX_URL }}
          AWX_TOKEN: ${{ secrets.AWX_TOKEN }}
        run: |
          # Sincronizar el proyecto de dev/stage
          DEV_PROJECT_ID=3  # ajusta

          echo "Sincronizando proyecto AWX Dev..."
          RESP=$(curl -sS -w "\n%{http_code}" \
            -H "Authorization: Bearer ${AWX_TOKEN}" \
            -X POST \
            "${AWX_URL}/api/v2/projects/${DEV_PROJECT_ID}/update/")

          HTTP_CODE=$(echo "$RESP" | tail -1)
          BODY=$(echo "$RESP" | head -1)

          if [ "$HTTP_CODE" = "202" ]; then
            JOB_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
            echo "✅ Sync lanzado: Job ID ${JOB_ID}"
          else
            echo "❌ Error: HTTP ${HTTP_CODE}"
            echo "$BODY"
            exit 1
          fi
```

## Paso 2 — Configurar .ansible-lint

```yaml
# .ansible-lint
---
profile: production

# Reglas a excluir (justificadas)
skip_list:
  - yaml[line-length]    # líneas largas en templates son inevitables
  - no-changed-when      # algunos comandos son idempotentes por naturaleza

# Reglas adicionales
warn_list:
  - experimental

# Excluir directorios
exclude_paths:
  - .git/
  - .github/
  - molecule/
  - tests/

# Configuración de parsers
use_default_rules: true
verbosity: 1
```
# 6.16 Patrones avanzados y buenas prácticas

## Patrón 1: Inventario como código (IaC)

```
PRINCIPIO:
  El inventario estático debe vivir en Git, no solo en AWX.
  Cualquier cambio en el inventario debe pasar por PR y revisión.
  AWX lo importa desde el proyecto SCM.

ESTRUCTURA EN EL REPO:
  inventory/
    hosts.yml              ← inventario principal
    group_vars/
      all.yml              ← variables para todos los hosts
      prod.yml             ← variables específicas de prod
      dev.yml
    host_vars/
      prod-web1.yml        ← variables específicas de un host

FLUJO DE CAMBIOS:
  1. Developer abre PR con cambio en inventory/hosts.yml
  2. CI valida el inventario: ansible-inventory --list
  3. Revisión por Platform Engineer
  4. Merge a main
  5. AWX sincroniza el proyecto automáticamente
  6. El inventario se actualiza en AWX sin intervención manual

VENTAJAS:
  → Historial de cambios completo en Git
  → Revisión obligatoria antes de aplicar
  → Rollback fácil: git revert + sync
  → Consistencia garantizada entre entornos
  → Auditoría: quién cambió qué y cuándo
```

---

## Patrón 2: Jerarquía de variables sin ambigüedad

La precedencia de variables en Ansible es compleja. Diseñar una jerarquía clara desde el principio evita horas de debugging.

```
JERARQUÍA RECOMENDADA (de menor a mayor precedencia):

1. group_vars/all.yml
   → Valores por defecto globales
   → Ejemplo: ansible_user: ansible, ntp_server: ntp.empresa.com

2. group_vars/<entorno>.yml  (dev.yml, stage.yml, prod.yml)
   → Valores específicos del entorno
   → Ejemplo: log_level: debug (dev), log_level: warning (prod)

3. group_vars/<rol>.yml  (web.yml, db.yml)
   → Valores específicos del rol del servidor
   → Ejemplo: nginx_workers: 4 (web), pg_max_conn: 200 (db)

4. host_vars/<hostname>.yml
   → Valores específicos de un host concreto
   → Ejemplo: az: eu-west-1a, server_id: 1

5. Extra Vars del Job Template (hardcoded)
   → Valores técnicos que no deben cambiar
   → Ejemplo: health_check_retries: 5

6. Survey del Workflow/Template
   → Valores introducidos por el operador al lanzar
   → Ejemplo: release_tag: v2.0.0, environment: prod

REGLA DE ORO:
  Si una variable aparece en más de un nivel, hay un problema de diseño.
  Cada variable debe tener exactamente UN lugar canónico donde se define.
```

```yaml
# group_vars/all.yml
---
# Variables globales - aplican a TODOS los hosts
ansible_user:              ansible
ansible_python_interpreter: /usr/bin/python3
ntp_servers:
  - ntp1.empresa.com
  - ntp2.empresa.com
dns_servers:
  - 10.0.0.53
  - 10.0.0.54
log_retention_days:        30
backup_enabled:            false    # override en prod

# group_vars/prod.yml
---
# Variables específicas de producción
log_level:                 warning
backup_enabled:            true
backup_retention_days:     90
monitoring_enabled:        true
alert_threshold_cpu:       80
alert_threshold_mem:       85
maintenance_window:        "02:00-04:00"
change_freeze_enabled:     false

# group_vars/dev.yml
---
# Variables específicas de desarrollo
log_level:                 debug
backup_enabled:            false
monitoring_enabled:        false
# En dev, permitir conexiones sin verificación de host
ansible_ssh_extra_args:    "-o StrictHostKeyChecking=no"
```

---

## Patrón 3: Separación de inventarios por criticidad

```
INVENTARIO 1: Dev/Stage (actualización frecuente y automática)
  Source: SCM + Dynamic (cuentas dev/stage)
  Update on Launch: ✅
  Sync interval:    cada 15 minutos
  Razón: en dev queremos siempre el estado más reciente

INVENTARIO 2: Producción (actualización controlada)
  Source: SCM (versión fija) + Dynamic (cuenta prod)
  Update on Launch: ☐
  Sync interval:    cada hora, con alerta si cambia
  Razón: en prod, un host nuevo inesperado puede ampliar
         el blast radius de un job. Los cambios deben ser
         deliberados y revisados.

INVENTARIO 3: Emergencia (snapshot estático)
  Source: copia manual del inventario de prod
  Update:  solo manual, solo Platform Admin
  Uso:     cuando el inventario dinámico falla y necesitas
           ejecutar algo urgente con un inventario conocido
```

---

## Patrón 4: Gestión de hosts en mantenimiento

```yaml
# En host_vars/prod-web1.yml
---
maintenance_mode: true
maintenance_reason: "Sustitución de disco - TICKET-4521"
maintenance_until:  "2026-06-05T06:00:00Z"
```

```yaml
# En los playbooks, respetar el modo mantenimiento
---
- name: Deploy Application
  hosts: all
  gather_facts: false

  pre_tasks:
    - name: Verificar que el host no está en mantenimiento
      ansible.builtin.assert:
        that:
          - not (maintenance_mode | default(false) | bool)
        fail_msg: >
          Host {{ inventory_hostname }} está en modo mantenimiento.
          Razón: {{ maintenance_reason | default('No especificada') }}
          Hasta: {{ maintenance_until | default('No especificado') }}
          Saltar este host con: --limit '!{{ inventory_hostname }}'
        success_msg: "Host {{ inventory_hostname }} disponible para deploy"
      tags: [always]
```

```
# Smart Inventory para hosts en mantenimiento (para monitorización)
Inventories → Add → Smart Inventory
  Name:         Smart - En Mantenimiento
  Smart Host Filter: variables__maintenance_mode=true

# Smart Inventory para hosts activos (excluye mantenimiento)
Inventories → Add → Smart Inventory
  Name:         Smart - Activos
  Smart Host Filter: variables__maintenance_mode=false OR NOT variables__maintenance_mode__exists=true
```

---

## Patrón 5: Inventario dinámico con caché para resiliencia

```
PROBLEMA:
  Si AWS tiene un outage o la CMDB no responde, el inventario
  dinámico falla y todos los jobs que usan "Update on Launch"
  también fallan.

SOLUCIÓN: Caché de inventario con TTL

  En la Inventory Source:
    Cache Timeout: 3600  (1 hora)
    
    Si el sync falla, AWX usa el último inventario válido
    cacheado durante hasta 1 hora.
    
    Después de 1 hora sin sync exitoso, el inventario
    se marca como stale y AWX alerta.

CONFIGURACIÓN:
  Inventories → AWS Production → Sources → EC2 eu-west-1 → Edit
    Cache Timeout: 3600
    → Save
```

---

## Patrón 6: Múltiples fuentes en un mismo inventario

```
CASO DE USO:
  Tu infraestructura está en AWS (servidores cloud) y
  también tienes servidores físicos en un datacenter (en la CMDB).
  Quieres un inventario unificado.

SOLUCIÓN: Múltiples Inventory Sources en el mismo inventario

  Inventories → Hybrid Inventory → Sources:
    Source 1: EC2 eu-west-1      (AWS cloud)
    Source 2: EC2 us-east-1      (AWS cloud, otra región)
    Source 3: CMDB Script        (datacenter físico)
    Source 4: SCM hosts.yml      (hosts estáticos adicionales)

  AWX combina todas las fuentes en un único inventario.
  Los grupos de cada fuente coexisten sin conflicto.
  
  CUIDADO: si dos fuentes tienen un host con el mismo nombre,
  las variables se fusionan. Definir qué fuente tiene precedencia:
    Overwrite Variables: ✅ en la fuente con mayor prioridad
```

---

## Patrón 7: Proyectos con credenciales SCM separadas por entorno

```
PROBLEMA:
  Usar el mismo token de GitHub para dev y prod significa que
  si el token se compromete, afecta a ambos entornos.

SOLUCIÓN: Credenciales SCM separadas

  Credential: GitHub Dev Token
    Token: ghp_dev_token_xxx
    Permisos: solo lectura en repos de dev
  
  Credential: GitHub Prod Token
    Token: ghp_prod_token_yyy
    Permisos: solo lectura en el repo de prod (rama protegida)
    Rotación: más frecuente

  Project Dev:  usa GitHub Dev Token
  Project Prod: usa GitHub Prod Token

  Si el token de dev se compromete:
  → El atacante solo puede leer el repo de dev
  → El repo de prod está protegido con otro token
```

---

## Patrón 8: Validación de inventario antes del deploy

```yaml
# playbooks/validate_inventory.yml
# Ejecutar como primer nodo del Workflow, antes del deploy
---
- name: Validar inventario antes del deploy
  hosts: "{{ target_group }}"
  gather_facts: false

  vars:
    min_hosts_required: "{{ min_hosts | default(1) | int }}"
    max_hosts_allowed:  "{{ max_hosts | default(100) | int }}"

  tasks:
    - name: Verificar número mínimo de hosts
      ansible.builtin.assert:
        that:
          - ansible_play_hosts | length >= min_hosts_required
        fail_msg: >
          Inventario insuficiente: se esperaban al menos
          {{ min_hosts_required }} hosts pero solo hay
          {{ ansible_play_hosts | length }}.
          Verificar que el inventario está sincronizado.
        success_msg: >
          ✅ Hosts disponibles: {{ ansible_play_hosts | length }}
      run_once: true
      tags: [always]

    - name: Verificar que no hay demasiados hosts (protección blast radius)
      ansible.builtin.assert:
        that:
          - ansible_play_hosts | length <= max_hosts_allowed
        fail_msg: >
          Demasiados hosts: {{ ansible_play_hosts | length }}.
          Máximo permitido: {{ max_hosts_allowed }}.
          Usar Limit para reducir el alcance.
        success_msg: >
          ✅ Número de hosts dentro del límite permitido.
      run_once: true
      when: max_hosts_allowed > 0
      tags: [always]

    - name: Verificar conectividad SSH con todos los hosts
      ansible.builtin.ping:
      register: ping_result
      ignore_errors: true
      tags: [connectivity]

    - name: Reportar hosts no alcanzables
      ansible.builtin.debug:
        msg: "⚠️  Host no alcanzable: {{ inventory_hostname }}"
      when: ping_result is failed
      tags: [connectivity]

    - name: Fallar si hay hosts no alcanzables en producción
      ansible.builtin.fail:
        msg: >
          Host {{ inventory_hostname }} no responde.
          Verificar conectividad antes de continuar el deploy.
      when:
        - ping_result is failed
        - environment == "prod"
      tags: [connectivity]
```

---

## Patrón 9: Webhook de inventario para actualizaciones en tiempo real

```
CASO DE USO:
  Cuando AWS lanza una nueva instancia (Auto Scaling),
  quieres que AWX actualice el inventario inmediatamente
  y configure la instancia automáticamente.

FLUJO:
  1. Auto Scaling Group lanza nueva instancia EC2
  2. CloudWatch Event detecta el lanzamiento
  3. Lambda function llama al webhook de AWX:
     POST /api/v2/inventory_sources/ID/update/
  4. AWX sincroniza el inventario
  5. La nueva instancia aparece en el inventario
  6. AWX lanza el Job Template de configuración
     (via Provisioning Callback desde la instancia)

CONFIGURACIÓN DEL WEBHOOK EN AWX:
  Inventories → AWS Production → Sources → EC2 eu-west-1 → Edit
  Options: ✅ Enable Webhook
  
  AWX genera:
    Webhook URL: http://awx:30080/api/v2/inventory_sources/2/update/
    Webhook Key: abc123secretkey

LAMBDA FUNCTION (Python):
```

```python
# lambda_function.py
# Trigger: CloudWatch Event - EC2 Instance State-change Notification

import json
import urllib.request
import urllib.error

AWX_URL        = "http://awx.empresa.com:30080"
INV_SOURCE_ID  = "2"
AWX_TOKEN      = "tu-token-de-servicio"

def lambda_handler(event, context):
    instance_id    = event['detail']['instance-id']
    instance_state = event['detail']['state']

    print(f"Instancia {instance_id} cambió a estado: {instance_state}")

    if instance_state not in ['running', 'terminated']:
        print(f"Estado {instance_state} no requiere acción")
        return {'statusCode': 200}

    # Sincronizar inventario en AWX
    url = f"{AWX_URL}/api/v2/inventory_sources/{INV_SOURCE_ID}/update/"
    req = urllib.request.Request(
        url,
        method='POST',
        headers={
            'Authorization': f'Bearer {AWX_TOKEN}',
            'Content-Type':  'application/json'
        },
        data=json.dumps({}).encode()
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            print(f"✅ Sync lanzado: Job ID {data.get('id')}")
            return {'statusCode': 202, 'body': json.dumps(data)}
    except urllib.error.HTTPError as e:
        print(f"❌ Error HTTP {e.code}: {e.read().decode()}")
        return {'statusCode': e.code}
```

---

## Patrón 10: Gestión de secrets en group_vars con Vault

```bash
# Cifrar variables sensibles con ansible-vault
# Las variables cifradas se guardan en Git de forma segura

# Cifrar un fichero de variables completo
ansible-vault encrypt inventory/group_vars/prod/secrets.yml \
    --vault-id prod@~/.vault_pass_prod

# O cifrar solo el valor de una variable (inline encryption)
ansible-vault encrypt_string \
    --vault-id prod@~/.vault_pass_prod \
    'SuperSecretPassword123!' \
    --name 'db_password'

# Resultado (se puede guardar en el YAML):
# db_password: !vault |
#   $ANSIBLE_VAULT;1.2;AES256;prod
#   61616161616161616161616161616161...
```

```yaml
# inventory/group_vars/prod/secrets.yml
# Este fichero está cifrado con ansible-vault
---
db_password:       !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  61616161...

api_secret_key:    !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  62626262...

smtp_password:     !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  63636363...
```

```
# En AWX, la credencial Vault descifra automáticamente estos valores
# Credentials → Vault Prod → Vault Identifier: prod
# El Job Template tiene adjunta esta credencial Vault
```

---

# 6.17 Troubleshooting del Módulo 6

## Problema 1: El inventario dinámico no se sincroniza

**Síntoma:**
```
La Inventory Source muestra status "failed" o los hosts
no aparecen en el inventario después del sync.
```

**Diagnóstico:**
```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver el estado de todas las Inventory Sources
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventory_sources/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for src in data['results']:
    icon = '✅' if src['status'] == 'successful' else '❌'
    print(f'{icon} {src[\"name\"]:35} | Status: {src[\"status\"]:12} | Last: {str(src.get(\"last_updated\",\"\"))[:19]}')
"

# Ver el log del último sync fallido
INV_SOURCE_ID=2
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventory_sources/${INV_SOURCE_ID}/inventory_updates/?order_by=-id&page_size=1" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    update = data['results'][0]
    print(f'Status:  {update[\"status\"]}')
    print(f'Started: {update[\"started\"]}')
    print(f'Elapsed: {update[\"elapsed\"]}s')
    print(f'Job ID:  {update[\"id\"]}')
"

# Ver el output completo del sync fallido
UPDATE_JOB_ID=10  # ajusta al ID del job de update
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventory_updates/${UPDATE_JOB_ID}/stdout/?format=txt" \
    | head -100
```

**Causas y soluciones:**

```
CAUSA 1: Credencial AWS inválida o expirada
  
  Síntoma en el log:
    botocore.exceptions.ClientError: An error occurred (AuthFailure)
    botocore.exceptions.NoCredentialsError
  
  Diagnóstico:
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
      python3 -c "
    import boto3
    ec2 = boto3.client('ec2', region_name='eu-west-1',
        aws_access_key_id='AKIAIOSFODNN7EXAMPLE',
        aws_secret_access_key='wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY')
    print(ec2.describe_regions()['Regions'][0]['RegionName'])
    "
  
  Solución:
    Credentials → AWS ReadOnly → Edit
    Actualizar Access Key y Secret Key
    → Save → Re-sync

CAUSA 2: El EE no tiene el plugin aws_ec2 instalado
  
  Síntoma en el log:
    [WARNING]: * Failed to parse inventory source with auto plugin
    amazon.aws collection not found
  
  Solución:
    Verificar que el EE tiene la colección amazon.aws:
    docker run --rm <ee-image> ansible-galaxy collection list | grep amazon
    
    Si no está: reconstruir el EE con amazon.aws en requirements.yml

CAUSA 3: Filtros de Instance Filters demasiado restrictivos
  
  El sync completa sin error pero no hay hosts.
  
  Diagnóstico:
    Temporalmente eliminar los filtros y hacer sync.
    Si aparecen hosts, el filtro es el problema.
  
  Solución:
    Revisar los filtros en Source Variables:
    filters:
      tag:Environment: prod        ← verificar que el tag existe en AWS
      instance-state-name: running ← verificar que hay instancias running

CAUSA 4: Problema de red: el pod AWX no llega a la API de AWS
  
  Síntoma en el log:
    ConnectionError: HTTPSConnectionPool(host='ec2.eu-west-1.amazonaws.com')
  
  Diagnóstico:
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
      curl -s https://ec2.eu-west-1.amazonaws.com --max-time 5 -o /dev/null -w "%{http_code}"
  
  Solución:
    Verificar que el pod tiene salida a internet
    Revisar NetworkPolicies de Kubernetes
    Configurar proxy si es necesario:
    Administration → Settings → System
    HTTP Proxy: http://proxy.empresa.com:3128

CAUSA 5: Script de inventario personalizado con error
  
  Síntoma en el log:
    ERROR: Script returned non-zero exit code
    Traceback (most recent call last): ...
  
  Diagnóstico:
    Ejecutar el script manualmente desde el pod:
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
      python3 /path/to/script.py --list
  
  Solución:
    Corregir el error en el script
    Asegurarse de que el script devuelve JSON válido
    Verificar que las variables de entorno necesarias están configuradas
```

---

## Problema 2: Variables del inventario no llegan al playbook

**Síntoma:**
```
El playbook usa {{ environment }} pero la variable tiene
el valor por defecto en lugar del valor del inventario.
```

**Diagnóstico:**
```bash
# Ver las variables de un host específico en el inventario
HOST_NAME="prod-web1"
INV_ID=1

curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/hosts/?name=${HOST_NAME}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    host = data['results'][0]
    import json as j
    vars_dict = j.loads(host.get('variables', '{}'))
    print(f'Variables del host {host[\"name\"]}:')
    for k, v in sorted(vars_dict.items()):
        print(f'  {k}: {v}')
else:
    print('Host no encontrado en el inventario')
"

# Ver las variables del grupo al que pertenece el host
GROUP_NAME="prod"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/groups/?name=${GROUP_NAME}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    group = data['results'][0]
    import json as j
    vars_dict = j.loads(group.get('variables', '{}'))
    print(f'Variables del grupo {group[\"name\"]}:')
    for k, v in sorted(vars_dict.items()):
        print(f'  {k}: {v}')
"

# Ver el inventario completo con todas las variables resueltas
# (ejecutar desde la línea de comandos en el servidor de control)
ansible-inventory -i inventory/hosts.yml --host prod-web1
```

**Causas y soluciones:**

```
CAUSA 1: Las variables están en group_vars pero no se sincronizan
  
  Si el inventario viene de un proyecto SCM, las group_vars
  del repo se cargan automáticamente.
  Si el inventario es manual en AWX, hay que añadir las
  variables directamente en AWX (no en ficheros).
  
  Solución:
    Inventories → Env Inventory → Groups → prod → Edit
    Variables:
      ---
      environment: prod
      log_level: warning
    → Save

CAUSA 2: La variable está en el inventario pero el playbook usa default()
  
  Si el playbook tiene:
    environment: "{{ environment | default('dev') }}"
  
  Y la variable del inventario se llama "env" (no "environment"),
  el default() se activa porque "environment" no existe.
  
  Solución:
    Verificar que el nombre de la variable en el inventario
    coincide exactamente con el nombre usado en el playbook.
    Los nombres son case-sensitive.

CAUSA 3: Extra Vars del Job Template sobreescriben las del inventario
  
  Si el Job Template tiene en Extra Vars:
    environment: dev
  
  Esto sobreescribe el valor del inventario porque Extra Vars
  tienen mayor precedencia.
  
  Solución:
    Eliminar la variable del campo Extra Vars del template.
    O usar el Survey para que el operador la especifique.

CAUSA 4: Inventory Source con "Overwrite Variables" activo borra las vars manuales
  
  Si tienes variables añadidas manualmente en AWX y también
  una Inventory Source con "Overwrite Variables: ✅",
  el sync borra las variables manuales.
  
  Solución:
    Opción A: Desactivar "Overwrite Variables" en la Inventory Source
    Opción B: Añadir las variables en el script/plugin de inventario
    Opción C: Usar group_vars en el proyecto SCM (más limpio)
```

---

## Problema 3: El proyecto no se sincroniza desde Git

**Síntoma:**
```
El proyecto muestra status "failed" en el sync.
Los playbooks en AWX son de una versión antigua.
```

**Diagnóstico:**
```bash
# Ver el estado del proyecto
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/projects/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for proj in data['results']:
    icon = '✅' if proj['status'] == 'successful' else '❌'
    print(f'{icon} {proj[\"name\"]:35} | {proj[\"status\"]:12} | Branch: {proj[\"scm_branch\"]}')
"

# Ver el log del último sync fallido
PROJECT_ID=3
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/projects/${PROJECT_ID}/project_updates/?order_by=-id&page_size=1" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    update = data['results'][0]
    print(f'Status:  {update[\"status\"]}')
    print(f'Job ID:  {update[\"id\"]}')
"

# Ver el output del sync
UPDATE_ID=5  # ajusta
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/project_updates/${UPDATE_ID}/stdout/?format=txt" \
    | head -50

# Probar la conexión Git desde el pod de AWX
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    git ls-remote https://github.com/empresa/platform-playbooks.git HEAD
```

**Causas y soluciones:**

```
CAUSA 1: Token de GitHub/GitLab expirado o revocado
  
  Síntoma en el log:
    fatal: Authentication failed for 'https://github.com/...'
    remote: Invalid username or password.
  
  Solución:
    Credentials → GitHub Token → Edit
    SCM Token: (nuevo token con permisos repo:read)
    → Save → Re-sync el proyecto

CAUSA 2: Rama o tag no existe
  
  Síntoma en el log:
    error: pathspec 'v2.0.0' did not match any file(s) known to git
    fatal: Remote branch v2.0.0 not found in upstream origin
  
  Solución:
    Verificar que el tag existe en GitHub:
    curl -s https://api.github.com/repos/empresa/platform-playbooks/tags
    
    Actualizar el proyecto con el tag correcto:
    Projects → Platform Playbooks (Prod) → Edit
    SCM Branch/Tag/Commit: v2.0.1  (el tag que sí existe)

CAUSA 3: El repo es privado y la credencial no tiene acceso
  
  Síntoma en el log:
    ERROR! Repository not found.
    fatal: repository 'https://github.com/empresa/...' not found
  
  Solución:
    Verificar que el token tiene acceso al repo:
    curl -H "Authorization: token TU_TOKEN" \
      https://api.github.com/repos/empresa/platform-playbooks
    
    Si devuelve 404: el token no tiene acceso al repo
    Regenerar el token con permisos correctos

CAUSA 4: Conflicto de merge o ficheros corruptos en el workspace
  
  AWX mantiene un workspace local del repo.
  Si hay cambios locales (ej: de una ejecución anterior),
  el pull puede fallar.
  
  Solución:
    Projects → Tu Proyecto → Edit
    Options: ✅ Clean  (hace git clean -fdx antes del pull)
    → Save → Re-sync

CAUSA 5: requirements.yml con colección que no existe o versión inválida
  
  Síntoma en el log:
    ERROR: Could not find a version that satisfies the requirement
    ERROR: No matching distribution found for ansible-core>=2.99
  
  Solución:
    Revisar collections/requirements.yml
    Verificar que todas las colecciones existen en Galaxy:
    ansible-galaxy collection info <nombre>
    Verificar que las versiones especificadas existen
```

---

## Problema 4: Smart Inventory no muestra los hosts esperados

**Síntoma:**
```
El Smart Inventory debería tener 50 hosts de producción
pero muestra 0 o un número incorrecto.
```

**Diagnóstico:**
```bash
# Ver el filtro del Smart Inventory
SMART_INV_ID=5
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${SMART_INV_ID}/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Smart Inventory: {data[\"name\"]}')
print(f'Filter: {data[\"host_filter\"]}')
print(f'Total hosts: {data[\"total_hosts\"]}')
"

# Probar el filtro manualmente contra el inventario base
BASE_INV_ID=1
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${BASE_INV_ID}/hosts/?variables__environment=prod&page_size=5" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Hosts con environment=prod en el inventario base: {data[\"count\"]}')
for host in data['results'][:5]:
    print(f'  {host[\"name\"]}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El filtro usa un campo que no existe en las variables del host
  
  Filtro: variables__environment=prod
  Pero las variables del host tienen: env=prod (no environment)
  
  Solución:
    Verificar el nombre exacto de la variable:
    Inventories → Base Inventory → Hosts → (un host) → Variables
    Actualizar el filtro para usar el nombre correcto:
    variables__env=prod

CAUSA 2: El fact cacheado no está disponible
  
  Si el filtro usa facts (ansible_distribution=Ubuntu)
  pero el fact cache está vacío o expirado, no hay matches.
  
  Solución:
    Ejecutar un job con gather_facts: true en el inventario base
    para poblar el fact cache.
    Luego el Smart Inventory debería mostrar los hosts.

CAUSA 3: El Smart Inventory no se actualiza automáticamente
  
  Los Smart Inventories se actualizan cuando se actualiza
  el inventario base. Si el base no se ha sincronizado
  recientemente, el Smart puede estar desactualizado.
  
  Solución:
    Sincronizar el inventario base primero:
    Inventories → Base Inventory → Sources → Sync All
    Luego verificar el Smart Inventory.

CAUSA 4: Sintaxis del filtro incorrecta
  
  Los filtros de Smart Inventory usan la sintaxis de Django ORM.
  Algunos operadores comunes:
    variables__environment=prod          ← igual
    variables__environment__icontains=pr ← contiene (case insensitive)
    name__startswith=prod                ← empieza por
    groups__name=prod_web                ← pertenece al grupo
    ansible_distribution=Ubuntu          ← fact cacheado
  
  Solución:
    Probar el filtro en la UI de AWX:
    Inventories → Smart Inventory → Edit
    Smart Host Filter: (usar el campo de búsqueda interactivo)
```

---

## Problema 5: ansible-lint falla en CI pero el playbook funciona en AWX

**Síntoma:**
```
El pipeline de CI falla con errores de ansible-lint pero
el mismo playbook se ejecuta sin problemas en AWX.
```

**Diagnóstico y soluciones:**

```
CAUSA 1: Versión diferente de ansible-lint entre CI y AWX
  
  CI usa ansible-lint 6.x pero AWX usa ansible-core 2.15
  con reglas diferentes.
  
  Solución:
    Fijar la versión de ansible-lint en CI:
    pip install ansible-lint==24.x.x
    
    Usar el mismo perfil que en producción:
    ansible-lint --profile production

CAUSA 2: Colecciones no instaladas en CI
  
  ansible-lint necesita las colecciones para validar los módulos.
  Si community.general no está instalado, lint falla con
  "couldn't resolve module/action".
  
  Solución:
    En el CI, instalar las colecciones antes de lint:
    ansible-galaxy collection install -r collections/requirements.yml

CAUSA 3: Reglas demasiado estrictas para el código existente
  
  Tienes playbooks legacy que no cumplen todas las reglas
  pero funcionan correctamente.
  
  Solución:
    Crear .ansible-lint con skip_list para las reglas problemáticas:
    skip_list:
      - yaml[line-length]
      - no-changed-when
    
    O añadir noqa inline en las tareas específicas:
    - name: Tarea legacy
      ansible.builtin.shell: comando_complejo  # noqa: command-instead-of-module

CAUSA 4: Variables no definidas en el contexto de lint
  
  ansible-lint puede quejarse de variables que solo existen
  en tiempo de ejecución (facts, variables del inventario).
  
  Solución:
    Usar default() en las variables que pueden no existir:
    "{{ ansible_distribution | default('Unknown') }}"
    
    O crear un fichero de variables para lint:
    ansible-lint --extra-vars @tests/lint_vars.yml
```

---

## Referencia rápida: comandos de diagnóstico de inventarios

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver todos los inventarios y su estado
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/inventories/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total inventarios: {data[\"count\"]}')
for inv in data['results']:
    inv_type = inv.get('kind', 'standard')
    print(f'  ID:{inv[\"id\"]:3} | {inv[\"name\"]:35} | Tipo: {inv_type:10} | Hosts: {inv[\"total_hosts\"]}')
"

# Ver las fuentes de un inventario específico
INV_ID=1
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/inventory_sources/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for src in data['results']:
    icon = '✅' if src['status'] == 'successful' else '❌' if src['status'] == 'failed' else '⏳'
    print(f'{icon} {src[\"name\"]:35} | {src[\"source\"]:15} | {src[\"status\"]}')
"

# Ver todos los proyectos y su estado
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/projects/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for proj in data['results']:
    icon = '✅' if proj['status'] == 'successful' else '❌' if proj['status'] == 'failed' else '⏳'
    print(f'{icon} {proj[\"name\"]:35} | Branch: {proj[\"scm_branch\"]:15} | {proj[\"status\"]}')
"

# Forzar sync de todos los proyectos
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/projects/?page_size=100" \
    | python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin)['results']]" \
    | while read PROJECT_ID; do
        curl -s -u "${AWX_AUTH}" \
            -X POST \
            "${AWX_URL}/api/v2/projects/${PROJECT_ID}/update/" > /dev/null
        echo "Sync lanzado para proyecto ID: ${PROJECT_ID}"
    done

# Ver el grafo completo del inventario (grupos y hosts)
INV_ID=1
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/inventories/${INV_ID}/script/?hostvars=1&towervars=1" \
    | python3 -m json.tool | head -100
```

---

# 6.18 Resumen y Checklist del Módulo 6

## Lo que has aprendido

```
✅ Inventario como fuente de verdad
   → Estático: simple pero se desincroniza
   → Dinámico: siempre refleja la realidad
   → Smart/Constructed: vistas filtradas y grupos lógicos

✅ Inventarios estáticos bien estructurados
   → Jerarquía de grupos: entorno → rol → host
   → Variables en el nivel correcto: group_vars vs host_vars
   → Inventario como código en Git con revisión obligatoria

✅ Inventarios dinámicos con fuentes externas
   → AWS EC2: keyed_groups por tags, compose para variables
   → Scripts personalizados: formato --list / --host
   → Múltiples fuentes en un mismo inventario
   → Caché de inventario para resiliencia

✅ Smart Inventories
   → Filtros sobre inventarios existentes
   → Por variables: variables__environment=prod
   → Por facts cacheados: ansible_distribution=Ubuntu
   → Por grupos: groups__name=prod_web

✅ Constructed Inventories
   → Grupos dinámicos con lógica Jinja2
   → Variables derivadas con compose
   → Combinación de múltiples inventarios base

✅ Proyectos bien gestionados
   → Estructura de repo clara y consistente
   → ansible.cfg con fact caching y SSH optimizado
   → Proyectos separados por entorno con pins de versión
   → Rama main para dev/stage, tags fijos para prod

✅ Collections y roles como dependencias declaradas
   → requirements.yml con versiones fijadas
   → Instalación automática en el sync del proyecto
   → EEs como alternativa más robusta

✅ Pipeline de validación en CI
   → ansible-lint con perfil production
   → Syntax check de todos los playbooks
   → Validación del inventario estático
   → Verificación de requirements.yml con versiones fijadas
   → Notificación a AWX (sync del proyecto) si todo pasa

✅ Patrones avanzados
   → Inventario como código con PR y revisión
   → Jerarquía de variables sin ambigüedad
   → Separación de inventarios por criticidad
   → Hosts en mantenimiento con flag y exclusión automática
   → Webhook de inventario para actualizaciones en tiempo real
   → Vault para secrets en group_vars
   → Rotación de credenciales SCM por entorno
```

## Checklist de verificación

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

echo "=== CHECKLIST INVENTARIOS Y PROYECTOS AWX ==="
echo ""

echo "1. Inventarios disponibles"
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/inventories/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'   Total: {data[\"count\"]}')
for inv in data['results']:
    kind = inv.get('kind', 'standard') or 'standard'
    print(f'   ✅ {inv[\"name\"]:35} | {kind:12} | {inv[\"total_hosts\"]} hosts')
"

echo ""
echo "2. Fuentes de inventario y su estado"
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/inventory_sources/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for src in data['results']:
    icon = '✅' if src['status'] == 'successful' else '❌' if src['status'] == 'failed' else '⏳'
    last = str(src.get('last_updated', 'nunca'))[:19]
    print(f'   {icon} {src[\"name\"]:35} | {src[\"source\"]:15} | Último sync: {last}')
"

echo ""
echo "3. Proyectos y su estado"
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/projects/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for proj in data['results']:
    icon = '✅' if proj['status'] == 'successful' else '❌' if proj['status'] == 'failed' else '⏳'
    branch = proj.get('scm_branch', 'N/A')
    print(f'   {icon} {proj[\"name\"]:35} | Branch: {branch:15} | {proj[\"status\"]}')
"

echo ""
echo "4. Proyectos con Update on Launch activo"
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/projects/?scm_update_on_launch=true" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    print(f'   Proyectos con Update on Launch: {data[\"count\"]}')
    for proj in data['results']:
        print(f'   ✅ {proj[\"name\"]}')
else:
    print('   ⚠️  Ningún proyecto tiene Update on Launch activo')
"

echo ""
echo "5. Hosts por inventario"
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/inventories/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for inv in data['results']:
    total = inv['total_hosts']
    failed = inv.get('hosts_with_active_failures', 0)
    icon = '✅' if failed == 0 else '⚠️'
    print(f'   {icon} {inv[\"name\"]:35} | Total: {total:4} | Con fallos: {failed}')
"

echo ""
echo "6. Últimas sincronizaciones de proyectos"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/project_updates/?order_by=-id&page_size=5" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for update in data['results']:
    icon = '✅' if update['status'] == 'successful' else '❌'
    proj = update.get('summary_fields', {}).get('project', {})
    elapsed = f'{update[\"elapsed\"]:.0f}s' if update.get('elapsed') else 'N/A'
    print(f'   {icon} {proj.get(\"name\",\"N/A\"):35} | {update[\"status\"]:12} | {elapsed}')
"
```

## Preguntas de verificación conceptual

```
1. ¿Cuál es la diferencia entre un Smart Inventory y un Constructed Inventory?
   → Smart: filtra hosts existentes de un inventario base usando
     condiciones simples (subset del inventario).
     Constructed: crea NUEVOS GRUPOS dinámicos con lógica Jinja2
     compleja, puede combinar múltiples inventarios y crear
     variables derivadas con compose.

2. ¿Por qué es peligroso usar "Update on Launch" en un inventario de producción?
   → Porque un cambio inesperado en la fuente dinámica (un nuevo host
     que aparece, un grupo que cambia) puede ampliar el blast radius
     del job sin que el operador lo sepa. En producción, los cambios
     en el inventario deben ser deliberados y revisados.

3. ¿Qué hace la opción "Overwrite Variables" en una Inventory Source?
   → Hace que las variables de la fuente dinámica sobreescriban
     las variables que existen en AWX para ese host/grupo.
     Si está desactivado, las variables existentes en AWX
     se preservan y solo se añaden las nuevas.

4. ¿Por qué se recomienda usar tags de Git en lugar de ramas para producción?
   → Un tag es inmutable: apunta siempre al mismo commit.
     Una rama puede avanzar con nuevos commits.
     Si el proyecto de prod apunta a una rama, un commit
     accidental puede cambiar el código que se ejecuta en prod
     sin que nadie lo haya decidido explícitamente.

5. ¿Qué es keyed_groups en el plugin aws_ec2?
   → Es una configuración que crea grupos automáticamente
     a partir de atributos de las instancias EC2.
     Ejemplo: keyed_groups con key=tags.Role crea grupos
     como role_web, role_db, role_cache automáticamente
     para cada valor único del tag Role.

6. ¿Para qué sirve el módulo set_stats en relación con los inventarios?
   → Permite que un playbook publique datos (como el estado
     de los hosts) que otros nodos del Workflow pueden usar.
     También actualiza los facts del host en el fact cache,
     lo que puede afectar a los Smart Inventories que filtran
     por facts cacheados.
```

---

## 🔜 Siguiente: Módulo 7

En el Módulo 7 profundizamos en **operaciones avanzadas**: gestión de nodos de ejecución, escalado horizontal de AWX, backup y restauración, actualizaciones sin downtime, métricas con Prometheus/Grafana y configuración de alta disponibilidad.

> 🎯 **El principio de este módulo:** El inventario no es una lista de hosts que mantienes a mano: es una vista en tiempo real de tu infraestructura. Los proyectos no son carpetas de ficheros: son versiones controladas de tu automatización. Cuando ambos están bien diseñados, AWX siempre sabe exactamente sobre qué ejecutar y con qué código.
