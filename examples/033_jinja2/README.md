# Ejemplo 033: Plantillas Jinja2 para nginx

Este ejemplo muestra cómo usar el módulo `template` de Ansible con una plantilla Jinja2 para generar archivos de configuración de `nginx`.

## Archivos principales

- `deploy-nginx.yml`: playbook de Ansible que instala `nginx`, crea directorios, y genera archivos basados en la plantilla.
- `nginx.conf.j2`: plantilla Jinja2 que crea un bloque `server` con soporte condicional para SSL.

## Qué demuestra

- Uso de variables como `server_name`, `document_root` y `enable_ssl`.
- Uso del módulo `template` para renderizar una plantilla Jinja2.
- Uso de condicionales Jinja2 (`{% if enable_ssl %}`) dentro de la plantilla.
- Escritura de archivos de configuración en `/etc/nginx/sites-available`.
- Creación de certificados SSL ficticios en `/etc/nginx/ssl` según la misma plantilla.

## Variables importantes

- `nginx_conf_template`: ruta de la plantilla Jinja2 (`nginx.conf.j2`).
- `server_name`: nombre del servidor que se usa en la configuración y en los nombres de archivo.
- `document_root`: raíz del documento donde `nginx` sirve el contenido.
- `enable_ssl`: habilita o deshabilita el bloque SSL en la configuración.

## Ejecución

Desde la raíz del repositorio, usa un comando similar a este:

```bash
ansible-playbook -i hosts examples/033_jinja2/deploy-nginx.yml \
  -e "server_name=example.com document_root=/var/www/html enable_ssl=true"
```

> Nota: Ajusta `server_name`, `document_root` y `enable_ssl` según tu entorno.

## Observaciones

El ejemplo genera:

- `/etc/nginx/sites-available/{{ server_name }}.conf`
- `/etc/nginx/ssl/{{ server_name }}.crt`
- `/etc/nginx/ssl/{{ server_name }}.key`

Y crea un enlace simbólico en `/etc/nginx/sites-enabled`.

Este ejemplo es útil para entender cómo Ansible puede personalizar archivos de configuración usando plantillas Jinja2.
