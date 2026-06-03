#!/bin/bash

# =============================================================
# AWX on K3s - Automated Setup Script (Steps 1-15)
# =============================================================

set -e  # Exit immediately on error
set -o pipefail  # Catch errors in pipes

# --- Colors for output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ✅ Capture start time
START_TIME=$SECONDS

# =============================================================
# == 1. Update Your System ==
# =============================================================
log "Step 1: Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
log "System updated successfully."

# =============================================================
# == 2. Install k3s ==
# =============================================================
log "Step 2: Installing k3s..."
curl -sfL https://get.k3s.io | sh -
log "k3s installed successfully."

# =============================================================
# == 3. Give Non-root User Access to K3s Config ==
# =============================================================
log "Step 3: Configuring k3s access for user: $USER..."
sudo chown "$USER:$USER" /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Persist KUBECONFIG in ~/.bashrc if not already set
if ! grep -q "KUBECONFIG=/etc/rancher/k3s/k3s.yaml" ~/.bashrc; then
  echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
  log "KUBECONFIG added to ~/.bashrc"
fi
log "k3s access configured."

# =============================================================
# == 4. Verify Kubernetes Cluster ==
# =============================================================
log "Step 4: Verifying Kubernetes cluster..."

# Wait for k3s node to be ready
# ⏱ Timeout: 36 × 10s = 6 minutes
log "Waiting for k3s node to become Ready..."
for i in $(seq 1 36); do
  STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
  if [ "$STATUS" == "Ready" ]; then
    log "Node is Ready!"
    break
  fi
  warn "Node not ready yet, retrying in 10s... ($i/36)"
  sleep 10
done

kubectl version
kubectl get nodes
kubectl get pods -A
log "Cluster verified."

# =============================================================
# == 5. Install Kustomize ==
# =============================================================
log "Step 5: Installing Kustomize..."
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
log "Kustomize installed: $(kustomize version)"

# =============================================================
# == 6. Create Kustomization Directory ==
# =============================================================
log "Step 6: Creating AWX deployment directory..."
mkdir -p awx-deploy
cd awx-deploy
log "Working directory: $(pwd)"

# =============================================================
# == 7. Create kustomization.yaml ==
# =============================================================
log "Step 7: Creating kustomization.yaml..."
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
log "kustomization.yaml created."

# =============================================================
# == 8. Apply Kustomize Configuration ==
# =============================================================
log "Step 8: Applying initial Kustomize configuration..."
kubectl apply -k .
log "Initial Kustomize config applied."

# =============================================================
# == 9. Verify Operator is Running ==
# =============================================================
log "Step 9: Waiting for AWX Operator pod to be Running..."
# ⏱ Timeout: 60 × 15s = 15 minutes
for i in $(seq 1 60); do
  STATUS=$(kubectl get pods -n awx --no-headers 2>/dev/null | grep "awx-operator" | awk '{print $3}' | head -1)
  if [ "$STATUS" == "Running" ]; then
    log "AWX Operator is Running!"
    break
  fi
  warn "Operator not ready yet (status: ${STATUS:-Pending}), retrying in 15s... ($i/60)"
  sleep 15
done

kubectl get pods -n awx
log "Operator verified."

# =============================================================
# == 10. Create AWX Instance File ==
# =============================================================
log "Step 10: Creating awx-demo.yaml..."
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
log "awx-demo.yaml created."

# =============================================================
# == 11. Update kustomization.yaml to Include AWX Instance ==
# =============================================================
log "Step 11: Updating kustomization.yaml to include awx-demo.yaml..."
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
  - awx-demo.yaml

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: awx
EOF
log "kustomization.yaml updated."

# =============================================================
# == 12. Reapply Kustomize Configuration ==
# =============================================================
log "Step 12: Reapplying Kustomize configuration with AWX instance..."
kubectl apply -k .
log "Kustomize configuration reapplied."

# =============================================================
# == 13. Wait for All AWX Pods to Be Running ==
# =============================================================
log "Step 13: Waiting for AWX pods to be fully Running (this may take up to 40 mins)..."
# ⏱ Timeout: 80 × 30s = 40 minutes
for i in $(seq 1 80); do
  TOTAL=$(kubectl get pods -n awx --no-headers 2>/dev/null | wc -l)
  READY=$(kubectl get pods -n awx --no-headers 2>/dev/null | grep -c "Running" || true)
  log "Pods Running: $READY / $TOTAL (attempt $i/80)"
  if [ "$TOTAL" -ge 4 ] && [ "$READY" -eq "$TOTAL" ]; then
    log "All AWX pods are Running!"
    break
  fi
  sleep 30
done

kubectl get pods -n awx
log "Pod status checked."

# =============================================================
# == 14. View Operator Logs (tail last 30 lines) ==
# =============================================================
log "Step 14: Fetching last 30 lines of AWX Operator logs..."
kubectl logs deployment/awx-operator-controller-manager \
  -c awx-manager \
  -n awx \
  --tail=30 || warn "Could not fetch logs yet — operator may still be initializing."

# =============================================================
# == 15. Retrieve Admin Password ==
# =============================================================
log "Step 15: Retrieving AWX admin password..."

# Wait for the secret to be created
# ⏱ Timeout: 40 × 30s = 20 minutes
for i in $(seq 1 40); do
  SECRET=$(kubectl get secret awx-demo-admin-password -n awx 2>/dev/null)
  if [ -n "$SECRET" ]; then
    log "Admin password secret found!"
    break
  fi
  warn "Secret not available yet, retrying in 30s... ($i/40)"
  sleep 30
done

ADMIN_PASSWORD=$(kubectl get secret awx-demo-admin-password \
  -n awx \
  -o jsonpath="{.data.password}" | base64 --decode)

# =============================================================
# == DONE — Summary ==
# =============================================================

# ✅ Calculate elapsed time
ELAPSED=$(( SECONDS - START_TIME ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  ✅  AWX Setup Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "  🌐 Dashboard URL : ${YELLOW}http://${SERVER_IP}:32000${NC}"
echo -e "  👤 Username      : ${YELLOW}admin${NC}"
echo -e "  🔑 Password      : ${YELLOW}${ADMIN_PASSWORD}${NC}"
echo ""
echo -e "  ⏱️  Total time    : ${YELLOW}${ELAPSED_MIN}m ${ELAPSED_SEC}s${NC}"
echo ""
echo -e "${GREEN}=============================================${NC}"