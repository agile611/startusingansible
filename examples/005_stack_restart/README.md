# 005 – Stack Restart con Ansible

Este ejemplo muestra cómo usar Ansible para **reiniciar de forma ordenada una pila de servicios**
(en este caso Apache + MySQL) en múltiples máquinas, respetando el orden de parada y arranque.
A continuación se detalla cada fichero y su función.

---

## 📁 Estructura del ejemplo

```
005_stack_restart/
├── playbook.yml         # Playbook principal
├── group_vars/
│   └── all.yml          # Variables compartidas
└── roles/
    ├── apache/
    │   └── tasks/
    │       └── main.yml
    └── mysql/
        └── tasks/
            └── main.yml
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

El playbook orquesta el reinicio en **tres fases ordenadas**:

```yaml
---
# FASE 1: Parar Apache en los servidores web
- hosts: webservers
  become: yes
  roles:
    - role: apache
      apache_state: stopped

# FASE 2: Reiniciar MySQL en los servidores de base de datos
- hosts: dbservers
  become: yes
  roles:
    - role: mysql
      mysql_state: restarted

# FASE 3: Arrancar Apache en los servidores web
- hosts: webservers
  become: yes
  roles:
    - role: apache
      apache_state: started
```

### 🔄 Orden de ejecución

```
1. STOP   → Apache  (webservers)   ← evita peticiones mientras la BD reinicia
2. RESTART→ MySQL   (dbservers)    ← reinicio seguro de la base de datos
3. START  → Apache  (webservers)   ← vuelve a aceptar tráfico
```

> **¿Por qué este orden?**
> Se para Apache primero para que no haya conexiones activas a la base de datos
> durante su reinicio. Una vez MySQL está operativo, se vuelve a levantar Apache.
> Esto garantiza un reinicio **sin errores de conexión** ni pérdida de peticiones.

---

## ⚙️ Role: `apache`

**Fichero:** `roles/apache/tasks/main.yml`

```yaml
---
- name: Gestionar servicio Apache
  service:
    name: apache2
    state: "{{ apache_state }}"
```

- Usa el módulo `service` de Ansible para controlar el demonio `apache2`.
- El estado (`stopped` / `started` / `restarted`) se inyecta como variable
  desde el playbook principal mediante `apache_state`.
- `become: yes` garantiza que la tarea se ejecuta con privilegios de `root`
  (equivalente a `sudo`).

---

## ⚙️ Role: `mysql`

**Fichero:** `roles/mysql/tasks/main.yml`

```yaml
---
- name: Gestionar servicio MySQL
  service:
    name: mysql
    state: "{{ mysql_state }}"
```

- Idéntica estructura al role de Apache.
- El estado se controla con la variable `mysql_state` (en este caso `restarted`).
- Se ejecuta también con `become: yes`.

---

## 📦 Variables: `group_vars/all.yml`

```yaml
---
apache_state: started
mysql_state:  started
```

- Define los **valores por defecto** de las variables de estado.
- El playbook los **sobreescribe** en cada play según la fase del reinicio.
- Tenerlos en `group_vars/all.yml` permite reutilizar los roles en otros
  contextos sin tocar su código interno.

---

## 🧩 Flujo completo resumido

```
ansible-playbook -i hosts -u vagrant playbook.yml
        │
        ├── Play 1 → webservers (192.168.56.11)
        │       └── role: apache  →  service apache2  STATE: stopped
        │
        ├── Play 2 → dbservers  (192.168.56.12)
        │       └── role: mysql   →  service mysql    STATE: restarted
        │
        └── Play 3 → webservers (192.168.56.11)
                └── role: apache  →  service apache2  STATE: started
```

---

## 💡 Conceptos clave aprendidos

| Concepto                  | Descripción                                                        |
|---------------------------|--------------------------------------------------------------------|
| **Roles reutilizables**   | El mismo role se usa dos veces con distintos parámetros            |
| **Variables como estado** | `apache_state` / `mysql_state` controlan el comportamiento del rol |
| **Orden de plays**        | Ansible ejecuta los plays en secuencia, lo que permite orquestar   |
| **`become: yes`**         | Escala privilegios a `root` para gestionar servicios del sistema   |
| **`service` module**      | Módulo estándar para controlar daemons en Linux                    |

---

## ✅ Requisitos previos

- Vagrant instalado con las dos VMs levantadas (`vagrant up`)
- Ansible instalado en la máquina de control
- Conectividad SSH a `192.168.56.11` y `192.168.56.12`
- Apache2 instalado en `webservers` y MySQL en `dbservers`
