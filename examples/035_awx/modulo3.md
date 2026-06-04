# ▶️ MÓDULO 3 — Job Templates y Surveys
### Curso Ansible AWX · De cero a producción · En español

---

## 🗺️ Índice del Módulo

| Sección | Contenido |
|---------|-----------|
| 3.1 | Modelo mental: de playbook a self-service |
| 3.2 | Job Templates vs Workflow Templates |
| 3.3 | Anatomía de un Job Template |
| 3.4 | Extra Vars, Prompts y Surveys |
| 3.5 | Limits, Tags y Skip-tags |
| 3.6 | Forks, Verbosity y Fact Caching |
| 3.7 | Instance Groups y Execution Environments |
| 3.8 | LAB — Job Template para deploy de web app |
| 3.9 | LAB — Survey con inputs validados |
| 3.10 | LAB — Tags, skip-tags y limit para ejecuciones quirúrgicas |
| 3.11 | LAB — Execution Environment personalizado con colecciones fijadas |
| 3.12 | LAB — Job Template avanzado con todas las opciones |
| 3.13 | Patrones avanzados y buenas prácticas |
| 3.14 | Troubleshooting del módulo |
| 3.15 | Resumen y checklist |

**Duración estimada:** 60-75 minutos
**Tipo:** Lab intensivo
**Prerrequisitos:** Módulos 1 y 2 completados, inventario y credenciales configurados

---

# 3.1 Modelo mental: de playbook a self-service

Sin AWX, ejecutar un playbook requiere acceso SSH al servidor de control, conocer la ruta del playbook, saber qué variables pasar y tener las credenciales configuradas localmente. Eso funciona para un sysadmin, pero no escala a un equipo.

Con Job Templates, cualquier persona autorizada puede lanzar automatización compleja desde un botón, sin saber Ansible, sin ver credenciales, con inputs validados y con auditoría completa.

```
SIN JOB TEMPLATE (CLI directo):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Developer → SSH al servidor de control
           → ansible-playbook deploy.yml \
               -i inventory/prod \
               -e "version=v1.4.2 env=prod" \
               --vault-id prod@~/.vault_pass \
               --limit web_servers \
               --tags deploy
  
  Problemas:
  ❌ Necesita acceso SSH al servidor de control
  ❌ Necesita conocer la sintaxis de Ansible
  ❌ Necesita tener las credenciales localmente
  ❌ Sin auditoría de quién ejecutó qué
  ❌ Sin validación de inputs
  ❌ Sin notificaciones automáticas

CON JOB TEMPLATE (AWX):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Developer → UI AWX → Rellena Survey (versión, entorno)
           → Launch → Ve logs en tiempo real → Recibe notificación
  
  Beneficios:
  ✅ Solo necesita un navegador
  ✅ No necesita saber Ansible
  ✅ Nunca ve las credenciales
  ✅ Auditoría completa (quién, cuándo, qué inputs)
  ✅ Inputs validados por tipo y regex
  ✅ Notificaciones automáticas en Slack/email
```

---

# 3.2 Job Templates vs Workflow Templates

Antes de profundizar en Job Templates, clarifica la diferencia con Workflow Templates para saber cuándo usar cada uno.

```
JOB TEMPLATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Ejecuta UN playbook específico
  
  Analogía: una función en programación
  
  Ejemplo:
    "Despliega la versión X de la app web en el grupo Y"
    "Configura Nginx en los servidores del grupo web"
    "Ejecuta el backup de PostgreSQL"
  
  Cuándo usar:
  → Tarea atómica y bien definida
  → Paso individual en un proceso mayor
  → Automatización que se ejecuta sola

WORKFLOW TEMPLATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Encadena MÚLTIPLES Job Templates con lógica condicional
  
  Analogía: un pipeline o proceso de negocio
  
  Ejemplo:
    Provision → Configure → Test → Approve → Deploy → Notify
    
  Cuándo usar:
  → Proceso de varios pasos con dependencias
  → Necesitas lógica success/failure/always
  → Requieres aprobación humana entre pasos
  → Fan-out (pasos en paralelo) o fan-in (convergencia)
```

**Regla de oro:** Construye Job Templates sólidos primero. Los Workflow Templates los componen. Un buen Job Template es reutilizable en múltiples workflows.

---

# 3.3 Anatomía de un Job Template

Cada campo de un Job Template tiene un propósito específico. Conocerlos todos te permite diseñar templates precisos y seguros.

## Campos principales

```
┌─────────────────────────────────────────────────────────────────┐
│                      JOB TEMPLATE                                │
├─────────────────────────────────────────────────────────────────┤
│ Name          │ Nombre descriptivo (incluye app + acción + env) │
│ Description   │ Qué hace, cuándo usarlo, quién lo mantiene      │
│ Job Type      │ Run / Check / Scan                              │
├─────────────────────────────────────────────────────────────────┤
│ CONTENIDO                                                        │
│ Inventory     │ Dónde ejecutar (con prompt opcional)            │
│ Project       │ Qué repo Git contiene el playbook               │
│ Playbook      │ Ruta relativa al playbook dentro del repo       │
│ EE            │ Qué imagen de contenedor usar                   │
├─────────────────────────────────────────────────────────────────┤
│ AUTENTICACIÓN                                                    │
│ Credentials   │ SSH, Vault, Cloud (múltiples permitidas)        │
├─────────────────────────────────────────────────────────────────┤
│ EJECUCIÓN                                                        │
│ Forks         │ Hosts en paralelo (default: 0 = usar config)    │
│ Limit         │ Patrón de hosts (con prompt opcional)           │
│ Verbosity     │ 0=Normal, 1=Verbose, 2=More, 3=Debug, 4=Conn   │
│ Timeout       │ Segundos máximos (0 = sin límite)               │
│ Job Slicing   │ Dividir el job en N slices paralelos            │
├─────────────────────────────────────────────────────────────────┤
│ OPCIONES                                                         │
│ Privilege Escalation │ Activar become (sudo)                    │
│ Provisioning Callbacks │ Token para que hosts llamen a AWX      │
│ Enable Webhook │ Recibir triggers externos                      │
│ Concurrent Jobs │ Permitir ejecuciones simultáneas              │
│ Fact Cache    │ Usar/guardar facts en Redis                     │
├─────────────────────────────────────────────────────────────────┤
│ VARIABLES                                                        │
│ Extra Vars    │ Variables adicionales (YAML o JSON)             │
│ Survey        │ Formulario de inputs validados                  │
└─────────────────────────────────────────────────────────────────┘
```

