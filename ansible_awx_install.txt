== 1. Update Your System ==
sudo apt update 
sudo apt upgrade -y

== 2. Install k3s ==
curl -sfL https://get.k3s.io | sh -

== 3. Give Non-root User Access to K3s Config ==
sudo chown $USER:$USER /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

== 4. Verify Kubernetes Cluster ==
kubectl version
kubectl get nodes
kubectl get pods -A

== 5. Install Kustomize ==
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin

== 6. Create Kustomization Directory ==
mkdir awx-deploy && cd awx-deploy

== 7. Create kustomization.yaml ==
#create file
nano kustomization.yaml

#Add below to the file
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: awx


== 8. Apply Kustomize Configuration ==
kubectl apply -k .

OR

kustomize build . | kubectl apply -f -

== 9. Verify Operator is Running ==
kubectl get pods -n awx

== 10. Create AWX Instance. Create a file named awx-demo.yaml ==
#create file
nano awx-demo.yaml

#Add below to the file
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
  nodeport_port: 32000

== 11.  Add Instance to Kustomization ==
# Update your kustomization.yaml to include awx-demo.yaml
#edit file
nano kustomization.yaml

#add - awx-demo.yaml under resources
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
  - awx-demo.yaml

images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1

namespace: awx

== 12. Reapply Kustomize Configuration ==
kubectl apply -k .

== 13. Check POD Status
kubectl get pods -n awx

== 14. View Logs ==
kubectl logs -f deployment/awx-operator-controller-manager -c awx-manager -n awx

== 15.  Retrieve Admin Password ==
 kubectl get secret awx-demo-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode ; echo
 
 == 16. Access the AWX Dashboard ==
 http://<your-server-ip>:32000
 
 #Username: admin
 #Password: (from previous step)