# 035 — AWX on K3s — Despliegue Automatizado

## 📋 Descripción General

Este ejemplo despliega **AWX** (la versión open source de Ansible Tower)
sobre **K3s** (Kubernetes ligero) de forma completamente automatizada.
El entorno se levanta con Vagrant: 4 VMs para el laboratorio Ansible estándar
más una **quinta VM dedicada exclusivamente a AWX** con recursos elevados
(16 GB RAM, 4 CPUs).

El despliegue de AWX se realiza mediante el script `setup-awx.sh`, que
ejecuta los **15 pasos** del proceso de instalación de forma desatendida,
con control de errores, timeouts y medición de tiempo de ejecución.

---

## 🗂️ Estructura del Ejemplo

```
035_awx/
├── Vagrantfile              # Define las 5 VMs del entorno
├── setup-awx.sh             # Script automatizado de instalación (15 pasos)
├── ansible_awx_install.txt  # Guía manual paso a paso (referencia)
└── .gitignore
```

---

## 🏗️ Arquitectura del Entorno

```
┌──────────────────────────────────────────────────────────┐
│                   red: 192.168.11.0/24                   │
│                                                          │
│  control       192.168.11.10   512 MB  1 CPU  Debian     │
│  database      192.168.11.20   512 MB  1 CPU  Debian     │
│  loadbalancer  192.168.11.30   512 MB  1 CPU  Debian     │
│  webserver     192.168.11.40   512 MB  1 CPU  Debian     │
│                                                          │
│  awx           192.168.11.50  16384 MB 4 CPU  Ubuntu     │
│                puerto 32000 → forwarded → host:32000     │
└──────────────────────────────────────────────────────────┘
```

> **Nota:** El Vagrantfile usa `bento/debian-13` y `bento/ubuntu-26.04`,
> que **no existen todavía** como boxes estables. Sustituir por
> `bento/debian-12` y `bento/ubuntu-24.04` respectivamente.

---

## 📄 Fichero: `Vagrantfile`

Define **5 máquinas virtuales** con VirtualBox como provider.

```ruby
Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 900   # 15 min de timeout (AWX tarda en arrancar)

  # ─── Nodos del laboratorio Ansible (Debian) ────────────
  # control      192.168.11.10  512 MB  1 CPU
  # database     192.168.11.20  512 MB  1 CPU
  # loadbalancer 192.168.11.30  512 MB  1 CPU
  # webserver    192.168.11.40  512 MB  1 CPU

  # ─── Nodo AWX (Ubuntu) ─────────────────────────────────
  config.vm.define "awx" do |awx|
    awx.vm.box      = "bento/ubuntu-24.04"      # ← corregido
    awx.vm.hostname = "awx"
    awx.vm.network "private_network", ip: "192.168.11.50"
    awx.vm.network "forwarded_port", guest: 32000, host: 32000
    awx.vm.provision :shell, :path => "setup-awx.sh"  # Autoinstala AWX
    awx.vm.provider "virtualbox" do |vb|
      vb.memory = 16384   # 16 GB — AWX + K3s + PostgreSQL son pesados
      vb.cpus   = 4
    end
  end

end
```

### Puntos clave del Vagrantfile

| **Parámetro** | **Valor** | **Motivo** |
|---|---|---|
| `boot_timeout` | `900` | AWX tarda hasta 15 min en estar listo |
| `memory` (awx) | `16384` MB | K3s + AWX Operator + PostgreSQL + Redis |
| `cpus` (awx) | `4` | Kubernetes necesita múltiples cores |
| `forwarded_port` | `32000 → 32000` | Acceso al dashboard AWX desde el host |
| `provision :shell` | `setup-awx.sh` | Instalación desatendida automática |

---

## 📄 Fichero: `setup-awx.sh` — Script Automatizado (15 Pasos)

Script Bash que instala y configura AWX sobre K3s de forma completamente
desatendida. Incluye colores en la salida, control de errores estricto
(`set -e`, `set -o pipefail`), timeouts con reintentos y **medición
del tiempo total de ejecución**.

### Cabecera y control de errores

```bash
#!/bin/bash
set -e           # Aborta al primer error
set -o pipefail  # Captura errores dentro de pipes

# Colores para la salida
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Captura el tiempo de inicio
START_TIME=$SECONDS
```

---

### Los 15 Pasos en Detalle

#### Paso 1 — Actualizar el sistema

```bash
sudo apt update -y
sudo apt upgrade -y
```

