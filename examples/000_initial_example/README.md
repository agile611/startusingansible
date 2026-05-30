# Primeros Pasos con Ansible: Ejemplo Inicial

En esta guía encontrarás los ficheros necesarios y la explicación paso a paso para entender cómo funciona tu primera automatización con Ansible.

---

## 📋 Ficheros del Proyecto

Para ejecutar este ejemplo, necesitas crear dos archivos. Uno contendrá el inventario (la lista de máquinas y su configuración) y el otro el *playbook* (las instrucciones).

### 1. Archivo de Inventario (`hosts`)
Guárdalo en la carpeta principal desde donde vas a ejecutar el comando.

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

### 2. Archivo Playbook (`000_initial_example.yml`)
Guárdalo respetando la ruta de carpetas: `examples/000_initial_example/000_initial_example.yml`.

```yaml
---
  - hosts: all
    tasks:
      - name: get server hostname
        command: hostname
      - name: Debug hostname
        ansible.builtin.debug:
          var: ansible_facts['hostname']
```

---

## 🧭 ¿Qué hace esto? (Explicación para alumnos)

Para entender Ansible, hay que imaginarlo como un **director de orquesta**. Tú le das una partitura (el *Playbook*) y le dices quiénes son los músicos (el *Inventario*). Ansible se encarga de que todos toquen la melodía exacta al mismo tiempo.

### El Inventario (`hosts`)
Es la **agenda de contactos y el manual de conexión**. En este archivo no solo le decimos a Ansible cuáles son las direcciones IP de las máquinas, sino también cómo debe conectarse a ellas.
- **Grupos de máquinas**: Hemos organizado nuestros servidores por su función: `[database]` (base de datos), `[loadbalancer]` (balanceador de carga) y `[webserver]` (servidor web).
- **Variables globales (`[all:vars]`)**: Son las "reglas del juego" para todas las máquinas. Le decimos a Ansible que use Python 3, que se conecte con el usuario `vagrant`, dónde está la llave de seguridad (clave SSH) para entrar sin contraseña, y que no nos pregunte por confirmaciones de seguridad al conectarse por primera vez.

### El Playbook (`000_initial_example.yml`)
Es la **receta paso a paso** de lo que queremos que Ansible haga. Está escrito en un lenguaje llamado YAML, que es muy fácil de leer para los humanos.
- **`hosts: all`**: Le dice a Ansible que ejecute esto en *todas* las máquinas del inventario.
- **`tasks` (Tareas)**: Son las acciones concretas. Aquí hacemos dos cosas muy interesantes:
  1. **`command: hostname`**: Le decimos a Ansible que ejecute el comando de Linux `hostname` en las máquinas remotas para averiguar cómo se llaman.
  2. **`ansible.builtin.debug`**: Le pedimos que nos muestre esa información por pantalla. Al usar `ansible_facts['hostname']`, estamos accediendo a los "facts" (datos que Ansible recopila automáticamente sobre cada máquina al conectarse) para imprimir el nombre real del servidor.

---

## 🚀 Entendiendo el Comando de Ejecución

Para poner en marcha esta receta, utilizamos el siguiente comando en la terminal:

```bash
ansible-playbook -i hosts -u vagrant examples/000_initial_example/000_initial_example.yml
```

Con esta línea, le estás dando a Ansible cuatro instrucciones muy precisas:

| **Parte del comando** | **¿Qué significa?** |
|-----------------------|---------------------|
| `ansible-playbook` | Es la orden principal: "¡Ansible, prepárate para ejecutar una receta!" |
| `-i hosts` | **i** de *Inventory*. Le dice: "Lee la lista de máquinas y configuraciones que está en el archivo llamado `hosts`". |
| `-u vagrant` | **u** de *User*. Le dice: "Conéctate a esas máquinas utilizando el nombre de usuario `vagrant`". |
| `examples/.../.yml` | Es la ruta exacta donde está guardada la receta (el archivo YAML) que queremos ejecutar. |

**Resultado:** Al pulsar *Enter*, Ansible viajará por la red, entrará en tus tres servidores (192.168.11.20, .30 y .40) usando las llaves SSH, ejecutará el comando para descubrir el nombre de cada máquina y te lo mostrará de forma ordenada en tu pantalla. ¡Todo en cuestión de segundos!