## Job Types explicados

```yaml
# Job Type: Run
# El más común. Ejecuta el playbook normalmente.
# Ansible aplica cambios reales a los hosts.
job_type: run

# Job Type: Check
# Dry-run. Ansible simula los cambios sin aplicarlos.
# Equivale a: ansible-playbook --check
# Útil para: validar antes de ejecutar en prod, CI/CD gates
job_type: check

# Job Type: Scan
# Recopila facts y los almacena en AWX.
# Usado para inventario de configuración.
# Requiere playbooks especiales de scan.
job_type: scan
```

## Precedencia de variables en AWX

Este es uno de los conceptos más importantes y fuente de confusión frecuente:

```
MENOR PRECEDENCIA (más fácil de sobreescribir)
     │
     ▼
1.  Variables del inventario (group_vars, host_vars)
2.  Variables del proyecto (vars/ en el repo)
3.  Extra Vars del Job Template (hardcoded en el template)
4.  Survey variables (introducidas por el usuario al lanzar)
5.  Extra Vars del launch (via API o prompt)
     │
     ▼
MAYOR PRECEDENCIA (sobreescribe todo lo anterior)
```

> ⚠️ **Importante:** Las variables del Survey **sobreescriben** las Extra Vars del template. Diseña tus templates teniendo esto en cuenta.

---

# 3.4 Extra Vars, Prompts y Surveys

Tres mecanismos para pasar variables a un Job Template. Cada uno tiene su caso de uso.

## Extra Vars (variables hardcoded en el template)

```yaml
# En el campo "Extra Variables" del Job Template
# Formato YAML o JSON

# Ejemplo: valores por defecto que raramente cambian
---
app_name: webapp
deploy_user: deploy
health_check_retries: 5
health_check_delay: 10
rollback_enabled: true
notification_channel: "#deployments"
```

**Cuándo usar Extra Vars:**
- Valores por defecto que aplican siempre
- Configuración técnica que los operadores no deben cambiar
- Parámetros de infraestructura fijos por entorno

## Prompts on Launch

Permiten que el operador seleccione o modifique ciertos campos al lanzar el job.

```
Campos que se pueden marcar como "Prompt on launch":
  ✅ Inventory      → el operador elige el inventario
  ✅ Credentials    → el operador elige las credenciales
  ✅ Limit          → el operador especifica el patrón de hosts
  ✅ Job Tags       → el operador elige qué tags ejecutar
  ✅ Skip Tags      → el operador elige qué tags saltar
  ✅ Job Type       → Run o Check
  ✅ Verbosity      → nivel de detalle de logs
  ✅ Extra Vars     → variables adicionales libres
  ✅ SCM Branch     → rama del proyecto (si Allow Branch Override)
```

**Cuándo usar Prompts:**
- Limit: para que el operador elija el entorno o subconjunto de hosts
- Credentials: cuando diferentes equipos usan diferentes credenciales
- Job Tags: para ejecuciones quirúrgicas sin crear múltiples templates

## Surveys: el mecanismo más seguro

Un Survey es un formulario con campos tipados y validados que aparece antes de lanzar el job. Es la forma más segura de recoger inputs de operadores.

```
TIPOS DE CAMPOS EN UN SURVEY:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Text
  → Texto libre con longitud mínima/máxima
  → Ejemplo: nombre del ticket, rama de Git

Textarea
  → Texto multilínea
  → Ejemplo: mensaje de release notes, configuración YAML

Password
  → Campo enmascarado, no aparece en logs
  → Ejemplo: token temporal, PIN de aprobación

Integer
  → Número entero con rango min/max
  → Ejemplo: número de réplicas, timeout en segundos

Float
  → Número decimal
  → Ejemplo: porcentaje de canary, factor de escala

Multiple Choice (single select)
  → Lista de opciones, el usuario elige una
  → Ejemplo: entorno (dev/stage/prod), región AWS

Multiple Choice (multiple select)
  → Lista de opciones, el usuario elige varias
  → Ejemplo: componentes a desplegar (web, api, db)
```

**Ventajas de Surveys sobre Extra Vars libres:**

```
Extra Vars libres:
  environment: ../../../../etc/passwd   ← posible
  version: ; rm -rf /                   ← posible (si no hay sanitización)
  forks: 9999999                        ← posible

Survey con validación:
  environment: Multiple Choice → solo dev/stage/prod
  version: Text con regex ^v\d+\.\d+\.\d+$ → solo formato semver
  forks: Integer min=1 max=50 → rango controlado
```

---

# 3.5 Limits, Tags y Skip-tags

Estos tres mecanismos te dan control quirúrgico sobre qué se ejecuta y dónde.

## Limit: controlar el alcance de hosts

```bash
# Patrones de Limit más útiles:

# Por grupo
dev                    # todos los hosts del grupo dev
prod                   # todos los hosts del grupo prod

# Por host específico
prod-web1              # solo este host

# Múltiples grupos (OR)
dev,stage              # hosts de dev O stage

# Intersección (AND)
prod:&web_servers      # hosts que están en prod Y en web_servers

# Exclusión (NOT)
prod:!prod-db1         # hosts de prod EXCEPTO prod-db1

# Wildcard
web*                   # hosts cuyo nombre empieza por "web"
*db*                   # hosts cuyo nombre contiene "db"

# Regex (prefijo ~)
~prod-web-[0-9]+       # hosts de prod-web seguido de número

# Combinaciones complejas
prod:&web_servers:!prod-web3   # prod + web_servers - prod-web3
```

## Tags: ejecutar solo partes del playbook

Los tags en Ansible permiten marcar tareas y ejecutar solo las marcadas.

