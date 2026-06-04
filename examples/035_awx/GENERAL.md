# 🚀 Curso Completo de Ansible AWX
### De cero a producción · 4-6 horas · En español

---

## 🗺️ Mapa del Curso

| # | Módulo | Duración | Tipo |
|---|--------|----------|------|
| 1 | Fundamentos y arquitectura | 45 min | Teoría + Lab |
| 2 | Inventarios, Credenciales y Proyectos | 60 min | Lab intensivo |
| 3 | Job Templates y Surveys | 45 min | Lab intensivo |
| 4 | Workflows, Aprobaciones y Notificaciones | 60 min | Lab + diseño |
| 5 | RBAC y Multi-tenancy | 30 min | Configuración |
| 6 | CI/CD, Testing y Linting | 45 min | Lab + integración |
| 7 | Escalado, Seguridad y Operaciones | 45 min | Lab + producción |

**Prerrequisitos:** Linux básico, Git, YAML, nociones de Ansible playbooks.

---

# 📘 MÓDULO 1 — Fundamentos y Arquitectura AWX

*Antes de tocar la UI, necesitas el modelo mental correcto. Todo encaja mejor cuando entiendes por qué existe cada pieza.*

---

## 🔍 AWX vs Ansible Tower vs AAP

```
AWX  ──────────────►  Ansible Tower  ──────────────►  AAP Controller
(open source, upstream)   (Red Hat, soporte comercial)   (plataforma completa)
```

- **AWX** = laboratorio de features, gratuito, comunidad
- **Tower/Controller** = distribución endurecida con SLA y soporte
- Misma base de código; Tower/AAP añade certificación, lifecycle y soporte enterprise

---

## 🏗️ Arquitectura AWX — El diagrama mental

```
┌─────────────────────────────────────────────────────┐
│                    USUARIO / CI                     │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP/API
┌──────────────────────▼──────────────────────────────┐
│              WEB / API (Django + DRF)               │
│         UI React · REST API · Webhooks              │
└──────┬───────────────────────────────┬──────────────┘
       │                               │
┌──────▼──────┐                ┌───────▼──────┐
│   TASK      │                │  SCHEDULER   │
│  (Celery)   │                │  (cron/SCM)  │
└──────┬──────┘                └──────────────┘
       │ encola trabajos
┌──────▼──────┐    ┌──────────────────────────────┐
│    REDIS    │    │   EXECUTION ENVIRONMENT (EE) │
│  (broker)   │    │  Container: ansible-core +   │
└─────────────┘    │  collections + dependencias  │
                   └──────────────┬───────────────┘
┌──────────────┐                  │ SSH / WinRM
│  POSTGRESQL  │         ┌────────▼────────┐
│  (config +   │         │   HOSTS TARGET  │
│  job history)│         │  web1, db1...   │
└──────────────┘         └─────────────────┘
```

**Flujo de ejecución:**
1. Pulsas "Launch" (o webhook/schedule lo dispara)
2. Scheduler encola → Task service arranca un worker con el EE correcto
3. Worker usa Credentials + Inventory para conectar a los hosts
4. Resultados fluyen por Redis → Web/API → persisten en Postgres

---

## 🧩 Objetos Core de AWX

```
Organization
  ├── Teams / Users
  ├── Credentials  (SSH, Vault, Cloud, Custom)
  ├── Projects     (Git repo → playbooks)
  ├── Inventories  (hosts: estático, YAML, dinámico)
  └── Templates
        ├── Job Template      → un playbook concreto
        └── Workflow Template → pipeline de templates
```

> 💡 **Regla de oro:** Diseña de afuera hacia adentro. Empieza por el Job Template que quieres ejecutar y asegúrate de que Inventory, Credentials, Project y EE estén listos.

---

## 🧪 LAB 1A — Instalar AWX con K3s en Ubuntu 22.04/24.04

*Este es el método recomendado para entornos reales. K3s es Kubernetes ligero, perfecto para un solo nodo.*

### Paso 1 — Instalar K3s

```bash
# En Ubuntu 22.04 o 24.04
curl -sfL https://get.k3s.io | sh -

# Verificar que el cluster está listo
sudo k3s kubectl get nodes
# NAME       STATUS   ROLES                  AGE   VERSION
# ubuntu     Ready    control-plane,master   30s   v1.29.x
```

### Paso 2 — Instalar el AWX Operator

```bash
# Crear namespace
sudo k3s kubectl create namespace awx

# Instalar el operador (ajusta la versión a la última disponible)
sudo k3s kubectl apply -n awx -f \
  https://raw.githubusercontent.com/ansible/awx-operator/2.19.1/deploy/awx-operator.yaml

# Esperar a que el operador esté listo
sudo k3s kubectl get pods -n awx -w
# awx-operator-controller-manager-xxxxx   2/2   Running   0   60s
```

