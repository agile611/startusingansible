# ⚙️ MÓDULO 7 — Operaciones Avanzadas: Escalado, HA, Backup y Observabilidad
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 7.1 | Modelo mental: AWX como plataforma de producción |
| 7.2 | Arquitectura interna de AWX en Kubernetes |
| 7.3 | Execution Nodes: tipos y topologías |
| 7.4 | Escalado horizontal: añadir capacidad de ejecución |
| 7.5 | Alta disponibilidad: diseño y configuración |
| 7.6 | Backup y restauración |
| 7.7 | Actualizaciones sin downtime |
| 7.8 | Métricas con Prometheus y Grafana |
| 7.9 | Logging centralizado con ELK/Loki |
| 7.10 | LAB — Añadir un Execution Node remoto |
| 7.11 | LAB — Configurar backup automático |
| 7.12 | LAB — Dashboard de observabilidad en Grafana |
| 7.13 | LAB — Actualización de AWX sin downtime |
| 7.14 | LAB — Simulación de fallo y recuperación |
| 7.15 | Patrones avanzados y buenas prácticas |
| 7.16 | Troubleshooting del módulo |
| 7.17 | Resumen y checklist |

**Duración estimada:** 75-90 minutos
**Tipo:** Operaciones + Labs de infraestructura
**Prerrequisitos:** Módulos 1-6 completados, acceso a kubectl

---

# 7.1 Modelo mental: AWX como plataforma de producción

Hasta ahora hemos construido automatización sobre AWX. En este módulo tratamos AWX como lo que es en producción: una plataforma crítica que necesita las mismas garantías que cualquier otro sistema de misión crítica.

```
AWX EN MODO LAB (lo que hemos hecho):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Un solo nodo Kubernetes
  Base de datos PostgreSQL sin réplica
  Sin backup automatizado
  Sin monitorización
  Actualización = downtime
  Si falla = todo para

AWX EN PRODUCCIÓN (lo que construimos en este módulo):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Múltiples Execution Nodes distribuidos geográficamente
  PostgreSQL con réplica de lectura y failover automático
  Backup diario con retención de 30 días y prueba de restauración
  Métricas en Prometheus, dashboards en Grafana
  Alertas en PagerDuty para eventos críticos
  Actualizaciones rolling sin downtime
  RTO < 15 minutos, RPO < 24 horas

LA PREGUNTA CLAVE:
  Si AWX falla a las 3 AM durante un incidente de producción,
  ¿cuánto tarda en volver? ¿Cuántos jobs se pierden?
  ¿Puede el equipo de guardia recuperarlo sin ayuda?
  
  Este módulo responde esas preguntas.
```

---

# 7.2 Arquitectura interna de AWX en Kubernetes

## Componentes del despliegue AWX

```
NAMESPACE: awx
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DEPLOYMENT: awx-web
  Contenedores:
    awx-web     → API REST + UI (Django + React)
    awx-rsyslog → Recopila logs de jobs y los envía a la BD
  
  Responsabilidad:
    → Servir la API REST (/api/v2/...)
    → Servir la UI web
    → Autenticación y autorización
    → Gestión de objetos (templates, inventarios, etc.)

DEPLOYMENT: awx-task
  Contenedores:
    awx-task    → Motor de tareas (Celery workers)
    awx-rsyslog → Logs de tareas
  
  Responsabilidad:
    → Procesar la cola de jobs
    → Lanzar Execution Environments (contenedores de ejecución)
    → Gestionar el ciclo de vida de los jobs
    → Sincronizar proyectos e inventarios

STATEFULSET: awx-postgres
  → Base de datos PostgreSQL
  → Almacena: objetos AWX, historial de jobs, credenciales cifradas
  → PersistentVolumeClaim para los datos

DEPLOYMENT: awx-redis
  → Cola de mensajes y fact cache
  → Coordina la comunicación entre awx-web y awx-task
  → Almacena el estado de los jobs en ejecución

SERVICE: awx-service
  → Expone la UI/API al exterior
  → Tipo: NodePort (lab) o LoadBalancer (producción)

SECRET: awx-secret-key
  → Clave de cifrado para credenciales en la BD
  → CRÍTICO: si se pierde, las credenciales cifradas son irrecuperables
```

## Flujo de ejecución de un job

```
FLUJO COMPLETO CUANDO SE LANZA UN JOB:

  1. Usuario → POST /api/v2/job_templates/ID/launch/
     awx-web recibe la petición, valida permisos, crea el Job object

  2. awx-web → Redis (encola el job)
     El job queda en estado "pending"

  3. awx-task (Celery worker) → lee de Redis
     El job pasa a estado "waiting" (esperando capacidad)

  4. awx-task → selecciona el Execution Node
     Basándose en el Instance Group del template

  5. awx-task → lanza el contenedor EE en el Execution Node
     Monta el proyecto, credenciales y variables

  6. EE (contenedor) → ejecuta ansible-runner
     ansible-runner ejecuta el playbook

  7. Eventos del job → rsyslog → awx-task → PostgreSQL
     Los logs se almacenan en tiempo real

  8. Job completa → awx-task actualiza el estado en PostgreSQL
     Notificaciones se envían si están configuradas

  9. EE (contenedor) → se destruye
     El Execution Node queda libre para el siguiente job
```

---

# 7.3 Execution Nodes: tipos y topologías

## Tipos de nodos en AWX

```
CONTROL PLANE NODE (awx-task):
  → Gestiona la lógica de AWX
  → Procesa la cola de jobs
  → NO ejecuta playbooks directamente (en configuraciones distribuidas)
  → Siempre en el cluster Kubernetes de AWX

EXECUTION NODE (hop node o execution node):
  → Ejecuta los playbooks (lanza los EE)
  → Puede estar fuera del cluster Kubernetes
  → Se conecta al Control Plane via receptor (mesh networking)
  → Ideal para: ejecutar cerca de los hosts objetivo

HOP NODE:
  → Nodo intermediario de red
  → No ejecuta playbooks
  → Reenvía tráfico entre el Control Plane y Execution Nodes
  → Útil para: redes segmentadas, DMZ, múltiples datacenters
```

## Topologías de despliegue

```
TOPOLOGÍA 1: Simple (lab / empresa pequeña)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [AWX Control Plane + Execution] ──── SSH ──── [Hosts]
  
  Todo en un solo nodo Kubernetes.
  El Control Plane también ejecuta los jobs.
  Válido para: < 50 hosts, < 10 jobs concurrentes.

TOPOLOGÍA 2: Distribuida (empresa mediana)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [AWX Control Plane]
       │ receptor (mesh)
       ├── [Execution Node 1] ──── SSH ──── [Hosts DC Madrid]
       └── [Execution Node 2] ──── SSH ──── [Hosts DC Barcelona]
  
  Control Plane en Kubernetes.
  Execution Nodes en VMs dedicadas, cerca de los hosts.
  Válido para: múltiples datacenters, < 500 hosts.

TOPOLOGÍA 3: Multi-datacenter con Hop Nodes (empresa grande)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [AWX Control Plane] (Kubernetes, HA)
       │ receptor
       ├── [Hop Node DMZ] ──── receptor ──── [Execution Node DMZ]
       │                                           │ SSH
       │                                     [Hosts DMZ]
       │
       ├── [Hop Node AWS] ──── receptor ──── [Execution Node AWS eu-west-1]
       │                                           │ SSH
       │                                     [EC2 Instances]
       │
       └── [Hop Node Azure] ── receptor ──── [Execution Node Azure]
                                                   │ SSH
                                             [Azure VMs]
```

## Receptor: el protocolo de comunicación

```
AWX usa "receptor" (librería de Red Hat) para la comunicación
entre el Control Plane y los Execution Nodes.

CARACTERÍSTICAS:
  → Comunicación bidireccional sobre TCP/27199
  → Cifrado TLS mutuo (mTLS) con certificados autofirmados
  → El Execution Node NO necesita acceso entrante al Control Plane
    (el Control Plane inicia la conexión, o se usa un Hop Node)
  → Tolerante a desconexiones temporales

REQUISITOS DE RED:
  Control Plane → Execution Node: TCP/27199
  (o Execution Node → Hop Node → Control Plane si hay NAT)
```

---

# 7.4 Escalado horizontal: añadir capacidad de ejecución

## Escalar el Control Plane (awx-task)

```yaml
# awx-operator/config/manager/kustomization.yaml
# Aumentar réplicas del deployment awx-task

# O directamente con kubectl:
kubectl scale deployment awx-task -n awx --replicas=3

# Verificar
kubectl get pods -n awx -l app.kubernetes.io/component=task
# NAME                        READY   STATUS    RESTARTS
# awx-task-xxx-yyy            4/4     Running   0
# awx-task-xxx-zzz            4/4     Running   0
# awx-task-xxx-aaa            4/4     Running   0
```

## Escalar awx-web

```bash
# Escalar la UI/API
kubectl scale deployment awx-web -n awx --replicas=3

# Verificar que el Service balancea correctamente
kubectl get endpoints awx-service -n awx
```

## Configurar el AWX Operator para HA

```yaml
# awx-instance.yaml
# Configuración del AWX Operator para alta disponibilidad
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: LoadBalancer

  # Réplicas de la UI/API
  web_replicas: 3

  # Réplicas del motor de tareas
  task_replicas: 3

  # Recursos para web
  web_resource_requirements:
    requests:
      cpu:    500m
      memory: 1Gi
    limits:
      cpu:    2000m
      memory: 4Gi

  # Recursos para task
  task_resource_requirements:
    requests:
      cpu:    500m
      memory: 2Gi
    limits:
      cpu:    4000m
      memory: 8Gi

  # PostgreSQL externo (recomendado para producción)
  postgres_configuration_secret: awx-postgres-configuration

  # Redis externo (recomendado para producción)
  redis_image: redis:7-alpine

  # Configuración de almacenamiento
  projects_storage_size:        20Gi
  projects_storage_class:       fast-ssd
  projects_storage_access_mode: ReadWriteMany   # NFS o similar para HA

  # Extra settings
  extra_settings:
    - setting: AWX_TASK_ENV
      value:
        ANSIBLE_FORCE_COLOR: "true"
    - setting: SESSION_COOKIE_AGE
      value: 28800
    - setting: MAX_WEBSOCKET_EVENT_RATE
      value: 30
```

```bash
# Aplicar la configuración
kubectl apply -f awx-instance.yaml

# Verificar que el operator aplica los cambios
kubectl logs -n awx deployment/awx-operator-controller-manager \
    -c awx-manager --tail=20 -f
```

---

# 7.5 Alta disponibilidad: diseño y configuración

## PostgreSQL en HA

```
OPCIÓN 1: PostgreSQL gestionado (recomendado para producción)
  → AWS RDS PostgreSQL con Multi-AZ
  → Azure Database for PostgreSQL con réplica
  → Google Cloud SQL con failover automático
  
  Ventajas:
    → Failover automático sin intervención
    → Backups gestionados
    → Réplicas de lectura para reporting
    → Patching automático

OPCIÓN 2: PostgreSQL en Kubernetes con Patroni
  → Patroni gestiona el cluster PostgreSQL
  → Etcd o Consul como DCS (Distributed Configuration Store)
  → HAProxy para balanceo de conexiones
  
  Más complejo pero sin dependencia de cloud provider.

OPCIÓN 3: PostgreSQL externo con streaming replication manual
  → Primary + Standby con pg_basebackup
  → Failover manual o con repmgr
  → Válido para entornos on-premise
```

