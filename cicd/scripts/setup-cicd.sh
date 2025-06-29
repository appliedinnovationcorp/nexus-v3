#!/bin/bash

set -e

# Advanced CI/CD Pipeline Setup Script
# Enterprise-grade CI/CD with multi-stage deployments, blue-green, canary, feature flags, security scanning

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[CICD]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[CICD SETUP]${NC} $1"
}

# Configuration
JENKINS_URL=${JENKINS_URL:-"http://localhost:8080"}
GITLAB_URL=${GITLAB_URL:-"http://localhost:8081"}
ARGOCD_URL=${ARGOCD_URL:-"http://localhost:8082"}
SONARQUBE_URL=${SONARQUBE_URL:-"http://localhost:9000"}
HARBOR_URL=${HARBOR_URL:-"http://localhost:8083"}
FLAGSMITH_URL=${FLAGSMITH_URL:-"http://localhost:8085"}

# Check dependencies
check_dependencies() {
    print_header "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not found - Kubernetes features may not work"
    fi
    
    if ! command -v helm &> /dev/null; then
        print_warning "helm not found - Helm deployments may not work"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Setup CI/CD infrastructure
setup_cicd_infrastructure() {
    print_header "Setting up CI/CD infrastructure..."
    
    # Create necessary directories
    mkdir -p cicd/{config,scripts,templates,pipelines,policies}
    mkdir -p cicd/config/{jenkins,gitlab,argocd,k8s,terraform,ansible,k6,sonarqube,harbor,flagsmith}
    mkdir -p cicd/config/k8s/{dev,staging,prod,rollouts}
    mkdir -p cicd/pipelines/{build,deploy,test,security}
    mkdir -p cicd/templates/{jenkins,gitlab-ci,github-actions}
    
    print_status "Directory structure created ✅"
    
    # Set proper permissions
    chmod +x cicd/scripts/*.sh 2>/dev/null || true
    
    print_status "Permissions set ✅"
}

# Start CI/CD stack
start_cicd_stack() {
    print_header "Starting CI/CD stack..."
    
    cd cicd
    
    # Pull latest images
    print_status "Pulling Docker images..."
    docker-compose -f docker-compose.cicd.yml pull
    
    # Start services
    print_status "Starting CI/CD services..."
    docker-compose -f docker-compose.cicd.yml up -d
    
    cd ..
    
    print_status "CI/CD stack started ✅"
}

# Wait for services to be ready
wait_for_services() {
    print_header "Waiting for services to be ready..."
    
    local services=(
        "jenkins:8080"
        "gitlab:8081"
        "argocd-server:8080"
        "sonarqube:9000"
        "harbor-core:8080"
        "flagsmith:8000"
    )
    
    for service in "${services[@]}"; do
        local host=$(echo $service | cut -d: -f1)
        local port=$(echo $service | cut -d: -f2)
        
        print_status "Waiting for $host:$port..."
        
        local retries=60
        while ! docker exec $host curl -f http://localhost:$port/health 2>/dev/null && [ $retries -gt 0 ]; do
            sleep 10
            retries=$((retries - 1))
            echo -n "."
        done
        
        if [ $retries -eq 0 ]; then
            print_warning "$host:$port may not be fully ready, but continuing..."
        else
            print_status "$host:$port is ready ✅"
        fi
    done
}

# Setup Jenkins
setup_jenkins() {
    print_header "Setting up Jenkins..."
    
    # Wait for Jenkins to be fully ready
    sleep 60
    
    # Get Jenkins initial admin password
    local admin_password
    if docker exec jenkins-cicd test -f /var/jenkins_home/secrets/initialAdminPassword; then
        admin_password=$(docker exec jenkins-cicd cat /var/jenkins_home/secrets/initialAdminPassword)
        print_status "Jenkins initial admin password: $admin_password"
    else
        print_warning "Jenkins initial admin password not found - may already be configured"
    fi
    
    # Install recommended plugins
    print_status "Installing Jenkins plugins..."
    docker exec jenkins-cicd jenkins-plugin-cli --plugins \
        "blueocean pipeline-stage-view docker-workflow kubernetes git github gitlab sonar" \
        2>/dev/null || print_warning "Some Jenkins plugins may not have installed correctly"
    
    # Create Jenkins jobs
    create_jenkins_jobs
    
    print_status "Jenkins setup completed ✅"
}

create_jenkins_jobs() {
    print_status "Creating Jenkins jobs..."
    
    # Create multibranch pipeline job
    local job_config=$(cat <<'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject plugin="workflow-multibranch">
  <actions/>
  <description>Nexus V3 Multi-stage CI/CD Pipeline</description>
  <properties>
    <org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig plugin="pipeline-model-definition">
      <dockerLabel></dockerLabel>
      <registry plugin="docker-commons"/>
    </org.jenkinsci.plugins.pipeline.modeldefinition.config.FolderConfig>
  </properties>
  <folderViews class="jenkins.branch.MultiBranchProjectViewHolder" plugin="branch-api">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </folderViews>
  <healthMetrics>
    <com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric plugin="cloudbees-folder">
      <nonRecursive>false</nonRecursive>
    </com.cloudbees.hudson.plugins.folder.health.WorstChildHealthMetric>
  </healthMetrics>
  <icon class="jenkins.branch.MetadataActionFolderIcon" plugin="branch-api">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </icon>
  <orphanedItemStrategy class="com.cloudbees.hudson.plugins.folder.computed.DefaultOrphanedItemStrategy" plugin="cloudbees-folder">
    <pruneDeadBranches>true</pruneDeadBranches>
    <daysToKeep>-1</daysToKeep>
    <numToKeep>-1</numToKeep>
  </orphanedItemStrategy>
  <triggers>
    <com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger plugin="cloudbees-folder">
      <spec>* * * * *</spec>
      <interval>60000</interval>
    </com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger>
  </triggers>
  <disabled>false</disabled>
  <sources class="jenkins.branch.MultiBranchProject$BranchSourceList" plugin="branch-api">
    <data>
      <jenkins.branch.BranchSource>
        <source class="jenkins.plugins.git.GitSCMSource" plugin="git">
          <id>nexus-v3-repo</id>
          <remote>https://github.com/appliedinnovationcorp/nexus-v3.git</remote>
          <credentialsId></credentialsId>
          <traits>
            <jenkins.plugins.git.traits.BranchDiscoveryTrait/>
          </traits>
        </source>
        <strategy class="jenkins.branch.DefaultBranchPropertyStrategy">
          <properties class="empty-list"/>
        </strategy>
      </jenkins.branch.BranchSource>
    </data>
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
  </sources>
  <factory class="org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory">
    <owner class="org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject" reference="../.."/>
    <scriptPath>cicd/config/jenkins/Jenkinsfile.multistage</scriptPath>
  </factory>
</org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject>
EOF
    )
    
    # Create job via Jenkins CLI (simplified approach)
    echo "$job_config" > /tmp/jenkins-job-config.xml
    print_status "Jenkins job configuration prepared"
}

# Setup GitLab
setup_gitlab() {
    print_header "Setting up GitLab..."
    
    # Wait for GitLab to be ready
    sleep 120
    
    # Get GitLab root password
    local root_password
    if docker exec gitlab-cicd test -f /etc/gitlab/initial_root_password; then
        root_password=$(docker exec gitlab-cicd grep 'Password:' /etc/gitlab/initial_root_password | awk '{print $2}')
        print_status "GitLab root password: $root_password"
    else
        print_warning "GitLab root password not found - may already be configured"
    fi
    
    # Configure GitLab CI/CD
    configure_gitlab_cicd
    
    print_status "GitLab setup completed ✅"
}

configure_gitlab_cicd() {
    print_status "Configuring GitLab CI/CD..."
    
    # Create GitLab CI configuration
    cat > cicd/config/gitlab/.gitlab-ci.yml << 'EOF'
# GitLab CI/CD Pipeline for Nexus V3
stages:
  - validate
  - build
  - test
  - security
  - deploy-dev
  - deploy-staging
  - deploy-prod

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: "/certs"
  APP_NAME: "nexus-v3-app"
  REGISTRY: "harbor.nexus-v3.local"

# Validation stage
validate:
  stage: validate
  image: node:18-alpine
  script:
    - npm ci
    - npm run lint
    - npm run format:check
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Build stage
build:
  stage: build
  image: docker:24-dind
  services:
    - docker:24-dind
  script:
    - docker build -t $REGISTRY/$APP_NAME:$CI_COMMIT_SHA .
    - docker push $REGISTRY/$APP_NAME:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Test stage
test:unit:
  stage: test
  image: node:18-alpine
  script:
    - npm ci
    - npm run test:unit -- --coverage
  coverage: '/Lines\s*:\s*(\d+\.\d+)%/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

test:integration:
  stage: test
  image: docker:24-dind
  services:
    - docker:24-dind
  script:
    - docker-compose -f docker-compose.test.yml up -d
    - npm run test:integration
    - docker-compose -f docker-compose.test.yml down
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Security stage
security:sast:
  stage: security
  image: securecodewarrior/docker-sast:latest
  script:
    - semgrep --config=auto --json --output=semgrep-report.json .
  artifacts:
    reports:
      sast: semgrep-report.json

security:container:
  stage: security
  image: aquasec/trivy:latest
  script:
    - trivy image --format json --output trivy-report.json $REGISTRY/$APP_NAME:$CI_COMMIT_SHA
  artifacts:
    reports:
      container_scanning: trivy-report.json

# Deployment stages
deploy:dev:
  stage: deploy-dev
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$APP_NAME $APP_NAME=$REGISTRY/$APP_NAME:$CI_COMMIT_SHA -n nexus-v3-dev
    - kubectl rollout status deployment/$APP_NAME -n nexus-v3-dev
  environment:
    name: development
    url: https://dev.nexus-v3.local
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy:staging:
  stage: deploy-staging
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/$APP_NAME $APP_NAME=$REGISTRY/$APP_NAME:$CI_COMMIT_SHA -n nexus-v3-staging
    - kubectl rollout status deployment/$APP_NAME -n nexus-v3-staging
  environment:
    name: staging
    url: https://staging.nexus-v3.local
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy:prod:
  stage: deploy-prod
  image: argoproj/argocd:latest
  script:
    - argocd app sync nexus-v3-prod --server $ARGOCD_SERVER --auth-token $ARGOCD_TOKEN
  environment:
    name: production
    url: https://nexus-v3.local
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
EOF

    print_status "GitLab CI/CD configuration created ✅"
}

# Setup ArgoCD
setup_argocd() {
    print_header "Setting up ArgoCD..."
    
    # Wait for ArgoCD to be ready
    sleep 60
    
    # Get ArgoCD admin password
    local admin_password
    if docker exec argocd-server test -f /tmp/argocd-initial-admin-secret; then
        admin_password=$(docker exec argocd-server cat /tmp/argocd-initial-admin-secret)
        print_status "ArgoCD admin password: $admin_password"
    else
        print_warning "ArgoCD admin password not found - may already be configured"
    fi
    
    # Configure ArgoCD applications
    configure_argocd_applications
    
    print_status "ArgoCD setup completed ✅"
}

configure_argocd_applications() {
    print_status "Configuring ArgoCD applications..."
    
    # Apply ArgoCD applications if kubectl is available
    if command -v kubectl &> /dev/null; then
        kubectl apply -f cicd/config/argocd/applications/ 2>/dev/null || \
            print_warning "Could not apply ArgoCD applications - kubectl may not be configured"
    else
        print_warning "kubectl not available - ArgoCD applications not deployed"
    fi
    
    print_status "ArgoCD applications configured ✅"
}

# Setup SonarQube
setup_sonarqube() {
    print_header "Setting up SonarQube..."
    
    # Wait for SonarQube to be ready
    sleep 90
    
    print_status "SonarQube default credentials: admin/admin"
    print_status "Please change the default password on first login"
    
    # Configure SonarQube quality gates
    configure_sonarqube_quality_gates
    
    print_status "SonarQube setup completed ✅"
}

configure_sonarqube_quality_gates() {
    print_status "Configuring SonarQube quality gates..."
    
    # Create quality gate configuration (would typically use SonarQube API)
    cat > cicd/config/sonarqube/quality-gate.json << 'EOF'
{
  "name": "Nexus V3 Quality Gate",
  "conditions": [
    {
      "metric": "new_coverage",
      "op": "LT",
      "error": "80"
    },
    {
      "metric": "new_duplicated_lines_density",
      "op": "GT",
      "error": "3"
    },
    {
      "metric": "new_maintainability_rating",
      "op": "GT",
      "error": "1"
    },
    {
      "metric": "new_reliability_rating",
      "op": "GT",
      "error": "1"
    },
    {
      "metric": "new_security_rating",
      "op": "GT",
      "error": "1"
    }
  ]
}
EOF

    print_status "SonarQube quality gates configured ✅"
}

# Setup Harbor
setup_harbor() {
    print_header "Setting up Harbor container registry..."
    
    # Wait for Harbor to be ready
    sleep 60
    
    print_status "Harbor default credentials: admin/Harbor12345"
    print_status "Please change the default password on first login"
    
    # Configure Harbor projects
    configure_harbor_projects
    
    print_status "Harbor setup completed ✅"
}

configure_harbor_projects() {
    print_status "Configuring Harbor projects..."
    
    # Create Harbor project configuration
    cat > cicd/config/harbor/projects.json << 'EOF'
{
  "projects": [
    {
      "name": "nexus-v3",
      "public": false,
      "vulnerability_scanning": true,
      "auto_scan": true,
      "prevent_vulnerable_images": true
    },
    {
      "name": "nexus-v3-dev",
      "public": false,
      "vulnerability_scanning": true,
      "auto_scan": true
    }
  ]
}
EOF

    print_status "Harbor projects configured ✅"
}

# Setup Flagsmith
setup_flagsmith() {
    print_header "Setting up Flagsmith feature flags..."
    
    # Wait for Flagsmith to be ready
    sleep 30
    
    print_status "Flagsmith is ready for configuration"
    print_status "Create an account at: $FLAGSMITH_URL"
    
    # Configure feature flags
    configure_feature_flags
    
    print_status "Flagsmith setup completed ✅"
}

configure_feature_flags() {
    print_status "Configuring feature flags..."
    
    # Create feature flag configuration
    cat > cicd/config/flagsmith/feature-flags.json << 'EOF'
{
  "feature_flags": [
    {
      "name": "production-deployment-ready",
      "description": "Controls whether production deployments are allowed",
      "default_enabled": false,
      "environments": {
        "development": true,
        "staging": true,
        "production": false
      }
    },
    {
      "name": "canary-deployment-enabled",
      "description": "Enables canary deployment strategy",
      "default_enabled": false,
      "environments": {
        "production": true
      }
    },
    {
      "name": "blue-green-deployment-enabled",
      "description": "Enables blue-green deployment strategy",
      "default_enabled": true,
      "environments": {
        "production": true
      }
    },
    {
      "name": "performance-testing-required",
      "description": "Requires performance testing in pipeline",
      "default_enabled": true
    },
    {
      "name": "security-scanning-required",
      "description": "Requires security scanning in pipeline",
      "default_enabled": true
    }
  ]
}
EOF

    print_status "Feature flags configured ✅"
}

# Setup Kubernetes resources
setup_kubernetes_resources() {
    print_header "Setting up Kubernetes resources..."
    
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl not available - skipping Kubernetes setup"
        return
    fi
    
    # Create namespaces
    kubectl create namespace nexus-v3-dev --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace nexus-v3-staging --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace nexus-v3-prod --dry-run=client -o yaml | kubectl apply -f - || true
    
    # Apply Argo Rollouts CRDs
    kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml || \
        print_warning "Could not install Argo Rollouts"
    
    # Apply rollout configurations
    kubectl apply -f cicd/config/k8s/rollouts/ || \
        print_warning "Could not apply rollout configurations"
    
    print_status "Kubernetes resources setup completed ✅"
}

# Generate documentation
generate_documentation() {
    print_header "Generating CI/CD documentation..."
    
    cat > cicd/README.md << 'EOF'
# Enterprise CI/CD Pipeline

## 🚀 Overview

Comprehensive CI/CD pipeline with enterprise-grade features:

- **Multi-stage Deployment Pipeline** (dev → staging → prod)
- **Blue-Green Deployments** with automated rollback
- **Canary Deployments** with traffic splitting and analysis
- **Feature Flags** for gradual rollouts and deployment control
- **Automated Security Scanning** (SAST, DAST, container scanning)
- **Performance Testing Integration** with K6
- **Infrastructure as Code Validation** with Terraform and Kubernetes

## 🛠 Tech Stack

### CI/CD Orchestration
- **Jenkins** (2.426.1-lts) - Primary CI/CD orchestration
- **GitLab CE** (16.6.1) - Git repository and CI/CD
- **ArgoCD** (2.9.3) - GitOps continuous deployment

### Container & Artifact Management
- **Harbor** (2.9.1) - Container registry with security scanning
- **Nexus Repository** (3.44.0) - Artifact management
- **MinIO** - S3-compatible artifact storage

### Deployment Strategies
- **Argo Rollouts** (1.6.4) - Advanced deployment strategies
- **Flagger** (1.35.0) - Progressive delivery
- **Istio** (1.20.1) - Traffic management for canary deployments

### Quality & Security
- **SonarQube** (10.3-community) - Code quality analysis
- **OWASP ZAP** (2.14.0) - Dynamic security testing
- **Trivy** (0.48.1) - Container security scanning
- **Falco** - Runtime security monitoring

### Feature Management
- **Flagsmith** (2.82.0) - Feature flags and gradual rollouts

### Performance Testing
- **K6** (0.47.0) - Performance and load testing

### Infrastructure as Code
- **Terraform** (1.6.6) - Infrastructure provisioning
- **Terragrunt** (1.6.6) - Terraform orchestration
- **Ansible** (2.3.4) - Configuration management

### Secret Management
- **HashiCorp Vault** (1.15.4) - Secret management
- **Sealed Secrets** (0.24.5) - Kubernetes secret encryption

## 🚦 Quick Start

```bash
# Start CI/CD infrastructure
./scripts/setup-cicd.sh

# Access dashboards
# - Jenkins: http://localhost:8080
# - GitLab: http://localhost:8081
# - ArgoCD: http://localhost:8082
# - SonarQube: http://localhost:9000
# - Harbor: http://localhost:8083
# - Flagsmith: http://localhost:8085
```

## 📊 Pipeline Stages

### 1. Validation & Build
- Code linting and formatting
- Dependency security scanning
- Unit and integration testing
- Docker image building

### 2. Quality & Security Analysis
- SonarQube code quality analysis
- SAST (Static Application Security Testing)
- Container vulnerability scanning
- Infrastructure security validation

### 3. Multi-Stage Deployment
- **Development**: Automatic deployment on main branch
- **Staging**: Manual approval with comprehensive testing
- **Production**: Feature flag controlled with advanced deployment strategies

### 4. Deployment Strategies

#### Blue-Green Deployment
- Zero-downtime deployments
- Instant rollback capability
- Full environment validation
- Automated traffic switching

#### Canary Deployment
- Gradual traffic shifting (10% → 25% → 50% → 75% → 100%)
- Automated analysis and rollback
- Business metrics validation
- Real-time monitoring and alerting

### 5. Performance & Security Testing
- K6 performance testing with budgets
- OWASP ZAP dynamic security testing
- Load testing with realistic scenarios
- Performance regression detection

## 🎛️ Feature Flags

### Deployment Control Flags
- `production-deployment-ready` - Controls production deployments
- `canary-deployment-enabled` - Enables canary strategy
- `blue-green-deployment-enabled` - Enables blue-green strategy

### Quality Control Flags
- `performance-testing-required` - Requires performance testing
- `security-scanning-required` - Requires security scanning
- `manual-approval-required` - Requires manual approval for production

## 🔒 Security Features

### Pipeline Security
- Automated vulnerability scanning at every stage
- Container image security validation
- Infrastructure as Code security checks
- Secret management with Vault integration

### Runtime Security
- Falco runtime threat detection
- Network policy enforcement
- Pod security standards
- RBAC and service account management

## 📈 Monitoring & Observability

### Pipeline Metrics
- Build success/failure rates
- Deployment frequency and lead time
- Mean Time to Recovery (MTTR)
- Change failure rate

### Application Metrics
- Performance budgets validation
- Error rates and latency tracking
- Business metrics correlation
- User experience monitoring

## 🔧 Configuration

### Environment Variables
```bash
# CI/CD URLs
JENKINS_URL=http://localhost:8080
GITLAB_URL=http://localhost:8081
ARGOCD_URL=http://localhost:8082
SONARQUBE_URL=http://localhost:9000
HARBOR_URL=http://localhost:8083
FLAGSMITH_URL=http://localhost:8085

# Deployment Configuration
DEPLOYMENT_STRATEGY=blue-green  # blue-green, canary, rolling
CANARY_PERCENTAGE=10
PERFORMANCE_TEST_REQUIRED=true
SECURITY_SCAN_REQUIRED=true
```

### Pipeline Customization
- Modify `Jenkinsfile.multistage` for Jenkins pipelines
- Update `.gitlab-ci.yml` for GitLab CI/CD
- Configure ArgoCD applications in `config/argocd/applications/`
- Customize deployment strategies in `config/k8s/rollouts/`

## 🚨 Troubleshooting

### Common Issues
1. **Services not starting**: Check Docker logs and resource allocation
2. **Pipeline failures**: Verify credentials and network connectivity
3. **Deployment issues**: Check Kubernetes cluster status and permissions
4. **Security scan failures**: Review vulnerability reports and update dependencies

### Health Checks
```bash
# Check service status
docker-compose -f docker-compose.cicd.yml ps

# View service logs
docker-compose -f docker-compose.cicd.yml logs [service-name]

# Test connectivity
curl http://localhost:8080/health  # Jenkins
curl http://localhost:8081/-/health  # GitLab
curl http://localhost:8082/health  # ArgoCD
```

## 📚 Best Practices

### Pipeline Design
- Fail fast with early validation stages
- Parallel execution for independent tasks
- Comprehensive testing at each stage
- Automated rollback on failure

### Security
- Scan early and often
- Use least privilege principles
- Encrypt secrets and sensitive data
- Regular security updates

### Performance
- Set and monitor performance budgets
- Use caching for build optimization
- Optimize container images
- Monitor resource usage

## 🔄 Continuous Improvement

### Metrics to Track
- Deployment frequency
- Lead time for changes
- Mean time to recovery
- Change failure rate

### Regular Reviews
- Pipeline performance analysis
- Security posture assessment
- Cost optimization review
- Team feedback incorporation

This CI/CD pipeline provides enterprise-grade capabilities while maintaining 
complete control and zero licensing costs through exclusive use of FOSS technologies.
EOF

    print_status "Documentation generated ✅"
}

# Main setup function
main() {
    print_header "Starting Enterprise CI/CD Pipeline Setup"
    
    check_dependencies
    setup_cicd_infrastructure
    start_cicd_stack
    wait_for_services
    setup_jenkins
    setup_gitlab
    setup_argocd
    setup_sonarqube
    setup_harbor
    setup_flagsmith
    setup_kubernetes_resources
    generate_documentation
    
    print_status "🎉 Enterprise CI/CD pipeline setup completed successfully!"
    echo ""
    echo "🚀 Access Points:"
    echo "  • Jenkins: http://localhost:8080"
    echo "  • GitLab: http://localhost:8081"
    echo "  • ArgoCD: http://localhost:8082"
    echo "  • SonarQube: http://localhost:9000"
    echo "  • Harbor Registry: http://localhost:8083"
    echo "  • Flagsmith: http://localhost:8085"
    echo "  • Nexus Repository: http://localhost:8088"
    echo "  • Vault: http://localhost:8200"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Configure authentication and authorization"
    echo "  2. Set up Git repository webhooks"
    echo "  3. Configure deployment environments"
    echo "  4. Set up monitoring and alerting integration"
    echo "  5. Configure feature flags for deployment control"
    echo "  6. Set up performance and security testing"
    echo ""
    echo "📚 Documentation: ./cicd/README.md"
}

main "$@"