### Paso 3 — Crear la instancia AWX

```yaml
# awx-instance.yaml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: nodeport
  nodeport_port: 30080
  admin_user: admin
  admin_password_secret: awx-admin-password
```

```bash
# Crear el secret con la contraseña de admin
sudo k3s kubectl create secret generic awx-admin-password \
  -n awx \
  --from-literal=password='TuPasswordSegura123!'

# Aplicar la instancia
sudo k3s kubectl apply -f awx-instance.yaml

# Seguir el despliegue (tarda 3-5 minutos)
sudo k3s kubectl get pods -n awx -w
```

### Paso 4 — Acceder a AWX

```bash
# Obtener la IP del nodo
hostname -I | awk '{print $1}'

# Acceder en el navegador
# http://<IP_NODO>:30080
# Usuario: admin
# Password: TuPasswordSegura123!
```

---

## 🧪 LAB 1B — Primera configuración: Organización, Equipo y Proyecto

```bash
# Verificar que AWX responde a la API
curl -s http://localhost:30080/api/v2/ping/ | python3 -m json.tool
# {
#   "ha": false,
#   "version": "24.x.x",
#   "active_node": "awx-task-xxx",
#   "install_uuid": "..."
# }
```

**En la UI (http://\<IP\>:30080):**

1. **Organizations → Add**
   - Name: `MiEmpresa`
   - Description: `Organización principal de automatización`

2. **Teams → Add**
   - Name: `Platform`
   - Organization: `MiEmpresa`

3. **Users → Add**
   - Username: `operador1`
   - Password: `...`
   - Team: `Platform`

---

# 🗂️ MÓDULO 2 — Inventarios, Credenciales y Proyectos

*Estos son los bloques de construcción que AWX usa en cada ejecución. Bien configurados, el resto fluye solo.*

---

## 🔍 Tipos de Inventario

| Tipo | Cuándo usarlo | Ejemplo |
|------|--------------|---------|
| **Estático (UI)** | Labs, entornos pequeños conocidos | `web1, db1, app1` |
| **YAML en SCM** | On-prem versionado en Git | `inventory/hosts.yml` |
| **Dinámico (plugin)** | Cloud: AWS, Azure, GCP, VMware | EC2 con filtros por tags |

---

## 🧪 LAB 2A — Inventario Estático con Grupos dev/stage/prod

**En la UI:**

```
Inventories → Add → Inventory
  Name: Env Inventory
  Organization: MiEmpresa

→ Groups → Add: dev
→ Groups → Add: stage  
→ Groups → Add: prod

→ dev → Hosts → Add:
  Hostname: dev-web1   (ansible_host=192.168.1.10)
  Hostname: dev-db1    (ansible_host=192.168.1.11)

→ prod → Hosts → Add:
  Hostname: prod-web1  (ansible_host=10.0.1.10)
```

**Variables de grupo (dev):**
```yaml
# En "Variables" del grupo dev
env: dev
app_port: 8080
debug_mode: true
```

**Variables de grupo (prod):**
```yaml
env: prod
app_port: 80
debug_mode: false
```

---

## 🧪 LAB 2B — Credenciales SSH y Vault

### Credencial SSH (Machine)

```
Credentials → Add
  Name: Platform SSH
  Type: Machine
  Username: ansible
  SSH Private Key: [pegar contenido de ~/.ssh/id_rsa]
  Privilege Escalation Method: sudo
```

### Credencial Vault

```
Credentials → Add
  Name: Vault Default
  Type: Ansible Vault
  Vault Password: MiPasswordVault123
  Vault Identifier: default
```

### Ejemplo de uso en playbook con Vault

```yaml
# vars/secrets.yml (encriptado con ansible-vault)
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38653061386665623835303763...

# playbook que usa el secret
- name: Configurar base de datos
  hosts: "{{ target_group }}"
  vars_files:
    - vars/secrets.yml
  tasks:
    - name: Crear config de BD
      template:
        src: db.conf.j2
        dest: /etc/app/db.conf
      vars:
        password: "{{ db_password }}"
```

---

## 🧪 LAB 2C — Inventario Dinámico AWS EC2

```
Inventories → Add → Inventory
  Name: AWS Inventory
  Organization: MiEmpresa

→ Sources → Add
  Name: EC2 Production
  Source: Amazon EC2
  Credential: [crear credencial AWS primero]
  Regions: eu-west-1
  
  Filters:
    Host Filter: tag:AnsibleManaged=true
    Group By: tag:Environment
    
  Update Options:
    ✅ Overwrite
    ✅ Overwrite Vars
    ✅ Update on Launch
    Cache Timeout: 300
```

**Credencial AWS (mínimos permisos IAM):**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeTags"
    ],
    "Resource": "*"
  }]
}
```

---

## 🧪 LAB 2D — Proyecto SCM con Webhook

```
Projects → Add
  Name: Platform Playbooks
  Organization: MiEmpresa
  SCM Type: Git
  SCM URL: https://github.com/tuorg/ansible-playbooks.git
  SCM Branch: main
  
  Options:
    ✅ Clean
    ✅ Delete on Update
    ✅ Update Revision on Launch (para dev)
  
  Credential: [tu credencial SCM si el repo es privado]
