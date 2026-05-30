# 📘 Ejemplo 006 — Notify & Handlers en Ansible

Este ejemplo ilustra uno de los patrones más importantes de Ansible: el uso de
**handlers** (manejadores) disparados mediante **notify**. La idea central es
ejecutar una acción secundaria (como reiniciar un servicio) *solo cuando una
tarea ha producido un cambio real* en el sistema — evitando reinicios
innecesarios y haciendo los playbooks más eficientes e idempotentes.

---

## 🗂️ Inventario (`hosts`)

El fichero de inventario define tres grupos de máquinas y variables globales
de conexión:

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3        # Intérprete Python a usar en los nodos
ansible_user=vagrant                               # Usuario SSH para conectarse
ansible_ssh_private_key_file=/home/vagrant/.ssh/id_rsa  # Clave privada SSH
ansible_ssh_common_args='-o StrictHostKeyChecking=no'   # Evita verificación de host SSH

[database]
192.168.11.20      # Nodo de base de datos

[loadbalancer]
192.168.11.30      # Nodo balanceador de carga

[webserver]
192.168.11.40      # Nodo servidor web
```

| **Grupo**      | **IP**         | **Rol**                  |
|----------------|----------------|--------------------------|
| `database`     | 192.168.11.20  | Servidor de base de datos |
| `loadbalancer` | 192.168.11.30  | Balanceador de carga      |
| `webserver`    | 192.168.11.40  | Servidor web              |

---

## 📄 Estructura del Playbook

El ejemplo `006_notify_handlers` contiene un playbook que demuestra el
mecanismo **notify → handler**. A continuación se explica su funcionamiento
completo.

---

## ⚙️ ¿Qué hace el código?

### 1. Tareas principales (`tasks`)

El playbook define tareas que realizan cambios en los nodos (por ejemplo,
instalar o configurar un servicio como **Nginx** o **Apache**). Cada tarea
que puede provocar un cambio incluye la directiva `notify`:

```yaml
tasks:
  - name: Instalar Nginx
    apt:
      name: nginx
      state: present
    notify: Reiniciar Nginx        # 👈 Dispara el handler SI hubo cambio
```

- Si la tarea **produce un cambio** (`changed`), Ansible registra
  internamente que debe ejecutar el handler asociado.
- Si la tarea **no produce cambio** (el paquete ya estaba instalado),
  el handler **no se ejecuta**.

---

### 2. Handlers (`handlers`)

Los handlers son tareas especiales que **solo se ejecutan al final del play**
y **únicamente si fueron notificados**:

```yaml
handlers:
  - name: Reiniciar Nginx
    service:
      name: nginx
      state: restarted
```

- Se definen en la sección `handlers:` del playbook.
- Su nombre debe coincidir **exactamente** con el valor del `notify`.
- Se ejecutan **una sola vez** aunque múltiples tareas los hayan notificado.
- Se lanzan **al final del play**, no en el momento del `notify`.

---

### 3. Flujo de ejecución completo

```
ansible-playbook -i hosts -u vagrant playbook.yml
        │
        ▼
┌─────────────────────────────────────────────┐
│  PLAY: webserver / loadbalancer / database  │
│                                             │
│  TASK 1: Instalar paquete                   │
│    → changed? ──YES──► marca handler        │
│    → changed? ──NO───► no marca nada        │
│                                             │
│  TASK 2: Copiar fichero de configuración    │
│    → changed? ──YES──► marca handler        │
│    → changed? ──NO───► no marca nada        │
│                                             │
│  [fin de todas las tasks]                   │
│         │                                   │
│         ▼                                   │
│  HANDLER: Reiniciar servicio                │
│    → Solo si fue marcado (notificado)       │
└─────────────────────────────────────────────┘
```

---

## 🚀 Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

| **Parámetro**       | **Descripción**                                              |
|---------------------|--------------------------------------------------------------|
| `-i hosts`          | Especifica el fichero de inventario                          |
| `-u vagrant`        | Usuario SSH con el que conectarse a los nodos                |
| `playbook.yml`      | Nombre del fichero playbook a ejecutar                       |

> 💡 El usuario `-u vagrant` coincide con `ansible_user=vagrant` del inventario,
> por lo que en este caso es redundante pero válido para sobreescribir si fuera necesario.

---

## 💡 Conceptos clave aprendidos

| **Concepto**       | **Descripción**                                                                 |
|--------------------|---------------------------------------------------------------------------------|
| `notify`           | Directiva en una task que marca un handler para ejecutarse si hubo cambio       |
| `handlers`         | Tareas especiales que solo se ejecutan si fueron notificadas                    |
| Idempotencia       | El handler no se ejecuta si no hubo cambio real → evita reinicios innecesarios  |
| Ejecución diferida | Los handlers se ejecutan al **final del play**, no inmediatamente               |
| Deduplicación      | Si varias tasks notifican el mismo handler, este se ejecuta **una sola vez**    |

---

## 🧠 ¿Por qué usar Notify + Handlers?

Sin handlers, tendrías que reiniciar el servicio en cada ejecución del
playbook, independientemente de si algo cambió. Con este patrón:

- ✅ El servicio **solo se reinicia cuando es necesario**.
- ✅ El playbook es **más seguro y predecible**.
- ✅ Se evitan **interrupciones de servicio innecesarias** en producción.
- ✅ El código es **más limpio y reutilizable**.

---

## 📁 Estructura de ficheros del ejemplo

```
006_notify_handlers/
├── hosts           # Inventario con los 3 grupos de nodos
├── playbook.yml    # Playbook principal con tasks y handlers
└── README.md       # (este fichero)
```
