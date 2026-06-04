# 🔐 MÓDULO 5 — RBAC, Organizaciones y Multi-tenancy
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 5.1 | Modelo mental: seguridad como diseño, no como añadido |
| 5.2 | Organizaciones: el límite de todo |
| 5.3 | Usuarios y Teams: identidades y agrupaciones |
| 5.4 | El modelo de roles de AWX |
| 5.5 | Roles por tipo de objeto |
| 5.6 | Credenciales: separación y mínimo privilegio |
| 5.7 | Activity Stream y auditoría |
| 5.8 | Multi-tenancy: patrones de aislamiento |
| 5.9 | LAB — Crear Teams con roles diferenciados |
| 5.10 | LAB — Delegar ejecución sin exponer credenciales |
| 5.11 | LAB — Acceso de solo lectura para auditores |
| 5.12 | LAB — Multi-tenancy con organizaciones separadas |
| 5.13 | LAB — Instance Groups por entorno y tenant |
| 5.14 | LAB — Integración con LDAP/SSO |
| 5.15 | Patrones avanzados y buenas prácticas |
| 5.16 | Troubleshooting del módulo |
| 5.17 | Resumen y checklist |

**Duración estimada:** 60-75 minutos
**Tipo:** Configuración + Labs de seguridad
**Prerrequisitos:** Módulos 1-4 completados

---

# 5.1 Modelo mental: seguridad como diseño, no como añadido

El error más común con AWX es construir toda la automatización primero y pensar en permisos después. El resultado es un sistema donde todo el mundo tiene acceso a todo, o donde los permisos son tan restrictivos que nadie puede trabajar.

El enfoque correcto es diseñar el modelo de acceso **antes** de crear los objetos.

```
PREGUNTA DE DISEÑO ANTES DE CREAR CUALQUIER OBJETO:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

¿Quién necesita EJECUTAR esto?     → rol Execute en el template
¿Quién necesita VERLO?             → rol Read en el template
¿Quién necesita MODIFICARLO?       → rol Admin en el template
¿Quién necesita APROBARLO?         → rol Approve en el workflow
¿Quién necesita VER LOS HOSTS?     → rol Read en el inventario
¿Quién necesita AÑADIR HOSTS?      → rol Admin en el inventario
¿Quién necesita USAR LAS CLAVES?   → rol Use en la credencial
¿Quién necesita VER LAS CLAVES?    → NADIE (nunca dar Read en creds)

PRINCIPIO FUNDAMENTAL:
  El operador pulsa el botón.
  AWX usa las credenciales.
  El operador nunca ve las credenciales.
```

## La matriz de acceso ideal

```
                    Platform  AppOps  SecOps  Auditores  CI/CD
                    ────────  ──────  ──────  ─────────  ─────
Org Admin           ✅        ❌      ❌      ❌         ❌
Crear Templates     ✅        ❌      ❌      ❌         ❌
Ejecutar Templates  ✅        ✅      ✅      ❌         ✅
Ver Templates       ✅        ✅      ✅      ✅         ✅
Gestionar Creds     ✅        ❌      ❌      ❌         ❌
Usar Creds          ✅        ❌*     ❌*     ❌         ❌
Ver Creds           ❌        ❌      ❌      ❌         ❌
Gestionar Inv.      ✅        ❌      ❌      ❌         ❌
Ver Inventario      ✅        ✅      ✅      ✅         ❌
Aprobar Workflows   ✅        ❌      ✅      ❌         ❌
Ver Jobs/Logs       ✅        ✅      ✅      ✅         ✅

* AppOps y SecOps usan creds a través de templates, no directamente
```

---

# 5.2 Organizaciones: el límite de todo

Una Organización en AWX es el contenedor de primer nivel. Todo objeto pertenece a una organización y los permisos no cruzan fronteras organizacionales (salvo System Admin).

## Cuándo usar una vs múltiples organizaciones

```
UNA ORGANIZACIÓN (lo más común):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Empresa mediana con múltiples equipos pero infraestructura compartida.
  Los equipos comparten inventarios y proyectos pero tienen
  distintos niveles de acceso.
  
  Estructura:
    Organization: MiEmpresa
      Team: Platform    (admin de la org)
      Team: AppOps      (ejecuta templates)
      Team: SecOps      (aprueba cambios críticos)
      Team: Auditores   (solo lectura)

MÚLTIPLES ORGANIZACIONES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Empresa grande con unidades de negocio independientes.
  O empresa que ofrece AWX como servicio a múltiples clientes.
  Cada organización es completamente independiente.
  
  Estructura:
    Organization: BU-Retail
      Team: Platform-Retail
      Team: AppOps-Retail
    
    Organization: BU-Finance
      Team: Platform-Finance
      Team: AppOps-Finance
    
    Organization: BU-Logistics
      Team: Platform-Logistics
      Team: AppOps-Logistics
  
  Ventaja: aislamiento total entre unidades
  Desventaja: duplicación de objetos (proyectos, EEs, etc.)
```

## Roles a nivel de Organización

```
Organization Admin:
  → Control total sobre todos los objetos de la organización
  → Puede crear/modificar/eliminar usuarios, teams, proyectos, etc.
  → NO puede modificar la configuración global de AWX
  → Asignar solo al equipo Platform

Organization Auditor:
  → Acceso de solo lectura a TODOS los objetos de la organización
  → Puede ver jobs, logs, inventarios, templates
  → NO puede ejecutar nada
  → Ideal para: compliance, auditores externos, management

Organization Member:
  → Pertenece a la organización
  → Sin permisos adicionales (los permisos vienen de roles en objetos específicos)
  → Todos los usuarios operativos deben ser Members
```

---

# 5.3 Usuarios y Teams: identidades y agrupaciones

## Tipos de usuarios en AWX

```
Normal User:
  → Sin permisos globales
  → Solo puede hacer lo que sus roles en objetos específicos permiten
  → El tipo correcto para el 95% de los usuarios

System Auditor:
  → Acceso de solo lectura a TODO AWX (todas las organizaciones)
  → Útil para: auditores de seguridad, compliance officers
  → NO puede ejecutar nada en ninguna organización

System Administrator:
  → Acceso total a TODO AWX
  → Equivale a root
  → Usar solo para: administración del sistema, emergencias
  → Nunca para trabajo diario
  → Mínimo 2 cuentas (para recuperación), máximo 3-4
```

## Teams: la unidad de gestión de permisos

```
REGLA DE ORO:
  Asignar roles a TEAMS, no a usuarios individuales.
  
  ❌ MAL:
    usuario1 → Execute en Template A
    usuario2 → Execute en Template A
    usuario3 → Execute en Template A
    (si entra usuario4, hay que añadirlo manualmente a cada template)
  
  ✅ BIEN:
    Team AppOps → Execute en Template A
    usuario1 → miembro de AppOps
    usuario2 → miembro de AppOps
    usuario3 → miembro de AppOps
    (si entra usuario4, solo hay que añadirlo al team AppOps)
```

## Estructura de teams recomendada

```
TEAM: Platform
  Responsabilidad: Gestionar la plataforma AWX
  Miembros: ingenieros de plataforma/infraestructura
  Roles típicos:
    → Organization Admin
    → Admin en todos los proyectos
    → Admin en todos los inventarios
    → Admin en todas las credenciales
    → Admin en todos los templates

TEAM: AppOps
  Responsabilidad: Operar las aplicaciones
  Miembros: ingenieros de operaciones de aplicaciones
  Roles típicos:
    → Organization Member
    → Execute + Read en templates de su aplicación
    → Read en inventarios relevantes
    → (sin acceso directo a credenciales)

TEAM: SecOps
  Responsabilidad: Seguridad y compliance
  Miembros: ingenieros de seguridad
  Roles típicos:
    → Organization Member
    → Approve en workflows críticos
    → Read en todos los templates e inventarios
    → Execute en templates de seguridad/hardening

TEAM: Change Advisory Board
  Responsabilidad: Aprobar cambios en producción
  Miembros: arquitectos, managers, representantes de negocio
  Roles típicos:
    → Organization Member
    → Approve en workflows de producción
    → Read en templates de producción

TEAM: Auditores
  Responsabilidad: Auditoría y compliance
  Miembros: auditores internos/externos
  Roles típicos:
    → Organization Auditor
    → (sin necesidad de roles adicionales)

TEAM: CI-CD-Automation
  Responsabilidad: Cuentas de servicio para CI/CD
  Miembros: cuentas de servicio (no personas)
  Roles típicos:
    → Organization Member
    → Execute en workflows específicos
    → (sin acceso a credenciales ni inventarios directamente)
```

---

# 5.4 El modelo de roles de AWX

AWX usa un sistema de RBAC basado en roles discretos por objeto. No hay herencia compleja: cada objeto tiene sus propios roles asignados.

## Cómo funciona la asignación de roles

```
OBJETO: Job Template "Web App Deploy"
  ├── Role: Admin    → Team Platform
  ├── Role: Execute  → Team AppOps
  ├── Role: Execute  → Team CI-CD-Automation
  └── Role: Read     → Team Auditores

OBJETO: Inventory "Env Inventory"
  ├── Role: Admin    → Team Platform
  ├── Role: Use      → (embebido en templates, no asignado directamente)
  └── Role: Read     → Team AppOps, Team SecOps, Team Auditores

OBJETO: Credential "Platform SSH"
  ├── Role: Admin    → Team Platform
  └── Role: Use      → (solo asignado a templates, no a teams directamente)
```

## Resolución de permisos

```
Para que un usuario pueda EJECUTAR un Job Template necesita:
  1. Ser miembro de la organización (Member o superior)
  2. Tener rol Execute (o Admin) en el Job Template
  
  AWX NO requiere que el usuario tenga acceso directo al
  inventario o credenciales: el template los usa en su nombre.

Para que un usuario pueda VER un Job Template necesita:
  1. Ser miembro de la organización
  2. Tener rol Read (o superior) en el Job Template

Para que un usuario pueda MODIFICAR un Job Template necesita:
  1. Ser miembro de la organización
  2. Tener rol Admin en el Job Template
  3. Tener rol Use (o superior) en el inventario que quiere asignar
  4. Tener rol Use (o superior) en las credenciales que quiere asignar
  5. Tener rol Use (o superior) en el proyecto que quiere asignar
```

---

# 5.5 Roles por tipo de objeto

## Tabla completa de roles

| Objeto | Admin | Use | Execute | Update | Read | Approve |
|--------|-------|-----|---------|--------|------|---------|
| **Organization** | Control total | — | — | — | Ver todo | — |
| **Team** | Gestionar miembros | — | — | — | Ver | — |
| **User** | Gestionar | — | — | — | Ver | — |
| **Project** | Gestionar | Usar en JT | — | Sync SCM | Ver | — |
| **Inventory** | Gestionar | Usar en JT | Ad-hoc | Sync source | Ver hosts/vars | — |
| **Credential** | Gestionar | Usar en JT | — | — | Ver (masked) | — |
| **Job Template** | Gestionar | — | Lanzar | — | Ver | — |
| **Workflow Template** | Gestionar | — | Lanzar | — | Ver | Aprobar nodos |
| **Notification Template** | Gestionar | — | — | — | Ver | — |
| **Execution Environment** | Gestionar | Usar en JT | — | — | Ver | — |
| **Instance Group** | Gestionar | Usar en JT | — | — | Ver | — |

