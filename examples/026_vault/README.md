# 📋 Ejemplo 026 — `vault`: Cifrado de secretos con Ansible Vault

## 🧭 Descripción general

Este ejemplo introduce **Ansible Vault**, el mecanismo nativo de Ansible para cifrar ficheros que contienen información sensible — credenciales de base de datos, claves API, contraseñas, certificados — de forma que puedan almacenarse de forma segura en un repositorio de control de versiones (Git) sin exponer los secretos en texto plano.

La novedad central es que el fichero `group_vars/all`, que en el ejemplo 025 contenía las variables en texto plano, ahora está **completamente cifrado con AES-256**. Su contenido en el repositorio es un bloque de texto cifrado ilegible. Ansible lo descifra automáticamente en tiempo de ejecución cuando se le proporciona la contraseña del vault — ya sea de forma interactiva, mediante un fichero de contraseña, o a través de una variable de entorno. El resto del proyecto (roles, playbooks, plantillas) es idéntico al ejemplo 025: el cifrado es completamente transparente para el resto de la infraestructura.

---

## 🗂️ Estructura del proyecto

```
026_vault/
├── site.yml                          # Orquestador maestro (include)
├── control.yml
├── database.yml                      # Variables leídas de group_vars/all (cifrado)
├── webserver.yml                     # Sin variables inline — roles limpios
├── loadbalancer.yml
├── group_vars/
│   └── all                           # ⭐ NOVEDAD PRINCIPAL: cifrado con AES-256 Vault
├── playbooks/
│   ├── stack_status.yml
│   └── stack_restart.yml
└── roles/
    ├── control/
    │   └── tasks/main.yml
    ├── mysql/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── defaults/main.yml         # Defaults comentados (igual que ejemplo 025)
    ├── apache2/
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    ├── demo_app/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── demo.wsgi.j2          # groups.database[0] como hostname de BD
    └── nginx/
        ├── tasks/main.yml            # ls -l en get active sites (novedad menor)
        ├── handlers/main.yml
        ├── templates/nginx.conf.j2
        └── defaults/main.yml         # Defaults comentados
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

| **Grupo** | **IP** | **Rol(es) asignado(s)** |
|---|---|---|
| `[database]` | `192.168.11.20` | `mysql` |
| `[loadbalancer]` | `192.168.11.30` | `nginx` |
| `[webserver]` | `192.168.11.40` | `apache2` + `demo_app` |

---

## ⭐ NOVEDAD PRINCIPAL: `group_vars/all` cifrado con Ansible Vault

### El fichero tal como aparece en el repositorio

```
$ANSIBLE_VAULT;1.1;AES256
34663065306632666162353539363635666666653431636164316639303935613066643837303234
3330306265323566313134623831613361336262666562340a383330396362383333383462336363
37616534393332313163633063303436653862343431633834396538363739373435396338323162
3230356333323765300a346436343931636134656237613633646662663637333635356563373565
...
```

Este es el contenido real del fichero `group_vars/all` en el repositorio Git. Es completamente ilegible — un bloque de texto hexadecimal cifrado con AES-256. Nadie que acceda al repositorio puede leer las credenciales sin conocer la contraseña del vault.

### Anatomía del encabezado Vault

La primera línea `$ANSIBLE_VAULT;1.1;AES256` es el identificador del formato:

| **Campo** | **Valor** | **Significado** |
|---|---|---|
| `$ANSIBLE_VAULT` | Literal | Identificador: este fichero está cifrado con Vault |
| `1.1` | Versión del formato | Versión del protocolo de cifrado de Ansible Vault |
| `AES256` | Algoritmo | Cifrado simétrico AES de 256 bits |

### Contenido descifrado (inferido del ejemplo 025)

Aunque el contenido cifrado es ilegible, sabemos exactamente qué contiene porque es la evolución directa del ejemplo 025. El fichero descifrado tiene esta estructura:

```yaml
---
# DB from role mysql
db_name: <nombre_de_bd>
db_user: <usuario_de_bd>
db_pass: <contraseña_de_bd>
db_user_host: localhost

# nginx loadbalancer configuration
sites:
  <nombre_del_sitio>:
    frontend: 80
    backend: 80
```

Las credenciales concretas (`db_name`, `db_user`, `db_pass`) y el nombre del sitio Nginx son desconocidas sin la contraseña del vault — que es exactamente el objetivo de este ejemplo.

### ¿Por qué cifrar `group_vars/all`?

Sin Vault, el flujo de trabajo habitual es:

```
group_vars/all (texto plano)  →  Git commit  →  Repositorio remoto
                                                      ↓
                                              Credenciales expuestas
                                              a cualquier persona con
                                              acceso al repositorio
