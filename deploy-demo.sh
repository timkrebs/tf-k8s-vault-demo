#!/bin/bash

# Vault Secrets Demo Deployment Script
# This script deploys the demo application that showcases Vault secrets integration
# 
# Prerequisites:
# 1. EKS cluster is running (deployed via terraform)
# 2. kubectl is configured for your EKS cluster
# 3. HashiCorp Vault is accessible and configured
# 4. Vault Secrets Operator (VSO) is installed
# 5. Docker is available for building the image

set -e

# Configuration
APP_NAME="vault-secrets-demo"
NAMESPACE="demo-app"
IMAGE_TAG="latest"
AWS_REGION="${AWS_REGION:-us-east-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available and configured
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig"
        exit 1
    fi
    
    # Check if VSO is installed
    if ! kubectl get crd vaultauths.secrets.hashicorp.com &> /dev/null; then
        log_error "Vault Secrets Operator CRDs not found. VSO must be installed before deploying the demo."
        log_info ""
        log_info "To install VSO, follow these steps:"
        log_info "1. Add HashiCorp Helm repository:"
        log_info "   helm repo add hashicorp https://helm.releases.hashicorp.com"
        log_info "   helm repo update"
        log_info ""
        log_info "2. Install VSO:"
        log_info "   helm install vault-secrets-operator hashicorp/vault-secrets-operator \\"
        log_info "     --namespace vault-secrets-operator-system \\"
        log_info "     --create-namespace \\"
        log_info "     --set defaultVaultConnection.enabled=true \\"
        log_info "     --set defaultVaultConnection.address=\"\$VAULT_ADDR\" \\"
        log_info "     --set defaultAuthMethod.enabled=true \\"
        log_info "     --set defaultAuthMethod.method=kubernetes \\"
        log_info "     --set defaultAuthMethod.mount=kubernetes \\"
        log_info "     --set defaultAuthMethod.kubernetes.role=vso-role \\"
        log_info "     --set defaultAuthMethod.kubernetes.serviceAccount=vault-secrets-operator"
        log_info ""
        log_info "3. Wait for VSO to be ready:"
        log_info "   kubectl wait --for=condition=available --timeout=300s deployment/vault-secrets-operator -n vault-secrets-operator-system"
        log_info ""
        log_info "For complete setup instructions, see: docs/K8s-VSO-config-V2.md"
        log_info ""
        read -p "Would you like to install VSO automatically? (y/N): " install_vso
        if [[ "$install_vso" =~ ^[Yy]$ ]]; then
            install_vso_automatically
        else
            log_error "VSO installation is required. Exiting."
            exit 1
        fi
    else
        log_success "Vault Secrets Operator CRDs found"
    fi
    
    log_success "Prerequisites check completed"
}