## Detalles importantes por objeto

### Credenciales: el objeto más sensible

```
Role: Admin
  → Puede ver, modificar y eliminar la credencial
  → Puede ver los campos (incluyendo secretos enmascarados)
  → NUNCA asignar a usuarios operativos

Role: Use
  → Puede seleccionar la credencial al crear/editar un Job Template
  → NO puede ver el valor de los campos secretos
  → Asignar solo cuando el usuario necesita crear templates
  → Para operadores que solo ejecutan: NO necesitan Use en creds
    (el template ya tiene las creds embebidas)

Role: Read
  → Puede ver que la credencial existe y su nombre
  → NO puede ver los valores
  → Útil para: auditores que necesitan verificar qué creds existen

REGLA PRÁCTICA:
  Si un usuario solo ejecuta templates (no los crea),
  NO necesita ningún rol en las credenciales.
  El template las usa en su nombre.
```

### Inventarios: el objeto más consultado

```
Role: Admin
  → Control total: crear grupos, hosts, fuentes dinámicas
  → Asignar solo a Platform

Role: Use
  → Puede seleccionar el inventario al crear Job Templates
  → Asignar a quienes crean templates (Platform, a veces AppOps senior)

Role: Update
  → Puede lanzar sincronizaciones de fuentes dinámicas
  → Útil para: equipos que gestionan sus propios inventarios

Role: Ad Hoc
  → Puede ejecutar comandos ad-hoc contra el inventario
  → PELIGROSO: permite ejecutar comandos arbitrarios en los hosts
  → Solo asignar a Platform y con mucho cuidado

Role: Read
  → Puede ver hosts, grupos y variables del inventario
  → Asignar a: AppOps, SecOps, Auditores
  → Permite ver la infraestructura sin poder modificarla
```

---

# 5.6 Credenciales: separación y mínimo privilegio

## Patrón de separación de credenciales por función

```
CREDENCIAL: Platform SSH (acceso general)
  Uso: templates de configuración de infraestructura
  Acceso: solo Platform Admin
  Asignada a: templates de Platform

CREDENCIAL: AppOps SSH (acceso limitado)
  Uso: templates de deploy de aplicaciones
  Acceso: Platform Admin (gestión), embebida en templates de AppOps
  Asignada a: templates que AppOps ejecuta

CREDENCIAL: Vault Dev
  Uso: descifrar secrets del entorno dev
  Acceso: Platform Admin
  Asignada a: templates de dev

CREDENCIAL: Vault Prod
  Uso: descifrar secrets del entorno prod
  Acceso: Platform Admin
  Asignada a: templates de prod (con aprobación)

CREDENCIAL: AWS ReadOnly
  Uso: inventario dinámico EC2
  Acceso: Platform Admin
  Asignada a: fuentes de inventario

CREDENCIAL: AWS Deploy
  Uso: crear/modificar recursos AWS
  Acceso: Platform Admin
  Asignada a: templates de provisioning

SEPARACIÓN CLAVE:
  ReadOnly ≠ Deploy
  Dev ≠ Prod
  SSH ≠ Vault ≠ Cloud
```

## Patrón de credenciales por entorno

```
PROBLEMA:
  Si usas la misma credencial SSH para dev y prod,
  un error en un template de dev puede afectar a prod.

SOLUCIÓN: Credenciales separadas por entorno

  Platform SSH Dev:
    Username: ansible
    Key: clave_dev (solo autorizada en hosts de dev)
    
  Platform SSH Prod:
    Username: ansible
    Key: clave_prod (solo autorizada en hosts de prod)
    Rotación: más frecuente
    Acceso: más restringido

  Templates de dev  → usan Platform SSH Dev
  Templates de prod → usan Platform SSH Prod
  
  Si alguien compromete un template de dev,
  no tiene acceso a los hosts de prod.
```

---

# 5.7 Activity Stream y auditoría

AWX registra automáticamente todas las acciones en el Activity Stream. Es la fuente de verdad para auditoría.

## Qué registra el Activity Stream

```
EVENTOS REGISTRADOS:
  • Creación/modificación/eliminación de cualquier objeto
  • Lanzamiento de jobs y workflows
  • Cambios de permisos (quién asignó qué rol a quién)
  • Aprobaciones y rechazos de workflows
  • Cambios de contraseña y tokens
  • Login/logout de usuarios
  • Cambios en credenciales (no el valor, sí el cambio)
  • Sincronizaciones de proyectos e inventarios

INFORMACIÓN POR EVENTO:
  • Timestamp (UTC)
  • Actor (quién lo hizo)
  • Operación (create, update, delete, associate, disassociate)
  • Objeto afectado (tipo + ID + nombre)
  • Cambios realizados (campo anterior → campo nuevo)
```

## Consultar el Activity Stream

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver los últimos 20 eventos del activity stream
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/activity_stream/?order_by=-timestamp&page_size=20" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total eventos: {data[\"count\"]}')
print()
for event in data['results']:
    actor = event.get('actor', {})
    actor_name = actor.get('username', 'system') if actor else 'system'
    obj1 = event.get('object1', 'N/A')
    obj2 = event.get('object2', '')
    obj2_str = f' → {obj2}' if obj2 else ''
    print(f'{event[\"timestamp\"][:19]} | {actor_name:20} | {event[\"operation\"]:12} | {obj1}{obj2_str}')
"

# Filtrar por usuario específico
USERNAME="operador1"
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/activity_stream/?actor__username=${USERNAME}&order_by=-timestamp&page_size=20" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Acciones de {sys.argv[1] if len(sys.argv) > 1 else \"usuario\"}: {data[\"count\"]}')
for event in data['results']:
    print(f'  {event[\"timestamp\"][:19]} | {event[\"operation\"]:12} | {event[\"object1\"]}')
"

# Filtrar por tipo de objeto (ej: job_template)
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/activity_stream/?object1=job_template&order_by=-timestamp&page_size=10" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for event in data['results']:
    actor = event.get('actor', {})
    actor_name = actor.get('username', 'system') if actor else 'system'
    print(f'{event[\"timestamp\"][:19]} | {actor_name:20} | {event[\"operation\"]:12} | {event[\"object1\"]}')
"
```

## Exportar Activity Stream para SIEM

```bash
#!/bin/bash
# script: export_activity_stream.sh
# Exportar el activity stream de las últimas 24 horas a JSON

AWX_URL="http://localhost:30080"
AWX_TOKEN="tu-token-admin"
OUTPUT_FILE="/var/log/awx/activity_stream_$(date +%Y%m%d).json"

# Calcular timestamp de hace 24 horas
SINCE=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ')  # macOS

PAGE=1
TOTAL_EVENTS=0

echo "[]" > "${OUTPUT_FILE}"

while true; do
  RESPONSE=$(curl -s \
    -H "Authorization: Bearer ${AWX_TOKEN}" \
    "${AWX_URL}/api/v2/activity_stream/?order_by=-timestamp&page_size=200&page=${PAGE}&timestamp__gte=${SINCE}")

  COUNT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
  NEXT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('next','null'))")

  # Añadir eventos al fichero
  echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
with open('${OUTPUT_FILE}', 'r') as f:
    existing = json.load(f)
existing.extend(data['results'])
with open('${OUTPUT_FILE}', 'w') as f:
    json.dump(existing, f, indent=2)