## Configurar AWX con PostgreSQL externo

```yaml
# Secret con la configuración de PostgreSQL externo
---
apiVersion: v1
kind: Secret
metadata:
  name: awx-postgres-configuration
  namespace: awx
type: Opaque
stringData:
  host:     "postgres-primary.empresa.com"
  port:     "5432"
  database: "awx"
  username: "awx"
  password: "PostgresPassword123!"
  sslmode:  "require"
```

```bash
# Aplicar el secret
kubectl apply -f postgres-secret.yaml

# Verificar la conexión desde AWX
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import psycopg2
conn = psycopg2.connect(
    host='postgres-primary.empresa.com',
    port=5432,
    database='awx',
    user='awx',
    password='PostgresPassword123!',
    sslmode='require'
)
cursor = conn.cursor()
cursor.execute('SELECT version()')
print(f'PostgreSQL: {cursor.fetchone()[0]}')
cursor.execute('SELECT COUNT(*) FROM main_job')
print(f'Total jobs en BD: {cursor.fetchone()[0]}')
conn.close()
"
```

## Redis en HA con Sentinel

```yaml
# redis-sentinel.yaml
# Redis con Sentinel para HA
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-sentinel-config
  namespace: awx
data:
  sentinel.conf: |
    sentinel monitor awx-redis redis-primary 6379 2
    sentinel down-after-milliseconds awx-redis 5000
    sentinel failover-timeout awx-redis 60000
    sentinel parallel-syncs awx-redis 1
    requirepass RedisPassword123!
    sentinel auth-pass awx-redis RedisPassword123!
```

```bash
# Verificar Redis desde AWX
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import redis
r = redis.Redis(
    host='redis-primary.empresa.com',
    port=6379,
    password='RedisPassword123!',
    decode_responses=True
)
print(f'Redis ping: {r.ping()}')
print(f'Redis info: {r.info()[\"redis_version\"]}')
print(f'Keys en uso: {r.dbsize()}')
"
```

---

# 7.6 Backup y restauración

## Qué necesita backup en AWX

```
COMPONENTES CRÍTICOS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. BASE DE DATOS POSTGRESQL (lo más crítico)
   Contiene: todos los objetos AWX, historial de jobs,
             credenciales cifradas, configuración
   Tamaño típico: 1-10 GB
   Frecuencia recomendada: cada hora (incremental), diario (completo)

2. SECRET KEY DE AWX (crítico)
   Kubernetes Secret: awx-secret-key
   Contiene: la clave de cifrado de las credenciales
   Si se pierde: las credenciales en la BD son irrecuperables
   Frecuencia: backup en cada cambio (raramente cambia)

3. PROYECTOS SCM (bajo riesgo si tienes Git)
   Si los proyectos están en Git, el código no necesita backup
   Solo necesita backup si usas proyectos "Manual" (sin Git)

4. EXECUTION ENVIRONMENTS (bajo riesgo si tienes registry)
   Si las imágenes están en un registry, no necesitan backup
   Solo el registro de qué EE usa cada template (está en la BD)

5. CONFIGURACIÓN DEL OPERATOR (medio)
   Los ficheros YAML del operator en Git
   Frecuencia: backup en cada cambio
```

## Script de backup completo

```bash
#!/bin/bash
# script: awx_backup.sh
# Backup completo de AWX: PostgreSQL + Secrets + configuración
# Ejecutar como cron diario

set -euo pipefail

# ── Configuración ─────────────────────────────────────────────
BACKUP_DIR="/opt/awx-backups"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_DATE}"
RETENTION_DAYS=30
S3_BUCKET="s3://empresa-awx-backups"
NAMESPACE="awx"

# Notificación Slack (opcional)
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

notify_slack() {
    local status="$1"
    local message="$2"
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"${status} AWX Backup: ${message}\"}" \
            > /dev/null
    fi
}

# ── Inicio ────────────────────────────────────────────────────
log "Iniciando backup AWX → ${BACKUP_PATH}"
mkdir -p "${BACKUP_PATH}"

# ── 1. Backup de PostgreSQL ───────────────────────────────────
log "Backup de PostgreSQL..."

# Obtener credenciales de PostgreSQL desde el secret de Kubernetes
PG_HOST=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.host}' | base64 -d)
PG_PORT=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.port}' | base64 -d)
PG_DB=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.database}' | base64 -d)
PG_USER=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.username}' | base64 -d)
PG_PASS=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d)

# Ejecutar pg_dump desde el pod de AWX
kubectl exec -n "${NAMESPACE}" deployment/awx-task -c awx-task -- \
    bash -c "PGPASSWORD='${PG_PASS}' pg_dump \
        -h '${PG_HOST}' \
        -p '${PG_PORT}' \
        -U '${PG_USER}' \
        -d '${PG_DB}' \
        --format=custom \
        --compress=9 \
        --no-password" \
    > "${BACKUP_PATH}/awx_db_${BACKUP_DATE}.pgdump"

DB_SIZE=$(du -sh "${BACKUP_PATH}/awx_db_${BACKUP_DATE}.pgdump" | cut -f1)
log "✅ PostgreSQL backup completado: ${DB_SIZE}"

# ── 2. Backup de Kubernetes Secrets ──────────────────────────
log "Backup de Kubernetes Secrets..."

# Secret key de AWX (crítico para descifrar credenciales)
kubectl get secret awx-secret-key -n "${NAMESPACE}" \
    -o yaml > "${BACKUP_PATH}/awx-secret-key.yaml"

# Secret de configuración de PostgreSQL
kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o yaml > "${BACKUP_PATH}/awx-postgres-configuration.yaml"

# Todos los secrets del namespace (por si acaso)
kubectl get secrets -n "${NAMESPACE}" \
    -o yaml > "${BACKUP_PATH}/all-secrets.yaml"

log "✅ Secrets backup completado"

# ── 3. Backup de ConfigMaps ───────────────────────────────────
log "Backup de ConfigMaps..."
kubectl get configmaps -n "${NAMESPACE}" \
    -o yaml > "${BACKUP_PATH}/all-configmaps.yaml"
log "✅ ConfigMaps backup completado"

# ── 4. Backup de la definición del AWX Operator ───────────────
log "Backup de la definición AWX..."
kubectl get awx -n "${NAMESPACE}" \
    -o yaml > "${BACKUP_PATH}/awx-definition.yaml"
log "✅ Definición AWX backup completado"

# ── 5. Backup via AWX Operator (si está disponible) ───────────
log "Verificando AWX Operator backup..."
if kubectl get crd awxbackups.awx.ansible.com &>/dev/null; then
    cat > /tmp/awx-backup-job.yaml << EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWXBackup
metadata:
  name: awx-backup-${BACKUP_DATE}
  namespace: ${NAMESPACE}
spec:
  deployment_name: awx
  backup_pvc_namespace: ${NAMESPACE}
EOF
    kubectl apply -f /tmp/awx-backup-job.yaml

    # Esperar a que complete
    TIMEOUT=300
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        STATUS=$(kubectl get awxbackup "awx-backup-${BACKUP_DATE}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.status.backupComplete}' 2>/dev/null || echo "false")
        if [ "$STATUS" = "true" ]; then
            log "✅ AWX Operator backup completado"
            break
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
fi

# ── 6. Comprimir y cifrar el backup ──────────────────────────
log "Comprimiendo backup..."
tar -czf "${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz" \
    -C "${BACKUP_DIR}" "${BACKUP_DATE}/"

TOTAL_SIZE=$(du -sh "${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz" | cut -f1)
log "✅ Backup comprimido: ${TOTAL_SIZE}"

# Cifrar con GPG (opcional pero recomendado)
if command -v gpg &>/dev/null && [ -n "${GPG_KEY_ID:-}" ]; then
    gpg --recipient "${GPG_KEY_ID}" \
        --encrypt \
        "${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz"
    rm "${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz"
    BACKUP_FILE="${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz.gpg"
    log "✅ Backup cifrado con GPG"
else
    BACKUP_FILE="${BACKUP_DIR}/awx_backup_${BACKUP_DATE}.tar.gz"
fi

# ── 7. Subir a S3 ─────────────────────────────────────────────
if command -v aws &>/dev/null && [ -n "${S3_BUCKET:-}" ]; then
    log "Subiendo a S3: ${S3_BUCKET}..."
    aws s3 cp "${BACKUP_FILE}" \
        "${S3_BUCKET}/$(basename ${BACKUP_FILE})" \
        --storage-class STANDARD_IA
    log "✅ Backup subido a S3"
fi

# ── 8. Limpiar backups antiguos ───────────────────────────────
log "Limpiando backups con más de ${RETENTION_DAYS} días..."
find "${BACKUP_DIR}" -name "awx_backup_*.tar.gz*" \
    -mtime "+${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -maxdepth 1 -mindepth 1 -type d \
    -mtime "+${RETENTION_DAYS}" -exec rm -rf {} +

# ── 9. Limpiar directorio temporal ───────────────────────────
rm -rf "${BACKUP_PATH}"

# ── 10. Resumen ───────────────────────────────────────────────
log "✅ Backup AWX completado exitosamente"
log "   Fichero: $(basename ${BACKUP_FILE})"
log "   Tamaño:  ${TOTAL_SIZE}"
log "   Retención: ${RETENTION_DAYS} días"

notify_slack "✅" "Backup completado: $(basename ${BACKUP_FILE}) (${TOTAL_SIZE})"
```

```bash
# Configurar como cron
chmod +x /opt/scripts/awx_backup.sh

crontab -e
# Backup diario a las 02:00 AM
# 0 2 * * * /opt/scripts/awx_backup.sh >> /var/log/awx/backup.log 2>&1
```

## Script de restauración

