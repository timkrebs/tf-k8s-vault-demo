# Vault Secrets Demo Application

This demo application showcases the **complete integration** between HashiCorp Vault, Kubernetes, and the Vault Secrets Operator (VSO). It demonstrates how secrets stored in Vault are automatically synchronized to Kubernetes secrets and consumed by applications with **full automation** from infrastructure to application deployment.

## What This Demo Shows

- **Complete Infrastructure**: Automated EKS cluster deployment with ECR integration
- **Vault Integration**: Fully automated Vault configuration with secrets, policies, and authentication
- **VSO Automation**: Automatic installation and configuration of Vault Secrets Operator
- **Security**: Kubernetes JWT authentication with proper RBAC and service accounts
- **Real-time Display**: Beautiful web interface showing live secret synchronization
- **Production Ready**: Includes health checks, monitoring, load balancing, and ingress support
- **Architecture Clarity**: Visual representation of the complete Vault → VSO → K8s → App flow

## Project Structure

```
tf-k8s-vault-demo/
├── app/                          # Demo application
│   ├── app.py                    # Flask web application
│   ├── templates/index.html      # Web interface
│   ├── Dockerfile               # Container image
│   ├── requirements.txt         # Python dependencies
│   └── k8s/                     # Kubernetes manifests
│       ├── namespace.yaml       # Namespace and service account
│       ├── vault-connection.yaml # VSO VaultConnection resource
│       ├── vault-auth.yaml      # VSO authentication config
│       ├── vault-static-secrets.yaml # Secret synchronization config
│       ├── deployment.yaml      # Application deployment
│       ├── service.yaml         # Services (ClusterIP and LoadBalancer)
│       └── ingress.yaml         # Optional ingress configuration
├── terraform/                   # EKS infrastructure with ECR
├── docs/K8s-VSO-config-V2.md   # Vault + VSO setup tutorial (reference)
├── deploy-demo.sh              # Complete automation script
└── README-demo.md              # This comprehensive guide
```

## Quick Start (Fully Automated)

### Prerequisites