print(f'Página ${PAGE}: {len(data[\"results\"])} eventos')
"

  TOTAL_EVENTS=$((TOTAL_EVENTS + $(echo "$RESPONSE" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['results']))")))

  if [ "$NEXT" = "null" ] || [ -z "$NEXT" ]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

echo "Total exportado: ${TOTAL_EVENTS} eventos → ${OUTPUT_FILE}"

# Comprimir y enviar al SIEM (ejemplo con S3)
gzip "${OUTPUT_FILE}"
aws s3 cp "${OUTPUT_FILE}.gz" "s3://mi-siem-bucket/awx/activity-stream/"
```

---

# 5.8 Multi-tenancy: patrones de aislamiento

## Nivel 1: Aislamiento por Teams (misma organización)

```
CUÁNDO USAR:
  Equipos de la misma empresa que comparten infraestructura
  pero necesitan ver/hacer cosas diferentes.

ESTRUCTURA:
  Organization: MiEmpresa
    Shared Resources:
      Inventories: Env Inventory (todos pueden leer)
      Projects: Platform Playbooks (solo Platform puede modificar)
      EEs: Default EE, Custom EE (todos pueden usar)
    
    Team Platform:
      → Admin en todo
    
    Team AppOps:
      → Execute en templates de su aplicación
      → Read en inventarios
    
    Team AppOps-WebApp:
      → Execute solo en templates de WebApp
      → Read en inventario WebApp
    
    Team AppOps-API:
      → Execute solo en templates de API
      → Read en inventario API

VENTAJA: Simple, un solo espacio de nombres
DESVENTAJA: Requiere gestión cuidadosa de permisos
```

## Nivel 2: Aislamiento por Organizaciones (multi-tenant real)

```
CUÁNDO USAR:
  Unidades de negocio completamente independientes.
  Clientes diferentes en un AWX compartido.
  Equipos que no deben ver los recursos de los demás.

ESTRUCTURA:
  Organization: Cliente-A
    Team: Platform-A (admin de Cliente-A)
    Team: Ops-A
    Inventories: propios de Cliente-A
    Projects: propios de Cliente-A
    Credentials: propias de Cliente-A
    Templates: propios de Cliente-A
  
  Organization: Cliente-B
    Team: Platform-B (admin de Cliente-B)
    Team: Ops-B
    Inventories: propios de Cliente-B
    (completamente separado de Cliente-A)
  
  System Admin: solo el equipo de plataforma AWX global
    → Puede ver todo pero no interfiere en el día a día

VENTAJA: Aislamiento total, cada cliente/BU es independiente
DESVENTAJA: Duplicación de objetos compartidos (EEs, etc.)
```

## Nivel 3: Aislamiento por Instance Groups

```
CUÁNDO USAR:
  Separar la capacidad de ejecución por entorno o tenant.
  Evitar que jobs de dev consuman capacidad de prod.
  Aislar la ejecución en redes diferentes.

ESTRUCTURA:
  Instance Group: ig-dev
    → Jobs de desarrollo
    → Capacidad: 2 instancias compartidas
    → Red: puede llegar a hosts de dev
  
  Instance Group: ig-prod
    → Jobs de producción
    → Capacidad: 4 instancias dedicadas
    → Red: puede llegar a hosts de prod
    → Hardened: imagen de EE firmada, sin acceso a internet
  
  Instance Group: ig-dmz
    → Jobs para hosts en DMZ
    → Execution node físicamente en la DMZ
    → Sin acceso a la red interna
  
  Instance Group: ig-cliente-a
    → Jobs del Cliente A
    → Aislado de ig-cliente-b

ASIGNACIÓN:
  Templates de dev  → Instance Group: ig-dev
  Templates de prod → Instance Group: ig-prod
  Templates DMZ     → Instance Group: ig-dmz
```

---

# 5.9 LAB — Crear Teams con roles diferenciados

## Paso 1 — Crear los Teams

```
AWX UI → Teams → Add

── Team 1: Platform ─────────────────────────────────────────────
  Name:         Platform
  Description:  Equipo de plataforma. Gestiona AWX y la infraestructura base.
  Organization: MiEmpresa
  → Save

── Team 2: AppOps ───────────────────────────────────────────────
  Name:         AppOps
  Description:  Equipo de operaciones de aplicaciones. Ejecuta deploys.
  Organization: MiEmpresa
  → Save

── Team 3: SecOps ───────────────────────────────────────────────
  Name:         SecOps
  Description:  Equipo de seguridad. Aprueba cambios críticos.
  Organization: MiEmpresa
  → Save

── Team 4: Change Advisory Board ────────────────────────────────
  Name:         Change Advisory Board
  Description:  Aprueba cambios en producción.
  Organization: MiEmpresa
  → Save

── Team 5: Auditores ────────────────────────────────────────────
  Name:         Auditores
  Description:  Acceso de solo lectura para compliance y auditoría.
  Organization: MiEmpresa
  → Save

── Team 6: CI-CD-Automation ─────────────────────────────────────
  Name:         CI-CD-Automation
  Description:  Cuentas de servicio para pipelines de CI/CD.
  Organization: MiEmpresa
  → Save
```

## Paso 2 — Crear los usuarios y asignarlos a Teams

```
Users → Add

── Usuario 1: Administrador de Plataforma ───────────────────────
  Username:   plataforma1
  First Name: Ana
  Last Name:  García
  Email:      ana.garcia@empresa.com
  Password:   PlatPass123!
  User Type:  Normal User
  → Save
  → Teams tab → Add Team: Platform

── Usuario 2: Operador de Aplicaciones ──────────────────────────
  Username:   operador1
  First Name: Carlos
  Last Name:  López
  Email:      carlos.lopez@empresa.com
  Password:   OpsPass123!
  User Type:  Normal User
  → Save
  → Teams tab → Add Team: AppOps

── Usuario 3: Ingeniero de Seguridad ────────────────────────────
  Username:   secops1
  First Name: María
  Last Name:  Martínez
  Email:      maria.martinez@empresa.com
  Password:   SecPass123!
  User Type:  Normal User
  → Save
  → Teams tab → Add Team: SecOps
  → Teams tab → Add Team: Change Advisory Board

── Usuario 4: Auditor ───────────────────────────────────────────
  Username:   auditor1
  First Name: Pedro
  Last Name:  Sánchez
  Email:      pedro.sanchez@empresa.com
  Password:   AuditPass123!
  User Type:  Normal User
  → Save
  → Teams tab → Add Team: Auditores

── Usuario 5: Cuenta de servicio CI/CD ──────────────────────────
  Username:   svc-cicd
  First Name: CI
  Last Name:  CD Service Account
  Email:      cicd@empresa.com
  Password:   (generada aleatoriamente, no se usa para login)
  User Type:  Normal User
  → Save
  → Teams tab → Add Team: CI-CD-Automation
```

## Paso 3 — Asignar roles de Organización

```
Organizations → MiEmpresa → Access → Add

  Team: Platform            → Role: Admin
  Team: AppOps              → Role: Member
  Team: SecOps              → Role: Member
  Team: Change Advisory Board → Role: Member
  Team: Auditores           → Role: Auditor
  Team: CI-CD-Automation    → Role: Member
```

## Paso 4 — Verificar via API

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver todos los teams y sus miembros
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/teams/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total teams: {data[\"count\"]}')
for team in data['results']:
    print(f'  Team: {team[\"name\"]:30} | Org: {team[\"summary_fields\"][\"organization\"][\"name\"]}')
"

# Ver miembros de un team específico
TEAM_ID=2  # ajusta
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/teams/${TEAM_ID}/users/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Miembros del team:')
for user in data['results']:
    print(f'  {user[\"username\"]:20} | {user[\"first_name\"]} {user[\"last_name\"]}')
"
```

---

# 5.10 LAB — Delegar ejecución sin exponer credenciales

*El patrón más importante de RBAC en AWX: los operadores ejecutan sin ver secretos.*

## Paso 1 — Verificar que las credenciales existen (creadas en Módulo 2)

```bash
# Listar credenciales disponibles
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/credentials/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cred in data['results']:
    print(f'ID:{cred[\"id\"]:3} | {cred[\"name\"]:30} | Tipo: {cred[\"credential_type\"]}')
"
```

## Paso 2 — Asignar roles en el Job Template

```
Templates → Web App Deploy → Access → Add

# AppOps puede ejecutar pero no modificar
  Team: AppOps
  Role: Execute
  → Save

# AppOps puede ver los logs
  Team: AppOps
  Role: Read
  → Save

# SecOps puede ver pero no ejecutar
  Team: SecOps
  Role: Read
  → Save

# Auditores solo pueden ver
  Team: Auditores
  Role: Read
  → Save

# CI/CD puede ejecutar
  Team: CI-CD-Automation
  Role: Execute
  → Save

# Platform tiene control total (ya lo tiene via Org Admin)
# No necesita asignación adicional
```

## Paso 3 — Asignar roles en el Inventario

```
Inventories → Env Inventory → Access → Add

  Team: AppOps              → Role: Read
  Team: SecOps              → Role: Read
  Team: Auditores           → Role: Read
  Team: CI-CD-Automation    → Role: Read

# Platform ya tiene acceso via Org Admin
# NADIE excepto Platform tiene Use o Admin en el inventario
```

## Paso 4 — NO asignar roles en Credenciales a operadores

```
# CORRECTO: Las credenciales NO tienen roles para AppOps, SecOps ni Auditores
# Solo Platform tiene acceso a las credenciales
# Los operadores usan las credenciales A TRAVÉS de los templates

# Verificar que AppOps NO tiene acceso a las credenciales:
CRED_ID=1  # Platform SSH
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/credentials/${CRED_ID}/access_list/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Acceso a la credencial:')
for access in data['results']:
    roles = [r['name'] for r in access.get('summary_fields', {}).get('direct_access', [])]
    if roles:
        print(f'  {access[\"username\"]:20} | Roles: {roles}')
"
# Solo debe aparecer Platform / admin
```

## Paso 5 — Verificar el acceso como operador1

```bash
# Login como operador1 y verificar qué puede hacer
OPERADOR_AUTH="operador1:OpsPass123!"

# ¿Puede ver el template?
curl -s -u "${OPERADOR_AUTH}" \
  "${AWX_URL}/api/v2/job_templates/?name=Web+App+Deploy" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    jt = data['results'][0]
    print(f'✅ Puede VER el template: {jt[\"name\"]}')
    print(f'   Can Execute: {jt[\"summary_fields\"][\"user_capabilities\"][\"start\"]}')
    print(f'   Can Edit:    {jt[\"summary_fields\"][\"user_capabilities\"][\"edit\"]}')
    print(f'   Can Delete:  {jt[\"summary_fields\"][\"user_capabilities\"][\"delete\"]}')
else:
    print('❌ No puede ver el template')
"

# ¿Puede ver las credenciales?
curl -s -u "${OPERADOR_AUTH}" \
  "${AWX_URL}/api/v2/credentials/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Credenciales visibles para operador1: {data[\"count\"]}')
# Debe ser 0 o solo las que explícitamente se le asignaron
"

# ¿Puede lanzar el template?
curl -s -u "${OPERADOR_AUTH}" \
  -X POST \
  -H "Content-Type: application/json" \
  "${AWX_URL}/api/v2/job_templates/1/launch/" \
  -d '{
    "extra_vars": {
      "app_version": "v1.0.0",
      "environment": "dev",
      "target_group": "dev"
    }
  }' \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'id' in data:
    print(f'✅ Puede LANZAR el template: Job ID {data[\"id\"]}')
elif data.get('detail') == 'You do not have permission to perform this action.':
    print('❌ No tiene permiso para lanzar')
else:
    print(f'Respuesta: {data}')
"
```

## Paso 6 — Verificar que operador1 no puede ver credenciales

```bash
# Intentar acceder directamente a una credencial
CRED_ID=1
curl -s -u "${OPERADOR_AUTH}" \
  "${AWX_URL}/api/v2/credentials/${CRED_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'detail' in data and 'permission' in data['detail'].lower():
    print('✅ Correcto: operador1 NO puede ver la credencial')
elif 'name' in data:
    print(f'⚠️  operador1 SÍ puede ver la credencial: {data[\"name\"]}')
    print('   Revisar permisos de la credencial')
"
```

---

# 5.11 LAB — Acceso de solo lectura para auditores

## Paso 1 — Verificar el rol de Auditor en la Organización

```
Organizations → MiEmpresa → Access

# Verificar que Auditores tiene rol "Auditor"
# El rol Auditor da acceso de lectura a TODOS los objetos de la org
# sin necesidad de asignaciones individuales
```

## Paso 2 — Verificar el acceso como auditor1

```bash
AUDITOR_AUTH="auditor1:AuditPass123!"

# ¿Puede ver templates?
curl -s -u "${AUDITOR_AUTH}" \
  "${AWX_URL}/api/v2/job_templates/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Templates visibles: {data[\"count\"]}')
for jt in data['results'][:5]:
    caps = jt['summary_fields']['user_capabilities']
    print(f'  {jt[\"name\"]:40} | start:{caps[\"start\"]} edit:{caps[\"edit\"]}')
"
# Debe ver todos los templates pero start=false y edit=false

# ¿Puede ver inventarios?
curl -s -u "${AUDITOR_AUTH}" \
  "${AWX_URL}/api/v2/inventories/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Inventarios visibles: {data[\"count\"]}')
for inv in data['results']:
    caps = inv['summary_fields']['user_capabilities']
    print(f'  {inv[\"name\"]:30} | edit:{caps[\"edit\"]} delete:{caps[\"delete\"]}')
"

# ¿Puede ver jobs históricos?
curl -s -u "${AUDITOR_AUTH}" \
  "${AWX_URL}/api/v2/jobs/?order_by=-id&page_size=5" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Jobs visibles: {data[\"count\"]}')
for job in data['results'][:5]:
    print(f'  Job #{job[\"id\"]}: {job[\"name\"]} → {job[\"status\"]}')
"

# ¿Puede lanzar un template?
curl -s -u "${AUDITOR_AUTH}" \
  -X POST \
  -H "Content-Type: application/json" \
  "${AWX_URL}/api/v2/job_templates/1/launch/" \
  -d '{}' \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'detail' in data:
    print(f'✅ Correcto: auditor1 NO puede lanzar: {data[\"detail\"]}')
else:
    print(f'⚠️  auditor1 pudo lanzar: {data}')
"
```

## Paso 3 — Crear un informe de auditoría básico

```bash
#!/usr/bin/env python3
# script: audit_report.py
# Genera un informe de auditoría de AWX

import requests
import json
from datetime import datetime, timedelta

AWX_URL   = "http://localhost:30080"
AWX_TOKEN = "tu-token-admin"

headers = {
    "Authorization": f"Bearer {AWX_TOKEN}",
    "Content-Type": "application/json"
}

def get_all(endpoint, params=None):
    results = []
    url = f"{AWX_URL}/api/v2/{endpoint}/"
    while url:
        resp = requests.get(url, headers=headers, params=params, timeout=30)
        data = resp.json()
        results.extend(data.get('results', []))
        url = data.get('next')
        params = None  # solo en la primera página
    return results

print("=" * 60)
print(f"INFORME DE AUDITORÍA AWX")
print(f"Generado: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}")
print("=" * 60)

# Usuarios y sus roles
print("\n📋 USUARIOS Y TIPOS:")
users = get_all("users")
for user in users:
    user_type = "System Admin" if user['is_superuser'] else \
                "System Auditor" if user['is_system_auditor'] else "Normal User"
    print(f"  {user['username']:25} | {user_type:15} | "
          f"Último login: {user.get('last_login', 'nunca')[:10] if user.get('last_login') else 'nunca'}")

# Jobs de las últimas 24 horas
print("\n📊 JOBS (últimas 24 horas):")
since = (datetime.utcnow() - timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%SZ')
jobs = get_all("jobs", params={"created__gte": since, "order_by": "-id"})
status_count = {}
for job in jobs:
    status_count[job['status']] = status_count.get(job['status'], 0) + 1
for status, count in status_count.items():
    icon = "✅" if status == "successful" else "❌" if status == "failed" else "⏳"
    print(f"  {icon} {status:15}: {count}")

# Credenciales (solo nombres, no valores)
print("\n🔑 CREDENCIALES REGISTRADAS:")
creds = get_all("credentials")
for cred in creds:
    print(f"  {cred['name']:35} | Tipo: {cred['credential_type']}")

# Activity stream de las últimas 24 horas
print("\n📝 ACTIVIDAD RECIENTE (últimas 24 horas):")
events = get_all("activity_stream",
                 params={"timestamp__gte": since, "order_by": "-timestamp"})
print(f"  Total eventos: {len(events)}")
ops_count = {}
for event in events:
    ops_count[event['operation']] = ops_count.get(event['operation'], 0) + 1
for op, count in sorted(ops_count.items(), key=lambda x: -x[1]):
    print(f"  {op:15}: {count}")

print("\n" + "=" * 60)
print("FIN DEL INFORME")
```

```bash
# Ejecutar el informe
python3 audit_report.py > audit_report_$(date +%Y%m%d).txt
cat audit_report_$(date +%Y%m%d).txt
```

---

# 5.12 LAB — Multi-tenancy con organizaciones separadas

## Paso 1 — Crear organizaciones separadas

```
Organizations → Add

── Organización 1: BU-Retail ────────────────────────────────────
  Name:         BU-Retail
  Description:  Unidad de negocio: Retail
  → Save

── Organización 2: BU-Finance ───────────────────────────────────
  Name:         BU-Finance
  Description:  Unidad de negocio: Finance
  → Save
```

## Paso 2 — Crear teams y usuarios por organización

```
# Para BU-Retail
Teams → Add
  Name:         Platform-Retail
  Organization: BU-Retail
  → Save

Teams → Add
  Name:         Ops-Retail
  Organization: BU-Retail
  → Save

Users → Add
  Username:     platform-retail1
  → Save → Teams: Platform-Retail

Users → Add
  Username:     ops-retail1
  → Save → Teams: Ops-Retail

# Asignar roles en BU-Retail
Organizations → BU-Retail → Access
  Team: Platform-Retail → Role: Admin
  Team: Ops-Retail      → Role: Member

# Repetir para BU-Finance
Teams → Add
  Name:         Platform-Finance
  Organization: BU-Finance
  → Save
# ... etc
```

## Paso 3 — Crear recursos separados por organización

```
# Inventario para BU-Retail
Inventories → Add
  Name:         Retail Inventory
  Organization: BU-Retail
  → Save → Añadir hosts de retail

# Credencial para BU-Retail
Credentials → Add
  Name:         Retail SSH
  Organization: BU-Retail
  Type:         Machine
  → Save

# Proyecto para BU-Retail
Projects → Add
  Name:         Retail Playbooks
  Organization: BU-Retail
  SCM URL:      https://github.com/empresa/retail-playbooks.git
  → Save
```

## Paso 4 — Verificar el aislamiento

```bash
# Login como platform-retail1
RETAIL_AUTH="platform-retail1:RetailPass123!"

# ¿Puede ver recursos de BU-Finance?
curl -s -u "${RETAIL_AUTH}" \
  "${AWX_URL}/api/v2/inventories/?organization__name=BU-Finance" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] == 0:
    print('✅ Correcto: platform-retail1 NO puede ver inventarios de BU-Finance')
else:
    print(f'⚠️  platform-retail1 VE {data[\"count\"]} inventarios de BU-Finance')
"

# ¿Solo ve recursos de su organización?
curl -s -u "${RETAIL_AUTH}" \
  "${AWX_URL}/api/v2/inventories/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Inventarios visibles para platform-retail1: {data[\"count\"]}')
for inv in data['results']:
    org = inv['summary_fields']['organization']['name']
    print(f'  {inv[\"name\"]:30} | Org: {org}')
"
```

---

# 5.13 LAB — Instance Groups por entorno y tenant

## Paso 1 — Crear los Instance Groups

```
Administration → Instance Groups → Add

── ig-dev ───────────────────────────────────────────────────────
  Name:                     ig-dev
  Policy Instance Minimum:  1
  Policy Instance Percentage: 0
  Max Concurrent Jobs:      10
  Max Forks:                50
  → Save

── ig-stage ─────────────────────────────────────────────────────
  Name:                     ig-stage
  Policy Instance Minimum:  1
  Policy Instance Percentage: 0
  Max Concurrent Jobs:      5
  Max Forks:                30
  → Save

── ig-prod ──────────────────────────────────────────────────────
  Name:                     ig-prod
  Policy Instance Minimum:  2
  Policy Instance Percentage: 50
  Max Concurrent Jobs:      5
  Max Forks:                50
  → Save
```

## Paso 2 — Asignar instancias a los grupos

```bash
# Ver las instancias disponibles
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/instances/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Instancias disponibles: {data[\"count\"]}')
for inst in data['results']:
    print(f'  ID:{inst[\"id\"]} | {inst[\"hostname\"]:30} | Capacity: {inst[\"capacity\"]}')
"

# Asignar instancia al Instance Group ig-prod
# (via UI: Administration → Instance Groups → ig-prod → Instances → Add)
```

## Paso 3 — Asignar Instance Groups a Templates

```
# Templates de dev
Templates → WF - Configure App → Edit
  Instance Group: ig-dev
  → Save

# Templates de prod
Templates → WF - Deploy to Prod → Edit
  Instance Group: ig-prod
  → Save

# También se puede asignar a nivel de Inventario
Inventories → Env Inventory → Edit
  Instance Group: ig-dev  (default para este inventario)
  → Save
```

## Paso 4 — Verificar el enrutamiento

```bash
# Lanzar un job y verificar en qué Instance Group se ejecutó
JOB_ID=10
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/jobs/${JOB_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
ig = data.get('summary_fields', {}).get('instance_group', {})
print(f'Job #{data[\"id\"]} ejecutado en Instance Group: {ig.get(\"name\", \"default\")}')
print(f'Execution Node: {data.get(\"execution_node\", \"N/A\")}')
"
```

---

# 5.14 LAB — Integración con LDAP/SSO

*Configurar AWX para autenticar contra Active Directory o LDAP corporativo.*

## Configuración LDAP básica

```
Administration → Authentication → LDAP

── Configuración de conexión ────────────────────────────────────
  LDAP Server URI:
    ldap://ldap.empresa.com:389
    (o ldaps://ldap.empresa.com:636 para TLS)

  LDAP Bind DN:
    CN=awx-service,OU=ServiceAccounts,DC=empresa,DC=com

  LDAP Bind Password:
    (contraseña de la cuenta de servicio)

  LDAP Start TLS: ✅ (si usas ldap:// con STARTTLS)

── Búsqueda de usuarios ─────────────────────────────────────────
  LDAP User Search:
    [
      "OU=Users,DC=empresa,DC=com",
      "SCOPE_SUBTREE",
      "(sAMAccountName=%(user)s)"
    ]

  LDAP User DN Template: (dejar vacío si usas User Search)

  LDAP User Attribute Map:
    {
      "first_name": "givenName",
      "last_name":  "sn",
      "email":      "mail"
    }

── Búsqueda de grupos ───────────────────────────────────────────
  LDAP Group Search:
    [
      "OU=Groups,DC=empresa,DC=com",
      "SCOPE_SUBTREE",
      "(objectClass=group)"
    ]

  LDAP Group Type: MemberDNGroupType
  LDAP Group Type Parameters:
    {
      "member_attr": "member",
      "name_attr": "cn"
    }

── Mapeo de grupos LDAP a Teams AWX ─────────────────────────────
  LDAP Organization Map:
    {
      "MiEmpresa": {
        "admins": "CN=AWX-Admins,OU=Groups,DC=empresa,DC=com",
        "auditors": "CN=AWX-Auditors,OU=Groups,DC=empresa,DC=com",
        "users": true
      }
    }

  LDAP Team Map:
    {
      "Platform": {
        "organization": "MiEmpresa",
        "users": "CN=AWX-Platform,OU=Groups,DC=empresa,DC=com",
        "remove": true
      },
      "AppOps": {
        "organization": "MiEmpresa",
        "users": "CN=AWX-AppOps,OU=Groups,DC=empresa,DC=com",
        "remove": true
      },
      "Auditores": {
        "organization": "MiEmpresa",
        "users": "CN=AWX-Auditors,OU=Groups,DC=empresa,DC=com",
        "remove": true
      }
    }
```

## Configuración SAML/SSO (para Okta, Azure AD, etc.)

```
Administration → Authentication → SAML

  SAML Service Provider Entity ID:
    https://awx.empresa.com/sso/metadata/saml/

  SAML Service Provider Public Certificate:
    (certificado X.509 del SP)

  SAML Service Provider Private Key:
    (clave privada del SP)

  SAML Identity Providers:
    {
      "Okta": {
        "attr_user_permanent_id": "name_id",
        "attr_first_name": "User.FirstName",
        "attr_last_name": "User.LastName",
        "attr_username": "User.email",
        "attr_email": "User.email",
        "entity_id": "https://empresa.okta.com/app/xxx/sso/saml/metadata",
        "url": "https://empresa.okta.com/app/xxx/sso/saml",
        "x509cert": "MIIC..."
      }
    }

  SAML Organization Map:
    {
      "MiEmpresa": {
        "admins": false,
        "auditors": false,
        "users": true
      }
    }

  SAML Team Map:
    {
      "Platform": {
        "organization": "MiEmpresa",
        "users": ["AWX-Platform"],
        "remove": true
      }
    }
```

## Verificar la integración LDAP

```bash
# Probar la conexión LDAP desde el pod de AWX
kubectl exec -n awx deployment/awx-task -c awx-task -- \
  python3 -c "
import ldap
conn = ldap.initialize('ldap://ldap.empresa.com:389')
conn.simple_bind_s(
    'CN=awx-service,OU=ServiceAccounts,DC=empresa,DC=com',
    'password'
)
result = conn.search_s(
    'OU=Users,DC=empresa,DC=com',
    ldap.SCOPE_SUBTREE,
    '(sAMAccountName=operador1)'
)
print(f'Usuario encontrado: {result[0][1].get(\"cn\", [b\"N/A\"])[0].decode()}')
"

# Ver los logs de autenticación LDAP
kubectl logs -n awx deployment/awx-task -c awx-task \
  | grep -i ldap | tail -20
```
# 5.15 Patrones avanzados y buenas prácticas

## Patrón 1: Revisión periódica de permisos

La acumulación de permisos con el tiempo es uno de los riesgos más comunes en plataformas de automatización. Un usuario que cambió de equipo sigue teniendo acceso al equipo anterior. Una cuenta de servicio de un proyecto cancelado sigue activa. La revisión periódica lo detecta.

```bash
#!/usr/bin/env python3
# script: review_permissions.py
# Genera un informe completo de todos los permisos asignados en AWX
# Ejecutar mensualmente como tarea de revisión de accesos

import requests
import json
from datetime import datetime

AWX_URL   = "http://localhost:30080"
AWX_TOKEN = "tu-token-admin"
HEADERS   = {
    "Authorization": f"Bearer {AWX_TOKEN}",
    "Content-Type":  "application/json"
}

def get_all(endpoint, params=None):
    """Pagina automáticamente por todos los resultados."""
    results = []
    url = f"{AWX_URL}/api/v2/{endpoint}/"
    while url:
        resp = requests.get(url, headers=HEADERS, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        results.extend(data.get('results', []))
        url  = data.get('next')
        params = None
    return results

def get_access_list(object_type, object_id):
    """Obtiene la lista de accesos de un objeto específico."""
    resp = requests.get(
        f"{AWX_URL}/api/v2/{object_type}/{object_id}/access_list/",
        headers=HEADERS, timeout=30
    )
    return resp.json().get('results', [])

print("=" * 70)
print(f"REVISIÓN DE PERMISOS AWX")
print(f"Generado: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}")
print("=" * 70)

# ── 1. Usuarios con privilegios elevados ──────────────────────────
print("\n⚠️  USUARIOS CON PRIVILEGIOS ELEVADOS:")
users = get_all("users")
elevated = [u for u in users if u['is_superuser'] or u['is_system_auditor']]
if elevated:
    for user in elevated:
        level = "🔴 SYSTEM ADMIN" if user['is_superuser'] else "🟡 SYSTEM AUDITOR"
        last_login = user.get('last_login', 'nunca')
        last_login = last_login[:10] if last_login else 'nunca'
        print(f"  {level}: {user['username']:25} | {user['email']:35} | Último login: {last_login}")
else:
    print("  ✅ No hay usuarios con privilegios elevados (solo admin)")

# ── 2. Usuarios sin actividad reciente ────────────────────────────
print("\n🕐 USUARIOS SIN LOGIN EN LOS ÚLTIMOS 90 DÍAS:")
from datetime import timedelta
cutoff = datetime.utcnow() - timedelta(days=90)
inactive = []
for user in users:
    if user['username'] == 'admin':
        continue
    last_login = user.get('last_login')
    if not last_login:
        inactive.append((user['username'], 'nunca'))
    else:
        login_dt = datetime.fromisoformat(last_login.replace('Z', '+00:00').replace('+00:00', ''))
        if login_dt < cutoff:
            inactive.append((user['username'], last_login[:10]))

if inactive:
    for username, last_login in inactive:
        print(f"  ⚠️  {username:25} | Último login: {last_login}")
else:
    print("  ✅ Todos los usuarios tienen actividad reciente")

# ── 3. Teams y sus miembros ───────────────────────────────────────
print("\n👥 TEAMS Y MIEMBROS:")
teams = get_all("teams")
for team in teams:
    members_resp = requests.get(
        f"{AWX_URL}/api/v2/teams/{team['id']}/users/",
        headers=HEADERS, timeout=30
    )
    members = members_resp.json().get('results', [])
    org = team['summary_fields']['organization']['name']
    print(f"\n  Team: {team['name']} (Org: {org})")
    if members:
        for member in members:
            print(f"    → {member['username']:25} | {member['email']}")
    else:
        print(f"    ⚠️  Sin miembros (team vacío)")

# ── 4. Acceso a Job Templates ─────────────────────────────────────
print("\n📋 ACCESO A JOB TEMPLATES:")
templates = get_all("job_templates")
for jt in templates:
    access_list = get_access_list("job_templates", jt['id'])
    has_access = False
    for entry in access_list:
        direct = entry.get('summary_fields', {}).get('direct_access', [])
        for role_info in direct:
            if not has_access:
                print(f"\n  Template: {jt['name']}")
                has_access = True
            role_name = role_info['role']['name']
            icon = "🔴" if role_name == "Admin" else "🟢" if role_name == "Execute" else "🔵"
            print(f"    {icon} {entry['username']:25} | {role_name}")

# ── 5. Credenciales y quién tiene acceso ──────────────────────────
print("\n🔑 ACCESO A CREDENCIALES:")
credentials = get_all("credentials")
for cred in credentials:
    access_list = get_access_list("credentials", cred['id'])
    has_access = False
    for entry in access_list:
        direct = entry.get('summary_fields', {}).get('direct_access', [])
        for role_info in direct:
            if not has_access:
                print(f"\n  Credencial: {cred['name']}")
                has_access = True
            role_name = role_info['role']['name']
            # Alertar si alguien que no debería tiene Use o Admin
            if role_name in ['Admin', 'Use'] and entry['username'] not in ['admin']:
                print(f"    ⚠️  {entry['username']:25} | {role_name} ← REVISAR")
            else:
                print(f"    ✅ {entry['username']:25} | {role_name}")

# ── 6. Tokens activos ─────────────────────────────────────────────
print("\n🎫 TOKENS DE API ACTIVOS:")
tokens = get_all("tokens")
for token in tokens:
    user = token.get('summary_fields', {}).get('user', {})
    expires = token.get('expires', 'nunca')
    expires_str = expires[:10] if expires and expires != 'never' else 'sin expiración ⚠️'
    scope = token.get('scope', 'N/A')
    print(f"  {user.get('username', 'N/A'):25} | Scope: {scope:8} | Expira: {expires_str}")

print("\n" + "=" * 70)
print("FIN DE LA REVISIÓN")
print("Acciones recomendadas:")
print("  1. Desactivar usuarios sin actividad en 90+ días")
print("  2. Revocar tokens sin expiración o muy antiguos")
print("  3. Revisar teams vacíos y eliminarlos")
print("  4. Verificar que ningún operador tiene Admin en credenciales")
print("=" * 70)
```

```bash
# Ejecutar mensualmente
python3 review_permissions.py > /var/log/awx/permissions_review_$(date +%Y%m).txt

# Enviar por email al equipo de seguridad
mail -s "[AWX] Revisión mensual de permisos $(date +%Y-%m)" \
  secops@empresa.com \
  < /var/log/awx/permissions_review_$(date +%Y%m).txt
```

---

## Patrón 2: Cuentas de servicio para CI/CD con mínimo privilegio

```
ESTRUCTURA DE CUENTAS DE SERVICIO:

  svc-github-webapp    → solo Execute en "App Delivery Pipeline" (WebApp)
  svc-github-api       → solo Execute en "App Delivery Pipeline" (API)
  svc-gitlab-infra     → solo Execute en "Provision Infra Workflow"
  svc-jenkins-legacy   → solo Execute en templates legacy específicos

PRINCIPIOS:
  1. Una cuenta por sistema/pipeline (no una cuenta compartida)
  2. Solo Execute en los Workflows necesarios, nada más
  3. Token con expiración de 90 días, rotación automática
  4. Sin acceso a credenciales, inventarios ni proyectos
  5. Monitorizar el activity stream de estas cuentas
```

```bash
#!/bin/bash
# script: create_service_account.sh
# Crea una cuenta de servicio con mínimo privilegio

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

SERVICE_NAME="$1"       # ej: svc-github-webapp
WFT_ID="$2"             # ID del Workflow Template al que dar Execute
ORG_ID="$3"             # ID de la organización
TOKEN_EXPIRY_DAYS="${4:-90}"

if [ -z "$SERVICE_NAME" ] || [ -z "$WFT_ID" ] || [ -z "$ORG_ID" ]; then
    echo "Uso: $0 <nombre> <wft_id> <org_id> [dias_expiracion]"
    exit 1
fi

echo "Creando cuenta de servicio: ${SERVICE_NAME}"

# Generar contraseña aleatoria (no se usará para login)
RANDOM_PASS=$(openssl rand -base64 32)

# Crear el usuario
USER_RESPONSE=$(curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/users/" \
    -d "{
        \"username\":   \"${SERVICE_NAME}\",
        \"password\":   \"${RANDOM_PASS}\",
        \"first_name\": \"Service\",
        \"last_name\":  \"Account\",
        \"email\":      \"${SERVICE_NAME}@empresa.com\",
        \"is_superuser\": false,
        \"is_system_auditor\": false
    }")

USER_ID=$(echo "$USER_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  ✅ Usuario creado: ID=${USER_ID}"

# Añadir a la organización como Member
curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/organizations/${ORG_ID}/users/" \
    -d "{\"id\": ${USER_ID}}" > /dev/null
echo "  ✅ Añadido a la organización"

# Dar Execute en el Workflow Template
curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/workflow_job_templates/${WFT_ID}/object_roles/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for role in data['results']:
    if role['name'] == 'Execute':
        print(role['id'])
" | xargs -I{} curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/roles/{}/users/" \
    -d "{\"id\": ${USER_ID}}" > /dev/null
echo "  ✅ Rol Execute asignado en Workflow Template ${WFT_ID}"

# Calcular fecha de expiración
EXPIRY_DATE=$(date -u -d "+${TOKEN_EXPIRY_DAYS} days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v+${TOKEN_EXPIRY_DAYS}d '+%Y-%m-%dT%H:%M:%SZ')

# Crear token de API
TOKEN_RESPONSE=$(curl -s -u "${AWX_AUTH}" \
    -X POST \
    -H "Content-Type: application/json" \
    "${AWX_URL}/api/v2/users/${USER_ID}/tokens/" \
    -d "{
        \"description\": \"Token para ${SERVICE_NAME} - creado $(date +%Y-%m-%d)\",
        \"application\":  null,
        \"scope\":        \"write\",
        \"expires\":      \"${EXPIRY_DATE}\"
    }")

TOKEN_VALUE=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
TOKEN_ID=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "  ✅ Token creado: ID=${TOKEN_ID}, expira en ${TOKEN_EXPIRY_DAYS} días (${EXPIRY_DATE})"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "GUARDAR EN EL GESTOR DE SECRETOS:"
echo "  Nombre:  AWX_TOKEN_${SERVICE_NAME^^}"
echo "  Valor:   ${TOKEN_VALUE}"
echo "  Expira:  ${EXPIRY_DATE}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  Este token solo se muestra UNA VEZ. Guárdalo ahora."
```

```bash
# Uso del script
chmod +x create_service_account.sh

# Crear cuenta para GitHub Actions del proyecto WebApp
./create_service_account.sh svc-github-webapp 3 1 90

# Crear cuenta para GitLab CI del proyecto API
./create_service_account.sh svc-gitlab-api 4 1 90
```

---

## Patrón 3: Separación de duties en el pipeline

```
PRINCIPIO: Quien crea no aprueba. Quien aprueba no ejecuta.
           Quien ejecuta no ve los secretos.

FLUJO COMPLETO:

  Developer
    → Crea/modifica playbooks en Git
    → Abre PR → CI ejecuta lint y syntax-check
    → Merge a main → CI lanza Workflow AWX en stage
    → NO tiene acceso a AWX directamente

  Platform Engineer
    → Crea y mantiene Job Templates y Workflows en AWX
    → Tiene Admin en los templates
    → NO puede aprobar cambios en producción (conflicto de interés)
    → NO ejecuta deploys de negocio (solo infraestructura)

  AppOps
    → Lanza deploys en dev y stage directamente
    → Solicita deploy en prod lanzando el Workflow
    → El Workflow se pausa en el nodo de aprobación
    → NO puede aprobar su propio deploy

  Change Advisory Board
    → Recibe notificación de aprobación pendiente
    → Revisa el contexto: versión, ticket, tests
    → Aprueba o rechaza
    → NO puede lanzar deploys directamente

  Auditor
    → Ve todo el activity stream
    → Genera informes de compliance
    → NO puede ejecutar nada

IMPLEMENTACIÓN EN AWX:

  Templates → App Delivery Pipeline → Access:
    Team AppOps:               Execute  (puede lanzar)
    Team Change Advisory Board: Approve  (puede aprobar)
    Team Platform:             Admin    (puede gestionar)
    Team Auditores:            Read     (solo ver)

  NADIE tiene tanto Execute como Approve en el mismo workflow.
```

---

## Patrón 4: Rotación de credenciales sin downtime

```
PROBLEMA:
  Rotar la clave SSH de producción implica actualizar la credencial
  en AWX y en todos los authorized_keys de los hosts.
  Si se hace mal, AWX pierde acceso a producción.

SOLUCIÓN: Rotación con doble clave

PASO 1: Añadir la nueva clave a los hosts (sin eliminar la antigua)
  → Playbook: add_new_ssh_key.yml
  → Ejecuta con la credencial ANTIGUA (que aún funciona)
  → Añade la nueva clave pública a authorized_keys
  → Verifica que la nueva clave funciona

PASO 2: Actualizar la credencial en AWX
  → Credentials → Platform SSH Prod → Edit
  → SSH Private Key: (nueva clave)
  → Save

PASO 3: Verificar que AWX puede conectar con la nueva clave
  → Lanzar un job de ping/verificación
  → Confirmar que funciona

PASO 4: Eliminar la clave antigua de los hosts
  → Playbook: remove_old_ssh_key.yml
  → Ejecuta con la credencial NUEVA
  → Elimina la clave antigua de authorized_keys

RESULTADO:
  En ningún momento AWX pierde acceso a los hosts.
  La rotación es transparente para los operadores.
```

```yaml
# playbooks/rotate_ssh_key.yml
---
- name: Añadir nueva clave SSH a los hosts (fase 1 de rotación)
  hosts: "{{ target_group }}"
  become: true
  gather_facts: false

  vars:
    new_public_key: "{{ new_ssh_public_key }}"
    ansible_user:   ansible

  tasks:
    - name: Añadir nueva clave pública a authorized_keys
      ansible.posix.authorized_key:
        user:    "{{ ansible_user }}"
        key:     "{{ new_public_key }}"
        state:   present
        comment: "AWX Platform Key - rotated {{ ansible_date_time.date | default('today') }}"

    - name: Verificar que la nueva clave está en authorized_keys
      ansible.builtin.command:
        cmd: grep -c "AWX Platform Key" /home/{{ ansible_user }}/.ssh/authorized_keys
      register: key_count
      changed_when: false

    - name: Confirmar resultado
      ansible.builtin.debug:
        msg: "Nueva clave añadida correctamente. Total claves AWX: {{ key_count.stdout }}"

- name: Eliminar clave antigua (fase 2 de rotación)
  hosts: "{{ target_group }}"
  become: true
  gather_facts: false

  vars:
    old_public_key: "{{ old_ssh_public_key }}"
    ansible_user:   ansible

  tasks:
    - name: Eliminar clave pública antigua
      ansible.posix.authorized_key:
        user:  "{{ ansible_user }}"
        key:   "{{ old_public_key }}"
        state: absent

    - name: Verificar que la clave antigua ya no está
      ansible.builtin.command:
        cmd: cat /home/{{ ansible_user }}/.ssh/authorized_keys
      register: auth_keys
      changed_when: false

    - name: Confirmar limpieza
      ansible.builtin.debug:
        msg: "Rotación completada. Claves actuales: {{ auth_keys.stdout_lines | length }} líneas"
```

---

## Patrón 5: Vault dinámico con HashiCorp Vault

Para entornos con alta exigencia de seguridad, integrar AWX con HashiCorp Vault permite que las credenciales nunca se almacenen en AWX: se obtienen dinámicamente en el momento de la ejecución.

```
FLUJO SIN VAULT DINÁMICO:
  Credencial almacenada en AWX (cifrada en BD)
  → AWX la descifra al ejecutar el job
  → La pasa al playbook como variable de entorno

FLUJO CON VAULT DINÁMICO:
  AWX tiene un AppRole de Vault (solo para leer secretos)
  → Al ejecutar el job, AWX llama a Vault
  → Vault devuelve el secreto (con TTL corto)
  → AWX lo pasa al playbook
  → El secreto expira automáticamente

VENTAJAS:
  → Los secretos no se almacenan en AWX
  → Rotación automática de secretos en Vault
  → Auditoría centralizada en Vault
  → Secretos con TTL: si se filtran, expiran solos
```

```
AWX UI → Credentials → Add

  Name:         HashiCorp Vault AppRole
  Type:         HashiCorp Vault Secret Lookup

  Server URL:   https://vault.empresa.com:8200
  Token:        (AppRole token o Vault Token)
  
  Path to Secret:  secret/data/awx/ssh/prod
  Secret Key:      private_key

# Luego crear la credencial de tipo Machine que usa el lookup:
Credentials → Add
  Name:         Platform SSH Prod (Vault Dynamic)
  Type:         Machine
  Username:     ansible
  SSH Private Key: (usar el lookup de Vault)
    → Click en el icono de llave junto al campo
    → Seleccionar: HashiCorp Vault AppRole
    → Secret path: secret/data/awx/ssh/prod
    → Secret key: private_key
```

---

## Patrón 6: Alertas de seguridad en el Activity Stream

```bash
#!/usr/bin/env python3
# script: security_alerts.py
# Monitoriza el activity stream en busca de eventos sospechosos
# Ejecutar como cron cada 15 minutos

import requests
import json
from datetime import datetime, timedelta

AWX_URL   = "http://localhost:30080"
AWX_TOKEN = "tu-token-admin"
HEADERS   = {"Authorization": f"Bearer {AWX_TOKEN}"}
SLACK_WEBHOOK = "https://hooks.slack.com/services/xxx/yyy/zzz"

SUSPICIOUS_PATTERNS = [
    # Cambios en credenciales de producción
    {
        "condition": lambda e: e.get('object1') == 'credential' and e.get('operation') in ['update', 'delete'],
        "severity":  "HIGH",
        "message":   "Credencial modificada/eliminada"
    },
    # Nuevos System Admins
    {
        "condition": lambda e: e.get('object1') == 'user' and e.get('operation') == 'update'
                               and 'is_superuser' in str(e.get('changes', {})),
        "severity":  "CRITICAL",
        "message":   "Cambio en privilegios de System Admin"
    },
    # Acceso fuera de horario (22:00 - 06:00 UTC)
    {
        "condition": lambda e: (
            datetime.fromisoformat(e['timestamp'].replace('Z', '')).hour >= 22
            or datetime.fromisoformat(e['timestamp'].replace('Z', '')).hour < 6
        ) and e.get('operation') in ['create', 'update', 'delete'],
        "severity":  "MEDIUM",
        "message":   "Actividad fuera de horario laboral"
    },
    # Eliminación de templates o workflows
    {
        "condition": lambda e: e.get('object1') in ['job_template', 'workflow_job_template']
                               and e.get('operation') == 'delete',
        "severity":  "HIGH",
        "message":   "Template eliminado"
    },
    # Cambios en permisos (roles)
    {
        "condition": lambda e: e.get('operation') in ['associate', 'disassociate']
                               and 'role' in str(e.get('object2', '')),
        "severity":  "MEDIUM",
        "message":   "Cambio en permisos/roles"
    },
]

def check_events():
    since = (datetime.utcnow() - timedelta(minutes=20)).strftime('%Y-%m-%dT%H:%M:%SZ')
    resp = requests.get(
        f"{AWX_URL}/api/v2/activity_stream/",
        headers=HEADERS,
        params={"timestamp__gte": since, "order_by": "-timestamp", "page_size": 100},
        timeout=30
    )
    events = resp.json().get('results', [])
    alerts = []

    for event in events:
        for pattern in SUSPICIOUS_PATTERNS:
            try:
                if pattern["condition"](event):
                    actor = event.get('actor', {})
                    actor_name = actor.get('username', 'system') if actor else 'system'
                    alerts.append({
                        "severity":  pattern["severity"],
                        "message":   pattern["message"],
                        "actor":     actor_name,
                        "operation": event.get('operation'),
                        "object":    event.get('object1'),
                        "timestamp": event.get('timestamp', '')[:19],
                        "url":       f"{AWX_URL}/#/activity_stream"
                    })
            except Exception:
                pass

    return alerts

def send_slack_alert(alerts):
    if not alerts:
        return

    blocks = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": "🚨 AWX Security Alerts"}
        }
    ]

    for alert in alerts:
        color = "#ff0000" if alert['severity'] == "CRITICAL" else \
                "#ff6600" if alert['severity'] == "HIGH" else "#ffcc00"
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{alert['severity']}* — {alert['message']}\n"
                        f"Actor: `{alert['actor']}` | Op: `{alert['operation']}` | "
                        f"Objeto: `{alert['object']}` | `{alert['timestamp']}`"
            }
        })

    payload = {"blocks": blocks}
    requests.post(SLACK_WEBHOOK, json=payload, timeout=10)
    print(f"Enviadas {len(alerts)} alertas a Slack")

alerts = check_events()
if alerts:
    send_slack_alert(alerts)
    for alert in alerts:
        print(f"[{alert['severity']}] {alert['message']} | {alert['actor']} | {alert['timestamp']}")
else:
    print("Sin alertas de seguridad en los últimos 20 minutos")
```

```bash
# Añadir al crontab
crontab -e
# */15 * * * * /usr/bin/python3 /opt/awx-scripts/security_alerts.py >> /var/log/awx/security_alerts.log 2>&1
```

---

## Patrón 7: Gestión de tokens con expiración automática

```bash
#!/bin/bash
# script: rotate_ci_tokens.sh
# Rota automáticamente los tokens de cuentas de servicio antes de que expiren

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
DAYS_BEFORE_EXPIRY=14  # renovar si expiran en menos de 14 días

echo "=== Revisión de tokens próximos a expirar ==="

# Obtener todos los tokens
TOKENS=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/tokens/?page_size=100" \
    | python3 -c "
import sys, json
from datetime import datetime, timedelta, timezone

data = json.load(sys.stdin)
cutoff = datetime.now(timezone.utc) + timedelta(days=${DAYS_BEFORE_EXPIRY})
expiring = []

for token in data['results']:
    expires = token.get('expires')
    if expires and expires != 'never':
        exp_dt = datetime.fromisoformat(expires.replace('Z', '+00:00'))
        if exp_dt < cutoff:
            user = token.get('summary_fields', {}).get('user', {})
            expiring.append({
                'id':       token['id'],
                'user':     user.get('username', 'N/A'),
                'user_id':  user.get('id', 0),
                'expires':  expires[:10],
                'scope':    token.get('scope', 'N/A')
            })

import json as j
print(j.dumps(expiring))
")

echo "$TOKENS" | python3 -c "
import sys, json, subprocess, os

tokens = json.load(sys.stdin)
if not tokens:
    print('✅ No hay tokens próximos a expirar')
    sys.exit(0)

print(f'Tokens próximos a expirar: {len(tokens)}')
for token in tokens:
    print(f'  Token ID:{token[\"id\"]} | User: {token[\"user\"]:25} | Expira: {token[\"expires\"]}')
"

# Para cada token próximo a expirar, crear uno nuevo y revocar el antiguo
# (Implementación completa requiere integración con el gestor de secretos)
echo ""
echo "Para rotar un token manualmente:"
echo "  1. Crear nuevo token: AWX UI → Users → <usuario> → Tokens → Add"
echo "  2. Actualizar el secret en GitHub/GitLab/Jenkins"
echo "  3. Revocar el token antiguo: AWX UI → Users → <usuario> → Tokens → Delete"
```

---

## Patrón 8: Hardening de la configuración de AWX

```bash
#!/bin/bash
# script: awx_hardening_check.sh
# Verifica que AWX está configurado de forma segura

AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"
PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    local expected="$3"

    if [ "$result" = "$expected" ]; then
        echo "  ✅ PASS: ${description}"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: ${description}"
        echo "     Esperado: ${expected} | Obtenido: ${result}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== AWX Security Hardening Check ==="
echo ""

# Obtener configuración global
CONFIG=$(curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/settings/all/")

# 1. Verificar que el registro de usuarios está deshabilitado
ALLOW_SIGNUP=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ALLOW_OAUTH2_FOR_EXTERNAL_USERS', False))")
check "Registro público de usuarios deshabilitado" "$ALLOW_SIGNUP" "False"

# 2. Verificar que la sesión expira
SESSION_TIMEOUT=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('SESSION_COOKIE_AGE', 0))")
check "Timeout de sesión configurado (< 28800s = 8h)" \
    "$([ "$SESSION_TIMEOUT" -lt 28800 ] && echo 'ok' || echo 'fail')" "ok"

# 3. Verificar que los logs de jobs no se guardan indefinidamente
STDOUT_MAX=$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('STDOUT_MAX_BYTES_DISPLAY', 0))")
check "Límite de stdout configurado" "$([ "$STDOUT_MAX" -gt 0 ] && echo 'ok' || echo 'fail')" "ok"

# 4. Verificar que hay al menos 2 System Admins (para recuperación)
ADMIN_COUNT=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/users/?is_superuser=true" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
check "Al menos 2 System Admins configurados" \
    "$([ "$ADMIN_COUNT" -ge 2 ] && echo 'ok' || echo 'fail')" "ok"

# 5. Verificar que no hay usuarios sin organización
ORPHAN_USERS=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/users/" \
    | python3 -c "
import sys, json, requests
data = json.load(sys.stdin)
orphans = 0
for user in data['results']:
    if not user['is_superuser'] and user['username'] != 'admin':
        # verificar si tiene alguna organización
        pass  # simplificado
print(0)  # placeholder
")
check "Sin usuarios huérfanos sin organización" "$ORPHAN_USERS" "0"

# 6. Verificar que los tokens tienen expiración
TOKENS_NO_EXPIRY=$(curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/tokens/?page_size=100" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
no_expiry = sum(1 for t in data['results'] if not t.get('expires') or t.get('expires') == 'never')
print(no_expiry)
")
check "Tokens sin expiración: 0" "$TOKENS_NO_EXPIRY" "0"

# 7. Verificar que AWX usa HTTPS (si está en producción)
HTTPS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://awx.empresa.com/api/v2/" 2>/dev/null || echo "000")
if [ "$HTTPS_CHECK" = "200" ] || [ "$HTTPS_CHECK" = "301" ]; then
    echo "  ✅ PASS: HTTPS configurado"
    PASS=$((PASS + 1))
else
    echo "  ⚠️  WARN: HTTPS no verificado (puede ser entorno de lab)"
fi

echo ""
echo "=== RESULTADO ==="
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "✅ Configuración de seguridad correcta"
else
    echo "❌ ${FAIL} verificaciones fallidas. Revisar y corregir."
fi
```

---

# 5.16 Troubleshooting del Módulo 5

## Problema 1: Usuario no puede ver los templates que debería ver

**Síntoma:**
```
El usuario operador1 pertenece al team AppOps pero cuando
hace login en AWX no ve ningún Job Template.
```

**Diagnóstico:**
```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Verificar que el usuario existe y está activo
USERNAME="operador1"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/users/?username=${USERNAME}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    user = data['results'][0]
    print(f'Usuario: {user[\"username\"]}')
    print(f'Activo:  {not user.get(\"is_inactive\", False)}')
    print(f'Tipo:    {\"Admin\" if user[\"is_superuser\"] else \"Normal\"}')
else:
    print('❌ Usuario no encontrado')
"

# Verificar que el usuario está en el team AppOps
TEAM_NAME="AppOps"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/teams/?name=${TEAM_NAME}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    team = data['results'][0]
    print(f'Team ID: {team[\"id\"]}')
    print(f'Team: {team[\"name\"]}')
" | while read line; do
    TEAM_ID=$(echo "$line" | grep "Team ID:" | awk '{print $3}')
    if [ -n "$TEAM_ID" ]; then
        curl -s -u "${AWX_AUTH}" \
            "${AWX_URL}/api/v2/teams/${TEAM_ID}/users/" \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
usernames = [u['username'] for u in data['results']]
print(f'Miembros del team: {usernames}')
if '${USERNAME}' in usernames:
    print('✅ ${USERNAME} está en el team')
else:
    print('❌ ${USERNAME} NO está en el team')
"
    fi
done

# Verificar que el team AppOps tiene rol en el template
JT_ID=1
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/job_templates/${JT_ID}/access_list/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Acceso al template:')
for entry in data['results']:
    direct = entry.get('summary_fields', {}).get('direct_access', [])
    indirect = entry.get('summary_fields', {}).get('indirect_access', [])
    all_roles = [(r['role']['name'], 'direct') for r in direct] + \
                [(r['role']['name'], 'indirect') for r in indirect]
    if all_roles:
        print(f'  {entry[\"username\"]:25}: {all_roles}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El team AppOps no tiene rol en el template
  
  Diagnóstico: el access_list del template no muestra AppOps
  
  Solución:
    Templates → Web App Deploy → Access → Add
    Team: AppOps → Role: Execute
    Team: AppOps → Role: Read

CAUSA 2: El usuario no está en el team AppOps
  
  Diagnóstico: el usuario no aparece en la lista de miembros del team
  
  Solución:
    Teams → AppOps → Users → Add
    Buscar: operador1 → Add

CAUSA 3: El team AppOps no es miembro de la organización
  
  Diagnóstico: el team existe pero no tiene rol en la organización
  
  Solución:
    Organizations → MiEmpresa → Access → Add
    Team: AppOps → Role: Member

CAUSA 4: El template pertenece a una organización diferente
  
  Diagnóstico: el template está en BU-Finance pero el usuario
  solo pertenece a MiEmpresa
  
  Solución:
    Verificar la organización del template
    Mover el template a la organización correcta
    O añadir el usuario a la organización del template
```

---

## Problema 2: Operador puede ver las credenciales (no debería)

**Síntoma:**
```
El usuario operador1 puede ver el contenido de las credenciales
en la UI de AWX, incluyendo campos que deberían estar ocultos.
```

**Diagnóstico:**
```bash
# Verificar los roles del usuario en las credenciales
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/credentials/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cred in data['results']:
    print(f'Credencial: {cred[\"name\"]} (ID: {cred[\"id\"]})')
" | while IFS= read -r line; do
    CRED_ID=$(echo "$line" | grep -oP 'ID: \K[0-9]+')
    if [ -n "$CRED_ID" ]; then
        curl -s -u "${AWX_AUTH}" \
            "${AWX_URL}/api/v2/credentials/${CRED_ID}/access_list/" \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
for entry in data['results']:
    if entry['username'] == 'operador1':
        direct = entry.get('summary_fields', {}).get('direct_access', [])
        for role in direct:
            print(f'  ⚠️  operador1 tiene rol \"{role[\"role\"][\"name\"]}\" en credencial ID ${CRED_ID}')
"
    fi
done
```

**Causas y soluciones:**

```
CAUSA 1: Se asignó rol "Use" o "Admin" directamente al usuario/team
  
  Alguien asignó permisos en la credencial pensando que era necesario.
  
  Solución:
    Credentials → Platform SSH → Access
    Eliminar cualquier rol de AppOps, SecOps u operadores individuales
    Solo Platform debe tener acceso a las credenciales

CAUSA 2: El usuario es System Auditor
  
  Los System Auditors pueden ver todos los objetos de todas las orgs.
  Aunque los campos de secretos están enmascarados, pueden ver
  que la credencial existe y sus metadatos.
  
  Solución:
    Verificar que el usuario no tiene is_system_auditor=true
    Users → operador1 → Edit
    System Auditor: ☐ (desmarcar si está marcado)

CAUSA 3: El usuario es Organization Auditor
  
  El rol Auditor de la organización da lectura a todos los objetos,
  incluyendo credenciales (campos enmascarados).
  
  Solución:
    Organizations → MiEmpresa → Access
    Cambiar el rol de operador1 de "Auditor" a "Member"
    Luego asignar roles específicos en los templates que necesita

CAUSA 4: El usuario tiene Admin en la organización
  
  Organization Admin tiene acceso a todos los objetos de la org.
  
  Solución:
    Verificar que AppOps no tiene rol Admin en la organización
    Organizations → MiEmpresa → Access
    AppOps debe tener "Member", no "Admin"
```

---

## Problema 3: La integración LDAP no funciona

**Síntoma:**
```
Los usuarios intentan hacer login con sus credenciales de AD
pero reciben "Invalid username or password".
```

**Diagnóstico:**
```bash
# Verificar la configuración LDAP desde los logs de AWX
kubectl logs -n awx deployment/awx-task -c awx-task \
    | grep -i "ldap\|auth\|login" | tail -30

# Probar la conexión LDAP directamente desde el pod
kubectl exec -n awx deployment/awx-task -c awx-task -- \
    python3 -c "
import ldap
try:
    conn = ldap.initialize('ldap://ldap.empresa.com:389')
    conn.set_option(ldap.OPT_TIMEOUT, 10)
    conn.set_option(ldap.OPT_NETWORK_TIMEOUT, 10)
    conn.simple_bind_s(
        'CN=awx-service,OU=ServiceAccounts,DC=empresa,DC=com',
        'ServicePassword123!'
    )
    print('✅ Conexión LDAP exitosa')

    # Buscar un usuario de prueba
    result = conn.search_s(
        'OU=Users,DC=empresa,DC=com',
        ldap.SCOPE_SUBTREE,
        '(sAMAccountName=operador1)',
        ['cn', 'mail', 'memberOf']
    )
    if result:
        dn, attrs = result[0]
        print(f'✅ Usuario encontrado: {dn}')
        print(f'   Email: {attrs.get(\"mail\", [b\"N/A\"])[0].decode()}')
        groups = [g.decode() for g in attrs.get('memberOf', [])]
        print(f'   Grupos: {groups[:3]}')
    else:
        print('❌ Usuario no encontrado en LDAP')
except ldap.SERVER_DOWN:
    print('❌ No se puede conectar al servidor LDAP')
except ldap.INVALID_CREDENTIALS:
    print('❌ Credenciales de la cuenta de servicio incorrectas')
except Exception as e:
    print(f'❌ Error: {e}')
"
```

**Causas y soluciones:**

```
CAUSA 1: LDAP Server URI incorrecto o inaccesible
  
  Diagnóstico:
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
      nc -zv ldap.empresa.com 389
  
  Solución:
    Verificar que el pod de AWX puede llegar al servidor LDAP
    Revisar NetworkPolicies de Kubernetes
    Verificar el DNS: nslookup ldap.empresa.com

CAUSA 2: Bind DN o contraseña incorrectos
  
  Diagnóstico: el script de prueba falla con INVALID_CREDENTIALS
  
  Solución:
    Verificar el Bind DN exacto en Active Directory
    Administration → Authentication → LDAP
    LDAP Bind DN: CN=awx-service,OU=ServiceAccounts,DC=empresa,DC=com
    (verificar cada componente del DN)

CAUSA 3: User Search filter incorrecto
  
  El filtro no encuentra al usuario porque el atributo es diferente.
  En AD: sAMAccountName
  En OpenLDAP: uid
  
  Solución:
    LDAP User Search:
    ["OU=Users,DC=empresa,DC=com", "SCOPE_SUBTREE", "(sAMAccountName=%(user)s)"]
    
    Para OpenLDAP:
    ["ou=users,dc=empresa,dc=com", "SCOPE_SUBTREE", "(uid=%(user)s)"]

CAUSA 4: El usuario no está en el OU correcto
  
  El User Search busca en OU=Users pero el usuario está en OU=Staff
  
  Solución:
    Cambiar el User Search a la raíz del dominio:
    ["DC=empresa,DC=com", "SCOPE_SUBTREE", "(sAMAccountName=%(user)s)"]
    (más lento pero encuentra usuarios en cualquier OU)

CAUSA 5: LDAPS con certificado autofirmado
  
  Si usas ldaps:// con certificado autofirmado, la conexión falla
  por verificación de certificado.
  
  Solución:
    Administration → Authentication → LDAP
    LDAP Connection Options:
    {"OPT_X_TLS_REQUIRE_CERT": "OPT_X_TLS_NEVER"}
    (solo en entornos de lab; en producción usar certificado válido)
```

---

## Problema 4: Aprobación de Workflow no aparece para el aprobador

**Síntoma:**
```
El workflow está pausado en el nodo de aprobación pero
el usuario del CAB no ve ninguna aprobación pendiente.
```

**Diagnóstico:**
```bash
# Ver aprobaciones pendientes
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/workflow_approvals/?status=pending" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Aprobaciones pendientes: {data[\"count\"]}')
for approval in data['results']:
    wf = approval.get('summary_fields', {}).get('workflow_job', {})
    print(f'  ID: {approval[\"id\"]}')
    print(f'  Nombre: {approval[\"name\"]}')
    print(f'  Workflow: {wf.get(\"name\", \"N/A\")}')
    print(f'  Creado: {approval[\"created\"][:19]}')
"

# Verificar los permisos del aprobador en el Workflow Template
WFT_ID=3
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/workflow_job_templates/${WFT_ID}/access_list/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Acceso al Workflow Template:')
for entry in data['results']:
    direct = entry.get('summary_fields', {}).get('direct_access', [])
    for role in direct:
        print(f'  {entry[\"username\"]:25} | {role[\"role\"][\"name\"]}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El usuario no tiene rol "Approve" en el Workflow Template
  
  Solución:
    Templates → App Delivery Pipeline → Access → Add
    Team: Change Advisory Board → Role: Approve
    Team: Change Advisory Board → Role: Read  (para ver el contexto)

CAUSA 2: El usuario tiene "Approve" pero no "Read"
  
  Sin "Read" no puede ver el workflow ni navegar al nodo de aprobación.
  
  Solución:
    Añadir también rol Read al team CAB en el Workflow Template

CAUSA 3: El aprobador busca en el lugar incorrecto
  
  Las aprobaciones pendientes están en:
    Menú lateral → Jobs → Workflow Approvals
    O: Jobs → Workflow Jobs → (job específico) → nodo amarillo
  
  Solución:
    Guiar al aprobador a la sección correcta
    Configurar notificación con link directo a la aprobación

CAUSA 4: La notificación de aprobación no llegó
  
  El aprobador no sabe que hay algo pendiente.
  
  Solución:
    Verificar que la notificación "On Approval Pending" está configurada
    Revisar el historial de notificaciones:
    Notifications → (ver si hay errores)
    Reenviar manualmente si es urgente
```

---

## Problema 5: Activity Stream no muestra eventos esperados

**Síntoma:**
```
Se ejecutaron varios jobs y se modificaron templates pero
el Activity Stream parece incompleto o vacío.
```

**Diagnóstico:**
```bash
# Verificar que el Activity Stream está activo
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/activity_stream/?page_size=1" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total eventos en Activity Stream: {data[\"count\"]}')
if data['results']:
    latest = data['results'][0]
    print(f'Evento más reciente: {latest[\"timestamp\"][:19]}')
    print(f'Operación: {latest[\"operation\"]}')
"

# Verificar la configuración de retención
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/settings/jobs/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Activity Stream retention: {data.get(\"ACTIVITY_STREAM_ENABLED\", \"N/A\")}')
print(f'Job retention (días): {data.get(\"CLEANUP_JOB_SCHEDULE\", \"N/A\")}')
"
```

**Causas y soluciones:**

```
CAUSA 1: Activity Stream deshabilitado
  
  Diagnóstico:
    Administration → Settings → System
    Activity Stream: debe estar ON
  
  Solución:
    Administration → Settings → System
    Enable Activity Stream: ✅ ON
    → Save

CAUSA 2: Eventos purgados por la tarea de limpieza
  
  AWX tiene una tarea periódica que limpia eventos antiguos.
  Si la retención es muy corta (ej: 30 días), los eventos
  más antiguos se eliminan.
  
  Solución:
    Administration → Settings → Jobs
    Days of Activity Stream data to keep: 365  (o más)
    → Save

CAUSA 3: El usuario auditor no tiene permisos para ver todos los eventos
  
  Un Organization Auditor solo ve eventos de su organización.
  Un System Auditor ve todos los eventos.
  
  Solución:
    Si el auditor necesita ver eventos de múltiples organizaciones,
    asignarle System Auditor en lugar de Organization Auditor.
    (con las implicaciones de seguridad que conlleva)

CAUSA 4: Filtros activos en la UI
  
  La UI de AWX puede tener filtros activos que ocultan eventos.
  
  Solución:
    Activity Stream → limpiar todos los filtros
    O consultar directamente via API sin filtros
```

---

## Referencia rápida: comandos de diagnóstico RBAC

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver todos los usuarios y sus tipos
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/users/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in data['results']:
    t = 'ADMIN' if u['is_superuser'] else 'AUDITOR' if u['is_system_auditor'] else 'normal'
    print(f'{u[\"username\"]:25} | {t:8} | {u[\"email\"]}')
"

# Ver todos los teams y sus organizaciones
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/teams/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['results']:
    org = t['summary_fields']['organization']['name']
    print(f'{t[\"name\"]:30} | Org: {org}')
"

# Ver qué roles tiene un usuario específico en todos los objetos
USERNAME="operador1"
curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/users/?username=${USERNAME}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['id'])" \
    | xargs -I{} curl -s -u "${AWX_AUTH}" \
    "${AWX_URL}/api/v2/users/{}/roles/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Roles de ${USERNAME}:')
