# 008 – Gestión de paquetes Python con pip en Ansible

Este ejemplo muestra cómo usar Ansible para **gestionar paquetes Python mediante pip**
en servidores remotos: instalar dependencias, crear entornos virtuales, fijar versiones
específicas y desinstalar paquetes. Es el patrón estándar para preparar entornos
Python en infraestructura gestionada como código.

---

## 📁 Estructura del ejemplo

```
008_pip/
├── playbook.yml              # Playbook principal
├── group_vars/
│   └── all.yml               # Variables: paquetes y versiones
└── roles/
    └── python_setup/
        ├── tasks/
        │   └── main.yml      # Tareas de gestión pip
        └── files/
            └── requirements.txt  # Fichero de dependencias Python
```

---

## 🗂️ Inventario: `hosts`

El fichero `hosts` define tres grupos de máquinas con roles diferenciados:

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

| Grupo          | IP             | Rol en la infraestructura       |
|----------------|----------------|---------------------------------|
| `database`     | 192.168.11.20  | Servidor de base de datos       |
| `loadbalancer` | 192.168.11.30  | Balanceador de carga            |
| `webserver`    | 192.168.11.40  | Servidor de aplicación web      |

### Variables globales `[all:vars]`

| Variable                    | Valor                            | Propósito                                          |
|-----------------------------|----------------------------------|----------------------------------------------------|
| `ansible_python_interpreter`| `/usr/bin/python3`               | Fuerza Python 3 en todos los hosts                 |
| `ansible_user`              | `vagrant`                        | Usuario SSH para conectarse                        |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa`   | Clave privada SSH para autenticación               |
| `ansible_ssh_common_args`   | `-o StrictHostKeyChecking=no`    | Evita la verificación de host key (entorno dev)    |

> **Nota:** `StrictHostKeyChecking=no` es conveniente en entornos de desarrollo
> con Vagrant, pero **nunca debe usarse en producción** ya que desactiva una
> protección contra ataques de tipo man-in-the-middle.

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

```yaml
---
- hosts: all
  become: yes
  roles:
    - python_setup
```

- Se aplica a **todos los hosts** del inventario (`database`, `loadbalancer`, `webserver`).
- `become: yes` permite instalar paquetes del sistema y escribir en rutas protegidas.
- Delega toda la lógica al role `python_setup`.

---

## ⚙️ Role: `python_setup`

### Tareas: `roles/python_setup/tasks/main.yml`

```yaml
---
# 1. Asegurar que pip y python3-venv están instalados en el sistema
- name: Instalar pip3 y python3-venv
  apt:
    name:
      - python3-pip
      - python3-venv
    state: present
    update_cache: yes

# 2. Crear un entorno virtual Python
- name: Crear entorno virtual en /opt/myapp/venv
  pip:
    virtualenv: /opt/myapp/venv
    virtualenv_command: python3 -m venv
    name: pip
    state: latest

# 3. Instalar un paquete con versión específica
- name: Instalar Flask versión específica
  pip:
    name: Flask
    version: "2.3.2"
    virtualenv: /opt/myapp/venv

# 4. Instalar múltiples paquetes desde una variable
- name: Instalar paquetes Python desde variable
  pip:
    name: "{{ python_packages }}"
    virtualenv: /opt/myapp/venv
    state: present

# 5. Copiar requirements.txt al servidor remoto
- name: Copiar requirements.txt al servidor remoto
  copy:
    src: requirements.txt
    dest: /opt/myapp/requirements.txt
    owner: root
    group: root
    mode: '0644'

# 6. Instalar dependencias desde requirements.txt
- name: Instalar dependencias desde requirements.txt
  pip:
    requirements: /opt/myapp/requirements.txt
    virtualenv: /opt/myapp/venv

# 7. Desinstalar paquetes obsoletos
- name: Desinstalar paquetes obsoletos
  pip:
    name: "{{ item }}"
    state: absent
    virtualenv: /opt/myapp/venv
  loop: "{{ pip_packages_to_remove }}"