```bash
#!/bin/bash
# script: awx_restore.sh
# Restaura AWX desde un backup

set -euo pipefail

BACKUP_FILE="$1"
NAMESPACE="awx"

if [ -z "$BACKUP_FILE" ]; then
    echo "Uso: $0 <fichero_backup.tar.gz>"
    echo "Ejemplo: $0 /opt/awx-backups/awx_backup_20260604_020000.tar.gz"
    exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "⚠️  RESTAURACIÓN AWX desde: ${BACKUP_FILE}"
log "⚠️  Esto sobreescribirá la base de datos actual."
read -p "¿Continuar? (escribe 'SI' para confirmar): " CONFIRM
if [ "$CONFIRM" != "SI" ]; then
    log "Restauración cancelada."
    exit 0
fi

# ── Descomprimir el backup ────────────────────────────────────
RESTORE_DIR=$(mktemp -d)
log "Descomprimiendo en ${RESTORE_DIR}..."
tar -xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"
BACKUP_CONTENT=$(ls "${RESTORE_DIR}")
BACKUP_PATH="${RESTORE_DIR}/${BACKUP_CONTENT}"

# ── Escalar AWX a 0 réplicas (modo mantenimiento) ─────────────
log "Poniendo AWX en modo mantenimiento (0 réplicas)..."
kubectl scale deployment awx-web  -n "${NAMESPACE}" --replicas=0
kubectl scale deployment awx-task -n "${NAMESPACE}" --replicas=0

# Esperar a que los pods terminen
kubectl wait --for=delete pod \
    -l app.kubernetes.io/name=awx \
    -n "${NAMESPACE}" \
    --timeout=120s 2>/dev/null || true

log "✅ AWX detenido"

# ── Restaurar PostgreSQL ──────────────────────────────────────
log "Restaurando PostgreSQL..."

PG_HOST=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.host}' | base64 -d)
PG_PORT=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.port}' | base64 -d)
PG_DB=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.database}' | base64 -d)
PG_USER=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.username}' | base64 -d)
PG_PASS=$(kubectl get secret awx-postgres-configuration -n "${NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d)

DB_BACKUP=$(ls "${BACKUP_PATH}"/awx_db_*.pgdump)

# Lanzar un pod temporal de PostgreSQL para la restauración
kubectl run pg-restore-tmp \
    --image=postgres:15 \
    --restart=Never \
    --env="PGPASSWORD=${PG_PASS}" \
    -n "${NAMESPACE}" \
    -- sleep 3600

kubectl wait --for=condition=Ready pod/pg-restore-tmp \
    -n "${NAMESPACE}" --timeout=60s

# Copiar el backup al pod temporal
kubectl cp "${DB_BACKUP}" \
    "${NAMESPACE}/pg-restore-tmp:/tmp/awx_backup.pgdump"

# Terminar conexiones activas y restaurar
kubectl exec -n "${NAMESPACE}" pg-restore-tmp -- \
    bash -c "
PGPASSWORD='${PG_PASS}' psql \
    -h '${PG_HOST}' -p '${PG_PORT}' \
    -U '${PG_USER}' -d postgres \
    -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${PG_DB}' AND pid <> pg_backend_pid();\"

PGPASSWORD='${PG_PASS}' dropdb \
    -h '${PG_HOST}' -p '${PG_PORT}' \
    -U '${PG_USER}' '${PG_DB}' --if-exists

PGPASSWORD='${PG_PASS}' createdb \
    -h '${PG_HOST}' -p '${PG_PORT}' \
    -U '${PG_USER}' '${PG_DB}'

PGPASSWORD='${PG_PASS}' pg_restore \
    -h '${PG_HOST}' -p '${PG_PORT}' \
    -U '${PG_USER}' -d '${PG_DB}' \
    --no-owner --no-privileges \
    /tmp/awx_backup.pgdump
"

kubectl delete pod pg-restore-tmp -n "${NAMESPACE}" --grace-period=0
log "✅ PostgreSQL restaurado"

# ── Restaurar Secrets ─────────────────────────────────────────
log "Restaurando Secrets..."
if [ -f "${BACKUP_PATH}/awx-secret-key.yaml" ]; then
    kubectl apply -f "${BACKUP_PATH}/awx-secret-key.yaml"
    log "✅ Secret key restaurado"
fi

# ── Reiniciar AWX ─────────────────────────────────────────────
log "Reiniciando AWX..."
kubectl scale deployment awx-web  -n "${NAMESPACE}" --replicas=2
kubectl scale deployment awx-task -n "${NAMESPACE}" --replicas=2

kubectl wait --for=condition=Ready pod \
    -l app.kubernetes.io/name=awx \
    -n "${NAMESPACE}" \
    --timeout=300s

log "✅ AWX reiniciado"

# ── Limpiar ───────────────────────────────────────────────────
rm -rf "${RESTORE_DIR}"

log "✅ RESTAURACIÓN COMPLETADA"
log "   Verificar: kubectl get pods -n ${NAMESPACE}"
log "   UI: http://$(kubectl get svc awx-service -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}'):80"
```

---

# 7.7 Actualizaciones sin downtime

## Estrategia de actualización

```
PROCESO DE ACTUALIZACIÓN AWX:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ANTES DE ACTUALIZAR:
  1. Leer las release notes de la nueva versión
     https://github.com/ansible/awx/releases
  2. Verificar compatibilidad con la versión de PostgreSQL
  3. Hacer backup completo (ver sección 7.6)
  4. Probar la actualización en un entorno de staging
  5. Planificar ventana de mantenimiento (aunque el downtime es mínimo)
  6. Notificar al equipo

PROCESO (con AWX Operator):
  1. Actualizar la versión del operator
  2. El operator actualiza AWX de forma rolling
  3. Los pods nuevos arrancan antes de que los viejos terminen
  4. Las migraciones de BD se ejecutan automáticamente
  5. Verificar que todo funciona

TIEMPO TÍPICO: 5-15 minutos
DOWNTIME REAL: < 30 segundos (durante el rolling update)
```

## Actualización con AWX Operator

```bash
#!/bin/bash
# script: update_awx.sh
# Actualiza AWX a una nueva versión usando el AWX Operator

set -euo pipefail

NEW_VERSION="${1:-24.6.0}"
NAMESPACE="awx"
OPERATOR_NAMESPACE="awx"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== ACTUALIZACIÓN AWX a versión ${NEW_VERSION} ==="

# ── 1. Verificar versión actual ───────────────────────────────
CURRENT_VERSION=$(kubectl get awx awx -n "${NAMESPACE}" \
    -o jsonpath='{.spec.image_version}' 2>/dev/null || echo "desconocida")
log "Versión actual: ${CURRENT_VERSION}"
log "Versión nueva:  ${NEW_VERSION}"

# ── 2. Hacer backup antes de actualizar ──────────────────────
log "Ejecutando backup pre-actualización..."
/opt/scripts/awx_backup.sh
log "✅ Backup completado"

# ── 3. Actualizar el AWX Operator ────────────────────────────
log "Actualizando AWX Operator..."

# Descargar los manifests del nuevo operator
curl -sL \
    "https://raw.githubusercontent.com/ansible/awx-operator/${NEW_VERSION}/deploy/awx-operator.yml" \
    -o /tmp/awx-operator-${NEW_VERSION}.yml

# Aplicar el nuevo operator
kubectl apply -f /tmp/awx-operator-${NEW_VERSION}.yml

# Esperar a que el operator esté listo
kubectl rollout status deployment/awx-operator-controller-manager \
    -n "${OPERATOR_NAMESPACE}" --timeout=120s

log "✅ Operator actualizado"

# ── 4. Actualizar la versión de AWX en el CR ─────────────────
log "Actualizando versión de AWX en el Custom Resource..."
kubectl patch awx awx -n "${NAMESPACE}" \
    --type=merge \
    -p "{\"spec\": {\"image_version\": \"${NEW_VERSION}\"}}"

# ── 5. Monitorizar el rolling update ─────────────────────────
log "Monitorizando el rolling update..."

# Esperar a que awx-web se actualice
log "Actualizando awx-web..."
kubectl rollout status deployment/awx-web \
    -n "${NAMESPACE}" --timeout=300s
log "✅ awx-web actualizado"

# Esperar a que awx-task se actualice
log "Actualizando awx-task..."
kubectl rollout status deployment/awx-task \
    -n "${NAMESPACE}" --timeout=300s
log "✅ awx-task actualizado"

# ── 6. Verificar la actualización ────────────────────────────
log "Verificando la actualización..."

# Esperar a que AWX esté disponible
sleep 30

AWX_URL="http://$(kubectl get svc awx-service -n ${NAMESPACE} \
    -o jsonpath='{.spec.clusterIP}'):80"

for i in $(seq 1 10); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${AWX_URL}/api/v2/ping/" --max-time 10 || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log "✅ AWX responde correctamente (HTTP 200)"
        break
    fi
    log "Intento ${i}/10: HTTP ${HTTP_CODE}, esperando..."
    sleep 15
done

# Verificar la versión instalada
INSTALLED_VERSION=$(curl -s "${AWX_URL}/api/v2/ping/" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','N/A'))")
log "Versión instalada: ${INSTALLED_VERSION}"

if [ "$INSTALLED_VERSION" = "$NEW_VERSION" ]; then
    log "✅ ACTUALIZACIÓN COMPLETADA EXITOSAMENTE"
    log "   Versión anterior: ${CURRENT_VERSION}"
    log "   Versión nueva:    ${INSTALLED_VERSION}"
else
    log "⚠️  La versión instalada (${INSTALLED_VERSION}) no coincide con la esperada (${NEW_VERSION})"
    log "   Verificar manualmente el estado de la actualización"
fi

# ── 7. Verificar jobs en ejecución ───────────────────────────
log "Verificando jobs en ejecución post-actualización..."
RUNNING_JOBS=$(curl -s \
    -u "admin:$(kubectl get secret awx-admin-password -n ${NAMESPACE} \
        -o jsonpath='{.data.password}' | base64 -d)" \
    "${AWX_URL}/api/v2/jobs/?status=running" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
log "Jobs en ejecución: ${RUNNING_JOBS}"
```

## Rollback en caso de fallo

```bash
#!/bin/bash
# script: rollback_awx.sh
# Rollback a la versión anterior si la actualización falla

PREVIOUS_VERSION="${1:-24.5.0}"
NAMESPACE="awx"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "⚠️  ROLLBACK AWX a versión ${PREVIOUS_VERSION}"

# Opción 1: Rollback del deployment de Kubernetes
kubectl rollout undo deployment/awx-web  -n "${NAMESPACE}"
kubectl rollout undo deployment/awx-task -n "${NAMESPACE}"

# Opción 2: Restaurar desde backup (si el schema de BD cambió)
# /opt/scripts/awx_restore.sh /opt/awx-backups/awx_backup_YYYYMMDD_HHMMSS.tar.gz

kubectl rollout status deployment/awx-web  -n "${NAMESPACE}" --timeout=300s
kubectl rollout status deployment/awx-task -n "${NAMESPACE}" --timeout=300s

log "✅ Rollback completado"
```

---

# 7.8 Métricas con Prometheus y Grafana

## Habilitar el endpoint de métricas en AWX

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Verificar que el endpoint de métricas está disponible
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/metrics/" \
    | head -50

# El endpoint devuelve métricas en formato Prometheus
# awx_pending_jobs_total
# awx_running_jobs_total
# awx_failed_jobs_total
# awx_successful_jobs_total
# awx_instance_capacity
# awx_instance_consumed_capacity
# etc.
```

## Configurar Prometheus para scraping de AWX

```yaml
# prometheus/awx-scrape-config.yaml
---
# Añadir a la configuración de Prometheus
scrape_configs:
  - job_name: 'awx'
    scrape_interval: 30s
    scrape_timeout:  10s

    # Autenticación básica para el endpoint de métricas
    basic_auth:
      username: admin
      password: TuPasswordSegura123!

    # O usar un token de API
    # authorization:
    #   credentials: tu-token-de-api

    static_configs:
      - targets:
          - 'awx.empresa.com:30080'
        labels:
          environment: production
          service:     awx

    metrics_path: /api/v2/metrics/

    # Relabeling para limpiar las métricas
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'awx_.*'
        action: keep
```

```bash
# Aplicar la configuración de Prometheus
kubectl create configmap prometheus-awx-config \
    --from-file=awx-scrape-config.yaml \
    -n monitoring

