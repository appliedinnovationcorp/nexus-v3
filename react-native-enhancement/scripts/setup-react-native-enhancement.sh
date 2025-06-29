#!/bin/bash

# Enterprise React Native Enhancement Setup Script
# Comprehensive mobile enhancement with 100% FOSS technologies

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
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js first."
    fi
    
    # Check React Native CLI (optional)
    if ! command -v npx &> /dev/null; then
        warn "npx is not available. Some React Native features may be limited."
    fi
    
    # Check available disk space (minimum 30GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 31457280 ]; then
        warn "Less than 30GB disk space available. React Native enhancement may require more space."
    fi
    
    # Check available memory (minimum 16GB recommended)
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_memory" -lt 16384 ]; then
        warn "Less than 16GB RAM available. Performance may be impacted."
    fi
    
    log "Prerequisites check completed"
}

# Initialize configuration files
init_configs() {
    log "Initializing configuration files..."
    
    # Create directory structure
    mkdir -p config/{redis,nginx,prometheus,grafana/{provisioning,dashboards},codepush,push-notifications,offline-sync,deep-linking,performance,auth,build}
    mkdir -p docker/{codepush-server,push-notification-server,offline-sync-server,deep-linking-service,rn-performance-monitor,auth-service,rn-build-server}
    mkdir -p sql
    mkdir -p ssl
    mkdir -p logs
    
    # CodePush Redis configuration
    cat > config/redis/codepush-redis.conf << 'EOF'
# Redis configuration for CodePush
bind 0.0.0.0
port 6379
timeout 0
keepalive 60
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes
dbfilename codepush-dump.rdb
dir /data
EOF

    # NGINX configuration for React Native services
    cat > config/nginx/rn-nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    # Upstream services
    upstream codepush_backend {
        server codepush-server:3000;
        keepalive 32;
    }

    upstream push_backend {
        server push-notification-server:3001;
        keepalive 32;
    }

    upstream sync_backend {
        server offline-sync-server:3002;
        keepalive 32;
    }

    upstream linking_backend {
        server deep-linking-service:3003;
        keepalive 32;
    }

    upstream perf_backend {
        server rn-performance-monitor:3004;
        keepalive 32;
    }

    upstream auth_backend {
        server auth-service:3005;
        keepalive 32;
    }

    server {
        listen 80;
        server_name localhost;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # CodePush API
        location /codepush/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://codepush_backend/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }

        # Push Notifications API
        location /push/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://push_backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Offline Sync API
        location /sync/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://sync_backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Deep Linking API
        location /link/ {
            proxy_pass http://linking_backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Performance Monitoring API
        location /perf/ {
            proxy_pass http://perf_backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Authentication API
        location /auth/ {
            limit_req zone=api burst=10 nodelay;
            
            proxy_pass http://auth_backend/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Health check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    # Prometheus configuration for React Native
    cat > config/prometheus/prometheus-rn.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  # React Native services
  - job_name: 'react-native-services'
    static_configs:
      - targets:
        - 'codepush-server:3000'
        - 'push-notification-server:3001'
        - 'offline-sync-server:3002'
        - 'deep-linking-service:3003'
        - 'rn-performance-monitor:3004'
        - 'auth-service:3005'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Mobile app metrics (when available)
  - job_name: 'mobile-apps'
    static_configs:
      - targets: []
    metrics_path: '/metrics'
    scrape_interval: 60s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # CodePush Server Dockerfile
    cat > docker/codepush-server/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

# Create storage directory
RUN mkdir -p /app/storage && chown -R node:node /app/storage

USER node

EXPOSE 3000

CMD ["node", "src/index.js"]
EOF

    cat > docker/codepush-server/package.json << 'EOF'
{
  "name": "codepush-server",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "compression": "^1.7.4",
    "multer": "^1.4.5",
    "pg": "^8.11.0",
    "redis": "^4.6.0",
    "jsonwebtoken": "^9.0.0",
    "bcryptjs": "^2.4.3",
    "joi": "^17.11.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "semver": "^7.5.0",
    "archiver": "^6.0.0",
    "unzipper": "^0.10.0",
    "crypto": "^1.0.1"
  }
}
EOF

    # Push Notification Server Dockerfile
    cat > docker/push-notification-server/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

USER node

EXPOSE 3001

CMD ["node", "src/index.js"]
EOF

    cat > docker/push-notification-server/package.json << 'EOF'
{
  "name": "push-notification-server",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "pg": "^8.11.0",
    "redis": "^4.6.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "firebase-admin": "^11.11.0",
    "apn": "^2.2.0",
    "node-cron": "^3.0.3",
    "bull": "^4.12.0"
  }
}
EOF

    log "Docker images configuration created"
}

# Start services
start_services() {
    log "Starting React Native Enhancement services..."
    
    # Pull required images
    docker-compose -f docker-compose.react-native-enhancement.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.react-native-enhancement.yml build
    
    # Start services in stages
    log "Starting database services..."
    docker-compose -f docker-compose.react-native-enhancement.yml up -d codepush-postgres push-postgres sync-postgres link-postgres perf-postgres auth-postgres
    sleep 30
    
    log "Starting cache services..."
    docker-compose -f docker-compose.react-native-enhancement.yml up -d codepush-redis push-redis sync-redis link-redis perf-redis auth-redis
    sleep 20
    
    log "Starting core services..."
    docker-compose -f docker-compose.react-native-enhancement.yml up -d codepush-server push-notification-server offline-sync-server deep-linking-service rn-performance-monitor auth-service
    sleep 30
    
    log "Starting monitoring services..."
    docker-compose -f docker-compose.react-native-enhancement.yml up -d rn-prometheus rn-grafana
    sleep 20
    
    log "Starting remaining services..."
    docker-compose -f docker-compose.react-native-enhancement.yml up -d rn-build-server rn-nginx
    
    log "Waiting for services to be ready..."
    sleep 60
    
    # Health checks
    check_service_health "CodePush Server" "http://localhost:3200/health"
    check_service_health "Push Notification Server" "http://localhost:3201/health"
    check_service_health "Offline Sync Server" "http://localhost:3202/health"
    check_service_health "Deep Linking Service" "http://localhost:3203/health"
    check_service_health "Performance Monitor" "http://localhost:3204/health"
    check_service_health "Auth Service" "http://localhost:3205/health"
    check_service_health "RN Prometheus" "http://localhost:9095/-/healthy"
    check_service_health "RN Grafana" "http://localhost:3207"
    check_service_health "RN NGINX" "http://localhost:8083/health"
    
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
    log "React Native Enhancement System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}NGINX Gateway:${NC} http://localhost:8083"
    echo -e "${GREEN}CodePush Server:${NC} http://localhost:3200"
    echo -e "${GREEN}Push Notification Server:${NC} http://localhost:3201"
    echo -e "${GREEN}Offline Sync Server:${NC} http://localhost:3202"
    echo -e "${GREEN}Deep Linking Service:${NC} http://localhost:3203"
    echo -e "${GREEN}Performance Monitor:${NC} http://localhost:3204"
    echo -e "${GREEN}Auth Service:${NC} http://localhost:3205"
    echo -e "${GREEN}Build Server:${NC} http://localhost:3206"
    echo -e "${GREEN}RN Grafana:${NC} http://localhost:3207 (admin/admin)"
    echo -e "${GREEN}RN Prometheus:${NC} http://localhost:9095"
    echo
    echo -e "${BLUE}=== API ENDPOINTS ===${NC}"
    echo "CodePush API: http://localhost:8083/codepush/"
    echo "Push Notifications: http://localhost:8083/push/"
    echo "Offline Sync: http://localhost:8083/sync/"
    echo "Deep Linking: http://localhost:8083/link/"
    echo "Performance: http://localhost:8083/perf/"
    echo "Authentication: http://localhost:8083/auth/"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Configure your React Native app with the CodePush SDK"
    echo "2. Set up push notifications with FCM/APNS credentials"
    echo "3. Implement offline-first architecture with sync capabilities"
    echo "4. Configure deep linking and universal links"
    echo "5. Monitor performance in Grafana at http://localhost:3207"
    echo
}

# Main execution
main() {
    log "Starting Enterprise React Native Enhancement Setup..."
    
    check_prerequisites
    init_configs
    build_images
    start_services
    show_access_info
    
    log "React Native Enhancement setup completed successfully!"
}

# Execute main function
main "$@"