```

Con Vault:

```
group_vars/all (cifrado AES-256)  →  Git commit  →  Repositorio remoto
                                                           ↓
                                                   Solo texto cifrado
                                                   ilegible sin la
                                                   contraseña del vault
                                                           ↓
                                              ansible-playbook --ask-vault-pass
                                                           ↓
                                                   Descifrado en memoria
                                                   durante la ejecución
```

---

## 🔐 Gestión del Vault: comandos esenciales

### Crear un fichero cifrado nuevo

```bash
ansible-vault create group_vars/all
```

Abre el editor por defecto (`$EDITOR`). Al guardar, el fichero se cifra automáticamente. Ansible pide la contraseña del vault interactivamente.

### Cifrar un fichero existente en texto plano

```bash
ansible-vault encrypt group_vars/all
```

Cifra un fichero que ya existe en texto plano. Útil para migrar desde el ejemplo 025 al 026.

### Ver el contenido de un fichero cifrado

```bash
ansible-vault view group_vars/all
```

Muestra el contenido descifrado en el terminal sin modificar el fichero.

### Editar un fichero cifrado

```bash
ansible-vault edit group_vars/all
```

Descifra temporalmente el fichero, abre el editor, y lo vuelve a cifrar al guardar. El fichero nunca existe en texto plano en el disco.

### Descifrar un fichero (convertirlo a texto plano)

```bash
ansible-vault decrypt group_vars/all
```

> ⚠️ **Precaución:** El fichero queda en texto plano en el disco. No hacer `git commit` después de este comando.

### Cambiar la contraseña del vault

```bash
ansible-vault rekey group_vars/all
```

Pide la contraseña actual y la nueva. Vuelve a cifrar el fichero con la nueva contraseña.

### Ver qué variables contiene sin descifrar el fichero

```bash
ansible-vault view group_vars/all
```

---

## 🚀 Comandos de ejecución con Vault

### Despliegue completo — contraseña interactiva

```bash
ansible-playbook -i hosts -u vagrant site.yml --ask-vault-pass
```

Ansible pide la contraseña del vault antes de ejecutar. La introduce el operador en el terminal. Es el método más seguro para uso interactivo.

### Despliegue completo — fichero de contraseña

```bash
# Crear el fichero de contraseña (una sola línea con la contraseña)
echo "mi_contraseña_secreta" > .vault_pass
chmod 600 .vault_pass
echo ".vault_pass" >> .gitignore  # ⚠️ NUNCA hacer commit de este fichero

# Ejecutar el playbook
ansible-playbook -i hosts -u vagrant site.yml --vault-password-file .vault_pass
```

Útil para automatización (CI/CD) donde no hay operador humano para introducir la contraseña.

### Despliegue completo — variable de entorno

```bash
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass
ansible-playbook -i hosts -u vagrant site.yml
```

### Despliegue de componentes individuales

```bash
ansible-playbook -i hosts -u vagrant database.yml --ask-vault-pass
ansible-playbook -i hosts -u vagrant webserver.yml --ask-vault-pass
ansible-playbook -i hosts -u vagrant loadbalancer.yml --ask-vault-pass
```

### Operaciones de mantenimiento

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml --ask-vault-pass
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml --ask-vault-pass
```

### Verificar que el vault está bien formado (sin ejecutar)

```bash
ansible-playbook -i hosts -u vagrant site.yml --ask-vault-pass --list-tasks
```

---

## 📄 Playbooks de componente — Sin cambios respecto a 025

### `site.yml`

```yaml
---
- include: control.yml
- include: database.yml
- include: webserver.yml
- include: loadbalancer.yml
- include: playbooks/stack_status.yml
```

Vuelve a usar `include` (en lugar de `import_playbook` del ejemplo 025). La funcionalidad es la misma para este caso de uso.

### `database.yml`

```yaml
---
- hosts: database
  become: true
  roles:
    - role: mysql
      db_user_name: "{{ db_user }}"
      db_user_pass: "{{ db_pass }}"
      db_user_host: '%'
```

Las variables `{{ db_user }}` y `{{ db_pass }}` se resuelven desde `group_vars/all` — que Ansible descifra automáticamente en tiempo de ejecución. El playbook no sabe ni le importa si las variables vienen de un fichero en texto plano o cifrado.

