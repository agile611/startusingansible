# 034 — Condicionales `when` en Ansible

## 📋 Descripción General

Este ejemplo demuestra el uso de la directiva `when` en Ansible,
que permite ejecutar tareas de forma **condicional** según el grupo
al que pertenece cada host, sus variables o los hechos (`facts`)
recogidos automáticamente por Ansible.

El uso de `when` es fundamental para escribir playbooks **reutilizables**
que se ejecutan sobre infraestructuras heterogéneas — como en este caso,
donde tenemos tres tipos de servidores con roles completamente diferentes.

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
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Desactiva la verificación de la clave del host (útil en entornos de laboratorio Vagrant) |

Los tres grupos definen la **topología de la infraestructura**:

- **`[database]`** → `192.168.11.20` — Servidor de base de datos
- **`[loadbalancer]`** → `192.168.11.30` — Balanceador de carga (ej: HAProxy / Nginx)
- **`[webserver]`** → `192.168.11.40` — Servidor web (ej: Apache / Nginx)

---

## 🎭 Qué hace el Playbook (`playbook.yml`)

El playbook se ejecuta sobre **todos los hosts** (`hosts: all`) pero
utiliza la directiva `when` para aplicar tareas específicas
**solo a los hosts que pertenecen a un grupo determinado**.

### Lógica condicional con `when`

```yaml
# Ejemplo de patrón típico de un playbook 034_when

- name: Ejemplo de condicionales when
  hosts: all
  become: true

  tasks:

    - name: Instalar MySQL (solo en el servidor de base de datos)
      apt:
        name: mysql-server
        state: present
      when: inventory_hostname in groups['database']

    - name: Instalar HAProxy (solo en el balanceador)
      apt:
        name: haproxy
        state: present
      when: inventory_hostname in groups['loadbalancer']

    - name: Instalar Apache (solo en los servidores web)
      apt:
        name: apache2
        state: present
      when: inventory_hostname in groups['webserver']

    - name: Tarea común para todos los servidores
      debug:
        msg: "Este servidor es: {{ inventory_hostname }}"
```

### Cómo funciona `when` paso a paso

1. Ansible se conecta a los **3 hosts** simultáneamente vía SSH
2. Para cada host, evalúa la condición `when` de cada tarea
3. Si la condición es **`true`** → ejecuta la tarea
4. Si la condición es **`false`** → marca la tarea como `skipping` y continúa
5. El resultado final es que **cada host recibe solo las tareas que le corresponden**

### Flujo de ejecución visual

```
                    ┌─────────────────────────────────────┐
                    │         ansible-playbook             │
                    │         hosts: all                   │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
    192.168.11.20          192.168.11.30        192.168.11.40
    [database]             [loadbalancer]       [webserver]
              │                    │                    │
              ▼                    ▼                    ▼
    ✅ MySQL install        ✅ HAProxy install   ✅ Apache install
    ⏭️  HAProxy → SKIP      ⏭️  MySQL → SKIP     ⏭️  MySQL → SKIP
    ⏭️  Apache → SKIP       ⏭️  Apache → SKIP    ⏭️  HAProxy → SKIP
    ✅ Debug msg            ✅ Debug msg         ✅ Debug msg
```

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

> **Nota:** El flag `-u vagrant` es redundante en este caso porque
> ya está definido en `[all:vars]` como `ansible_user=vagrant`,
> pero es una buena práctica especificarlo explícitamente en el comando.

---

## 🔑 Conceptos Clave Aprendidos

### 1. La directiva `when`
Permite condicionar la ejecución de una tarea. Acepta expresiones Python/Jinja2:

```yaml
# Por grupo de inventario
when: inventory_hostname in groups['webserver']

# Por sistema operativo (usando facts)
when: ansible_os_family == "Debian"

# Por variable
when: my_variable == true

# Condiciones múltiples (AND)
when:
  - ansible_os_family == "Debian"
  - inventory_hostname in groups['webserver']

# Condiciones múltiples (OR)
when: ansible_os_family == "Debian" or ansible_os_family == "RedHat"
```

### 2. `inventory_hostname`
Variable mágica de Ansible que contiene el nombre o IP del host
que se está procesando en ese momento.

### 3. `groups['nombre_grupo']`
Diccionario de Ansible que contiene todos los hosts de un grupo determinado.
La combinación `inventory_hostname in groups['grupo']` es el patrón
más común para aplicar tareas por rol de servidor.

### 4. Comportamiento `skipping`
Cuando una condición `when` no se cumple, Ansible **no falla** —
simplemente muestra `skipping` y continúa con la siguiente tarea.
Esto es lo que permite ejecutar un solo playbook sobre toda la infraestructura.

---

## 🏗️ Casos de Uso Reales

| **Escenario** | **Condición `when`** |
|---|---|
| Instalar paquetes por rol | `inventory_hostname in groups['webserver']` |
| Diferenciar Debian vs RedHat | `ansible_os_family == "Debian"` |
| Ejecutar solo en producción | `env == "production"` |
| Saltar si ya está configurado | `not config_file.stat.exists` |
| Condicionar por versión de SO | `ansible_distribution_version >= "20.04"` |

---

## 📚 Referencias

- [Ansible Docs — Conditionals (`when`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [Ansible Docs — Magic Variables (`inventory_hostname`, `groups`)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Ansible Docs — Inventory basics](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Repositorio original — agile611/startusingansible](https://github.com/agile611/startusingansible)