Actualiza todos los paquetes del sistema antes de instalar nada.

---

#### Paso 2 — Instalar K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

Descarga e instala **K3s**, la distribución ligera de Kubernetes de Rancher.
K3s es un binario único que incluye `kubectl`, `containerd` y todo lo
necesario para un clúster Kubernetes funcional.

---

#### Paso 3 — Configurar acceso a K3s para usuario no-root

```bash
sudo chown "$USER:$USER" /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Persiste KUBECONFIG en ~/.bashrc si no existe ya
if ! grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc; then
  echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
fi
```

Cambia el propietario del fichero de configuración de K3s al usuario actual
y persiste la variable `KUBECONFIG` en `.bashrc` para que esté disponible
en futuras sesiones.

---

#### Paso 4 — Verificar el clúster Kubernetes

```bash
# Espera hasta 6 minutos (36 × 10s) a que el nodo esté Ready
for i in $(seq 1 36); do
  STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
  if [ "$STATUS" == "Ready" ]; then break; fi
  sleep 10
done

kubectl version
kubectl get nodes
kubectl get pods -A
```

Bucle de espera con **timeout de 6 minutos** (36 reintentos × 10 segundos).
Verifica que el nodo K3s está en estado `Ready` antes de continuar.

---

#### Paso 5 — Instalar Kustomize

```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
```

Instala **Kustomize**, la herramienta de personalización de manifiestos
Kubernetes que usa el AWX Operator para su despliegue.

---

#### Paso 6 — Crear directorio de trabajo

```bash
mkdir -p awx-deploy
cd awx-deploy
```

Crea el directorio `awx-deploy` donde se generarán los manifiestos
de Kubernetes para AWX.

---

#### Paso 7 — Crear `kustomization.yaml` inicial

```bash
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: awx
EOF
```

Define el manifiesto Kustomize que apunta al **AWX Operator v2.19.1**
en el repositorio oficial de Ansible en GitHub.

---

#### Paso 8 — Aplicar configuración inicial de Kustomize

```bash
kubectl apply -k .
```

Despliega el **AWX Operator** en el namespace `awx` del clúster K3s.
El Operator es el controlador Kubernetes que gestiona el ciclo de vida
de AWX.

---

#### Paso 9 — Esperar a que el Operator esté Running

```bash
# Timeout: 15 minutos (60 × 15s)
for i in $(seq 1 60); do
  STATUS=$(kubectl get pods -n awx --no-headers 2>/dev/null \
    | grep "awx-operator" | awk '{print $3}' | head -1)
  if [ "$STATUS" == "Running" ]; then break; fi
  sleep 15
done

kubectl get pods -n awx
```

Bucle de espera con **timeout de 15 minutos** hasta que el pod del
AWX Operator esté en estado `Running`. La descarga de imágenes puede
tardar según la conexión.

---

#### Paso 10 — Crear la instancia AWX (`awx-demo.yaml`)

```bash
cat > awx-demo.yaml <<'EOF'
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
  nodeport_port: 32000
EOF
```

Define el **Custom Resource AWX** que le indica al Operator que
despliegue una instancia de AWX llamada `awx-demo`, expuesta como
`NodePort` en el puerto `32000`.

---

#### Paso 11 — Actualizar `kustomization.yaml` con la instancia

```bash
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
  - awx-demo.yaml          # ← añadido en este paso

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: awx
EOF
```

Actualiza el `kustomization.yaml` para incluir el fichero `awx-demo.yaml`
como recurso adicional.

---

#### Paso 12 — Reaplicar la configuración Kustomize

```bash
kubectl apply -k .
```

Reaplicar con el `awx-demo.yaml` incluido hace que el AWX Operator
detecte el nuevo Custom Resource y comience a desplegar todos los
componentes de AWX (PostgreSQL, Redis, AWX web, AWX task).

---

#### Paso 13 — Esperar a que todos los pods AWX estén Running

```bash
# Timeout: 30 minutos (60 × 30s)
for i in $(seq 1 60); do
  NOT_RUNNING=$(kubectl get pods -n awx --no-headers 2>/dev/null \
    | grep -v "Running\|Completed" | wc -l)
  if [ "$NOT_RUNNING" -eq 0 ]; then break; fi
  sleep 30
done

kubectl get pods -n awx
```

Espera hasta **30 minutos** a que todos los pods del namespace `awx`
estén en estado `Running` o `Completed`. AWX despliega múltiples pods:

| **Pod** | **Función** |
|---|---|
| `awx-operator-*` | Controlador Kubernetes del Operator |
| `awx-demo-postgres-*` | Base de datos PostgreSQL |
| `awx-demo-*` (web) | Interfaz web de AWX |
| `awx-demo-*` (task) | Motor de ejecución de tareas Ansible |

---

#### Paso 14 — Ver logs del Operator

```bash
kubectl logs -f deployment/awx-operator-controller-manager \
  -c awx-manager -n awx
```

Muestra los logs en tiempo real del AWX Operator para verificar
que el despliegue se ha completado sin errores.

---

#### Paso 15 — Obtener la contraseña de administrador

```bash
kubectl get secret awx-demo-admin-password \
  -n awx \
  -o jsonpath="{.data.password}" | base64 --decode ; echo
```

Extrae la contraseña del usuario `admin` del Secret de Kubernetes
donde AWX la almacena cifrada en base64.

---

### Medición del tiempo de ejecución

Al final del script se calcula el tiempo total transcurrido:

```bash
ELAPSED=$((SECONDS - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS_REM=$((ELAPSED % 60))
log "✅ AWX deployment completed in ${MINUTES}m ${SECONDS_REM}s"
```

Usando la variable especial `$SECONDS` de Bash (segundos desde el inicio
del script), calcula minutos y segundos del proceso completo.
El despliegue típico tarda entre **15 y 60 minutos** según los recursos
del host y la velocidad de descarga de imágenes.

---

## 📄 Fichero: `ansible_awx_install.txt` — Guía Manual

Versión manual de los mismos 16 pasos para ejecutarlos uno a uno
en una terminal. Útil como referencia o para instalaciones interactivas.

Incluye un **paso 16** adicional no automatizado en el script:

```
== 16. Access the AWX Dashboard ==
http://<your-server-ip>:32000

Username: admin
Password: (obtenida en el paso 15)
```

---

## 🚀 Uso del Ejemplo

### Arrancar el entorno completo

```bash
cd examples/035_awx
vagrant up
```

> Vagrant levantará las 5 VMs. La VM `awx` ejecutará automáticamente
> `setup-awx.sh` durante el aprovisionamiento. El proceso puede tardar
> entre 15 y 60 minutos.

### Arrancar solo la VM de AWX

```bash
vagrant up awx
```

### Seguir el progreso de la instalación

```bash
vagrant ssh awx
kubectl get pods -n awx -w
```

### Acceder al dashboard AWX

Una vez completado el despliegue, abrir en el navegador del host:

```
http://192.168.11.50:32000
# o bien, gracias al port forwarding:
http://localhost:32000

Usuario:    admin
Contraseña: (ejecutar el paso 15)
```

### Obtener la contraseña de admin

```bash
vagrant ssh awx
kubectl get secret awx-demo-admin-password \
  -n awx \
  -o jsonpath="{.data.password}" | base64 --decode ; echo
```

## 🔄 Flujo Completo de Despliegue

```
vagrant up awx
     │
     ▼
setup-awx.sh
     │
     ├── [1]  apt update + upgrade
     ├── [2]  Instala K3s (Kubernetes ligero)
     ├── [3]  Configura KUBECONFIG
     ├── [4]  Espera nodo Ready          ⏱ timeout 6 min
     ├── [5]  Instala Kustomize
     ├── [6]  Crea directorio awx-deploy/
     ├── [7]  Crea kustomization.yaml    → AWX Operator v2.19.1
     ├── [8]  kubectl apply -k .         → Despliega Operator
     ├── [9]  Espera Operator Running    ⏱ timeout 15 min
     ├── [10] Crea awx-demo.yaml         → NodePort :32000
     ├── [11] Actualiza kustomization.yaml
     ├── [12] kubectl apply -k .         → Despliega AWX
     ├── [13] Espera todos pods Running  ⏱ timeout 30 min
     ├── [14] Muestra logs del Operator
     ├── [15] Extrae contraseña admin
     └── ✅  Tiempo total: ~15-60 min
          │
          ▼
   http://localhost:32000
   admin / <password>
```

---

## 📚 Referencias

- [AWX Project — GitHub](https://github.com/ansible/awx)
- [AWX Operator — GitHub](https://github.com/ansible/awx-operator)
- [K3s — Lightweight Kubernetes](https://k3s.io/)
- [Kustomize — Kubernetes SIG](https://kustomize.io/)
- [Repositorio original — agile611/startusingansible](https://github.com/agile611/startusingansible)