```

**Configurar Webhook en GitHub:**
```
GitHub → Repo → Settings → Webhooks → Add webhook
  Payload URL: http://<AWX_IP>:30080/api/v2/projects/<ID>/update/
  Content type: application/json
  Secret: [copiar desde AWX Project → Webhook Key]
  Events: Just the push event
```

**Estructura recomendada del repo:**
```
ansible-playbooks/
├── playbooks/
│   ├── deploy_web.yml
│   ├── configure_db.yml
│   └── site.yml
├── inventory/
│   ├── dev/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── prod/
│       ├── hosts.yml
│       └── group_vars/
├── roles/
│   └── webapp/
├── collections/
│   └── requirements.yml
└── .ansible-lint
```

---

# ▶️ MÓDULO 3 — Job Templates y Surveys

*Aquí es donde la automatización se vuelve self-service: cualquier persona del equipo puede lanzar un deploy sin saber Ansible.*

---

## 🔍 Job Template vs Workflow Template

```
Job Template ──────► ejecuta UN playbook
                     con inventory + credentials + EE

Workflow Template ──► encadena VARIOS templates
                     con lógica condicional y aprobaciones
```

---

## 🧪 LAB 3A — Job Template para Deploy de Web App

```
Templates → Add → Job Template
  Name: Web App Deploy
  Job Type: Run
  Inventory: Env Inventory
  Project: Platform Playbooks
  Playbook: playbooks/deploy_web.yml
  Credentials: Platform SSH, Vault Default
  Execution Environment: Default EE
  
  Options:
    ✅ Enable Privilege Escalation
    ✅ Enable Fact Cache
    Verbosity: 1 (Normal)
    Forks: 10
```

**El playbook `deploy_web.yml`:**
```yaml
---
- name: Deploy Web Application
  hosts: "{{ target_group | default('dev') }}"
  become: true
  
  vars:
    app_version: "{{ app_version | default('v1.0.0') }}"
    app_env: "{{ environment | default('dev') }}"
    
  tasks:
    - name: Instalar Nginx
      ansible.builtin.package:
        name: nginx
        state: present
      tags: [packages]

    - name: Crear directorio de la app
      ansible.builtin.file:
        path: "/var/www/{{ app_env }}"
        state: directory
        owner: www-data
        mode: '0755'
      tags: [config]

    - name: Desplegar configuración Nginx
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/sites-available/webapp
      notify: Reload Nginx
      tags: [config, deploy]

    - name: Desplegar aplicación versión {{ app_version }}
      ansible.builtin.copy:
        content: |
          # App version: {{ app_version }}
          # Environment: {{ app_env }}
          # Deployed: {{ ansible_date_time.iso8601 }}
        dest: "/var/www/{{ app_env }}/version.txt"
      tags: [deploy]

  handlers:
    - name: Reload Nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

---

## 🧪 LAB 3B — Survey para Inputs Seguros

```
Job Template: Web App Deploy → Survey → Add Questions
```

**Pregunta 1 — Versión de la app:**
```
Question Name: Versión de la aplicación
Answer Variable Name: app_version
Answer Type: Text
Default Answer: v1.0.0
Required: ✅
Min Length: 5
Max Length: 20
```

**Pregunta 2 — Entorno:**
```
Question Name: Entorno de despliegue
Answer Variable Name: environment
Answer Type: Multiple Choice (single select)
Choices:
  dev
  stage
  prod
Default Answer: dev
Required: ✅
```

**Pregunta 3 — Ticket de cambio:**
```
Question Name: Ticket de cambio (JIRA/ServiceNow)
Answer Variable Name: change_ticket
Answer Type: Text
Default Answer: (vacío)
Required: ❌
```

> 💡 **Por qué Surveys y no Extra Vars libres:** Los Surveys validan tipos, longitudes y opciones. Un operador no puede meter `environment: ../../../../etc/passwd`. Las Extra Vars libres no tienen esa protección.

---

## 🧪 LAB 3C — Tags, Skip-tags y Limit

**Lanzar solo la parte de config en dev:**
```
Launch → Web App Deploy
  Limit: dev
  Job Tags: config
  Skip Tags: packages
```

