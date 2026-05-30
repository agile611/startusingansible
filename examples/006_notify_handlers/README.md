# 006 – Notify & Handlers con Ansible

Este ejemplo introduce uno de los mecanismos más potentes de Ansible: los **handlers**.
Un handler es una tarea especial que **solo se ejecuta si otra tarea la notifica** (`notify`),
y únicamente **una vez al final del play**, aunque múltiples tareas lo hayan invocado.
Es el patrón ideal para reiniciar servicios solo cuando realmente ha habido un cambio.

---

## 📁 Estructura del ejemplo

```
006_notify_handlers/
├── playbook.yml         # Playbook principal
├── group_vars/
│   └── all.yml          # Variables compartidas
└── roles/
    ├── apache/
    │   ├── tasks/
    │   │   └── main.yml     # Tareas del role Apache
    │   ├── handlers/
    │   │   └── main.yml     # Handler: reiniciar Apache
    │   └── templates/
    │       └── apache.conf.j2  # Plantilla de configuración
    └── mysql/
        ├── tasks/
        │   └── main.yml     # Tareas del role MySQL
        └── handlers/
            └── main.yml     # Handler: reiniciar MySQL
```

---

## 🗂️ Inventario: `hosts`

El fichero `hosts` (en la raíz del repositorio) define las máquinas gestionadas:

```ini
[webservers]
192.168.56.11

[dbservers]
192.168.56.12

[all:vars]
ansible_user=vagrant
ansible_ssh_private_key_file=~/.vagrant.d/insecure_private_key
ansible_python_interpreter=/usr/bin/python3
```

| Grupo        | IP             | Rol asignado     |
|--------------|----------------|------------------|
| `webservers` | 192.168.56.11  | Servidor Apache  |
| `dbservers`  | 192.168.56.12  | Servidor MySQL   |

- Las IPs corresponden a máquinas virtuales **Vagrant** levantadas localmente.
- Se usa la clave SSH insegura de Vagrant (entorno de desarrollo).
- Se fuerza el intérprete Python 3 para evitar warnings de deprecación.

---

## ▶️ Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

| Parámetro      | Significado                                              |
|----------------|----------------------------------------------------------|
| `-i hosts`     | Usa el fichero `hosts` como inventario                   |
| `-u vagrant`   | Se conecta a las máquinas con el usuario `vagrant`       |
| `playbook.yml` | Playbook principal a ejecutar                            |

---

## 📋 Playbook principal: `playbook.yml`

El playbook aplica los roles a cada grupo de servidores:

```yaml
---
- hosts: webservers
  become: yes
  roles:
    - apache

- hosts: dbservers
  become: yes
  roles:
    - mysql
```

- Cada play aplica un role al grupo correspondiente.
- `become: yes` permite ejecutar tareas con privilegios de `root`.
- La magia ocurre **dentro de los roles**, en la relación tarea → notify → handler.

---

## ⚙️ Role: `apache`

### Tareas: `roles/apache/tasks/main.yml`

```yaml
---
- name: Instalar Apache
  apt:
    name: apache2
    state: present
  notify: restart apache

- name: Copiar configuración de Apache
  template:
    src: apache.conf.j2
    dest: /etc/apache2/sites-available/000-default.conf
  notify: restart apache
```

- **Tarea 1:** Instala el paquete `apache2` si no está presente.
  Si Ansible realiza un cambio (instala el paquete), **notifica** al handler `restart apache`.
- **Tarea 2:** Despliega una plantilla de configuración en el servidor.
  Si el fichero cambia respecto al existente, **notifica** al handler `restart apache`.

> **Clave:** Si ninguna tarea produce cambios (idempotencia), el handler
> **no se ejecuta**. Apache no se reinicia innecesariamente.

### Handler: `roles/apache/handlers/main.yml`

```yaml
---
- name: restart apache
  service:
    name: apache2
    state: restarted
```

- Se ejecuta **solo si fue notificado** por al menos una tarea.
- Se ejecuta **una sola vez** al final del play, aunque dos tareas lo hayan notificado.
- Reinicia el servicio `apache2` usando el módulo `service`.

### Plantilla: `roles/apache/templates/apache.conf.j2`

