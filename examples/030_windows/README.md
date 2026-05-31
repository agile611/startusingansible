# 📋 Ejemplo 030 — `windows`: Gestión de máquinas Windows con Ansible y WinRM

## 🧭 Descripción general

Este ejemplo marca un **cambio de paradigma** respecto a todos los ejemplos anteriores: por primera vez, Ansible gestiona un nodo **Windows** en lugar de Linux. El salto conceptual es importante — Ansible no puede usar SSH para conectarse a Windows, sino que utiliza **WinRM** (Windows Remote Management), el protocolo nativo de administración remota de Microsoft. Además, los módulos cambian completamente: en lugar de `apt`, `service` o `copy`, se usan módulos del namespace `win_*` (`win_ping`, `win_file`, `win_get_url`, `win_package`, `win_shell`).

El caso de uso es deliberadamente concreto y visual: el playbook instala **Google Chrome** en una máquina Windows de forma completamente automatizada — descarga el instalador, lo ejecuta en silencio, y verifica que la instalación fue exitosa. Es el equivalente Windows del "Hello World" de Ansible: demuestra que el canal de comunicación WinRM funciona y que los módulos `win_*` pueden gestionar software en el sistema operativo de Microsoft.

Este ejemplo es **independiente** del stack Linux de los ejemplos anteriores (MySQL + Apache + Nginx). Tiene su propio inventario (`all-hosts`) y su propio playbook (`windows.yml`). El fichero `hosts` Linux del enunciado no se usa aquí.

---

## ⚠️ Advertencias previas

> - La máquina virtual Windows debe tener la red configurada en modo **Privado** (no Público). Windows bloquea WinRM en redes públicas por seguridad. Si está en modo Público, cámbialo antes de continuar.
> - Este ejemplo usa **autenticación básica** y **conexiones no cifradas** (HTTP sobre el puerto 5985). Esto es aceptable en un entorno de laboratorio/desarrollo, pero **nunca debe usarse en producción**.
> - Para producción: usar HTTPS (puerto 5986), certificados válidos y autenticación Kerberos o NTLM.

---

## 🗂️ Estructura del proyecto

```
030_windows/
├── README.md           # Instrucciones de configuración de WinRM
├── all-hosts           # ⭐ Inventario para la máquina Windows
└── windows.yml         # ⭐ Playbook: ping + instalar Google Chrome
```

Este ejemplo es minimalista por diseño: no hay roles, no hay `group_vars`, no hay `site.yml`. El foco está en demostrar la conexión y los módulos `win_*`, no en la estructura del proyecto.

---

## 🔧 Configuración previa de la máquina Windows

Antes de ejecutar cualquier playbook, la máquina Windows debe tener WinRM habilitado y un usuario administrador disponible. Sigue estos pasos en orden.

### Paso 1 — Habilitar WinRM en la máquina Windows

Ejecuta el siguiente script en **PowerShell como Administrador** en la máquina Windows:

```powershell
# Habilita WinRM y configura la autenticación básica (solo para pruebas/lab)
winrm quickconfig -force
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Permite conexiones no cifradas y autenticación básica
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true

# Abre el puerto 5985 en el firewall de Windows (HTTP)
netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985

# Crea regla del firewall persistente para el puerto 5985
New-NetFirewallRule -Name "WinRM HTTP" -DisplayName "WinRM HTTP" `
  -Enabled True -Direction Inbound -Protocol TCP -Localport 5985 -Action Allow
