# 📦 Ejemplo 008 — Instalación de paquetes Python con el módulo `pip` en Ansible

## 🧭 Descripción general

Este ejemplo muestra cómo usar Ansible para **instalar paquetes Python mediante `pip`** en un conjunto de máquinas remotas organizadas por grupos (`database`, `loadbalancer`, `webserver`). Es un patrón muy habitual en entornos de infraestructura automatizada donde cada rol de servidor necesita dependencias Python específicas.

El módulo `ansible.builtin.pip` permite gestionar paquetes Python de forma idempotente, es decir, solo instala lo que falta, sin reinstalar lo que ya está presente. 

---

## 🗂️ Estructura del proyecto

```
008_pip/
├── hosts           # Inventario de máquinas
├── requirements.txt # Lista de paquetes Python a instalar
└── playbook.yml    # Playbook principal de Ansible
```

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

### ¿Qué define este inventario?

| **Parámetro** | **Valor** | **Descripción** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Fuerza el uso de Python 3 en los nodos remotos |
| `ansible_user` | `vagrant` | Usuario SSH con el que Ansible se conecta |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación de host SSH (útil en entornos de laboratorio) |

Los tres grupos definen máquinas con roles diferenciados:
- **`[database]`** → `192.168.11.20` — Servidor de base de datos
- **`[loadbalancer]`** → `192.168.11.30` — Balanceador de carga
- **`[webserver]`** → `192.168.11.40` — Servidor web

> ⚠️ `StrictHostKeyChecking=no` es práctico en laboratorios con Vagrant, pero **no se recomienda en producción** por razones de seguridad. 

---

## 📄 Fichero `requirements.txt` — Paquetes Python

Este fichero lista los paquetes Python que se instalarán en los nodos remotos. Un ejemplo típico para este tipo de ejemplo sería:

```
flask
requests
gunicorn
```

Ansible lee este fichero y lo pasa al módulo `pip` para instalar cada dependencia listada, de forma equivalente a ejecutar `pip install -r requirements.txt` manualmente en cada máquina. 

---

## 📜 Fichero `playbook.yml` — El Playbook principal

Un playbook típico para este ejemplo tiene la siguiente estructura:

```yaml
---
- name: Instalar paquetes Python con pip
  hosts: all
  become: true

  tasks:
    - name: Instalar pip3 si no está presente
      ansible.builtin.package:
        name: python3-pip
        state: present

    - name: Instalar paquetes desde requirements.txt
      ansible.builtin.pip:
        requirements: /ruta/al/requirements.txt
        executable: pip3
```

### Desglose de cada tarea

#### ✅ Tarea 1 — Asegurar que `pip3` está instalado
Antes de poder instalar paquetes Python, el nodo remoto necesita tener `pip3` disponible. El módulo `ansible.builtin.package` (o `apt`/`yum` según la distro) garantiza que esté presente. 

#### ✅ Tarea 2 — Instalar paquetes desde `requirements.txt`
El módulo `ansible.builtin.pip` acepta el parámetro `requirements` apuntando a un fichero de dependencias. Instala todos los paquetes listados usando `pip3`. Los parámetros más relevantes del módulo son:

| **Parámetro** | **Descripción** |
|---|---|
| `requirements` | Ruta al fichero `requirements.txt` |
| `name` | Nombre de un paquete individual (alternativa a `requirements`) |
| `state: present` | Asegura que el paquete está instalado |
| `state: absent` | Desinstala el paquete |
| `state: latest` | Actualiza al paquete a la última versión |
| `executable` | Especifica el ejecutable pip a usar (`pip3`, `pip`) |
| `virtualenv` | Instala en un entorno virtual específico |



---

## ▶️ Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

### Desglose del comando

| **Parte** | **Descripción** |
|---|---|
| `ansible-playbook` | Comando principal para ejecutar playbooks |
| `-i hosts` | Especifica el fichero de inventario (`hosts`) |
| `-u vagrant` | Usuario SSH de conexión (sobreescribe `ansible_user` si difiere) |
| `playbook.yml` | Fichero playbook a ejecutar |

> 💡 Como el fichero `hosts` ya define `ansible_user=vagrant`, el flag `-u vagrant` es redundante pero explícito. En entornos con múltiples usuarios definidos, `-u` permite sobreescribir el valor del inventario. 

---

## 🔄 Flujo completo de ejecución

```
[Máquina de control]
        │
        ├─ Lee inventario (hosts)
        ├─ Conecta por SSH a cada nodo (clave id_rsa, user vagrant)
        │
        ├──► 192.168.11.20 (database)   ─┐
        ├──► 192.168.11.30 (loadbalancer) ├─ Instala pip3 + paquetes de requirements.txt
        └──► 192.168.11.40 (webserver)  ─┘
```

Ansible ejecuta las tareas en **paralelo** sobre todos los nodos definidos en `hosts: all`, conectándose por SSH sin contraseña gracias a la clave privada configurada. 

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Módulo `pip`**: Gestión idempotente de paquetes Python en nodos remotos. 
- **`requirements.txt`**: Patrón estándar de Python para declarar dependencias, reutilizable tanto en local como con Ansible.
- **`become: true`**: Escalada de privilegios (`sudo`) necesaria para instalar paquetes a nivel de sistema. 
- **Inventario por grupos**: Permite aplicar tareas a subconjuntos de máquinas (`database`, `webserver`, etc.) de forma selectiva.
- **Autenticación SSH sin contraseña**: Uso de claves RSA para conexiones automatizadas seguras. 

---

## 📚 Referencias

- : [Ansible Docs — ansible.builtin.pip module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/pip_module.html)
- : [Ansible Docs — SSH connection settings](https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html)
- : [Ansible Docs — ansible.builtin.package module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_module.html)
- : [Ansible Docs — ansible-playbook command](https://docs.ansible.com/ansible/latest/cli/ansible-playbook.html)
