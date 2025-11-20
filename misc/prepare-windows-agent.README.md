# Preparación del Windows Agent para Ansible

**Descripción**: Este fichero contiene los comandos necesarios para preparar un host Windows para ser gestionado por Ansible usando WinRM (HTTP no cifrado / Autenticación Basic).

**Requisitos previos en el agent Windows**:
- Windows con PowerShell ejecutándose como administrador.
- Conexión de red que permita acceso al puerto `5985` (WinRM HTTP) des del agente de Ansible.

**Pasos**:
1. **Cambiar red a privada**: En la configuración de Red de Windows, establecer el perfil de red de "Pública" a "Privada".
2. **Habilitar WinRM**: Ejecutar en PowerShell elevado a nivel administrador:

```powershell
winrm quickconfig -force
```

3. **Permitir autenticación Basic** (necesario si usarás credenciales básicas):

```powershell
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
```

4. **Permitir tráfico no cifrado** (si no usas HTTPS/WinRM cifrado):

```powershell
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
```

5. **Abrir puerto WinRM en el firewall**:

```powershell
New-NetFirewallRule -Name "WinRM HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow
```

**Notas de seguridad**:
- Habilitar `AllowUnencrypted` y `Basic` significa que las credenciales viajan en claro si no usas túnel/capa adicional. Evítalo en entornos de producción.
- Para un entorno más seguro, configura WinRM sobre HTTPS (puerto 5986) y usa certificados, o usa un túnel VPN/SSH para proteger el tráfico.
- Asegúrate de limitar el acceso al puerto `5985` mediante reglas de firewall o controles de red (IP whitelist).

**Comprobación**:
- Desde el controlador Ansible (Linux/macOS), prueba conectividad con `winrm` usando un módulo o una tarea `ping` de Ansible, o bien con `Test-NetConnection` desde otro host Windows:

```powershell
Test-NetConnection -ComputerName <IP-o-hostname> -Port 5985
```

**Deshacer/Restaurar**:
- Para deshabilitar Basic auth:

```powershell
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
```

- Para volver a bloquear tráfico no cifrado:

```powershell
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
```

- Para eliminar la regla de firewall creada:

```powershell
Remove-NetFirewallRule -Name "WinRM HTTP"
```

**Comandos antiguos del tirón**
```powershell
Preparación del Windows Agent para Ansible:
1) Poner el Windows de Red Publica a Privada (En configuración de Red)
2) winrm quickconfig -force
3) Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
4) Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
5) New-NetFirewallRule -Name "WinRM HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow
```