```

---

## 🔍 Análisis tarea por tarea

### 1. Instalar pip3 y python3-venv — módulo `apt`

```yaml
apt:
  name:
    - python3-pip
    - python3-venv
  state: present
  update_cache: yes
```

- Instala los prerrequisitos del sistema operativo antes de usar el módulo `pip`.
- `update_cache: yes` equivale a ejecutar `apt-get update` antes de instalar.
- Sin `python3-pip` instalado, el módulo `pip` de Ansible no puede funcionar.
- Se ejecuta en los **tres servidores**: `database`, `loadbalancer` y `webserver`.

---

### 2. Crear entorno virtual — módulo `pip` con `virtualenv`

```yaml
pip:
  virtualenv: /opt/myapp/venv
  virtualenv_command: python3 -m venv
  name: pip
  state: latest
```

- Crea un entorno virtual aislado en `/opt/myapp/venv`.
- `virtualenv_command: python3 -m venv` usa el módulo estándar de Python 3
  en lugar de la herramienta `virtualenv` externa.
- Actualiza `pip` dentro del entorno virtual a su última versión.
- **Aislamiento:** los paquetes instalados aquí no afectan al Python del sistema.

---

### 3. Instalar paquete con versión fija — módulo `pip`

```yaml
pip:
  name: Flask
  version: "2.3.2"
  virtualenv: /opt/myapp/venv
```

- Instala exactamente `Flask==2.3.2` dentro del entorno virtual.
- Fijar versiones garantiza **reproducibilidad**: el mismo playbook produce
  el mismo entorno en cualquier servidor y en cualquier momento.
- Si la versión ya está instalada, Ansible marca `ok` (idempotente).

---

### 4. Instalar lista de paquetes — módulo `pip` con variable

```yaml
pip:
  name: "{{ python_packages }}"
  virtualenv: /opt/myapp/venv
  state: present
```

- `python_packages` es una lista definida en `group_vars/all.yml`.
- Ansible pasa la lista completa al módulo `pip` en una sola llamada.
- `state: present` instala si no existe; no actualiza si ya hay una versión instalada.

---

### 5. Copiar requirements.txt — módulo `copy`

```yaml
copy:
  src: requirements.txt
  dest: /opt/myapp/requirements.txt
  owner: root
  group: root
  mode: '0644'
```

- Copia el fichero desde `roles/python_setup/files/requirements.txt`
  al servidor remoto en `/opt/myapp/requirements.txt`.
- Ansible detecta cambios por checksum: si el fichero no cambia, no retransfiere.
- Esta tarea debe ejecutarse **antes** de la que instala desde `requirements.txt`.

---

### 6. Instalar desde requirements.txt — módulo `pip`

```yaml
pip:
  requirements: /opt/myapp/requirements.txt
  virtualenv: /opt/myapp/venv
```

- Lee el fichero `requirements.txt` del servidor remoto y lo instala.
- Es el método más habitual en proyectos Python reales.
- El fichero debe existir en el servidor antes de ejecutar esta tarea
  (garantizado por la tarea 5).

---

### 7. Desinstalar paquetes — módulo `pip` con `loop`

```yaml
pip:
  name: "{{ item }}"
  state: absent
  virtualenv: /opt/myapp/venv
loop: "{{ pip_packages_to_remove }}"
```

- Itera sobre la lista `pip_packages_to_remove` definida en `group_vars/all.yml`.
- `state: absent` desinstala el paquete si está presente.
- Si el paquete no está instalado, Ansible marca `ok` sin error (idempotente).
- `loop` es el mecanismo de Ansible para repetir una tarea con distintos valores.

---

## 📄 Fichero: `roles/python_setup/files/requirements.txt`

```
Flask==2.3.2
requests==2.31.0
SQLAlchemy==2.0.19
gunicorn==21.2.0
python-dotenv==1.0.0
```

- Formato estándar de Python para declarar dependencias con versiones fijas.
- Ansible lo copia al servidor y luego `pip` lo procesa.
- Mantener versiones fijas en `requirements.txt` es una **buena práctica**
  para entornos de producción.

---

## 📦 Variables: `group_vars/all.yml`

```yaml
---
python_packages:
  - requests
  - SQLAlchemy
  - gunicorn
  - python-dotenv

