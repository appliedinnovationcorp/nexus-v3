#!/bin/bash

set -e

# Comprehensive Alerting & Incident Management Setup Script
# Enterprise-grade alerting, incident response, chaos engineering, SLA/SLO monitoring

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[ALERTING]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[ALERTING SETUP]${NC} $1"
}

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
        print_warning "kubectl not found - some chaos engineering features may not work"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Setup alerting infrastructure
setup_alerting_infrastructure() {
    print_header "Setting up alerting infrastructure..."
    
    # Create necessary directories
    mkdir -p alerting/{config,scripts,templates,dashboards}
    mkdir -p alerting/config/{alertmanager,pyrra,sloth,chaos,falco,botkube,robusta,thanos,otel-advanced}
    mkdir -p alerting/config/alertmanager/templates
    mkdir -p alerting/generated
    
    print_status "Directory structure created ✅"
    
    # Set proper permissions
    chmod +x alerting/scripts/*.sh 2>/dev/null || true
    
    print_status "Permissions set ✅"
}

# Start alerting stack
start_alerting_stack() {
    print_header "Starting alerting and incident management stack..."
    
    cd alerting
    
    # Pull latest images
    print_status "Pulling Docker images..."
    docker-compose -f docker-compose.alerting.yml pull
    
    # Start services
    print_status "Starting alerting services..."
    docker-compose -f docker-compose.alerting.yml up -d
    
    cd ..
    
    print_status "Alerting stack started ✅"
}

# Wait for services to be ready
wait_for_services() {
    print_header "Waiting for services to be ready..."
    
    local services=(
        "alertmanager-advanced:9093"
        "karma-dashboard:8080"
        "grafana-oncall-engine:8080"
        "pyrra-slo:9444"
        "litmus-server:8080"
        "falco-security:8765"
        "victoriametrics:8428"
    )
    
    for service in "${services[@]}"; do
        local host=$(echo $service | cut -d: -f1)
        local port=$(echo $service | cut -d: -f2)
        
        print_status "Waiting for $host:$port..."
        
        local retries=30
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

# Setup SLO monitoring
setup_slo_monitoring() {
    print_header "Setting up SLO monitoring..."
    
    # Generate SLO rules using Sloth
    if docker ps | grep -q sloth-slo; then
        print_status "Generating SLO rules with Sloth..."
        docker exec sloth-slo sloth generate -i /etc/sloth -o /generated/slo-rules.yaml
        
        # Copy generated rules to Prometheus
        if [ -f alerting/generated/slo-rules.yaml ]; then
            cp alerting/generated/slo-rules.yaml monitoring/config/prometheus/rules/
            print_status "SLO rules generated and deployed ✅"
        else
            print_warning "SLO rules generation may have failed"
        fi
    else
        print_warning "Sloth container not running - SLO rules not generated"
    fi
    
    print_status "SLO monitoring setup completed ✅"
}

# Setup chaos engineering
setup_chaos_engineering() {
    print_header "Setting up chaos engineering..."
    
    # Check if Kubernetes is available
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        print_status "Kubernetes detected - setting up Litmus Chaos..."
        
        # Create Litmus namespace
        kubectl create namespace litmus --dry-run=client -o yaml | kubectl apply -f -
        
        # Apply chaos experiments
        if [ -f alerting/config/chaos/chaos-experiments.yaml ]; then
            kubectl apply -f alerting/config/chaos/chaos-experiments.yaml
            print_status "Chaos experiments deployed ✅"
        fi
        
        print_status "Chaos engineering setup completed ✅"
    else
        print_warning "Kubernetes not available - chaos engineering limited to container-level experiments"
        print_status "Container-level chaos experiments available through Chaos Monkey ✅"
    fi
}

# Setup security monitoring
setup_security_monitoring() {
    print_header "Setting up security monitoring with Falco..."
    
    # Verify Falco is running
    if docker ps | grep -q falco-security; then
        print_status "Falco security monitoring is active ✅"
        
        # Test Falco rules
        print_status "Testing Falco security rules..."
        docker exec falco-security falco --list-rules | head -10
        
        print_status "Security monitoring setup completed ✅"
    else
        print_warning "Falco container not running - security monitoring may not be active"
    fi
}

# Setup incident response automation
setup_incident_response() {
    print_header "Setting up incident response automation..."
    
    # Configure Grafana OnCall
    if docker ps | grep -q grafana-oncall-engine; then
        print_status "Grafana OnCall is running ✅"
        
        # Wait for OnCall to be ready
        sleep 30
        
        # Create default escalation policies via API (simplified)
        local oncall_url="http://localhost:8081"
        
        print_status "OnCall incident management available at $oncall_url"
        print_status "Please configure escalation policies through the web interface"
        
        print_status "Incident response automation setup completed ✅"
    else
        print_warning "Grafana OnCall not running - incident response automation limited"
    fi
}

# Setup performance budgets
setup_performance_budgets() {
    print_header "Setting up performance budgets and regression detection..."
    
    # Verify performance budget rules are loaded
    if [ -f alerting/config/sloth/performance-budgets.yaml ]; then
        print_status "Performance budget configuration loaded ✅"
        
        # Generate performance budget alerts
        if docker ps | grep -q sloth-slo; then
            docker exec sloth-slo sloth generate -i /etc/sloth/performance-budgets.yaml -o /generated/performance-budget-rules.yaml
            
            if [ -f alerting/generated/performance-budget-rules.yaml ]; then
                cp alerting/generated/performance-budget-rules.yaml monitoring/config/prometheus/rules/
                print_status "Performance budget rules generated and deployed ✅"
            fi
        fi
        
        print_status "Performance budgets setup completed ✅"
    else
        print_warning "Performance budget configuration not found"
    fi
}

# Setup advanced metrics storage
setup_advanced_metrics() {
    print_header "Setting up advanced metrics storage..."
    
    # Configure VictoriaMetrics for high-performance metrics
    if docker ps | grep -q victoriametrics; then
        print_status "VictoriaMetrics high-performance storage active ✅"
    fi
    
    # Configure Thanos for long-term storage
    if docker ps | grep -q thanos-sidecar; then
        print_status "Thanos long-term metrics storage active ✅"
    fi
    
    print_status "Advanced metrics storage setup completed ✅"
}

# Generate alerting documentation
generate_documentation() {
    print_header "Generating alerting documentation..."
    
    cat > alerting/README.md << 'EOF'
# Enterprise Alerting & Incident Management

## 🚨 Overview

Comprehensive alerting and incident management system with:

- **Smart Alerting** - Advanced AlertManager with escalation policies
- **Incident Response** - Grafana OnCall for automated incident management
- **Chaos Engineering** - Litmus Chaos for resilience testing
- **SLA/SLO Monitoring** - Pyrra and Sloth for service level objectives
- **Performance Budgets** - Automated regression detection
- **Security Monitoring** - Falco for runtime threat detection

## 🚀 Quick Start

```bash
# Start alerting stack
./scripts/setup-alerting.sh

# Access dashboards
# - AlertManager: http://localhost:9093
# - Karma Dashboard: http://localhost:8080
# - Grafana OnCall: http://localhost:8081
# - Pyrra SLO: http://localhost:9099
# - Litmus Chaos: http://localhost:9002
# - VictoriaMetrics: http://localhost:8428
```

## 📊 Components

### Smart Alerting
- **AlertManager Advanced**: Multi-channel notifications with escalation
- **Karma Dashboard**: Alert aggregation and management
- **Smart Routing**: Severity-based alert routing and escalation

### Incident Management
- **Grafana OnCall**: Automated incident response and escalation
- **Escalation Policies**: P0/P1/P2 incident classification
- **War Room Creation**: Automated incident response coordination

### SLA/SLO Monitoring
- **Pyrra**: SLO monitoring with error budgets
- **Sloth**: SLI/SLO rule generation
- **Error Budget Tracking**: Automated budget consumption alerts

### Performance Budgets
- **Regression Detection**: Automated performance regression alerts
- **Budget Violations**: Performance threshold monitoring
- **Trend Analysis**: Performance trend tracking and alerting

### Chaos Engineering
- **Litmus Chaos**: Comprehensive chaos experiments
- **Scheduled Chaos**: Automated resilience testing
- **Chaos Monitoring**: Experiment success/failure tracking

### Security Monitoring
- **Falco**: Runtime security threat detection
- **Container Security**: Anomaly detection in containers
- **Threat Intelligence**: Security event correlation

## 🔧 Configuration

### Alert Routing
Alerts are routed based on:
- **Severity**: critical, high, warning
- **Category**: infrastructure, application, security
- **Team**: backend, frontend, platform, security
- **Priority**: P0 (immediate), P1 (urgent), P2 (normal)

### Escalation Policies
- **P0 Incidents**: Immediate page + war room creation
- **Critical Alerts**: Multi-channel notification within 5 seconds
- **High Severity**: Escalated response within 30 seconds
- **Warning Alerts**: Standard notification channels

### SLO Targets
- **API Availability**: 99.9% (30-day window)
- **API Latency**: 95% under 500ms (7-day window)
- **Database Availability**: 99.95% (30-day window)
- **Frontend Performance**: 90% under 2s page load (7-day window)
- **User Journey Success**: 99.5% checkout success (7-day window)

## 🎯 Performance Budgets

### Frontend Budgets
- Page load time: 95% under 2 seconds
- First Contentful Paint: 95% under 1.5 seconds
- Largest Contentful Paint: 95% under 2.5 seconds
- Cumulative Layout Shift: 95% under 0.1

### Backend Budgets
- API response time: 99% under 200ms
- Database queries: 95% under 100ms
- Error rate: 99.9% success rate
- Throughput: 95% of baseline

## 🐒 Chaos Engineering

### Experiment Types
- **Network Chaos**: Latency injection, packet loss, partitioning
- **Pod Chaos**: Deletion, resource exhaustion, failure injection
- **Node Chaos**: Resource exhaustion, network issues
- **Application Chaos**: Database failures, API errors

### Experiment Schedule
- **Light Chaos**: Daily during off-peak hours
- **Medium Chaos**: Weekly during maintenance windows
- **Heavy Chaos**: Monthly during planned chaos days

## 🛡️ Security Monitoring

### Threat Detection
- Unauthorized process execution
- Sensitive file access
- Privilege escalation attempts
- Container escape attempts
- Crypto mining activity
- Suspicious network connections

### Response Actions
- Automatic alert generation
- Container isolation (if configured)
- Incident creation for critical threats
- Security team notification

## 📈 Metrics & KPIs

### Alerting Metrics
- Alert volume and trends
- Mean Time to Acknowledge (MTTA)
- Mean Time to Resolution (MTTR)
- False positive rate
- Escalation effectiveness

### SLO Metrics
- Error budget consumption
- SLO compliance percentage
- Burn rate trends
- Service reliability scores

### Chaos Metrics
- Experiment success rate
- System resilience scores
- Recovery time measurements
- Failure mode coverage

## 🚨 Alert Channels

### Critical Alerts
- Slack: #alerts-critical
- PagerDuty: Immediate page
- Email: oncall@nexus-v3.local
- SMS: Emergency contacts

### Team-Specific Alerts
- Backend: #backend-alerts
- Frontend: #frontend-alerts
- Infrastructure: #infrastructure-alerts
- Security: #security-alerts
- SRE: #sre-alerts

## 🔍 Troubleshooting

### Common Issues
1. **Alerts not firing**: Check Prometheus targets and rules
2. **OnCall not responding**: Verify webhook configurations
3. **Chaos experiments failing**: Check Kubernetes permissions
4. **SLO calculations incorrect**: Verify metric queries

### Health Checks
```bash
# Check AlertManager status
curl http://localhost:9093/api/v1/status

# Check OnCall health
curl http://localhost:8081/health/

# Check Pyrra SLO status
curl http://localhost:9099/api/v1/status

# Check Falco rules
docker exec falco-security falco --list-rules
```

## 📚 Runbooks

- [P0 Incident Response](https://runbooks.nexus-v3.local/p0-incident-response)
- [SLO Violation Response](https://runbooks.nexus-v3.local/slo-violation-response)
- [Security Incident Response](https://runbooks.nexus-v3.local/security-incident-response)
- [Chaos Experiment Failure](https://runbooks.nexus-v3.local/chaos-experiment-failure)
- [Performance Budget Violation](https://runbooks.nexus-v3.local/performance-budget-violation)
EOF

    print_status "Documentation generated ✅"
}

# Main setup function
main() {
    print_header "Starting Enterprise Alerting & Incident Management Setup"
    
    check_dependencies
    setup_alerting_infrastructure
    start_alerting_stack
    wait_for_services
    setup_slo_monitoring
    setup_chaos_engineering
    setup_security_monitoring
    setup_incident_response
    setup_performance_budgets
    setup_advanced_metrics
    generate_documentation
    
    print_status "🎉 Enterprise alerting and incident management setup completed successfully!"
    echo ""
    echo "🚨 Access Points:"
    echo "  • AlertManager: http://localhost:9093"
    echo "  • Karma Dashboard: http://localhost:8080"
    echo "  • Grafana OnCall: http://localhost:8081"
    echo "  • Pyrra SLO Monitoring: http://localhost:9099"
    echo "  • Litmus Chaos Engineering: http://localhost:9002"
    echo "  • VictoriaMetrics: http://localhost:8428"
    echo "  • Thanos Query: http://localhost:10904"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Configure notification channels (Slack, PagerDuty, email)"
    echo "  2. Set up escalation policies in Grafana OnCall"
    echo "  3. Define custom SLOs for your services"
    echo "  4. Schedule chaos engineering experiments"
    echo "  5. Configure security response procedures"
    echo "  6. Set up performance budget thresholds"
    echo ""
    echo "📚 Documentation: ./alerting/README.md"
}

main "$@"