**Patrón de despliegue gradual (canary):**
```bash
# Paso 1: Solo un host de prod
Limit: prod-web1
Tags: deploy

# Paso 2: Si va bien, el resto
Limit: prod
Tags: deploy
```

**Ejemplo de tags en roles:**
```yaml
# roles/webapp/tasks/main.yml
- name: Instalar dependencias
  ansible.builtin.package:
    name: "{{ item }}"
    state: present
  loop: "{{ webapp_packages }}"
  tags: [packages, install]

- name: Configurar aplicación
  ansible.builtin.template:
    src: app.conf.j2
    dest: /etc/webapp/app.conf
  tags: [config]

- name: Reiniciar servicio
  ansible.builtin.service:
    name: webapp
    state: restarted
  tags: [deploy, restart]
```

---

## 🧪 LAB 3D — Execution Environment Personalizado

```bash
# requirements.yml para el EE
---
collections:
  - name: community.general
    version: ">=9.3.0,<10.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.mysql
    version: ">=3.8.0"

python_requirements:
  - boto3>=1.34.0
  - botocore>=1.34.0
```

```dockerfile
# Dockerfile del EE personalizado
ARG EE_BASE_IMAGE=quay.io/ansible/awx-ee:latest
FROM ${EE_BASE_IMAGE}

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
    && pip install boto3 botocore
```

```bash
# Build y push
docker build -t registry.ejemplo.com/ee/webapp-ee:1.2.0 .
docker push registry.ejemplo.com/ee/webapp-ee:1.2.0
```

```
AWX → Execution Environments → Add
  Name: EE WebApp 1.2.0
  Image: registry.ejemplo.com/ee/webapp-ee:1.2.0
  Pull Policy: Always
```

---

# 🔗 MÓDULO 4 — Workflows, Aprobaciones y Notificaciones

*Un Workflow convierte pasos manuales en un pipeline gobernado. Es la diferencia entre "alguien ejecutó algo" y "el proceso de cambio fue seguido correctamente".*

---

## 🔍 Anatomía de un Workflow

```
                    ┌─────────────────┐
                    │  Provision Infra │  (nodo raíz)
                    └────────┬────────┘
                    success  │  failure
              ┌──────────────┼──────────────┐
              ▼              │              ▼
    ┌──────────────┐         │      ┌──────────────┐
    │ Configure App│         │      │   ROLLBACK   │
    └──────┬───────┘         │      └──────────────┘
    success│  failure────────┘
           ▼
    ┌──────────────┐
    │  Run Tests   │
    └──────┬───────┘
    success│  failure──────► ROLLBACK
           ▼
    ┌──────────────┐
    │  APROBACIÓN  │  ← nodo humano
    │  (2 horas)   │
    └──────┬───────┘
  approved │  denied──────► ROLLBACK
           ▼
    ┌──────────────┐
    │ Deploy Prod  │
    └──────┬───────┘
           │ always
           ▼
    ┌──────────────┐
    │ Notificación │  (siempre se ejecuta)
    └──────────────┘
```

---

## 🧪 LAB 4A — Crear el Workflow Completo

```
Templates → Add → Workflow Template
  Name: App Delivery Pipeline
  Organization: MiEmpresa
  
  Survey:
    - release_tag (text, required)
    - environment (choice: dev/stage/prod)
    - change_ticket (text, optional)
```

**Construir el grafo (Visualizer):**

```
1. Click "Start" → Add Node
   Type: Job Template
   Template: Provision Infra
   
2. Desde Provision (success) → Add Node
   Template: Configure App
   
3. Desde Configure (failure) → Add Node
   Template: Rollback App
   
4. Desde Configure (success) → Add Node
   Template: Run Tests
   
5. Desde Run Tests (failure) → conectar a Rollback App
   
6. Desde Run Tests (success) → Add Node
   Type: Approval
   Name: "Go/No-Go para Producción"
   Description: "Confirma que el ticket {{ change_ticket }} está aprobado"
   Timeout: 7200 (2 horas)
   
7. Desde Approval (approved) → Add Node
   Template: Deploy to Prod
   
8. Desde Approval (denied) → conectar a Rollback App

9. Desde Deploy (always) → Add Node
   Template: Post-Deploy Notifications
```

---

## 🧪 LAB 4B — Nodo de Aprobación

```
En el Workflow Visualizer → Add Node
  Type: Approval
  Name: Go/No-Go para Producción
  Description: |
    Antes de aprobar, verifica:
    ✅ Tests pasaron en stage
    ✅ Ticket {{ change_ticket }} aprobado en JIRA
    ✅ Ventana de cambio activa
    ✅ Equipo de guardia notificado
  Timeout: 7200
```

**Asignar permisos de aprobación:**
```
Workflow Template → Access → Add
  Team: Change Advisory Board
  Role: Approve
```

