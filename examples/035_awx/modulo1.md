# 📘 MÓDULO 1 — Fundamentos y Arquitectura AWX
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 1.1 | ¿Qué es AWX? Historia y contexto |
| 1.2 | AWX vs Ansible Tower vs AAP |
| 1.3 | Arquitectura interna: cada componente explicado |
| 1.4 | Flujo de ejecución de un job |
| 1.5 | Objetos core de AWX y sus relaciones |
| 1.6 | LAB — Instalar AWX con K3s en Ubuntu 22.04/24.04 |
| 1.7 | LAB — Primera configuración: Organización, Equipo y Proyecto |
| 1.8 | LAB — Primer Job Template y ejecución end-to-end |
| 1.9 | Troubleshooting del módulo |
| 1.10 | Resumen y checklist |

**Duración estimada:** 45-60 minutos  
**Tipo:** Teoría + Labs guiados  
**Prerrequisitos:** Linux básico, Git, YAML, nociones de Ansible playbooks

---

# 1.1 ¿Qué es AWX? Historia y contexto

Ansible por sí solo es una herramienta de línea de comandos: ejecutas `ansible-playbook` desde tu terminal, con tus credenciales, en tu máquina. Eso funciona perfectamente para un sysadmin trabajando solo. Pero en cuanto el equipo crece, aparecen preguntas incómodas:

- ¿Quién ejecutó ese playbook ayer a las 3am?
- ¿Con qué credenciales? ¿Desde qué máquina?
- ¿Cómo evito que el becario ejecute en producción sin querer?
- ¿Puedo programar ejecuciones automáticas?
- ¿Hay una forma de que el equipo de desarrollo lance deploys sin darles acceso SSH a los servidores?

**AWX responde a todas esas preguntas.** Es una capa de orquestación, gobierno y visibilidad sobre Ansible.

```
SIN AWX:
  Developer → ansible-playbook site.yml → Servidores
  (sin logs centralizados, sin RBAC, sin auditoría, sin scheduling)

CON AWX:
  Developer → UI/API AWX → Job Template → EE Container → Servidores
  (logs, RBAC, auditoría, scheduling, notificaciones, aprobaciones)
```

### Línea de tiempo rápida

```
2012  ──► Ansible nace (Michael DeHaan)
2015  ──► Red Hat adquiere Ansible
2015  ──► Ansible Tower 2.0 (producto comercial)
2017  ──► AWX se publica como open source (upstream de Tower)
2019  ──► Ansible Tower 3.x → madurez enterprise
2021  ──► Red Hat Ansible Automation Platform (AAP) 2.0
           Tower pasa a llamarse "Automation Controller"
2022+ ──► AWX sigue como upstream activo de AAP Controller
```

### ¿Por qué importa conocer la historia?

Porque cuando buscas documentación, encontrarás referencias a Tower, AWX y AAP mezcladas. Saber que son la misma base de código en distintos estadios de madurez te evita confusión.

---

# 1.2 AWX vs Ansible Tower vs AAP

La pregunta más frecuente al empezar: *"¿Cuál uso?"*

```
AWX  ──────────────►  Automation Controller  ──────────────►  AAP Completo
(open source)          (antes: Tower)                          (plataforma)
```

## Comparativa detallada

| Característica | AWX | Automation Controller | AAP Completo |
|---------------|-----|----------------------|--------------|
| **Coste** | Gratuito | Suscripción Red Hat | Suscripción Red Hat |
| **Soporte** | Comunidad | SLA Red Hat | SLA Red Hat |
| **Actualizaciones** | Frecuentes, sin garantía | Ciclo de vida gestionado | Ciclo de vida gestionado |
| **Certificación** | No | Sí | Sí |
| **Execution Environments** | ✅ | ✅ | ✅ |
| **RBAC** | ✅ | ✅ | ✅ |
| **Workflows** | ✅ | ✅ | ✅ |
| **Private Automation Hub** | ❌ (separado) | ❌ (separado) | ✅ incluido |
| **Event-Driven Ansible** | ❌ | ❌ | ✅ incluido |
| **Ansible Lightspeed (AI)** | ❌ | ❌ | ✅ incluido |
| **Ideal para** | Labs, startups, aprendizaje | Empresas con soporte | Grandes empresas |

### La regla práctica

> **Aprende con AWX → Despliega Tower/AAP en producción enterprise.**  
> Todo lo que aprendes en AWX se transfiere directamente. La UI, la API, los conceptos y los objetos son idénticos.

---

# 1.3 Arquitectura interna de AWX

Entender la arquitectura no es teoría vacía: cuando algo falla, saber qué componente está involucrado te lleva directamente a la solución. Vamos componente a componente.

## El diagrama completo

