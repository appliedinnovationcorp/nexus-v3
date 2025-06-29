#!/bin/bash

# Enterprise Infrastructure Scaling Setup Script
# Comprehensive infrastructure scaling with 100% FOSS technologies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
    
    # Check Terraform (optional but recommended)
    if ! command -v terraform &> /dev/null; then
        warn "Terraform is not installed. Some features may be limited."
    fi
    
    # Check Ansible (optional but recommended)
    if ! command -v ansible &> /dev/null; then
        warn "Ansible is not installed. Some automation features may be limited."
    fi
    
    # Check available disk space (minimum 50GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 52428800 ]; then
        warn "Less than 50GB disk space available. Infrastructure scaling may require more space."
    fi
    
    # Check available memory (minimum 32GB recommended)
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_memory" -lt 32768 ]; then
        warn "Less than 32GB RAM available. Performance may be impacted with full scaling."
    fi
    
    log "Prerequisites check completed"
}

# Initialize configuration files
init_configs() {
    log "Initializing configuration files..."
    
    # Create directory structure
    mkdir -p config/{consul,nomad,haproxy,keepalived,prometheus,grafana/{provisioning,dashboards},varnish,nginx,pgpool,postgres,redis,auto-scaler,health-checker,dr-manager,traffic-manager,predictive-scaler}
    mkdir -p docker/{auto-scaler,nginx-edge,health-checker,dr-manager,traffic-manager,predictive-scaler}
    mkdir -p terraform/{modules,environments}
    mkdir -p ansible/{playbooks,roles,inventory}
    mkdir -p kubernetes/{manifests,helm-charts}
    mkdir -p ssl
    mkdir -p logs
    mkdir -p backups
    mkdir -p models
    
    # Consul configuration
    cat > config/consul/consul.json << 'EOF'
{
  "datacenter": "dc1",
  "data_dir": "/consul/data",
  "log_level": "INFO",
  "server": true,
  "bootstrap_expect": 1,
  "bind_addr": "0.0.0.0",
  "client_addr": "0.0.0.0",
  "retry_join": ["consul-server"],
  "ui_config": {
    "enabled": true
  },
  "connect": {
    "enabled": true
  },
  "ports": {
    "grpc": 8502
  },
  "services": [
    {
      "name": "consul",
      "tags": ["infrastructure", "service-discovery"],
      "port": 8500,
      "check": {
        "http": "http://localhost:8500/v1/status/leader",
        "interval": "10s"
      }
    }
  ]
}
EOF

    # Nomad configuration
    cat > config/nomad/nomad.hcl << 'EOF'
datacenter = "dc1"
data_dir = "/nomad/data"
log_level = "INFO"
bind_addr = "0.0.0.0"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
  servers = ["127.0.0.1:4647"]
  
  host_volume "docker-sock" {
    path = "/var/run/docker.sock"
    read_only = false
  }
}

consul {
  address = "consul-server:8500"
}

autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "10s"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
  enable_redundancy_zones = false
  disable_upgrade_migration = false
  enable_custom_upgrades = false
}

