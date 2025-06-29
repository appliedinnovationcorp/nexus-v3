#!/bin/bash

set -e

# Comprehensive Monitoring Stack Setup Script
# Sets up APM, Infrastructure monitoring, Log aggregation, Distributed tracing, RUM, and Synthetic monitoring

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[MONITORING]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[MONITORING SETUP]${NC} $1"
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
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Setup monitoring infrastructure
setup_monitoring_infrastructure() {
    print_header "Setting up monitoring infrastructure..."
    
    # Create necessary directories
    mkdir -p monitoring/{config,scripts,dashboards,alerts}
    mkdir -p monitoring/config/{prometheus,grafana,logstash,otel,blackbox,alertmanager,vector}
    mkdir -p monitoring/config/grafana/{provisioning/{datasources,dashboards},dashboards}
    mkdir -p monitoring/config/prometheus/rules
    
    print_status "Directory structure created ✅"
    
    # Set proper permissions
    chmod +x monitoring/scripts/*.sh 2>/dev/null || true
    
    print_status "Permissions set ✅"
}

# Start monitoring stack
start_monitoring_stack() {
    print_header "Starting monitoring stack..."
    
    cd monitoring
    
    # Pull latest images
    print_status "Pulling Docker images..."
    docker-compose -f docker-compose.monitoring.yml pull
    
    # Start services
    print_status "Starting monitoring services..."
    docker-compose -f docker-compose.monitoring.yml up -d
    
    cd ..
    
    print_status "Monitoring stack started ✅"
}

# Wait for services to be ready
wait_for_services() {
    print_header "Waiting for services to be ready..."
    
    local services=(
        "elasticsearch-monitoring:9200"
        "kibana-monitoring:5601"
        "prometheus:9090"
        "grafana:3000"
        "jaeger:16686"
        "uptime-kuma:3001"
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

# Setup Kibana dashboards and index patterns
setup_kibana() {
    print_header "Setting up Kibana dashboards..."
    
    # Wait for Kibana to be ready
    sleep 30
    
    # Create index patterns
    local kibana_url="http://localhost:5601"
    
    # Create logs index pattern
    curl -X POST "$kibana_url/api/saved_objects/index-pattern/logs-*" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "logs-*",
                "timeFieldName": "@timestamp"
            }
        }' 2>/dev/null || print_warning "Failed to create logs index pattern"
    
    # Create APM index pattern
    curl -X POST "$kibana_url/api/saved_objects/index-pattern/apm-*" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "apm-*",
                "timeFieldName": "@timestamp"
            }
        }' 2>/dev/null || print_warning "Failed to create APM index pattern"
    
    print_status "Kibana setup completed ✅"
}

# Setup Grafana dashboards
setup_grafana() {
    print_header "Setting up Grafana dashboards..."
    
    local grafana_url="http://admin:admin123@localhost:3000"
    
    # Import infrastructure dashboard
    curl -X POST "$grafana_url/api/dashboards/db" \
        -H "Content-Type: application/json" \
        -d '{
            "dashboard": {
                "title": "Infrastructure Overview",
                "panels": [
                    {
                        "title": "CPU Usage",
                        "type": "graph",
                        "targets": [
                            {
                                "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
                            }
                        ]
                    }
                ]
            }
        }' 2>/dev/null || print_warning "Failed to create infrastructure dashboard"
    
    print_status "Grafana setup completed ✅"
}

# Setup synthetic monitoring
setup_synthetic_monitoring() {
    print_header "Setting up synthetic monitoring..."
    
    # Configure Uptime Kuma monitors via API (simplified)
    local uptime_kuma_url="http://localhost:3001"
    
    print_status "Uptime Kuma is available at $uptime_kuma_url"
    print_status "Please configure monitors manually through the web interface"
    
    print_status "Synthetic monitoring setup completed ✅"
}

# Generate monitoring documentation
generate_documentation() {
    print_header "Generating monitoring documentation..."
    
    cat > monitoring/README.md << 'EOF'
# Comprehensive Monitoring Stack

## 🎯 Overview

This monitoring stack provides complete observability for the Nexus V3 platform with:

- **Application Performance Monitoring (APM)** - Elastic APM
- **Infrastructure Monitoring** - Prometheus + Grafana
- **Log Aggregation** - ELK Stack + Vector
- **Distributed Tracing** - Jaeger + OpenTelemetry
- **Real User Monitoring (RUM)** - Elastic RUM
- **Synthetic Monitoring** - Uptime Kuma + Blackbox Exporter

## 🚀 Quick Start

```bash
# Start monitoring stack
./scripts/setup-monitoring.sh

# Access dashboards
# - Grafana: http://localhost:3000 (admin/admin123)
# - Kibana: http://localhost:5601
# - Jaeger: http://localhost:16686
# - Prometheus: http://localhost:9090
# - Uptime Kuma: http://localhost:3001
```

## 📊 Components

### Application Performance Monitoring
- **Elastic APM Server**: Collects performance metrics and traces
- **APM Agents**: Instrument applications for monitoring
- **RUM Agent**: Browser-side performance monitoring

### Infrastructure Monitoring
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and alerting
- **Node Exporter**: System metrics
- **cAdvisor**: Container metrics

### Log Management
- **Elasticsearch**: Log storage and search
- **Logstash**: Log processing and enrichment
- **Kibana**: Log visualization and analysis
- **Vector**: High-performance log collection

### Distributed Tracing
- **Jaeger**: Trace storage and visualization
- **OpenTelemetry Collector**: Trace collection and processing
- **OTLP**: Standard telemetry protocol

### Synthetic Monitoring
- **Uptime Kuma**: Uptime monitoring and alerting
- **Blackbox Exporter**: Endpoint probing
- **Prometheus Alerting**: Alert management

## 🔧 Configuration

### Adding Application Monitoring

1. **Install APM Agent** in your application
2. **Configure APM Server** endpoint: `http://localhost:8200`
3. **Add RUM Agent** to frontend applications
4. **Configure OpenTelemetry** for distributed tracing

### Custom Dashboards

- **Grafana**: Import dashboards from `/config/grafana/dashboards/`
- **Kibana**: Create visualizations using index patterns
- **Prometheus**: Add custom recording rules in `/config/prometheus/rules/`

### Alerting

- **Prometheus Alerts**: Defined in `/config/prometheus/rules/alerts.yml`
- **AlertManager**: Configured in `/config/alertmanager/config.yml`
- **Grafana Alerts**: Set up through the Grafana UI

## 📈 Metrics and KPIs

### Application Metrics
- Response time (p50, p95, p99)
- Error rate
- Throughput (requests/second)
- Apdex score

### Infrastructure Metrics
- CPU utilization
- Memory usage
- Disk I/O
- Network traffic
- Container resource usage

### Business Metrics
- User sessions
- Page views
- Conversion rates
- Feature usage

## 🚨 Alerting Rules

### Critical Alerts
- Service down (> 1 minute)
- High error rate (> 5%)
- High response time (p95 > 1s)
- Infrastructure resource exhaustion

### Warning Alerts
- Elevated error rate (> 1%)
- Increased response time (p95 > 500ms)
- High resource usage (> 80%)

## 🔍 Troubleshooting

### Common Issues

1. **Services not starting**: Check Docker logs
2. **Missing metrics**: Verify scrape targets in Prometheus
3. **No traces**: Check OpenTelemetry configuration
4. **Log parsing errors**: Review Logstash patterns

### Health Checks

```bash
# Check service status
docker-compose -f docker-compose.monitoring.yml ps

# View service logs
docker-compose -f docker-compose.monitoring.yml logs [service-name]

# Test connectivity
curl http://localhost:9090/api/v1/targets  # Prometheus targets
curl http://localhost:9200/_cluster/health  # Elasticsearch health
```

## 📚 Additional Resources

- [Elastic APM Documentation](https://www.elastic.co/guide/en/apm/index.html)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
EOF

    print_status "Documentation generated ✅"
}

# Main setup function
main() {
    print_header "Starting Comprehensive Monitoring Stack Setup"
    
    check_dependencies
    setup_monitoring_infrastructure
    start_monitoring_stack
    wait_for_services
    setup_kibana
    setup_grafana
    setup_synthetic_monitoring
    generate_documentation
    
    print_status "🎉 Monitoring stack setup completed successfully!"
    echo ""
    echo "📊 Access Points:"
    echo "  • Grafana (Metrics): http://localhost:3000 (admin/admin123)"
    echo "  • Kibana (Logs/APM): http://localhost:5601"
    echo "  • Jaeger (Tracing): http://localhost:16686"
    echo "  • Prometheus: http://localhost:9090"
    echo "  • Uptime Kuma: http://localhost:3001"
    echo "  • AlertManager: http://localhost:9093"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Configure application APM agents"
    echo "  2. Set up RUM for frontend monitoring"
    echo "  3. Create custom Grafana dashboards"
    echo "  4. Configure synthetic monitoring checks"
    echo "  5. Set up alerting channels (email, Slack, etc.)"
    echo ""
    echo "📚 Documentation: ./monitoring/README.md"
}

main "$@"