# Automatically install VSO
install_vso_automatically() {
    log_info "Installing Vault Secrets Operator automatically..."
    
    # Check if Helm is available
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first:"
        log_info "https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    # Check if VAULT_ADDR is set
    if [ -z "$VAULT_ADDR" ]; then
        log_warning "VAULT_ADDR environment variable not set"
        read -p "Enter your Vault address (e.g., https://vault_uri.hashicorp.io): " VAULT_ADDR
        if [ -z "$VAULT_ADDR" ]; then
            log_error "Vault address is required for VSO installation"
            exit 1
        fi
        export VAULT_ADDR
    fi
    
    log_info "Using Vault address: $VAULT_ADDR"
    
    # Add HashiCorp Helm repository
    log_info "Adding HashiCorp Helm repository..."
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update
    
    # Install VSO
    log_info "Installing Vault Secrets Operator..."
    helm install vault-secrets-operator hashicorp/vault-secrets-operator \
        --namespace vault-secrets-operator-system \
        --create-namespace \
        --set defaultVaultConnection.enabled=true \
        --set defaultVaultConnection.address="$VAULT_ADDR" \
        --set defaultAuthMethod.enabled=true \
        --set defaultAuthMethod.method=kubernetes \
        --set defaultAuthMethod.mount=kubernetes \
        --set defaultAuthMethod.kubernetes.role=vso-role \
        --set defaultAuthMethod.kubernetes.serviceAccount=vault-secrets-operator
    
    # Wait for VSO to be ready - try different possible deployment names
    log_info "Waiting for VSO to be ready..."
    local vso_deployment=""
    
    # Check for possible deployment names
    for name in "vault-secrets-operator" "vault-secrets-operator-controller-manager" "vso-controller-manager"; do
        if kubectl get deployment "$name" -n vault-secrets-operator-system &> /dev/null; then
            vso_deployment="$name"
            break
        fi
    done
    
    if [ -n "$vso_deployment" ]; then
        log_info "Found VSO deployment: $vso_deployment"
        kubectl wait --for=condition=available --timeout=300s deployment/"$vso_deployment" -n vault-secrets-operator-system
    else
        log_warning "VSO deployment not found with expected names. Checking for any deployment..."
        kubectl get deployments -n vault-secrets-operator-system
        sleep 30  # Give it some time
    fi
    
    # Verify CRDs are available
    local retry_count=0
    while [ $retry_count -lt 12 ]; do  # Wait up to 60 seconds
        if kubectl get crd vaultauths.secrets.hashicorp.com &> /dev/null; then
            log_success "Vault Secrets Operator installed successfully"
            break
        fi
        log_info "Waiting for VSO CRDs to be available... (attempt $((retry_count + 1))/12)"
        sleep 5
        retry_count=$((retry_count + 1))
    done
    
    if ! kubectl get crd vaultauths.secrets.hashicorp.com &> /dev/null; then
        log_error "VSO installation failed - CRDs not found after waiting"
        log_info "Available CRDs:"
        kubectl get crd | grep -i vault || echo "No Vault-related CRDs found"
        exit 1
    fi
    
    log_warning "IMPORTANT: Now configuring Vault authentication automatically!"
    log_info ""
    read -p "Would you like to configure Vault automatically? (Y/n): " configure_vault
    if [[ "$configure_vault" =~ ^[Nn]$ ]]; then
        log_info "Manual configuration required. Follow docs/K8s-VSO-config-V2.md"
        log_info "1. Set up Vault secrets (secret/myapp, secret/database)"
        log_info "2. Create Vault policies"
        log_info "3. Configure Kubernetes authentication in Vault"
        log_info "4. Create the Vault role 'vso-role'"
        read -p "Press Enter when you have completed the Vault configuration..."
    else
        configure_vault_automatically
    fi
}