for role in data['results']:
    obj = role.get('summary_fields', {})
    resource = obj.get('resource_name', 'N/A')
    resource_type = obj.get('resource_type', 'N/A')
    print(f'  {role[\"name\"]:15} en {resource_type:20}: {resource}')
"

# Ver los tokens activos y sus expiraciones
curl -s -u "${AWX_AUTH}" "${AWX_URL}/api/v2/tokens/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Tokens activos: {data[\"count\"]}')
for token in data['results']:
    user = token.get('summary_fields', {}).get('user', {})
    expires = token.get('expires', 'never')
    expires_str = expires[:10] if expires and expires != 'never' else '⚠️ sin expiración'
    print(f'  {user.get(\"username\", \"N/A\"):25} | Scope: {token[\"scope\"]:8} | Expira: {expires_str}')
"
```

---

# 5.17 Resumen y Checklist del Módulo 5

## Lo que has aprendido

```
✅ Seguridad como diseño previo, no como añadido posterior
   → Diseñar la matriz de acceso antes de crear objetos
   → Principio de mínimo privilegio en cada asignación

✅ Organizaciones como límite de aislamiento
   → Una org para equipos de la misma empresa
   → Múltiples orgs para tenants completamente independientes
   → Roles de org: Admin, Auditor, Member

