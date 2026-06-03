# 033 — Templates Jinja2 en Ansible

## 📋 Descripción General

Este ejemplo demuestra el uso del módulo `template` de Ansible junto con
**plantillas Jinja2** (ficheros `.j2`), que permiten generar ficheros de
configuración **dinámicos** en los hosts remotos, sustituyendo variables
en tiempo de ejecución.

Es uno de los conceptos más potentes de Ansible: en lugar de copiar
ficheros estáticos, se generan ficheros **personalizados para cada host**
a partir de una plantilla común.

---

## 🗂️ Estructura del Proyecto

```
033_jinja2/
├── hosts               # Inventario de hosts
├── playbook.yml        # Playbook principal
└── index.html.j2       # Plantilla Jinja2 (fichero dinámico)
```

---

## 🗂️ Estructura del Inventario (`hosts`)

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

### Explicación del inventario

| **Parámetro** | **Valor** | **Función** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Fuerza el uso de Python 3 en los nodos remotos |
| `ansible_user` | `vagrant` | Usuario SSH para conectarse a los hosts |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada para autenticación SSH sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Desactiva la verificación de clave del host (entorno Vagrant) |

Los tres grupos definen la **topología de la infraestructura**:

- **`[database]`** → `192.168.11.20` — Servidor de base de datos
- **`[loadbalancer]`** → `192.168.11.30` — Balanceador de carga
- **`[webserver]`** → `192.168.11.40` — Servidor web

---

## 🎭 Qué hace el Playbook (`playbook.yml`)

El playbook instala Apache en el servidor web y despliega una página
`index.html` **generada dinámicamente** a partir de una plantilla Jinja2,
usando variables propias de cada host como su IP, nombre o grupo.

### Contenido típico del playbook

```yaml
---
- name: Deploy web page using Jinja2 template
  hosts: webserver
  become: true

  vars:
    app_name: "My Ansible App"
    environment: "production"

  tasks:

    - name: Install Apache web server
      apt:
        name: apache2
        state: present
        update_cache: yes

    - name: Ensure Apache is started and enabled
      service:
        name: apache2
        state: started
        enabled: yes

    - name: Deploy index.html from Jinja2 template
      template:
        src: index.html.j2
        dest: /var/www/html/index.html
        owner: www-data
        group: www-data
        mode: '0644'
      notify: Restart Apache

  handlers:
    - name: Restart Apache
      service:
        name: apache2
        state: restarted
```

---

## 🧩 La Plantilla Jinja2 (`index.html.j2`)

El fichero `.j2` es HTML estándar con **expresiones Jinja2** intercaladas.
Ansible procesa la plantilla en el controlador y envía el fichero
**ya renderizado** al host remoto.

### Contenido típico de `index.html.j2`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>{{ app_name }}</title>
</head>
<body>
    <h1>Welcome to {{ app_name }}</h1>
    <p><strong>Server IP:</strong> {{ ansible_default_ipv4.address }}</p>
    <p><strong>Hostname:</strong> {{ ansible_hostname }}</p>
    <p><strong>OS:</strong> {{ ansible_distribution }} {{ ansible_distribution_version }}</p>
    <p><strong>Environment:</strong> {{ environment }}</p>
    <p><strong>Managed by:</strong> Ansible + Jinja2</p>
</body>
</html>
```

### Variables Jinja2 utilizadas

| **Variable** | **Origen** | **Valor de ejemplo** |
|---|---|---|
| `{{ app_name }}` | `vars` del playbook | `My Ansible App` |
| `{{ environment }}` | `vars` del playbook | `production` |
| `{{ ansible_default_ipv4.address }}` | Fact automático | `192.168.11.40` |
| `{{ ansible_hostname }}` | Fact automático | `webserver` |
| `{{ ansible_distribution }}` | Fact automático | `Ubuntu` |
| `{{ ansible_distribution_version }}` | Fact automático | `22.04` |

---

## 🔄 Flujo de Ejecución Paso a Paso

```
  CONTROLADOR ANSIBLE
  ┌─────────────────────────────────────────┐
  │  1. Lee index.html.j2                   │
  │  2. Recoge facts del host remoto        │
  │  3. Sustituye {{ variables }} → valores │
  │  4. Genera index.html (ya renderizado)  │
  └──────────────────┬──────────────────────┘
                     │ SSH — transfiere fichero renderizado
                     ▼
  HOST REMOTO: 192.168.11.40 [webserver]
  ┌─────────────────────────────────────────┐
  │  5. Recibe index.html final             │
  │  6. Lo deposita en /var/www/html/       │
  │  7. Apache sirve la página              │
  └─────────────────────────────────────────┘
