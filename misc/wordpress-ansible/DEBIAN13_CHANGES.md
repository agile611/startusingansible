# Cambios para Debian 13 + MariaDB

Este documento detalla los cambios realizados para transformar el proyecto de **Ubuntu 24.04 + MySQL** a **Debian 13 + MariaDB**.

---

## 📋 Cambios principales

### 1. **Vagrantfile**
- ✅ Cambio de imagen base: `bento/ubuntu-24.04` → `bento/debian-13`
- Todas las cuatro máquinas (ansible, database, loadbalancer, webserver) utilizan la nueva imagen

### 2. **ansible.sh** (Script de aprovisionamiento)
- ✅ Eliminado: `software-properties-common` y repositorio PPA de Ansible
- ✅ Simplificado: Ansible ahora se instala directamente desde los repositorios de Debian
- Estructura simplificada, sin dependencias de PPA

### 3. **group_vars/all.yml**
- ✅ Cambio de paquete: `default-mysql-server` → `mariadb-server`
- Resto de paquetes compatibles (php-mysql sigue funcionando con MariaDB)

### 4. **roles/database/**

#### handlers/main.yml
- ✅ Nombre del servicio: `mysql` → `mariadb`
- El handler ahora reinicia `mariadb` en lugar de `mysql`

#### tasks/main.yml
- ✅ Actualización de rutas de configuración:
  - `mysqld.cnf` → `50-server.cnf`
  - Ruta: `/etc/mysql/mysql.conf.d/` → `/etc/mysql/mariadb.conf.d/`

- ✅ Actualización de fichero my.cnf:
  - Ahora referencia: `!includedir /etc/mysql/mariadb.conf.d/`
  - Anteriormente: `!includedir /etc/mysql/mysql.conf.d/`

- ✅ Cambio de cliente: `mysql` → `mariadb`
  - Las tareas shell ahora usan `mariadb` en lugar de `mysql`

- ✅ Método de autenticación:
  - Ubuntu 24.04: utilizaba `auth_socket`
  - Debian 13: utiliza `unix_socket` por defecto
  - Ambos se cambian a `mysql_native_password` para permitir autenticación remota

### 5. **README.md**
- ✅ Actualizado: descripción del proyecto ahora menciona "Debian 13 + MariaDB"
- ✅ Actualizado: script `ansible.sh` descrito como "para Debian 13"

---

## 🔄 Cambios técnicos importantes

### Estructura de directorios en Debian 13

```
/etc/mysql/
├── my.cnf                      (archivo principal)
├── conf.d/                      (configuración genérica)
├── mariadb.conf.d/             (configuración específica MariaDB)
│   └── 50-server.cnf           (configuración del servidor)
└── mysql.conf.d/               (legado, para compatibilidad)
```

### Diferencias de autenticación

| Aspecto | Ubuntu 24.04 | Debian 13 |
|---------|---|---|
| Método por defecto | `auth_socket` | `unix_socket` |
| Cambio aplicado | Sí | Sí |
| Cliente predeterminado | `mysql` | `mariadb` |

---

## ✅ Compatibilidad mantenida

- ✅ **Paquetes PHP**: `php-mysql` sigue siendo compatible con MariaDB
- ✅ **Estructura de roles**: Sin cambios en la organización
- ✅ **Variables**: Compatibles con MySQL y MariaDB
- ✅ **Community.mysql collection**: Compatible con MariaDB
- ✅ **Playbooks**: No requieren cambios

---

## 🚀 Uso

Para utilizar el proyecto transformado:

```bash
vagrant up --provider=virtualbox
vagrant ssh ansible
cd /home/vagrant/sync
ansible-playbook -i inventory/hosts site.yml
```

---

## 📝 Notas

1. **MariaDB vs MySQL**: MariaDB es un fork de MySQL mantenido por la comunidad. Es totalmente compatible a nivel de API y SQL.
2. **Debian 13**: Utiliza MariaDB como alternativa a MySQL en sus repositorios oficiales.
3. **Servicios**: En Debian 13, el servicio se llama `mariadb` (no `mysql`).
4. **Configuración**: MariaDB mantiene la estructura de `/etc/mysql/` por compatibilidad.

---

## 🔍 Validación

Para validar que los cambios se han aplicado correctamente:

```bash
# Verificar que MariaDB se inicia correctamente
vagrant ssh database
systemctl status mariadb

# Verificar la conexión remota
mariadb -u wordpress -p -h 192.168.11.20 -e "SELECT VERSION();"
```

---

Última actualización: Junio 2026