pip_packages_to_remove:
  - simplejson
  - nose
```

| Variable                 | Tipo   | Uso                                                   |
|--------------------------|--------|-------------------------------------------------------|
| `python_packages`        | Lista  | Paquetes a instalar via módulo `pip` + variable       |
| `pip_packages_to_remove` | Lista  | Paquetes a desinstalar con `state: absent` + `loop`   |

---

## 🧩 Flujo completo del playbook

```
ansible-playbook -i hosts -u vagrant playbook.yml
        │
        └── Play 1 → all hosts
                ├── 192.168.11.20  (database)
                ├── 192.168.11.30  (loadbalancer)
                └── 192.168.11.40  (webserver)
                        │
                        ├── task 1: apt       → instalar python3-pip + python3-venv
                        ├── task 2: pip       → crear venv en /opt/myapp/venv
                        ├── task 3: pip       → instalar Flask==2.3.2
                        ├── task 4: pip       → instalar lista {{ python_packages }}
                        ├── task 5: copy      → copiar requirements.txt al servidor
                        ├── task 6: pip       → instalar desde requirements.txt
                        └── task 7: pip+loop  → desinstalar {{ pip_packages_to_remove }}
```

> Ansible ejecuta **todas las tareas en cada host** antes de pasar al siguiente,
> o bien ejecuta cada tarea en todos los hosts en paralelo según la configuración
> de `forks` en `ansible.cfg` (por defecto 5 hosts en paralelo).

---

## 🔑 Formas de instalar paquetes con el módulo `pip`

| Método                  | Cuándo usarlo                                       | Ejemplo clave                           |
|-------------------------|-----------------------------------------------------|-----------------------------------------|
| **Paquete único**       | Un solo paquete, versión libre                      | `name: requests`                        |
| **Versión fija**        | Reproducibilidad en producción                      | `name: Flask, version: "2.3.2"`         |
| **Lista de paquetes**   | Varios paquetes definidos como variable             | `name: "{{ python_packages }}"`         |
| **requirements.txt**    | Proyectos Python con dependencias ya declaradas     | `requirements: /ruta/requirements.txt`  |
| **Desinstalar**         | Limpiar paquetes obsoletos o conflictivos           | `state: absent`                         |

---

## 💡 Conceptos clave aprendidos

| Concepto                      | Descripción                                                               |
|-------------------------------|---------------------------------------------------------------------------|
| **Módulo `pip`**              | Gestiona paquetes Python en hosts remotos (instalar, actualizar, borrar)  |
| **`virtualenv`**              | Crea entornos Python aislados para no contaminar el sistema               |
| **`version:`**                | Fija una versión exacta para garantizar reproducibilidad                  |
| **`requirements:`**           | Instala dependencias desde un fichero `requirements.txt`                  |
| **`state: absent`**           | Desinstala un paquete si está presente                                    |
| **`loop:`**                   | Repite una tarea iterando sobre una lista de valores                      |
| **`StrictHostKeyChecking=no`**| Desactiva verificación de host key SSH (solo para desarrollo con Vagrant) |
| **`group_vars/all.yml`**      | Centraliza listas de paquetes aplicables a todos los grupos               |

---

## ✅ Requisitos previos

- Vagrant instalado con las tres VMs levantadas (`vagrant up`)
- Ansible instalado en la máquina de control
- Conectividad SSH a `192.168.11.20`, `192.168.11.30` y `192.168.11.40`
- Clave SSH generada en `/home/vagrant/.ssh/id_rsa` y distribuida a los hosts
- Sistema operativo Debian/Ubuntu en las VMs (usa `apt` como gestor de paquetes)
- Python 3 disponible en los hosts remotos