```
╔══════════════════════════════════════════════════════════════════╗
║                        USUARIO / CI / SCHEDULE                   ║
╚══════════════════════════════════╦═══════════════════════════════╝
                                   ║ HTTPS / REST API / WebSocket
╔══════════════════════════════════▼═══════════════════════════════╗
║                    WEB SERVICE (Django + DRF)                     ║
║                                                                   ║
║  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐  ║
║  │   UI React  │  │  REST API v2 │  │  WebSocket (live logs) │  ║
║  └─────────────┘  └──────────────┘  └────────────────────────┘  ║
╚══════════╦═══════════════════════════════════════════════════════╝
           ║ encola tareas
╔══════════▼═══════════════╗    ╔═══════════════════════════════╗
║    TASK SERVICE           ║    ║        SCHEDULER              ║
║    (Celery workers)       ║    ║                               ║
║                           ║    ║  • Cron-based schedules       ║
║  • Orquesta job runs      ║    ║  • SCM polling                ║
║  • Gestiona el ciclo      ║    ║  • Webhook triggers           ║
║    de vida de cada job    ║    ║  • Inventory sync             ║
╚══════════╦════════════════╝    ╚═══════════════════════════════╝
           ║ pub/sub eventos
╔══════════▼════════════════╗
║         REDIS              ║
║                            ║
║  • Message broker          ║
║  • Cola de tareas          ║
║  • Streaming de logs       ║
║  • Fact cache (opcional)   ║
╚════════════════════════════╝

╔═══════════════════════════════════════════════════════════════╗
║              EXECUTION ENVIRONMENT (Container)                 ║
║                                                               ║
║  ┌─────────────────────────────────────────────────────────┐ ║
║  │  ansible-core  +  collections  +  Python deps  +  tools │ ║
║  └─────────────────────────────────────────────────────────┘ ║
║                           │                                   ║
║                           │ SSH / WinRM / API                 ║
║                           ▼                                   ║
║            ┌──────────────────────────────┐                  ║
║            │         HOSTS TARGET          │                  ║
║            │  web1  db1  app1  router1...  │                  ║
║            └──────────────────────────────┘                  ║
╚═══════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════╗
║                      POSTGRESQL                                ║
║                                                               ║
║  • Configuración completa (orgs, users, templates...)         ║
║  • Historial de jobs y eventos                                ║
║  • Credenciales cifradas                                      ║
║  • Activity stream (auditoría)                                ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## Componente por componente

### 🌐 Web Service

Es la cara visible de AWX. Sirve tanto la UI de React como la REST API v2.

- **UI React:** interfaz gráfica para gestionar todos los objetos
- **REST API v2:** todo lo que haces en la UI se puede hacer via API; es la misma API que usa la UI internamente
- **WebSocket:** permite ver los logs de ejecución en tiempo real sin polling

```bash
# La API es tu mejor amiga para automatizar AWX desde AWX
# Ejemplo: listar todos los job templates
curl -s -u admin:password \
  http://localhost:30080/api/v2/job_templates/ \
  | python3 -m json.tool | head -50

# La UI de la API es navegable en el browser:
# http://localhost:30080/api/v2/
```

### ⚙️ Task Service (Celery)

El motor de ejecución. Recibe trabajos de la cola de Redis y los orquesta:

1. Selecciona el Execution Environment correcto
2. Arranca el contenedor EE
3. Inyecta credenciales de forma segura (variables de entorno, ficheros temporales)
4. Lanza `ansible-runner` dentro del contenedor
5. Recoge eventos y los envía a Redis para streaming
6. Persiste resultados en PostgreSQL

> 💡 Cuando un job se queda en estado "pending" o "waiting", el problema está aquí o en la capacidad del Instance Group.

### 🕐 Scheduler

Gestiona cuándo se ejecutan los trabajos:

- **Schedules basados en cron:** ejecutar un template todos los días a las 2am
- **SCM polling:** comprobar si hay cambios en el repo cada N minutos
- **Webhook triggers:** ejecutar cuando GitHub/GitLab notifica un push
- **Inventory sync:** mantener el inventario dinámico actualizado

### 🔴 Redis

El sistema nervioso de AWX. Actúa como:

- **Message broker:** comunicación entre Web Service y Task Service
- **Cola de tareas:** buffer de trabajos pendientes
- **Streaming de logs:** los eventos de ejecución viajan por Redis hacia la UI en tiempo real
- **Fact cache** (opcional): almacena los facts de Ansible para reutilizarlos entre runs

> 💡 Si Redis cae, AWX no puede ejecutar nuevos jobs ni mostrar logs en tiempo real. Es un componente crítico.

### 🐘 PostgreSQL

La fuente de verdad de AWX. Almacena:

- Toda la configuración: organizaciones, usuarios, equipos, credenciales, proyectos, inventarios, templates
- Historial completo de jobs y eventos
- Credenciales cifradas con la `SECRET_KEY` de AWX
- Activity stream: registro de auditoría de todos los cambios

> ⚠️ **Importante:** Si pierdes PostgreSQL sin backup, pierdes toda la configuración de AWX. Es el componente más crítico para hacer backup.

### 📦 Execution Environments (EE)

Este es el concepto más importante de AWX moderno. Un EE es una **imagen de contenedor** que contiene:

```
Execution Environment
├── ansible-core (versión específica)
├── Python (versión específica)
├── Collections de Ansible (versiones fijadas)
├── Dependencias Python (boto3, netmiko, etc.)
└── Herramientas del sistema (git, rsync, etc.)
```

**¿Por qué EEs y no instalar Ansible directamente?**

```
SIN EE (método antiguo):
  Servidor AWX → ansible instalado globalmente
  Problema: "funciona en mi máquina", conflictos de versiones,
            difícil de reproducir, difícil de auditar

CON EE (método moderno):
  Job A usa EE con ansible-core 2.15 + community.general 9.x
  Job B usa EE con ansible-core 2.17 + community.network 5.x
  Sin conflictos, reproducible, auditable, portable