```yaml
# Ejemplo de playbook con tags bien estructurados
---
- name: Deploy completo de la aplicación
  hosts: "{{ target_group }}"
  become: true

  tasks:
    # ── BLOQUE: Paquetes del sistema ──────────────────────────
    - name: Actualizar cache de paquetes
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      tags:
        - packages
        - system

    - name: Instalar dependencias del sistema
      ansible.builtin.package:
        name: "{{ item }}"
        state: present
      loop: "{{ system_packages }}"
      tags:
        - packages
        - install

    # ── BLOQUE: Configuración ─────────────────────────────────
    - name: Crear directorios de la aplicación
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: "{{ app_user }}"
        mode: '0755'
      loop:
        - /opt/webapp
        - /opt/webapp/config
        - /opt/webapp/logs
      tags:
        - config
        - directories

    - name: Desplegar fichero de configuración
      ansible.builtin.template:
        src: app.conf.j2
        dest: /opt/webapp/config/app.conf
        owner: "{{ app_user }}"
        mode: '0640'
      notify: Restart webapp
      tags:
        - config
        - app_config

    - name: Desplegar configuración de Nginx
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/sites-available/webapp
        mode: '0644'
      notify: Reload nginx
      tags:
        - config
        - nginx_config

    # ── BLOQUE: Deploy ────────────────────────────────────────
    - name: Descargar artefacto de la aplicación
      ansible.builtin.get_url:
        url: "{{ artifact_url }}/webapp-{{ app_version }}.tar.gz"
        dest: /tmp/webapp-{{ app_version }}.tar.gz
        checksum: "sha256:{{ artifact_checksum }}"
      tags:
        - deploy
        - download

    - name: Descomprimir artefacto
      ansible.builtin.unarchive:
        src: /tmp/webapp-{{ app_version }}.tar.gz
        dest: /opt/webapp
        remote_src: true
        owner: "{{ app_user }}"
      tags:
        - deploy
        - extract

    - name: Actualizar enlace simbólico a versión actual
      ansible.builtin.file:
        src: /opt/webapp/releases/{{ app_version }}
        dest: /opt/webapp/current
        state: link
      notify: Restart webapp
      tags:
        - deploy
        - symlink

    # ── BLOQUE: Verificación ──────────────────────────────────
    - name: Esperar a que la aplicación responda
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      register: health_check
      retries: 5
      delay: 10
      until: health_check.status == 200
      tags:
        - verify
        - health_check

    - name: Verificar versión desplegada
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/version"
        return_content: true
      register: version_check
      tags:
        - verify
        - version_check

    - name: Mostrar resultado de verificación
      ansible.builtin.debug:
        msg: "Versión desplegada: {{ version_check.content }}"
      tags:
        - verify
        - always

  handlers:
    - name: Restart webapp
      ansible.builtin.service:
        name: webapp
        state: restarted

    - name: Reload nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

## Combinaciones de tags más útiles en AWX

```bash
# Escenario 1: Solo actualizar configuración (sin reinstalar paquetes)
Job Tags:   config
Skip Tags:  packages, deploy

# Escenario 2: Solo desplegar nueva versión (sin reconfigurar)
Job Tags:   deploy
Skip Tags:  packages, config

# Escenario 3: Deploy completo pero sin verificación (urgente)
Skip Tags:  verify

# Escenario 4: Solo verificar el estado actual
Job Tags:   verify

# Escenario 5: Reinstalar paquetes y reconfigurar (sin nuevo deploy)
Job Tags:   packages,config
Skip Tags:  deploy,verify

# Escenario 6: Deploy completo (sin tags = todo)
Job Tags:   (vacío)
Skip Tags:  (vacío)
```

---

# 3.6 Forks, Verbosity y Fact Caching

Estos parámetros controlan el rendimiento y la observabilidad de tus jobs.

## Forks: paralelismo por job

```
Forks = número de hosts que Ansible gestiona simultáneamente

Ejemplo con 100 hosts y forks=10:
  Ronda 1: hosts 1-10  (en paralelo)
  Ronda 2: hosts 11-20 (en paralelo)
  ...
  Ronda 10: hosts 91-100

Ejemplo con 100 hosts y forks=50:
  Ronda 1: hosts 1-50  (en paralelo)
  Ronda 2: hosts 51-100

Ejemplo con 100 hosts y forks=100:
  Ronda 1: todos los hosts (en paralelo)
  → Más rápido pero más carga en el execution node
```

**Guía de configuración de forks:**

```
Entorno de desarrollo:
  Forks: 5-10
  Motivo: pocos hosts, no necesitas velocidad máxima

Entorno de staging:
  Forks: 10-20
  Motivo: balance entre velocidad y estabilidad

Entorno de producción (servidores estables):
  Forks: 20-50
  Motivo: maximizar velocidad con red estable

Entorno de producción (cloud con latencia variable):
  Forks: 10-25
  Motivo: evitar timeouts SSH por saturación

Rolling updates (serial):
  Forks: 5-10 + serial: 1 o serial: 10%
  Motivo: actualizar de forma gradual sin downtime
```

**Configurar serial en el playbook para rolling updates:**

```yaml
# Rolling update: actualizar de 1 en 1
- name: Rolling update de servidores web
  hosts: web_servers
  become: true
  serial: 1          # de 1 en 1 (más seguro)
  # serial: 2        # de 2 en 2
  # serial: "10%"    # 10% del total a la vez
  # serial: [1, 5, 10%]  # primero 1, luego 5, luego 10%

  tasks:
    - name: Sacar host del load balancer
      # ...
    - name: Actualizar aplicación
      # ...
    - name: Verificar health check
      # ...
    - name: Volver a añadir al load balancer
      # ...
```

## Verbosity: niveles de detalle en los logs

```
Nivel 0 — Normal (default)
  Muestra: plays, tasks, resultados (ok/changed/failed/skipped)
  Uso: ejecuciones rutinarias de producción
  Ejemplo output:
    PLAY [Deploy Web Application] ****
    TASK [Instalar Nginx] ****
    ok: [prod-web1]
    changed: [prod-web2]

Nivel 1 — Verbose
  Muestra: nivel 0 + variables de task y detalles de módulo
  Uso: troubleshooting inicial
  Ejemplo output:
    ok: [prod-web1] => {"changed": false, "msg": "nginx already installed"}

Nivel 2 — More Verbose
  Muestra: nivel 1 + variables de host y detalles de conexión
  Uso: problemas de variables o inventario

Nivel 3 — Debug
  Muestra: nivel 2 + información de debug completa
  Uso: problemas complejos de lógica en playbooks

Nivel 4 — Connection Debug
  Muestra: nivel 3 + detalles de conexión SSH/WinRM
  Uso: problemas de conectividad o autenticación
  ⚠️ Puede exponer información sensible en los logs
