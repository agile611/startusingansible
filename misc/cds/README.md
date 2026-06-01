# 📋 `misc/` — Colección de ficheros de referencia y ejemplos auxiliares

## 🧭 Descripción general

El directorio `misc/` no es un ejemplo ejecutable de Ansible con un playbook principal — es una **biblioteca de referencia**. Contiene ficheros auxiliares, plantillas de configuración y variantes de inventario que complementan los ejemplos numerados de la serie `startusingansible`.

Aquí encontrarás respuestas a preguntas prácticas muy habituales: *¿Cómo escribo el inventario en formato YAML en lugar de INI? ¿Cómo uso nombres DNS en lugar de IPs? ¿Cómo incluyo el nodo de control en el inventario? ¿Cómo es un `nginx.conf` completo o un VirtualHost de Apache?* Cada fichero es un ejemplo autocontenido listo para copiar y adaptar.

---

## 🗂️ Estructura completa del directorio

```
misc/
├── all-hosts           # Inventario INI que incluye el nodo de control Ansible
├── dns-hosts           # Inventario INI con nombres DNS en lugar de IPs directas
├── hosts-yaml          # Inventario en formato YAML (alternativa al formato INI)
├── example-certs.yml   # Playbook de ejemplo: gestión de certificados SSL con Let's Encrypt
├── hosts.conf          # Plantilla de VirtualHost para Apache2
└── nginx.conf          # Configuración completa de referencia para Nginx
```

---

## 📄 `all-hosts` — Inventario con el nodo de control incluido

Este fichero muestra cómo incluir el **propio nodo de control Ansible** en el inventario, añadiendo un grupo `[control]` con `ansible_connection=local`.

```ini
[control]
192.168.11.10 ansible_connection=local

[database]
192.168.11.20

[loadbalancer]
192.168.11.30

[webserver]
192.168.11.40
```

### ¿Por qué `ansible_connection=local`?

Cuando Ansible gestiona el propio nodo donde se ejecuta, no necesita SSH — puede ejecutar las tareas directamente en el proceso local. La variable `ansible_connection=local` le indica exactamente eso: *"no abras una conexión SSH, ejecuta aquí mismo"*.

| **Parámetro** | **Valor** | **Significado** |
|---|---|---|
| `[control]` | Grupo nuevo | Agrupa el nodo de control Ansible |
| `192.168.11.10` | IP del nodo de control | La máquina donde corre `ansible-playbook` |
| `ansible_connection=local` | Conexión local | Evita SSH, ejecuta tareas en el proceso local |

### Comando de uso

```bash
# Ejecutar solo en el nodo de control
ansible-playbook -i all-hosts -u vagrant site.yml --limit control

# Ejecutar en todos los grupos incluyendo el control
ansible-playbook -i all-hosts -u vagrant site.yml
```

> **Nota práctica**: Este patrón es útil para playbooks que configuran el propio nodo de control (instalar dependencias, configurar `ansible.cfg`, gestionar claves SSH, etc.).

---

## 📄 `dns-hosts` — Inventario con nombres DNS (aliases)

Este fichero muestra cómo usar **nombres de host** (`db_01`, `lb_01`, `ws_01`) en lugar de IPs directas, vinculando cada nombre a su IP real mediante `ansible_host`.

```ini
[all:vars] # Definir el intérprete de Python para todos los hosts
ansible_python_interpreter=/usr/bin/python3.12

[database] # Definir el grupo de bases de datos
db_01 ansible_host=192.168.11.20

[loadbalancer] # Definir el grupo de balanceadores de carga
lb_01 ansible_host=192.168.11.30

[webserver] # Definir el grupo de servidores web
ws_01 ansible_host=192.168.11.40
```

### ¿Por qué usar nombres en lugar de IPs?

| **Aspecto** | **Solo IP** | **Nombre + `ansible_host`** |
|---|---|---|
| **Legibilidad** | `192.168.11.20` | `db_01` |
| **Mantenimiento** | Cambiar IP en múltiples sitios | Cambiar solo `ansible_host` en el inventario |
| **Referencia en playbooks** | `hosts: 192.168.11.20` | `hosts: db_01` o `hosts: database` |
| **Integración con DNS real** | No | Sí — el nombre puede resolverse por DNS |

### Diferencia respecto al `hosts` principal

```ini
# hosts principal (IPs directas)
[database]
192.168.11.20

# dns-hosts (nombre + IP)
[database]
db_01 ansible_host=192.168.11.20
```