```

---

# 1.4 Flujo de ejecución de un Job

Seguir el camino completo de un job te ayuda a diagnosticar cualquier problema.

```
PASO 1: TRIGGER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Usuario pulsa "Launch" en la UI
  ─── o ───
  Schedule dispara automáticamente
  ─── o ───
  Webhook de GitHub/GitLab llega a la API
  ─── o ───
  CI/CD hace POST a /api/v2/job_templates/<id>/launch/

PASO 2: VALIDACIÓN Y ENCOLADO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Web Service valida permisos (RBAC)
  Web Service valida inputs (Survey, extra_vars)
  Crea registro de Job en PostgreSQL (estado: pending)
  Encola el trabajo en Redis

PASO 3: ASIGNACIÓN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Task Service recoge el trabajo de Redis
  Selecciona instancia disponible del Instance Group asignado
  Cambia estado a: waiting → running

PASO 4: PREPARACIÓN DEL ENTORNO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Task Service arranca el contenedor EE (pull si no existe localmente)
  Monta el directorio del Proyecto (playbooks desde Git)
  Inyecta credenciales de forma segura:
    - SSH keys → fichero temporal en /tmp (permisos 600)
    - Vault passwords → variable de entorno efímera
    - Cloud credentials → variables de entorno (AWS_ACCESS_KEY_ID, etc.)
  Genera el inventario (estático o ejecuta el plugin dinámico)

PASO 5: EJECUCIÓN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ansible-runner ejecuta el playbook dentro del EE
  Cada evento (task start, task result, host result) se emite
  Los eventos fluyen: EE → Task Service → Redis → Web Service → UI

PASO 6: RESULTADOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Task Service recoge el código de salida
  Persiste todos los eventos en PostgreSQL
  Actualiza estado del Job: success / failed / error / canceled
  Dispara notificaciones configuradas (Slack, email, webhook)
  Limpia ficheros temporales de credenciales
```

### Diagrama de estados de un Job

```
           ┌─────────┐
  launch → │ PENDING │
           └────┬────┘
                │ instancia disponible
           ┌────▼────┐
           │ WAITING │ ← esperando capacidad o aprobación
           └────┬────┘
                │ worker asignado
           ┌────▼────┐
           │ RUNNING │ ←──────────────────────┐
           └────┬────┘                        │
                │                             │ relaunch
      ┌─────────┼─────────┐                   │
      ▼         ▼         ▼                   │
  ┌───────┐ ┌──────┐ ┌─────────┐             │
  │SUCCESS│ │FAILED│ │CANCELED │             │
  └───────┘ └──────┘ └─────────┘             │
                │                             │
                └─────────────────────────────┘
                  (relaunch on failed hosts)
```

---

# 1.5 Objetos Core de AWX y sus relaciones

Antes de tocar la UI, entiende el modelo de objetos. Todo en AWX es un objeto con relaciones entre sí.

## El árbol de objetos

```
ORGANIZATION (límite de RBAC y contenido)
│
├── USERS & TEAMS
│     ├── User: operador1, developer2, auditor3
│     └── Team: Platform, AppOps, SecOps
│           └── Roles asignados sobre otros objetos
│
├── CREDENTIALS (autenticación y secretos)
│     ├── Machine/SSH → conectar a hosts
│     ├── Ansible Vault → descifrar vars
│     ├── Cloud (AWS/Azure/GCP) → inventario dinámico
│     ├── Source Control → clonar repos privados
│     ├── Container Registry → pull de EE privados
│     └── Custom → cualquier secreto con schema propio
│
├── PROJECTS (contenido de automatización)
│     ├── SCM Type: Git
│     ├── URL: github.com/org/repo
│     ├── Branch/Tag/Commit: main / v1.6.3 / abc1234
│     └── Credential: Source Control (si repo privado)
│
├── INVENTORIES (dónde ejecutar)
│     ├── Static: hosts definidos manualmente
│     ├── SCM: fichero de inventario en el repo Git
│     └── Dynamic Sources:
│           ├── AWS EC2 plugin
│           ├── Azure RM plugin
│           ├── GCP Compute plugin
│           └── Custom scripts
│
├── EXECUTION ENVIRONMENTS
│     ├── Default EE (incluido con AWX)
│     └── Custom EE (imagen propia con colecciones específicas)
│
└── TEMPLATES
      ├── JOB TEMPLATE (ejecuta un playbook)
      │     ├── Project + Playbook
      │     ├── Inventory
      │     ├── Credentials (una o varias)
      │     ├── Execution Environment
      │     ├── Extra Vars / Survey
      │     ├── Tags, Limit, Forks, Verbosity
      │     └── Instance Group
      │
      └── WORKFLOW TEMPLATE (pipeline de templates)
            ├── Nodos: Job Templates, Workflow Templates, Approvals
            ├── Edges: success / failure / always
            └── Survey propio
```

## Las relaciones mínimas para ejecutar un Job

```
Para que un Job Template funcione necesitas:

  PROJECT ──────────────────────────────────┐
  (contiene el playbook)                    │
                                            ▼
  INVENTORY ──────────────────────► JOB TEMPLATE ──► EJECUCIÓN
  (contiene los hosts)                      ▲
                                            │
  CREDENTIAL ───────────────────────────────┤
  (SSH key para conectar)                   │
                                            │
  EXECUTION ENVIRONMENT ────────────────────┘
  (ansible-core + collections)