```

> 💡 **Buena práctica:** Configura verbosity=0 o 1 en templates de producción. Sube a 2-3 solo cuando investigas un problema específico. Nunca uses 4 en producción de forma permanente.

## Fact Caching: acelerar ejecuciones repetidas

Sin fact caching, cada job ejecuta `gather_facts` en todos los hosts al inicio. Con 100 hosts, eso puede tardar 30-60 segundos solo en recopilar facts.

```
SIN FACT CACHE:
  Job 1: gather_facts (30s) → tasks (2min) → total: 2min 30s
  Job 2: gather_facts (30s) → tasks (2min) → total: 2min 30s
  Job 3: gather_facts (30s) → tasks (2min) → total: 2min 30s

CON FACT CACHE (Redis, TTL 24h):
  Job 1: gather_facts (30s) → tasks (2min) → guarda en Redis
  Job 2: lee de Redis (2s)  → tasks (2min) → total: 2min 2s  ✅
  Job 3: lee de Redis (2s)  → tasks (2min) → total: 2min 2s  ✅
```

**Configurar fact caching en ansible.cfg del proyecto:**

```ini
# ansible.cfg en la raíz de tu repo Git
[defaults]
# Activar Redis como backend de fact cache
fact_caching = redis

# Conexión a Redis (ajusta host/puerto/contraseña)
fact_caching_connection = redis://redis.ejemplo.com:6379/0

# TTL en segundos (86400 = 24 horas)
fact_caching_timeout = 86400

# Con autenticación y TLS:
# fact_caching_connection = rediss://:password@redis.ejemplo.com:6380/0
```

**Uso en playbooks con fact cache:**

```yaml
# Playbook 1: recoge y cachea facts
- name: Recopilar y cachear facts del sistema
  hosts: all
  gather_facts: true    # ← recoge y guarda en Redis
  tasks:
    - name: Mostrar OS
      ansible.builtin.debug:
        msg: "{{ ansible_distribution }} {{ ansible_distribution_version }}"

---
# Playbook 2: usa facts cacheados (más rápido)
- name: Deploy usando facts del cache
  hosts: all
  gather_facts: false   # ← usa el cache, no vuelve a recopilar
  tasks:
    - name: Configurar según OS (usando fact cacheado)
      ansible.builtin.template:
        src: "app-{{ ansible_distribution | lower }}.conf.j2"
        dest: /etc/app/app.conf
      # ansible_distribution viene del cache de Redis

    - name: Ajustar configuración según RAM disponible
      ansible.builtin.lineinfile:
        path: /etc/app/app.conf
        regexp: '^max_memory='
        line: "max_memory={{ (ansible_memtotal_mb * 0.7) | int }}M"
      # ansible_memtotal_mb también viene del cache
```

---

# 3.7 Instance Groups y Execution Environments

## Instance Groups: enrutar jobs al lugar correcto

Un Instance Group es un pool lógico de nodos de ejecución. Permiten:

```
CASO DE USO 1: Aislamiento por entorno
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ig-dev   → jobs de desarrollo (capacidad compartida)
  ig-stage → jobs de staging    (capacidad dedicada)
  ig-prod  → jobs de producción (capacidad dedicada, hardened)

CASO DE USO 2: Aislamiento por red
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ig-datacenter-madrid  → ejecuta jobs cerca de hosts en Madrid
  ig-datacenter-paris   → ejecuta jobs cerca de hosts en París
  ig-dmz                → execution node en DMZ para hosts sin VPN

CASO DE USO 3: Aislamiento por tipo de carga
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ig-heavy  → jobs largos y pesados (backups, migraciones)
  ig-light  → jobs cortos y frecuentes (health checks, configs)
```

## Execution Environments: el contenedor de ejecución

Un EE es una imagen Docker/OCI que contiene todo lo necesario para ejecutar playbooks:

```
Execution Environment
├── Base OS (UBI8/UBI9 de Red Hat, o similar)
├── Python (versión específica)
├── ansible-core (versión específica)
├── ansible-runner (para comunicación con AWX)
├── Collections de Ansible
│   ├── community.general 9.3.0
│   ├── ansible.posix 1.5.4
│   ├── community.mysql 3.8.0
│   └── amazon.aws 8.0.0
├── Dependencias Python
│   ├── boto3 1.34.x
│   ├── botocore 1.34.x
│   └── netmiko 4.3.x
└── Herramientas del sistema
    ├── git
    ├── rsync
    └── jq
```

**EEs disponibles por defecto en AWX:**

```
awx-ee (default):
  → ansible-core reciente
  → Colecciones básicas incluidas
  → Ideal para: playbooks estándar sin dependencias especiales

minimal:
  → Solo ansible-core, sin colecciones extra
  → Ideal para: playbooks que solo usan módulos built-in

custom (los que tú construyes):
  → Exactamente lo que necesitas, nada más
  → Ideal para: producción con dependencias específicas