---

## 🧪 LAB 4C — Notificaciones Slack

```
Notifications → Add
  Name: Slack - App Pipeline
  Type: Slack
  Slack Token: xoxb-tu-token-de-slack
  Destination Channel: #deployments
```

**Mensaje personalizado de éxito:**
```
✅ *{{ workflow_job_template_name }}* completado
• Entorno: {{ extra_vars.environment }}
• Release: {{ extra_vars.release_tag }}
• Ticket: {{ extra_vars.change_ticket | default('N/A') }}
• Duración: {{ elapsed }}s
• 🔗 <{{ url }}|Ver detalles>
```

**Mensaje de fallo:**
```
❌ *FALLO* en {{ workflow_job_template_name }}
• Nodo fallido: {{ job_template_name }}
• Entorno: {{ extra_vars.environment }}
• 🔗 <{{ url }}|Investigar ahora>
• CC: @oncall-infra
```

```
Workflow Template → Notifications
  On Success: Slack - App Pipeline
  On Failure: Slack - App Pipeline
  On Approval Pending: Slack - CAB Channel
```

---

## 🧪 LAB 4D — Trigger desde CI (GitHub Actions)

```yaml
# .github/workflows/deploy.yml
name: Deploy via AWX

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger AWX Workflow
        env:
          AWX_URL: ${{ secrets.AWX_URL }}
          AWX_TOKEN: ${{ secrets.AWX_TOKEN }}
          WFT_ID: ${{ secrets.AWX_WORKFLOW_ID }}
        run: |
          RESPONSE=$(curl -sS -w "\n%{http_code}" \
            -X POST "${AWX_URL}/api/v2/workflow_job_templates/${WFT_ID}/launch/" \
            -H "Authorization: Bearer ${AWX_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
              "extra_vars": {
                "release_tag": "'"${GITHUB_SHA::7}"'",
                "environment": "stage",
                "change_ticket": "AUTO-'"${GITHUB_RUN_NUMBER}"'"
              }
            }')
          
          HTTP_CODE=$(echo "$RESPONSE" | tail -1)
          BODY=$(echo "$RESPONSE" | head -1)
          
          if [ "$HTTP_CODE" != "201" ]; then
            echo "❌ Error lanzando workflow: $HTTP_CODE"
            echo "$BODY"
            exit 1
          fi
          
          JOB_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
          echo "✅ Workflow lanzado: Job ID $JOB_ID"
          echo "🔗 ${AWX_URL}/#/jobs/workflow/${JOB_ID}"
```

---

# 🔐 MÓDULO 5 — RBAC y Multi-tenancy

*La seguridad en AWX no es un módulo separado: es cómo diseñas los permisos desde el día uno.*

---

## 🔍 Matriz de Roles AWX

| Objeto | Admin | Use | Execute | Update | Read |
|--------|-------|-----|---------|--------|------|
| **Organization** | Control total | — | — | — | Ver todo |
| **Inventory** | Gestionar | Usar en JT | — | Sincronizar | Ver hosts |
| **Project** | Gestionar | Usar en JT | — | Sincronizar SCM | Ver |
| **Job Template** | Gestionar | — | Lanzar | — | Ver |
| **Credentials** | Gestionar | Usar en JT | — | — | Ver (enmascarado) |
| **Workflow** | Gestionar | — | Lanzar | — | Aprobar |

---

## 🧪 LAB 5A — Crear Equipos con Roles Diferenciados

```
Teams → Add: Platform
  Organization: MiEmpresa
  Roles: Organization Admin

Teams → Add: AppOps  
  Organization: MiEmpresa
  Roles: Organization Member

Teams → Add: SecOps
  Organization: MiEmpresa
  Roles: Organization Member

Teams → Add: Auditores
  Organization: MiEmpresa
  Roles: Organization Auditor
```

---

## 🧪 LAB 5B — Delegar Ejecución sin Exponer Credenciales

**El patrón correcto:**
```
Platform crea:
  ├── Credencial SSH (Platform Admin)
  ├── Proyecto (Platform Admin)
  └── Job Template (Platform Admin)
        └── Credencial SSH embebida en el template
              └── AppOps: Execute en el template
                  (NO Use en la credencial)
```

```
Job Template: Web App Deploy → Access → Add
  Team: AppOps
  Role: Execute    ← pueden lanzar
  Role: Read       ← pueden ver logs

Job Template: Web App Deploy → Access → Add  
  Team: Auditores
  Role: Read       ← solo pueden ver, no lanzar
```

**Verificación:** Loguéate como usuario de AppOps:
- ✅ Puede ver y lanzar el template
- ✅ Puede ver logs de ejecución
- ❌ No puede ver la clave SSH
- ❌ No puede editar el template
- ❌ No puede cambiar las credenciales

