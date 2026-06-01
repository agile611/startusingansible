# 🚀 Ansible Example 000 — Initial Example

Este es el **ejemplo inicial de Ansible**: una primera automatización que conecta con todos los
servidores del inventario, ejecuta el comando `hostname` y muestra el nombre de cada máquina por
pantalla. Es el "Hola Mundo" de Ansible.

---

## 🗂️ Inventario (`hosts`)

El fichero `hosts` define los grupos de máquinas y las variables globales de conexión.

### Variables globales (`[all:vars]`)

| Variable | Valor | Descripción |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Fuerza el uso de Python 3 en los hosts remotos |
| `ansible_user` | `vagrant` | Usuario SSH con el que se conecta Ansible |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clave privada SSH para autenticación sin contraseña |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Evita la verificación del fingerprint del host (útil en entornos de laboratorio) |

### Grupos de hosts

| Grupo | IP |
|---|---|
| `[database]` | `192.168.11.20` |
| `[loadbalancer]` | `192.168.11.30` |
| `[webserver]` | `192.168.11.40` |

---

## 📄 El Playbook (`000_initial_example.yml`)

```yaml
---
  - hosts: all
    tasks:
      - name: get server hostname
        command: hostname
        register: hostname_output
      - name: print hostname
        debug:
          msg: "The hostname of the server is {{ hostname_output.stdout }}"
```

---

## 🔍 Qué hace el Playbook paso a paso

### 1. Selección de hosts (`hosts: all`)

```yaml
- hosts: all
```

- Le indica a Ansible que ejecute el playbook en **todas las máquinas** definidas en el inventario.
- En este caso actuará sobre los tres servidores: `192.168.11.20`, `192.168.11.30` y `192.168.11.40`.

---

### 2. Ejecutar el comando `hostname` en remoto y guardar el resultado (`command` + `register`)

```yaml
- name: get server hostname
  command: hostname
  register: hostname_output
```

- Usa el módulo **`command`** para ejecutar el comando Linux `hostname` directamente en cada servidor remoto.
- El módulo `command` ejecuta comandos de shell sin pasar por un intérprete (`/bin/sh`), lo que lo hace
  más seguro y predecible que el módulo `shell`.
- **`register: hostname_output`** guarda el resultado completo de la ejecución en la variable `hostname_output`.
  Esta variable contiene:
  - `hostname_output.stdout`: la salida estándar del comando (el nombre del host)
  - `hostname_output.stderr`: la salida de errores (si los hay)
  - `hostname_output.rc`: el código de retorno (0 si fue exitoso)

---

### 3. Mostrar el hostname por pantalla (`debug`)

```yaml
- name: print hostname
  debug:
    msg: "The hostname of the server is {{ hostname_output.stdout }}"
```

- Usa el módulo **`debug`** para imprimir información en la salida del terminal.
- Accede a **`hostname_output.stdout`** para obtener el nombre del host capturado en la tarea anterior.
- Usa la sintaxis **Jinja2** (`{{ ... }}`) para interpolar variables dentro del mensaje.
- El resultado se muestra de forma clara y personalizada en la terminal: `"The hostname of the server is [hostname]"`.

> 💡 **¿Qué es `register`?**
> El atributo `register` captura la salida completa de una tarea en una variable que puedes reutilizar
> en tareas posteriores. Es fundamental en Ansible para:
> - Capturar resultados de comandos
> - Usar salidas como entrada en tareas siguientes
> - Validar resultados con condiciones (`when`)
> - Mostrar información específica de forma personalizada

---

## ▶️ Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant examples/000_initial_example/000_initial_example.yml
```

| Parámetro | Descripción |
|---|---|
| `ansible-playbook` | Comando principal para ejecutar un playbook |
| `-i hosts` | Especifica el fichero de inventario (`hosts`) |
| `-u vagrant` | Usuario SSH con el que conectarse a los hosts remotos |
| `examples/000_initial_example/000_initial_example.yml` | Ruta al fichero playbook a ejecutar |

> **Nota:** Como el inventario ya define `ansible_user=vagrant`, el flag `-u vagrant` es redundante
> pero no genera ningún conflicto.

---

## 📊 Flujo de ejecución

```
Tu máquina (nodo de control)
        │
        ├──► SSH → 192.168.11.20 (database)   → ejecuta hostname → muestra resultado
        ├──► SSH → 192.168.11.30 (loadbalancer) → ejecuta hostname → muestra resultado
        └──► SSH → 192.168.11.40 (webserver)   → ejecuta hostname → muestra resultado
```

Ansible se conecta a los tres servidores **en paralelo** (por defecto, en lotes de 5 hosts),
ejecuta las tareas en cada uno y devuelve los resultados ordenados en la terminal.

---

## 💡 Conceptos clave del ejemplo

- **Playbook**: la "receta" escrita en YAML que describe qué tareas ejecutar y en qué máquinas.
- **Inventario**: la "agenda de contactos" que lista los hosts y cómo conectarse a ellos.
- **`hosts: all`**: selector que apunta a todos los hosts del inventario.
- **Módulo `command`**: ejecuta comandos en el host remoto de forma segura sin shell intermedio.
- **Módulo `debug`**: imprime variables o mensajes en la salida de Ansible, muy útil para verificar valores.
- **`ansible_facts`**: diccionario con información del sistema recopilada automáticamente al conectarse.
- **Idempotencia**: aunque `command` no es idempotente por naturaleza, en este caso solo lee
  información (no modifica nada), por lo que es seguro ejecutarlo múltiples veces.

---

## 🗃️ Estructura de ficheros del ejemplo

```
startusingansible/
├── hosts                                        # Inventario (raíz del proyecto)
└── examples/
    └── 000_initial_example/
        └── 000_initial_example.yml              # Playbook principal
```