```

> 💡 **Regla de oro:** Cuando algo falla, pregúntate: ¿cuál de estos 4 objetos es el problema? El 95% de los errores iniciales están en uno de estos cuatro.

## Descripción de cada objeto

### Organization

El contenedor de todo. Define los límites de RBAC: lo que está en la Organización A no es visible desde la Organización B (salvo que seas System Admin).

```
Casos de uso:
  • Una organización por empresa (lo más común en AWX)
  • Una organización por departamento (Platform, AppDev, DataOps)
  • Una organización por cliente (si usas AWX como servicio multi-tenant)
```

### Credentials

AWX nunca muestra las credenciales en texto plano después de guardarlas. Se cifran en PostgreSQL con la `SECRET_KEY`. Los tipos más usados:

```yaml
# Tipo: Machine (SSH)
# Campos: username, ssh_private_key, become_method, become_password
# Uso: conectar a Linux/Unix hosts

# Tipo: Ansible Vault
# Campos: vault_password, vault_id
# Uso: descifrar vars_files o variables individuales encriptadas

# Tipo: Amazon Web Services
# Campos: access_key, secret_key (o assume_role)
# Uso: inventario dinámico EC2, módulos cloud

# Tipo: Source Control
# Campos: username, password/token o ssh_key
# Uso: clonar repos privados en Projects

# Tipo: Container Registry
# Campos: host, username, password
# Uso: pull de imágenes EE privadas
```

### Projects

Un Project es un puntero a un repositorio Git. AWX clona el repo y lo mantiene sincronizado.

```
Opciones importantes:
  SCM Branch:           main, develop, feature/x
  SCM Tag:              v1.6.3 (inmutable, ideal para prod)
  SCM Commit:           abc1234def (máxima precisión)
  
  Clean:                elimina ficheros no rastreados por Git
  Delete on Update:     borra y vuelve a clonar (evita estado sucio)
  Update on Launch:     sincroniza antes de cada ejecución (útil en dev)
  Update Revision on Launch: fija el commit exacto al lanzar
```

### Inventories

Los hosts donde se ejecutan los playbooks. Pueden ser:

```yaml
# Inventario estático (YAML en la UI o en SCM)
all:
  children:
    dev:
      hosts:
        dev-web1:
          ansible_host: 192.168.1.10
          ansible_user: ansible
        dev-db1:
          ansible_host: 192.168.1.11
    prod:
      hosts:
        prod-web1:
          ansible_host: 10.0.1.10
      vars:
        env: prod
        debug_mode: false
```

### Job Templates

El objeto central de AWX. Une todos los demás objetos en una definición ejecutable.

```
Parámetros clave:
  Job Type:     Run (ejecutar) / Check (dry-run) / Scan
  Verbosity:    0=Normal, 1=Verbose, 2=More Verbose, 3=Debug, 4=Connection Debug
  Forks:        paralelismo (hosts simultáneos)
  Limit:        patrón de hosts (dev, web*, prod-web1)
  Tags:         ejecutar solo tareas con estas tags
  Skip Tags:    saltar tareas con estas tags
  Timeout:      segundos máximos de ejecución (0 = sin límite)
```

---

# 1.6 LAB — Instalar AWX con K3s en Ubuntu 22.04/24.04

*Usamos K3s porque es Kubernetes ligero, se instala en un comando, y refleja cómo se despliega AWX en entornos reales.*

## Requisitos del sistema

```
Mínimo recomendado para el lab:
  CPU:    4 vCPUs
  RAM:    8 GB (AWX usa ~4-6 GB en reposo)
  Disco:  40 GB
  OS:     Ubuntu 22.04 LTS o 24.04 LTS
  Red:    acceso a internet (para pull de imágenes)
```

## Paso 1 — Preparar el sistema

```bash
# Actualizar el sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependencias básicas
sudo apt install -y curl git vim python3 python3-pip

# Verificar versión de Ubuntu
lsb_release -a
# Description: Ubuntu 22.04.x LTS  (o 24.04.x LTS)

# Verificar recursos disponibles
echo "=== CPU ===" && nproc
echo "=== RAM ===" && free -h
echo "=== DISCO ===" && df -h /
```

## Paso 2 — Instalar K3s

```bash
# Instalar K3s (Kubernetes ligero)
curl -sfL https://get.k3s.io | sh -

# Esperar a que K3s esté listo (30-60 segundos)
sudo systemctl status k3s

# Verificar que el nodo está Ready
sudo k3s kubectl get nodes
# NAME       STATUS   ROLES                  AGE   VERSION
# ubuntu     Ready    control-plane,master   60s   v1.29.x+k3s1

# Configurar kubectl para tu usuario (sin sudo)
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Verificar sin sudo
kubectl get nodes
```

## Paso 3 — Instalar el AWX Operator

El Operator es un controlador de Kubernetes que gestiona el ciclo de vida de AWX: instalación, actualizaciones y configuración.

```bash
# Crear el namespace para AWX
kubectl create namespace awx

# Verificar la última versión disponible del operator en:
# https://github.com/ansible/awx-operator/releases
# Usamos 2.19.1 como ejemplo; ajusta a la versión más reciente

OPERATOR_VERSION="2.19.1"

# Instalar el AWX Operator
kubectl apply -n awx -f \
  "https://raw.githubusercontent.com/ansible/awx-operator/${OPERATOR_VERSION}/deploy/awx-operator.yaml"