---

## 🧪 LAB 5C — Separación por Entornos con Instance Groups

```
Administration → Instance Groups → Add
  Name: ig-dev
  Policy Instance Minimum: 1

Administration → Instance Groups → Add
  Name: ig-prod
  Policy Instance Minimum: 2
  Policy Instance Percentage: 50

# Asignar templates a grupos
Job Template: Web App Deploy (Dev) → Instance Group: ig-dev
Job Template: Web App Deploy (Prod) → Instance Group: ig-prod
```

---

# 🧪 MÓDULO 6 — CI/CD, Testing y Linting

*La calidad del código Ansible se valida antes de que AWX lo vea. Esto evita el 80% de los problemas en producción.*

---

## 🧪 LAB 6A — Configurar ansible-lint

```bash
# Instalar
pip install ansible-lint

# .ansible-lint en la raíz del repo
---
exclude_paths:
  - .venv/
  - collections/ansible_collections/*/tests/
  
skip_list: []
warn_list:
  - experimental

strict: true
```

**Errores comunes y cómo corregirlos:**

```yaml
# ❌ MAL - usar yes/no
- name: Habilitar servicio
  service:
    name: nginx
    enabled: yes   # ansible-lint: yaml[truthy]

# ✅ BIEN
- name: Habilitar servicio
  ansible.builtin.service:
    name: nginx
    enabled: true
```

```yaml
# ❌ MAL - command en vez de módulo
- name: Instalar nginx
  command: apt-get install -y nginx   # ansible-lint: command-instead-of-module

# ✅ BIEN
- name: Instalar nginx
  ansible.builtin.package:
    name: nginx
    state: present
```

```yaml
# ❌ MAL - versión no fijada
- name: Instalar Python
  package:
    name: python3
    state: latest   # ansible-lint: package-latest

# ✅ BIEN
- name: Instalar Python
  package:
    name: python3
    state: present
```

---

## 🧪 LAB 6B — Pipeline CI/CD Completo

```yaml
# .github/workflows/ci.yml
name: CI/CD Ansible AWX

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: 🔍 Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          
      - name: Instalar dependencias
        run: |
          pip install ansible-core ansible-lint
          
      - name: Ejecutar ansible-lint
        run: ansible-lint --show-relpath

  test:
    name: 🧪 Molecule Tests
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          
      - name: Instalar Molecule
        run: |
          pip install ansible-core molecule molecule-plugins[docker]
          
      - name: Ejecutar tests
        run: |
          cd roles/webapp
          molecule test

  deploy-stage:
    name: 🚀 Deploy Stage
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Trigger AWX - Stage
        run: |
          curl -sS -X POST \
            "${{ secrets.AWX_URL }}/api/v2/workflow_job_templates/${{ secrets.WFT_ID }}/launch/" \
            -H "Authorization: Bearer ${{ secrets.AWX_TOKEN }}" \
            -H "Content-Type: application/json" \
            -d '{
              "extra_vars": {
                "release_tag": "'"${GITHUB_SHA::7}"'",
                "environment": "stage",
                "change_ticket": "CI-'"${GITHUB_RUN_NUMBER}"'"
              }
            }'
```

---

## 🔍 Estrategia de Promoción Git → AWX

```
develop branch ──► AWX Project: Dev  (branch: develop)
                   Auto-deploy en cada push
                   
main branch ──────► AWX Project: Stage (branch: main)
                    Deploy tras CI verde
                    
tag v1.6.3 ───────► AWX Project: Prod  (tag: v1.6.3)
                    Deploy solo con aprobación manual
                    Tag inmutable = reproducibilidad garantizada
```

```bash
# Crear tag de release
git tag -a v1.6.3 -m "Release 1.6.3: feature X y bugfix Y"
git push origin v1.6.3

# En AWX: actualizar el Project de Prod al nuevo tag
Projects → Platform Playbooks (Prod) → Edit
  SCM Branch/Tag/Commit: v1.6.3
  → Save → Sync
```

---

# 📈 MÓDULO 7 — Escalado, Seguridad y Operaciones

*Los módulos anteriores te dan AWX funcionando. Este módulo te da AWX en producción.*

---

## 🔍 Escalado: Los 3 Ejes

```
Eje 1: FORKS (paralelismo por job)
  Más forks = más hosts en paralelo
  Límite: capacidad SSH del target y RAM del execution node
  Recomendación: empieza en 10-15, mide, ajusta

Eje 2: JOBS CONCURRENTES (paralelismo de jobs)
  Controlado por capacidad del Instance Group
  Más instancias = más jobs simultáneos

Eje 3: FACT CACHE (velocidad de ejecución)
  Sin cache: cada job ejecuta setup (gather_facts) en todos los hosts
  Con Redis: segunda ejecución usa facts cacheados → 20-40% más rápido
```

