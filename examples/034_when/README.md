# 034 — Condicionals `when` en Ansible

## 📋 Descripció General

Aquest exemple demostra l'ús de la directiva `when` en Ansible,
que permet executar tasques de forma **condicional** segons el grup
al qual pertany cada host, les seves variables o els fets (`facts`)
recollits automàticament per Ansible.

L'ús de `when` és fonamental per escriure playbooks **reutilitzables**
que s'executen sobre infraestructures heterogènies — com en aquest cas,
on tenim tres tipus de servidors amb rols completament diferents.

---

## 🗂️ Estructura de l'Inventari (`hosts`)

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

### Explicació de l'inventari

| **Paràmetre** | **Valor** | **Funció** |
|---|---|---|
| `ansible_python_interpreter` | `/usr/bin/python3` | Força l'ús de Python 3 als nodes remots |
| `ansible_user` | `vagrant` | Usuari SSH per connectar-se als hosts |
| `ansible_ssh_private_key_file` | `/home/vagrant/.ssh/id_rsa` | Clau privada per a l'autenticació SSH sense contrasenya |
| `ansible_ssh_common_args` | `-o StrictHostKeyChecking=no` | Desactiva la verificació de la clau del host (útil en entorns de laboratori Vagrant) |

Els tres grups defineixen la **topologia de la infraestructura**:

- **`[database]`** → `192.168.11.20` — Servidor de base de dades
- **`[loadbalancer]`** → `192.168.11.30` — Balancejador de càrrega (ex: HAProxy / Nginx)
- **`[webserver]`** → `192.168.11.40` — Servidor web (ex: Apache / Nginx)

---

## 🎭 Què fa el Playbook (`playbook.yml`)

El playbook s'executa sobre **tots els hosts** (`hosts: all`) però
utilitza la directiva `when` per aplicar tasques específiques
**només als hosts que pertanyen a un grup determinat**.

### Lògica condicional amb `when`

```yaml
# Exemple de patró típic d'un playbook 034_when

- name: Exemple de condicionals when
  hosts: all
  become: true

  tasks:

    - name: Instal·lar MySQL (només al servidor de base de dades)
      apt:
        name: mysql-server
        state: present
      when: inventory_hostname in groups['database']

    - name: Instal·lar HAProxy (només al balancejador)
      apt:
        name: haproxy
        state: present
      when: inventory_hostname in groups['loadbalancer']

    - name: Instal·lar Apache (només als servidors web)
      apt:
        name: apache2
        state: present
      when: inventory_hostname in groups['webserver']

    - name: Tasca comuna per a tots els servidors
      debug:
        msg: "Aquest servidor és: {{ inventory_hostname }}"
```

### Com funciona `when` pas a pas

1. Ansible es connecta als **3 hosts** simultàniament via SSH
2. Per a cada host, avalua la condició `when` de cada tasca
3. Si la condició és **`true`** → executa la tasca
4. Si la condició és **`false`** → marca la tasca com a `skipping` i continua
5. El resultat final és que **cada host rep només les tasques que li corresponen**

### Flux d'execució visual

```
                    ┌─────────────────────────────────────┐
                    │         ansible-playbook             │
                    │         hosts: all                   │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
    192.168.11.20          192.168.11.30        192.168.11.40
    [database]             [loadbalancer]       [webserver]
              │                    │                    │
              ▼                    ▼                    ▼
    ✅ MySQL install        ✅ HAProxy install   ✅ Apache install
    ⏭️  HAProxy → SKIP      ⏭️  MySQL → SKIP     ⏭️  MySQL → SKIP
    ⏭️  Apache → SKIP       ⏭️  Apache → SKIP    ⏭️  HAProxy → SKIP
    ✅ Debug msg            ✅ Debug msg         ✅ Debug msg
```

---

## ▶️ Comanda d'Execució

```bash
ansible-playbook -i hosts -u vagrant playbook.yml
```

### Desglossat de la comanda

| **Flag** | **Valor** | **Funció** |
|---|---|---|
| `-i hosts` | fitxer `hosts` | Especifica l'inventari d'hosts |
| `-u vagrant` | `vagrant` | Usuari SSH per a la connexió remota |
| `playbook.yml` | fitxer principal | El playbook a executar |

> **Nota:** L'usuari `-u vagrant` és redundant en aquest cas perquè
> ja està definit a `[all:vars]` com `ansible_user=vagrant`,
> però és una bona pràctica especificar-lo explícitament a la comanda.

---

## 🔑 Conceptes Clau Apresos

### 1. La directiva `when`
Permet condicionar l'execució d'una tasca. Accepta expressions Python/Jinja2:

```yaml
# Per grup d'inventari
when: inventory_hostname in groups['webserver']

# Per sistema operatiu (usant facts)
when: ansible_os_family == "Debian"

# Per variable
when: my_variable == true

# Condicions múltiples (AND)
when:
  - ansible_os_family == "Debian"
  - inventory_hostname in groups['webserver']

# Condicions múltiples (OR)
when: ansible_os_family == "Debian" or ansible_os_family == "RedHat"
```

### 2. `inventory_hostname`
Variable màgica d'Ansible que conté el nom o IP del host
que s'està processant en aquell moment.

### 3. `groups['nom_grup']`
Diccionari d'Ansible que conté tots els hosts d'un grup determinat.
La combinació `inventory_hostname in groups['grup']` és el patró
més comú per aplicar tasques per rol de servidor.

### 4. Comportament `skipping`
Quan una condició `when` no es compleix, Ansible **no falla** —
simplement mostra `skipping` i continua amb la següent tasca.
Això és el que permet executar un sol playbook sobre tota la infraestructura.

---

## 🏗️ Casos d'Ús Reals

| **Escenari** | **Condició `when`** |
|---|---|
| Instal·lar paquets per rol | `inventory_hostname in groups['webserver']` |
| Diferenciar Debian vs RedHat | `ansible_os_family == "Debian"` |
| Executar només en producció | `env == "production"` |
| Saltar si ja està configurat | `not config_file.stat.exists` |
| Condicionar per versió de SO | `ansible_distribution_version >= "20.04"` |

---

## 📚 Referències

- [Ansible Docs — Conditionals (`when`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [Ansible Docs — Magic Variables (`inventory_hostname`, `groups`)](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html)
- [Ansible Docs — Inventory basics](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Repositori original — agile611/startusingansible](https://github.com/agile611/startusingansible)