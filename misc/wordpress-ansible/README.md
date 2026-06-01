[![Agile611](https://www.agile611.com/wp-content/uploads/2020/09/cropped-logo-header.png)](http://www.agile611.com/)

# Agile611 WordPress Ansible (Vagrant)

Plantilla per desplegar un entorn WordPress utilitzant Vagrant i Ansible. Inclou una màquina de control (Ansible), servidor web, base de dades i balancejador de càrrega, tots definits al `Vagrantfile`.

**Objectiu:** facilitar el proveïment i les proves locals d'una arquitectura WordPress multinodo utilitzant caixes `bento/ubuntu-24.04`.

---

## Contingut principal

- **`Vagrantfile`**: definició de les màquines (ansible, database, loadbalancer, webserver).
- **`ansible.sh`** (si existeix): script de proveïment inicial utilitzat per la màquina `ansible`.
- **Playbooks/rols**: afegeix els teus playbooks d'Ansible a una carpeta `ansible/` o similar.

---

## Requisits

- `Vagrant` (>= 2.2.x)
- `VirtualBox` (o un altre proveïdor suportat per Vagrant)
- Opcional: `ansible` a la màquina amfitriona si prefereixes executar playbooks des de fora de la VM

---

## Guia ràpida

Aixecar totes les màquines:

```bash
vagrant up --provider=virtualbox
```

Aixecar una màquina concreta (per exemple `webserver`):

```bash
vagrant up webserver
```

Accedir per SSH a la màquina de control (Ansible):

```bash
vagrant ssh ansible
```

Des de la màquina `ansible` (o des del teu host si tens Ansible instal·lat), executa els teus playbooks:

```bash
# des de la VM de control
ansible-playbook -i inventory/hosts site.yml

# o des del host (si està configurat)
ansible-playbook -i inventory/hosts site.yml --private-key=path/to/key
```

---

## Notes i recomanacions

- Revisa i ajusta les IPs privades al `Vagrantfile` si entren en conflicte amb la teva xarxa local.
- Si utilitzes `rsync` per sincronitzar carpetes, recorda que pot requerir `rsync` instal·lat a la màquina amfitriona.
- Mantén `composer.lock` al repositori si el teu projecte PHP depèn de versions concretes; `vendor/` normalment s'ignora (està al `.gitignore`).

---

## Estructura suggerida

```
Vagrantfile
ansible/
├── inventory/
├── playbooks/
└── roles/
ansible.sh  (opcional)
```

---

## Contribucions

Obre issues o PRs per suggerir millores. Descriu els canvis i els passos per reproduir-los.

---

## Llicència

Aquest tutorial és alliberat al domini públic per [Agile611](http://www.agile611.com/) sota la llicència Creative Commons Attribution-NonCommercial 4.0 International.

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC_BY--NC_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/)

Aquest fitxer README va ser escrit originalment per [Guillem Hernández Sola](https://www.linkedin.com/in/guillemhs/) i és igualment alliberat al domini públic.

Contacta amb Agile611 per a més informació.

- [Agile611](http://www.agile611.com/)
- Laureà Miró 309
- 08950 Esplugues de Llobregat (Barcelona)