✅ Teams como unidad de gestión de permisos
   → Roles siempre a teams, nunca a usuarios individuales
   → Platform, AppOps, SecOps, CAB, Auditores, CI-CD
   → Revisión periódica de membresía

✅ Modelo de roles por objeto
   → Admin: control total
   → Execute: lanzar jobs/workflows
   → Use: seleccionar en templates
   → Read: solo ver
   → Approve: aprobar nodos de workflow
   → Cada objeto tiene sus propios roles

✅ Credenciales: el objeto más sensible
   → Operadores nunca ven credenciales directamente
   → Los templates las usan en nombre del operador
   → Separación por entorno (dev ≠ prod) y función (SSH ≠ Vault ≠ Cloud)
   → Rotación sin downtime con doble clave

✅ Activity Stream como fuente de auditoría
   → Todos los eventos registrados automáticamente
   → Filtrar por usuario, tipo de objeto, operación
   → Exportar para SIEM
   → Alertas automáticas para eventos sospechosos

✅ Multi-tenancy con organizaciones separadas
   → Aislamiento total entre tenants
   → Instance Groups por entorno y tenant
   → Capacidad dedicada para producción

✅ Integración LDAP/SSO
   → Autenticación centralizada con AD/LDAP
   → Mapeo automático de grupos LDAP a Teams AWX
   → SAML para Okta, Azure AD, etc.

✅ Patrones avanzados
   → Revisión periódica de permisos con script
   → Cuentas de servicio con mínimo privilegio
   → Separación de duties en el pipeline
   → Rotación de credenciales sin downtime
   → Vault dinámico con HashiCorp Vault
   → Alertas de seguridad en el Activity Stream
   → Hardening de la configuración de AWX
```