# Esperar a que el operator esté Running (1-2 minutos)
kubectl get pods -n awx -w
# NAME                                               READY   STATUS    RESTARTS
# awx-operator-controller-manager-6c995d4d9f-xxxxx  2/2     Running   0

# Cuando veas 2/2 Running, pulsa Ctrl+C
```

## Paso 4 — Crear el Secret con la contraseña de admin

```bash
# Crear el secret ANTES de desplegar la instancia AWX
kubectl create secret generic awx-admin-password \
  -n awx \
  --from-literal=password='TuPasswordSegura123!'

# Verificar que se creó
kubectl get secret awx-admin-password -n awx
# NAME                 TYPE     DATA   AGE
# awx-admin-password   Opaque   1      5s
```

## Paso 5 — Crear el fichero de instancia AWX

```bash
# Crear el fichero de configuración de la instancia AWX
cat > awx-instance.yaml << 'EOF'
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  # Tipo de servicio: nodeport para acceso directo al nodo
  service_type: nodeport
  nodeport_port: 30080
  
  # Credenciales de admin
  admin_user: admin
  admin_password_secret: awx-admin-password
  
  # Configuración de PostgreSQL (gestionado por el operator)
  postgres_storage_class: local-path
  postgres_storage_requirements:
    requests:
      storage: 8Gi
  
  # Configuración de proyectos (almacenamiento para repos Git)
  projects_storage_class: local-path
  projects_storage_size: 8Gi
  projects_persistence: true
EOF

# Aplicar la configuración
kubectl apply -f awx-instance.yaml
```

## Paso 6 — Seguir el despliegue

```bash
# Ver todos los pods creándose (tarda 5-10 minutos la primera vez)
kubectl get pods -n awx -w

# Lo que verás durante el proceso:
# awx-operator-controller-manager-xxx   2/2   Running   0   (ya existía)
# awx-postgres-15-0                     0/1   Pending   0   (BD arrancando)
# awx-postgres-15-0                     1/1   Running   0   (BD lista)
# awx-migration-24.x.x-xxx              0/1   Init:0/1  0   (migraciones)
# awx-migration-24.x.x-xxx              0/1   Running   0
# awx-migration-24.x.x-xxx              0/1   Completed 0   (migraciones OK)
# awx-task-xxx                          0/4   Init:0/2  0   (task service)
# awx-web-xxx                           0/1   Init:0/2  0   (web service)
# awx-task-xxx                          4/4   Running   0   (task listo)
# awx-web-xxx                           1/1   Running   0   (web listo)

# Cuando veas awx-web y awx-task en Running, pulsa Ctrl+C

# Verificar estado final
kubectl get pods -n awx
# NAME                                               READY   STATUS      RESTARTS
# awx-operator-controller-manager-6c995d4d9f-xxxxx  2/2     Running     0
# awx-postgres-15-0                                  1/1     Running     0
# awx-migration-24.x.x-xxxxx                        0/1     Completed   0
# awx-task-xxxxxxxxxx-xxxxx                          4/4     Running     0
# awx-web-xxxxxxxxxx-xxxxx                           1/1     Running     0
```

## Paso 7 — Acceder a AWX

```bash
# Obtener la IP del nodo
NODE_IP=$(hostname -I | awk '{print $1}')
echo "AWX disponible en: http://${NODE_IP}:30080"

# Verificar que la API responde
curl -s "http://${NODE_IP}:30080/api/v2/ping/" | python3 -m json.tool
# {
#     "ha": false,
#     "version": "24.x.x",
#     "active_node": "awx-task-xxxxxxxxxx-xxxxx",
#     "install_uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }
```

Abre el navegador en `http://<IP_NODO>:30080`:
- **Usuario:** `admin`
- **Password:** `TuPasswordSegura123!`

## Paso 8 — Verificaciones post-instalación

```bash
# Ver los logs del web service (útil para troubleshooting)
kubectl logs -n awx deployment/awx-web -c awx-web --tail=20

# Ver los logs del task service
kubectl logs -n awx deployment/awx-task -c awx-task --tail=20

# Ver los logs del operator
kubectl logs -n awx deployment/awx-operator-controller-manager --tail=20

# Verificar que el servicio NodePort está expuesto
kubectl get svc -n awx
# NAME              TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)
# awx-service       NodePort   10.43.xxx.xxx   <none>        80:30080/TCP

# Verificar el estado de la instancia AWX (Custom Resource)
kubectl get awx -n awx
# NAME   AGE
# awx    10m

kubectl describe awx awx -n awx | grep -A5 "Status:"
```

---

# 1.7 LAB — Primera configuración: Organización, Equipo y Proyecto

*Ahora que AWX está funcionando, configuramos la estructura base que usaremos en todos los módulos siguientes.*

## Parte A — Configuración via UI

### Crear la Organización

```
1. Login como admin en http://<IP>:30080

2. Menú izquierdo → Organizations → Add (botón azul +)
   
   Name:        MiEmpresa
   Description: Organización principal de automatización
   
   → Save
```

### Crear los Equipos

```
3. Menú izquierdo → Teams → Add
   
   Name:         Platform
   Description:  Equipo de plataforma e infraestructura
   Organization: MiEmpresa
   → Save

4. Teams → Add
   Name:         AppOps
   Description:  Equipo de operaciones de aplicaciones
   Organization: MiEmpresa
   → Save

5. Teams → Add
   Name:         Auditores
   Description:  Acceso de solo lectura para compliance
   Organization: MiEmpresa
   → Save
```

