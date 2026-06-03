# Ejemplo 019: Facts de Ansible

Este directorio muestra un ejemplo simple de uso de `ansible_facts` en un playbook de Ansible.

## Archivos

- `site.yml`
  - Playbook principal que importa `control.yml` y `webserver.yml`.
- `control.yml`
  - Playbook para el grupo de hosts `control`.
  - Ejecuta la recolección de facts (`gather_facts: true`).
  - Muestra información de facts con tareas `debug`.
- `webserver.yml`
  - Playbook para el grupo de hosts `webserver`.
  - No recolecta facts (`gather_facts: false`).
  - Instala paquetes necesarios para un servidor web Apache con soporte WSGI y virtualenv.

## Propósito

Este ejemplo sirve para:

- Ver cómo Ansible recopila facts automáticamente en un playbook.
- Inspeccionar variables disponibles en `ansible_facts`.
- Comparar un playbook con facts habilitados frente a otro con facts deshabilitados.

## Ejecución

Asegúrate de tener un inventario que defina los grupos `control` y `webserver`.

Ejemplo de ejecución:

```bash
ansible-playbook -i hosts site.yml
```

Si quieres ejecutar solo el playbook de control:

```bash
ansible-playbook -i hosts control.yml
```

Y para ejecutar solo el playbook de webserver:

```bash
ansible-playbook -i hosts webserver.yml
```

## Notas

- `control.yml` usa `gather_facts: true` para permitir el uso de `ansible_facts`.
- `webserver.yml` instala Apache y componentes Python sin recopilar facts primero.
- Si necesitas usar facts dentro de `webserver.yml`, cambia `gather_facts` a `true`.