```

### ¿Qué hace cada comando?

| **Comando** | **Efecto** |
|---|---|
| `winrm quickconfig -force` | Activa el servicio WinRM y lo configura con valores por defecto |
| `AllowUnencrypted="true"` | Permite tráfico HTTP sin cifrar (necesario para puerto 5985) |
| `Auth\Basic="true"` | Habilita autenticación con usuario/contraseña en texto plano |
| `netsh advfirewall` | Abre el puerto 5985 en el firewall de Windows Defender |
| `New-NetFirewallRule` | Crea una regla de firewall persistente con PowerShell |

---

### Paso 2 — Crear un usuario administrador o usar uno existente

Asegúrate de tener un usuario con **privilegios de administrador** en la máquina Windows. Recuerda la contraseña — la necesitarás para configurar el inventario de Ansible en el siguiente paso.

---

### Paso 3 — Instalar `pywinrm` en el nodo de control

El nodo de control (la máquina Linux/Mac desde donde se ejecuta Ansible) necesita la librería Python `pywinrm` para hablar el protocolo WinRM:

```bash
pip install pywinrm
```

---

## 📋 Fichero `all-hosts` — El inventario Windows

El inventario de este ejemplo es completamente diferente al de los ejemplos Linux. En lugar de claves SSH, se usan credenciales de usuario Windows y el protocolo WinRM:

```ini
[windows]
win101 ansible_host=192.168.1.175

[windows:vars]
ansible_user=vboxuser
ansible_password=changeme
ansible_port=5985
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
```

Para un entorno con usuario `Administrador`, el inventario tendría este aspecto:

```ini
[windows]
mi_windows_server ansible_host=192.168.1.100

[windows:vars]
ansible_user=Administrador
ansible_password=TuContraseña
ansible_port=5985
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
```

### Análisis de las variables de conexión

| **Variable** | **Valor** | **Significado** |
|---|---|---|
| `ansible_host` | `192.168.1.175` | IP de la máquina Windows (VirtualBox) |
| `ansible_user` | `vboxuser` | Usuario administrador de Windows |
| `ansible_password` | `changeme` | Contraseña en texto plano (⚠️ solo para lab) |
| `ansible_port` | `5985` | Puerto WinRM HTTP (no cifrado) |
| `ansible_connection` | `winrm` | ⭐ Protocolo WinRM en lugar de SSH |
| `ansible_winrm_server_cert_validation` | `ignore` | Ignora la validación del certificado SSL (lab) |

### Comparativa: inventario Linux vs. inventario Windows

| **Parámetro** | **Linux (ejemplos 025-029)** | **Windows (ejemplo 030)** |
|---|---|---|
| **Protocolo** | SSH (implícito) | `ansible_connection=winrm` |
| **Puerto** | 22 (SSH) | `ansible_port=5985` (WinRM HTTP) |
| **Autenticación** | Clave SSH privada | `ansible_password` (básica) |
| **Módulos** | `apt`, `service`, `copy`... | `win_ping`, `win_file`, `win_package`... |
| **Python en nodo** | `ansible_python_interpreter` | No necesario (WinRM nativo) |

---

## 📄 `windows.yml` — El playbook

```yaml
- name: Ping a Máquina Windows
  hosts: windows
  tasks:
    - name: Ping the Windows machine
      win_ping:
      register: ping_result

    - name: Display the ping result
      debug:
        var: ping_result

    - name: Create folder C:\Temp if it does not exist
      win_file:
        path: C:\Temp
        state: directory

    - name: Download Google Chrome installer
      win_get_url:
        url: https://dl.google.com/chrome/install/375.126/chrome_installer.exe
        dest: C:\Temp\chrome_installer.exe

    - name: Install Google Chrome
      win_package:
        path: C:\Temp\chrome_installer.exe
        arguments: /silent /install
        state: present

    - name: Ensure Google Chrome is installed
      win_shell: |
        $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        if (Test-Path $chromePath) {
          Write-Output "Google Chrome is installed."
        } else {
          Write-Output "Google Chrome is not installed."
          exit 1
        }
      register: chrome_check

    - name: Display the Chrome Check result
      debug:
        var: chrome_check
```

### Flujo de ejecución tarea a tarea

```
windows.yml
│
├── [1] win_ping          → Verifica que WinRM responde (equivalente a SSH ping)
├── [2] debug             → Muestra el resultado del ping en la salida de Ansible
├── [3] win_file          → Crea C:\Temp si no existe (idempotente)
├── [4] win_get_url       → Descarga chrome_installer.exe desde Google
├── [5] win_package       → Ejecuta el instalador en modo silencioso
├── [6] win_shell         → Script PowerShell: verifica que chrome.exe existe
└── [7] debug             → Muestra el resultado de la verificación
```

---

## 🛠️ Los módulos `win_*` en detalle

### `win_ping` — Verificación de conectividad

```yaml
- name: Ping the Windows machine
  win_ping:
  register: ping_result