**Required Tools** (install these first):
- [AWS CLI](https://aws.amazon.com/cli/) - configured with appropriate permissions
- [Terraform](https://terraform.io/downloads) - for infrastructure deployment
- [Docker](https://docker.com/get-started) - for building container images
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - for Kubernetes management
- [Helm](https://helm.sh/docs/intro/install/) - for installing VSO
- [Vault CLI](https://developer.hashicorp.com/vault/docs/install) - for Vault configuration

**Required Access**:
- **Vault Server**: Access to a HashiCorp Vault instance (like `https://vault_uri.hashicorp.io`)
- **Vault Token**: Admin token with permissions to configure auth methods and secrets
- **AWS Account**: With permissions to create EKS clusters, ECR repositories, and VPCs

### **One-Command Complete Setup**

For the fastest setup, use the complete automation:
change the Terraform cloud Variables accordingly to your Setup in `terraform/terraform.tf`

```bash
cloud { 
    
    organization = "<tf-org>" 

    workspaces { 
      name = "<tf-workspace>" 
    } 
} 
```

```bash
# 1. Clone this repository
git clone <your-repo-url>
cd tf-k8s-vault-demo

# 2. Deploy infrastructure
cd terraform
terraform init
terraform apply  # Type 'yes' when prompted

# 3. Set your Vault credentials
export VAULT_ADDR="https://vault_uri.hashicorp.io"
export VAULT_TOKEN="your-vault-root-or-admin-token"

# 4. Run complete automation (installs VSO + configures Vault + deploys app)
cd ..
./deploy-demo.sh setup-all
```

**That's it!** 🎉 The script will:
- ✅ Install and configure Vault Secrets Operator
- ✅ Create Vault secrets, policies, and authentication
- ✅ Build and push Docker image to ECR
- ✅ Deploy the demo application
- ✅ Display the LoadBalancer URL for access

### 🎛️ **Step-by-Step Setup (If You Prefer Manual Control)**

#### Step 1: Deploy EKS Infrastructure
```bash
cd terraform
terraform init
terraform apply
```

#### Step 2: Set Environment Variables
```bash
export VAULT_ADDR="https://vault_uri.hashicorp.io"
export VAULT_TOKEN="your-vault-root-or-admin-token"
```

#### Step 3: Install VSO (Optional - done automatically)
```bash
./deploy-demo.sh install-vso
```

#### Step 4: Configure Vault (Optional - done automatically)
```bash
./deploy-demo.sh configure-vault
```

#### Step 5: Deploy Demo Application
```bash
./deploy-demo.sh deploy
# OR for LoadBalancer + Ingress:
./deploy-demo.sh deploy-with-ingress
```

### **Accessing Your Application**

After deployment, the script automatically displays:

```
========================================
  VAULT SECRETS DEMO - ACCESS INFO
========================================

Application is ready and accessible!

MAIN APPLICATION URL:
   http://your-loadbalancer-hostname

API ENDPOINTS:
   Health Check: http://your-loadbalancer-hostname/api/health
   Secrets API:  http://your-loadbalancer-hostname/api/secrets
   Vault Status: http://your-loadbalancer-hostname/api/vault-status
```

**Important**: Use the LoadBalancer URL provided by the script, **NOT** the Kubernetes API endpoint!

## What You'll See

The web interface displays:

1. **Kubernetes Environment**: Pod name, namespace, node, service account
2. **Application Secrets**: Username, password (masked), API key from `secret/myapp`
3. **Database Configuration**: Host, port, username, password (masked) from `secret/database`
4. **Architecture Diagram**: Visual representation of the Vault → VSO → K8s flow
5. **Real-time Updates**: Automatically refreshes every 30 seconds

## **Available Commands**

The `deploy-demo.sh` script provides comprehensive automation:

```bash
# DEPLOYMENT COMMANDS
./deploy-demo.sh setup-all           # Complete end-to-end setup (recommended)
./deploy-demo.sh deploy              # Deploy demo app only
./deploy-demo.sh deploy-with-ingress # Deploy with LoadBalancer + Ingress

# 🔧 COMPONENT COMMANDS  
./deploy-demo.sh install-vso         # Install Vault Secrets Operator only
./deploy-demo.sh configure-vault     # Configure Vault secrets & auth only

# 🔍 DIAGNOSTIC COMMANDS
./deploy-demo.sh check-vso           # Check VSO installation status
./deploy-demo.sh status              # Check deployment status
./deploy-demo.sh fix-image           # Fix Docker architecture issues

# 🧹 CLEANUP
./deploy-demo.sh cleanup             # Remove demo application
```

### **Monitoring & Debugging**

```bash
# View application logs
kubectl logs -f deployment/vault-secrets-demo -n demo-app

# Check secret synchronization
kubectl get secrets -n demo-app
kubectl describe vaultauth vault-auth -n demo-app
kubectl describe vaultstaticsecret myapp-secret -n demo-app

# Check VSO status
kubectl get pods -n vault-secrets-operator-system
kubectl logs -f deployment/vault-secrets-operator -n vault-secrets-operator-system

# View LoadBalancer status
kubectl get service vault-secrets-demo-lb -n demo-app
kubectl describe service vault-secrets-demo-lb -n demo-app
```

## **Infrastructure & Automation Features**

### **Complete Infrastructure Automation**
- **EKS Cluster**: Terraform deploys production-ready EKS with proper VPC, subnets, and security groups
- **ECR Repository**: Automatic container registry with lifecycle policies for image management
- **Load Balancer**: AWS Network Load Balancer with proper subnet tagging for external access
- **Multi-Architecture Support**: Handles ARM64 (Apple Silicon) → AMD64 (EKS) architecture differences

### **Vault Integration Automation**
- **KV v2 Engine**: Automatically enabled at `secret/` path
- **Demo Secrets**: Auto-created `secret/myapp` and `secret/database` with sample data
- **Policy Management**: Automatic creation of `app-secrets` policy with read permissions
- **Kubernetes Auth**: Complete setup of K8s JWT authentication with proper audience claims
- **Service Accounts**: RBAC and token management for VSO and demo application

### **VSO Integration**
- **Auto-Installation**: Helm-based VSO deployment with proper configuration
- **Connection Management**: VaultConnection resources automatically configured
- **Secret Synchronization**: VaultStaticSecret resources for real-time sync
- **Authentication**: VaultAuth resources with Kubernetes JWT tokens

### **Application Features**
- **Real-time Secret Display**: Live web interface showing synchronized secrets
- **Health Monitoring**: Multiple endpoints for health checks and status monitoring
- **Security Context**: Non-root containers with proper resource limits
- **Auto-scaling Ready**: Deployment supports horizontal pod autoscaling

## Customization

### Adding New Secrets

1. **Add to Vault**:
   ```bash
   vault kv put secret/newsecret key1=value1 key2=value2
   ```

2. **Create VaultStaticSecret**:
   ```yaml
   apiVersion: secrets.hashicorp.com/v1beta1
   kind: VaultStaticSecret
   metadata:
     name: newsecret
     namespace: demo-app
   spec:
     type: kv-v2
     mount: secret
     path: newsecret
     destination:
       name: newsecret-credentials
       create: true
     vaultAuthRef: vault-auth
   ```

3. **Update Deployment**: Add environment variables in `deployment.yaml`

### Changing Vault Address

Update the address in `app/k8s/vault-connection.yaml` or set `VAULT_ADDR` environment variable when running the deployment script.

## Security Features

- **Non-root Container**: Runs as user 1000
- **Minimal Privileges**: Only necessary Kubernetes permissions
- **Secret Masking**: Passwords are masked in the UI
- **Health Checks**: Liveness and readiness probes
- **Resource Limits**: CPU and memory constraints
- **JWT Authentication**: Secure Vault authentication using Kubernetes service accounts

## **Troubleshooting Guide**

### **Common Issues & Solutions**

#### **"Forbidden: User system:anonymous cannot get path" Error**
This means you're accessing the Kubernetes API instead of your application.

**Solution**:
```bash
# Get the correct LoadBalancer URL (NOT the Kubernetes API URL)
kubectl get service vault-secrets-demo-lb -n demo-app
# Use the EXTERNAL-IP hostname, e.g., http://a1234567890abcdef-123456789.us-east-2.elb.amazonaws.com
```

#### **Docker Image Architecture Issues**
If you see `no match for platform in manifest`, you're building on ARM64 (Apple Silicon) for AMD64 (EKS).

**Solution**:
```bash
./deploy-demo.sh fix-image  # Rebuilds with correct architecture
```

#### **VSO Not Found / CRDs Missing**
**Solution**:
```bash
./deploy-demo.sh install-vso  # Installs VSO automatically
```

#### **Secrets Not Appearing in App**
1. **Check VSO Status**:
   ```bash
   kubectl describe vaultauth vault-auth -n demo-app
   kubectl describe vaultstaticsecret myapp-secret -n demo-app
   ```

2. **Check VSO Logs**:
   ```bash
   kubectl logs -f deployment/vault-secrets-operator -n vault-secrets-operator-system
   ```

3. **Verify Vault Connectivity**:
   ```bash
   # Test Vault connection
   curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/sys/health
   
   # Check if secrets exist in Vault
   vault kv get secret/myapp
   vault kv get secret/database
   ```

#### **LoadBalancer Not Getting External Hostname**
**Check**:
```bash
kubectl describe service vault-secrets-demo-lb -n demo-app
```

**Common causes**:
- AWS Load Balancer Controller not installed
- Incorrect subnet tags (fixed by Terraform)
- Security group issues

**Solution**:
```bash
# Use port-forward as temporary workaround
kubectl port-forward service/vault-secrets-demo-service 8080:80 -n demo-app
# Visit http://localhost:8080
```

#### **Application Pod Not Starting**
```bash
# Check pod status
kubectl get pods -n demo-app -l app=vault-secrets-demo
kubectl describe pod -l app=vault-secrets-demo -n demo-app

# Check logs
kubectl logs -f deployment/vault-secrets-demo -n demo-app
```

### **Advanced Debugging**

#### Check Complete System Status
```bash
# Run comprehensive status check
./deploy-demo.sh status

# Check all VSO resources
kubectl get vaultconnections,vaultauths,vaultstaticsecrets -n demo-app

# Check Kubernetes events
kubectl get events -n demo-app --sort-by='.lastTimestamp'
```

#### Reset and Redeploy
```bash
# Clean up everything
./deploy-demo.sh cleanup
terraform destroy  # If you want to rebuild infrastructure

# Fresh deployment
terraform apply
./deploy-demo.sh setup-all
```

## Monitoring

The application provides several endpoints for monitoring:

- `/api/health` - Health check endpoint
- `/api/secrets` - JSON API for secret status
- `/api/vault-status` - Vault synchronization status

## **Cleanup**

### **Remove Demo Application Only**
```bash
./deploy-demo.sh cleanup
```

### **Destroy Complete Infrastructure**
```bash
# Remove demo application first
./deploy-demo.sh cleanup

# Destroy EKS cluster and all AWS resources
cd terraform
terraform destroy
```

**Note**: The cleanup command only removes the demo application. Use `terraform destroy` to remove the entire EKS cluster and associated AWS resources.

---

## **What Makes This Demo Special**

This demo showcases a **production-ready, fully automated** pattern for managing secrets in Kubernetes using HashiCorp Vault and the Vault Secrets Operator. Key differentiators:

✅ **Complete Automation** - From infrastructure to application deployment  
✅ **Real Production Patterns** - Proper RBAC, security contexts, and monitoring  
✅ **Architecture Flexibility** - Handles ARM64 → AMD64 builds automatically  
✅ **Comprehensive Error Handling** - Clear error messages and automatic fixes  
✅ **Visual Validation** - Beautiful web interface to verify the integration works  
✅ **Enterprise Ready** - ECR integration, load balancing, ingress support  

Perfect for:
- **Learning** HashiCorp Vault + Kubernetes integration
- **Demonstrating** VSO capabilities to stakeholders  
- **Prototyping** production secret management patterns
- **Training** teams on modern secret management practices

## **Contributing**

Found an issue or want to improve the demo? Contributions are welcome! This project demonstrates best practices for:
- Infrastructure as Code with Terraform
- Kubernetes secret management with Vault
- Automated deployment pipelines
- Production-ready containerization