```

---

# 3.8 LAB — Job Template para deploy de web app

*Construimos el Job Template base que usaremos y mejoraremos en los labs siguientes.*

## Paso 1 — Preparar el playbook en el repo

```yaml
# playbooks/deploy_web.yml
---
- name: Deploy Web Application
  hosts: "{{ target_group | default('dev') }}"
  become: true

  vars:
    app_version: "{{ app_version | default('v1.0.0') }}"
    app_env: "{{ environment | default('dev') }}"
    app_user: webapp
    app_port: "{{ app_port | default(8080) }}"
    app_dir: /opt/webapp
    change_ticket: "{{ change_ticket | default('N/A') }}"

  pre_tasks:
    - name: Mostrar información del deploy
      ansible.builtin.debug:
        msg:
          - "=== INICIO DE DEPLOY ==="
          - "Versión:  {{ app_version }}"
          - "Entorno:  {{ app_env }}"
          - "Hosts:    {{ ansible_play_hosts | join(', ') }}"
          - "Ticket:   {{ change_ticket }}"
          - "Fecha:    {{ ansible_date_time.iso8601 }}"
      tags: [always]

  tasks:
    # ── Paquetes ──────────────────────────────────────────────
    - name: Instalar dependencias del sistema
      ansible.builtin.package:
        name:
          - nginx
          - curl
          - jq
        state: present
      tags: [packages, install]

    # ── Usuarios y directorios ────────────────────────────────
    - name: Crear usuario de la aplicación
      ansible.builtin.user:
        name: "{{ app_user }}"
        system: true
        shell: /sbin/nologin
        create_home: false
      tags: [config, users]

    - name: Crear estructura de directorios
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: "{{ app_user }}"
        group: "{{ app_user }}"
        mode: '0755'
      loop:
        - "{{ app_dir }}"
        - "{{ app_dir }}/releases"
        - "{{ app_dir }}/shared"
        - "{{ app_dir }}/shared/config"
        - "{{ app_dir }}/shared/logs"
      tags: [config, directories]

    # ── Configuración ─────────────────────────────────────────
    - name: Desplegar configuración de la aplicación
      ansible.builtin.template:
        src: app.conf.j2
        dest: "{{ app_dir }}/shared/config/app.conf"
        owner: "{{ app_user }}"
        mode: '0640'
      notify: Restart webapp
      tags: [config, app_config]

    - name: Desplegar configuración de Nginx
      ansible.builtin.template:
        src: nginx_webapp.conf.j2
        dest: /etc/nginx/sites-available/webapp
        mode: '0644'
      notify: Reload nginx
      tags: [config, nginx_config]

    - name: Habilitar sitio en Nginx
      ansible.builtin.file:
        src: /etc/nginx/sites-available/webapp
        dest: /etc/nginx/sites-enabled/webapp
        state: link
      notify: Reload nginx
      tags: [config, nginx_config]

    # ── Deploy ────────────────────────────────────────────────
    - name: Crear directorio para esta release
      ansible.builtin.file:
        path: "{{ app_dir }}/releases/{{ app_version }}"
        state: directory
        owner: "{{ app_user }}"
        mode: '0755'
      tags: [deploy]

    - name: Desplegar ficheros de la aplicación
      ansible.builtin.copy:
        content: |
          #!/usr/bin/env python3
          # Aplicación simulada para el lab
          # Versión: {{ app_version }}
          # Entorno: {{ app_env }}
          # Desplegado: {{ ansible_date_time.iso8601 }}
          print("App {{ app_version }} running in {{ app_env }}")
        dest: "{{ app_dir }}/releases/{{ app_version }}/app.py"
        owner: "{{ app_user }}"
        mode: '0755'
      tags: [deploy]

    - name: Actualizar enlace simbólico a versión actual
      ansible.builtin.file:
        src: "{{ app_dir }}/releases/{{ app_version }}"
        dest: "{{ app_dir }}/current"
        state: link
        force: true
      notify: Restart webapp
      tags: [deploy, symlink]

    - name: Registrar versión desplegada
      ansible.builtin.copy:
        content: |
          version={{ app_version }}
          environment={{ app_env }}
          deployed_at={{ ansible_date_time.iso8601 }}
          deployed_by={{ lookup('env', 'AWX_USER_NAME') | default('unknown') }}
          change_ticket={{ change_ticket }}
        dest: "{{ app_dir }}/current/VERSION"
        owner: "{{ app_user }}"
        mode: '0644'
      tags: [deploy]

    # ── Servicios ─────────────────────────────────────────────
    - name: Asegurar que Nginx está habilitado y corriendo
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
      tags: [services]

    # ── Verificación ──────────────────────────────────────────
    - name: Verificar que Nginx responde
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: [200, 404]  # 404 es OK si no hay health endpoint
        timeout: 10
      register: health_result
      retries: 3
      delay: 5
      until: health_result.status in [200, 404]
      ignore_errors: true
      tags: [verify, health_check]

    - name: Mostrar resultado de verificación
      ansible.builtin.debug:
        msg: >
          Health check: {{ 'OK' if health_result.status is defined else 'No disponible' }}
      tags: [verify, always]

  post_tasks:
    - name: Resumen del deploy
      ansible.builtin.debug:
        msg:
          - "=== DEPLOY COMPLETADO ==="
          - "Versión:  {{ app_version }}"
          - "Entorno:  {{ app_env }}"
          - "Estado:   SUCCESS"
      tags: [always]

  handlers:
    - name: Restart webapp
      ansible.builtin.debug:
        msg: "Handler: reiniciando webapp (simulado en lab)"

    - name: Reload nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
      ignore_errors: true
```

```bash
# Commit el playbook al repo
git add playbooks/deploy_web.yml
git commit -m "feat: añadir playbook deploy_web con tags completos"
git push origin main

# Sincronizar el proyecto en AWX
# Projects → Platform Playbooks → Sync (o esperar webhook)
```

## Paso 2 — Crear el Job Template en AWX

```
Templates → Add → Job Template

  Name:         Web App Deploy
  Description:  Despliega la aplicación web. Soporta tags para ejecución parcial.
  Job Type:     Run
  
  Inventory:    Env Inventory
  Project:      Platform Playbooks
  Playbook:     playbooks/deploy_web.yml
  
  Credentials:
    + Platform SSH    (tipo Machine)
    + Vault Dev       (tipo Ansible Vault, si usas secrets)
  
  Execution Environment: Default Execution Environment
  
  Forks:        10
  Verbosity:    1 (Verbose)
  Timeout:      600  (10 minutos máximo)
  
  Options:
    ✅ Enable Privilege Escalation
    ✅ Enable Fact Cache
  
  Extra Variables:
    ---
    app_name: webapp
    health_check_retries: 5
    health_check_delay: 10
    rollback_enabled: true
  
  → Save
```

## Paso 3 — Lanzar y verificar

```
Templates → Web App Deploy → Launch (🚀)

# En el diálogo de launch (sin Survey todavía):
→ Launch

# Observar en tiempo real:
# - Cada task con su estado (ok/changed/failed/skipped)
# - Output de debug con la información del deploy
# - Duración de cada task
# - Estado final: Successful ✅
```

```bash
# Verificar via API que el job se completó
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/jobs/?order_by=-id&page_size=1" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
job = data['results'][0]
print(f'Job ID:    {job[\"id\"]}')
print(f'Status:    {job[\"status\"]}')
print(f'Template:  {job[\"name\"]}')
print(f'Started:   {job[\"started\"]}')
print(f'Finished:  {job[\"finished\"]}')
print(f'Elapsed:   {job[\"elapsed\"]}s')
"
```

---

# 3.9 LAB — Survey con inputs validados

*Añadimos un formulario de inputs al Job Template para que los operadores puedan lanzar deploys de forma segura.*

## Paso 1 — Diseñar el Survey

Antes de configurarlo en AWX, diseña qué preguntas necesitas:

```
PREGUNTA 1: Versión de la aplicación
  Variable:  app_version
  Tipo:      Text
  Validación: regex ^v\d+\.\d+\.\d+$  (formato semver: v1.2.3)
  Default:   v1.0.0
  Requerido: Sí