telemetry {
  collection_interval = "1s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}
EOF

    # HAProxy configuration
    cat > config/haproxy/haproxy.cfg << 'EOF'
global
    daemon
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    
    # SSL Configuration
    ssl-default-bind-ciphers ECDHE+AESGCM:ECDHE+CHACHA20:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option log-health-checks
    option forwardfor
    option http-server-close
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Statistics page
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

# Frontend for HTTP traffic
frontend http_frontend
    bind *:80
    redirect scheme https code 301 if !{ ssl_fc }

# Frontend for HTTPS traffic
frontend https_frontend
    bind *:443 ssl crt /etc/ssl/certs/
    
    # Security headers
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    http-response set-header X-Frame-Options "DENY"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-XSS-Protection "1; mode=block"
    
    # Load balancing rules
    use_backend api_servers if { path_beg /api }
    use_backend web_servers if { path_beg /app }
    default_backend web_servers

# Backend for API servers
backend api_servers
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    # Dynamic server registration via Consul
    server-template api 10 _api._tcp.service.consul:80 check resolvers consul resolve-prefer ipv4

# Backend for web servers
backend web_servers
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    # Dynamic server registration via Consul
    server-template web 10 _web._tcp.service.consul:80 check resolvers consul resolve-prefer ipv4

# Consul resolver
resolvers consul
    nameserver consul consul-server:8600
    accepted_payload_size 8192
    hold valid 5s
EOF

    # Prometheus configuration for scaling
    cat > config/prometheus/prometheus-scaling.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  # Consul service discovery
  - job_name: 'consul-services'
    consul_sd_configs:
      - server: 'consul-server:8500'
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job
      - source_labels: [__meta_consul_node]
        target_label: instance

  # Infrastructure components
  - job_name: 'infrastructure-scaling'
    static_configs:
      - targets: 
        - 'auto-scaler:8080'
        - 'health-checker:3106'
        - 'traffic-manager:3107'
        - 'predictive-scaler:8080'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # System metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter-scaling:9100']

  # Container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  # HAProxy metrics
  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:8404']
    metrics_path: '/stats/prometheus'

  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: 
        - 'postgres-primary:5432'
        - 'postgres-replica1:5432'
        - 'postgres-replica2:5432'

  # Redis cluster metrics
  - job_name: 'redis-cluster'
    static_configs:
      - targets:
        - 'redis-cluster-1:7001'
        - 'redis-cluster-2:7002'
        - 'redis-cluster-3:7003'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    # Auto-scaler configuration
    cat > config/auto-scaler/config.yml << 'EOF'
scaling:
  enabled: true
  min_instances: 2
  max_instances: 20
  target_cpu_utilization: 70
  target_memory_utilization: 80
  scale_up_cooldown: 300
  scale_down_cooldown: 600
  
metrics:
  prometheus_url: "http://prometheus-scaling:9090"
  evaluation_interval: 30
  
predictive:
  enabled: true
  model_type: "linear_regression"
  prediction_horizon: 3600
  training_window: 86400
  confidence_threshold: 0.8
  
services:
  - name: "api-service"
    min_instances: 2
    max_instances: 10
    target_cpu: 70
    target_memory: 80
    
  - name: "web-service"
    min_instances: 1
    max_instances: 5
    target_cpu: 60
    target_memory: 70
    
  - name: "worker-service"
    min_instances: 1
    max_instances: 8
    target_cpu: 80
    target_memory: 85

consul:
  address: "consul-server:8500"
  
nomad:
  address: "nomad-server:4646"
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # Auto-scaler Dockerfile
    cat > docker/auto-scaler/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

EXPOSE 8080

CMD ["python", "src/main.py"]
EOF

    cat > docker/auto-scaler/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
prometheus-client==0.19.0
requests==2.31.0
pyyaml==6.0.1
numpy==1.24.3
scikit-learn==1.3.0
pandas==2.0.3
consul==1.1.0
python-nomad==1.4.1
schedule==1.2.0
asyncio==3.4.3
aiohttp==3.9.1
EOF

    # Health Checker Dockerfile
    cat > docker/health-checker/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

EXPOSE 3106

CMD ["node", "src/index.js"]
EOF

    cat > docker/health-checker/package.json << 'EOF'
{
  "name": "health-checker",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "consul": "^0.40.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "node-cron": "^3.0.3"
  }
}
EOF

    # NGINX Edge Dockerfile
    cat > docker/nginx-edge/Dockerfile << 'EOF'
FROM nginx:alpine

# Install additional modules
RUN apk add --no-cache nginx-mod-http-geoip2

# Copy configuration
COPY nginx-edge.conf /etc/nginx/nginx.conf
COPY edge-sites/ /etc/nginx/sites-enabled/

# Create cache directories
RUN mkdir -p /var/cache/nginx/edge && \
    chown -R nginx:nginx /var/cache/nginx

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
EOF

    log "Docker images configuration created"
}