# Automatically configure Vault
configure_vault_automatically() {
    log_info "Configuring Vault automatically..."
    
    # Check if vault CLI is available
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI is not installed. Please install vault CLI first:"
        log_info "https://developer.hashicorp.com/vault/docs/install"
        exit 1
    fi
    
    # Test Vault connectivity
    log_info "Testing Vault connectivity..."
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        log_info "Please ensure:"
        log_info "1. VAULT_ADDR is set correctly: $VAULT_ADDR"
        log_info "2. VAULT_TOKEN is set with appropriate permissions"
        log_info "3. Vault is accessible from this machine"
        exit 1
    fi
    
    log_success "Connected to Vault successfully"
    
    # Step 1: Enable KV v2 secret engine
    log_info "Step 1: Enabling KV v2 secret engine..."
    if vault secrets list | grep -q "^secret/"; then
        log_info "KV v2 secret engine already enabled at secret/"
    else
        vault secrets enable -path=secret kv-v2
        log_success "KV v2 secret engine enabled"
    fi
    
    # Step 2: Create example secrets
    log_info "Step 2: Creating demo secrets..."
    
    log_info "Creating secret/myapp..."
    vault kv put secret/myapp \
        username=admin \
        password=supersecret \
        api_key=abc123xyz
    
    log_info "Creating secret/database..."
    vault kv put secret/database \
        host=db.example.com \
        port=5432 \
        username=dbuser \
        password=dbpass123
    
    log_success "Demo secrets created"
    
    # Verify secrets
    log_info "Verifying secrets..."
    vault kv get secret/myapp
    vault kv get secret/database
    
    # Step 3: Create Vault policy
    log_info "Step 3: Creating Vault policy..."
    vault policy write app-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
    
    log_success "Policy 'app-secrets' created"
    vault policy read app-secrets
    
    # Step 4: Set up Kubernetes authentication
    log_info "Step 4: Setting up Kubernetes authentication..."
    
    # Create VSO service account and RBAC if not exists
    log_info "Creating VSO service account and RBAC..."
    
    kubectl create namespace vault-secrets-operator-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create serviceaccount vault-secrets-operator -n vault-secrets-operator-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create token secret for VSO service account
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
    log_info "Waiting for service account token creation..."
    sleep 15
    
    # Get cluster information
    log_info "Getting Kubernetes cluster information..."
    KUBE_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
    KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
    KUBE_TOKEN=$(kubectl get secret vault-secrets-operator-token -n vault-secrets-operator-system -o jsonpath='{.data.token}' | base64 -d)
    
    if [ -z "$KUBE_TOKEN" ]; then
        log_error "Failed to get service account token"
        log_info "Trying alternative method..."
        # Try to get token from service account directly
        KUBE_TOKEN=$(kubectl create token vault-secrets-operator -n vault-secrets-operator-system --duration=8760h)
    fi
    
    log_info "Cluster Host: $KUBE_HOST"
    log_info "Token retrieved: ${#KUBE_TOKEN} characters"
    
    # Enable Kubernetes authentication in Vault
    log_info "Enabling Kubernetes authentication in Vault..."
    if vault auth list | grep -q "^kubernetes/"; then
        log_info "Kubernetes auth already enabled"
    else
        vault auth enable kubernetes
        log_success "Kubernetes auth enabled"
    fi
    
    # Configure Vault with cluster details
    log_info "Configuring Vault with Kubernetes cluster details..."
    vault write auth/kubernetes/config \
        kubernetes_host="$KUBE_HOST" \
        kubernetes_ca_cert="$KUBE_CA_CERT" \
        token_reviewer_jwt="$KUBE_TOKEN"
    
    log_success "Kubernetes auth configured"
    
    # Step 5: Create Vault role with audience claim
    log_info "Step 5: Creating Vault role 'vso-role'..."
    vault write auth/kubernetes/role/vso-role \
        bound_service_account_names=vault-secrets-operator,default \
        bound_service_account_namespaces=vault-secrets-operator-system,demo-app \
        policies=app-secrets \
        audience="https://kubernetes.default.svc" \
        ttl=24h
    
    log_success "Vault role 'vso-role' created"
    
    # Verify role configuration
    log_info "Verifying role configuration..."
    vault read auth/kubernetes/role/vso-role
    
    log_success "Vault configuration completed successfully!"
    log_info ""
    log_info "Summary of what was configured:"
    log_info "✓ KV v2 secret engine enabled at 'secret/'"
    log_info "✓ Demo secrets created: secret/myapp, secret/database"
    log_info "✓ Policy 'app-secrets' created with read access"
    log_info "✓ Kubernetes authentication enabled and configured"
    log_info "✓ Vault role 'vso-role' created"
    log_info "✓ Service account and RBAC configured"
    log_info ""
    log_success "Ready to deploy the demo application!"
}

# Check VSO installation status
check_vso_status() {
    log_info "Checking Vault Secrets Operator status..."
    
    # Check if VSO CRDs exist
    if kubectl get crd vaultauths.secrets.hashicorp.com &> /dev/null; then
        log_success "VSO CRDs are installed"
        
        # Check if VSO namespace exists
        if kubectl get namespace vault-secrets-operator-system &> /dev/null; then
            log_success "VSO namespace exists"
            
            # Check VSO deployment status
            if kubectl get deployment vault-secrets-operator -n vault-secrets-operator-system &> /dev/null; then
                log_info "VSO deployment status:"
                kubectl get deployment vault-secrets-operator -n vault-secrets-operator-system
                
                # Check if VSO is running
                if kubectl get pods -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator --field-selector=status.phase=Running &> /dev/null; then
                    log_success "VSO is running"
                    
                    # Show VSO pods
                    log_info "VSO pods:"
                    kubectl get pods -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
                    
                else
                    log_warning "VSO pods are not running"
                    kubectl get pods -n vault-secrets-operator-system
                fi
            else
                log_warning "VSO deployment not found"
            fi
        else
            log_warning "VSO namespace does not exist"
        fi
        
        # List available VSO CRDs
        log_info "Available VSO CRDs:"
        kubectl get crd | grep secrets.hashicorp.com || log_warning "No VSO CRDs found"
        
    else
        log_error "VSO CRDs are not installed"
        log_info "Run './deploy-demo.sh install-vso' to install VSO"
    fi
    
    echo ""
    log_info "To install VSO: ./deploy-demo.sh install-vso"
    log_info "To deploy demo: ./deploy-demo.sh deploy"
}

