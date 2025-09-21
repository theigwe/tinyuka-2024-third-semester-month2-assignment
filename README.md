# Tinyuka EKS Infrastructure

## Cluster Overview
> **Name**: tinyuka-cluster  
> **Region**: eu-west-1  
> **Host Location**: [tinyuka-mart.run.place](https://tinyuka-mart.run.place)

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
- **Version**: Kubernetes 1.33 (latest)
- **Node Group**: 2 t3.small instances for cost optimization
- **Authentication**: API_AND_CONFIG_MAP mode with EKS access entries
- **OIDC Provider**: Enables IAM Roles for Service Accounts (IRSA)
- **AWS Load Balancer Controller**: Helm-deployed for ALB/NLB support

### **AWS Managed Services**
- **RDS PostgreSQL**: 15.8 (db.t3.micro, 20GB gp3 storage)
- **RDS MySQL**: 8.0 (db.t3.micro, 20GB gp3 storage)
- **ElastiCache Redis**: 7 (cache.t3.micro, single node)
- **DynamoDB**: Pay-per-request table with string hash key "id"

### **In-Cluster Services** (app namespace)
- **PostgreSQL**: Available via database manifest (deployed separately)
- **MySQL**: Available via database manifest (deployed separately)
- **Redis**: Available via database manifest (deployed separately)
- **DynamoDB Local**: Available via database manifest (deployed separately)
- **RabbitMQ**: Available via database manifest (deployed separately)

**Note**: In-cluster services are deployed via `terraform/infra/database/manifest.yaml` as StatefulSets with persistent storage.

### **Access Control & Security**
- **IAM Roles**:
  - **Developer Role**: `AmazonEKSViewPolicy` (read-only access via EKS access entries)
  - **Admin Role**: `AmazonEKSClusterAdminPolicy` (full admin access via EKS access entries)
  - **DynamoDB Service Account Role**: `tinyuka-cluster-dynamodb-service-account-role` (CRUD access to DynamoDB)
- **EKS Access Entries**: Modern IAM-to-Kubernetes access mapping
- **Authentication Mode**: API_AND_CONFIG_MAP for backward compatibility
- **Service Accounts**: IRSA-enabled for AWS service integration

### **Configuration Management**
- **database ConfigMap**: Non-sensitive connection details (32+ configuration values including hosts, ports, usernames, table names, DynamoDB role ARN)
- **database Secret**: Sensitive data (passwords, connection URLs, endpoints)
- **Random Password Generation**: Secure 16-character passwords (no special characters for compatibility)
- **Comprehensive DynamoDB Support**: Both AWS and in-cluster endpoints configured
- **DynamoDB IRSA**: Service account role ARN available in ConfigMap for seamless pod integration

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
aws eks update-kubeconfig --region eu-west-1 --name tinyuka-cluster

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
      "Resource": "arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-cluster-developer-role"
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
  --name tinyuka-cluster \
  --profile eks-developer \
  --role-arn arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-cluster-developer-role
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
  --exec-arg=tinyuka-cluster \
  --exec-arg=--role \
  --exec-arg=arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-cluster-developer-role

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

### **DynamoDB Access with IRSA (IAM Roles for Service Accounts)**

The infrastructure provides secure DynamoDB access using IRSA. The DynamoDB service account role ARN is available in the ConfigMap for easy reference:

```yaml
# First, get the role ARN from the ConfigMap
# kubectl get configmap database -n app -o jsonpath='{.data.aws_dynamodb_service_account_role_arn}'

apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-dynamodb-service-account
  namespace: app
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR-ACCOUNT-ID:role/tinyuka-cluster-dynamodb-service-account-role"
    # Note: Replace with actual ARN from ConfigMap above
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-dynamodb-app
  namespace: app
spec:
  selector:
    matchLabels:
      app: my-dynamodb-app
  template:
    metadata:
      labels:
        app: my-dynamodb-app
    spec:
      serviceAccountName: my-dynamodb-service-account
      containers:
      - name: app
        image: my-app:latest
        env:
        - name: DYNAMODB_TABLE_NAME
          valueFrom:
            configMapKeyRef:
              name: database
              key: aws_dynamodb_table_name
        - name: AWS_REGION
          valueFrom:
            configMapKeyRef:
              name: database
              key: aws_dynamodb_region
        # AWS SDK will automatically use IRSA credentials
```

**Permissions Granted:**
- `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:Query`, `dynamodb:Scan`
- `dynamodb:UpdateItem`, `dynamodb:DeleteItem`, `dynamodb:BatchGetItem`, `dynamodb:BatchWriteItem`
- `dynamodb:ConditionCheckItem`, `dynamodb:DescribeTable`, `dynamodb:DescribeTimeToLive`

### **Using Database Credentials in Applications**

#### **Environment Variables from Secret**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app
spec:
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: my-app:latest
        env:
        # AWS Managed Services
        - name: AWS_POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: aws_postgres_url
        - name: AWS_MYSQL_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: aws_mysql_url
        - name: AWS_REDIS_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: aws_redis_url
        - name: AWS_DYNAMODB_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: database
              key: aws_dynamodb_endpoint
        - name: DYNAMODB_TABLE_NAME
          valueFrom:
            configMapKeyRef:
              name: database
              key: aws_dynamodb_table_name
        - name: AWS_REGION
          valueFrom:
            configMapKeyRef:
              name: database
              key: aws_dynamodb_region

        # In-Cluster Services
        - name: CLUSTER_POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: in_cluster_postgres_url
        - name: CLUSTER_MYSQL_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: in_cluster_mysql_url
        - name: CLUSTER_RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: in_cluster_rabbitmq_url
        - name: CLUSTER_DYNAMODB_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: database
              key: in_cluster_dynamodb_endpoint
        - name: CLUSTER_REDIS_URL
          valueFrom:
            secretKeyRef:
              name: database
              key: in_cluster_redis_url
```

#### **Using ConfigMap for Non-Sensitive Data**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app
spec:
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: my-app:latest
        envFrom:
        - configMapRef:
            name: database  # Contains hosts, ports, usernames, table names
        - secretRef:
            name: database  # Contains passwords and URLs
```

### **Accessing Credentials**

#### **View Available Configurations**
```bash
# View non-sensitive configuration
kubectl get configmap database -n app -o yaml

# List available credential keys
kubectl get secret database -n app -o jsonpath='{.data}' | jq 'keys'

# Retrieve specific connection URL (decode base64)
kubectl get secret database -n app -o jsonpath='{.data.aws_postgres_url}' | base64 -d
```

## 🔍 **Monitoring and Troubleshooting**

### **Check Infrastructure Status**
```bash
# Verify cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify in-cluster services (deployed via database manifest)
kubectl get statefulsets -n app
kubectl get services -n app
```

### **Access Service Endpoints**
```bash
# AWS Service Endpoints (from Terraform outputs)
terraform output rds_postgres_endpoint
terraform output elasticache_redis_endpoint

# In-cluster Service DNS (when database manifest is deployed)
# PostgreSQL: postgres.app.svc.cluster.local:5432
# MySQL: mysql.app.svc.cluster.local:3306
# Redis: redis.app.svc.cluster.local:6379
# DynamoDB Local: dynamodb.app.svc.cluster.local:8000
# RabbitMQ: rabbitmq.app.svc.cluster.local:5672 (AMQP)
# RabbitMQ Management: rabbitmq.app.svc.cluster.local:15672 (HTTP)
```

## 📊 **Cost Optimization**

This infrastructure is designed for cost efficiency:

- **Instance Types**: t3.small for EKS nodes, t3.micro for databases
- **Storage**: GP3 for an optimal price/performance ratio
- **DynamoDB**: Pay-per-request billing (no fixed costs)
- **No NAT Gateway**: Public subnets only to reduce costs
- **Minimal Node Count**: 2 nodes for basic high availability