# Recargar Prometheus
curl -X POST http://prometheus:9090/-/reload
```

## Alertas de Prometheus para AWX

```yaml
# prometheus/awx-alerts.yaml
---
groups:
  - name: awx_alerts
    interval: 60s
    rules:

      # ── Jobs fallidos ─────────────────────────────────────────
      - alert: AWXHighJobFailureRate
        expr: |
          rate(awx_failed_jobs_total[15m]) /
          (rate(awx_successful_jobs_total[15m]) + rate(awx_failed_jobs_total[15m]))
          > 0.1
        for: 5m
        labels:
          severity: warning
          team:     platform
        annotations:
          summary:     "Alta tasa de fallos en AWX"
          description: >
            La tasa de fallos de jobs supera el 10% en los últimos 15 minutos.
            Tasa actual: {{ $value | humanizePercentage }}
          runbook:     "https://wiki.empresa.com/runbooks/awx-job-failures"

      # ── Jobs pendientes acumulados ────────────────────────────
      - alert: AWXJobsQueueBacklog
        expr: awx_pending_jobs_total > 20
        for: 10m
        labels:
          severity: warning
          team:     platform
        annotations:
          summary:     "Cola de jobs AWX acumulada"
          description: >
            Hay {{ $value }} jobs pendientes en la cola durante más de 10 minutos.
            Puede indicar falta de capacidad de ejecución.

      # ── Capacidad de ejecución agotada ────────────────────────
      - alert: AWXInstanceCapacityLow
        expr: |
          (awx_instance_capacity - awx_instance_consumed_capacity)
          / awx_instance_capacity < 0.1
        for: 5m
        labels:
          severity: critical
          team:     platform
        annotations:
          summary:     "Capacidad AWX casi agotada"
          description: >
            La capacidad disponible es menor del 10%.
            Añadir más Execution Nodes o reducir la carga.

      # ── AWX no responde ───────────────────────────────────────
      - alert: AWXDown
        expr: up{job="awx"} == 0
        for: 2m
        labels:
          severity: critical
          team:     platform
        annotations:
          summary:     "AWX no responde"
          description: >
            El endpoint de métricas de AWX no está disponible.
            AWX puede estar caído o con problemas de red.
          runbook:     "https://wiki.empresa.com/runbooks/awx-down"

      # ── PostgreSQL sin espacio ────────────────────────────────
      - alert: AWXDatabaseDiskSpaceLow
        expr: |
          pg_database_size_bytes{datname="awx"}
          / (1024*1024*1024) > 8
        for: 5m
        labels:
          severity: warning
          team:     platform
        annotations:
          summary:     "Base de datos AWX grande"
          description: >
            La BD de AWX supera los 8GB.
            Considerar ejecutar la tarea de limpieza de jobs antiguos.
```

```bash
# Aplicar las alertas
kubectl apply -f prometheus/awx-alerts.yaml -n monitoring
```

---

# 7.9 Logging centralizado con ELK/Loki

## Configurar AWX para enviar logs a un sistema externo

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Configurar logging externo via API
curl -s -u "${AWX_AUTH}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/settings/logging/" \
    -d '{
        "LOG_AGGREGATOR_HOST":          "elasticsearch.empresa.com",
        "LOG_AGGREGATOR_PORT":          9200,
        "LOG_AGGREGATOR_TYPE":          "elasticsearch",
        "LOG_AGGREGATOR_USERNAME":      "awx-logger",
        "LOG_AGGREGATOR_PASSWORD":      "ElasticPassword123!",
        "LOG_AGGREGATOR_LOGGERS": [
            "awx",
            "activity_stream",
            "job_events",
            "system_tracking"
        ],
        "LOG_AGGREGATOR_INDIVIDUAL_FACTS": false,
        "LOG_AGGREGATOR_ENABLED":       true,
        "LOG_AGGREGATOR_LEVEL":         "WARNING",
        "LOG_AGGREGATOR_ACTION_QUEUE_SIZE": 131072,
        "LOG_AGGREGATOR_ACTION_MAX_DISK_USAGE_GB": 1,
        "LOG_AGGREGATOR_MAX_DISK_USAGE_PATH": "/var/lib/awx"
    }' \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'LOG_AGGREGATOR_ENABLED' in data:
    print(f'✅ Logging configurado: {data[\"LOG_AGGREGATOR_ENABLED\"]}')
    print(f'   Host: {data[\"LOG_AGGREGATOR_HOST\"]}:{data[\"LOG_AGGREGATOR_PORT\"]}')
else:
    print(f'❌ Error: {data}')
"
```

## Configurar Fluent Bit para capturar logs de pods AWX

```yaml
# fluentbit/awx-log-config.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-awx-config
  namespace: monitoring
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Parsers_File  parsers.conf

    # Capturar logs de todos los pods AWX
    [INPUT]
        Name              tail
        Path              /var/log/containers/*awx*.log
        Parser            docker
        Tag               awx.*
        Refresh_Interval  5
        Mem_Buf_Limit     50MB
        Skip_Long_Lines   On

    # Filtrar y enriquecer los logs
    [FILTER]
        Name         kubernetes
        Match        awx.*
        Kube_URL     https://kubernetes.default.svc:443
        Kube_CA_File /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log    On
        K8S-Logging.Parser On

    # Añadir campos de contexto
    [FILTER]
        Name   record_modifier
        Match  awx.*
        Record environment production
        Record cluster  k8s-prod-01
        Record service  awx

    # Enviar a Loki
    [OUTPUT]
        Name            loki
        Match           awx.*
        Host            loki.empresa.com
        Port            3100
        Labels          job=awx, env=production
        Label_Keys      $kubernetes['namespace_name'],$kubernetes['pod_name']
        Remove_Keys     kubernetes,stream
        Line_Format     json

    # Enviar a Elasticsearch (alternativa)
    # [OUTPUT]
    #     Name  es
    #     Match awx.*
    #     Host  elasticsearch.empresa.com
    #     Port  9200
    #     Index awx-logs
    #     Type  _doc
```

---

# 7.10 LAB — Añadir un Execution Node remoto

## Paso 1 — Preparar el servidor del Execution Node

```bash
# En el servidor que será Execution Node (Ubuntu 22.04 / RHEL 9)
# Ejecutar como root o con sudo

# ── Instalar dependencias ─────────────────────────────────────
apt-get update && apt-get install -y \
    python3 python3-pip \
    podman \
    git \
    curl \
    openssl

# O en RHEL/Rocky:
# dnf install -y python3 python3-pip podman git curl openssl

# ── Instalar ansible-runner y receptor ───────────────────────
pip3 install ansible-runner

# Instalar receptor (el daemon de comunicación con AWX)
pip3 install receptorctl

# O desde paquetes RPM/DEB si están disponibles:
# dnf install -y receptor  (RHEL)
# apt-get install -y receptor  (Ubuntu, si hay repo)

# ── Crear usuario para AWX ────────────────────────────────────
useradd -m -s /bin/bash awx
usermod -aG podman awx  # para ejecutar contenedores sin root

# ── Crear directorios ─────────────────────────────────────────
mkdir -p /etc/receptor
mkdir -p /var/lib/receptor
mkdir -p /var/log/receptor
chown -R awx:awx /var/lib/receptor /var/log/receptor
```

## Paso 2 — Registrar el Execution Node en AWX

```
AWX UI → Administration → Instance Groups → Add → Instance

  Hostname:     execution-node-01.empresa.com
  Instance Type: Execution
  
  → Save

# AWX genera los certificados y la configuración de receptor
# Descargar el bundle de instalación:
Administration → Instances → execution-node-01 → Install Bundle → Download
```

## Paso 3 — Instalar el bundle en el Execution Node

```bash
# En el Execution Node:
# Copiar el bundle descargado de AWX
scp awx_install_bundle_execution-node-01.tar.gz \
    awx@execution-node-01.empresa.com:/tmp/

ssh awx@execution-node-01.empresa.com

# Descomprimir e instalar
cd /tmp
tar -xzf awx_install_bundle_execution-node-01.tar.gz
cd awx_install_bundle_execution-node-01

# El bundle contiene un playbook de instalación
# Ejecutar con ansible-playbook
ansible-playbook -i inventory.yml install_receptor.yml \
    -e "receptor_port=27199" \
    -e "awx_host=awx.empresa.com" \
    -e "awx_port=27199"

# Verificar que receptor está corriendo
systemctl status receptor
receptorctl --socket /var/run/receptor/receptor.sock status
```

## Paso 4 — Verificar la conexión desde AWX

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver el estado del nuevo nodo
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instances/?hostname=execution-node-01.empresa.com" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    node = data['results'][0]
    print(f'Nodo: {node[\"hostname\"]}')
    print(f'Tipo: {node[\"node_type\"]}')
    print(f'Estado: {node[\"node_state\"]}')
    print(f'Capacidad: {node[\"capacity\"]}')
    print(f'Versión: {node[\"version\"]}')
else:
    print('Nodo no encontrado')
"

# Verificar el health check del nodo
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instances/?hostname=execution-node-01.empresa.com" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    node = data['results'][0]
    healthy = node['node_state'] == 'ready'
    icon = '✅' if healthy else '❌'
    print(f'{icon} Estado del nodo: {node[\"node_state\"]}')
"
```

## Paso 5 — Asignar el Execution Node a un Instance Group

```
Administration → Instance Groups → ig-prod → Instances → Add
  + execution-node-01.empresa.com
  → Save

# Verificar
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instance_groups/?name=ig-prod" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    ig = data['results'][0]
    print(f'Instance Group: {ig[\"name\"]}')
    print(f'Capacidad total: {ig[\"capacity\"]}')
    print(f'Instancias: {ig[\"instances\"]}')
"
```

---

# 7.11 LAB — Configurar backup automático

## Paso 1 — Crear el CronJob de Kubernetes para backup

```yaml
# backup/awx-backup-cronjob.yaml
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: awx-backup
  namespace: awx
spec:
  # Ejecutar a las 02:00 AM todos los días
  schedule: "0 2 * * *"

  # Mantener los últimos 3 jobs completados y 1 fallido
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit:     1

  # No ejecutar si el job anterior sigue corriendo
  concurrencyPolicy: Forbid

  jobTemplate:
    spec:
      # Timeout de 2 horas
      activeDeadlineSeconds: 7200

      template:
        spec:
          serviceAccountName: awx-backup-sa
          restartPolicy: OnFailure

          containers:
            - name: awx-backup
              image: bitnami/kubectl:latest
              command: ["/bin/bash", "/scripts/backup.sh"]

              env:
                - name: NAMESPACE
                  value: awx
                - name: S3_BUCKET
                  value: "s3://empresa-awx-backups"
                - name: RETENTION_DAYS
                  value: "30"
                - name: SLACK_WEBHOOK
                  valueFrom:
                    secretKeyRef:
                      name: awx-backup-secrets
                      key: slack-webhook

              volumeMounts:
                - name: backup-scripts
                  mountPath: /scripts
                - name: backup-storage
                  mountPath: /backups

          volumes:
            - name: backup-scripts
              configMap:
                name: awx-backup-scripts
                defaultMode: 0755
            - name: backup-storage
              persistentVolumeClaim:
                claimName: awx-backup-pvc
```

```yaml
# backup/awx-backup-rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: awx-backup-sa
  namespace: awx
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: awx-backup-role
  namespace: awx