# Build and push Docker image
build_image() {
    log_info "Building Docker image..."
    
    cd app
    
    # Build for linux/amd64 platform (EKS nodes are x86_64)
    log_info "Building Docker image for linux/amd64 platform..."
    docker build --platform linux/amd64 -t ${APP_NAME}:${IMAGE_TAG} .
    
    # Check if we're using local development (kind/minikube) or AWS EKS
    if command -v kind &> /dev/null && kind get clusters | grep -q "kind"; then
        log_info "Loading image into kind cluster..."
        kind load docker-image ${APP_NAME}:${IMAGE_TAG}
    elif command -v minikube &> /dev/null && minikube status &> /dev/null; then
        log_info "Loading image into minikube..."
        minikube image load ${APP_NAME}:${IMAGE_TAG}
    else
        # Try to get ECR repository URL from Terraform output
        if [ -f "../terraform/.terraform/terraform.tfstate" ]; then
            log_info "Detecting ECR repository from Terraform state..."
            ECR_REPO_URL=$(cd ../terraform && terraform output -raw ecr_repository_url 2>/dev/null)
            
            if [ -n "$ECR_REPO_URL" ]; then
                log_info "Found ECR repository: $ECR_REPO_URL"
                
                # Get AWS account ID and region for ECR login
                AWS_ACCOUNT_ID=$(echo "$ECR_REPO_URL" | cut -d'.' -f1 | cut -d'/' -f3)
                ECR_REGION=$(echo "$ECR_REPO_URL" | cut -d'.' -f4)
                
                log_info "Logging into ECR..."
                aws ecr get-login-password --region ${ECR_REGION} | \
                    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com
                
                log_info "Tagging image for ECR..."
                docker tag ${APP_NAME}:${IMAGE_TAG} ${ECR_REPO_URL}:${IMAGE_TAG}
                docker tag ${APP_NAME}:${IMAGE_TAG} ${ECR_REPO_URL}:latest
                
                log_info "Pushing image to ECR..."
                if ! docker push ${ECR_REPO_URL}:${IMAGE_TAG}; then
                    log_error "Failed to push image to ECR"
                    log_info "This might be due to architecture mismatch or network issues"
                    exit 1
                fi
                docker push ${ECR_REPO_URL}:latest
                
                # Update the deployment to use ECR image
                export ECR_IMAGE="${ECR_REPO_URL}:${IMAGE_TAG}"
                log_success "Image pushed to ECR: $ECR_IMAGE"
            else
                log_error "Could not find ECR repository URL in Terraform output"
                log_info "Make sure you've run 'terraform apply' and the ECR repository exists"
                exit 1
            fi
        else
            log_error "Terraform state file not found. Please run 'terraform apply' first"
            log_info "Or manually set ECR_REPO_URL environment variable"
            exit 1
        fi
    fi
    
    cd ..
    log_success "Docker image built and available"
}