PREGUNTA 2: Entorno de despliegue
  Variable:  environment
  Tipo:      Multiple Choice (single select)
  Opciones:  dev, stage, prod
  Default:   dev
  Requerido: Sí

PREGUNTA 3: Grupo de hosts objetivo
  Variable:  target_group
  Tipo:      Multiple Choice (single select)
  Opciones:  dev, dev_web, stage, prod, prod_web
  Default:   dev
  Requerido: Sí

PREGUNTA 4: Ticket de cambio
  Variable:  change_ticket
  Tipo:      Text
  Validación: min_length=0, max_length=50
  Default:   (vacío)
  Requerido: No

PREGUNTA 5: Notas del deploy
  Variable:  deploy_notes
  Tipo:      Textarea
  Default:   (vacío)
  Requerido: No
```

## Paso 2 — Configurar el Survey en AWX

```
Templates → Web App Deploy → Survey → Add Question

── Pregunta 1: Versión ──────────────────────────────────────────
  Question:             ¿Qué versión desplegar?
  Description:          Formato semver: v1.2.3
  Answer Variable Name: app_version
  Answer Type:          Text
  Minimum Length:       5
  Maximum Length:       20
  Default Answer:       v1.0.0
  Required:             ✅
  → Save

── Pregunta 2: Entorno ──────────────────────────────────────────
  Question:             ¿En qué entorno desplegar?
  Description:          Selecciona el entorno objetivo
  Answer Variable Name: environment
  Answer Type:          Multiple Choice (single select)
  Multiple Choice Options:
    dev
    stage
    prod
  Default Answer:       dev
  Required:             ✅
  → Save

── Pregunta 3: Grupo de hosts ───────────────────────────────────
  Question:             ¿Qué grupo de hosts?
  Description:          Grupo del inventario donde desplegar
  Answer Variable Name: target_group
  Answer Type:          Multiple Choice (single select)
  Multiple Choice Options:
    dev
    dev_web
    stage
    prod
    prod_web
  Default Answer:       dev
  Required:             ✅
  → Save

── Pregunta 4: Ticket ───────────────────────────────────────────
  Question:             Ticket de cambio (opcional)
  Description:          Número de ticket JIRA/ServiceNow para auditoría
  Answer Variable Name: change_ticket
  Answer Type:          Text
  Minimum Length:       0
  Maximum Length:       50
  Default Answer:       (dejar vacío)
  Required:             ❌
  → Save

── Pregunta 5: Notas ────────────────────────────────────────────
  Question:             Notas del deploy (opcional)
  Description:          Descripción de los cambios o contexto adicional
  Answer Variable Name: deploy_notes
  Answer Type:          Textarea
  Default Answer:       (dejar vacío)
  Required:             ❌
  → Save
```

## Paso 3 — Habilitar el Survey

```
Templates → Web App Deploy → Survey

  Toggle: Survey Enabled → ON  ✅

  → Save
```

## Paso 4 — Verificar el Survey en acción

```
Templates → Web App Deploy → Launch (🚀)

# Ahora aparece el formulario del Survey:
  ¿Qué versión desplegar?      → v1.2.0
  ¿En qué entorno desplegar?   → dev
  ¿Qué grupo de hosts?         → dev
  Ticket de cambio (opcional)  → DEV-1234
  Notas del deploy (opcional)  → Primera prueba del Survey

→ Next → Launch

# En los logs verás:
# "=== INICIO DE DEPLOY ==="
# "Versión:  v1.2.0"
# "Entorno:  dev"
# "Ticket:   DEV-1234"
```

## Paso 5 — Verificar que la validación funciona

```
Templates → Web App Deploy → Launch (🚀)

# Intentar introducir una versión inválida:
  ¿Qué versión desplegar? → 1.2.0  (sin la "v" inicial)
  
# AWX mostrará error de validación si configuraste el regex
# El campo no acepta el valor hasta que cumpla el formato

# Intentar introducir texto en un campo de opciones:
  ¿En qué entorno desplegar? → (solo puedes elegir de la lista)
```

## Paso 6 — Ver las variables del Survey en los logs del job

```bash
# Ver las variables con las que se ejecutó el job
JOB_ID=5  # ajusta al ID del último job
curl -s -u "admin:TuPasswordSegura123!" \
  "http://localhost:30080/api/v2/jobs/${JOB_ID}/" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('Extra vars del job:')
print(json.dumps(json.loads(data.get('extra_vars', '{}')), indent=2))
"
# {
#   "app_version": "v1.2.0",
#   "environment": "dev",
#   "target_group": "dev",
#   "change_ticket": "DEV-1234",
#   "deploy_notes": "Primera prueba del Survey"
# }
```

---

# 3.10 LAB — Tags, skip-tags y limit para ejecuciones quirúrgicas

*Aprendemos a ejecutar solo las partes necesarias del playbook para reducir tiempo y riesgo.*

## Paso 1 — Habilitar prompts para tags y limit

```
Templates → Web App Deploy → Edit

  Prompt on Launch:
    ✅ Limit
    ✅ Job Tags
    ✅ Skip Tags
  
  → Save
```

## Paso 2 — Escenarios de ejecución con tags

### Escenario A: Solo actualizar configuración

```
Templates → Web App Deploy → Launch

Survey:
  app_version: v1.2.0
  environment: dev
  target_group: dev

Prompt - Limit:     dev
Prompt - Job Tags:  config
Prompt - Skip Tags: packages,deploy,verify

→ Launch

# Solo ejecutará las tasks con tag "config"
# Mucho más rápido que un deploy completo
# Útil para: cambios de configuración sin nueva versión
```

### Escenario B: Solo desplegar nueva versión (sin reconfigurar)

```
Survey:
  app_version: v1.3.0
  environment: stage
  target_group: stage