```

> **Clave:** Jinja2 se procesa **en el controlador**, no en el host remoto.
> El host recibe el fichero ya con todos los valores sustituidos.

---

## ▶️ Comando de Ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

### Desglose del comando

| **Flag** | **Valor** | **Función** |
|---|---|---|
| `-i hosts` | fichero `hosts` | Especifica el inventario de hosts |
| `-u vagrant` | `vagrant` | Usuario SSH para la conexión remota |
| `playbook.yml` | fichero principal | El playbook a ejecutar |

> **Nota:** `-u vagrant` es redundante porque ya está definido en
> `[all:vars]` como `ansible_user=vagrant`, pero es buena práctica
> especificarlo explícitamente.

---

## 🔑 Conceptos Clave Aprendidos

### 1. El módulo `template`
Copia un fichero `.j2` al host remoto **después de renderizarlo**:

```yaml
- name: Deploy config from template
  template:
    src: index.html.j2      # Fichero local en el controlador
    dest: /var/www/html/index.html  # Ruta destino en el host remoto
    owner: www-data
    group: www-data
    mode: '0644'
```

### 2. Sintaxis Jinja2 en Ansible

```jinja2
{# Comentario — no aparece en el fichero final #}

{{ variable }}               → Imprime el valor de una variable

{% if condition %}           → Condicional
  contenido
{% endif %}

{% for item in lista %}      → Bucle
  {{ item }}
{% endfor %}
```

### 3. Variables disponibles en las plantillas

```yaml
# Variables definidas en el playbook (vars:)
{{ app_name }}
{{ environment }}

# Facts recogidos automáticamente por Ansible (gather_facts: true)
{{ ansible_hostname }}
{{ ansible_default_ipv4.address }}
{{ ansible_distribution }}
{{ ansible_os_family }}
{{ ansible_memtotal_mb }}

# Variables mágicas de inventario
{{ inventory_hostname }}     # Nombre/IP del host en el inventario
{{ group_names }}            # Lista de grupos a los que pertenece el host
{{ ansible_user }}           # Usuario SSH utilizado
```

### 4. `notify` + `handlers`
Cuando la plantilla cambia, se dispara automáticamente el handler
que reinicia Apache — **solo si hubo cambios**, no siempre:

```yaml
tasks:
  - name: Deploy template
    template:
      src: index.html.j2
      dest: /var/www/html/index.html
    notify: Restart Apache       # ← Solo se ejecuta si el fichero cambió

handlers:
  - name: Restart Apache
    service:
      name: apache2
      state: restarted
```

---

## 🆚 Diferencia entre `copy` y `template`

| **Módulo** | **Fichero origen** | **Procesa variables** | **Uso recomendado** |
|---|---|---|---|
| `copy` | Fichero estático | ❌ No | Ficheros binarios o que no cambian |
| `template` | Fichero `.j2` | ✅ Sí | Configs dinámicas por host |

---

## 🏗️ Casos de Uso Reales con `template`

| **Fichero generado** | **Plantilla** | **Variables típicas** |
|---|---|---|
| Página web personalizada | `index.html.j2` | IP, hostname, entorno |
| Config de Nginx | `nginx.conf.j2` | Puerto, server_name, workers |
| Config de MySQL | `my.cnf.j2` | max_connections, buffer_size |
| `/etc/hosts` | `hosts.j2` | IPs de todos los nodos |
| Fichero `.env` de app | `app.env.j2` | DB_HOST, API_KEY, ENV |

---

## 📚 Referencias

- [Ansible Docs — Template module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html)
- [Ansible Docs — Jinja2 templating](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Docs — Using Variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html)
- [Ansible Docs — Discovering variables: facts and magic variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html)
- [Repositorio original — agile611/startusingansible](https://github.com/agile611/startusingansible)