### `webserver.yml`

```yaml
---
- hosts: webserver
  become: true
  roles:
    - apache2
    - demo_app
```

### `loadbalancer.yml`

```yaml
---
- hosts: loadbalancer
  become: true
  roles:
    - nginx
```

---

## 🛠️ Los Roles en detalle

### 🗄️ Rol `mysql`

#### `roles/mysql/defaults/main.yml`

```yaml
---
#db_name: myapp
#db_user_name: dbuser
#db_user_pass: dbpass
#db_user_host: localhost
```

Defaults comentados — igual que en el ejemplo 025. Todas las variables deben venir del vault.

#### `roles/mysql/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python3-mysqldb

- name: install mysql-server
  apt: name=mysql-server state=present update_cache=yes

- name: chmod 777 /etc/mysql/my.cnf
  command: chmod 777 /etc/mysql/my.cnf
  notify: restart mysql

- name: ensure mysql listening on all ports
  lineinfile: dest=/etc/mysql/my.cnf regexp=^bind-address
              line="bind-address = {{ ansible_eth0.ipv4.address }}"
  notify: restart mysql

- name: ensure mysql started
  service: name=mysql state=started enabled=yes

- name: create database
  mysql_db: name={{ db_name }} state=present

- name: create user
  mysql_user: name={{ db_user_name }} password={{ db_user_pass }} priv={{ db_name }}.*:ALL
              host='{{ db_user_host }}' state=present
```

Sin cambios respecto al ejemplo 025. Las variables `{{ db_name }}`, `{{ db_user_name }}`, `{{ db_user_pass }}` y `{{ db_user_host }}` se resuelven desde el vault en tiempo de ejecución.

---

### 🌐 Rol `apache2`

```yaml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - apache2
    - libapache2-mod-wsgi-py3

- name: ensure mod_wsgi enabled
  apache2_module: state=present name=wsgi
  notify: restart apache2

- name: de-activate default apache site
  file: path=/etc/apache2/sites-enabled/000-default.conf state=absent
  notify: restart apache2

- name: ensure apache2 started
  service: name=apache2 state=started enabled=yes
```

Sin cambios respecto al ejemplo 025. Instala `libapache2-mod-wsgi-py3` (Python 3).

---

### 🚀 Rol `demo_app`

#### `roles/demo_app/tasks/main.yml`

```yaml
---
- name: install web components
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-pip-whl
    - python3-virtualenv
    - python3-mysqldb

- name: copy demo app source
  copy: src=demo/app/ dest=/var/www/demo mode=0755
  notify: restart apache2

- name: copy demo.wsgi
  template: src=demo.wsgi.j2 dest=/var/www/demo/demo.wsgi mode=0755
  notify: restart apache2

- name: copy apache virtual host config
  copy: src=demo/demo.conf dest=/etc/apache2/sites-available mode=0755
  notify: restart apache2

- name: setup python virtualenv
  pip: requirements=/var/www/demo/requirements.txt virtualenv=/var/www/demo/.venv
  notify: restart apache2

- name: activate demo apache site
  file: src=/etc/apache2/sites-available/demo.conf
        dest=/etc/apache2/sites-enabled/demo.conf
        state=link
  notify: restart apache2
```

#### `roles/demo_app/templates/demo.wsgi.j2`

```jinja2
activate_this = '/var/www/demo/.venv/bin/activate_this.py'
exec(open(activate_this).read(), {'__file__': activate_this})

import os
os.environ['DATABASE_URI'] = 'mysql://{{ db_user }}:{{ db_pass }}@{{ groups.database[0] }}/{{ db_name }}'

import sys
sys.path.insert(0, '/var/www/demo')

from demo import app as application
```

La plantilla es idéntica al ejemplo 025. La diferencia es que `{{ db_user }}`, `{{ db_pass }}` y `{{ db_name }}` ahora provienen del vault cifrado. El fichero generado en el servidor contiene las credenciales reales en texto plano (necesario para que la aplicación funcione), pero **nunca se almacenan en texto plano en el repositorio Git**.

---

### ⚖️ Rol `nginx` — ⚠️ `ls -l` en lugar de `ls`

#### `roles/nginx/defaults/main.yml`

```yaml
#---
#sites:
#  myapp:
#    frontend: 80
#    backend: 80
```

Defaults comentados. El diccionario `sites` viene del vault.

#### `roles/nginx/tasks/main.yml`

```yaml
---
- name: install tools
  apt: name={{item}} state=present update_cache=yes
  with_items:
    - python-httplib2

