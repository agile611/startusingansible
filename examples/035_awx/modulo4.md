[# 🔗 MÓDULO 4 — Workflows, Aprobaciones y Notificaciones
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 4.1 | Modelo mental: de jobs individuales a pipelines gobernados |
| 4.2 | Anatomía de un Workflow Template |
| 4.3 | Tipos de nodos en un Workflow |
| 4.4 | Edges condicionales: success, failure, always |
| 4.5 | Fan-out y Fan-in: paralelismo y convergencia |
| 4.6 | Nodos de Aprobación: human-in-the-loop |
| 4.7 | Variables en Workflows: surveys y propagación |
| 4.8 | Notificaciones: Slack, Teams, email y webhooks |
| 4.9 | Callback tokens y patrones de relaunch |
| 4.10 | LAB — Workflow completo: provision → configure → test → deploy → rollback |
| 4.11 | LAB — Nodo de aprobación con permisos y timeout |
| 4.12 | LAB — Notificaciones Slack con mensajes personalizados |
| 4.13 | LAB — Notificaciones por email y webhook genérico |
| 4.14 | LAB — Trigger desde GitHub Actions via API |
| 4.15 | LAB — Trigger desde GitLab CI via webhook de proyecto |
| 4.16 | Patrones avanzados y buenas prácticas |
| 4.17 | Troubleshooting del módulo |
| 4.18 | Resumen y checklist |

**Duración estimada:** 75-90 minutos
**Tipo:** Lab + diseño de pipelines
**Prerrequisitos:** Módulos 1, 2 y 3 completados. Job Templates funcionando.

---

# 4.1 Modelo mental: de jobs individuales a pipelines gobernados

Un Job Template resuelve el problema de ejecutar una tarea de forma repetible y segura. Pero en la realidad, un cambio en producción nunca es una sola tarea: es una secuencia de pasos con dependencias, validaciones, aprobaciones y posibles rollbacks.

```
SIN WORKFLOW: ejecución manual y frágil
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Operador:
    1. Lanza "Provision Infra"          → espera → verifica
    2. Lanza "Configure App"            → espera → verifica
    3. Lanza "Run Tests"                → espera → verifica resultado
    4. Envía email al CAB pidiendo OK   → espera respuesta
    5. Lanza "Deploy to Prod"           → espera → verifica
    6. Si falla: lanza "Rollback"       → espera
    7. Envía notificación a Slack       → manual
  
  Problemas:
  ❌ El operador puede saltarse pasos
  ❌ Si se va a comer y falla algo, nadie se entera
  ❌ Sin registro de quién aprobó qué y cuándo
  ❌ El rollback depende de que alguien recuerde hacerlo
  ❌ Sin paralelismo: configure y security_scan podrían ir en paralelo

CON WORKFLOW: pipeline automático y gobernado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Operador lanza el Workflow y rellena el Survey.
  AWX se encarga de:
    → Ejecutar pasos en el orden correcto
    → Paralelizar donde es posible
    → Parar y esperar aprobación humana
    → Ejecutar rollback automáticamente si algo falla
    → Notificar en Slack en cada evento relevante
    → Registrar quién aprobó, cuándo y con qué comentario
  
  Beneficios:
  ✅ El proceso siempre se sigue completo
  ✅ Auditoría completa del pipeline
  ✅ Rollback automático sin intervención humana
  ✅ Aprobaciones con SLA y timeout
  ✅ Notificaciones automáticas en cada evento
  ✅ Paralelismo donde tiene sentido
```

---

# 4.2 Anatomía de un Workflow Template

Un Workflow Template es un grafo dirigido donde cada nodo es una unidad de trabajo y cada arista (edge) define la condición de transición.

```
COMPONENTES DE UN WORKFLOW TEMPLATE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NODOS (vértices del grafo):
  • Job Template Node      → ejecuta un Job Template
  • Workflow Template Node → ejecuta otro Workflow (anidado)
  • Approval Node          → pausa y espera aprobación humana
  • Project Sync Node      → sincroniza un proyecto SCM
  • Inventory Sync Node    → sincroniza un inventario dinámico

EDGES (aristas del grafo):
  • success  → ejecutar el siguiente nodo si este tuvo éxito
  • failure  → ejecutar el siguiente nodo si este falló
  • always   → ejecutar el siguiente nodo siempre (éxito o fallo)

PROPIEDADES DEL WORKFLOW:
  • Survey propio (independiente de los surveys de los JTs)
  • Inventory por defecto (puede ser sobreescrito por nodo)
  • Credentials por defecto
  • Notificaciones (start, success, failure, approval)
  • Límite de concurrencia
  • Timeout global
```

## El Visualizer: la herramienta de diseño

```
AWX → Templates → Tu Workflow → Visualizer

El Visualizer muestra el grafo del workflow:
  • Nodos como cajas con el nombre del Job Template
  • Edges como flechas de colores:
      Verde  → success path
      Rojo   → failure path
      Azul   → always path
  
  Para añadir un nodo:
    Click en el "+" de un nodo existente
    Seleccionar: tipo, template, edge de conexión
  
  Para conectar nodos existentes:
    Arrastrar desde el punto de conexión de un nodo al otro
  
  Para eliminar un nodo:
    Click en el nodo → Delete
```

---

# 4.3 Tipos de nodos en un Workflow

## Job Template Node

El más común. Ejecuta un Job Template con opciones adicionales.

```
Opciones al añadir un Job Template Node:

  Convergence:
    Any  → el nodo se ejecuta si CUALQUIERA de sus predecesores completa
    All  → el nodo se ejecuta solo si TODOS sus predecesores completan
    
    (relevante cuando hay fan-in: múltiples nodos apuntan al mismo siguiente)

  Identifier:
    Nombre único del nodo dentro del workflow
    Útil para referenciar en la API y en logs

  Override variables:
    Puedes sobreescribir variables específicas para este nodo
    sin afectar a otros nodos del workflow
```

## Workflow Template Node (anidado)

Permite componer workflows dentro de workflows.

```
CASO DE USO: Workflow de alto nivel que reutiliza sub-workflows

Workflow: "Release Completa"
  Node 1: Workflow "Deploy Backend"    ← sub-workflow completo
  Node 2: Workflow "Deploy Frontend"   ← sub-workflow completo
  Node 3: Workflow "Run E2E Tests"     ← sub-workflow completo
  Node 4: Approval "Go/No-Go"
  Node 5: Workflow "Promote to Prod"   ← sub-workflow completo
```

## Approval Node

Pausa el workflow y espera que un usuario autorizado apruebe o rechace.

```
Campos del Approval Node:
  Name:        nombre visible para el aprobador
  Description: instrucciones detalladas para el aprobador
  Timeout:     segundos antes de auto-expirar (0 = sin límite)
  
Permisos:
  Solo usuarios/equipos con rol "Approve" en el Workflow Template
  pueden aprobar o rechazar.
  
Estados posibles:
  pending   → esperando aprobación
  approved  → aprobado → continúa por el edge "success"
  denied    → rechazado → continúa por el edge "failure"
  timed_out → expiró el timeout → continúa por el edge "failure"
```

## Project Sync Node

Sincroniza un proyecto SCM antes de ejecutar jobs que dependen de él.

```
CASO DE USO:
  Node 1: Project Sync "Platform Playbooks"
  Node 2 (success): Job Template "Deploy App"
  
  Garantiza que el código está actualizado antes del deploy.
  Útil cuando no usas "Update on Launch" en el proyecto.
```

---

# 4.4 Edges condicionales: success, failure, always

Los edges son la lógica del workflow. Entenderlos bien es fundamental para diseñar pipelines robustos.

```
SUCCESS EDGE (verde):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  El nodo destino se ejecuta SOLO SI el nodo origen completó
  con éxito (status: successful).
  
  Uso: el camino feliz del pipeline
  Ejemplo: Configure App → (success) → Run Tests

FAILURE EDGE (rojo):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  El nodo destino se ejecuta SOLO SI el nodo origen falló
  (status: failed o error).
  
  Uso: manejo de errores, rollback, notificaciones de fallo
  Ejemplo: Deploy App → (failure) → Rollback App

ALWAYS EDGE (azul):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  El nodo destino se ejecuta SIEMPRE, independientemente
  del resultado del nodo origen.
  
  Uso: limpieza, notificaciones finales, métricas
  Ejemplo: Deploy App → (always) → Send Notification
```

## Combinaciones de edges desde un mismo nodo

Un nodo puede tener múltiples edges salientes de diferentes tipos:

```
Deploy App
  ├── (success) → Run Smoke Tests
  ├── (failure) → Rollback App
  └── (always)  → Update CMDB

Esto significa:
  Si Deploy App tiene éxito:
    → Ejecuta Run Smoke Tests
    → Ejecuta Update CMDB (siempre)
    
  Si Deploy App falla:
    → Ejecuta Rollback App
    → Ejecuta Update CMDB (siempre)
    → NO ejecuta Run Smoke Tests
```

## Estado final del Workflow

```
El Workflow completa como "successful" si:
  → Todos los nodos del camino ejecutado terminaron con éxito
  → O si el único fallo fue en un nodo con edge "failure" que
    llevó a un nodo de recuperación exitoso

El Workflow completa como "failed" si:
  → Algún nodo del camino principal falló y no hay recuperación
  → Un Approval Node fue rechazado o expiró
  → Un nodo crítico falló sin edge de failure configurado
```

---

# 4.5 Fan-out y Fan-in: paralelismo y convergencia

## Fan-out: ejecutar nodos en paralelo

```
EJEMPLO: Configurar múltiples componentes en paralelo

                    ┌─────────────────┐
                    │  Provision Infra │
                    └────────┬────────┘
                             │ success
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ Configure DB │ │Configure App │ │Config Monitor│
    └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
           │                │                │
           └────────────────┼────────────────┘
                            │ (fan-in)
                            ▼
                    ┌──────────────┐
                    │  Run Tests   │
                    └──────────────┘

Los tres nodos "Configure" se ejecutan en PARALELO.
"Run Tests" espera a que los TRES terminen (Convergence: All).

Beneficio: reduce el tiempo total del pipeline.
Configure DB + Configure App + Config Monitor = max(T1, T2, T3)
En lugar de T1 + T2 + T3
```

## Fan-in: convergencia con Convergence

```
CONFIGURACIÓN EN AWX:

Al añadir el nodo "Run Tests" que recibe de los tres Configure:

  Node: Run Tests
  Convergence: All   ← espera a que TODOS los predecesores completen
  
  vs.
  
  Convergence: Any   ← se ejecuta cuando CUALQUIERA completa
                        (útil para redundancia, no para dependencias)
```

## Ejemplo práctico de fan-out con tiempos

```
SIN PARALELISMO (secuencial):
  Configure DB       → 5 min
  Configure App      → 3 min
  Configure Monitor  → 2 min
  Total:             → 10 min

CON FAN-OUT (paralelo):
  Configure DB   ─┐
  Configure App  ─┼─ en paralelo → max(5, 3, 2) = 5 min
  Config Monitor ─┘
  Total:         → 5 min  (50% más rápido)
```

---

# 4.6 Nodos de Aprobación: human-in-the-loop

Los nodos de aprobación son el mecanismo de gobernanza más importante de AWX. Permiten insertar una decisión humana en cualquier punto del pipeline.

## Cuándo usar aprobaciones

```
✅ USAR APROBACIÓN:
  • Antes de cualquier cambio en producción
  • Antes de operaciones destructivas (borrar datos, terminar instancias)
  • Cuando el cambio requiere validación de un experto (DBA, SecOps)
  • Cuando hay un proceso de Change Advisory Board (CAB)
  • Cuando el coste de un error es muy alto

❌ NO USAR APROBACIÓN:
  • En pipelines de dev/stage (ralentiza el feedback loop)
  • Para tareas rutinarias de bajo riesgo
  • Cuando el timeout puede bloquear el pipeline indefinidamente
    sin que nadie esté disponible para aprobar
```

## Diseño de un nodo de aprobación efectivo

```
Un buen nodo de aprobación tiene:

1. NOMBRE CLARO que indique la decisión:
   ✅ "Autorizar deploy en PROD - {{ change_ticket }}"
   ❌ "Aprobación"

2. DESCRIPCIÓN con contexto suficiente para decidir:
   ✅ "Antes de aprobar, verifica:
       ✅ Tests de integración pasaron en stage
       ✅ Ticket {{ change_ticket }} tiene aprobación del CAB
       ✅ Ventana de cambio activa ({{ maintenance_window }})
       ✅ Equipo de guardia notificado: {{ oncall_team }}
       ✅ Plan de rollback documentado en el ticket"
   ❌ "¿Aprobar?"

3. TIMEOUT razonable:
   ✅ 7200 (2 horas) para cambios planificados
   ✅ 3600 (1 hora) para cambios urgentes
   ❌ 0 (sin timeout) → puede bloquear el pipeline indefinidamente

4. PERMISOS correctos:
   Solo el equipo que debe aprobar tiene el rol "Approve"
   No dar "Approve" a quien también ejecuta el pipeline
```

## Flujo de aprobación desde la perspectiva del aprobador

```
1. AWX envía notificación (Slack/email) al canal del CAB:
   "⏳ Aprobación pendiente: Deploy WebApp v2.0.0 en PROD
    Ticket: CHANGE-4521
    Solicitado por: operador1
    Expira en: 2 horas
    🔗 http://awx:30080/#/jobs/workflow/42"

2. El aprobador accede a AWX:
   Jobs → Workflow Jobs → Job #42 → (nodo de aprobación)
   
   O directamente desde el link de la notificación.

3. El aprobador ve:
   - El nombre y descripción del nodo
   - El contexto del workflow (qué se va a desplegar)
   - Los valores del Survey (versión, entorno, ticket)
   - Botones: Approve / Deny

4. El aprobador puede añadir un comentario antes de decidir.

5. AWX registra:
   - Quién aprobó/rechazó
   - Cuándo (timestamp)
   - El comentario (si lo hay)
   - El estado resultante del workflow
```

---

# 4.7 Variables en Workflows: surveys y propagación

## Survey del Workflow vs Survey del Job Template

```
WORKFLOW SURVEY:
  Definido en el Workflow Template.
  Las variables están disponibles para TODOS los nodos del workflow.
  Se rellena UNA VEZ al lanzar el workflow.
  
  Ejemplo:
    release_tag:    v2.0.0
    environment:    prod
    change_ticket:  CHANGE-4521

JOB TEMPLATE SURVEY:
  Definido en el Job Template individual.
  Solo aplica cuando ese JT se lanza directamente.
  Cuando se lanza desde un Workflow, el Workflow Survey tiene precedencia.
  
  Recomendación:
    Definir el Survey en el Workflow, no en los JTs individuales.
    Los JTs deben funcionar con variables pasadas desde el Workflow.
```

## Propagación de variables entre nodos

```
Las variables del Workflow Survey se propagan automáticamente
a todos los nodos (Job Templates) del workflow.

WORKFLOW SURVEY define:
  release_tag: v2.0.0
  environment: prod
  change_ticket: CHANGE-4521

NODO 1: "Provision Infra"
  Recibe automáticamente:
    release_tag, environment, change_ticket
  Puede usar: {{ release_tag }}, {{ environment }}, etc.

NODO 2: "Configure App"
  También recibe:
    release_tag, environment, change_ticket
  
NODO 3: "Deploy to Prod"
  También recibe las mismas variables.
```

## Pasar variables entre nodos (set_stats)

Ansible tiene un módulo especial `set_stats` que permite que un Job Template pase variables al siguiente nodo del Workflow.

```yaml
# En el playbook del nodo "Run Tests":
- name: Pasar resultado de tests al siguiente nodo
  ansible.builtin.set_stats:
    data:
      test_results:
        passed: "{{ tests_passed }}"
        failed: "{{ tests_failed }}"
        coverage: "{{ code_coverage }}"
      deploy_approved: "{{ tests_failed == 0 }}"
      artifact_url: "https://registry.ejemplo.com/webapp:{{ release_tag }}"
    # per_host: false → las stats son globales, no por host
    per_host: false
```

```yaml
# En el playbook del nodo siguiente "Deploy App":
- name: Verificar que los tests pasaron
  ansible.builtin.assert:
    that:
      - deploy_approved | bool
    fail_msg: "Deploy bloqueado: tests fallaron ({{ test_results.failed }} fallos)"
    success_msg: "Tests OK: {{ test_results.passed }} pasados, cobertura {{ test_results.coverage }}%"
```

---

# 4.8 Notificaciones: Slack, Teams, email y webhooks

Las notificaciones convierten AWX en un sistema observable. El equipo sabe qué está pasando sin tener que mirar la UI constantemente.

## Tipos de eventos para notificaciones

```
Por Workflow Template:
  Started          → el workflow comenzó
  Success          → el workflow completó con éxito
  Failure          → el workflow falló
  Approval Pending → hay una aprobación esperando
  Approval Granted → alguien aprobó
  Approval Denied  → alguien rechazó

Por Job Template:
  Started          → el job comenzó
  Success          → el job completó con éxito
  Failure          → el job falló

Recomendación de configuración:
  Workflow: Success + Failure + Approval Pending
  Job Templates críticos: solo Failure (evitar ruido)
  Canal de auditoría: todos los eventos
```

## Variables disponibles en mensajes de notificación

```
AWX expone estas variables en los templates de mensajes:

{{ job_friendly_name }}      → "Workflow Job" o "Job"
{{ url }}                    → URL directa al job en AWX
{{ workflow_url }}           → URL al workflow padre (si aplica)
{{ job_id }}                 → ID numérico del job
{{ name }}                   → nombre del template
{{ status }}                 → successful / failed / pending
{{ started }}                → timestamp de inicio
{{ finished }}               → timestamp de fin
{{ elapsed }}                → duración en segundos
{{ traceback }}              → traceback si hubo error interno
{{ extra_vars }}             → variables del job (dict)
{{ hosts_with_failures }}    → lista de hosts que fallaron
{{ job_template_name }}      → nombre del Job Template (en workflows)
{{ workflow_job_template_name }} → nombre del Workflow Template
```

---

# 4.9 Callback tokens y patrones de relaunch

## Callback tokens

Un callback token permite que un sistema externo (CI, script, host) lance un Job Template sin tener credenciales completas de AWX.

```
CONFIGURACIÓN:
  Templates → Tu JT → Edit
  Options: ✅ Enable Provisioning Callbacks
  
  AWX genera:
    Callback URL:     http://awx:30080/api/v2/job_templates/5/callback/
    Host Config Key:  abc123def456xyz789

USO DESDE UN HOST (user-data, cloud-init):
  curl -X POST \
    http://awx:30080/api/v2/job_templates/5/callback/ \
    -d "host_config_key=abc123def456xyz789"
  
  AWX lanza el job limitado al host que hizo la llamada.
  El host debe existir en el inventario del template.
```

## Patrones de relaunch

```
RELAUNCH COMPLETO:
  Jobs → Tu Job → Relaunch
  Usa exactamente los mismos parámetros del job original.
  Útil para: reintentar un job que falló por problema transitorio.

RELAUNCH EN HOSTS FALLIDOS:
  Jobs → Tu Job → Relaunch → "Relaunch on Failed Hosts"
  Solo ejecuta en los hosts que fallaron en el job anterior.
  Útil para: corregir el problema en los hosts afectados sin
  volver a ejecutar en los que ya están bien.

RELAUNCH DESDE NODO FALLIDO (Workflow):
  Jobs → Workflow Job → Relaunch
  Opciones:
    From the beginning    → reinicia todo el workflow
    From failed node      → continúa desde el nodo que falló
  
  Útil para: corregir el problema y continuar sin repetir
  los pasos que ya completaron correctamente.
```

---

# 4.10 LAB — Workflow completo: provision → configure → test → deploy → rollback

*Construimos el pipeline de entrega completo con todas las rutas de éxito, fallo y recuperación.*

## Paso 1 — Preparar los Job Templates necesarios

Necesitamos estos Job Templates antes de crear el Workflow. Crea cada uno con su playbook correspondiente.

### Playbooks para el lab

```yaml
# playbooks/provision_infra.yml
---
- name: Provision Infrastructure
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    release_tag:    "{{ release_tag    | default('v1.0.0') }}"
    environment:    "{{ environment    | default('dev') }}"
    change_ticket:  "{{ change_ticket  | default('N/A') }}"

  tasks:
    - name: Simular provisión de infraestructura
      ansible.builtin.debug:
        msg:
          - "=== PROVISION INFRA ==="
          - "Release:  {{ release_tag }}"
          - "Entorno:  {{ environment }}"
          - "Ticket:   {{ change_ticket }}"

    - name: Registrar resultado de provisión
      ansible.builtin.set_stats:
        data:
          infra_provisioned: true
          provision_timestamp: "{{ lookup('pipe', 'date +%s') }}"
        per_host: false
```

```yaml
# playbooks/configure_app.yml
---
- name: Configure Application
  hosts: "{{ target_group | default('dev') }}"
  become: true
  gather_facts: false

  vars:
    release_tag: "{{ release_tag | default('v1.0.0') }}"
    environment: "{{ environment | default('dev') }}"

  tasks:
    - name: Simular configuración de la aplicación
      ansible.builtin.debug:
        msg:
          - "=== CONFIGURE APP ==="
          - "Host:    {{ inventory_hostname }}"
          - "Release: {{ release_tag }}"
          - "Entorno: {{ environment }}"

    - name: Crear fichero de configuración
      ansible.builtin.copy:
        content: |
          # Configuración generada por AWX
          app_version={{ release_tag }}
          environment={{ environment }}
          configured_at={{ ansible_date_time.iso8601 | default('unknown') }}
        dest: /tmp/app_config_{{ environment }}.conf
        mode: '0644'

    - name: Registrar resultado de configuración
      ansible.builtin.set_stats:
        data:
          app_configured: true
          config_version: "{{ release_tag }}"
        per_host: false
```

```yaml
# playbooks/run_tests.yml
---
- name: Run Integration Tests
  hosts: "{{ target_group | default('dev') }}"
  gather_facts: false

  vars:
    release_tag: "{{ release_tag | default('v1.0.0') }}"
    environment: "{{ environment | default('dev') }}"

  tasks:
    - name: Ejecutar tests de integración (simulado)
      ansible.builtin.debug:
        msg:
          - "=== RUN TESTS ==="
          - "Versión bajo test: {{ release_tag }}"
          - "Entorno: {{ environment }}"

    - name: Verificar que el servicio responde
      ansible.builtin.uri:
        url: "http://localhost:8080/health"
        status_code: [200, 404]
        timeout: 5
      register: health_check
      ignore_errors: true

    - name: Simular resultado de tests
      ansible.builtin.set_fact:
        tests_passed: 42
        tests_failed: 0
        test_coverage: 87.5

    - name: Registrar resultados para el siguiente nodo
      ansible.builtin.set_stats:
        data:
          tests_passed: "{{ tests_passed }}"
          tests_failed: "{{ tests_failed }}"
          test_coverage: "{{ test_coverage }}"
          tests_ok: "{{ tests_failed == 0 }}"
        per_host: false

    - name: Fallar si hay tests fallidos
      ansible.builtin.fail:
        msg: "Tests fallaron: {{ tests_failed }} fallos de {{ tests_passed + tests_failed }} tests"
      when: tests_failed | int > 0
```

```yaml
# playbooks/deploy_to_prod.yml
---
- name: Deploy to Production
  hosts: "{{ target_group | default('prod') }}"
  become: true
  gather_facts: false
  serial: "25%"

  vars:
    release_tag:   "{{ release_tag   | default('v1.0.0') }}"
    environment:   "{{ environment   | default('prod') }}"
    change_ticket: "{{ change_ticket | default('N/A') }}"

  tasks:
    - name: Mostrar información del deploy de producción
      ansible.builtin.debug:
        msg:
          - "=== DEPLOY TO PROD ==="
          - "Versión:  {{ release_tag }}"
          - "Host:     {{ inventory_hostname }}"
          - "Ticket:   {{ change_ticket }}"

    - name: Crear directorio de release
      ansible.builtin.file:
        path: "/opt/webapp/releases/{{ release_tag }}"
        state: directory
        mode: '0755'

    - name: Desplegar versión {{ release_tag }}
      ansible.builtin.copy:
        content: |
          version={{ release_tag }}
          environment={{ environment }}
          deployed_at={{ ansible_date_time.iso8601 | default('now') }}
          change_ticket={{ change_ticket }}
        dest: "/opt/webapp/releases/{{ release_tag }}/VERSION"
        mode: '0644'

    - name: Actualizar enlace simbólico current
      ansible.builtin.file:
        src: "/opt/webapp/releases/{{ release_tag }}"
        dest: /opt/webapp/current
        state: link
        force: true

    - name: Registrar deploy exitoso
      ansible.builtin.set_stats:
        data:
          deployed_version: "{{ release_tag }}"
          deploy_successful: true
        per_host: false
```

```yaml
# playbooks/rollback_app.yml
---
- name: Rollback Application
  hosts: "{{ target_group | default('prod') }}"
  become: true
  gather_facts: false

  vars:
    release_tag:      "{{ release_tag      | default('v1.0.0') }}"
    previous_version: "{{ previous_version | default('v0.9.0') }}"
    environment:      "{{ environment      | default('prod') }}"

  tasks:
    - name: Mostrar información del rollback
      ansible.builtin.debug:
        msg:
          - "=== ROLLBACK ==="
          - "Versión fallida:  {{ release_tag }}"
          - "Rollback a:       {{ previous_version }}"
          - "Host:             {{ inventory_hostname }}"

    - name: Verificar que la versión anterior existe
      ansible.builtin.stat:
        path: "/opt/webapp/releases/{{ previous_version }}"
      register: prev_version_stat

    - name: Restaurar versión anterior
      ansible.builtin.file:
        src: "/opt/webapp/releases/{{ previous_version }}"
        dest: /opt/webapp/current
        state: link
        force: true
      when: prev_version_stat.stat.exists

    - name: Advertir si la versión anterior no existe
      ansible.builtin.debug:
        msg: "⚠️ ADVERTENCIA: versión {{ previous_version }} no encontrada. Rollback manual requerido."
      when: not prev_version_stat.stat.exists

    - name: Registrar rollback
      ansible.builtin.set_stats:
        data:
          rollback_performed: true
          rollback_to_version: "{{ previous_version }}"
        per_host: false
```

```yaml
# playbooks/post_deploy_notify.yml
---
- name: Post Deploy Notification
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    release_tag:       "{{ release_tag       | default('unknown') }}"
    environment:       "{{ environment       | default('unknown') }}"
    change_ticket:     "{{ change_ticket     | default('N/A') }}"
    deploy_successful: "{{ deploy_successful | default(false) }}"

  tasks:
    - name: Registrar deploy en log de auditoría
      ansible.builtin.copy:
        content: |
          DEPLOY AUDIT LOG
          ================
          Timestamp:  {{ lookup('pipe', 'date -u +%Y-%m-%dT%H:%M:%SZ') }}
          Version:    {{ release_tag }}
          Env:        {{ environment }}
          Ticket:     {{ change_ticket }}
          Success:    {{ deploy_successful }}
        dest: "/tmp/deploy_audit_{{ release_tag }}_{{ environment }}.log"
        mode: '0644'

    - name: Mostrar resumen del deploy
      ansible.builtin.debug:
        msg:
          - "=== POST DEPLOY ==="
          - "Versión:  {{ release_tag }}"
          - "Entorno:  {{ environment }}"
          - "Estado:   {{ 'SUCCESS ✅' if deploy_successful | bool else 'FAILED ❌' }}"
          - "Ticket:   {{ change_ticket }}"
```

### Commit todos los playbooks

```bash
git add playbooks/
git commit -m "feat: añadir playbooks para workflow de entrega completo"
git push origin main

# Sincronizar el proyecto en AWX
# Projects → Platform Playbooks → Sync
```

## Paso 2 — Crear los Job Templates

```
# Template 1: Provision Infra
Templates → Add → Job Template
  Name:      WF - Provision Infra
  Inventory: Env Inventory
  Project:   Platform Playbooks
  Playbook:  playbooks/provision_infra.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save

# Template 2: Configure App
Templates → Add → Job Template
  Name:      WF - Configure App
  Inventory: Env Inventory
  Project:   Platform Playbooks
  Playbook:  playbooks/configure_app.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save

# Template 3: Run Tests
Templates → Add → Job Template
  Name:      WF - Run Tests
  Inventory: Env Inventory
  Project:   Platform Playbooks
  Playbook:  playbooks/run_tests.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save

# Template 4: Deploy to Prod
Templates → Add → Job Template
  Name:      WF - Deploy to Prod
  Inventory: Env Inventory
  Project:   Platform Playbooks (Prod)
  Playbook:  playbooks/deploy_to_prod.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save

# Template 5: Rollback App
Templates → Add → Job Template
  Name:      WF - Rollback App
  Inventory: Env Inventory
  Project:   Platform Playbooks
  Playbook:  playbooks/rollback_app.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save

# Template 6: Post Deploy Notify
Templates → Add → Job Template
  Name:      WF - Post Deploy Notify
  Inventory: Env Inventory
  Project:   Platform Playbooks
  Playbook:  playbooks/post_deploy_notify.yml
  EE:        Default EE
  Credentials: Platform SSH
  → Save
```

## Paso 3 — Crear el Workflow Template

```
Templates → Add → Workflow Template

  Name:         App Delivery Pipeline
  Description:  |
    Pipeline completo de entrega de la aplicación web.
    Pasos: Provision → Configure → Tests → Approval → Deploy → Notify
    Rollback automático en caso de fallo.
  Organization: MiEmpresa
  Inventory:    Env Inventory   (default, los nodos pueden sobreescribir)

  Extra Variables:
    ---
    previous_version: v1.0.0
    target_group: dev
    maintenance_window: "02:00-04:00 UTC"
    oncall_team: "@oncall-infra"

  → Save
```

## Paso 4 — Añadir el Survey al Workflow

```
Templates → App Delivery Pipeline → Survey → Add Questions

── Pregunta 1 ───────────────────────────────────────────────────
  Question:             Versión a desplegar
  Answer Variable Name: release_tag
  Answer Type:          Text
  Default:              v1.0.0
  Required:             ✅

── Pregunta 2 ───────────────────────────────────────────────────
  Question:             Entorno objetivo
  Answer Variable Name: environment
  Answer Type:          Multiple Choice (single select)
  Choices:              dev / stage / prod
  Default:              dev
  Required:             ✅

── Pregunta 3 ───────────────────────────────────────────────────
  Question:             Grupo de hosts objetivo
  Answer Variable Name: target_group
  Answer Type:          Multiple Choice (single select)
  Choices:              dev / stage / prod / prod_web
  Default:              dev
  Required:             ✅

── Pregunta 4 ───────────────────────────────────────────────────
  Question:             Ticket de cambio
  Answer Variable Name: change_ticket
  Answer Type:          Text
  Min Length:           0
  Max Length:           50
  Default:              (vacío)
  Required:             ❌

── Pregunta 5 ───────────────────────────────────────────────────
  Question:             Versión anterior (para rollback)
  Answer Variable Name: previous_version
  Answer Type:          Text
  Default:              v1.0.0
  Required:             ❌

Survey Enabled: ✅ ON
→ Save
```

## Paso 5 — Construir el grafo en el Visualizer

```
Templates → App Delivery Pipeline → Visualizer
```

**Construir nodo a nodo:**

```
NODO RAÍZ:
  Click "Start" → Add Node
  Node Type:  Job Template
  Template:   WF - Provision Infra
  → Save

DESDE "Provision Infra" (success):
  Click "+" → Add Node
  Node Type:  Job Template
  Template:   WF - Configure App
  Edge:       On Success
  → Save

DESDE "Provision Infra" (failure):
  Click "+" → Add Node
  Node Type:  Job Template
  Template:   WF - Post Deploy Notify
  Edge:       On Failure
  → Save

DESDE "Configure App" (success):
  Click "+" → Add Node
  Node Type:  Job Template
  Template:   WF - Run Tests
  Edge:       On Success
  → Save

DESDE "Configure App" (failure):
  Click "+" → Add Node
  Node Type:  Job Template
  Template:   WF - Rollback App
  Edge:       On Failure
  → Save

DESDE "Rollback App" (always):
  Conectar al nodo "WF - Post Deploy Notify" ya existente
  Edge: On Always

DESDE "Run Tests" (success):
  Click "+" → Add Node
  Node Type:  Approval
  Name:       Go/No-Go para Producción
  Description: |
    Antes de aprobar, verifica:
    ✅ Tests pasaron: ver resultados en el job anterior
    ✅ Ticket {{ change_ticket }} aprobado en el CAB
    ✅ Ventana de cambio activa
    ✅ Equipo de guardia notificado
  Timeout:    7200
  Edge:       On Success
  → Save

DESDE "Run Tests" (failure):
  Conectar al nodo "WF - Rollback App" ya existente
  Edge: On Failure

DESDE "Go/No-Go" (success / approved):
  Click "+" → Add Node
  Node Type:  Job Template
  Template:   WF - Deploy to Prod
  Edge:       On Success
  → Save

DESDE "Go/No-Go" (failure / denied o timeout):
  Conectar al nodo "WF - Rollback App" ya existente
  Edge: On Failure

DESDE "Deploy to Prod" (success):
  Conectar al nodo "WF - Post Deploy Notify" ya existente
  Edge: On Success

DESDE "Deploy to Prod" (failure):
  Conectar al nodo "WF - Rollback App" ya existente
  Edge: On Failure

DESDE "Deploy to Prod" (always):
  Conectar al nodo "WF - Post Deploy Notify" ya existente
  Edge: On Always
```

## El grafo resultante

```
                         ┌──────────────────┐
                         │  Provision Infra  │  (nodo raíz)
                         └────────┬─────────┘
                         success  │   failure
                    ┌─────────────┘     └──────────────────────┐
                    ▼                                           ▼
          ┌──────────────────┐                    ┌────────────────────┐
          │  Configure App   │                    │ Post Deploy Notify │◄─┐
          └────────┬─────────┘                    └────────────────────┘  │
          success  │   failure                                             │
     ┌─────────────┘     └──────────────────┐                             │
     ▼                                      ▼                             │
┌──────────────┐                   ┌──────────────────┐                   │
│  Run Tests   │                   │   Rollback App   │───── always ──────┘
└──────┬───────┘                   └──────────────────┘
success│   failure──────────────────────────▲
       ▼                                    │
┌──────────────────────┐                    │
│  Go/No-Go (Approval) │                    │
└──────┬───────────────┘                    │
approved│  denied/timeout────────────────────┘
        ▼
┌──────────────────┐
│  Deploy to Prod  │─── failure ────────────▲
└──────┬───────────┘                        │
success│                                    │
       │  always ───────────────────────────┘
       ▼
┌────────────────────┐
│ Post Deploy Notify │
└────────────────────┘
```

## Paso 6 — Lanzar y verificar el Workflow

```
Templates → App Delivery Pipeline → Launch (🚀)

Survey:
  release_tag:      v2.0.0
  environment:      dev
  target_group:     dev
  change_ticket:    DEV-TEST-001
  previous_version: v1.0.0

→ Launch

# Observar en tiempo real:
# Jobs → Workflow Jobs → App Delivery Pipeline #1
# Ver el grafo con nodos coloreados según su estado:
#   Gris    → pendiente
#   Amarillo → ejecutándose
#   Verde   → exitoso
#   Rojo    → fallido
```

---

# 4.11 LAB — Nodo de aprobación con permisos y timeout

## Paso 1 — Crear el equipo de aprobadores

```
Teams → Add
  Name:         Change Advisory Board
  Description:  Equipo autorizado para aprobar cambios en producción
  Organization: MiEmpresa
  → Save

# Añadir usuarios al equipo CAB
Teams → Change Advisory Board → Users → Add
  + usuario_cab1
  + usuario_cab2
```

## Paso 2 — Asignar permisos de aprobación al Workflow

```
Templates → App Delivery Pipeline → Access → Add

  Team:  Change Advisory Board
  Role:  Approve

# También dar Read para que puedan ver el contexto:
  Team:  Change Advisory Board
  Role:  Read
```

## Paso 3 — Configurar notificación de aprobación pendiente

```
# Primero crear la notificación (ver sección 4.12)
# Luego adjuntarla:

Templates → App Delivery Pipeline → Notifications

  On Approval Pending:  ✅ Slack - CAB Channel
```

## Paso 4 — Probar el flujo de aprobación

```bash
# Lanzar el workflow como operador normal
# El workflow llegará al nodo de aprobación y se pausará

# Ver el estado via API
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/workflow_jobs/?order_by=-id&page_size=1" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
wf = data['results'][0]
print(f'Workflow Job ID: {wf[\"id\"]}')
print(f'Status: {wf[\"status\"]}')
print(f'Name: {wf[\"name\"]}')
"

# Ver los nodos del workflow job (para encontrar el nodo de aprobación)
WF_JOB_ID=1  # ajusta
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/workflow_jobs/${WF_JOB_ID}/workflow_nodes/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for node in data['results']:
    if node.get('type') == 'workflow_approval':
        print(f'Approval Node ID: {node[\"id\"]}')
        print(f'Status: {node[\"status\"]}')
        print(f'Approval URL: /api/v2/workflow_approvals/{node[\"id\"]}/')
"
```

## Paso 5 — Aprobar via API (simular el aprobador)

```bash
# Aprobar el nodo de aprobación via API
APPROVAL_ID=1  # ajusta al ID del nodo de aprobación
curl -s -u "admin:TuPasswordSegura123!" \
  -X POST \
  -H "Content-Type: application/json" \
  "http://localhost:30080/api/v2/workflow_approvals/${APPROVAL_ID}/approve/" \
  -d '{}' \
  | python3 -m json.tool

# Rechazar (para probar el camino de failure/rollback)
curl -s -u "admin:TuPasswordSegura123!" \
  -X POST \
  -H "Content-Type: application/json" \
  "http://localhost:30080/api/v2/workflow_approvals/${APPROVAL_ID}/deny/" \
  -d '{}' \
  | python3 -m json.tool
```

## Paso 6 — Verificar el registro de auditoría

```bash
# Ver el activity stream del workflow job
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/activity_stream/?object1=workflow_job&object1_id=${WF_JOB_ID}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Eventos de auditoría: {data[\"count\"]}')
for event in data['results'][:10]:
    print(f'  {event[\"timestamp\"]} | {event[\"actor\"][\"username\"]} | {event[\"operation\"]}')
"
```

---

# 4.12 LAB — Notificaciones Slack con mensajes personalizados

## Paso 1 — Crear un Incoming Webhook en Slack

```
1. Ir a: https://api.slack.com/apps
2. Create New App → From scratch
   App Name: AWX Notifications
   Workspace: tu workspace

3. Features → Incoming Webhooks → Activate Incoming Webhooks: ON

4. Add New Webhook to Workspace
   Channel: #deployments
   → Allow

5. Copiar el Webhook URL:
   https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```

## Paso 2 — Crear la Notification Template en AWX

```
Notifications → Add

  Name:         Slack - Deployments
  Description:  Notificaciones de deploys al canal #deployments
  Organization: MiEmpresa
  Type:         Slack

  Token:        xoxb-tu-bot-token
                (o usar Webhook URL directamente si el tipo lo permite)

  Destination Channels: #deployments

  → Save
```

## Paso 3 — Personalizar los mensajes

```
Notifications → Slack - Deployments → Edit

── Mensaje de SUCCESS ───────────────────────────────────────────
  Custom Success Message:
  {
    "attachments": [
      {
        "color": "#36a64f",
        "title": "✅ Deploy Exitoso",
        "title_link": "{{ url }}",
        "fields": [
          {
            "title": "Workflow",
            "value": "{{ workflow_job_template_name }}",
            "short": true
          },
          {
            "title": "Versión",
            "value": "{{ extra_vars.release_tag | default('N/A') }}",
            "short": true
          },
          {
            "title": "Entorno",
            "value": "{{ extra_vars.environment | default('N/A') }}",
            "short": true
          },
          {
            "title": "Ticket",
            "value": "{{ extra_vars.change_ticket | default('N/A') }}",
            "short": true
          },
          {
            "title": "Duración",
            "value": "{{ elapsed }}s",
            "short": true
          },
          {
            "title": "Lanzado por",
            "value": "{{ created_by }}",
            "short": true
          }
        ],
        "footer": "AWX Automation Platform",
        "ts": "{{ started | int }}"
      }
    ]
  }

── Mensaje de FAILURE ───────────────────────────────────────────
  Custom Failure Message:
  {
    "attachments": [
      {
        "color": "#ff0000",
        "title": "❌ FALLO en Deploy",
        "title_link": "{{ url }}",
        "text": "El pipeline de entrega ha fallado. Acción requerida.",
        "fields": [
          {
            "title": "Workflow",
            "value": "{{ workflow_job_template_name }}",
            "short": true
          },
          {
            "title": "Versión",
            "value": "{{ extra_vars.release_tag | default('N/A') }}",
            "short": true
          },
          {
            "title": "Entorno",
            "value": "{{ extra_vars.environment | default('N/A') }}",
            "short": true
          },
          {
            "title": "Ticket",
            "value": "{{ extra_vars.change_ticket | default('N/A') }}",
            "short": true
          },
          {
            "title": "Hosts con fallos",
            "value": "{{ hosts_with_failures | default('N/A') }}",
            "short": false
          }
        ],
        "footer": "AWX Automation Platform | Revisar logs: {{ url }}"
      }
    ]
  }

── Mensaje de APPROVAL PENDING ──────────────────────────────────
  Custom Approval Pending Message:
  {
    "attachments": [
      {
        "color": "#ff9900",
        "title": "⏳ Aprobación Requerida",
        "title_link": "{{ approval_node_url }}",
        "text": "Se requiere aprobación para continuar el pipeline de producción.",
        "fields": [
          {
            "title": "Workflow",
            "value": "{{ workflow_job_template_name }}",
            "short": true
          },
          {
            "title": "Versión",
            "value": "{{ extra_vars.release_tag | default('N/A') }}",
            "short": true
          },
          {
            "title": "Ticket",
            "value": "{{ extra_vars.change_ticket | default('N/A') }}",
            "short": true
          },
          {
            "title": "Expira en",
            "value": "2 horas",
            "short": true
          }
        ],
        "actions": [
          {
            "type": "button",
            "text": "Revisar y Aprobar",
            "url": "{{ approval_node_url }}",
            "style": "primary"
          }
        ],
        "footer": "CC: @change-advisory-board"
      }
    ]
  }
```

## Paso 4 — Adjuntar notificaciones al Workflow

```
Templates → App Delivery Pipeline → Notifications

  On Start:            ☐  (demasiado ruido)
  On Success:          ✅ Slack - Deployments
  On Failure:          ✅ Slack - Deployments
  On Approval Pending: ✅ Slack - Deployments
  On Approval Granted: ✅ Slack - Deployments
  On Approval Denied:  ✅ Slack - Deployments
```

## Paso 5 — Crear notificación separada para el canal de CAB

```
Notifications → Add
  Name:         Slack - CAB Channel
  Type:         Slack
  Destination:  #change-advisory-board
  → Save

# Adjuntar solo para aprobaciones
Templates → App Delivery Pipeline → Notifications
  On Approval Pending: ✅ Slack - CAB Channel
  On Approval Granted: ✅ Slack - CAB Channel
  On Approval Denied:  ✅ Slack - CAB Channel
```

## Paso 6 — Verificar las notificaciones

```bash
# Ver el historial de notificaciones enviadas
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/notifications/?order_by=-id&page_size=5" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for notif in data['results']:
    status = '✅' if notif['status'] == 'successful' else '❌'
    print(f'{status} ID:{notif[\"id\"]} | {notif[\"notification_type\"]} | {notif[\"status\"]}')
    if notif['status'] == 'failed':
        print(f'   Error: {notif.get(\"error\", \"N/A\")}')
"
```
---

# 4.13 LAB — Notificaciones por email y webhook genérico

## Notificación por Email

```
Notifications → Add

  Name:         Email - Ops Team
  Description:  Notificaciones críticas al equipo de operaciones
  Organization: MiEmpresa
  Type:         Email

  Host:         smtp.empresa.com
  Port:         587
  Username:     awx-notifications@empresa.com
  Password:     SmtpPassword123!
  Use TLS:      ✅
  Use SSL:      ☐

  Sender:       awx-notifications@empresa.com
  Recipients:   ops-team@empresa.com, oncall@empresa.com

  Subject:
    [AWX] {{ status | upper }} - {{ workflow_job_template_name }}

  Body:
    Pipeline:  {{ workflow_job_template_name }}
    Status:    {{ status }}
    Versión:   {{ extra_vars.release_tag | default('N/A') }}
    Entorno:   {{ extra_vars.environment | default('N/A') }}
    Ticket:    {{ extra_vars.change_ticket | default('N/A') }}
    Duración:  {{ elapsed }}s
    Iniciado:  {{ started }}
    Finalizado:{{ finished }}

    Ver detalles: {{ url }}

    -- AWX Automation Platform

  → Save
```

## Notificación por Webhook genérico (ServiceNow)

Útil para integrar con sistemas ITSM, observabilidad o cualquier API REST.

```
Notifications → Add

  Name:         Webhook - ServiceNow
  Description:  Actualizar tickets en ServiceNow al completar deploys
  Organization: MiEmpresa
  Type:         Webhook

  Target URL:   https://tuinstancia.service-now.com/api/now/table/change_request/{{ extra_vars.change_ticket }}
  HTTP Method:  PATCH

  HTTP Headers:
    Content-Type:  application/json
    Authorization: Basic dXNlcjpwYXNz==
    Accept:        application/json

  Body:
    {
      "state": "{{ '3' if status == 'successful' else '4' }}",
      "close_code": "{{ 'successful' if status == 'successful' else 'unsuccessful' }}",
      "close_notes": "Deploy {{ extra_vars.release_tag | default('N/A') }} en {{ extra_vars.environment | default('N/A') }}: {{ status }}. AWX Job: {{ url }}",
      "work_notes": "Completado por AWX Automation Platform. Duración: {{ elapsed }}s. Lanzado por: {{ created_by }}"
    }

  → Save
```

## Notificación para PagerDuty

```
Notifications → Add

  Name:         PagerDuty - Critical Failures
  Description:  Alertas críticas para fallos en producción
  Organization: MiEmpresa
  Type:         PagerDuty

  API Token:    tu-pagerduty-api-token
  Subdomain:    tu-empresa
  Service Key:  tu-service-integration-key
  Client URL:   {{ url }}

  → Save

# Adjuntar solo a fallos de producción
Templates → App Delivery Pipeline → Notifications
  On Failure: ✅ PagerDuty - Critical Failures
```

## Adjuntar múltiples notificaciones por evento

```
Templates → App Delivery Pipeline → Notifications

  On Start:
    ☐  (evitar ruido; solo activar en pipelines críticos)

  On Success:
    ✅ Slack - Deployments
    ✅ Email - Ops Team
    ✅ Webhook - ServiceNow

  On Failure:
    ✅ Slack - Deployments
    ✅ Email - Ops Team
    ✅ Webhook - ServiceNow
    ✅ PagerDuty - Critical Failures  (solo prod)

  On Approval Pending:
    ✅ Slack - CAB Channel
    ✅ Email - Ops Team

  On Approval Granted:
    ✅ Slack - CAB Channel

  On Approval Denied:
    ✅ Slack - CAB Channel
    ✅ Email - Ops Team
```

## Verificar el historial de notificaciones enviadas

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver las últimas notificaciones
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/notifications/?order_by=-id&page_size=10" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total notificaciones: {data[\"count\"]}')
print()
for notif in data['results']:
    icon = '✅' if notif['status'] == 'successful' else '❌'
    print(f'{icon} ID:{notif[\"id\"]:4} | {notif[\"notification_type\"]:10} | {notif[\"status\"]:12} | {notif.get(\"subject\",\"\")}')
    if notif['status'] == 'failed':
        print(f'     Error: {notif.get(\"error\", \"N/A\")}')
"
```

---

# 4.14 LAB — Trigger desde GitHub Actions via API

*GitHub Actions lanza el Workflow de AWX automáticamente después de que el CI pase.*

## Paso 1 — Crear un token de API en AWX

```
AWX UI → (icono de usuario arriba a la derecha) → User Tokens → Add

  Description:  GitHub Actions CI Token
  Application:  (dejar vacío para token personal)
  Scope:        Write

→ Save

# Copiar el token generado (solo se muestra UNA VEZ)
# Ejemplo: 7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b
```

## Paso 2 — Obtener el ID del Workflow Template

```bash
# Buscar el ID del Workflow Template via API
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/workflow_job_templates/?name=App+Delivery+Pipeline" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    wft = data['results'][0]
    print(f'Workflow Template ID: {wft[\"id\"]}')
    print(f'Name:                 {wft[\"name\"]}')
    print(f'Survey enabled:       {wft[\"survey_enabled\"]}')
else:
    print('Workflow Template no encontrado')
"
# Workflow Template ID: 3
```

## Paso 3 — Configurar secrets en GitHub

```
GitHub → Repo → Settings → Secrets and variables → Actions

New repository secret:
  AWX_URL:     http://tu-awx-ip:30080
  AWX_TOKEN:   7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b
  AWX_WFT_ID:  3
```

## Paso 4 — Crear el workflow completo de GitHub Actions

```yaml
# .github/workflows/ci-cd.yml
---
name: CI/CD → AWX Deploy

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    branches:
      - main

jobs:

  # ── JOB 1: Lint ───────────────────────────────────────────────
  lint:
    name: 🔍 Ansible Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout código
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: pip

      - name: Instalar dependencias
        run: |
          pip install ansible-core ansible-lint

      - name: Ejecutar ansible-lint
        run: ansible-lint --show-relpath

      - name: Verificar sintaxis de playbooks
        run: |
          for playbook in playbooks/*.yml; do
            echo "Verificando sintaxis: $playbook"
            ansible-playbook --syntax-check "$playbook" \
              -i "localhost," \
              -e "target_group=localhost" \
              -e "ansible_connection=local" \
              -e "release_tag=v0.0.0" \
              -e "environment=dev"
          done

  # ── JOB 2: Deploy a Stage via AWX ────────────────────────────
  deploy-stage:
    name: 🚀 Deploy Stage via AWX
    runs-on: ubuntu-latest
    needs: lint
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: stage
      url: ${{ secrets.AWX_URL }}

    steps:
      - name: Lanzar Workflow AWX en Stage
        id: launch_workflow
        env:
          AWX_URL:    ${{ secrets.AWX_URL }}
          AWX_TOKEN:  ${{ secrets.AWX_TOKEN }}
          AWX_WFT_ID: ${{ secrets.AWX_WFT_ID }}
        run: |
          # Extraer versión del tag o usar el SHA corto
          RELEASE_TAG="${GITHUB_REF_NAME:-v0.0.0}"
          if [[ "$RELEASE_TAG" == "main" ]]; then
            RELEASE_TAG="v0.0.0-${GITHUB_SHA::7}"
          fi

          echo "Lanzando workflow AWX..."
          echo "  URL:     ${AWX_URL}"
          echo "  WFT ID:  ${AWX_WFT_ID}"
          echo "  Release: ${RELEASE_TAG}"
          echo "  Commit:  ${GITHUB_SHA::7}"

          # Lanzar el workflow
          RESPONSE=$(curl -sS -w "\n%{http_code}" \
            -X POST "${AWX_URL}/api/v2/workflow_job_templates/${AWX_WFT_ID}/launch/" \
            -H "Authorization: Bearer ${AWX_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
              \"extra_vars\": {
                \"release_tag\":     \"${RELEASE_TAG}\",
                \"environment\":     \"stage\",
                \"target_group\":    \"stage\",
                \"change_ticket\":   \"CI-${GITHUB_RUN_NUMBER}\",
                \"previous_version\":\"v0.0.0\",
                \"git_commit\":      \"${GITHUB_SHA}\",
                \"git_ref\":         \"${GITHUB_REF}\",
                \"triggered_by\":    \"github-actions\"
              }
            }")

          HTTP_CODE=$(echo "$RESPONSE" | tail -1)
          BODY=$(echo "$RESPONSE" | head -1)

          echo "HTTP Status: ${HTTP_CODE}"

          if [ "$HTTP_CODE" != "201" ]; then
            echo "❌ Error lanzando workflow AWX"
            echo "Response: $BODY"
            exit 1
          fi

          # Extraer el ID del workflow job
          WF_JOB_ID=$(echo "$BODY" | python3 -c "
          import sys, json
          data = json.load(sys.stdin)
          print(data['id'])
          ")

          echo "✅ Workflow lanzado: Job ID ${WF_JOB_ID}"
          echo "🔗 ${AWX_URL}/#/jobs/workflow/${WF_JOB_ID}"

          # Guardar el ID para el siguiente step
          echo "wf_job_id=${WF_JOB_ID}" >> $GITHUB_OUTPUT
          echo "awx_url=${AWX_URL}" >> $GITHUB_OUTPUT

      - name: Esperar resultado del Workflow AWX
        env:
          AWX_URL:   ${{ steps.launch_workflow.outputs.awx_url }}
          AWX_TOKEN: ${{ secrets.AWX_TOKEN }}
          WF_JOB_ID: ${{ steps.launch_workflow.outputs.wf_job_id }}
        run: |
          echo "Esperando resultado del Workflow Job ${WF_JOB_ID}..."
          echo "🔗 ${AWX_URL}/#/jobs/workflow/${WF_JOB_ID}"

          MAX_WAIT=1800  # 30 minutos máximo
          INTERVAL=15    # comprobar cada 15 segundos
          ELAPSED=0

          while [ $ELAPSED -lt $MAX_WAIT ]; do
            STATUS=$(curl -sS \
              -H "Authorization: Bearer ${AWX_TOKEN}" \
              "${AWX_URL}/api/v2/workflow_jobs/${WF_JOB_ID}/" \
              | python3 -c "
          import sys, json
          data = json.load(sys.stdin)
          print(data['status'])
          ")

            echo "  [${ELAPSED}s] Status: ${STATUS}"

            case "$STATUS" in
              "successful")
                echo "✅ Workflow completado con éxito"
                exit 0
                ;;
              "failed"|"error"|"canceled")
                echo "❌ Workflow falló con status: ${STATUS}"
                echo "🔗 Ver detalles: ${AWX_URL}/#/jobs/workflow/${WF_JOB_ID}"
                exit 1
                ;;
              "pending"|"waiting"|"running")
                # Continuar esperando
                ;;
              *)
                echo "⚠️ Status desconocido: ${STATUS}"
                ;;
            esac

            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
          done

          echo "⏰ Timeout esperando el workflow (${MAX_WAIT}s)"
          exit 1

      - name: Publicar resultado en el PR
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            const wfJobId = '${{ steps.launch_workflow.outputs.wf_job_id }}';
            const awxUrl  = '${{ steps.launch_workflow.outputs.awx_url }}';
            const status  = '${{ job.status }}';
            const icon    = status === 'success' ? '✅' : '❌';

            if (context.eventName === 'pull_request') {
              await github.rest.issues.createComment({
                owner:    context.repo.owner,
                repo:     context.repo.repo,
                issue_number: context.issue.number,
                body: `## ${icon} AWX Deploy Stage\n\n` +
                      `**Status:** ${status}\n` +
                      `**Workflow Job:** [#${wfJobId}](${awxUrl}/#/jobs/workflow/${wfJobId})\n` +
                      `**Commit:** ${context.sha.substring(0,7)}\n`
              });
            }

  # ── JOB 3: Deploy a Prod via AWX (solo en tags) ───────────────
  deploy-prod:
    name: 🏭 Deploy Prod via AWX
    runs-on: ubuntu-latest
    needs: deploy-stage
    if: startsWith(github.ref, 'refs/tags/v')
    environment:
      name: production
      url: ${{ secrets.AWX_URL }}

    steps:
      - name: Extraer versión del tag
        id: version
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          echo "tag=${TAG}" >> $GITHUB_OUTPUT
          echo "Desplegando versión: ${TAG}"

      - name: Lanzar Workflow AWX en Prod
        env:
          AWX_URL:    ${{ secrets.AWX_URL }}
          AWX_TOKEN:  ${{ secrets.AWX_TOKEN }}
          AWX_WFT_ID: ${{ secrets.AWX_WFT_ID }}
          RELEASE_TAG: ${{ steps.version.outputs.tag }}
        run: |
          echo "🏭 Lanzando deploy de PRODUCCIÓN: ${RELEASE_TAG}"

          RESPONSE=$(curl -sS -w "\n%{http_code}" \
            -X POST "${AWX_URL}/api/v2/workflow_job_templates/${AWX_WFT_ID}/launch/" \
            -H "Authorization: Bearer ${AWX_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
              \"extra_vars\": {
                \"release_tag\":     \"${RELEASE_TAG}\",
                \"environment\":     \"prod\",
                \"target_group\":    \"prod\",
                \"change_ticket\":   \"RELEASE-${RELEASE_TAG}\",
                \"triggered_by\":    \"github-actions-tag\"
              }
            }")

          HTTP_CODE=$(echo "$RESPONSE" | tail -1)
          BODY=$(echo "$RESPONSE" | head -1)

          if [ "$HTTP_CODE" != "201" ]; then
            echo "❌ Error: HTTP ${HTTP_CODE}"
            echo "$BODY"
            exit 1
          fi

          WF_JOB_ID=$(echo "$BODY" | python3 -c "
          import sys, json
          print(json.load(sys.stdin)['id'])
          ")

          echo "✅ Workflow de producción lanzado: Job ID ${WF_JOB_ID}"
          echo "🔗 ${AWX_URL}/#/jobs/workflow/${WF_JOB_ID}"
          echo "⏳ El workflow requiere aprobación manual del CAB en AWX"
```

## Paso 5 — Probar el pipeline completo

```bash
# Simular un push a main
echo "# Test CI/CD $(date)" >> README.md
git add README.md
git commit -m "ci: test pipeline completo CI → AWX"
git push origin main

# Observar en GitHub Actions:
# Actions → CI/CD → AWX Deploy → ver los jobs

# Observar en AWX:
# Jobs → Workflow Jobs → ver el workflow lanzado por CI
```

---

# 4.15 LAB — Trigger desde GitLab CI via webhook de proyecto

*Alternativa a GitHub Actions: GitLab CI lanza AWX usando el webhook del proyecto.*

## Opción A: Via webhook del proyecto AWX

### Paso 1 — Habilitar webhook en el proyecto AWX

```
Projects → Platform Playbooks → Edit

  Options:
    ✅ Enable Webhook
    Webhook Service: GitLab

→ Save

# AWX genera:
#   Webhook URL:    http://awx:30080/api/v2/projects/1/update/
#   Webhook Key:    abc123secretkey456
```

### Paso 2 — Configurar webhook en GitLab

```
GitLab → Repo → Settings → Webhooks → Add new webhook

  URL:             http://awx:30080/api/v2/projects/1/update/
  Secret token:    abc123secretkey456
  Trigger:         ✅ Push events
  SSL verification: ☐ (si AWX no tiene HTTPS)

→ Add webhook → Test → Push events
```

## Opción B: Via API de AWX desde .gitlab-ci.yml

```yaml
# .gitlab-ci.yml
---
stages:
  - lint
  - test
  - deploy-stage
  - deploy-prod

variables:
  AWX_URL:    "http://tu-awx-ip:30080"
  AWX_WFT_ID: "3"

# ── STAGE: Lint ───────────────────────────────────────────────
ansible-lint:
  stage: lint
  image: python:3.11-slim
  before_script:
    - pip install ansible-core ansible-lint
  script:
    - ansible-lint --show-relpath
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"

syntax-check:
  stage: lint
  image: python:3.11-slim
  before_script:
    - pip install ansible-core
  script:
    - |
      for playbook in playbooks/*.yml; do
        echo "Verificando: $playbook"
        ansible-playbook --syntax-check "$playbook" \
          -i "localhost," \
          -e "ansible_connection=local" \
          -e "target_group=localhost" \
          -e "release_tag=v0.0.0"
      done
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"

# ── STAGE: Deploy Stage ───────────────────────────────────────
deploy-to-stage:
  stage: deploy-stage
  image: python:3.11-slim
  before_script:
    - pip install requests
  script:
    - |
      python3 << 'PYTHON_SCRIPT'
      import os, sys, time, requests

      awx_url    = os.environ['AWX_URL']
      awx_token  = os.environ['AWX_TOKEN']
      wft_id     = os.environ['AWX_WFT_ID']
      release    = os.environ.get('CI_COMMIT_TAG', f"v0.0.0-{os.environ['CI_COMMIT_SHORT_SHA']}")
      run_number = os.environ['CI_PIPELINE_ID']

      headers = {
          'Authorization': f'Bearer {awx_token}',
          'Content-Type': 'application/json'
      }

      # Lanzar el workflow
      payload = {
          'extra_vars': {
              'release_tag':   release,
              'environment':   'stage',
              'target_group':  'stage',
              'change_ticket': f'GITLAB-{run_number}',
              'triggered_by':  'gitlab-ci'
          }
      }

      print(f"Lanzando workflow AWX: {awx_url}/api/v2/workflow_job_templates/{wft_id}/launch/")
      resp = requests.post(
          f"{awx_url}/api/v2/workflow_job_templates/{wft_id}/launch/",
          json=payload,
          headers=headers,
          timeout=30
      )

      if resp.status_code != 201:
          print(f"❌ Error HTTP {resp.status_code}: {resp.text}")
          sys.exit(1)

      wf_job_id = resp.json()['id']
      print(f"✅ Workflow lanzado: Job ID {wf_job_id}")
      print(f"🔗 {awx_url}/#/jobs/workflow/{wf_job_id}")

      # Esperar resultado
      max_wait = 1800
      interval = 15
      elapsed  = 0

      while elapsed < max_wait:
          time.sleep(interval)
          elapsed += interval

          status_resp = requests.get(
              f"{awx_url}/api/v2/workflow_jobs/{wf_job_id}/",
              headers=headers,
              timeout=10
          )
          status = status_resp.json().get('status', 'unknown')
          print(f"  [{elapsed}s] Status: {status}")

          if status == 'successful':
              print("✅ Workflow completado con éxito")
              sys.exit(0)
          elif status in ('failed', 'error', 'canceled'):
              print(f"❌ Workflow falló: {status}")
              print(f"🔗 {awx_url}/#/jobs/workflow/{wf_job_id}")
              sys.exit(1)

      print(f"⏰ Timeout ({max_wait}s)")
      sys.exit(1)
      PYTHON_SCRIPT
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  environment:
    name: stage
    url: $AWX_URL

# ── STAGE: Deploy Prod (solo en tags) ─────────────────────────
deploy-to-prod:
  stage: deploy-prod
  image: python:3.11-slim
  before_script:
    - pip install requests
  script:
    - |
      python3 << 'PYTHON_SCRIPT'
      import os, sys, requests

      awx_url   = os.environ['AWX_URL']
      awx_token = os.environ['AWX_TOKEN']
      wft_id    = os.environ['AWX_WFT_ID']
      tag       = os.environ['CI_COMMIT_TAG']

      headers = {
          'Authorization': f'Bearer {awx_token}',
          'Content-Type': 'application/json'
      }

      payload = {
          'extra_vars': {
              'release_tag':   tag,
              'environment':   'prod',
              'target_group':  'prod',
              'change_ticket': f'RELEASE-{tag}',
              'triggered_by':  'gitlab-ci-tag'
          }
      }

      print(f"🏭 Lanzando deploy de PRODUCCIÓN: {tag}")
      resp = requests.post(
          f"{awx_url}/api/v2/workflow_job_templates/{wft_id}/launch/",
          json=payload,
          headers=headers,
          timeout=30
      )

      if resp.status_code != 201:
          print(f"❌ Error HTTP {resp.status_code}: {resp.text}")
          sys.exit(1)

      wf_job_id = resp.json()['id']
      print(f"✅ Workflow de producción lanzado: Job ID {wf_job_id}")
      print(f"🔗 {awx_url}/#/jobs/workflow/{wf_job_id}")
      print("⏳ El workflow requiere aprobación del CAB en AWX")
      PYTHON_SCRIPT
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
  environment:
    name: production
    url: $AWX_URL
  when: manual
```

### Configurar variables en GitLab

```
GitLab → Repo → Settings → CI/CD → Variables

  AWX_TOKEN:  (tu token de AWX, marcar como Masked y Protected)
  AWX_URL:    http://tu-awx-ip:30080
  AWX_WFT_ID: 3
```

---

# 4.16 Patrones avanzados y buenas prácticas

## Patrón 1: Workflow como contrato de proceso

Un Workflow no es solo automatización técnica: es la representación ejecutable de un proceso de negocio. Diseñarlo así cambia cómo lo construyes.

```
PROCESO DE NEGOCIO:
  "Para desplegar en producción necesitamos:
   1. Infraestructura provisionada y verificada
   2. Aplicación configurada correctamente
   3. Tests de integración pasando
   4. Aprobación del Change Advisory Board
   5. Deploy gradual (25% de hosts a la vez)
   6. Verificación post-deploy
   7. Notificación al equipo y actualización del ticket"

WORKFLOW AWX:
  Node 1: Provision Infra          → refleja el punto 1
  Node 2: Configure App            → refleja el punto 2
  Node 3: Run Integration Tests    → refleja el punto 3
  Node 4: Approval (CAB)           → refleja el punto 4
  Node 5: Deploy Prod (serial 25%) → refleja el punto 5
  Node 6: Smoke Tests              → refleja el punto 6
  Node 7: Post Deploy Notify       → refleja el punto 7

Cada nodo es trazable a un requisito del proceso.
```

---

## Patrón 2: Workflows anidados para reutilización

```
PROBLEMA:
  Tienes 3 aplicaciones (webapp, api, worker) que comparten
  el mismo proceso de deploy pero con playbooks diferentes.

SOLUCIÓN: Sub-workflows reutilizables

Sub-Workflow: "Deploy Component" (genérico)
  Node 1: Configure Component
  Node 2: Run Component Tests
  Node 3: Approval (si env=prod)
  Node 4: Deploy Component
  Node 5: Verify Component
  Node 6: Notify

Workflow Principal: "Deploy Full Stack"
  Node 1: Provision Infra
  Node 2: Sub-Workflow "Deploy WebApp"   ─┐
  Node 3: Sub-Workflow "Deploy API"       ├─ en paralelo (fan-out)
  Node 4: Sub-Workflow "Deploy Worker"   ─┘
  Node 5: Run E2E Tests                  (fan-in, Convergence: All)
  Node 6: Approval Final
  Node 7: Promote to Prod
```

---

## Patrón 3: Workflow de rollback independiente

Tener un Workflow de rollback separado del de deploy permite:
- Ejecutarlo manualmente en emergencias sin lanzar el pipeline completo
- Tener su propio Survey (versión a la que hacer rollback)
- Asignarlo a un equipo diferente (on-call puede hacer rollback sin poder hacer deploy)

```yaml
# Workflow: Emergency Rollback
# Survey: target_version (versión a la que volver)
# Permisos: On-Call Team puede Execute
# Aprobación: no requerida (es una emergencia)

Nodes:
  1. Verify Target Version Exists
  2. Approval "Confirmar Rollback de Emergencia"
     (timeout: 300 segundos = 5 minutos)
  3. Execute Rollback
  4. Verify Service Health
  5. Notify (con mensaje de urgencia)
```

---

## Patrón 4: Pipeline de promoción entre entornos

```
FLUJO DE PROMOCIÓN:

Workflow: "Promote Dev → Stage"
  Survey: release_tag
  Nodes:
    1. Sync Project (Stage)
    2. Deploy to Stage
    3. Run Stage Tests
    4. Tag Release in Git (via API)
    5. Notify: "Stage listo para revisión"

Workflow: "Promote Stage → Prod"
  Survey: release_tag, change_ticket
  Nodes:
    1. Verify Stage Tests Passed (check set_stats del workflow anterior)
    2. Approval (CAB)
    3. Deploy to Prod (serial: 25%)
    4. Smoke Tests
    5. Update CMDB
    6. Notify

VENTAJA:
  Cada promoción es un evento auditado con su propio ticket,
  aprobación y registro. Trazabilidad completa de qué versión
  pasó por qué entorno y quién lo aprobó.
```

---

## Patrón 5: Manejo de timeouts en aprobaciones

```
ESCENARIO: Aprobación con ventana de mantenimiento

Node: Approval "Deploy en Ventana de Mantenimiento"
  Timeout: 3600 (1 hora)
  
  Si expira (failure edge):
    → Node: "Notificar Ventana Perdida"
    → Node: "Cancelar Deploy y Reprogramar"
  
  Si se aprueba (success edge):
    → Node: "Verificar que estamos en ventana de mantenimiento"
      (playbook que comprueba la hora actual)
    → Node: "Deploy"

BUENA PRÁCTICA:
  Añadir una task en el playbook de deploy que verifique
  que la hora actual está dentro de la ventana permitida:
```

```yaml
# En playbooks/deploy_to_prod.yml
- name: Verificar ventana de mantenimiento
  ansible.builtin.assert:
    that:
      - ansible_date_time.hour | int >= 2
      - ansible_date_time.hour | int < 4
    fail_msg: >
      Deploy bloqueado: fuera de ventana de mantenimiento.
      Ventana permitida: 02:00-04:00 UTC.
      Hora actual: {{ ansible_date_time.time }} UTC.
    success_msg: "✅ Dentro de ventana de mantenimiento"
  when: environment == 'prod'
  tags: [always, maintenance_window]
```

---

## Patrón 6: Notificaciones inteligentes (evitar el ruido)

```
ESTRATEGIA DE NOTIFICACIONES:

Canal #deployments (general):
  → Solo Success y Failure de Workflows completos
  → NO notificar cada Job Template individual
  → NO notificar Started (demasiado ruido)

Canal #deployments-prod (producción):
  → Todo: Started, Success, Failure, Approval Pending/Granted/Denied
  → Más detalle en los mensajes (hosts afectados, duración)

Canal #alerts-critical (emergencias):
  → Solo Failure en producción
  → Integración con PagerDuty para fallos nocturnos

Canal #deployments-audit (auditoría):
  → Todos los eventos de todos los workflows
  → Mensajes con máximo detalle
  → Retención larga (compliance)

REGLA DE ORO:
  Si recibes una notificación y no requiere acción,
  esa notificación no debería existir.
```

---

## Patrón 7: Usar set_stats para comunicación entre nodos

```yaml
# Nodo 1: Run Tests → pasa resultados al siguiente nodo
- name: Publicar resultados de tests
  ansible.builtin.set_stats:
    data:
      test_summary:
        total:    "{{ total_tests }}"
        passed:   "{{ passed_tests }}"
        failed:   "{{ failed_tests }}"
        coverage: "{{ coverage_pct }}"
      quality_gate_passed: "{{ failed_tests | int == 0 and coverage_pct | float >= 80.0 }}"
      artifact_url: "https://registry.ejemplo.com/webapp:{{ release_tag }}"
    per_host: false
```

```yaml
# Nodo 2: Deploy → usa los resultados del nodo anterior
- name: Verificar quality gate antes de deploy
  ansible.builtin.assert:
    that:
      - quality_gate_passed | bool
    fail_msg: >
      Quality gate no superado.
      Tests fallados: {{ test_summary.failed }}.
      Cobertura: {{ test_summary.coverage }}% (mínimo: 80%).
    success_msg: >
      Quality gate OK.
      {{ test_summary.passed }} tests pasados,
      cobertura {{ test_summary.coverage }}%.
  tags: [always]
```

---

## Patrón 8: Workflow de validación pre-deploy (Check Mode)

```
Workflow: "Pre-Deploy Validation"
  Node 1: [CHECK] Configure App    (dry-run)
  Node 2: [CHECK] Deploy App       (dry-run)
  Node 3: Notify "Validación OK - listo para deploy real"

Workflow: "Full Deploy"
  Node 1: Sub-Workflow "Pre-Deploy Validation"
  Node 2 (success): Approval "Confirmar deploy tras validación"
  Node 3 (approved): [RUN] Configure App
  Node 4 (success):  [RUN] Deploy App
  Node 5 (always):   Notify resultado
```

---

# 4.17 Troubleshooting del Módulo 4

## Problema 1: Workflow se queda en estado "running" indefinidamente

**Síntoma:**
```
El Workflow Job lleva horas en estado "running" sin avanzar.
Ningún nodo parece estar ejecutándose.
```

**Diagnóstico:**
```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

# Ver el estado del workflow job
WF_JOB_ID=5
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_jobs/${WF_JOB_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Status:  {data[\"status\"]}')
print(f'Started: {data[\"started\"]}')
print(f'Elapsed: {data[\"elapsed\"]}s')
"

# Ver el estado de cada nodo del workflow
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_jobs/${WF_JOB_ID}/workflow_nodes/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for node in data['results']:
    job_info = ''
    if node.get('job'):
        job_info = f' → Job #{node[\"job\"]}'
    print(f'  Node: {node[\"id\"]:3} | {node.get(\"summary_fields\",{}).get(\"job_template\",{}).get(\"name\",\"Approval\"):30} | {node[\"do_not_run\"]} skip | {job_info}')
"
```

**Causas y soluciones:**

```
CAUSA 1: Nodo de aprobación esperando sin notificación
  El workflow está en un Approval Node pero nadie lo sabe.
  
  Diagnóstico:
    Jobs → Workflow Jobs → Tu Workflow → ver el grafo
    El nodo de aprobación estará en amarillo/pendiente
  
  Solución:
    Aprobar o rechazar manualmente desde la UI
    Añadir notificación "On Approval Pending" para evitarlo en el futuro

CAUSA 2: Job Template del nodo en estado "waiting" por capacidad
  El nodo lanzó un job pero está esperando capacidad en el Instance Group.
  
  Diagnóstico:
    Jobs → Jobs → ver si hay jobs en estado "waiting"
    Administration → Instance Groups → ver capacidad disponible
  
  Solución:
    Cancelar jobs bloqueados o añadir capacidad al Instance Group

CAUSA 3: Timeout del nodo de aprobación expiró pero no hay edge de failure
  El Approval Node expiró pero no tiene configurado un edge "failure".
  El workflow no sabe qué hacer y se queda bloqueado.
  
  Solución:
    Siempre configurar edge "failure" en los Approval Nodes.
    Cancelar el workflow actual manualmente.
    Editar el workflow para añadir el edge faltante.

CAUSA 4: Convergence: All esperando un nodo que nunca completará
  Un fan-in con Convergence: All está esperando un nodo que falló
  sin edge de failure configurado.
  
  Solución:
    Revisar todos los nodos con Convergence: All
    Asegurarse de que todos los predecesores tienen edges configurados
```

---

## Problema 2: Nodo de aprobación no aparece en la UI del aprobador

**Síntoma:**
```
El workflow está en un Approval Node pero el usuario del CAB
no ve ninguna aprobación pendiente en su UI de AWX.
```

**Diagnóstico:**
```bash
# Ver las aprobaciones pendientes
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_approvals/?status=pending" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Aprobaciones pendientes: {data[\"count\"]}')
for approval in data['results']:
    print(f'  ID: {approval[\"id\"]}')
    print(f'  Name: {approval[\"name\"]}')
    print(f'  Workflow: {approval.get(\"summary_fields\",{}).get(\"workflow_job\",{}).get(\"name\",\"N/A\")}')
"

# Ver los permisos del usuario aprobador
USERNAME="usuario_cab1"
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/users/?username=${USERNAME}" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    user = data['results'][0]
    print(f'User ID: {user[\"id\"]}')
    print(f'Is Superuser: {user[\"is_superuser\"]}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El usuario no tiene rol "Approve" en el Workflow Template
  
  Solución:
    Templates → App Delivery Pipeline → Access → Add
    Team: Change Advisory Board → Role: Approve
    
    Verificar que el usuario está en el equipo CAB:
    Teams → Change Advisory Board → Users

CAUSA 2: El usuario tiene rol "Approve" pero no "Read"
  Sin "Read" no puede ver el workflow ni el nodo de aprobación.
  
  Solución:
    Templates → App Delivery Pipeline → Access → Add
    Team: Change Advisory Board → Role: Read  (además de Approve)

CAUSA 3: La notificación de aprobación no se envió
  El usuario no recibió la notificación y no sabe que hay algo pendiente.
  
  Solución:
    Verificar que la notificación "On Approval Pending" está configurada.
    Revisar el historial de notificaciones:
    Notifications → (ver si hay errores en el envío)

CAUSA 4: El aprobador busca en el lugar incorrecto
  Las aprobaciones pendientes aparecen en:
    Jobs → Workflow Approvals  (menú lateral)
    O en: Jobs → Workflow Jobs → Tu Workflow → (nodo amarillo)
```

---

## Problema 3: Variables del Survey no llegan a los nodos del Workflow

**Síntoma:**
```
El Survey del Workflow tiene release_tag=v2.0.0 pero en los
playbooks de los nodos la variable tiene el valor por defecto.
```

**Diagnóstico:**
```bash
# Ver las variables del workflow job
WF_JOB_ID=5
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_jobs/${WF_JOB_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
import json as j
extra_vars = j.loads(data.get('extra_vars', '{}'))
print('Variables del Workflow Job:')
for k, v in extra_vars.items():
    print(f'  {k} = {v}')
"

# Ver las variables del job de un nodo específico
JOB_ID=10  # el job lanzado por el nodo
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/jobs/${JOB_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
extra_vars = json.loads(data.get('extra_vars', '{}'))
print('Variables del Job del nodo:')
for k, v in extra_vars.items():
    print(f'  {k} = {v}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El Job Template tiene "Ask on Launch" deshabilitado para Extra Vars
  Si el JT no tiene "Prompt on launch" para Extra Vars,
  puede ignorar las variables del Workflow.
  
  Solución:
    Templates → Tu JT → Edit
    Options: ✅ Prompt on Launch para Extra Variables
    
    O mejor: asegurarse de que el playbook usa default():
    release_tag: "{{ release_tag | default('v1.0.0') }}"

CAUSA 2: El JT tiene Extra Vars hardcoded que sobreescriben el Survey
  Si el JT tiene release_tag: v0.0.0 en sus Extra Vars,
  puede sobreescribir el valor del Survey del Workflow.
  
  Solución:
    Eliminar las Extra Vars hardcoded del JT
    O moverlas al Workflow Survey con valores por defecto

CAUSA 3: El playbook usa vars_files que sobreescriben las extra_vars
  Un vars_file cargado en el playbook puede tener la misma variable
  con un valor diferente.
  
  Solución:
    Revisar la precedencia de variables de Ansible.
    Los extra_vars tienen la mayor precedencia, pero solo si
    no hay un set_fact posterior que los sobreescriba.
    Usar: vars_files solo para variables que no vienen del Survey.
```

---

## Problema 4: Webhook de CI no lanza el Workflow

**Síntoma:**
```
GitHub Actions hace el POST a AWX pero recibe un error
HTTP 401, 403 o 404.
```

**Diagnóstico:**
```bash
# Probar el token manualmente
AWX_TOKEN="tu-token-aqui"
curl -s \
  -H "Authorization: Bearer ${AWX_TOKEN}" \
  "http://localhost:30080/api/v2/me/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'username' in data:
    print(f'Token válido para: {data[\"username\"]}')
    print(f'Is superuser: {data[\"is_superuser\"]}')
else:
    print('Token inválido o expirado')
    print(data)
"

# Probar el lanzamiento del workflow manualmente
WFT_ID=3
curl -sS -w "\nHTTP_CODE: %{http_code}\n" \
  -X POST \
  -H "Authorization: Bearer ${AWX_TOKEN}" \
  -H "Content-Type: application/json" \
  "http://localhost:30080/api/v2/workflow_job_templates/${WFT_ID}/launch/" \
  -d '{"extra_vars": {"release_tag": "v1.0.0", "environment": "dev", "target_group": "dev"}}'
```

**Causas y soluciones:**

```
HTTP 401 Unauthorized:
  → Token inválido, expirado o mal formateado
  Solución:
    Regenerar el token en AWX: User Tokens → Add
    Verificar que el header es: "Authorization: Bearer TOKEN"
    (no "Basic", no "Token", sino "Bearer")

HTTP 403 Forbidden:
  → Token válido pero sin permisos para lanzar el Workflow
  Solución:
    El usuario del token necesita Execute en el Workflow Template:
    Templates → App Delivery Pipeline → Access → Add
    User: ci-user → Role: Execute

HTTP 404 Not Found:
  → El ID del Workflow Template es incorrecto
  Solución:
    Verificar el ID:
    curl -s -u admin:pass http://awx/api/v2/workflow_job_templates/
    Actualizar el secret AWX_WFT_ID en GitHub/GitLab

HTTP 400 Bad Request:
  → El body del POST tiene errores (variables mal formateadas)
  Solución:
    Verificar que el JSON es válido:
    echo '{"extra_vars": {"key": "value"}}' | python3 -m json.tool
    Verificar que todas las variables requeridas del Survey están presentes

HTTP 405 Method Not Allowed:
  → Estás haciendo GET en lugar de POST, o la URL es incorrecta
  Solución:
    Verificar que usas -X POST
    La URL correcta es: /api/v2/workflow_job_templates/ID/launch/
    (con la barra final)
```

---

## Problema 5: Rollback no se ejecuta cuando falla el deploy

**Síntoma:**
```
El nodo "Deploy to Prod" falla pero el nodo "Rollback App"
no se ejecuta automáticamente.
```

**Diagnóstico:**
```bash
# Ver el grafo del workflow y sus edges
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_job_templates/${WFT_ID}/workflow_nodes/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Nodos y sus edges:')
for node in data['results']:
    name = node.get('summary_fields',{}).get('job_template',{}).get('name','Approval/Other')
    print(f'  Node {node[\"id\"]}: {name}')
    
    # Ver edges de success
    for edge in node.get('success_nodes', []):
        print(f'    → success → Node {edge}')
    
    # Ver edges de failure
    for edge in node.get('failure_nodes', []):
        print(f'    → failure → Node {edge}')
    
    # Ver edges de always
    for edge in node.get('always_nodes', []):
        print(f'    → always  → Node {edge}')
"
```

**Causas y soluciones:**

```
CAUSA 1: El edge "failure" no está configurado en el nodo "Deploy to Prod"
  
  Diagnóstico:
    En el Visualizer, verificar que hay una flecha ROJA
    desde "Deploy to Prod" hacia "Rollback App"
  
  Solución:
    Templates → App Delivery Pipeline → Visualizer
    Click en el nodo "Deploy to Prod"
    Añadir edge: On Failure → Rollback App

CAUSA 2: El Job Template "Rollback App" tiene un error que le impide ejecutarse
  El nodo de rollback está configurado pero falla al arrancar.
  
  Diagnóstico:
    Jobs → Jobs → buscar jobs de "WF - Rollback App"
    Ver si hay errores de configuración (inventario, credencial, EE)
  
  Solución:
    Probar el Job Template de rollback de forma independiente
    Corregir los errores antes de confiar en él en el workflow

CAUSA 3: El playbook de deploy usa ignore_errors: true
  Si el playbook de deploy ignora errores, AWX lo considera exitoso
  aunque haya habido fallos reales.
  
  Solución:
    Revisar el playbook de deploy.
    Usar ignore_errors: true solo donde sea absolutamente necesario.
    Usar failed_when para controlar cuándo se considera un fallo real.

CAUSA 4: El rollback necesita variables que no tiene
  El playbook de rollback necesita "previous_version" pero
  esa variable no está en el Survey del Workflow.
  
  Solución:
    Añadir "previous_version" al Survey del Workflow.
    O usar set_stats en el nodo de deploy para pasar la versión anterior.
```

---

## Problema 6: Notificaciones Slack no se envían

**Síntoma:**
```
El workflow completa (éxito o fallo) pero no llega ningún
mensaje al canal de Slack.
```

**Diagnóstico:**
```bash
# Ver el historial de notificaciones
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/notifications/?order_by=-id&page_size=5" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for notif in data['results']:
    print(f'ID: {notif[\"id\"]} | Status: {notif[\"status\"]} | Type: {notif[\"notification_type\"]}')
    if notif['status'] == 'failed':
        print(f'  Error: {notif.get(\"error\", \"N/A\")}')
        print(f'  Body:  {str(notif.get(\"body\", \"\"))[:200]}')
"

# Probar la notificación manualmente
NOTIF_TEMPLATE_ID=1
curl -s -u "${AWX_AUTH}" \
  -X POST \
  "${AWX_URL}/api/v2/notification_templates/${NOTIF_TEMPLATE_ID}/test/" \
  | python3 -m json.tool
```

**Causas y soluciones:**

```
CAUSA 1: Webhook URL de Slack inválido o expirado
  Los webhooks de Slack pueden expirar o ser revocados.
  
  Solución:
    Ir a api.slack.com → tu app → Incoming Webhooks
    Verificar que el webhook está activo
    Regenerar si es necesario y actualizar en AWX

CAUSA 2: La notificación no está adjunta al Workflow Template
  La notificación existe pero no está asignada al template correcto.
  
  Solución:
    Templates → App Delivery Pipeline → Notifications
    Verificar que "Slack - Deployments" aparece en On Success y On Failure

CAUSA 3: AWX no tiene salida a internet para llamar a Slack
  El pod de AWX está en una red sin acceso a hooks.slack.com.
  
  Diagnóstico:
    kubectl exec -n awx deployment/awx-task -c awx-task -- \
      curl -s https://hooks.slack.com --max-time 5 -o /dev/null -w "%{http_code}"
    # Debe devolver 200 o 405
  
  Solución:
    Configurar proxy de salida o abrir el firewall para hooks.slack.com

CAUSA 4: Mensaje personalizado con sintaxis inválida
  Si el mensaje personalizado tiene un error de template Jinja2,
  la notificación falla silenciosamente.
  
  Solución:
    Simplificar el mensaje y añadir complejidad gradualmente.
    Verificar que las variables usadas existen en el contexto.
    Usar | default('N/A') para variables opcionales.
```

---

## Referencia rápida: estados de un Workflow Job

```
pending     → Workflow creado, esperando recursos
running     → Al menos un nodo está ejecutándose
successful  → Todos los nodos del camino ejecutado completaron OK
failed      → Algún nodo crítico falló sin recuperación
error       → Error interno de AWX (no del playbook)
canceled    → Cancelado manualmente
```

## Referencia rápida: estados de un Approval Node

```
pending     → Esperando que alguien apruebe o rechace
approved    → Aprobado → continúa por edge "success"
denied      → Rechazado → continúa por edge "failure"
timed_out   → Expiró el timeout → continúa por edge "failure"
canceled    → El workflow fue cancelado mientras esperaba
```

---

# 4.18 Resumen y Checklist del Módulo 4

## Lo que has aprendido

```
✅ Workflows como representación ejecutable de procesos de negocio
   → Cada nodo es un paso del proceso
   → Cada edge es una condición de transición
   → El grafo completo es el proceso auditado

✅ Tipos de nodos: Job Template, Workflow, Approval, Project Sync
   → Cada tipo tiene su caso de uso específico

✅ Edges condicionales: success, failure, always
   → success: el camino feliz
   → failure: manejo de errores y rollback
   → always:  limpieza y notificaciones

✅ Fan-out (paralelismo) y Fan-in (convergencia)
   → Convergence: All → espera a todos los predecesores
   → Convergence: Any → se ejecuta con el primero que complete

✅ Nodos de Aprobación como mecanismo de gobernanza
   → Nombre y descripción claros para el aprobador
   → Timeout razonable con edge de failure configurado
   → Permisos específicos: solo el equipo correcto puede aprobar
   → Auditoría completa: quién, cuándo, comentario

✅ Variables en Workflows
   → Survey del Workflow propaga variables a todos los nodos
   → set_stats para pasar datos entre nodos
   → Precedencia: Survey > Extra Vars del template > Inventario

✅ Notificaciones configuradas por evento y canal
   → Slack para visibilidad del equipo
   → Email para escaladas y auditoría
   → Webhook para integración con ITSM y observabilidad
   → PagerDuty para alertas críticas nocturnas

✅ Trigger desde CI/CD
   → GitHub Actions: POST a /api/v2/workflow_job_templates/ID/launch/
   → GitLab CI: mismo endpoint via python requests
   → Esperar resultado con polling del estado
   → Token con permisos mínimos (solo Execute en el WFT)

✅ Patrones avanzados
   → Workflows anidados para reutilización
   → Workflow de rollback independiente
   → Pipeline de promoción entre entornos
   → Check Mode como gate de validación
   → Notificaciones inteligentes sin ruido
```

## Checklist de verificación

```bash
AWX_URL="http://localhost:30080"
AWX_AUTH="admin:TuPasswordSegura123!"

echo "=== 1. Workflow Template existe ==="
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_job_templates/?name=App+Delivery+Pipeline" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] > 0:
    wft = data['results'][0]
    print(f'✅ Workflow: {wft[\"name\"]} (ID: {wft[\"id\"]})')
    print(f'   Survey: {\"habilitado\" if wft[\"survey_enabled\"] else \"deshabilitado\"}')
else:
    print('❌ Workflow Template no encontrado')
"

echo ""
echo "=== 2. Nodos del Workflow ==="
WFT_ID=3  # ajusta
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_job_templates/${WFT_ID}/workflow_nodes/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total nodos: {data[\"count\"]}')
for node in data['results']:
    name = node.get('summary_fields',{}).get('job_template',{}).get('name','Approval/Other')
    success = len(node.get('success_nodes', []))
    failure = len(node.get('failure_nodes', []))
    always  = len(node.get('always_nodes',  []))
    print(f'  Node {node[\"id\"]}: {name}')
    print(f'    Edges → success:{success} failure:{failure} always:{always}')
"

echo ""
echo "=== 3. Notificaciones configuradas ==="
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/notification_templates/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total notification templates: {data[\"count\"]}')
for nt in data['results']:
    print(f'  ✅ {nt[\"name\"]} ({nt[\"notification_type\"]})')
"

echo ""
echo "=== 4. Últimos Workflow Jobs ==="
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_jobs/?order_by=-id&page_size=5" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for wf in data['results']:
    icon = '✅' if wf['status'] == 'successful' else '❌' if wf['status'] == 'failed' else '⏳'
    elapsed = f'{wf[\"elapsed\"]:.0f}s' if wf.get('elapsed') else 'N/A'
    print(f'{icon} WF#{wf[\"id\"]}: {wf[\"name\"]} → {wf[\"status\"]} ({elapsed})')
"

echo ""
echo "=== 5. Aprobaciones pendientes ==="
curl -s -u "${AWX_AUTH}" \
  "${AWX_URL}/api/v2/workflow_approvals/?status=pending" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data['count'] == 0:
    print('✅ No hay aprobaciones pendientes')
else:
    print(f'⚠️  {data[\"count\"]} aprobación(es) pendiente(s):')
    for approval in data['results']:
        print(f'  ID:{approval[\"id\"]} - {approval[\"name\"]}')
"

echo ""
echo "=== 6. Token de CI válido ==="
# Sustituir con el token real de CI
CI_TOKEN="tu-token-de-ci"
curl -s \
  -H "Authorization: Bearer ${CI_TOKEN}" \
  "${AWX_URL}/api/v2/me/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'username' in data:
    print(f'✅ Token válido para: {data[\"username\"]}')
else:
    print('❌ Token inválido o expirado')
" 2>/dev/null || echo "❌ No se pudo verificar el token"
```

