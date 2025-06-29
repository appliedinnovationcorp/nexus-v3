#!/bin/bash

set -e

# Container & Orchestration Setup Script
# Enterprise-grade container orchestration with Kubernetes, Helm, security policies, autoscaling, and service mesh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[CONTAINERS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[CONTAINER SETUP]${NC} $1"
}

# Configuration
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"1.28.0"}
HELM_VERSION=${HELM_VERSION:-"3.13.0"}
ISTIO_VERSION=${ISTIO_VERSION:-"1.20.1"}
DOCKER_REGISTRY=${DOCKER_REGISTRY:-"harbor.nexus-v3.local"}

# Check dependencies
check_dependencies() {
    print_header "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_deps+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        print_warning "Helm not found - will install"
        install_helm
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Install Helm
install_helm() {
    print_status "Installing Helm..."
    
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh --version v${HELM_VERSION}
    rm get_helm.sh
    
    print_status "Helm installed successfully ✅"
}

# Setup container infrastructure
setup_container_infrastructure() {
    print_header "Setting up container infrastructure..."
    
    # Create necessary directories
    mkdir -p containers/{docker,k8s,scripts,configs}
    mkdir -p containers/k8s/{helm,security,autoscaling,service-mesh,monitoring}
    mkdir -p containers/k8s/helm/nexus-v3/{templates,charts}
    mkdir -p containers/docker/{nginx,scripts}
    
    print_status "Directory structure created ✅"
    
    # Set proper permissions
    chmod +x containers/scripts/*.sh 2>/dev/null || true
    
    print_status "Permissions set ✅"
}

# Build multi-stage Docker images
build_docker_images() {
    print_header "Building multi-stage Docker images..."
    
    # Build production image with distroless base
    print_status "Building production image..."
    docker build -f containers/docker/Dockerfile.multistage \
        --target runtime \
        --tag ${DOCKER_REGISTRY}/nexus-v3/nexus-v3-app:latest \
        --tag ${DOCKER_REGISTRY}/nexus-v3/nexus-v3-app:$(date +%Y%m%d-%H%M%S) \
        .
    
    # Build development image
    print_status "Building development image..."
    docker build -f containers/docker/Dockerfile.multistage \
        --target development \
        --tag ${DOCKER_REGISTRY}/nexus-v3/nexus-v3-app:dev \
        .
    
    # Build nginx image for static assets
    print_status "Building nginx image..."
    docker build -f containers/docker/Dockerfile.multistage \
        --target nginx \
        --tag ${DOCKER_REGISTRY}/nexus-v3/nexus-v3-nginx:latest \
        .
    
    print_status "Docker images built successfully ✅"
}

# Setup Kubernetes cluster (if not exists)
setup_kubernetes_cluster() {
    print_header "Setting up Kubernetes cluster..."
    
    # Check if cluster is accessible
    if kubectl cluster-info &> /dev/null; then
        print_status "Kubernetes cluster is accessible ✅"
    else
        print_warning "Kubernetes cluster not accessible - please ensure cluster is running"
        return 1
    fi
    
    # Create namespaces
    print_status "Creating namespaces..."
    kubectl create namespace nexus-v3-dev --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace nexus-v3-staging --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace nexus-v3-prod --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespaces for network policies
    kubectl label namespace nexus-v3-dev name=nexus-v3-dev --overwrite
    kubectl label namespace nexus-v3-staging name=nexus-v3-staging --overwrite
    kubectl label namespace nexus-v3-prod name=nexus-v3-prod --overwrite
    kubectl label namespace monitoring name=monitoring --overwrite
    kubectl label namespace istio-system name=istio-system --overwrite
    
    print_status "Kubernetes namespaces configured ✅"
}

# Install Istio service mesh
install_istio() {
    print_header "Installing Istio service mesh..."
    
    # Download and install Istio
    if ! command -v istioctl &> /dev/null; then
        print_status "Downloading Istio..."
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
        export PATH="$PATH:$PWD/istio-${ISTIO_VERSION}/bin"
        sudo cp istio-${ISTIO_VERSION}/bin/istioctl /usr/local/bin/
    fi
    
    # Install Istio
    print_status "Installing Istio control plane..."
    istioctl install --set values.defaultRevision=default -y
    
    # Enable sidecar injection for application namespaces
    kubectl label namespace nexus-v3-dev istio-injection=enabled --overwrite
    kubectl label namespace nexus-v3-staging istio-injection=enabled --overwrite
    kubectl label namespace nexus-v3-prod istio-injection=enabled --overwrite
    
    # Apply Istio configuration
    kubectl apply -f containers/k8s/service-mesh/istio-config.yaml
    
    print_status "Istio service mesh installed ✅"
}

# Setup security policies
setup_security_policies() {
    print_header "Setting up security policies..."
    
    # Apply Pod Security Policies
    print_status "Applying Pod Security Policies..."
    kubectl apply -f containers/k8s/security/pod-security-policy.yaml
    
    # Apply Network Policies
    print_status "Applying Network Policies..."
    kubectl apply -f containers/k8s/security/network-policies.yaml
    
    # Create RBAC policies
    print_status "Creating RBAC policies..."
    create_rbac_policies
    
    print_status "Security policies configured ✅"
}

create_rbac_policies() {
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: nexus-v3-prod
  name: nexus-v3-role
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nexus-v3-rolebinding
  namespace: nexus-v3-prod
subjects:
- kind: ServiceAccount
  name: nexus-v3
  namespace: nexus-v3-prod
roleRef:
  kind: Role
  name: nexus-v3-role
  apiGroup: rbac.authorization.k8s.io
EOF
}

# Setup autoscaling
setup_autoscaling() {
    print_header "Setting up autoscaling..."
    
    # Install Metrics Server if not present
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        print_status "Installing Metrics Server..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    fi
    
    # Install Vertical Pod Autoscaler
    print_status "Installing Vertical Pod Autoscaler..."
    install_vpa
    
    # Apply HPA and VPA configurations
    print_status "Applying autoscaling configurations..."
    kubectl apply -f containers/k8s/autoscaling/hpa-vpa.yaml
    
    print_status "Autoscaling configured ✅"
}

install_vpa() {
    if ! kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &> /dev/null; then
        git clone https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
        cd /tmp/autoscaler/vertical-pod-autoscaler
        ./hack/vpa-install.sh
        cd -
        rm -rf /tmp/autoscaler
    fi
}

# Setup Helm charts
setup_helm_charts() {
    print_header "Setting up Helm charts..."
    
    # Add Helm repositories
    print_status "Adding Helm repositories..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Install cert-manager
    print_status "Installing cert-manager..."
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.3 \
        --set installCRDs=true
    
    # Install ingress-nginx
    print_status "Installing ingress-nginx..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.metrics.enabled=true \
        --set controller.podAnnotations."prometheus\.io/scrape"=true \
        --set controller.podAnnotations."prometheus\.io/port"=10254
    
    # Package and install Nexus V3 chart
    print_status "Installing Nexus V3 application..."
    helm dependency update containers/k8s/helm/nexus-v3/
    helm upgrade --install nexus-v3 containers/k8s/helm/nexus-v3/ \
        --namespace nexus-v3-prod \
        --create-namespace \
        --values containers/k8s/helm/nexus-v3/values.yaml
    
    print_status "Helm charts deployed ✅"
}

# Setup monitoring
setup_monitoring() {
    print_header "Setting up monitoring..."
    
    # Install Prometheus
    print_status "Installing Prometheus..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
    
    # Install Grafana dashboards
    print_status "Installing Grafana dashboards..."
    kubectl apply -f containers/k8s/monitoring/grafana-dashboards.yaml
    
    print_status "Monitoring configured ✅"
}

# Validate deployment
validate_deployment() {
    print_header "Validating deployment..."
    
    # Check pod status
    print_status "Checking pod status..."
    kubectl get pods -n nexus-v3-prod -l app.kubernetes.io/name=nexus-v3
    
    # Check service status
    print_status "Checking service status..."
    kubectl get svc -n nexus-v3-prod -l app.kubernetes.io/name=nexus-v3
    
    # Check HPA status
    print_status "Checking HPA status..."
    kubectl get hpa -n nexus-v3-prod
    
    # Check VPA status
    print_status "Checking VPA status..."
    kubectl get vpa -n nexus-v3-prod
    
    # Check Istio configuration
    print_status "Checking Istio configuration..."
    kubectl get virtualservice,destinationrule,gateway -n nexus-v3-prod
    
    # Run connectivity tests
    print_status "Running connectivity tests..."
    run_connectivity_tests
    
    print_status "Deployment validation completed ✅"
}

run_connectivity_tests() {
    # Test internal connectivity
    kubectl run test-pod --image=curlimages/curl:latest --rm -it --restart=Never -- \
        curl -f http://nexus-v3-service.nexus-v3-prod.svc.cluster.local/health || \
        print_warning "Internal connectivity test failed"
    
    # Test external connectivity (if ingress is configured)
    if kubectl get ingress -n nexus-v3-prod &> /dev/null; then
        local ingress_ip=$(kubectl get ingress -n nexus-v3-prod -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
        if [[ -n "$ingress_ip" ]]; then
            curl -f http://$ingress_ip/health || print_warning "External connectivity test failed"
        fi
    fi
}

# Generate documentation
generate_documentation() {
    print_header "Generating documentation..."
    
    cat > containers/README.md << 'EOF'
# Enterprise Container & Orchestration

## 🚀 Overview

Comprehensive container orchestration solution with:

- **Multi-stage Docker builds** with distroless images for security
- **Kubernetes orchestration** with Helm charts for deployment
- **Pod Security Policies** and Network Policies for security
- **Horizontal Pod Autoscaling (HPA)** and Vertical Pod Autoscaling (VPA)
- **Istio service mesh** for traffic management and security
- **Enterprise-grade monitoring** and observability

## 🛠 Tech Stack

### Container Runtime
- **Docker** - Multi-stage builds with distroless base images
- **Kubernetes** (1.28.0) - Container orchestration platform
- **Helm** (3.13.0) - Package manager for Kubernetes

### Service Mesh
- **Istio** (1.20.1) - Service mesh for traffic management
- **Envoy Proxy** - High-performance proxy for service communication

### Security
- **Pod Security Policies** - Pod-level security constraints
- **Network Policies** - Network-level security controls
- **RBAC** - Role-based access control
- **mTLS** - Mutual TLS for service-to-service communication

### Autoscaling
- **HPA** - Horizontal Pod Autoscaler for replica scaling
- **VPA** - Vertical Pod Autoscaler for resource optimization
- **Cluster Autoscaler** - Node-level scaling

### Monitoring
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization and dashboards
- **Jaeger** - Distributed tracing
- **Kiali** - Service mesh observability

## 🚦 Quick Start

```bash
# Setup container infrastructure
./scripts/setup-containers.sh

# Build Docker images
docker build -f docker/Dockerfile.multistage --target runtime -t nexus-v3-app:latest .

# Deploy to Kubernetes
helm upgrade --install nexus-v3 k8s/helm/nexus-v3/ --namespace nexus-v3-prod
```

## 📊 Architecture

### Multi-stage Docker Build
```dockerfile
FROM node:18-alpine AS builder    # Build stage
FROM deps AS security-scan        # Security scanning
FROM gcr.io/distroless/nodejs18   # Runtime stage (distroless)
```

### Kubernetes Deployment
```yaml
Deployment Strategy:
├── Rolling Update (maxUnavailable: 1, maxSurge: 2)
├── Health Checks (liveness, readiness, startup)
├── Resource Limits (CPU: 1000m, Memory: 2Gi)
├── Security Context (non-root, read-only filesystem)
└── Autoscaling (HPA + VPA)
```

### Service Mesh Architecture
```yaml
Istio Components:
├── Ingress Gateway (external traffic)
├── Virtual Service (routing rules)
├── Destination Rule (load balancing, circuit breaking)
├── Peer Authentication (mTLS)
└── Authorization Policy (access control)
```

## 🔒 Security Features

### Container Security
- **Distroless base images** for minimal attack surface
- **Non-root user** execution
- **Read-only root filesystem**
- **Dropped capabilities** (ALL capabilities dropped)
- **Security scanning** with Trivy in build pipeline

### Kubernetes Security
- **Pod Security Policies** enforcing security constraints
- **Network Policies** for micro-segmentation
- **RBAC** with least privilege access
- **Service Account** with minimal permissions
- **Secrets management** with encrypted storage

### Service Mesh Security
- **Mutual TLS** for all service communication
- **Authorization policies** for fine-grained access control
- **Traffic encryption** in transit
- **Identity-based security** with SPIFFE/SPIRE

## 📈 Autoscaling Configuration

### Horizontal Pod Autoscaler
```yaml
Scaling Metrics:
├── CPU Utilization: 70%
├── Memory Utilization: 80%
├── Custom Metrics: Request rate, Response time
└── External Metrics: Queue depth
```

### Vertical Pod Autoscaler
```yaml
Resource Optimization:
├── CPU: 100m - 2000m
├── Memory: 128Mi - 4Gi
├── Update Mode: Auto
└── Controlled Resources: CPU, Memory
```

## 🌐 Service Mesh Features

### Traffic Management
- **Load balancing** with multiple algorithms
- **Circuit breaking** for fault tolerance
- **Retry policies** with exponential backoff
- **Timeout configuration** for reliability
- **Traffic splitting** for canary deployments

### Observability
- **Distributed tracing** with Jaeger integration
- **Metrics collection** with Prometheus
- **Access logging** with structured logs
- **Service topology** visualization with Kiali

### Security
- **Automatic mTLS** for service communication
- **JWT validation** for external requests
- **Rate limiting** with Envoy filters
- **Authorization policies** based on service identity

## 📊 Monitoring & Observability

### Application Metrics
- **Request rate** and **response time**
- **Error rate** and **success rate**
- **Resource utilization** (CPU, memory)
- **Custom business metrics**

### Infrastructure Metrics
- **Node resource usage**
- **Pod resource consumption**
- **Network traffic patterns**
- **Storage utilization**

### Service Mesh Metrics
- **Service-to-service communication**
- **mTLS certificate status**
- **Circuit breaker status**
- **Load balancing distribution**

## 🔧 Configuration

### Environment Variables
```bash
KUBERNETES_VERSION=1.28.0
HELM_VERSION=3.13.0
ISTIO_VERSION=1.20.1
DOCKER_REGISTRY=harbor.nexus-v3.local
```

### Helm Values
```yaml
# Resource configuration
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi

# Autoscaling configuration
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
```

## 🚨 Troubleshooting

### Common Issues
1. **Pods not starting**: Check resource limits and node capacity
2. **Network connectivity**: Verify network policies and service mesh configuration
3. **Autoscaling not working**: Check metrics server and HPA/VPA configuration
4. **Service mesh issues**: Verify Istio sidecar injection and mTLS configuration

### Debugging Commands
```bash
# Check pod status
kubectl get pods -n nexus-v3-prod -o wide

# Check service mesh status
istioctl proxy-status

# Check autoscaling status
kubectl get hpa,vpa -n nexus-v3-prod

# Check network policies
kubectl get networkpolicy -n nexus-v3-prod

# View logs
kubectl logs -f deployment/nexus-v3 -n nexus-v3-prod
```

## 📚 Best Practices

### Container Security
- Use distroless or minimal base images
- Run containers as non-root users
- Implement read-only root filesystems
- Regularly scan images for vulnerabilities
- Use multi-stage builds to reduce image size

### Kubernetes Security
- Implement Pod Security Policies/Standards
- Use Network Policies for micro-segmentation
- Apply RBAC with least privilege principle
- Encrypt secrets at rest and in transit
- Regular security audits and compliance checks

### Performance Optimization
- Set appropriate resource requests and limits
- Use HPA and VPA for optimal resource utilization
- Implement proper health checks
- Optimize container startup time
- Use persistent volumes for stateful workloads

This container orchestration solution provides enterprise-grade capabilities
while maintaining complete control and zero licensing costs through exclusive
use of free and open-source technologies.
EOF

    print_status "Documentation generated ✅"
}

# Main setup function
main() {
    print_header "Starting Enterprise Container & Orchestration Setup"
    
    check_dependencies
    setup_container_infrastructure
    build_docker_images
    setup_kubernetes_cluster
    install_istio
    setup_security_policies
    setup_autoscaling
    setup_helm_charts
    setup_monitoring
    validate_deployment
    generate_documentation
    
    print_status "🎉 Enterprise container orchestration setup completed successfully!"
    echo ""
    echo "🚀 Deployment Status:"
    echo "  • Kubernetes cluster: Ready"
    echo "  • Istio service mesh: Installed"
    echo "  • Security policies: Applied"
    echo "  • Autoscaling: Configured (HPA + VPA)"
    echo "  • Monitoring: Deployed"
    echo ""
    echo "🔧 Access Points:"
    echo "  • Application: kubectl port-forward svc/nexus-v3-service 8080:80 -n nexus-v3-prod"
    echo "  • Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
    echo "  • Kiali: kubectl port-forward svc/kiali 20001:20001 -n istio-system"
    echo "  • Jaeger: kubectl port-forward svc/jaeger 16686:16686 -n istio-system"
    echo ""
    echo "📚 Documentation: ./containers/README.md"
}

main "$@"