- name: install nginx
  apt: name=nginx state=present update_cache=yes

- name: configure nginx sites
  template: src=nginx.conf.j2 dest=/etc/nginx/sites-available/{{ item.key }} mode=0644
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: get active sites
  shell: ls -l /etc/nginx/sites-enabled
  register: result

- name: de-activate default
  file: path=/etc/nginx/sites-enabled/default state=absent
  notify: restart nginx

- name: de-activate sites
  file: path=/etc/nginx/sites-enabled/{{ item }} state=absent
  with_items: active.stdout_lines
  when: item not in sites
  notify: restart nginx

- name: activate nginx sites
  file: src=/etc/nginx/sites-available/{{ item.key }}
        dest=/etc/nginx/sites-enabled/{{ item.key }}
        state=link
  with_dict: "{{ sites }}"
  notify: restart nginx

- name: ensure nginx started
  service: name=nginx state=started enabled=yes
```

Hay dos diferencias menores respecto al ejemplo 025:

**1. `ls -l` en lugar de `ls`:**

```yaml
- name: get active sites
  shell: ls -l /etc/nginx/sites-enabled
  register: result
```

`ls -l` produce una salida con formato largo (permisos, propietario, tamaño, fecha, nombre). Esto significa que `result.stdout_lines` contiene líneas como:

```
total 0
lrwxrwxrwx 1 root root 45 Jan 1 00:00 myapp -> /etc/nginx/sites-available/myapp
```

> ⚠️ **Bug potencial:** La tarea `de-activate sites` itera sobre `result.stdout_lines` y comprueba `when: item not in sites`. Con `ls -l`, cada línea contiene la ruta completa y metadatos, no solo el nombre del fichero. La condición `item not in sites` comparará líneas completas como `lrwxrwxrwx 1 root root...` contra las claves del diccionario `sites`, lo que siempre será `true` — eliminando todos los sitios. Este es un bug introducido en este ejemplo que no existía en el 025 (que usaba `ls` sin `-l`).

**2. `active.stdout_lines` sin llaves Jinja2:**

```yaml
  with_items: active.stdout_lines
```

En lugar de `"{{ result.stdout_lines }}"` (ejemplo 025). En versiones antiguas de Ansible esto funcionaba como sintaxis simplificada, pero en versiones modernas puede causar que `active.stdout_lines` se interprete como una cadena literal en lugar de una variable. La sintaxis correcta y recomendada es siempre `"{{ variable }}"`.

#### `roles/nginx/templates/nginx.conf.j2`

```jinja2
upstream {{ item.key }} {
{% for server in groups.webserver %}
    server {{ server }}:{{ item.value.backend }};
{% endfor %}
}

server {
    listen {{ item.value.frontend }};

    location / {
        proxy_pass http://{{ item.key }};
    }
}
```

Sin cambios respecto a ejemplos anteriores.

---

## 📄 Playbooks de mantenimiento

### `playbooks/stack_restart.yml`

```yaml
---
# Bring stack down
- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=stopped
    - wait_for: port=80 state=drained

- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=stopped
    - wait_for: port=80 state=stopped

# Restart mysql
- hosts: database
  become: true
  tasks:
    - service: name=mysql state=restarted
    - wait_for: host={{ ansible_eth0.ipv4.address }} port=3306 state=started

# Bring stack up
- hosts: webserver
  become: true
  tasks:
    - service: name=apache2 state=started
    - wait_for: port=80

- hosts: loadbalancer
  become: true
  tasks:
    - service: name=nginx state=started
    - wait_for: port=80
```

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_restart.yml --ask-vault-pass
```

### `playbooks/stack_status.yml`

Verificación en cuatro capas, idéntica al ejemplo 025:

| **Capa** | **Desde** | **Hacia** | **Qué verifica** |
|---|---|---|---|
| Servicios | cada nodo | sí mismo | `service status` + puerto abierto |
| End-to-end index | `control` | `loadbalancer:80` | `"Hello, from sunny"` en la respuesta |
| End-to-end DB | `control` | `loadbalancer:80/db` | `"Database Connected from"` en la respuesta |
| Backend index | `loadbalancer` | cada `webserver:80` | Solo que responde |
| Backend DB | `loadbalancer` | cada `webserver:80/db` | Solo que responde |

```bash
ansible-playbook -i hosts -u vagrant playbooks/stack_status.yml --ask-vault-pass
```

---

## 🔐 Flujo completo de seguridad con Vault