### Crear Usuarios

```
6. Menú izquierdo → Users → Add
   
   First Name:   Operador
   Last Name:    Uno
   Username:     operador1
   Email:        operador1@miempresa.com
   Password:     OperadorPass123!
   User Type:    Normal User
   → Save
   
   → Teams tab → Add Team: AppOps

7. Users → Add
   Username:     plataforma1
   User Type:    Normal User
   → Save
   → Teams tab → Add Team: Platform
```

### Crear Credencial SSH

```
8. Menú izquierdo → Credentials → Add
   
   Name:         Platform SSH
   Description:  Clave SSH para conexión a hosts gestionados
   Organization: MiEmpresa
   Credential Type: Machine
   
   Username:     ansible
   SSH Private Key: [pegar el contenido de tu clave privada]
   
   # Si no tienes clave SSH, créala:
   # ssh-keygen -t ed25519 -C "awx-lab" -f ~/.ssh/awx_lab
   # cat ~/.ssh/awx_lab  (pegar este contenido en el campo)
   
   Privilege Escalation Method: sudo
   
   → Save
```

### Crear el Proyecto

Para este lab necesitas un repositorio Git con al menos un playbook. Puedes usar un repositorio público de ejemplo o crear el tuyo.

```
9. Menú izquierdo → Projects → Add
   
   Name:         Platform Playbooks
   Description:  Repositorio principal de playbooks
   Organization: MiEmpresa
   Source Control Type: Git
   
   Source Control URL: https://github.com/ansible/ansible-examples.git
   # (o tu propio repo)
   
   Source Control Branch/Tag/Commit: master
   # (o main, según tu repo)
   
   Options:
     ✅ Clean
     ✅ Delete on Update
   
   → Save
   
   # AWX intentará sincronizar el repo automáticamente
   # Verás el estado: Running → Successful
```

### Verificar la sincronización del Proyecto

```
10. Projects → Platform Playbooks
    
    Verifica que "Last Job Status" muestra: Successful
    
    Si muestra Failed:
    - Revisa la URL del repo
    - Si es privado, añade la credencial SCM
    - Comprueba que AWX tiene acceso a internet
```

## Parte B — Lo mismo via API (para automatización)

```bash
# Variables de entorno para la API
AWX_URL="http://localhost:30080"
AWX_USER="admin"
AWX_PASS="TuPasswordSegura123!"

# Función helper para llamadas a la API
awx_api() {
  curl -s -u "${AWX_USER}:${AWX_PASS}" \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/$@"
}

# Crear Organización
awx_api organizations/ -X POST \
  -d '{"name": "MiEmpresa", "description": "Organización principal"}' \
  | python3 -m json.tool | grep '"id"'
# "id": 2,   ← guarda este ID

ORG_ID=2  # ajusta al ID obtenido

# Crear Equipo Platform
awx_api teams/ -X POST \
  -d "{\"name\": \"Platform\", \"organization\": ${ORG_ID}}" \
  | python3 -m json.tool | grep '"id"'

# Crear Proyecto
awx_api projects/ -X POST \
  -d "{
    \"name\": \"Platform Playbooks\",
    \"organization\": ${ORG_ID},
    \"scm_type\": \"git\",
    \"scm_url\": \"https://github.com/ansible/ansible-examples.git\",
    \"scm_branch\": \"master\",
    \"scm_clean\": true,
    \"scm_delete_on_update\": true
  }" | python3 -m json.tool | grep '"id"'

# Verificar estado del proyecto (esperar a que sincronice)
PROJECT_ID=X  # ajusta al ID obtenido
awx_api projects/${PROJECT_ID}/ | python3 -m json.tool | grep '"status"'
# "status": "successful",
```

---

# 1.8 LAB — Primer Job Template y ejecución end-to-end

*El objetivo es completar el ciclo completo: Git → AWX → Hosts. Aunque sea con un playbook simple.*

## Preparar el inventario

```
Menú izquierdo → Inventories → Add → Inventory

  Name:         Lab Inventory
  Organization: MiEmpresa
  
  → Save

→ Lab Inventory → Hosts → Add

  Name:         localhost
  Variables:
    ansible_connection: local
    ansible_python_interpreter: "{{ ansible_playbook_python }}"
  
  → Save
```

> 💡 Usamos `localhost` con `ansible_connection: local` para el primer lab. Así no necesitas hosts externos ni configuración de red.

## Crear el playbook en tu repo

Si usas el repo de ejemplos de Ansible, ya tiene playbooks. Si quieres crear el tuyo:

```yaml
# playbooks/hello_awx.yml
---
- name: Mi primer playbook en AWX
  hosts: all
  gather_facts: true
  
  tasks:
    - name: Mostrar mensaje de bienvenida
      ansible.builtin.debug:
        msg: |
          ¡Hola desde AWX!
          Host: {{ inventory_hostname }}
          OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
          Fecha: {{ ansible_date_time.iso8601 }}
          Usuario: {{ ansible_user_id }}

    - name: Crear fichero de prueba
      ansible.builtin.copy:
        content: |
          Ejecutado por AWX
          Timestamp: {{ ansible_date_time.iso8601 }}
          Host: {{ inventory_hostname }}
        dest: /tmp/awx_test.txt
        mode: '0644'
      
    - name: Verificar que el fichero existe
      ansible.builtin.stat:
        path: /tmp/awx_test.txt
      register: fichero_resultado
      
    - name: Mostrar resultado de verificación
      ansible.builtin.debug:
        msg: "Fichero creado: {{ fichero_resultado.stat.exists }}"
```