# Deploy Kubernetes resources
deploy_k8s_resources() {
    log_info "Deploying Kubernetes resources..."
    
    # Create namespace and service account
    log_info "Creating namespace and service account..."
    kubectl apply -f app/k8s/namespace.yaml
    
    # Wait for namespace to be ready
    #kubectl wait --for=condition=Ready namespace/${NAMESPACE} --timeout=30s || true
    
    # Get Vault address from user or environment
    if [ -z "$VAULT_ADDR" ]; then
        log_warning "VAULT_ADDR environment variable not set"
        read -p "Enter your Vault address (e.g., https://vault.example.com:8200): " VAULT_ADDR
        if [ -z "$VAULT_ADDR" ]; then
            log_error "Vault address is required"
            exit 1
        fi
    fi
    
    # Update VaultConnection with the actual Vault address
    log_info "Updating VaultConnection with Vault address: $VAULT_ADDR"
    sed "s|address: \"https://vault.example.com:8200\"|address: \"$VAULT_ADDR\"|g" app/k8s/vault-connection.yaml > /tmp/vault-connection.yaml
    kubectl apply -f /tmp/vault-connection.yaml
    rm /tmp/vault-connection.yaml
    
    # Deploy Vault authentication and secrets
    log_info "Deploying Vault authentication resources..."
    kubectl apply -f app/k8s/vault-auth.yaml
    kubectl apply -f app/k8s/vault-static-secrets.yaml
    
    # Wait a bit for VSO to sync secrets
    log_info "Waiting for VSO to sync secrets (this may take up to 60 seconds)..."
    sleep 30
    
    # Update deployment with ECR image if available
    if [ -n "$ECR_IMAGE" ]; then
        log_info "Updating deployment to use ECR image: $ECR_IMAGE"
        sed "s|image: vault-secrets-demo:latest|image: $ECR_IMAGE|g" app/k8s/deployment.yaml > /tmp/deployment.yaml
        kubectl apply -f /tmp/deployment.yaml
        rm /tmp/deployment.yaml
    else
        log_info "Deploying with local image..."
        kubectl apply -f app/k8s/deployment.yaml
    fi
    
    kubectl apply -f app/k8s/service.yaml
    
    log_success "Kubernetes resources deployed successfully"
}

# Deploy ingress with LoadBalancer hostname
deploy_ingress() {
    log_info "Deploying ingress with LoadBalancer hostname..."
    
    # Wait for LoadBalancer to get external hostname
    log_info "Waiting for LoadBalancer to get external hostname (this may take 2-3 minutes)..."
    local timeout=300  # 5 minutes timeout
    local counter=0
    local LB_HOSTNAME=""
    
    while [ $counter -lt $timeout ]; do
        LB_HOSTNAME=$(kubectl get service ${APP_NAME}-lb -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [ -n "$LB_HOSTNAME" ]; then
            log_success "LoadBalancer hostname found: $LB_HOSTNAME"
            break
        fi
        
        if [ $((counter % 30)) -eq 0 ]; then
            log_info "Still waiting for LoadBalancer hostname... (${counter}s elapsed)"
        fi
        
        sleep 5
        counter=$((counter + 5))
    done
    
    if [ -z "$LB_HOSTNAME" ]; then
        log_warning "LoadBalancer hostname not available after ${timeout}s. Skipping ingress deployment."
        log_info "You can deploy the ingress manually once the LoadBalancer is ready."
        return
    fi
    
    # Update ingress with actual LoadBalancer hostname
    log_info "Creating ingress with hostname: $LB_HOSTNAME"
    sed "s|LOADBALANCER_HOSTNAME_PLACEHOLDER|$LB_HOSTNAME|g" app/k8s/ingress.yaml > /tmp/ingress.yaml
    kubectl apply -f /tmp/ingress.yaml
    rm /tmp/ingress.yaml
    
    log_success "Ingress deployed successfully with hostname: $LB_HOSTNAME"
}

# Check deployment status
check_deployment() {
    log_info "Checking deployment status..."
    
    # Wait for deployment to be ready
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/${APP_NAME} -n ${NAMESPACE}
    
    # Check if secrets were synced successfully
    log_info "Checking if Vault secrets were synced..."
    
    if kubectl get secret myapp-credentials -n ${NAMESPACE} &> /dev/null; then
        log_success "myapp-credentials secret found"
    else
        log_warning "myapp-credentials secret not found - VSO may still be syncing"
    fi
    
    if kubectl get secret database-credentials -n ${NAMESPACE} &> /dev/null; then
        log_success "database-credentials secret found"
    else
        log_warning "database-credentials secret not found - VSO may still be syncing"
    fi
    
    # Show pod status
    log_info "Pod status:"
    kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}
    
    # Show service status
    log_info "Service status:"
    kubectl get services -n ${NAMESPACE}
    
    log_success "Deployment check completed"
}