```
Desarrollo (máquina local)
  │
  ├── ansible-vault edit group_vars/all
  │     └── Edita credenciales en texto plano temporalmente
  │     └── Al guardar → cifra con AES-256 + contraseña del vault
  │
  ├── git add group_vars/all
  ├── git commit -m "update db credentials"
  │     └── Solo el bloque cifrado va al repositorio
  │     └── Las credenciales reales NUNCA están en Git
  │
  └── git push
        └── Repositorio remoto contiene solo texto cifrado

Despliegue (máquina de CI/CD o operador)
  │
  ├── git pull
  │     └── Obtiene el group_vars/all cifrado
  │
  ├── ansible-playbook -i hosts site.yml --ask-vault-pass
  │     └── Ansible descifra group_vars/all en MEMORIA
  │     └── Las variables están disponibles para todos los roles
  │     └── demo.wsgi.j2 se renderiza con las credenciales reales
  │     └── El fichero /var/www/demo/demo.wsgi en el servidor
  │         contiene las credenciales en texto plano (necesario)
  │
  └── Las credenciales nunca tocan el disco en texto plano
      en la máquina de control
```

---

## 🏗️ Evolución entre ejemplos

| **Aspecto** | **025** | **026** |
|---|---|---|
| **`group_vars/all`** | Texto plano (credenciales visibles) | ⭐ Cifrado AES-256 con Ansible Vault |
| **Seguridad en Git** | ❌ Credenciales expuestas | ⭐ Solo texto cifrado ilegible |
| **Ejecución del playbook** | `ansible-playbook ... site.yml` | ⭐ `ansible-playbook ... site.yml --ask-vault-pass` |
| **`ls` en nginx** | `ls` (solo nombres) | `ls -l` (formato largo — bug potencial) |
| **`with_items` en nginx** | `"{{ result.stdout_lines }}"` | `active.stdout_lines` (sin llaves — sintaxis antigua) |
| **`site.yml`** | `import_playbook` | `include` (vuelve a la sintaxis antigua) |
| **Roles y plantillas** | Sin cambios | Sin cambios (Vault es transparente para los roles) |

---

## 💡 Conceptos clave aprendidos en este ejemplo

- **Ansible Vault es transparente para los roles**: Los roles no saben ni necesitan saber si las variables vienen de un fichero en texto plano o cifrado. Ansible descifra el vault antes de ejecutar cualquier tarea, y las variables están disponibles exactamente igual que si estuvieran en texto plano. Esta transparencia es el diseño más elegante de Vault.

- **AES-256 con contraseña derivada**: Ansible Vault usa AES-256 en modo CTR con una clave derivada de la contraseña mediante PBKDF2-SHA256. Esto significa que la seguridad del vault depende completamente de la fortaleza de la contraseña elegida.

- **El vault cifra ficheros completos, no variables individuales**: `ansible-vault encrypt group_vars/all` cifra todo el fichero. También es posible cifrar solo el valor de una variable con `ansible-vault encrypt_string`, lo que permite tener un fichero `group_vars/all` con algunas variables en texto plano y solo los secretos cifrados.

- **`.vault_pass` nunca debe ir a Git**: El fichero de contraseña del vault debe estar en `.gitignore`. Si se sube accidentalmente, todos los ficheros cifrados con esa contraseña quedan comprometidos y deben ser recifrados con una nueva contraseña.

- **Vault + `group_vars/` = gestión de secretos completa**: La combinación de `group_vars/all` (centralización de variables, ejemplo 025) con Vault (cifrado, ejemplo 026) es el patrón estándar de Ansible para gestión de secretos. Permite que el repositorio Git sea completamente público sin exponer ninguna credencial.

- **`ansible-vault edit` es la operación más segura**: A diferencia de `decrypt` + editar + `encrypt`, `ansible-vault edit` nunca deja el fichero descifrado en el disco — descifra en memoria, abre el editor con el contenido temporal, y vuelve a cifrar al guardar.

---

## 📚 Referencias

- [Ansible Docs — Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Ansible Docs — Encrypting content with Vault](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html)
- [Ansible Docs — Using Vault in playbooks](https://docs.ansible.com/ansible/latest/vault_guide/vault_using_encrypted_content.html)
- [Ansible Docs — `ansible-vault` CLI](https://docs.ansible.com/ansible/latest/cli/ansible-vault.html)
- [Ansible Docs — `encrypt_string` (cifrado de variables individuales)](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html#encrypting-individual-variables-with-ansible-vault)