```jinja2
<VirtualHost *:{{ apache_port }}>
    ServerAdmin {{ apache_admin_email }}
    DocumentRoot {{ apache_document_root }}

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

- Es una plantilla **Jinja2** que Ansible renderiza con las variables definidas.
- Las variables `{{ apache_port }}`, `{{ apache_admin_email }}` y
  `{{ apache_document_root }}` se resuelven desde `group_vars/all.yml`.
- El fichero resultante se despliega en el servidor como configuración real de Apache.

---

## ⚙️ Role: `mysql`

### Tareas: `roles/mysql/tasks/main.yml`

```yaml
---
- name: Instalar MySQL
  apt:
    name: mysql-server
    state: present
  notify: restart mysql

- name: Asegurar que MySQL está habilitado
  service:
    name: mysql
    enabled: yes
```

- **Tarea 1:** Instala `mysql-server`. Si hay cambio, notifica al handler `restart mysql`.
- **Tarea 2:** Garantiza que MySQL arranca automáticamente con el sistema
  (no notifica ningún handler, es una tarea de estado puro).

### Handler: `roles/mysql/handlers/main.yml`

```yaml
---
- name: restart mysql
  service:
    name: mysql
    state: restarted
```

- Mismo patrón que el handler de Apache.
- Solo se dispara si la instalación de MySQL produjo un cambio real.

---

## 📦 Variables: `group_vars/all.yml`

```yaml
---
apache_port: 80
apache_admin_email: admin@example.com
apache_document_root: /var/www/html
```

- Define los valores que se inyectan en la plantilla `apache.conf.j2`.
- Centraliza la configuración: cambiar un valor aquí afecta a todos los servidores.

---

## 🔄 Flujo completo: cómo funciona notify + handler

```
Tarea ejecutada
      │
      ├── ¿Hubo cambio? (changed)
      │       │
      │       ├── SÍ → marca el handler como "pendiente"
      │       │
      │       └── NO → no pasa nada (idempotencia)
      │
      └── Al final del play...
              │
              └── ¿Handler pendiente? → SÍ → se ejecuta UNA sola vez
```

### Ejemplo práctico con dos tareas notificando el mismo handler:

```
Play: webservers
  ├── Tarea 1: Instalar Apache     → CHANGED → notify: restart apache ✓
  ├── Tarea 2: Copiar config       → CHANGED → notify: restart apache ✓
  └── Handlers:
        └── restart apache         → se ejecuta 1 vez (no 2)
```

> Sin handlers, habría que reiniciar Apache manualmente después de cada tarea,
> arriesgando reinicios dobles o innecesarios. Los handlers lo resuelven elegantemente.

---

## 🧩 Flujo completo del playbook

```
ansible-playbook -i hosts -u vagrant playbook.yml
        │
        ├── Play 1 → webservers (192.168.56.11)
        │       ├── task: instalar apache2       → [changed?] → notify: restart apache
        │       ├── task: copiar apache.conf.j2  → [changed?] → notify: restart apache
        │       └── handler: restart apache      → se ejecuta solo si hubo cambios
        │
        └── Play 2 → dbservers (192.168.56.12)
                ├── task: instalar mysql-server  → [changed?] → notify: restart mysql
                ├── task: habilitar mysql         → (sin notify)
                └── handler: restart mysql       → se ejecuta solo si hubo cambios
```

---

## 💡 Conceptos clave aprendidos

| Concepto              | Descripción                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| **`notify`**          | Marca un handler como pendiente si la tarea produce un cambio               |
| **`handlers`**        | Tareas especiales que solo se ejecutan si fueron notificadas                |
| **Ejecución única**   | Un handler se ejecuta una sola vez al final del play, sin importar cuántas tareas lo notifiquen |
| **Idempotencia**      | Si no hay cambios, el handler no se dispara → sin reinicios innecesarios    |
| **`template`**        | Módulo que renderiza ficheros Jinja2 con variables de Ansible               |
| **`group_vars`**      | Variables centralizadas aplicables a todos los hosts del inventario         |

---

## ✅ Requisitos previos

- Vagrant instalado con las dos VMs levantadas (`vagrant up`)
- Ansible instalado en la máquina de control
- Conectividad SSH a `192.168.56.11` y `192.168.56.12`
- Sistema operativo Debian/Ubuntu en las VMs (usa `apt` como gestor de paquetes)
