# Tinyuka EKS Infrastructure

A comprehensive, production-ready AWS EKS infrastructure with both AWS managed services and in-cluster alternatives, built with Terraform and automated via GitHub Actions.

## 🏗️ **Cloud Architecture Overview**

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.0.0.0/16)                │
│                                                             │
│  ┌─────────────────┐              ┌─────────────────┐       │
│  │   Public Subnet │              │   Public Subnet │       │
│  │  (10.0.1.0/24)  │              │  (10.0.2.0/24)  │       │
│  │       AZ-a      │              │       AZ-b      │       │
│  │                 │              │                 │       │
│  │  ┌─────────────┐│              │┌─────────────┐  │       │
│  │  │ EKS Worker  ││              ││ EKS Worker  │  │       │
│  │  │ Node (t3.s) ││              ││ Node (t3.s) │  │       │
│  │  └─────────────┘│              │└─────────────┘  │       │
│  └─────────────────┘              └─────────────────┘       │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                EKS Control Plane                        ││
│  │              (Managed by AWS)                           ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   RDS PostgreSQL│  │   RDS MySQL     │  │  ElastiCache │ │
│  │   (db.t3.micro) │  │  (db.t3.micro)  │  │    Redis     │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   DynamoDB Table                        ││
│  │                 (Pay-per-request)                       ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    In-Cluster Services                      │
│                   (storage namespace)                       │
│                                                             │
│  PostgreSQL StatefulSet  │  MySQL StatefulSet               │
│  Redis StatefulSet       │  DynamoDB Local StatefulSet      │
│  RabbitMQ StatefulSet    │  (All with persistent storage)   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                Load Balancing & Ingress                     │
│                                                             │
│  AWS Load Balancer Controller (ALB/NLB support)             │
│  │                                                          │
│  └─► Application Load Balancers                             │
│  └─► Network Load Balancers                                 │
└─────────────────────────────────────────────────────────────┘
```

## 🏗️ **Infrastructure Components**

### **Networking & Security**
- **VPC**: 10.0.0.0/16 with 2 public subnets across availability zones
- **Internet Gateway**: Direct internet access with proper routing
- **Security Groups**: Restrictive access controls (databases only accessible from EKS nodes)
- **Network ACLs**: Default AWS network ACLs for additional security

### **EKS Cluster**
- **Version**: Kubernetes 1.28 (latest stable)
- **Node Group**: 2 t3.small instances for cost optimization
- **OIDC Provider**: Enables IAM Roles for Service Accounts (IRSA)
- **AWS Load Balancer Controller**: Helm-deployed for ALB/NLB support

### **AWS Managed Services**
- **RDS PostgreSQL**: 15.4 (db.t3.micro, 20GB gp3 storage)
- **RDS MySQL**: 8.0 (db.t3.micro, 20GB gp3 storage)
- **ElastiCache Redis**: 7 (cache.t3.micro, single node)
- **DynamoDB**: Pay-per-request table with on-demand billing

### **In-Cluster Services** (storage namespace)
- **PostgreSQL**: StatefulSet with 10Gi persistent storage
- **MySQL**: StatefulSet with 10Gi persistent storage
- **Redis**: StatefulSet with 5Gi persistent storage
- **DynamoDB Local**: StatefulSet with 5Gi persistent storage
- **RabbitMQ**: StatefulSet with management interface (5Gi storage)

### **Access Control & Security**
- **IAM Roles**:
  - **Developer Role**: `AmazonEKSViewerPolicy` (read-only access)
  - **Admin Role**: `AmazonEKSClusterAdminPolicy` (full admin access)
- **aws-auth ConfigMap**: Maps IAM roles to Kubernetes groups
- **RBAC**: Custom ClusterRole for developer read-only access
- **Service Accounts**: IRSA-enabled for AWS service integration

### **Configuration Management**
- **storage-configs ConfigMap**: Non-sensitive connection details (hosts, ports, usernames)
- **storage-credentials Secret**: Sensitive data (passwords, connection URLs)
- **Random Password Generation**: Secure 16-character passwords for all services

## 🚀 **Deployment Instructions**

### **Prerequisites**
1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.0
3. **kubectl** for Kubernetes management
4. **Git** for repository management

### **Step 1: Deploy Backend Infrastructure**
```bash
# Navigate to backend directory
cd terraform/backend

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy S3 backend
terraform apply
```

### **Step 2: Deploy Main Infrastructure**
```bash
# Navigate to infrastructure directory
cd ../infra

# Initialize with backend configuration
terraform init \
  -backend-config="bucket=tinyuka-terraform-state" \
  -backend-config="key=eks-infrastructure/terraform.tfstate" \
  -backend-config="region=eu-west-1"

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### **Step 3: Configure kubectl Access**

#### **For Cluster Admin (Infrastructure Creator)**
```bash
# Configure kubectl for the cluster creator (admin access)
aws eks update-kubeconfig --region eu-west-1 --name tinyuka-tinyuka-eks-cluster

# Verify access
kubectl get nodes
kubectl get namespaces
```

## 👥 **Developer Access Setup**