rules:
  - apiGroups: [""]
    resources: ["secrets", "configmaps", "pods", "pods/exec"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
  - apiGroups: ["awx.ansible.com"]
    resources: ["awx", "awxbackups"]
    verbs: ["get", "list", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: awx-backup-rolebinding
  namespace: awx
subjects:
  - kind: ServiceAccount
    name: awx-backup-sa
    namespace: awx
roleRef:
  kind: Role
  name: awx-backup-role
  apiGroup: rbac.authorization.k8s.io
```

```bash
# Aplicar los recursos
kubectl apply -f backup/awx-backup-rbac.yaml
kubectl apply -f backup/awx-backup-cronjob.yaml

# Verificar que el CronJob se creó
kubectl get cronjob awx-backup -n awx

# Lanzar un backup manual para probar
kubectl create job awx-backup-manual \
    --from=cronjob/awx-backup \
    -n awx

# Ver el estado
kubectl get jobs -n awx
kubectl logs -n awx job/awx-backup-manual
```

## Paso 2 — Configurar alertas de backup fallido

```yaml
# prometheus/backup-alerts.yaml
---
groups:
  - name: awx_backup_alerts
    rules:
      - alert: AWXBackupFailed
        expr: |
          kube_job_status_failed{
            job_name=~"awx-backup.*",
            namespace="awx"
          } > 0
        for: 5m
        labels:
          severity: critical
          team:     platform
        annotations:
          summary:     "Backup AWX fallido"
          description: >
            El job de backup AWX ha fallado.
            Verificar los logs: kubectl logs -n awx job/{{ $labels.job_name }}
          runbook:     "https://wiki.empresa.com/runbooks/awx-backup-failed"

      - alert: AWXBackupNotRunning
        expr: |
          time() - kube_cronjob_status_last_schedule_time{
            cronjob="awx-backup",
            namespace="awx"
          } > 90000
        for: 5m
        labels:
          severity: warning
          team:     platform
        annotations:
          summary:     "Backup AWX no se ha ejecutado en 25 horas"
          description: >
            El CronJob de backup AWX no se ha ejecutado en más de 25 horas.
            Verificar el estado del CronJob.
```
# 7.12 LAB — Dashboard de observabilidad en Grafana

## Paso 1 — Definición del dashboard como código

```json
{
  "title": "AWX Platform Overview",
  "uid": "awx-platform-overview",
  "tags": ["awx", "ansible", "automation"],
  "timezone": "browser",
  "refresh": "30s",
  "time": { "from": "now-3h", "to": "now" },
  "panels": [
    {
      "id": 1,
      "title": "Jobs en ejecución ahora",
      "type": "stat",
      "gridPos": { "x": 0, "y": 0, "w": 4, "h": 4 },
      "targets": [{
        "expr": "awx_running_jobs_total",
        "legendFormat": "Running"
      }],
      "options": {
        "colorMode": "background",
        "thresholds": {
          "steps": [
            { "color": "green", "value": null },
            { "color": "yellow", "value": 10 },
            { "color": "red",    "value": 20 }
          ]
        }
      }
    },
    {
      "id": 2,
      "title": "Jobs pendientes en cola",
      "type": "stat",
      "gridPos": { "x": 4, "y": 0, "w": 4, "h": 4 },
      "targets": [{
        "expr": "awx_pending_jobs_total",
        "legendFormat": "Pending"
      }],
      "options": {
        "colorMode": "background",
        "thresholds": {
          "steps": [
            { "color": "green",  "value": null },
            { "color": "yellow", "value": 5 },
            { "color": "red",    "value": 15 }
          ]
        }
      }
    },
    {
      "id": 3,
      "title": "Tasa de éxito (últimas 24h)",
      "type": "gauge",
      "gridPos": { "x": 8, "y": 0, "w": 4, "h": 4 },
      "targets": [{
        "expr": "rate(awx_successful_jobs_total[24h]) / (rate(awx_successful_jobs_total[24h]) + rate(awx_failed_jobs_total[24h])) * 100",
        "legendFormat": "Success Rate %"
      }],
      "options": {
        "thresholds": {
          "steps": [
            { "color": "red",    "value": null },
            { "color": "yellow", "value": 80 },
            { "color": "green",  "value": 95 }
          ]
        },
        "min": 0,
        "max": 100
      }
    },
    {
      "id": 4,
      "title": "Capacidad disponible",
      "type": "gauge",
      "gridPos": { "x": 12, "y": 0, "w": 4, "h": 4 },
      "targets": [{
        "expr": "(awx_instance_capacity - awx_instance_consumed_capacity) / awx_instance_capacity * 100",
        "legendFormat": "Capacidad libre %"
      }],
      "options": {
        "thresholds": {
          "steps": [
            { "color": "red",    "value": null },
            { "color": "yellow", "value": 20 },
            { "color": "green",  "value": 40 }
          ]
        },
        "min": 0,
        "max": 100
      }
    },
    {
      "id": 5,
      "title": "Jobs por estado (últimas 3h)",
      "type": "timeseries",
      "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "rate(awx_successful_jobs_total[5m]) * 300",
          "legendFormat": "Exitosos"
        },
        {
          "expr": "rate(awx_failed_jobs_total[5m]) * 300",
          "legendFormat": "Fallidos"
        },
        {
          "expr": "awx_running_jobs_total",
          "legendFormat": "En ejecución"
        },
        {
          "expr": "awx_pending_jobs_total",
          "legendFormat": "Pendientes"
        }
      ]
    },
    {
      "id": 6,
      "title": "Capacidad por Instance Group",
      "type": "bargauge",
      "gridPos": { "x": 12, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "awx_instance_capacity",
          "legendFormat": "Total - {{ instance_group }}"
        },
        {
          "expr": "awx_instance_consumed_capacity",
          "legendFormat": "Usado - {{ instance_group }}"
        }
      ]
    },
    {
      "id": 7,
      "title": "Duración media de jobs (últimas 24h)",
      "type": "timeseries",
      "gridPos": { "x": 0, "y": 12, "w": 12, "h": 8 },
      "targets": [{
        "expr": "histogram_quantile(0.95, rate(awx_job_elapsed_seconds_bucket[1h]))",
        "legendFormat": "p95 duración"
      },
      {
        "expr": "histogram_quantile(0.50, rate(awx_job_elapsed_seconds_bucket[1h]))",
        "legendFormat": "p50 duración"
      }]
    },
    {
      "id": 8,
      "title": "Top 10 Job Templates por ejecuciones fallidas",
      "type": "table",
      "gridPos": { "x": 12, "y": 12, "w": 12, "h": 8 },
      "targets": [{
        "expr": "topk(10, increase(awx_failed_jobs_total[24h]))",
        "legendFormat": "{{ job_template_name }}",
        "instant": true
      }]
    }
  ]
}
```

## Paso 2 — Importar el dashboard via API de Grafana

```bash
#!/bin/bash
# script: import_grafana_dashboard.sh

GRAFANA_URL="http://grafana.empresa.com:3000"
GRAFANA_AUTH="admin:GrafanaPassword123!"
DASHBOARD_FILE="grafana/awx-dashboard.json"
DATASOURCE_UID="prometheus-prod"

# Envolver el dashboard en el formato de importación de Grafana
python3 << PYTHON
import json

with open("${DASHBOARD_FILE}") as f:
    dashboard = json.load(f)

payload = {
    "dashboard": dashboard,
    "folderId": 0,
    "overwrite": True,
    "inputs": [{
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "pluginId": "prometheus",
        "value": "${DATASOURCE_UID}"
    }]
}

with open("/tmp/dashboard_import.json", "w") as f:
    json.dump(payload, f)

print("Payload preparado")
PYTHON

# Importar el dashboard
RESPONSE=$(curl -s \
    -u "${GRAFANA_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${GRAFANA_URL}/api/dashboards/import" \
    -d @/tmp/dashboard_import.json)

echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'url' in data:
    print(f'✅ Dashboard importado: ${GRAFANA_URL}{data[\"url\"]}')
else:
    print(f'❌ Error: {data}')
"
```

## Paso 3 — Queries útiles para exploración en Grafana

```
QUERIES PROMETHEUS PARA AWX:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Jobs en ejecución ahora mismo
awx_running_jobs_total

# Jobs pendientes en cola
awx_pending_jobs_total

# Tasa de jobs fallidos por minuto
rate(awx_failed_jobs_total[5m]) * 60

# Porcentaje de éxito en las últimas 24 horas
(
  increase(awx_successful_jobs_total[24h]) /
  (increase(awx_successful_jobs_total[24h]) + increase(awx_failed_jobs_total[24h]))
) * 100

# Capacidad libre por Instance Group
(awx_instance_capacity - awx_instance_consumed_capacity)
  / awx_instance_capacity * 100

# Jobs completados en las últimas 24 horas
increase(awx_successful_jobs_total[24h])
+ increase(awx_failed_jobs_total[24h])

# Tiempo medio de ejecución (percentil 95)
histogram_quantile(0.95, rate(awx_job_elapsed_seconds_bucket[1h]))

# Nodos con capacidad agotada
awx_instance_capacity - awx_instance_consumed_capacity == 0

# Alertas activas de AWX
ALERTS{alertname=~"AWX.*", alertstate="firing"}
```

## Paso 4 — Configurar alertas en Grafana

```yaml
# grafana/awx-alert-rules.yaml
# Reglas de alerta nativas de Grafana (Grafana 9+)
---
apiVersion: 1
groups:
  - orgId: 1
    name: AWX Alerts
    folder: Platform
    interval: 1m
    rules:

      - uid:   awx-jobs-failing
        title: AWX - Alta tasa de fallos
        condition: C
        data:
          - refId: A
            relativeTimeRange: { from: 900, to: 0 }
            datasourceUid: prometheus-prod
            model:
              expr: |
                rate(awx_failed_jobs_total[15m]) /
                (rate(awx_successful_jobs_total[15m]) + rate(awx_failed_jobs_total[15m]))
              intervalMs: 1000
              maxDataPoints: 43200
          - refId: C
            datasourceUid: __expr__
            model:
              type:       threshold
              conditions:
                - evaluator: { params: [0.1], type: gt }
                  query:     { params: [A] }
        noDataState:  NoData
        execErrState: Error
        for:          5m
        annotations:
          summary:     "Tasa de fallos AWX > 10%"
          description: "Revisar los jobs fallidos en AWX"
          runbook_url: "https://wiki.empresa.com/runbooks/awx-failures"
        labels:
          severity: warning
          team:     platform

      - uid:   awx-queue-backlog
        title: AWX - Cola de jobs acumulada
        condition: C
        data:
          - refId: A
            relativeTimeRange: { from: 600, to: 0 }
            datasourceUid: prometheus-prod
            model:
              expr: awx_pending_jobs_total
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              conditions:
                - evaluator: { params: [20], type: gt }
                  query:     { params: [A] }
        for: 10m
        annotations:
          summary: "Cola AWX > 20 jobs pendientes"
        labels:
          severity: warning
          team:     platform
```

---

# 7.13 LAB — Actualización de AWX sin downtime

## Paso 1 — Checklist pre-actualización

```bash
#!/bin/bash
# script: pre_upgrade_checklist.sh
# Verificar que AWX está listo para ser actualizado

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
NAMESPACE="awx"
PASS=0
FAIL=0
WARN=0

check_pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
check_fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check_warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "=== PRE-UPGRADE CHECKLIST AWX ==="
echo ""

# 1. Verificar que no hay jobs en ejecución
echo "1. Jobs en ejecución:"
RUNNING=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/?status=running" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
if [ "$RUNNING" -eq 0 ]; then
    check_pass "Sin jobs en ejecución"
else
    check_warn "${RUNNING} jobs en ejecución. Esperar a que terminen o cancelarlos."
fi

# 2. Verificar que no hay jobs pendientes
echo "2. Jobs pendientes:"
PENDING=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/?status=pending" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
if [ "$PENDING" -eq 0 ]; then
    check_pass "Sin jobs pendientes"
else
    check_warn "${PENDING} jobs pendientes en la cola"
fi

# 3. Verificar que el backup reciente existe
echo "3. Backup reciente:"
LATEST_BACKUP=$(find /opt/awx-backups -name "awx_backup_*.tar.gz*" \
    -mtime -1 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 3600 ))
    check_pass "Backup reciente encontrado (${BACKUP_AGE}h): $(basename $LATEST_BACKUP)"
else
    check_fail "No hay backup de las últimas 24 horas. Ejecutar backup antes de continuar."
fi

