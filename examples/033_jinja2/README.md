# 📋 Ejemplo 033 — `jinja2`: Plantillas dinámicas con Jinja2 en Ansible

## 🧭 Descripción general

Este ejemplo introduce uno de los conceptos más potentes de Ansible: **las plantillas Jinja2**. Jinja2 es el motor de plantillas que Ansible usa internamente en absolutamente todo — desde las variables `{{ variable }}` en los playbooks hasta la generación dinámica de ficheros de configuración completos en los servidores gestionados.

La diferencia fundamental respecto a copiar un fichero estático con el módulo `copy` es que con el módulo `template` el fichero se **renderiza en tiempo de ejecución**: Ansible sustituye las expresiones Jinja2 (`{{ }}`, `{% %}`, `{# #}`) con los valores reales de las variables antes de enviar el fichero al nodo destino. Esto permite generar configuraciones personalizadas para cada host a partir de una única plantilla.

Este ejemplo es la base teórica y práctica de lo que ya se ha visto en los roles `nginx` y `apache2` de los ejemplos anteriores — las plantillas `nginx.conf.j2` y `apache2.conf.j2` son exactamente esto. Aquí se estudia Jinja2 de forma explícita y aislada.

---

## 🗂️ Estructura típica del proyecto

```
033_jinija2/
├── hosts                           # Inventario (database, loadbalancer, webserver)
├── jinja2.yml                      # ⭐ Playbook principal: demuestra plantillas Jinja2
└── templates/                      # Directorio de plantillas .j2
    ├── config.j2                   # Plantilla de ejemplo con variables, bucles y condicionales
    └── motd.j2                     # Plantilla para el mensaje del día (Message of the Day)
```

> **Nota**: El directorio del repositorio tiene un typo intencional en el nombre (`jinija2` en lugar de `jinja2`). El contenido y los conceptos son idénticos.

---

## 📋 Fichero `hosts` — El inventario

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=vagrant
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[database]
192.168.11.20

[loadbalancer]
192.168.11.30