Limit:     stage
Job Tags:  deploy,verify
Skip Tags: packages,config

→ Launch

# Solo descarga y despliega el artefacto, luego verifica
# Asume que la configuración ya está correcta
```

### Escenario C: Canary deploy (un host primero)

```
# Primera ejecución: solo el host primario
Survey:
  app_version: v1.4.0
  environment: prod
  target_group: prod

Limit:     prod-web1    ← solo el primer host
Job Tags:  deploy,verify

→ Launch → Verificar manualmente → Si OK, continuar

# Segunda ejecución: el resto de hosts
Limit:     prod:!prod-web1   ← todos excepto el primero
Job Tags:  deploy,verify

→ Launch
```

### Escenario D: Solo verificar el estado actual

```
Survey:
  app_version: v1.4.0  (no importa, no se usa)
  environment: prod
  target_group: prod

Limit:     prod
Job Tags:  verify

→ Launch

# Solo ejecuta las tasks de verificación
# Útil para: health checks, auditorías de estado
```

## Paso 3 — Crear Job Templates especializados (alternativa a prompts)

Para equipos donde los operadores no deben elegir tags, crea templates específicos:

```
# Template 1: Deploy completo
Templates → Add → Job Template
  Name:      Web App - Deploy Completo
  Playbook:  playbooks/deploy_web.yml
  Job Tags:  (vacío = todo)
  → Save

# Template 2: Solo configuración
Templates → Add → Job Template
  Name:      Web App - Solo Config
  Playbook:  playbooks/deploy_web.yml
  Job Tags:  config
  Skip Tags: packages,deploy,verify
  → Save

# Template 3: Solo deploy de artefacto
Templates → Add → Job Template
  Name:      Web App - Solo Deploy
  Playbook:  playbooks/deploy_web.yml
  Job Tags:  deploy,verify
  Skip Tags: packages,config
  → Save

# Template 4: Health Check
Templates → Add → Job Template
  Name:      Web App - Health Check
  Playbook:  playbooks/deploy_web.yml
  Job Tags:  verify
  Job Type:  Check  ← dry-run, no hace cambios
  → Save
```

## Paso 4 — Verificar el comportamiento de tags via API

```bash
# Lanzar un job con tags específicos via API
curl -s -u "admin:TuPasswordSegura123!" \
  -X POST \
  -H "Content-Type: application/json" \
  "http://localhost:30080/api/v2/job_templates/1/launch/" \
  -d '{
    "extra_vars": {
      "app_version": "v1.5.0",
      "environment": "dev",
      "target_group": "dev"
    },
    "limit": "dev",
    "job_tags": "config",
    "skip_tags": "packages,deploy"
  }' \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Job lanzado: ID={data[\"id\"]}')
print(f'Status: {data[\"status\"]}')
print(f'Tags: {data[\"job_tags\"]}')
print(f'Skip Tags: {data[\"skip_tags\"]}')
print(f'Limit: {data[\"limit\"]}')
"
```

---

# 3.11 LAB — Execution Environment personalizado con colecciones fijadas

*Construimos un EE personalizado con las colecciones exactas que necesitamos, fijadas a versiones específicas.*

## Paso 1 — Preparar los ficheros de definición del EE

```bash
# Crear directorio para el EE
mkdir -p ee-webapp && cd ee-webapp
```

```yaml
# ee-webapp/requirements.yml
# Colecciones necesarias con versiones fijadas
---
collections:
  - name: community.general
    version: ">=9.3.0,<10.0.0"

  - name: ansible.posix
    version: ">=1.5.0,<2.0.0"

  - name: community.mysql
    version: ">=3.8.0,<4.0.0"

  - name: amazon.aws
    version: ">=8.0.0,<9.0.0"

  - name: community.crypto
    version: ">=2.18.0,<3.0.0"
```

```text
# ee-webapp/bindep.txt
# Dependencias del sistema operativo
git [platform:rpm]
git [platform:dpkg]
rsync [platform:rpm]
rsync [platform:dpkg]
jq [platform:rpm]
jq [platform:dpkg]
```

```text
# ee-webapp/requirements.txt
# Dependencias Python
boto3>=1.34.0,<2.0.0
botocore>=1.34.0,<2.0.0
PyMySQL>=1.1.0
cryptography>=42.0.0
requests>=2.31.0
```

```yaml
# ee-webapp/execution-environment.yml
# Definición del EE para ansible-builder
---
version: 3

build_arg_defaults:
  ANSIBLE_GALAXY_CLI_COLLECTION_OPTS: "--pre"

dependencies:
  galaxy: requirements.yml
  python: requirements.txt
  system: bindep.txt

images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

additional_build_steps:
  prepend_galaxy:
    - ENV ANSIBLE_GALAXY_SERVER_TIMEOUT=120

  append_final:
    - RUN ansible --version
    - RUN ansible-galaxy collection list
```

## Paso 2 — Construir el EE con ansible-builder

```bash
# Instalar ansible-builder
pip install ansible-builder

# Construir el EE
ansible-builder build \
  --file execution-environment.yml \
  --tag registry.ejemplo.com/ee/webapp-ee:1.0.0 \
  --container-runtime docker \
  --verbosity 2

# El proceso:
# 1. Descarga la imagen base
# 2. Instala las colecciones de requirements.yml
# 3. Instala las dependencias Python de requirements.txt
# 4. Instala las dependencias del sistema de bindep.txt
# 5. Genera la imagen final

# Verificar que la imagen se construyó correctamente
docker run --rm registry.ejemplo.com/ee/webapp-ee:1.0.0 \
  ansible-galaxy collection list

# Output esperado:
# Collection                    Version
# ----------------------------- -------
# amazon.aws                    8.x.x
# ansible.posix                 1.x.x
# community.crypto              2.x.x
# community.general             9.x.x
# community.mysql               3.x.x
```

## Paso 3 — Push al registry

```bash
# Login al registry
docker login registry.ejemplo.com

# Push de la imagen
docker push registry.ejemplo.com/ee/webapp-ee:1.0.0

# Obtener el digest para pin inmutable (recomendado para prod)
docker inspect registry.ejemplo.com/ee/webapp-ee:1.0.0 \
  --format='{{index .RepoDigests 0}}'