---

## 🧪 LAB 7A — Fact Cache con Redis

```ini
# En tu Execution Environment o ansible.cfg del proyecto
[defaults]
fact_caching = redis
fact_caching_connection = redis://redis.ejemplo.com:6379/0
fact_caching_timeout = 86400  # 24 horas

# En tus playbooks: reusar facts sin gather_facts
- name: Deploy usando facts cacheados
  hosts: webservers
  gather_facts: false   # ← usa el cache
  tasks:
    - name: Mostrar OS desde cache
      debug:
        msg: "OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"
```

---

## 🔐 Seguridad: HashiCorp Vault Integration

```
Credentials → Add
  Name: HashiCorp Vault AppRole
  Type: HashiCorp Vault Secret Lookup
  Server URL: https://vault.ejemplo.com
  Token: [token de AWX con permisos de lectura]
  API Version: v2
```

**Usar en playbook:**
```yaml
- name: Obtener credenciales de BD desde Vault
  hosts: dbservers
  vars:
    db_creds: "{{ lookup('community.hashi_vault.hashi_vault',
                  'secret=kv/data/prod/database
                   url=https://vault.ejemplo.com
                   auth_method=approle
                   role_id=mi-role-id
                   secret_id=mi-secret-id') }}"
  tasks:
    - name: Configurar conexión BD
      template:
        src: database.conf.j2
        dest: /etc/app/database.conf
      vars:
        db_host: "{{ db_creds.host }}"
        db_pass: "{{ db_creds.password }}"
```

---

## 🛠️ Operaciones: Backup y Restore

```bash
# Backup de PostgreSQL (programar con cron o AWX Schedule)
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="awx_backup_${DATE}.sql.gz"

# Dump comprimido
kubectl exec -n awx awx-postgres-0 -- \
  pg_dump -U awx awx | gzip > "/backups/${BACKUP_FILE}"

# Cifrar con GPG (opcional pero recomendado)
gpg --recipient ops@empresa.com --encrypt "/backups/${BACKUP_FILE}"

# Subir a S3
aws s3 cp "/backups/${BACKUP_FILE}.gpg" \
  "s3://mi-bucket-backups/awx/${BACKUP_FILE}.gpg"

echo "✅ Backup completado: ${BACKUP_FILE}"
```

```bash
# Restore (en staging para verificar)
# 1. Descifrar y descomprimir
gpg --decrypt awx_backup_20260604.sql.gz.gpg | gunzip > awx_backup.sql

# 2. Restaurar en Postgres
kubectl exec -i -n awx awx-postgres-0 -- \
  psql -U awx awx < awx_backup.sql

# 3. Reiniciar AWX
kubectl rollout restart deployment/awx-web -n awx
kubectl rollout restart deployment/awx-task -n awx

# 4. Verificar
curl -s http://awx-staging:30080/api/v2/ping/
```

---

## 📊 Monitorización con Prometheus + Grafana

```yaml
# prometheus-scrape-config.yml
scrape_configs:
  - job_name: 'awx'
    static_configs:
      - targets: ['awx-service:8080']
    metrics_path: '/api/v2/metrics'
    bearer_token: 'tu-token-de-admin'
    
  - job_name: 'postgres-awx'
    static_configs:
      - targets: ['postgres-exporter:9187']
```

**Métricas clave para el dashboard Grafana:**
```
# Jobs en cola
awx_pending_jobs_total

# Jobs ejecutándose ahora
awx_running_jobs_total

# Tasa de fallos (últimas 24h)
rate(awx_failed_jobs_total[24h])

# Duración P95 de jobs
histogram_quantile(0.95, awx_job_duration_seconds_bucket)

# Capacidad de Instance Groups
awx_instance_capacity_total - awx_instance_consumed_capacity_total
```

---

# 🧩 PROYECTO FINAL — Pipeline Completo Multi-tier

*Integra todo lo aprendido en un escenario real: desplegar una app de 3 capas (DB + API + Web).*

---

## 📋 Descripción del Proyecto

```
OBJETIVO: Provisionar, configurar y desplegar una app multi-tier
con gobernanza completa de cambios.

ARQUITECTURA:
  ┌─────────┐    ┌─────────┐    ┌─────────┐
  │  MySQL  │◄───│   API   │◄───│  Nginx  │
  │  :3306  │    │  :8080  │    │   :80   │
  └─────────┘    └─────────┘    └─────────┘
  
REQUISITOS:
  ✅ Inventario dinámico (AWS EC2 con tags)
  ✅ Survey con versión, entorno y ticket
  ✅ Credenciales separadas por capa
  ✅ Workflow con gates de test y aprobación
  ✅ Notificaciones Slack
  ✅ CI/CD desde GitHub Actions
  ✅ Rollback automático en fallo
```