[webserver]
192.168.11.40
```

| **Grupo** | **IP** | **Rol en el ejemplo** |
|---|---|---|
| `[database]` | `192.168.11.20` | Nodo donde se despliegan plantillas de configuración de BD |
| `[loadbalancer]` | `192.168.11.30` | Nodo donde se despliegan plantillas de configuración de Nginx |
| `[webserver]` | `192.168.11.40` | Nodo donde se despliegan plantillas de configuración de Apache |

---

## 🔑 Los tres delimitadores de Jinja2

Jinja2 usa tres tipos de delimitadores, cada uno con un propósito distinto:

| **Delimitador** | **Nombre** | **Uso** | **Ejemplo** |
|---|---|---|---|
| `{{ }}` | **Expression** | Imprimir el valor de una variable o expresión | `{{ ansible_hostname }}` |
| `{% %}` | **Statement** | Lógica de control: `if`, `for`, `set`... | `{% if condicion %}` |
| `{# #}` | **Comment** | Comentarios que no aparecen en el fichero final | `{# esto es un comentario #}` |

---

## 📄 El módulo `template` — La pieza central

El módulo `template` es el equivalente de `copy` pero con renderizado Jinja2. Toma un fichero `.j2` del nodo de control, sustituye todas las expresiones Jinja2 con los valores reales, y deposita el resultado en el nodo destino.

```yaml
- name: Desplegar fichero de configuración desde plantilla
  template:
    src: templates/config.j2      # Fichero .j2 en el nodo de control
    dest: /etc/myapp/config.conf  # Destino en el nodo gestionado (ya renderizado)
    owner: root
    group: root
    mode: '0644'
```

| **Parámetro** | **Significado** |
|---|---|
| `src` | Ruta al fichero `.j2` en el nodo de control (relativa al playbook o al rol) |
| `dest` | Ruta donde se guarda el fichero renderizado en el nodo destino |
| `owner` / `group` | Propietario y grupo del fichero resultante |
| `mode` | Permisos del fichero resultante |

---

## 🧩 Sintaxis Jinja2 en detalle

### 1. Variables — `{{ }}`

La forma más básica: imprimir el valor de una variable de Ansible.

```jinja2
# Plantilla: motd.j2
Bienvenido a {{ ansible_hostname }}
Sistema operativo: {{ ansible_distribution }} {{ ansible_distribution_version }}
IP del servidor: {{ ansible_default_ipv4.address }}
Entorno: {{ entorno | default('desarrollo') }}
```

Resultado renderizado en `192.168.11.40`:
```
Bienvenido a webserver
Sistema operativo: Ubuntu 22.04
IP del servidor: 192.168.11.40
Entorno: desarrollo
```

Las variables disponibles en las plantillas son exactamente las mismas que en los playbooks:
- **Facts de Ansible** (`ansible_hostname`, `ansible_distribution`, etc.)
- **Variables del inventario** (`group_vars`, `host_vars`)
- **Variables del playbook** (`vars`, `vars_files`)
- **Variables de rol** (`defaults/main.yml`, `vars/main.yml`)

---

### 2. Filtros — `{{ variable | filtro }}`

Los filtros transforman el valor de una variable antes de imprimirlo. Jinja2 incluye decenas de filtros built-in, y Ansible añade sus propios filtros específicos.

```jinja2
# Ejemplos de filtros en plantillas
{{ nombre | upper }}                    → NOMBRE EN MAYÚSCULAS
{{ nombre | lower }}                    → nombre en minúsculas
{{ nombre | capitalize }}               → Nombre con primera letra mayúscula
{{ lista | join(', ') }}               → elemento1, elemento2, elemento3
{{ variable | default('valor') }}       → valor si variable no está definida
{{ numero | int }}                      → convierte a entero
{{ texto | replace('viejo', 'nuevo') }} → reemplaza texto
{{ lista | length }}                    → número de elementos
{{ variable | bool }}                   → convierte a booleano
{{ path | basename }}                   → nombre del fichero sin la ruta
```

Ejemplo práctico en una plantilla de configuración:

```jinja2
# config.j2
[database]
host = {{ db_host | default('localhost') }}
port = {{ db_port | default(3306) | int }}
name = {{ db_name | upper }}
max_connections = {{ max_conn | default(100) }}
```

---

### 3. Condicionales — `{% if %}`

Permiten incluir o excluir bloques de configuración según el valor de una variable o un fact de Ansible.

```jinja2
# nginx.conf.j2
server {
    listen 80;
    server_name {{ server_name }};

{% if ssl_enabled is defined and ssl_enabled %}
    listen 443 ssl;
    ssl_certificate /etc/ssl/{{ server_name }}.crt;
    ssl_certificate_key /etc/ssl/{{ server_name }}.key;
{% endif %}

{% if environment == 'production' %}
    access_log /var/log/nginx/access.log combined;
    error_log /var/log/nginx/error.log warn;
{% else %}
    access_log /var/log/nginx/access.log debug;
    error_log /var/log/nginx/error.log debug;
{% endif %}
}
```

Estructura completa de condicionales:

```jinja2
{% if condicion %}
  # bloque si condicion es verdadera
{% elif otra_condicion %}
  # bloque si otra_condicion es verdadera
{% else %}
  # bloque por defecto
{% endif %}
```

---

### 4. Bucles — `{% for %}`

Permiten generar bloques repetitivos a partir de listas o diccionarios.

```jinja2
# hosts.j2 — generar /etc/hosts dinámicamente
127.0.0.1   localhost

# Servidores del inventario
{% for host in groups['webserver'] %}
{{ hostvars[host]['ansible_default_ipv4']['address'] }}   {{ host }}
{% endfor %}

{% for host in groups['database'] %}
{{ hostvars[host]['ansible_default_ipv4']['address'] }}   {{ host }}
{% endfor %}
```

Ejemplo con diccionario de sitios web (patrón de los ejemplos anteriores):

```jinja2
# nginx-sites.j2
{% for site_name, site_config in sites.items() %}
upstream {{ site_name }} {
    server {{ site_config.backend }}:{{ site_config.port }};
}

server {
    listen 80;
    server_name {{ site_name }};
    location / {
        proxy_pass http://{{ site_name }};
    }
}
{% endfor %}
```

---

### 5. Variables locales — `{% set %}`

Permiten definir variables temporales dentro de la plantilla para simplificar expresiones complejas.

```jinja2
{% set max_workers = ansible_processor_vcpus * 2 %}
{% set log_dir = '/var/log/' + app_name %}

worker_processes {{ max_workers }};
error_log {{ log_dir }}/error.log;
access_log {{ log_dir }}/access.log;
```

---

### 6. Comentarios — `{# #}`

Los comentarios Jinja2 **no aparecen** en el fichero renderizado final. Son útiles para documentar la plantilla sin contaminar el fichero de configuración generado.

```jinja2
{# Este fichero es gestionado por Ansible. No editar manualmente. #}
{# Plantilla: templates/config.j2 — Variables: group_vars/all.yml #}

[server]
port = {{ app_port }}
```

---

## 📄 Ejemplo completo de playbook `jinja2.yml`

```yaml
---
- name: Demostración de plantillas Jinja2
  hosts: all
  become: true
  vars:
    app_name: miapp
    app_port: 8080
    entorno: produccion
    ssl_enabled: false
    servidores_backend:
      - nombre: web1
        ip: 192.168.11.40
        puerto: 80
      - nombre: web2
        ip: 192.168.11.41
        puerto: 80

  tasks:
    - name: Desplegar mensaje del día (MOTD)
      template:
        src: templates/motd.j2
        dest: /etc/motd
        owner: root
        group: root
        mode: '0644'

    - name: Desplegar fichero de configuración de la aplicación
      template:
        src: templates/config.j2
        dest: /etc/{{ app_name }}/config.conf
        owner: root
        group: root
        mode: '0640'
      notify: Reiniciar aplicación

    - name: Mostrar el contenido del fichero generado
      command: cat /etc/motd
      register: motd_content
      changed_when: false

    - name: Imprimir el MOTD renderizado
      debug:
        msg: "{{ motd_content.stdout_lines }}"

  handlers:
    - name: Reiniciar aplicación
      service:
        name: "{{ app_name }}"
        state: restarted
```

---

## 🔍 Flujo de ejecución

```
jinja2.yml  (hosts: all → database + loadbalancer + webserver)
│
├── [vars]  Definición de variables locales del play
│       ├── app_name, app_port, entorno, ssl_enabled
│       └── servidores_backend (lista de dicts)
│
├── [1] template (motd.j2)     → Renderiza y despliega /etc/motd en cada nodo
│       └── Sustituye: ansible_hostname, ansible_distribution, entorno...
│
├── [2] template (config.j2)   → Renderiza y despliega /etc/miapp/config.conf
│       └── notify: Reiniciar aplicación (handler)
│
├── [3] command: cat /etc/motd → Lee el fichero generado para verificar
│       └── register: motd_content
│
├── [4] debug                  → Imprime el contenido del MOTD renderizado
│
└── [handler] Reiniciar aplicación → Solo si config.j2 generó cambios (changed)
```

---

## 🏗️ Comparativa: `copy` vs `template`

| **Aspecto** | **Módulo `copy`** | **Módulo `template`** |
|---|---|---|
| **Procesamiento Jinja2** | ❌ No — copia el fichero tal cual | ✅ Sí — renderiza antes de copiar |
| **Variables en el fichero** | ❌ No se sustituyen | ✅ Se sustituyen en tiempo de ejecución |
| **Extensión del fichero fuente** | Cualquiera | Convencionalmente `.j2` |
| **Personalización por host** | ❌ Mismo fichero para todos | ✅ Fichero diferente por host (misma plantilla) |
| **Bucles y condicionales** | ❌ No | ✅ Sí (`{% for %}`, `{% if %}`) |
| **Caso de uso** | Ficheros estáticos (binarios, scripts fijos) | Ficheros de configuración dinámicos |

---

## 🚀 Comandos de ejecución

### Ejecutar el playbook en todos los nodos

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml
```

### Ejecutar solo en el grupo webserver

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml --limit webserver
```

### Ejecutar solo en el loadbalancer

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml --limit loadbalancer
```

### Ver las tareas sin ejecutar

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml --list-tasks
```

### Verificar sintaxis

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml --syntax-check
```

### Modo dry-run (sin cambios reales)

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml --check
```

### Pasar variables externas para sobreescribir las del playbook

```bash
ansible-playbook -i hosts -u vagrant jinja2.yml \
  -e "entorno=staging" \
  -e "app_port=9090"
```

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Jinja2 es omnipresente en Ansible**: No es solo para el módulo `template`. Cada vez que escribes `{{ variable }}` en un playbook, en un `when`, en un `loop`, en un `debug` — estás usando Jinja2. Entender Jinja2 es entender Ansible.

- **`template` vs `copy`**: El módulo `template` renderiza el fichero `.j2` antes de enviarlo al nodo destino. El módulo `copy` envía el fichero tal cual. La elección depende de si el fichero necesita adaptarse a cada host o entorno.

- **Facts como variables de plantilla**: Todos los facts recopilados por `gather_facts` (`ansible_hostname`, `ansible_distribution`, `ansible_default_ipv4.address`, etc.) están disponibles directamente en las plantillas. Esto permite generar configuraciones completamente adaptadas a cada servidor sin escribir una línea de Python.

- **Filtros Jinja2**: Los filtros (`| default()`, `| upper`, `| join()`, `| int`, etc.) son transformaciones que se aplican a las variables en el momento del renderizado. Son la forma idiomática de manejar valores opcionales, formatear strings y transformar estructuras de datos en las plantillas.

- **Idempotencia del módulo `template`**: Al igual que `copy`, el módulo `template` calcula el hash del fichero renderizado y lo compara con el fichero existente en el destino. Solo reporta `changed` (y dispara handlers) si el contenido ha cambiado. Si la plantilla genera el mismo resultado que el fichero existente, reporta `ok`.

- **Separación de lógica y datos**: Las plantillas Jinja2 implementan el principio de separación entre la **estructura** del fichero (la plantilla `.j2`) y los **datos** (las variables en `group_vars`, `host_vars` o `vars`). Esto permite reutilizar la misma plantilla para diferentes entornos (desarrollo, staging, producción) simplemente cambiando las variables.

- **Convención `.j2`**: Los ficheros de plantilla se nombran con la extensión `.j2` por convención (ej. `nginx.conf.j2`, `motd.j2`). Ansible no requiere esta extensión — el módulo `template` funciona con cualquier extensión — pero es la práctica estándar de la comunidad para distinguir plantillas de ficheros estáticos.

---

## 📚 Referencias

- [Ansible Docs — `template` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Templating (Jinja2)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Docs — Filters](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html)
- [Ansible Docs — Tests](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tests.html)
- [Jinja2 Docs — Template Designer Documentation](https://jinja.palletsprojects.com/en/3.1.x/templates/)
- [Ansible Docs — Special Variables (Facts)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