La variable `ansible_host` le dice a Ansible *"para conectarte a `db_01`, usa la IP `192.168.11.20`"*. En los playbooks y roles, puedes referenciar el host como `db_01` en lugar de la IP.

### Comando de uso

```bash
ansible-playbook -i dns-hosts -u vagrant site.yml
ansible-playbook -i dns-hosts -u vagrant site.yml --limit db_01
ansible-playbook -i dns-hosts -u vagrant site.yml --limit database
```

---

## 📄 `hosts-yaml` — Inventario en formato YAML

Este es el mismo inventario de la serie pero escrito en **formato YAML** en lugar del formato INI clásico. Ambos formatos son equivalentes — Ansible los soporta nativamente.

```yaml
all:
  ansible_python_interpreter: /usr/bin/python3.12

database:
  hosts:
    db_01:
      ansible_host: 192.168.11.20
      ansible_connection: ssh
      ansible_user: vagrant
      ansible_ssh_password: vagrant

loadbalancer:
  hosts:
    lb_01:
      ansible_host: 192.168.11.30
      ansible_connection: ssh
      ansible_user: vagrant
      ansible_ssh_password: vagrant

webserver:
  hosts:
    ws_01:
      ansible_host: 192.168.11.40
      ansible_connection: ssh
      ansible_user: vagrant
      ansible_ssh_password: vagrant
    ws_02:
      ansible_host: 192.168.11.50
      ansible_connection: ssh
      ansible_user: vagrant
      ansible_ssh_password: vagrant
```

### Características destacadas

| **Elemento** | **Valor** | **Significado** |
|---|---|---|
| `all.ansible_python_interpreter` | `/usr/bin/python3.12` | Python 3.12 para todos los hosts |
| `ansible_connection: ssh` | `ssh` | Conexión explícita por SSH (valor por defecto, pero aquí documentado) |
| `ansible_ssh_password` | `vagrant` | Autenticación por contraseña en lugar de clave SSH |
| `ws_02` | `192.168.11.50` | **Segundo webserver** — no presente en el inventario INI principal |

### Comparativa formato INI vs YAML

```ini
# Formato INI (clásico)
[webserver]
192.168.11.40
```

```yaml
# Formato YAML (equivalente)
webserver:
  hosts:
    ws_01:
      ansible_host: 192.168.11.40
```

El formato YAML es más **verboso** pero más **explícito** — cada variable de conexión está documentada junto al host. Es preferido en entornos grandes con muchos hosts y configuraciones heterogéneas.

### Comando de uso

```bash
ansible-playbook -i hosts-yaml -u vagrant site.yml
ansible-playbook -i hosts-yaml -u vagrant site.yml --limit webserver
ansible-playbook -i hosts-yaml -u vagrant site.yml --limit ws_01
```

> ⚠️ **Importante**: Este inventario usa `ansible_ssh_password` (contraseña). Para que funcione, necesitas tener instalado el paquete `sshpass` en el nodo de control: `apt-get install sshpass`.

---

## 📄 `example-certs.yml` — Playbook: Certificados SSL con Let's Encrypt

Este playbook demuestra cómo gestionar certificados SSL/TLS de forma automatizada usando la colección `community.crypto` de Ansible Galaxy.

```yaml
- name: test para autenticar en máquina con certificado
  hosts: all
  become: yes
  vars:
    domain_name: "example.com"
    cert_path: "/etc/ssl/certs/example.com.crt"
    key_path: "/etc/ssl/private/example.com.key"
  tasks:
    - name: Asegurarse que existe la clave dominio
      community.crypto.openssl_privatekey:
        path: "{{ key_path }}"
        size: 2048
        state: present

    - name: Obtener certificado via ACME (Let's Encrypt)
      community.crypto.acme_certificate:
        account_key_src: "/etc/ssl/private/account.key"
        csr:
          common_name: "{{ domain_name }}"
        fullchain_dest: "{{ cert_path }}"
        privatekey_dest: "{{ key_path }}"
        provider: letsencrypt
        terms_agreed: true
        state: present
```

### Flujo de ejecución