---

## 🗺️ Workflow del Proyecto Final

```
GitHub push → CI lint+test → AWX Webhook
                                  │
                    ┌─────────────▼──────────────┐
                    │     SURVEY al lanzar        │
                    │  release_tag, environment,  │
                    │  change_ticket              │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │  1. Provision Infra (EC2)   │
                    └──────┬──────────────────────┘
                    success│         failure
                           │              └──► Notify Failure
                    ┌──────▼──────┐
                    │ 2. Config DB│
                    └──────┬──────┘
                    success│         failure
                           │              └──► Rollback DB
                    ┌──────▼──────┐
                    │ 3. Deploy   │
                    │    API      │
                    └──────┬──────┘
                    success│         failure
                           │              └──► Rollback API
                    ┌──────▼──────┐
                    │ 4. Deploy   │
                    │    Web      │
                    └──────┬──────┘
                    success│         failure
                           │              └──► Rollback Web
                    ┌──────▼──────┐
                    │ 5. Run      │
                    │    Tests    │
                    └──────┬──────┘
                    success│         failure
                           │              └──► Full Rollback
                    ┌──────▼──────┐
                    │ 6. APPROVAL │  ← solo si env=prod
                    │   (CAB)     │
                    └──────┬──────┘
                  approved │         denied
                           │              └──► Cancel & Notify
                    ┌──────▼──────┐
                    │ 7. Promote  │
                    │   to Prod   │
                    └──────┬──────┘
                           │ always
                    ┌──────▼──────┐
                    │ 8. Notify   │
                    │   Slack     │
                    └─────────────┘
```

---

## 📦 Entregables del Proyecto

```
proyecto-awx/
├── README.md                    # Runbook completo
├── playbooks/
│   ├── provision_infra.yml
│   ├── configure_db.yml
│   ├── deploy_api.yml
│   ├── deploy_web.yml
│   ├── run_tests.yml
│   └── rollback.yml
├── inventory/
│   ├── aws_ec2.yml              # Plugin dinámico
│   └── group_vars/
│       ├── all.yml
│       ├── db_servers.yml
│       └── web_servers.yml
├── roles/
│   ├── mysql/
│   ├── api_server/
│   └── nginx/
├── collections/
│   └── requirements.yml
├── .ansible-lint
├── .github/
│   └── workflows/
│       └── ci.yml
└── awx-export/
    ├── organizations.yml
    ├── inventories.yml
    ├── credential_types.yml
    ├── job_templates.yml
    └── workflow_templates.yml
```

---

# 🧯 Guía de Troubleshooting Rápido

| Síntoma | Causa más probable | Solución |
|---------|-------------------|----------|
| SCM sync falla | Clave SSH incorrecta o rama inexistente | Verificar credencial SCM y nombre de rama |
| Job en "waiting" | Instance group sin capacidad o aprobación pendiente | Revisar capacidad y aprobaciones pendientes |
| Host unreachable | Ruta de red o credencial incorrecta | Confirmar `ansible_host`, usuario y firewall |
| Vault error | Vault ID no coincide | Asegurar que el EE tiene `ansible-vault` y el ID es correcto |
| Module not found | EE sin la colección necesaria | Reconstruir EE con la colección requerida |
| Runs lentos | `gather_facts` sin cache, forks bajos | Activar Redis cache, aumentar forks gradualmente |
| Webhook 403 | Token expirado o RBAC incorrecto | Rotar token, verificar permisos de Execute |
| Survey var no llega | Nombre de variable no coincide | Verificar que `Answer Variable Name` = nombre en playbook |

---

# ✅ Resumen: Lo Que Sabes Hacer Ahora

```
✅ Instalar AWX con K3s en Ubuntu 22.04/24.04
✅ Entender la arquitectura completa (Web/Task/Redis/Postgres/EE)
✅ Crear inventarios estáticos y dinámicos (AWS EC2)
✅ Gestionar credenciales SSH, Vault y Cloud de forma segura
✅ Sincronizar proyectos desde Git con webhooks
✅ Crear Job Templates parametrizados con Surveys validados
✅ Usar tags, limits y forks para ejecuciones quirúrgicas
✅ Diseñar Workflows con lógica condicional y rollback
✅ Implementar aprobaciones humanas con auditoría completa
✅ Configurar notificaciones Slack con contexto de negocio
✅ Integrar AWX en pipelines CI/CD (GitHub Actions)
✅ Aplicar RBAC con mínimo privilegio por equipo
✅ Escalar con Instance Groups y Redis Fact Cache
✅ Integrar HashiCorp Vault para secretos dinámicos
✅ Hacer backups, monitorizar y actualizar AWX en producción
```