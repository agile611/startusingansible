# 📘 Ejemplo 005 – Stack Restart con Ansible

Este ejemplo muestra cómo usar Ansible para **reiniciar de forma ordenada y controlada una pila de servicios** compuesta por una base de datos, un balanceador de carga y servidores web. A continuación se detalla todo lo que hace el código, cómo está estructurado el inventario y cómo ejecutarlo.

---

## 🗂️ Inventario: fichero `hosts`

El fichero `hosts` define **qué máquinas gestiona Ansible** y cómo conectarse a ellas.

### Variables globales (`[all:vars]`)

Estas variables aplican a **todos los hosts** del inventario:

| **Variable** | **Valor** | **Descripción** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Usa Python 3 en los hosts remotos |
| `ansible_user` | `vagrant` | Usuario SSH con el que se conecta |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación de host SSH (útil en entornos de laboratorio) |

### Grupos de hosts

| **Grupo** | **IP** | **Rol en la pila** |
|---|---|---|
| `[database]` | `192.168.11.20` | Servidor de base de datos |
| `[loadbalancer]` | `192.168.11.30` | Balanceador de carga (ej. HAProxy/Nginx) |
| `[webserver]` | `192.168.11.40` | Servidor web de aplicación |

---

## 📋 ¿Qué hace el Playbook?

El playbook orquesta el **reinicio ordenado de la pila**, respetando las dependencias entre servicios. El orden es crítico: primero la base de datos, luego los servidores web, y finalmente el balanceador de carga.

### 🔄 Orden de reinicio

```
[database] → [webserver] → [loadbalancer]
```

> Este orden garantiza que cada capa esté operativa antes de que la capa superior intente conectarse.

---

### 🗄️ Play 1 – Reinicio de la Base de Datos (`[database]`)

Se conecta al host `192.168.11.20` y ejecuta tareas como:

- **Parar el servicio** de base de datos (ej. `mysql`, `postgresql`).
- **Arrancar el servicio** de nuevo.
- **Esperar** a que el puerto de la base de datos esté disponible antes de continuar (usando `wait_for`).

Esto asegura que la base de datos está completamente operativa antes de arrancar los servidores web.

---

### 🌐 Play 2 – Reinicio de los Servidores Web (`[webserver]`)

Se conecta al host `192.168.11.40` y ejecuta tareas como:

- **Parar el servicio web** (ej. `apache2`, `nginx`).
- **Arrancar el servicio web**.
- **Verificar** que el servicio responde correctamente (comprobación de puerto o URL).

Los servidores web dependen de la base de datos, por eso se reinician **después** de ella.

---

### ⚖️ Play 3 – Reinicio del Balanceador de Carga (`[loadbalancer]`)

Se conecta al host `192.168.11.30` y ejecuta tareas como:

- **Parar el balanceador** (ej. `haproxy`).
- **Arrancar el balanceador**.
- **Confirmar** que el servicio está escuchando en el puerto correspondiente.

El balanceador se reinicia **al final** porque es el punto de entrada del tráfico; si se reiniciara primero, los usuarios verían errores mientras los backends aún no están listos.

---

## ▶️ Comando de ejecución

La estructura del comando es:

```bash
ansible-playbook -i hosts -u vagrant <nombre_del_playbook>.yml
```

### Desglose de los parámetros

| **Parámetro** | **Descripción** |
|---|---|
| `ansible-playbook` | Comando principal para ejecutar playbooks |
| `-i hosts` | Especifica el fichero de inventario (`hosts`) |
| `-u vagrant` | Usuario SSH con el que se conecta a los hosts remotos |
| `<nombre_del_playbook>.yml` | Fichero YAML del playbook a ejecutar |

### Ejemplo concreto

```bash
ansible-playbook -i hosts -u vagrant stack_restart.yml
```

---

## 💡 Conceptos clave que ilustra este ejemplo

Este ejemplo es una demostración práctica de varios patrones fundamentales de Ansible:

- **Orquestación multi-host**: gestionar varios grupos de máquinas en un solo playbook con orden controlado.
- **Dependencias entre servicios**: reiniciar en el orden correcto para evitar errores en cascada.
- **`wait_for`**: módulo de Ansible que pausa la ejecución hasta que un puerto o condición esté disponible, haciendo el reinicio **robusto y fiable**.
- **Idempotencia**: las tareas pueden ejecutarse múltiples veces sin producir efectos no deseados.
- **Inventario por grupos**: separar los hosts por rol (`database`, `webserver`, `loadbalancer`) permite aplicar tareas específicas a cada capa de la arquitectura.

---

## 🏗️ Arquitectura de la pila

```
         Internet / Usuario
               │
               ▼
      ┌─────────────────┐
      │  Load Balancer  │  192.168.11.30
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │   Web Server    │  192.168.11.40
      └────────┬────────┘
               │
               ▼
      ┌─────────────────┐
      │    Database     │  192.168.11.20
      └─────────────────┘
```

El tráfico entra por el balanceador, pasa al servidor web, y este consulta la base de datos. Por eso el **reinicio se hace de abajo hacia arriba** y el **arranque del balanceador es siempre el último paso**.