```
example-certs.yml  (hosts: all → database + loadbalancer + webserver)
│
├── [vars]
│       ├── domain_name: "example.com"
│       ├── cert_path:   "/etc/ssl/certs/example.com.crt"
│       └── key_path:    "/etc/ssl/private/example.com.key"
│
├── [1] community.crypto.openssl_privatekey
│       └── Crea la clave privada RSA de 2048 bits en {{ key_path }}
│           Si ya existe, no la sobreescribe (idempotente)
│
└── [2] community.crypto.acme_certificate
        ├── Usa la cuenta ACME de Let's Encrypt (/etc/ssl/private/account.key)
        ├── Solicita certificado para "example.com"
        ├── Guarda el certificado completo (fullchain) en {{ cert_path }}
        └── Acepta los términos de servicio de Let's Encrypt automáticamente
```

### Módulos de la colección `community.crypto`

| **Módulo** | **Función** |
|---|---|
| `community.crypto.openssl_privatekey` | Genera y gestiona claves privadas RSA/ECDSA |
| `community.crypto.acme_certificate` | Obtiene/renueva certificados via protocolo ACME (Let's Encrypt, ZeroSSL, etc.) |

### Prerequisitos

```bash
# Instalar la colección community.crypto en el nodo de control
ansible-galaxy collection install community.crypto
```

### Comando de ejecución

```bash
ansible-playbook -i hosts -u vagrant example-certs.yml
ansible-playbook -i hosts -u vagrant example-certs.yml --limit webserver
```

> ⚠️ **Importante**: Este playbook requiere que el dominio `example.com` sea **públicamente accesible** desde Internet para que Let's Encrypt pueda validar la propiedad del dominio (challenge ACME HTTP-01 o DNS-01). En un laboratorio local con Vagrant, este playbook sirve como referencia de sintaxis — no funcionará con `example.com` real.

---

## 📄 `hosts.conf` — Plantilla VirtualHost para Apache2

Este fichero es una **plantilla de referencia** de configuración de VirtualHost para Apache2. No es un playbook — es el fichero de configuración estático que se desplegaría con el módulo `copy` o `template` en los ejemplos de Apache.

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@exemple.com
    ServerName exemple.com
    ServerAlias www.exemple.com

    DocumentRoot /var/www/exemple.com/public_html

    ErrorLog ${APACHE_LOG_DIR}/exemple.com_error.log
    CustomLog ${APACHE_LOG_DIR}/exemple.com_access.log combined

    <Directory /var/www/exemple.com/public_html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

### Anatomía del VirtualHost

| **Directiva** | **Valor** | **Función** |
|---|---|---|
| `<VirtualHost *:80>` | Puerto 80 | Escucha en todas las IPs en el puerto HTTP estándar |
| `ServerAdmin` | `webmaster@exemple.com` | Email del administrador (aparece en páginas de error) |
| `ServerName` | `exemple.com` | Nombre principal del dominio |
| `ServerAlias` | `www.exemple.com` | Alias adicional — `www.` redirige al mismo VirtualHost |
| `DocumentRoot` | `/var/www/exemple.com/public_html` | Directorio raíz del sitio web |
| `ErrorLog` | `${APACHE_LOG_DIR}/...` | Fichero de log de errores |
| `CustomLog` | `${APACHE_LOG_DIR}/...` | Fichero de log de accesos (formato `combined`) |
| `AllowOverride All` | `All` | Permite `.htaccess` — necesario para WordPress, Laravel, etc. |
| `Require all granted` | `granted` | Permite acceso a todos los clientes (sin restricción de IP) |

### Cómo usar este fichero con Ansible

```yaml
# En un playbook o rol de Apache:
- name: Desplegar VirtualHost de Apache
  copy:
    src: files/hosts.conf
    dest: /etc/apache2/sites-available/exemple.com.conf
    owner: root
    group: root
    mode: '0644'
  notify: Recargar Apache

- name: Activar el sitio
  command: a2ensite exemple.com.conf
  notify: Recargar Apache
```

---

## 📄 `nginx.conf` — Configuración completa de referencia para Nginx

Este fichero es una **configuración Nginx completa y comentada** que sirve como referencia para entender la estructura de `nginx.conf` antes de crear plantillas Jinja2 para los ejemplos de la serie.

```nginx
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;
    gzip_disable "msie6";

    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
            try_files $uri $uri/ =404;
        }
    }
}
```

### Anatomía del `nginx.conf`

| **Bloque / Directiva** | **Función** |
|---|---|
| `user www-data` | Proceso Nginx corre con el usuario `www-data` (sin privilegios root) |
| `worker_processes auto` | Crea un worker por CPU disponible automáticamente |
| `pid /run/nginx.pid` | Fichero PID del proceso maestro Nginx |
| `worker_connections 768` | Máximo de conexiones simultáneas por worker |
| `sendfile on` | Transferencia de ficheros optimizada a nivel de kernel |
| `tcp_nopush on` | Envía cabeceras HTTP y el inicio del fichero en el mismo paquete TCP |
| `keepalive_timeout 65` | Tiempo máximo de espera en conexiones keep-alive (segundos) |
| `gzip on` | Compresión gzip activada para reducir ancho de banda |
| `gzip_disable "msie6"` | Desactiva gzip para Internet Explorer 6 (bug histórico) |
| `listen 80 default_server` | Escucha en IPv4 puerto 80, servidor por defecto |
| `listen [::]:80 default_server` | Escucha en IPv6 puerto 80, servidor por defecto |
| `server_name _` | Comodín — responde a cualquier nombre de host |
| `try_files $uri $uri/ =404` | Busca el fichero, luego el directorio, devuelve 404 si no existe |

### Cómo usar este fichero con Ansible

```yaml
# En un playbook o rol de Nginx:
- name: Desplegar configuración de Nginx
  copy:
    src: files/nginx.conf
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    validate: nginx -t -c %s   # Valida la sintaxis antes de copiar
  notify: Recargar Nginx
```

---

## 🔍 Resumen: ¿Para qué sirve cada fichero?

| **Fichero** | **Tipo** | **Propósito** |
|---|---|---|
| `all-hosts` | Inventario INI | Incluir el nodo de control Ansible en el inventario |
| `dns-hosts` | Inventario INI | Usar nombres DNS/aliases en lugar de IPs directas |
| `hosts-yaml` | Inventario YAML | Alternativa al formato INI — más explícito y estructurado |
| `example-certs.yml` | Playbook | Gestión automatizada de certificados SSL con Let's Encrypt |
| `hosts.conf` | Config Apache | Plantilla de VirtualHost Apache2 lista para copiar/adaptar |
| `nginx.conf` | Config Nginx | Configuración Nginx completa comentada — referencia y base para plantillas Jinja2 |

---

## 💡 Conceptos clave aprendidos

- **Tres formatos de inventario**: Ansible soporta inventarios en formato INI (clásico), YAML (explícito) y dinámico (scripts/plugins). Los tres son equivalentes en funcionalidad — la elección es de preferencia y escala del proyecto.

- **`ansible_connection=local`**: Permite que Ansible gestione el propio nodo de control sin SSH. Imprescindible para playbooks de bootstrapping o configuración del entorno de control.

- **`ansible_host` vs nombre del host**: El nombre del host en el inventario (ej. `db_01`) es el identificador lógico que usas en playbooks y `--limit`. La variable `ansible_host` es la dirección real de conexión (IP o FQDN). Separarlos da flexibilidad para renombrar hosts sin cambiar IPs y viceversa.

- **`community.crypto`**: Colección de Ansible Galaxy que extiende las capacidades criptográficas de Ansible. Permite gestionar el ciclo de vida completo de certificados SSL/TLS (generación de claves, CSRs, obtención via ACME, renovación) de forma idempotente.

- **Validación de configuración antes de desplegar**: El parámetro `validate` del módulo `copy` permite ejecutar un comando de validación sobre el fichero antes de copiarlo al destino. `nginx -t -c %s` valida la sintaxis de Nginx — si falla, Ansible no copia el fichero y no rompe el servicio en producción.

- **`AllowOverride All` en Apache**: Directiva crítica para aplicaciones PHP modernas (WordPress, Laravel, Symfony) que usan `.htaccess` para reescritura de URLs. Sin ella, los permalinks y rutas amigables no funcionan.

---

## 📚 Referencias

- [Ansible Docs — Inventory formats](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Ansible Docs — Behavioral inventory parameters](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Ansible Galaxy — community.crypto](https://galaxy.ansible.com/community/crypto)
- [Ansible Docs — `community.crypto.acme_certificate`](https://docs.ansible.com/ansible/latest/collections/community/crypto/acme_certificate_module.html)
- [Nginx Docs — Beginner's Guide](https://nginx.org/en/docs/beginners_guide.html)
- [Apache Docs — VirtualHost Examples](https://httpd.apache.org/docs/2.4/vhosts/examples.html)