# Get access information
get_access_info() {
    log_info "Getting access information..."
    
    # Ensure kubectl is connected to the right cluster
    log_info "Ensuring kubectl is connected to the correct EKS cluster..."
    if [ -f "terraform/terraform.tfstate" ]; then
        CLUSTER_NAME=$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "")
        if [ -n "$CLUSTER_NAME" ]; then
            log_info "Updating kubeconfig for cluster: $CLUSTER_NAME"
            aws eks update-kubeconfig --region ${AWS_REGION} --name "$CLUSTER_NAME" &>/dev/null || log_warning "Failed to update kubeconfig"
        fi
    fi
    
    # Wait a moment for the command to take effect
    sleep 2
    
    # Try to get LoadBalancer external hostname with retries
    log_info "Retrieving LoadBalancer information..."
    local retry_count=0
    local max_retries=6
    LB_HOSTNAME=""
    
    while [ $retry_count -lt $max_retries ]; do
        LB_HOSTNAME=$(kubectl get service ${APP_NAME}-lb -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$LB_HOSTNAME" ]; then
            break
        fi
        log_info "Waiting for LoadBalancer hostname... (attempt $((retry_count + 1))/$max_retries)"
        sleep 10
        retry_count=$((retry_count + 1))
    done
    
    # Display comprehensive access information
    echo ""
    echo "🎉 ========================================"
    echo "🎉   VAULT SECRETS DEMO - ACCESS INFO"
    echo "🎉 ========================================"
    echo ""
    
    if [ -n "$LB_HOSTNAME" ]; then
        log_success "✅ Application is ready and accessible!"
        echo ""
        echo "🌍 MAIN APPLICATION URL:"
        echo "   👉 http://$LB_HOSTNAME"
        echo ""
        echo "🔍 API ENDPOINTS:"
        echo "   Health Check: http://$LB_HOSTNAME/api/health"
        echo "   Secrets API:  http://$LB_HOSTNAME/api/secrets"
        echo "   Vault Status: http://$LB_HOSTNAME/api/vault-status"
        echo ""
        
        # Test if the application is responding
        log_info "Testing application connectivity..."
        if curl -s --max-time 10 "http://$LB_HOSTNAME/api/health" &>/dev/null; then
            log_success "✅ Application is responding correctly!"
        else
            log_warning "⚠️  Application may still be starting up..."
            log_info "If you get a 'Forbidden' error, make sure you're using the LoadBalancer URL above,"
            log_info "NOT the Kubernetes cluster API URL."
        fi
        
        # Check if ingress is deployed and get its hostname
        INGRESS_HOSTNAME=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
        if [ -n "$INGRESS_HOSTNAME" ]; then
            echo "🚪 INGRESS URL (Alternative Access):"
            echo "   👉 http://$INGRESS_HOSTNAME"
            echo "   Note: Ingress might take additional time to become ready"
            echo ""
        fi
        
    else
        log_warning "⚠️  LoadBalancer external hostname not yet available"
        echo ""
        echo "🔧 TEMPORARY ACCESS (Port Forward):"
        echo "   Run: kubectl port-forward service/${APP_NAME}-service 8080:80 -n ${NAMESPACE}"
        echo "   Then visit: http://localhost:8080"
        echo ""
        log_info "The LoadBalancer may take 2-3 minutes to be ready. Check again with:"
        echo "   kubectl get service ${APP_NAME}-lb -n ${NAMESPACE}"
    fi
    
    echo "📊 MONITORING & DEBUG:"
    echo "   Service Status: kubectl get service ${APP_NAME}-lb -n ${NAMESPACE}"
    echo "   Pod Logs:      kubectl logs -f deployment/${APP_NAME} -n ${NAMESPACE}"
    echo "   Pod Status:    kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}"
    echo ""
    
    # Show logs command
    log_info "To view application logs:"
    echo "  kubectl logs -f deployment/${APP_NAME} -n ${NAMESPACE}"
    
    # Show VSO status command
    log_info "To check VSO status:"
    echo "  kubectl describe vaultauth vault-auth -n ${NAMESPACE}"
    echo "  kubectl describe vaultstaticsecret myapp-secret -n ${NAMESPACE}"
    echo "  kubectl describe vaultstaticsecret database-secret -n ${NAMESPACE}"
    
    # Show LoadBalancer and Ingress status
    log_info "To check LoadBalancer status:"
    echo "  kubectl get service ${APP_NAME}-lb -n ${NAMESPACE}"
    echo "  kubectl describe service ${APP_NAME}-lb -n ${NAMESPACE}"
    
    if kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} &>/dev/null; then
        log_info "To check Ingress status:"
        echo "  kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE}"
        echo "  kubectl describe ingress ${APP_NAME}-ingress -n ${NAMESPACE}"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up demo application..."
    
    kubectl delete -f app/k8s/ --ignore-not-found=true
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    echo "=================================="
    echo "  Vault Secrets Demo Deployment"
    echo "=================================="
    echo ""
    
    case "${1:-deploy}" in
        deploy)
            check_prerequisites
            build_image
            deploy_k8s_resources
            check_deployment
            get_access_info
            ;;
        deploy-with-ingress)
            check_prerequisites
            build_image
            deploy_k8s_resources
            check_deployment
            deploy_ingress
            get_access_info
            ;;
        cleanup)
            cleanup
            ;;
        install-vso)
            if [ -z "$VAULT_ADDR" ]; then
                log_warning "Please set VAULT_ADDR environment variable"
                read -p "Enter your Vault address (e.g., https://vault_uri.hashicorp.io): " VAULT_ADDR
                export VAULT_ADDR
            fi
            install_vso_automatically
            ;;
        configure-vault)
            if [ -z "$VAULT_ADDR" ]; then
                log_warning "Please set VAULT_ADDR environment variable"
                read -p "Enter your Vault address (e.g., https://vault_uri.hashicorp.io): " VAULT_ADDR
                export VAULT_ADDR
            fi
            configure_vault_automatically
            ;;
        setup-all)
            if [ -z "$VAULT_ADDR" ]; then
                log_warning "Please set VAULT_ADDR environment variable"
                read -p "Enter your Vault address (e.g., https://vault_uri.hashicorp.io): " VAULT_ADDR
                export VAULT_ADDR
            fi
            check_prerequisites
            install_vso_automatically
            log_info "Now deploying the demo application..."
            build_image
            deploy_k8s_resources
            check_deployment
            get_access_info
            ;;
        check-vso)
            check_vso_status
            ;;
        fix-image)
            log_info "Fixing Docker image architecture issue..."
            build_image
            log_info "Redeploying with fixed image..."
            kubectl delete deployment ${APP_NAME} -n ${NAMESPACE} --ignore-not-found=true
            sleep 10
            deploy_k8s_resources
            check_deployment
            ;;
        status)
            check_deployment
            get_access_info
            ;;
        *)
            echo "Usage: $0 [deploy|deploy-with-ingress|setup-all|install-vso|configure-vault|check-vso|fix-image|cleanup|status]"
            echo ""
            echo "Commands:"
            echo "  deploy              - Deploy the demo application with LoadBalancer (default)"
            echo "  deploy-with-ingress - Deploy with both LoadBalancer and Ingress"
            echo "  setup-all           - Complete setup: Install VSO + Configure Vault + Deploy Demo"
            echo "  install-vso         - Install Vault Secrets Operator only"
            echo "  configure-vault     - Configure Vault secrets, policies, and authentication only"
            echo "  check-vso           - Check VSO installation status"
            echo "  fix-image           - Fix Docker image architecture issues and redeploy"
            echo "  cleanup             - Remove the demo application"
            echo "  status              - Check deployment status and get access info"
            echo ""
            echo "Prerequisites:"
            echo "  - Set VAULT_ADDR and VAULT_TOKEN environment variables"
            echo "  - Install vault CLI: https://developer.hashicorp.com/vault/docs/install"
            echo "  - Install helm: https://helm.sh/docs/intro/install/"
            echo ""
            echo "Quick Start:"
            echo "  export VAULT_ADDR='https://vault_uri.hashicorp.io'"
            echo "  export VAULT_TOKEN='your-vault-token'"
            echo "  ./deploy-demo.sh setup-all"
            echo ""
            echo "Notes:"
            echo "  - ECR integration is automatic when Terraform state is detected"
            echo "  - Ingress deployment waits for LoadBalancer hostname"
            echo "  - Full automation configures Vault secrets, policies, and K8s auth"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
