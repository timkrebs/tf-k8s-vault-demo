# HashiCorp Vault + Kubernetes Integration mit VSO

Eine vereinfachte Anleitung zum sicheren Verwalten von Kubernetes-Geheimnissen mit HashiCorp Vault und dem Vault Secrets Operator (VSO).

## Voraussetzungen

- Kubernetes-Cluster läuft
- HashiCorp Vault-Server vom Cluster aus zugänglich
- CLI-Tools `kubectl` und `vault` konfiguriert
- Helm installiert

## Schritt 1: Konfigurieren Sie Vault Secrets

Richte zunächst die Secrets in Vault ein:

```bash
# Enable KV v2 secret engine
vault secrets enable -path=secret kv-v2

# Create example secrets
vault kv put secret/myapp \
    username=admin \
    password=supersecret \
    api_key=abc123xyz

vault kv put secret/database \
    host=db.example.com \
    port=5432 \
    username=dbuser \
    password=dbpass123

# Verify secrets were created
vault kv get secret/myapp
```

## Schritt 2: Vault-Richtlinie erstellen

Erstelle eine Policy, die das Lesen von secrets erlaubt:

```bash
vault policy write app-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

# Verify policy
vault policy read app-secrets
```

## Schritt 3: Einrichten der Kubernetes-Authentifizierung

### Erstellen eine Service Accounts und RBAC

```bash
# Create namespaces
kubectl create namespace vault-secrets-operator-system
kubectl create namespace demo-app

# Create service account for VSO
kubectl create serviceaccount vault-secrets-operator -n vault-secrets-operator-system

# Create token secret (required for Kubernetes 1.21+)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: vault-secrets-operator-token
  namespace: vault-secrets-operator-system
  annotations:
    kubernetes.io/service-account.name: vault-secrets-operator
type: kubernetes.io/service-account-token
EOF

# Set up RBAC permissions
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-token-reviewer
rules:
- apiGroups: [""]
  resources: ["serviceaccounts"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
- apiGroups: ["authentication.k8s.io"]
  resources: ["tokenreviews"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-token-reviewer
subjects:
- kind: ServiceAccount
  name: vault-secrets-operator
  namespace: vault-secrets-operator-system
EOF

# Wait for token creation
sleep 15
```

### Konfigurieren von Vault Kubernetes Auth

```bash
# Get cluster information
KUBE_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
KUBE_TOKEN=$(kubectl get secret vault-secrets-operator-token -n vault-secrets-operator-system -o jsonpath='{.data.token}' | base64 -d)

# Enable Kubernetes authentication in Vault
vault auth enable kubernetes

# Configure Vault with cluster details
vault write auth/kubernetes/config \
    kubernetes_host="$KUBE_HOST" \
    kubernetes_ca_cert="$KUBE_CA_CERT" \
    token_reviewer_jwt="$KUBE_TOKEN"
```

## Schritt 4: Erstellen einer Vault Role mit Audience Claim


```bash
# Create Vault role with audience claim
vault write auth/kubernetes/role/vso-role \
    bound_service_account_names=vault-secrets-operator,default \
    bound_service_account_namespaces=vault-secrets-operator-system,demo-app \
    policies=app-secrets \
    audience="https://kubernetes.default.svc" \
    ttl=24h

# Verify role configuration
vault read auth/kubernetes/role/vso-role
```

**Wichtige Änderungen für Vault 1.24+:**
- `audience=https://kubernetes.default.svc` – Erforderlicher Anspruch für JWT-Token (in der Vault-Rolle festgelegt)
- Die Überprüfung des Anspruchs erfolgt durch die Vault-Rolle, nicht in der VaultAuth-Ressource

## Schritt 5: Installieren des Vault Secrets Operator

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install VSO with default configuration
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --namespace vault-secrets-operator-system \
    --set defaultVaultConnection.enabled=true \
    --set defaultVaultConnection.address="$VAULT_ADDR" \
    --set defaultAuthMethod.enabled=true \
    --set defaultAuthMethod.method=kubernetes \
    --set defaultAuthMethod.mount=kubernetes \
    --set defaultAuthMethod.kubernetes.role=vso-role \
    --set defaultAuthMethod.kubernetes.serviceAccount=vault-secrets-operator

# Verify installation
kubectl get pods -n vault-secrets-operator-system
```

## Schritt 6: Konfigurieren der Secret synchronisation

### Erstellen der VaultConnection und VaultAuth für demo-app

```bash
# Create VaultConnection in demo-app namespace
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: demo-app
spec:
  address: "$VAULT_ADDR"
EOF

# Create VaultAuth (audience is handled by Vault role configuration)
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: demo-app
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: vso-role
    serviceAccount: default
  vaultConnectionRef: default
EOF
```

### Erstellen der VaultStaticSecret Ressourcen

```bash
# Create VaultStaticSecret resources to sync secrets
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: myapp-secret
  namespace: demo-app
spec:
  type: kv-v2
  mount: secret
  path: myapp
  destination:
    name: myapp-credentials
    create: true
  vaultAuthRef: vault-auth
  refreshAfter: 30s
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: database-secret
  namespace: demo-app
spec:
  type: kv-v2
  mount: secret
  path: database
  destination:
    name: database-credentials
    create: true
  vaultAuthRef: vault-auth
  refreshAfter: 30s
EOF
```

## Schritt 7:Überprüfen Sie, ob alles funktioniert.

```bash
# Check VSO resources status
kubectl describe vaultauth vault-auth -n demo-app
kubectl describe vaultstaticsecret myapp-secret -n demo-app

# Wait for synchronization (30-90 seconds)
sleep 60

# Verify secrets were created
kubectl get secrets -n demo-app

# Check secret contents
kubectl get secret myapp-credentials -n demo-app -o jsonpath='{.data}' | \
  jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
```

Erwarteter Output:
```
username: admin
password: supersecret
api_key: abc123xyz
```


## Wichtige Sicherheitshinweise

- **Audience Claim**: Erforderlich in Vault 1.21+ für die JWT-Token-Validierung
- **Service Account Tokens**: Müssen explizit in Kubernetes erstellt werden
- **RBAC**: VSO benötigt clusterweite Berechtigungen für die namensraumübergreifende Token-Validierung

## Architekturübersicht

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │      VSO         │    │   HashiCorp     │
│     Cluster     │◄──►│   (Operator)     │◄──►│     Vault       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
    ┌────▼────┐              ┌───▼───┐               ┌───▼───┐
    │ K8s     │              │Vault  │               │Secret │
    │Secrets  │              │Auth   │               │Engine │
    └─────────┘              └───────┘               └───────┘
```

1. VSO authentifiziert sich bei Vault mithilfe eines Kubernetes-Dienstkontos.
2. VSO liest Secrets aus Vault basierend auf VaultStaticSecret-Konfigurationen.
3. VSO erstellt/aktualisiert Kubernetes-Secrets automatisch.
4. Anwendungen verwenden Secrets als standardmäßige Kubernetes-Secrets.