### **Step 1: Create Access Keys for Developer IAM Role**

The infrastructure creates a developer IAM role with read-only access to the EKS cluster. To use this role:

#### **Option A: AssumeRole via AWS CLI**
```bash
# Configure AWS CLI to assume the developer role
aws configure set role_arn arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-eks-developer-role
aws configure set source_profile default

# Test role assumption
aws sts get-caller-identity
```

#### **Option B: Create IAM User with AssumeRole Policy**
```bash
# Create IAM user for developer
aws iam create-user --user-name eks-developer

# Create access keys
aws iam create-access-key --user-name eks-developer

# Attach policy to allow assuming the developer role
aws iam put-user-policy --user-name eks-developer --policy-name AssumeEKSDeveloperRole --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-eks-developer-role"
    }
  ]
}'
```

### **Step 2: Configure kubectl for Developer**

#### **Using AssumeRole Profile**
```bash
# Configure AWS CLI profile for developer
aws configure --profile eks-developer
# Enter the access keys created above

# Configure kubectl using the developer profile
aws eks update-kubeconfig \
  --region eu-west-1 \
  --name tinyuka-tinyuka-eks-cluster \
  --profile eks-developer \
  --role-arn arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-eks-developer-role
```

#### **Manual kubectl Configuration**
```bash
# Create kubeconfig entry for developer
kubectl config set-cluster tinyuka-cluster \
  --server=https://EKS-CLUSTER-ENDPOINT \
  --certificate-authority-data=CERTIFICATE-DATA

kubectl config set-credentials developer \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=aws \
  --exec-arg=eks \
  --exec-arg=get-token \
  --exec-arg=--cluster-name \
  --exec-arg=tinyuka-tinyuka-eks-cluster \
  --exec-arg=--role \
  --exec-arg=arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-eks-developer-role

kubectl config set-context developer-context \
  --cluster=tinyuka-cluster \
  --user=developer

kubectl config use-context developer-context
```

### **Step 3: Verify Developer Access**

#### **Developer Permissions (Read-Only)**
```bash
# These commands should work (read-only access)
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
kubectl describe deployment -n app

# These commands should fail (no write access)
kubectl create namespace test        # ❌ Should fail
kubectl delete pod -n app some-pod   # ❌ Should fail
kubectl apply -f deployment.yaml     # ❌ Should fail
```

## 📦 **Application Integration**

### **Using Database Credentials in Applications**

#### **Environment Variables from Secret**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app
spec:
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
        env:
        # AWS Managed Services
        - name: AWS_POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: storage-credentials
              key: aws_postgres_url
        - name: AWS_MYSQL_URL
          valueFrom:
            secretKeyRef:
              name: storage-credentials
              key: aws_mysql_url
        - name: AWS_REDIS_URL
          valueFrom:
            secretKeyRef:
              name: storage-credentials
              key: aws_redis_url

        # In-Cluster Services
        - name: CLUSTER_POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: storage-credentials
              key: in_cluster_postgres_url
        - name: CLUSTER_RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: storage-credentials
              key: in_cluster_rabbitmq_url
```

#### **Using ConfigMap for Non-Sensitive Data**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app
spec:
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
        envFrom:
        - configMapRef:
            name: storage-configs  # Contains hosts, ports, usernames
        - secretRef:
            name: storage-credentials  # Contains passwords and URLs
```

### **Accessing Credentials**

#### **View Available Configurations**
```bash
# View non-sensitive configuration
kubectl get configmap storage-configs -n app -o yaml

# List available credential keys
kubectl get secret storage-credentials -n app -o jsonpath='{.data}' | jq 'keys'

# Retrieve specific connection URL (decode base64)
kubectl get secret storage-credentials -n app -o jsonpath='{.data.aws_postgres_url}' | base64 -d
```

## 🔍 **Monitoring and Troubleshooting**

### **Check Infrastructure Status**
```bash
# Verify cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify in-cluster services
kubectl get statefulsets -n storage
kubectl get services -n storage
```

### **Access Service Endpoints**
```bash
# AWS Service Endpoints (from Terraform outputs)
terraform output rds_postgres_endpoint
terraform output elasticache_redis_endpoint

# In-cluster Service DNS
# PostgreSQL: postgres.storage.svc.cluster.local:5432
# MySQL: mysql.storage.svc.cluster.local:3306
# Redis: redis.storage.svc.cluster.local:6379
# DynamoDB Local: dynamodb.storage.svc.cluster.local:8000
# RabbitMQ: rabbitmq.storage.svc.cluster.local:5672 (AMQP)
# RabbitMQ Management: rabbitmq.storage.svc.cluster.local:15672 (HTTP)
```

## 📊 **Cost Optimization**

This infrastructure is designed for cost efficiency:

- **Instance Types**: t3.small for EKS nodes, t3.micro for databases
- **Storage**: GP3 for an optimal price/performance ratio
- **DynamoDB**: Pay-per-request billing (no fixed costs)
- **No NAT Gateway**: Public subnets only to reduce costs
- **Minimal Node Count**: 2 nodes for basic high availability