```

El equivalente Windows de `ping` en Ansible. No es un ping ICMP — es una llamada WinRM que verifica que:
1. El servicio WinRM está activo en el nodo Windows.
2. Las credenciales (`ansible_user` / `ansible_password`) son correctas.
3. El canal de comunicación funciona end-to-end.

Devuelve `{"ping": "pong"}` si todo está correcto. El resultado se guarda en `ping_result` y se muestra con `debug`.

Para probar la conexión de forma aislada antes de ejecutar el playbook completo:

```bash
ansible windows -i all-hosts -m win_ping
```

---

### `win_file` — Gestión de ficheros y directorios

```yaml
- name: Create folder C:\Temp if it does not exist
  win_file:
    path: C:\Temp
    state: directory
```

Equivalente Windows del módulo `file` de Linux. Con `state: directory` crea el directorio si no existe. Es **idempotente**: si `C:\Temp` ya existe, Ansible no hace nada y reporta `ok` en lugar de `changed`.

---

### `win_get_url` — Descarga de ficheros desde URL

```yaml
- name: Download Google Chrome installer
  win_get_url:
    url: https://dl.google.com/chrome/install/375.126/chrome_installer.exe
    dest: C:\Temp\chrome_installer.exe
```

Equivalente Windows del módulo `get_url` de Linux. Descarga el instalador de Chrome directamente en la máquina Windows gestionada — Ansible no actúa como intermediario, el nodo Windows hace la descarga directamente desde Google.

---

### `win_package` — Instalación de software (.exe, .msi)

```yaml
- name: Install Google Chrome
  win_package:
    path: C:\Temp\chrome_installer.exe
    arguments: /silent /install
    state: present
```

El módulo más potente de este playbook. Gestiona la instalación de paquetes Windows en formato `.exe` o `.msi`. Los parámetros clave:

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `path` | `C:\Temp\chrome_installer.exe` | Ruta al instalador (local en el nodo Windows) |
| `arguments` | `/silent /install` | Flags del instalador: modo silencioso, sin GUI |
| `state` | `present` | Instalar si no está instalado; no reinstalar si ya lo está |

El flag `/silent /install` es específico del instalador de Chrome. Cada instalador `.exe` tiene sus propios argumentos de línea de comandos para instalación desatendida.

---

### `win_shell` — Ejecución de scripts PowerShell

```yaml
- name: Ensure Google Chrome is installed
  win_shell: |
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
      Write-Output "Google Chrome is installed."
    } else {
      Write-Output "Google Chrome is not installed."
      exit 1
    }
  register: chrome_check