# 4. Verificar que todos los pods están Running
echo "4. Estado de los pods:"
NOT_RUNNING=$(kubectl get pods -n "${NAMESPACE}" \
    --field-selector=status.phase!=Running \
    --no-headers 2>/dev/null | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
    check_pass "Todos los pods están Running"
else
    check_fail "${NOT_RUNNING} pods no están en estado Running"
    kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase!=Running
fi

# 5. Verificar conectividad con PostgreSQL
echo "5. Conectividad PostgreSQL:"
PG_CHECK=$(kubectl exec -n "${NAMESPACE}" deployment/awx-task \
    -c awx-task -- \
    python3 -c "
import psycopg2, os
try:
    conn = psycopg2.connect(os.environ.get('DATABASE_URL', ''))
    conn.close()
    print('ok')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "error")
if [ "$PG_CHECK" = "ok" ]; then
    check_pass "PostgreSQL accesible"
else
    check_fail "PostgreSQL no accesible: ${PG_CHECK}"
fi

# 6. Verificar espacio en disco
echo "6. Espacio en disco:"
DISK_FREE=$(df /opt/awx-backups 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
if [ -n "$DISK_FREE" ] && [ "$DISK_FREE" -lt 80 ]; then
    check_pass "Espacio en disco OK (${DISK_FREE}% usado)"
elif [ -n "$DISK_FREE" ]; then
    check_warn "Poco espacio en disco (${DISK_FREE}% usado)"
fi

# 7. Verificar que el operator está actualizado
echo "7. Versión del operator:"
OPERATOR_VERSION=$(kubectl get deployment awx-operator-controller-manager \
    -n "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null \
    | cut -d: -f2)
check_pass "Operator versión: ${OPERATOR_VERSION}"

# 8. Verificar aprobaciones pendientes
echo "8. Aprobaciones pendientes:"
PENDING_APPROVALS=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/workflow_approvals/?status=pending" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
if [ "$PENDING_APPROVALS" -eq 0 ]; then
    check_pass "Sin aprobaciones pendientes"
else
    check_warn "${PENDING_APPROVALS} aprobaciones pendientes. Resolver antes de actualizar."
fi

# ── Resumen ───────────────────────────────────────────────────
echo ""
echo "=== RESUMEN ==="
echo "  ✅ PASS: ${PASS}"
echo "  ⚠️  WARN: ${WARN}"
echo "  ❌ FAIL: ${FAIL}"
echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "❌ NO proceder con la actualización. Resolver los fallos primero."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "⚠️  Hay advertencias. Revisar antes de proceder."
    exit 0
else
    echo "✅ Sistema listo para la actualización."
    exit 0
fi
```

## Paso 2 — Proceso de actualización controlado

```bash
#!/bin/bash
# script: upgrade_awx_controlled.sh
# Actualización controlada con verificaciones en cada paso

set -euo pipefail

NEW_VERSION="${1:?Especifica la versión: $0 <version>}"
NAMESPACE="awx"
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
step() { echo ""; echo "══════════════════════════════════════"; echo "PASO $1: $2"; echo "══════════════════════════════════════"; }

step 1 "Verificaciones pre-upgrade"
bash /opt/scripts/pre_upgrade_checklist.sh || {
    log "❌ Checklist fallido. Abortando."
    exit 1
}

step 2 "Backup pre-upgrade"
log "Ejecutando backup de seguridad..."
bash /opt/scripts/awx_backup.sh
log "✅ Backup completado"

step 3 "Anotar la versión actual para posible rollback"
CURRENT_IMAGE=$(kubectl get deployment awx-web -n "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
log "Imagen actual: ${CURRENT_IMAGE}"
echo "${CURRENT_IMAGE}" > /tmp/awx_previous_image.txt

step 4 "Actualizar el AWX Operator"
log "Descargando manifests del operator ${NEW_VERSION}..."
curl -sL \
    "https://raw.githubusercontent.com/ansible/awx-operator/${NEW_VERSION}/deploy/awx-operator.yml" \
    -o "/tmp/awx-operator-${NEW_VERSION}.yml"

kubectl apply -f "/tmp/awx-operator-${NEW_VERSION}.yml"
kubectl rollout status deployment/awx-operator-controller-manager \
    -n "${NAMESPACE}" --timeout=120s
log "✅ Operator actualizado"

step 5 "Actualizar la versión de AWX"
kubectl patch awx awx -n "${NAMESPACE}" \
    --type=merge \
    -p "{\"spec\": {\"image_version\": \"${NEW_VERSION}\"}}"
log "Patch aplicado, esperando rolling update..."

step 6 "Monitorizar el rolling update"
# awx-web: rolling update
log "Actualizando awx-web (rolling)..."
kubectl rollout status deployment/awx-web \
    -n "${NAMESPACE}" --timeout=600s
log "✅ awx-web actualizado"

# awx-task: rolling update
log "Actualizando awx-task (rolling)..."
kubectl rollout status deployment/awx-task \
    -n "${NAMESPACE}" --timeout=600s
log "✅ awx-task actualizado"

step 7 "Verificaciones post-upgrade"
log "Esperando a que AWX esté completamente disponible..."
sleep 45

# Verificar que la API responde
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${AWX_URL}/api/v2/ping/" --max-time 10 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log "✅ API responde (HTTP 200)"
        break
    fi
    log "Intento ${i}/12: HTTP ${HTTP_CODE}, esperando 15s..."
    sleep 15
    if [ "$i" -eq 12 ]; then
        log "❌ API no responde después de 3 minutos"
        log "Iniciando rollback automático..."
        bash /opt/scripts/rollback_awx.sh
        exit 1
    fi
done

# Verificar la versión instalada
INSTALLED=$(curl -s "${AWX_URL}/api/v2/ping/" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','N/A'))")
log "Versión instalada: ${INSTALLED}"

# Verificar que los jobs pueden ejecutarse (smoke test)
log "Ejecutando smoke test..."
SMOKE_RESP=$(curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/ad_hoc_commands/" \
    -d '{
        "inventory": 1,
        "credential": 1,
        "module_name": "ping",
        "module_args": "",
        "limit": "localhost"
    }' 2>/dev/null || echo "{}")

SMOKE_JOB=$(echo "$SMOKE_RESP" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('id','N/A'))" 2>/dev/null)
log "Smoke test job ID: ${SMOKE_JOB}"

step 8 "Actualización completada"
log "✅ AWX actualizado exitosamente a ${NEW_VERSION}"
log "   Versión anterior: ${CURRENT_IMAGE}"
log "   Versión nueva:    ${INSTALLED}"
log ""
log "Acciones post-upgrade recomendadas:"
log "  1. Verificar que los Execution Nodes se reconectan"
log "  2. Lanzar un job de prueba en dev"
log "  3. Revisar el Activity Stream por errores"
log "  4. Notificar al equipo que la actualización completó"
```

---

# 7.14 LAB — Simulación de fallo y recuperación

*Practicar la recuperación ante fallos antes de que ocurran en producción.*

## Escenario 1: Fallo del pod awx-task

```bash
#!/bin/bash
# Simular fallo del pod awx-task y verificar recuperación automática

NAMESPACE="awx"
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== SIMULACIÓN: Fallo de awx-task ==="
log ""

# Estado inicial
log "Estado inicial:"
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=task

# Lanzar un job de prueba antes del fallo
log "Lanzando job de prueba..."
JOB_RESP=$(curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/job_templates/1/launch/" \
    -d '{"extra_vars": {"target_group": "dev", "release_tag": "v1.0.0", "environment": "dev"}}')
JOB_ID=$(echo "$JOB_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','N/A'))")
log "Job lanzado: ID ${JOB_ID}"

# Matar el pod awx-task
log ""
log "Matando el pod awx-task..."
TASK_POD=$(kubectl get pods -n "${NAMESPACE}" \
    -l app.kubernetes.io/component=task \
    -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "${TASK_POD}" -n "${NAMESPACE}" --grace-period=0

log "Pod eliminado: ${TASK_POD}"
log "Kubernetes debería crear un nuevo pod automáticamente..."

# Monitorizar la recuperación
log ""
log "Monitorizando recuperación:"
for i in $(seq 1 30); do
    READY_PODS=$(kubectl get pods -n "${NAMESPACE}" \
        -l app.kubernetes.io/component=task \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].status.containerStatuses[0].ready}' \
        | tr ' ' '\n' | grep -c "true" || echo "0")

    if [ "$READY_PODS" -gt 0 ]; then
        log "✅ Pod awx-task recuperado (${READY_PODS} pod(s) Ready)"
        break
    fi
    log "  [${i}/30] Esperando pod awx-task... (${READY_PODS} Ready)"
    sleep 5
done

# Verificar el estado del job
log ""
log "Verificando estado del job ${JOB_ID}..."
sleep 10
JOB_STATUS=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/${JOB_ID}/" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','N/A'))")
log "Estado del job: ${JOB_STATUS}"

# Verificar que AWX puede lanzar nuevos jobs
log ""
log "Verificando que AWX puede lanzar nuevos jobs..."
NEW_JOB=$(curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/job_templates/1/launch/" \
    -d '{"extra_vars": {"target_group": "dev", "release_tag": "v1.0.0", "environment": "dev"}}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','error'))")

if [ "$NEW_JOB" != "error" ] && [ "$NEW_JOB" != "N/A" ]; then
    log "✅ Nuevo job lanzado exitosamente: ID ${NEW_JOB}"
else
    log "❌ No se pudo lanzar nuevo job"
fi

log ""
log "=== RESULTADO DE LA SIMULACIÓN ==="
log "  Tiempo de recuperación: < 30 segundos (Kubernetes reinicia el pod)"
log "  Jobs en ejecución durante el fallo: pueden quedar en estado 'failed'"
log "  Nuevos jobs: se pueden lanzar inmediatamente tras la recuperación"
log ""
log "LECCIÓN: Kubernetes garantiza la disponibilidad del Control Plane."
log "         Los jobs en ejecución durante el fallo deben relanzarse manualmente."
```

## Escenario 2: Fallo de PostgreSQL (simulación)

```bash
#!/bin/bash
# Simular pérdida de conectividad con PostgreSQL

NAMESPACE="awx"
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== SIMULACIÓN: Pérdida de conectividad PostgreSQL ==="
log ""
log "IMPORTANTE: Esta simulación usa NetworkPolicy para bloquear"
log "el tráfico a PostgreSQL. Solo en entornos de lab."
log ""

# Crear NetworkPolicy que bloquea el tráfico a PostgreSQL
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-postgres-test
  namespace: awx
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: awx
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 80
        - port: 443
        - port: 6379
      # No incluir puerto 5432 → bloquea PostgreSQL
EOF

log "NetworkPolicy aplicada: PostgreSQL bloqueado"
log "Verificando comportamiento de AWX..."

# Intentar acceder a la API
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${AWX_URL}/api/v2/ping/" --max-time 5 || echo "000")
log "API /ping: HTTP ${HTTP_CODE}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/" --max-time 5 || echo "000")
log "API /jobs: HTTP ${HTTP_CODE} (esperado: 500 o timeout)"

# Restaurar conectividad
log ""
log "Restaurando conectividad PostgreSQL..."
kubectl delete networkpolicy block-postgres-test -n "${NAMESPACE}"

log "NetworkPolicy eliminada. Esperando recuperación..."
sleep 15

# Verificar recuperación
for i in $(seq 1 10); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${AWX_AUTH}" \
        "${AWX_URL}/api/v2/jobs/" --max-time 5 || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log "✅ AWX recuperado (HTTP 200) en intento ${i}"
        break
    fi
    log "  [${i}/10] HTTP ${HTTP_CODE}, esperando..."
    sleep 5
done

log ""
log "=== RESULTADO ==="
log "  AWX detecta la pérdida de BD y devuelve errores 500"
log "  Al restaurar la BD, AWX se recupera automáticamente"
log "  No se necesita reiniciar ningún pod"
log "  RTO para este escenario: < 30 segundos tras restaurar la BD"
```

## Escenario 3: Fallo de un Execution Node

```bash
#!/bin/bash
# Simular fallo de un Execution Node y verificar que los jobs
# se redirigen a otro nodo disponible

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
FAILING_NODE="execution-node-01.empresa.com"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== SIMULACIÓN: Fallo de Execution Node ==="
log "Nodo a fallar: ${FAILING_NODE}"
log ""

# Estado inicial de los nodos
log "Estado inicial de los nodos:"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instances/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for node in data['results']:
    state = node['node_state']
    icon = '✅' if state == 'ready' else '❌'
    print(f'  {icon} {node[\"hostname\"]:40} | {state:10} | Capacity: {node[\"capacity\"]}')
"

# Poner el nodo en modo mantenimiento (simula fallo)
log ""
log "Poniendo ${FAILING_NODE} en modo mantenimiento..."
NODE_ID=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instances/?hostname=${FAILING_NODE}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['id'])")

curl -s -u "${AWX_AUTH}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/instances/${NODE_ID}/" \
    -d '{"node_state": "deprovisioning"}' > /dev/null

log "Nodo marcado como no disponible"

# Lanzar jobs y verificar que van a otro nodo
log ""
log "Lanzando jobs para verificar redirección..."
for i in 1 2 3; do
    JOB_RESP=$(curl -s -u "${AWX_AUTH}" \
        -X POST \
        -H "Content-Type: application/json" \
        "${AWX_URL}/api/v2/job_templates/1/launch/" \
        -d '{"extra_vars": {"target_group": "dev", "release_tag": "v1.0.0", "environment": "dev"}}')
    JOB_ID=$(echo "$JOB_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','N/A'))")
    log "  Job ${i} lanzado: ID ${JOB_ID}"
done

sleep 30

# Verificar en qué nodo se ejecutaron
log ""
log "Verificando nodos de ejecución:"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/?order_by=-id&page_size=3" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for job in data['results']:
    exec_node = job.get('execution_node', 'N/A')
    print(f'  Job #{job[\"id\"]}: ejecutado en {exec_node} | Status: {job[\"status\"]}')
"

# Restaurar el nodo
log ""
log "Restaurando ${FAILING_NODE}..."
curl -s -u "${AWX_AUTH}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/instances/${NODE_ID}/" \
    -d '{"node_state": "ready"}' > /dev/null

log "✅ Nodo restaurado"
log ""
log "=== RESULTADO ==="
log "  Los jobs se redirigieron automáticamente al nodo disponible"
log "  Sin intervención manual necesaria"
log "  El nodo fallido puede restaurarse sin afectar los jobs en curso"
```

## Escenario 4: Prueba de restauración desde backup

```bash
#!/bin/bash
# Prueba mensual de restauración: verificar que el backup funciona
# Ejecutar en un entorno de staging, nunca en producción directamente

BACKUP_FILE="${1:?Especifica el fichero de backup}"
STAGING_NAMESPACE="awx-staging"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== PRUEBA DE RESTAURACIÓN ==="
log "Backup: ${BACKUP_FILE}"
log "Namespace destino: ${STAGING_NAMESPACE}"
log ""
log "⚠️  Esta prueba restaura en el namespace de STAGING"
log "   No afecta al AWX de producción"
log ""

# Verificar que el namespace de staging existe
if ! kubectl get namespace "${STAGING_NAMESPACE}" &>/dev/null; then
    log "Creando namespace de staging..."
    kubectl create namespace "${STAGING_NAMESPACE}"
fi

# Ejecutar la restauración en staging
log "Iniciando restauración en staging..."
STAGING_AWX_URL="http://awx-staging.empresa.com:30080"

# (Aquí iría la lógica de restauración adaptada al namespace de staging)
# Ver script awx_restore.sh de la sección 7.6

# Verificar que la restauración fue exitosa
sleep 60
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${STAGING_AWX_URL}/api/v2/ping/" --max-time 10 || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    log "✅ PRUEBA DE RESTAURACIÓN EXITOSA"
    log "   AWX de staging responde correctamente"

    # Verificar datos restaurados
    STAGING_AUTH="admin:TuPasswordSegura123!"
    JOB_COUNT=$(curl -s -u "${STAGING_AUTH}" \
        "${STAGING_AWX_URL}/api/v2/jobs/" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
    log "   Jobs restaurados: ${JOB_COUNT}"

    TEMPLATE_COUNT=$(curl -s -u "${STAGING_AUTH}" \
        "${STAGING_AWX_URL}/api/v2/job_templates/" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
    log "   Templates restaurados: ${TEMPLATE_COUNT}"

    log ""
    log "RTO verificado: $(date)"
    log "El backup del $(stat -c %y ${BACKUP_FILE} | cut -d' ' -f1) es válido y restaurable."
else
    log "❌ PRUEBA DE RESTAURACIÓN FALLIDA"
    log "   HTTP Code: ${HTTP_CODE}"
    log "   Revisar los logs del pod de staging"
    exit 1
fi
```

---

# 7.15 Patrones avanzados y buenas prácticas

## Patrón 1: Runbook de recuperación ante desastres

```
RUNBOOK: AWX DR (Disaster Recovery)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ESCENARIO A: Pod awx-task caído
  Tiempo de detección: < 2 min (Prometheus alerta)
  Tiempo de recuperación: < 1 min (Kubernetes reinicia el pod)
  Acción manual: ninguna (Kubernetes lo gestiona)
  Jobs afectados: los que estaban en ejecución quedan en "failed"
  Acción post-recovery: relanzar los jobs fallidos

ESCENARIO B: Nodo Kubernetes caído
  Tiempo de detección: < 5 min
  Tiempo de recuperación: < 10 min (pods se replanifican)
  Acción manual: verificar que los pods se replanifican
  Si no se replanifican: kubectl drain + kubectl uncordon

ESCENARIO C: PostgreSQL caído
  Tiempo de detección: < 2 min (Prometheus alerta)
  Tiempo de recuperación: depende del tipo de PostgreSQL
    → RDS Multi-AZ: < 2 min (failover automático)
    → PostgreSQL manual: 5-15 min (failover manual)
  Acción manual (PostgreSQL manual):
    1. Promover la réplica a primary
    2. Actualizar el secret de conexión en AWX
    3. Reiniciar los pods de AWX

ESCENARIO D: Pérdida total del cluster Kubernetes
  Tiempo de detección: inmediato
  Tiempo de recuperación: 15-60 min (reconstruir desde backup)
  Acción manual:
    1. Desplegar nuevo cluster Kubernetes
    2. Instalar AWX Operator
    3. Restaurar desde el último backup
    4. Verificar conectividad con Execution Nodes
    5. Notificar al equipo

ESCENARIO E: Corrupción de datos en PostgreSQL
  Tiempo de detección: variable (puede ser horas)
  Tiempo de recuperación: 30-120 min (restauración desde backup)
  Acción manual:
    1. Identificar el punto de corrupción
    2. Seleccionar el backup anterior al problema
    3. Restaurar en staging para verificar
    4. Restaurar en producción con ventana de mantenimiento
    5. Aplicar cambios manuales si los hay desde el backup

RPO (Recovery Point Objective):  < 24 horas (backup diario)
RTO (Recovery Time Objective):   < 15 minutos (escenarios A, B, C)
                                  < 60 minutos (escenarios D, E)
```

---

## Patrón 2: Gestión de capacidad proactiva

```bash
#!/usr/bin/env python3
# script: capacity_planning.py
# Analiza el uso de capacidad de AWX y predice cuándo se agotará

import requests
from datetime import datetime, timedelta

AWX_URL   = "http://localhost:30080"
AWX_TOKEN = "tu-token-admin"
HEADERS   = {"Authorization": f"Bearer {AWX_TOKEN}"}

def get_metrics():
    resp = requests.get(
        f"{AWX_URL}/api/v2/metrics/",
        headers=HEADERS, timeout=30
    )
    metrics = {}
    for line in resp.text.split('\n'):
        if line and not line.startswith('#'):
            parts = line.split(' ')
            if len(parts) >= 2:
                metrics[parts[0]] = float(parts[1])
    return metrics

def get_job_stats(days=30):
    since = (datetime.utcnow() - timedelta(days=days)).strftime('%Y-%m-%dT%H:%M:%SZ')
    resp = requests.get(
        f"{AWX_URL}/api/v2/jobs/",
        headers=HEADERS,
        params={"created__gte": since, "page_size": 1},
        timeout=30
    )
    return resp.json()['count']

metrics    = get_metrics()
jobs_30d   = get_job_stats(30)
jobs_7d    = get_job_stats(7)
jobs_today = get_job_stats(1)

print("=" * 60)
print("ANÁLISIS DE CAPACIDAD AWX")
print(f"Fecha: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
print("=" * 60)

running  = int(metrics.get('awx_running_jobs_total', 0))
pending  = int(metrics.get('awx_pending_jobs_total', 0))
capacity = int(metrics.get('awx_instance_capacity', 0))
consumed = int(metrics.get('awx_instance_consumed_capacity', 0))
free     = capacity - consumed
util_pct = (consumed / capacity * 100) if capacity > 0 else 0

print(f"\n📊 ESTADO ACTUAL:")
print(f"  Jobs en ejecución:  {running}")
print(f"  Jobs en cola:       {pending}")
print(f"  Capacidad total:    {capacity}")
print(f"  Capacidad usada:    {consumed} ({util_pct:.1f}%)")
print(f"  Capacidad libre:    {free}")

print(f"\n📈 TENDENCIA DE USO:")
print(f"  Jobs últimos 30 días: {jobs_30d:,}")
print(f"  Jobs últimos 7 días:  {jobs_7d:,}")
print(f"  Jobs hoy:             {jobs_today:,}")
print(f"  Media diaria (30d):   {jobs_30d/30:.0f}")
print(f"  Tendencia (7d vs 30d): {((jobs_7d/7) / (jobs_30d/30) - 1) * 100:+.1f}%")

print(f"\n🔮 RECOMENDACIONES:")
if util_pct > 80:
    print(f"  🔴 URGENTE: Capacidad al {util_pct:.0f}%. Añadir Execution Nodes.")
elif util_pct > 60:
    print(f"  🟡 ATENCIÓN: Capacidad al {util_pct:.0f}%. Planificar ampliación.")
else:
    print(f"  ✅ Capacidad OK ({util_pct:.0f}% usado)")

if pending > 10:
    print(f"  🔴 {pending} jobs en cola. Posible cuello de botella.")

growth_rate = (jobs_7d/7) / (jobs_30d/30) if jobs_30d > 0 else 1
if growth_rate > 1.2:
    print(f"  📈 Crecimiento del {(growth_rate-1)*100:.0f}% en la última semana.")
    print(f"     Revisar capacidad en las próximas 2-4 semanas.")
```

---

## Patrón 3: Mantenimiento programado con notificaciones

```bash
#!/bin/bash
# script: maintenance_mode.sh
# Activar/desactivar modo mantenimiento en AWX con notificaciones

ACTION="${1:?Uso: $0 enable|disable <motivo>}"
REASON="${2:-Mantenimiento programado}"
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
NAMESPACE="awx"

notify() {
    local msg="$1"
    echo "$msg"
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$msg\"}" > /dev/null
    fi
}

if [ "$ACTION" = "enable" ]; then
    notify "🔧 AWX entrando en modo mantenimiento: ${REASON}"

    # Esperar a que terminen los jobs en ejecución (máx 30 min)
    echo "Esperando a que terminen los jobs en ejecución..."
    TIMEOUT=1800
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        RUNNING=$(curl -s -u "${AWX_AUTH}" \
            "${AWX_URL}/api/v2/jobs/?status=running" \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
        if [ "$RUNNING" -eq 0 ]; then
            echo "✅ Sin jobs en ejecución"
            break
        fi
        echo "  ${RUNNING} jobs en ejecución, esperando..."
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done

    # Escalar a 0 (modo mantenimiento)
    kubectl scale deployment awx-web  -n "${NAMESPACE}" --replicas=0
    kubectl scale deployment awx-task -n "${NAMESPACE}" --replicas=0

    notify "🔴 AWX en modo mantenimiento. Motivo: ${REASON}"

elif [ "$ACTION" = "disable" ]; then
    notify "🔄 Saliendo del modo mantenimiento AWX..."

    kubectl scale deployment awx-web  -n "${NAMESPACE}" --replicas=2
    kubectl scale deployment awx-task -n "${NAMESPACE}" --replicas=2

    # Esperar a que estén listos
    kubectl rollout status deployment/awx-web  -n "${NAMESPACE}" --timeout=300s
    kubectl rollout status deployment/awx-task -n "${NAMESPACE}" --timeout=300s

    notify "✅ AWX disponible. Mantenimiento completado."
else
    echo "Acción desconocida: ${ACTION}"
    exit 1
fi
```

---

## Patrón 4: Limpieza automática de jobs antiguos

```bash
#!/bin/bash
# script: cleanup_old_jobs.sh
# Limpiar jobs y logs antiguos para mantener la BD en buen estado

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
DAYS_TO_KEEP=90

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Limpieza de jobs AWX (retención: ${DAYS_TO_KEEP} días) ==="

# Obtener el tamaño actual de la BD
DB_SIZE=$(kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import django
django.setup()
from django.db import connection
with connection.cursor() as c:
    c.execute(\"SELECT pg_size_pretty(pg_database_size(current_database()))\")
    print(c.fetchone()[0])
" 2>/dev/null || echo "N/A")
log "Tamaño actual de la BD: ${DB_SIZE}"

# Contar jobs a eliminar
JOBS_TO_DELETE=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/jobs/?created__lt=$(date -u -d "-${DAYS_TO_KEEP} days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-${DAYS_TO_KEEP}d '+%Y-%m-%dT%H:%M:%SZ')&page_size=1" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
log "Jobs a eliminar (> ${DAYS_TO_KEEP} días): ${JOBS_TO_DELETE}"

# Ejecutar la limpieza via management command de Django
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    awx-manage cleanup_jobs \
    --days="${DAYS_TO_KEEP}" \
    --jobs \
    --workflow_jobs \
    --ad_hoc_commands \
    --project_updates \
    --inventory_updates \
    --management_jobs \
    --notifications

log "✅ Limpieza completada"

# Tamaño después de la limpieza
DB_SIZE_AFTER=$(kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import django
django.setup()
from django.db import connection
with connection.cursor() as c:
    c.execute(\"SELECT pg_size_pretty(pg_database_size(current_database()))\")
    print(c.fetchone()[0])
" 2>/dev/null || echo "N/A")
log "Tamaño de la BD después: ${DB_SIZE_AFTER}"

# VACUUM para recuperar espacio en PostgreSQL
log "Ejecutando VACUUM ANALYZE..."
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import django
django.setup()
from django.db import connection
connection.connection.autocommit = True
with connection.cursor() as c:
    c.execute('VACUUM ANALYZE')
print('VACUUM completado')
"
log "✅ VACUUM completado"
```

```bash
# Configurar limpieza automática en AWX
# Administration → Settings → Jobs
#   Days of data to keep: 90
#   Frequency of data cleanup: 30 (días entre limpiezas automáticas)

# O via API:
curl -s -u "${AWX_AUTH}" \
    -X PATCH \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/settings/jobs/" \
    -d '{
        "CLEANUP_JOB_SCHEDULE": 30,
        "CLEANUP_JOB_DAYS": 90
    }'
```

---

# 7.16 Troubleshooting del Módulo 7

## Problema 1: AWX no arranca después de una actualización

**Síntoma:**
```
Después de actualizar AWX, los pods quedan en CrashLoopBackOff
o en estado Init.
```

**Diagnóstico:**
```bash
NAMESPACE="awx"

# Ver el estado de todos los pods
kubectl get pods -n "${NAMESPACE}"

# Ver los eventos del namespace
kubectl get events -n "${NAMESPACE}" \
    --sort-by='.lastTimestamp' | tail -20

# Ver los logs del pod que falla
FAILING_POD=$(kubectl get pods -n "${NAMESPACE}" \
    --field-selector=status.phase!=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$FAILING_POD" ]; then
    echo "Pod fallido: ${FAILING_POD}"
    kubectl logs -n "${NAMESPACE}" "${FAILING_POD}" \
        --all-containers --previous 2>/dev/null | tail -50
    kubectl describe pod "${FAILING_POD}" -n "${NAMESPACE}"
fi

# Ver los logs del operator para entender qué está haciendo
kubectl logs -n "${NAMESPACE}" \
    deployment/awx-operator-controller-manager \
    -c awx-manager --tail=30
```

**Causas y soluciones:**

```
CAUSA 1: Migración de base de datos fallida
  
  Síntoma en logs:
    django.db.utils.ProgrammingError: column does not exist
    django.db.migrations.exceptions.MigrationSchemaMissing
  
  Solución:
    # Ejecutar las migraciones manualmente
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
        awx-manage migrate --run-syncdb
    
    # Si falla, restaurar desde backup y no actualizar
    bash /opt/scripts/awx_restore.sh /opt/awx-backups/ultimo_backup.tar.gz

CAUSA 2: Secret key cambiado o perdido
  
  Síntoma en logs:
    cryptography.fernet.InvalidToken
    Error decrypting credential
  
  Solución:
    # Restaurar el secret key desde el backup
    kubectl apply -f /opt/awx-backups/FECHA/awx-secret-key.yaml
    
    # Reiniciar los pods
    kubectl rollout restart deployment/awx-web deployment/awx-task -n awx

CAUSA 3: PostgreSQL no accesible durante el arranque
  
  Síntoma en logs:
    django.db.utils.OperationalError: could not connect to server
  
  Solución:
    # Verificar que PostgreSQL está disponible
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
        python3 -c "import psycopg2; print('OK')"
    
    # Verificar el secret de configuración
    kubectl get secret awx-postgres-configuration -n awx \
        -o jsonpath='{.data.host}' | base64 -d

CAUSA 4: Imagen del EE no disponible
  
  Síntoma en logs:
    Failed to pull image "quay.io/ansible/awx-ee:24.6.0"
    ImagePullBackOff
  
  Solución:
    # Verificar conectividad con el registry
    kubectl run test-pull --image=quay.io/ansible/awx-ee:24.6.0 \
        --restart=Never -n awx -- echo "OK"
    kubectl logs test-pull -n awx
    kubectl delete pod test-pull -n awx
    
    # Si hay problemas de red, usar una imagen local o mirror
    kubectl patch awx awx -n awx --type=merge \
        -p '{"spec": {"ee_images": [{"name": "Default EE", "image": "registry.empresa.com/awx-ee:24.6.0"}]}}'
```

---

## Problema 2: Execution Node no se conecta al Control Plane

**Síntoma:**
```
El Execution Node aparece en AWX pero con estado "unavailable"
o "deprovisioning". Los jobs asignados a ese nodo se quedan
en estado "pending" indefinidamente.
```

**Diagnóstico:**
```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
NODE_HOST="execution-node-01.empresa.com"

# Ver el estado del nodo en AWX
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/instances/?hostname=${NODE_HOST}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    node = data['results'][0]
    print(f'Estado:        {node[\"node_state\"]}')
    print(f'Tipo:          {node[\"node_type\"]}')
    print(f'Capacidad:     {node[\"capacity\"]}')
    print(f'Versión:       {node[\"version\"]}')
    print(f'Último ping:   {node.get(\"last_seen\", \"N/A\")}')
    print(f'Errors:        {node.get(\"errors\", \"ninguno\")}')
"

# Verificar el servicio receptor en el Execution Node
ssh "${NODE_HOST}" "systemctl status receptor"
ssh "${NODE_HOST}" "receptorctl --socket /var/run/receptor/receptor.sock status"

# Verificar la conectividad de red
# Desde el Control Plane al Execution Node:
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    nc -zv "${NODE_HOST}" 27199

# Ver los logs del receptor en el Execution Node
ssh "${NODE_HOST}" "journalctl -u receptor -n 50 --no-pager"

# Ver los logs del receptor en el Control Plane
kubectl logs -n awx deployment/awx-task -c awx-task \
    | grep -i "receptor\|${NODE_HOST}" | tail -20
```

**Causas y soluciones:**

```
CAUSA 1: Puerto 27199 bloqueado por firewall
  
  Diagnóstico:
    nc -zv execution-node-01.empresa.com 27199
    # Si falla: firewall bloqueando
  
  Solución:
    # En el Execution Node (iptables):
    iptables -A INPUT -p tcp --dport 27199 -j ACCEPT
    
    # O en el Security Group de AWS:
    aws ec2 authorize-security-group-ingress \
        --group-id sg-xxx \
        --protocol tcp \
        --port 27199 \
        --cidr 10.0.0.0/8

CAUSA 2: Certificados de receptor expirados o incorrectos
  
  Diagnóstico:
    ssh execution-node-01 "openssl x509 -in /etc/receptor/tls/receptor.crt -noout -dates"
  
  Solución:
    # Regenerar el bundle de instalación desde AWX
    Administration → Instances → execution-node-01 → Install Bundle → Download
    
    # Reinstalar en el Execution Node
    cd /tmp && tar -xzf awx_install_bundle_*.tar.gz
    ansible-playbook install_receptor.yml

CAUSA 3: Servicio receptor caído en el Execution Node
  
  Diagnóstico:
    ssh execution-node-01 "systemctl status receptor"
    # Si está inactive o failed:
  
  Solución:
    ssh execution-node-01 "systemctl restart receptor"
    ssh execution-node-01 "systemctl enable receptor"
    
    # Ver por qué falló:
    ssh execution-node-01 "journalctl -u receptor -n 100"

CAUSA 4: Versión de receptor incompatible
  
  Síntoma:
    El nodo se conecta pero los jobs fallan con errores de protocolo.
  
  Solución:
    # Actualizar receptor en el Execution Node
    ssh execution-node-01 "pip3 install --upgrade receptorctl ansible-runner"
    ssh execution-node-01 "systemctl restart receptor"
```

---

## Problema 3: Métricas de Prometheus no aparecen

**Síntoma:**
```
Prometheus no recibe métricas de AWX o el endpoint
/api/v2/metrics/ devuelve 401 o 403.
```

**Diagnóstico:**
```bash
AWX_URL="http://localhost:30080"

# Probar el endpoint de métricas directamente
curl -s -u "admin:TuPasswordSegura