## Crear el Job Template

```
Templates → Add → Job Template

  Name:                  Hello AWX
  Description:           Primer job template de prueba
  Job Type:              Run
  Inventory:             Lab Inventory
  Project:               Platform Playbooks
  Playbook:              playbooks/hello_awx.yml
                         (o el playbook que tengas en tu repo)
  Credentials:           Platform SSH
  Execution Environment: Default Execution Environment
  
  Verbosity:             1 (Verbose)
  Forks:                 5
  
  Options:
    ✅ Enable Privilege Escalation (si el playbook lo necesita)
  
  → Save
```

## Lanzar el Job

```
Templates → Hello AWX → Launch (botón cohete 🚀)

En el diálogo de confirmación:
  → Launch (sin cambios adicionales por ahora)

Observa en tiempo real:
  • La barra de progreso
  • Los eventos de cada task
  • El output de debug con el mensaje
  • El estado final: Successful ✅
```

## Explorar los resultados

```
Una vez completado el job:

1. Tab "Details":
   - Job ID, estado, duración, quién lo lanzó
   - Template, proyecto, inventario, credencial usados
   - Execution Environment utilizado

2. Tab "Output":
   - Log completo de la ejecución
   - Puedes filtrar por host, tipo de evento, estado
   - Buscar texto específico en los logs

3. Tab "Events":
   - Cada evento individual (task start, task result)
   - Tiempo de cada task
   - Datos completos en JSON

4. Volver a Jobs (menú izquierdo):
   - Historial completo de todos los jobs
   - Filtrar por template, estado, fecha, usuario
```

## Explorar la API del Job ejecutado

```bash
# Listar los últimos jobs
curl -s -u admin:TuPasswordSegura123! \
  "http://localhost:30080/api/v2/jobs/?order_by=-id&page_size=5" \
  | python3 -m json.tool | grep -E '"id"|"status"|"name"'

# Ver detalles del último job (ajusta el ID)
JOB_ID=1
curl -s -u admin:TuPasswordSegura123! \
  "http://localhost:30080/api/v2/jobs/${JOB_ID}/" \
  | python3 -m json.tool | grep -E '"status"|"elapsed"|"started"|"finished"'

# Ver los eventos del job
curl -s -u admin:TuPasswordSegura123! \
  "http://localhost:30080/api/v2/jobs/${JOB_ID}/job_events/?page_size=5" \
  | python3 -m json.tool | head -60
```

---

# 1.9 Troubleshooting del Módulo 1

Los problemas más frecuentes en la instalación y primera configuración.

## Problemas de instalación K3s/AWX

### K3s no arranca

```bash
# Ver logs de K3s
sudo journalctl -u k3s -f

# Problema frecuente: puerto 6443 ocupado
sudo ss -tlnp | grep 6443

# Solución: reiniciar K3s
sudo systemctl restart k3s
```

### Pods de AWX en estado Pending

```bash
# Ver por qué el pod no arranca
kubectl describe pod <nombre-pod> -n awx | tail -20

# Causas frecuentes:
# 1. Insuficiente memoria → añadir RAM o reducir requests
# 2. StorageClass no disponible → verificar local-path provisioner
kubectl get storageclass

# Verificar el local-path provisioner de K3s
kubectl get pods -n kube-system | grep local-path
```

### Pods de AWX en estado CrashLoopBackOff

```bash
# Ver logs del pod que falla
kubectl logs -n awx <nombre-pod> --previous

# Causa frecuente: el secret de admin no existe
kubectl get secret awx-admin-password -n awx
# Si no existe, créalo:
kubectl create secret generic awx-admin-password \
  -n awx --from-literal=password='TuPasswordSegura123!'

# Reiniciar el deployment
kubectl rollout restart deployment/awx-web -n awx
kubectl rollout restart deployment/awx-task -n awx
```

### No puedo acceder a la UI

```bash
# Verificar que el servicio NodePort existe
kubectl get svc -n awx

# Verificar que el puerto está escuchando
sudo ss -tlnp | grep 30080

# Si usas una VM en la nube, verificar el Security Group/Firewall
# El puerto 30080 debe estar abierto para tu IP

# Probar acceso local
curl -s http://localhost:30080/api/v2/ping/
```

## Problemas de configuración

### SCM sync falla (Project)

```bash
# Ver el log del sync en AWX UI:
# Projects → Platform Playbooks → (icono de reloj) → ver último job

# Causas frecuentes:
# 1. URL incorrecta del repo
# 2. Rama inexistente (main vs master)
# 3. Repo privado sin credencial SCM
# 4. AWX sin acceso a internet

# Verificar acceso a internet desde el pod
kubectl exec -n awx deployment/awx-task -c awx-task -- \
  curl -s https://github.com --max-time 5 -o /dev/null -w "%{http_code}"
# Debe devolver 200 o 301
```

### Job falla con "Host unreachable"