```

Ejecuta un bloque de código **PowerShell** directamente en la máquina Windows. Es el equivalente del módulo `shell` de Linux, pero para PowerShell.

El script verifica la existencia de `chrome.exe` en la ruta de instalación estándar:
- Si existe → imprime `"Google Chrome is installed."` y termina con código 0 (éxito).
- Si no existe → imprime `"Google Chrome is not installed."` y termina con `exit 1` (fallo), lo que hace que Ansible marque la tarea como **failed**.

El resultado completo (stdout, stderr, código de retorno) se guarda en `chrome_check` y se muestra con `debug`.

---

## 🚀 Comandos de ejecución

### Verificar conectividad con `win_ping`

```bash
ansible windows -i all-hosts -m win_ping
```

Prueba la conexión WinRM antes de ejecutar el playbook completo. Debe devolver `"ping": "pong"`.

### Ejecutar el playbook completo

```bash
ansible-playbook -i all-hosts windows.yml
```

Ejecuta las 7 tareas en orden: ping, crear directorio, descargar Chrome, instalar Chrome, verificar instalación.

### Ejecutar con verbose para ver la salida de PowerShell

```bash
ansible-playbook -i all-hosts windows.yml -v
```

Con `-v`, Ansible muestra el contenido de los módulos `debug` y la salida estándar de `win_shell` en tiempo real.

### Listar las tareas del playbook sin ejecutar

```bash
ansible-playbook -i all-hosts windows.yml --list-tasks
```

---

## 🏗️ Comparativa: Ansible para Linux vs. Ansible para Windows

| **Aspecto** | **Linux (ejemplos 025-029)** | **Windows (ejemplo 030)** |
|---|---|---|
| **Protocolo de conexión** | SSH | WinRM |
| **Puerto** | 22 | 5985 (HTTP) / 5986 (HTTPS) |
| **Autenticación** | Clave SSH | Usuario + contraseña |
| **Módulo de ping** | `ping` | `win_ping` / `ansible.windows.win_ping` |
| **Gestión de ficheros** | `file`, `copy` | `win_file`, `win_copy` |
| **Descarga de ficheros** | `get_url` | `win_get_url` |
| **Instalación de paquetes** | `apt`, `yum` | `win_package`, `win_chocolatey` |
| **Ejecución de comandos** | `shell`, `command` | `win_shell`, `win_command` |
| **Scripting** | Bash | PowerShell |
| **Python en el nodo** | Requerido | No requerido |
| **Namespace de módulos** | `ansible.builtin.*` | `ansible.windows.win_*` |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **WinRM como protocolo de gestión remota de Windows**: WinRM es el equivalente Windows de SSH. Ansible lo usa a través de la librería `pywinrm` (instalada en el nodo de control). El nodo Windows no necesita Python — WinRM es nativo del sistema operativo desde Windows Server 2008 R2 / Windows 7.

- **`ansible_connection=winrm`**: Esta variable en el inventario es el interruptor que cambia completamente el comportamiento de Ansible. Sin ella, Ansible intentaría conectarse por SSH y fallaría. Con ella, toda la comunicación pasa por WinRM.

- **Módulos `win_*`**: Los módulos del namespace `win_*` (o `ansible.windows.win_*` con FQCN) son el equivalente Windows de los módulos estándar de Linux. No son intercambiables — `apt` no funciona en Windows, `win_package` no funciona en Linux.

- **PowerShell como lenguaje de scripting**: `win_shell` ejecuta PowerShell, no Bash. Esto abre todo el ecosistema de PowerShell para la automatización de Windows: gestión de Active Directory, registro de Windows, servicios, IIS, etc.

- **Idempotencia en Windows**: Los módulos `win_*` mantienen el principio de idempotencia de Ansible. `win_file` con `state: directory` no falla si el directorio ya existe; `win_package` con `state: present` no reinstala si el software ya está instalado.

- **Inventario separado por plataforma**: Este ejemplo tiene su propio fichero `all-hosts` completamente diferente al `hosts` de los ejemplos Linux. En proyectos reales con nodos mixtos (Linux + Windows), se suelen usar grupos separados (`[linux]`, `[windows]`) en el mismo inventario, con variables de conexión diferentes para cada grupo.

- **Seguridad en producción**: El ejemplo usa HTTP (puerto 5985) y autenticación básica — aceptable solo en laboratorio. En producción se debe usar HTTPS (puerto 5986) con certificados válidos y autenticación Kerberos o CredSSP.

---

## 📚 Referencias

- [Ansible Docs — Windows Remote Management](https://docs.ansible.com/ansible/latest/os_guide/windows_winrm.html)
- [Ansible Docs — Setting up a Windows Host](https://docs.ansible.com/ansible/latest/os_guide/windows_setup.html)
- [Ansible Docs — `ansible.windows` collection](https://docs.ansible.com/ansible/latest/collections/ansible/windows/index.html)
- [Ansible Docs — `win_ping` module](https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_ping_module.html)
- [Ansible Docs — `win_package` module](https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_package_module.html)
- [Microsoft Docs — WinRM Architecture](https://learn.microsoft.com/en-us/windows/win32/winrm/windows-remote-management-architecture)
- [pywinrm — Python WinRM library](https://github.com/diyan/pywinrm)