# Create scaling services
create_scaling_services() {
    log "Creating scaling services..."
    
    # Auto-scaler main application
    mkdir -p docker/auto-scaler/src
    cat > docker/auto-scaler/src/main.py << 'EOF'
import asyncio
import logging
import yaml
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import uvicorn
from auto_scaler import AutoScaler
from predictive_scaler import PredictiveScaler
from metrics_collector import MetricsCollector

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load configuration
with open('config/config.yml', 'r') as f:
    config = yaml.safe_load(f)

# Initialize FastAPI app
app = FastAPI(title="Infrastructure Auto-Scaler", version="1.0.0")

# Prometheus metrics
scaling_operations = Counter('scaling_operations_total', 'Total scaling operations', ['service', 'direction'])
scaling_duration = Histogram('scaling_duration_seconds', 'Time spent on scaling operations', ['service'])
current_instances = Gauge('current_instances', 'Current number of instances', ['service'])
target_instances = Gauge('target_instances', 'Target number of instances', ['service'])
cpu_utilization = Gauge('cpu_utilization_percent', 'CPU utilization percentage', ['service'])
memory_utilization = Gauge('memory_utilization_percent', 'Memory utilization percentage', ['service'])

# Initialize components
auto_scaler = AutoScaler(config)
predictive_scaler = PredictiveScaler(config) if config['predictive']['enabled'] else None
metrics_collector = MetricsCollector(config)

@app.on_startup
async def startup_event():
    """Initialize scaling services on startup"""
    logger.info("Starting Infrastructure Auto-Scaler")
    
    # Start background tasks
    asyncio.create_task(scaling_loop())
    asyncio.create_task(metrics_collection_loop())
    
    if predictive_scaler:
        asyncio.create_task(predictive_scaling_loop())

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": asyncio.get_event_loop().time()}

@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.get("/scaling/status")
async def get_scaling_status():
    """Get current scaling status"""
    try:
        status = await auto_scaler.get_status()
        return status
    except Exception as e:
        logger.error(f"Error getting scaling status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/scaling/trigger/{service_name}")
async def trigger_scaling(service_name: str, target_instances: int):
    """Manually trigger scaling for a service"""
    try:
        result = await auto_scaler.scale_service(service_name, target_instances)
        scaling_operations.labels(service=service_name, direction='manual').inc()
        return result
    except Exception as e:
        logger.error(f"Error triggering scaling for {service_name}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/predictions/{service_name}")
async def get_predictions(service_name: str):
    """Get scaling predictions for a service"""
    if not predictive_scaler:
        raise HTTPException(status_code=404, detail="Predictive scaling not enabled")
    
    try:
        predictions = await predictive_scaler.get_predictions(service_name)
        return predictions
    except Exception as e:
        logger.error(f"Error getting predictions for {service_name}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def scaling_loop():
    """Main scaling loop"""
    while True:
        try:
            await auto_scaler.evaluate_and_scale()
            await asyncio.sleep(config['scaling']['evaluation_interval'])
        except Exception as e:
            logger.error(f"Error in scaling loop: {e}")
            await asyncio.sleep(30)

async def metrics_collection_loop():
    """Metrics collection loop"""
    while True:
        try:
            metrics = await metrics_collector.collect_all_metrics()
            
            # Update Prometheus metrics
            for service, data in metrics.items():
                current_instances.labels(service=service).set(data.get('current_instances', 0))
                target_instances.labels(service=service).set(data.get('target_instances', 0))
                cpu_utilization.labels(service=service).set(data.get('cpu_utilization', 0))
                memory_utilization.labels(service=service).set(data.get('memory_utilization', 0))
            
            await asyncio.sleep(30)
        except Exception as e:
            logger.error(f"Error in metrics collection: {e}")
            await asyncio.sleep(30)

async def predictive_scaling_loop():
    """Predictive scaling loop"""
    if not predictive_scaler:
        return
        
    while True:
        try:
            await predictive_scaler.train_models()
            await predictive_scaler.generate_predictions()
            await asyncio.sleep(3600)  # Run every hour
        except Exception as e:
            logger.error(f"Error in predictive scaling: {e}")
            await asyncio.sleep(300)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    log "Scaling services created"
}

# Start services
start_services() {
    log "Starting Infrastructure Scaling services..."
    
    # Pull required images
    docker-compose -f docker-compose.infrastructure-scaling.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.infrastructure-scaling.yml build
    
    # Start services in stages
    log "Starting core infrastructure services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d consul-server
    sleep 30
    
    log "Starting orchestration services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d nomad-server
    sleep 20
    
    log "Starting database services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d postgres-primary postgres-replica1 postgres-replica2 pgpool
    sleep 30
    
    log "Starting cache services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d redis-cluster-1 redis-cluster-2 redis-cluster-3
    sleep 20
    
    log "Starting load balancing services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d haproxy keepalived-master
    sleep 20
    
    log "Starting monitoring services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d prometheus-scaling grafana-scaling node-exporter-scaling cadvisor
    sleep 30
    
    log "Starting scaling services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d auto-scaler predictive-scaler health-checker
    sleep 20
    
    log "Starting edge services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d edge-cache nginx-edge
    sleep 20
    
    log "Starting remaining services..."
    docker-compose -f docker-compose.infrastructure-scaling.yml up -d dr-manager traffic-manager
    
    log "Waiting for services to be ready..."
    sleep 60
    
    # Health checks
    check_service_health "Consul" "http://localhost:8500/v1/status/leader"
    check_service_health "Nomad" "http://localhost:4646/v1/status/leader"
    check_service_health "HAProxy Stats" "http://localhost:8404/stats"
    check_service_health "Prometheus" "http://localhost:9094/-/healthy"
    check_service_health "Grafana" "http://localhost:3105"
    check_service_health "Health Checker" "http://localhost:3106/health"
    
    log "All services are running successfully!"
}

# Health check function
check_service_health() {
    local service_name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            log "$service_name is healthy"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            warn "$service_name health check failed after $max_attempts attempts"
            return 1
        fi
        
        sleep 10
        ((attempt++))
    done
}

# Display access information
show_access_info() {
    log "Infrastructure Scaling System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Consul UI:${NC} http://localhost:8500"
    echo -e "${GREEN}Nomad UI:${NC} http://localhost:4646"
    echo -e "${GREEN}HAProxy Stats:${NC} http://localhost:8404/stats"
    echo -e "${GREEN}Prometheus:${NC} http://localhost:9094"
    echo -e "${GREEN}Grafana:${NC} http://localhost:3105 (admin/admin)"
    echo -e "${GREEN}Health Checker:${NC} http://localhost:3106"
    echo -e "${GREEN}Traffic Manager:${NC} http://localhost:3107"
    echo -e "${GREEN}Edge Cache:${NC} http://localhost:8081"
    echo -e "${GREEN}NGINX Edge:${NC} http://localhost:8082"
    echo -e "${GREEN}cAdvisor:${NC} http://localhost:8080"
    echo
    echo -e "${BLUE}=== DATABASE CONNECTIONS ===${NC}"
    echo "Primary DB: postgresql://postgres:postgres_password@localhost:5434/nexus_db"
    echo "Replica 1: postgresql://postgres:postgres_password@localhost:5435/nexus_db"
    echo "Replica 2: postgresql://postgres:postgres_password@localhost:5436/nexus_db"
    echo "PgPool (Load Balanced): postgresql://postgres:postgres_password@localhost:5433/nexus_db"
    echo
    echo -e "${BLUE}=== REDIS CLUSTER ===${NC}"
    echo "Redis Cluster Node 1: localhost:7001"
    echo "Redis Cluster Node 2: localhost:7002"
    echo "Redis Cluster Node 3: localhost:7003"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Monitor infrastructure in Grafana at http://localhost:3105"
    echo "2. View service discovery in Consul at http://localhost:8500"
    echo "3. Manage workloads in Nomad at http://localhost:4646"
    echo "4. Check load balancer stats at http://localhost:8404/stats"
    echo "5. Monitor auto-scaling at http://localhost:3106/health"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Infrastructure Scaling Setup..."
    
    check_prerequisites
    init_configs
    build_images
    create_scaling_services
    start_services
    show_access_info
    
    log "Infrastructure Scaling setup completed successfully!"
}

# Execute main function
main "$@"