# registry.ejemplo.com/ee/webapp-ee@sha256:abc123def456...
```

## Paso 4 — Registrar el EE en AWX

```
# Primero: crear credencial para el registry (si es privado)
Credentials → Add
  Name:         Registry Privado
  Type:         Container Registry
  Authentication URL: registry.ejemplo.com
  Username:     tu-usuario
  Password:     tu-password-o-token
  → Save

# Registrar el EE
Administration → Execution Environments → Add

  Name:         EE WebApp 1.0.0
  Description:  EE con community.general, mysql, aws. Versiones fijadas.
  Image:        registry.ejemplo.com/ee/webapp-ee:1.0.0
  
  # Para prod, usar digest inmutable:
  # Image: registry.ejemplo.com/ee/webapp-ee@sha256:abc123def456...
  
  Pull:         Always  (en CI/dev)
  # Pull:       If not present  (en prod, para velocidad)
  
  Credential:   Registry Privado
  
  → Save
```

## Paso 5 — Asignar el EE al Job Template

```
Templates → Web App Deploy → Edit

  Execution Environment: EE WebApp 1.0.0
  
  → Save → Launch

# En los logs del job verás:
# Using EE image: registry.ejemplo.com/ee/webapp-ee:1.0.0
# Pulling image...
# Running with ansible-core X.Y.Z
```

## Paso 6 — Verificar el EE desde dentro del job

```yaml
# Añadir esta task al playbook para verificar el EE en uso
- name: Mostrar información del Execution Environment
  ansible.builtin.debug:
    msg:
      - "ansible-core: {{ ansible_version.full }}"
      - "Python: {{ ansible_python_version }}"
      - "EE Image: {{ lookup('env', 'AWX_EE_IMAGE') | default('unknown') }}"
  tags: [always, debug_ee]
```

---

# 3.12 LAB — Job Template avanzado con todas las opciones

*Combinamos todo lo aprendido en un Job Template de producción completo.*

## El Job Template completo

```
Templates → Add → Job Template

── IDENTIFICACIÓN ───────────────────────────────────────────────
  Name:         [PROD] Web App - Deploy Completo
  Description:  |
    Deploy completo de la aplicación web.
    Soporta tags: packages, config, deploy, verify
    Requiere: ticket de cambio para entorno prod
    Mantenedor: equipo Platform
  Job Type:     Run

── CONTENIDO ────────────────────────────────────────────────────
  Inventory:    Env Inventory
  Project:      Platform Playbooks (Prod)    ← proyecto con pin de tag
  Playbook:     playbooks/deploy_web.yml
  EE:           EE WebApp 1.0.0

── CREDENCIALES ─────────────────────────────────────────────────
  Credentials:
    + Platform SSH    (Machine)
    + Vault Prod      (Ansible Vault)

── EJECUCIÓN ────────────────────────────────────────────────────
  Forks:        20
  Verbosity:    1 (Verbose)
  Timeout:      900   (15 minutos)
  Job Slicing:  1     (sin slicing por defecto)

── OPCIONES ─────────────────────────────────────────────────────
  ✅ Enable Privilege Escalation
  ✅ Enable Fact Cache
  ✅ Prevent Instance Group Fallback

── PROMPTS ON LAUNCH ────────────────────────────────────────────
  ✅ Limit          (para canary/targeting)
  ✅ Job Tags       (para ejecución parcial)
  ✅ Skip Tags      (para saltar pasos)
  ☐  Credentials   (fijas, no cambiar en prod)
  ☐  Inventory     (fijo en prod)

── EXTRA VARIABLES ──────────────────────────────────────────────
  ---
  app_name: webapp
  health_check_retries: 5
  health_check_delay: 15
  rollback_enabled: true
  notification_channel: "#deployments-prod"
  max_deploy_time: 600

── INSTANCE GROUP ───────────────────────────────────────────────
  Instance Group: ig-prod    ← grupo dedicado a producción

→ Save
```

## Añadir el Survey completo

```
Templates → [PROD] Web App - Deploy Completo → Survey

── Pregunta 1 ───────────────────────────────────────────────────
  Question:             Versión a desplegar
  Description:          Formato: v1.2.3 (semver obligatorio)
  Answer Variable Name: app_version
  Answer Type:          Text
  Min Length:           5
  Max Length:           20
  Default:              v1.0.0
  Required:             ✅

── Pregunta 2 ───────────────────────────────────────────────────
  Question:             Entorno objetivo
  Answer Variable Name: environment
  Answer Type:          Multiple Choice (single select)
  Choices:              dev / stage / prod
  Default:              prod
  Required:             ✅

── Pregunta 3 ───────────────────────────────────────────────────
  Question:             Grupo de hosts
  Answer Variable Name: target_group
  Answer Type:          Multiple Choice (single select)
  Choices:              prod / prod_web / prod_db / all
  Default:              prod_web
  Required:             ✅

── Pregunta 4 ───────────────────────────────────────────────────
  Question:             Ticket de cambio (obligatorio en prod)
  Description:          Formato: CHANGE-XXXX o JIRA-XXXX
  Answer Variable Name: change_ticket
  Answer Type:          Text
  Min Length:           5
  Max Length:           30
  Default:              (vacío)
  Required:             ✅

── Pregunta 5 ───────────────────────────────────────────────────
  Question:             Número máximo de forks para este deploy
  Description:          Entre 1 y 50. Default: 20
  Answer Variable Name: custom_forks
  Answer Type:          Integer
  Min:                  1
  Max:                  50
  Default:              20
  Required:             ❌

Survey Enabled: ✅ ON
→ Save
```

## Lanzar el Job Template completo

```
Templates → [PROD] Web App - Deploy Completo → Launch

Survey:
  Versión:       v2.0.0
  Entorno:       prod
  Grupo:         prod_web
  Ticket:        CHANGE-4521
  Forks:         20

Prompts:
  Limit:         prod_web    (o prod-web1 para canary)
  Job Tags:      (vacío = deploy completo)
  Skip Tags:     (vacío)

→ Launch

# Seguir la ejecución en tiempo real
# Verificar que todas las tasks pasan
# Confirmar el estado final: Successful ✅
```

---

# 3.13 Patrones avanzados y buenas prácticas

## Patrón 1: Job Templates como bloques atómicos

```
❌ MAL: Un template que hace todo
  "Deploy completo: provision + configure + deploy + test + notify"