```bash
# En el output del job, busca el error específico:
# UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host..."}

# Causas y soluciones:
# 1. ansible_host incorrecto → verificar IP en el inventario
# 2. Usuario SSH incorrecto → verificar campo Username en la credencial
# 3. Clave SSH incorrecta → verificar que la clave pública está en authorized_keys del host
# 4. Puerto SSH no estándar → añadir ansible_port: 2222 en host vars
# 5. Firewall bloqueando → verificar reglas de red

# Para localhost (lab): asegúrate de que tienes:
# ansible_connection: local
# en las variables del host
```

### "Module not found" o "Collection not found"

```bash
# El EE no tiene la colección necesaria
# Solución 1: usar un EE diferente que la incluya
# Solución 2: construir un EE personalizado (ver Módulo 3)

# Ver qué colecciones tiene el EE por defecto
kubectl exec -n awx deployment/awx-task -c awx-task -- \
  ansible-galaxy collection list
```

### Survey variable no llega al playbook

```
Causa más frecuente: el nombre de la variable en el Survey
no coincide exactamente con el nombre en el playbook.

Survey → Answer Variable Name: app_version
Playbook → {{ app_version }}

Deben ser IDÉNTICOS (case-sensitive).

También verificar:
  - El Survey está habilitado en el template
  - "Prompt on launch" está activado para el Survey
```

---

# 1.10 Resumen y Checklist del Módulo 1

## Lo que has aprendido

```
✅ AWX es la capa de gobierno sobre Ansible:
   UI + API + RBAC + Scheduling + Auditoría + Notificaciones

✅ Arquitectura de 6 componentes:
   Web Service → Task Service → Scheduler → Redis → PostgreSQL → EE

✅ Flujo de ejecución completo:
   Trigger → Validación → Encolado → Asignación → Preparación → Ejecución → Resultados

✅ 7 objetos core y sus relaciones:
   Organization → Teams/Users → Credentials → Projects → Inventories → EE → Templates

✅ Instalación con K3s en Ubuntu 22.04/24.04:
   K3s → AWX Operator → AWX Instance → Acceso UI

✅ Primera configuración:
   Organización → Equipos → Usuarios → Credenciales → Proyecto → Job Template

✅ Primer job ejecutado end-to-end con logs y auditoría
```

## Checklist de verificación

```bash
# Ejecuta estos comandos para verificar que todo está en orden

echo "=== 1. K3s funcionando ==="
kubectl get nodes | grep Ready

echo "=== 2. Pods AWX Running ==="
kubectl get pods -n awx | grep -E "web|task|postgres" | grep Running

echo "=== 3. API respondiendo ==="
curl -s http://localhost:30080/api/v2/ping/ | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(f'AWX v{d[\"version\"]} ✅')"

echo "=== 4. Organización creada ==="
curl -s -u admin:TuPasswordSegura123! \
  http://localhost:30080/api/v2/organizations/ | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(f'Orgs: {d[\"count\"]} ✅')"

echo "=== 5. Proyecto sincronizado ==="
curl -s -u admin:TuPasswordSegura123! \
  http://localhost:30080/api/v2/projects/ | python3 -c \
  "import sys,json; d=json.load(sys.stdin)
for p in d['results']:
    status = '✅' if p['status'] == 'successful' else '❌'
    print(f'{status} {p[\"name\"]}: {p[\"status\"]}')"

echo "=== 6. Job Template existe ==="
curl -s -u admin:TuPasswordSegura123! \
  http://localhost:30080/api/v2/job_templates/ | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(f'Templates: {d[\"count\"]} ✅')"
```

## Preguntas de verificación conceptual

Antes de pasar al Módulo 2, deberías poder responder:

```
1. ¿Cuál es la diferencia entre AWX y Ansible Tower?
   → Misma base de código; AWX es open source upstream,
     Tower/Controller es la distribución comercial con soporte Red Hat.

2. ¿Qué componente persiste toda la configuración de AWX?
   → PostgreSQL. Es el componente más crítico para backup.

3. ¿Qué es un Execution Environment y por qué es mejor
   que instalar Ansible directamente en el servidor?
   → Es una imagen de contenedor con ansible-core + collections.
     Permite versiones distintas por job, es reproducible y auditable.

4. ¿Cuáles son los 4 objetos mínimos para ejecutar un Job Template?
   → Project (playbook) + Inventory (hosts) + Credential (SSH) + EE

5. ¿Qué pasa en Redis cuando lanzas un job?
   → El trabajo se encola en Redis como mensaje;
     el Task Service lo consume y orquesta la ejecución.
     Los eventos de ejecución también fluyen por Redis hacia la UI.

6. ¿Por qué AWX no muestra las credenciales en texto plano?
   → Se cifran en PostgreSQL con la SECRET_KEY de AWX.
     Solo se inyectan de forma efímera durante la ejecución.
```

---

## 🔜 Siguiente: Módulo 2

En el Módulo 2 profundizamos en los tres bloques de construcción que hacen que los jobs funcionen de forma segura y escalable:

- **Inventarios** estáticos, en SCM y dinámicos (AWS EC2, Azure, GCP)
- **Credenciales** SSH, Vault, Cloud y tipos personalizados
- **Proyectos** con estrategias de sync, webhooks y pins por entorno

> 🎯 **El principio de este módulo:** AWX no es solo una UI para Ansible. Es la capa de gobernanza que convierte scripts en procesos auditables, repetibles y seguros. Cada objeto que has creado hoy es un contrato entre equipos: quién puede hacer qué, con qué herramientas, sobre qué hosts.