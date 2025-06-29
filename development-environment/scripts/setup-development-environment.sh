#!/bin/bash

# Enterprise Development Environment Setup Script
# Comprehensive development environment with 100% FOSS technologies

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
    
    # Check VS Code (optional)
    if ! command -v code &> /dev/null; then
        warn "VS Code is not installed. Dev containers will use browser-based editor."
    fi
    
    # Check available disk space (minimum 25GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 26214400 ]; then
        warn "Less than 25GB disk space available. Development environment may require more space."
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
    mkdir -p config/{postgres,redis,nginx,prometheus,grafana/{dev-provisioning,dev-dashboards},hmr,debug,profiling,seeder,watcher,mocks,dashboard}
    mkdir -p docker/{hmr-server,debug-server,profiling-server,data-seeder,file-watcher,mock-server,dev-dashboard}
    mkdir -p devcontainers/{.devcontainer,features}
    mkdir -p vscode/{settings,extensions}
    mkdir -p data/{sample-data,mock-responses,fixtures}
    mkdir -p ssl
    mkdir -p logs
    
    # Development PostgreSQL configuration
    cat > config/postgres/dev-postgresql.conf << 'EOF'
# Development PostgreSQL Configuration

# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory Settings (optimized for development)
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 2MB
maintenance_work_mem = 32MB

# Logging (verbose for development)
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_duration_statement = 100
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'all'
log_connections = on
log_disconnections = on

# Development optimizations
fsync = off
synchronous_commit = off
full_page_writes = off
checkpoint_segments = 32
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# Query planner
random_page_cost = 1.1
effective_io_concurrency = 200
EOF

    # Development Redis configuration
    cat > config/redis/dev-redis.conf << 'EOF'
# Development Redis Configuration
bind 0.0.0.0
port 6379
timeout 0
keepalive 60

# Memory management (development)
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistence (disabled for development speed)
save ""
appendonly no

# Logging
loglevel debug
logfile ""

# Development optimizations
tcp-keepalive 300
databases 16
EOF

    # Development NGINX configuration
    cat > config/nginx/dev-nginx.conf << 'EOF'
user nginx;
worker_processes 1;
error_log /var/log/nginx/error.log debug;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    # Development optimizations
    sendfile off;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    # Upstream for HMR server
    upstream hmr_backend {
        server hmr-server:3400;
    }

    # HTTP server
    server {
        listen 80;
        server_name localhost;

        # Proxy to HMR server
        location / {
            proxy_pass http://hmr_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            # HMR WebSocket support
            proxy_read_timeout 86400;
        }

        # WebSocket for HMR
        location /sockjs-node {
            proxy_pass http://hmr_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
        }
    }

    # HTTPS server with self-signed certificate
    server {
        listen 443 ssl;
        server_name localhost;

        ssl_certificate /etc/nginx/ssl/dev-cert.pem;
        ssl_certificate_key /etc/nginx/ssl/dev-key.pem;

        location / {
            proxy_pass http://hmr_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }
    }
}
EOF

    # Dev Container configuration
    cat > devcontainers/.devcontainer/devcontainer.json << 'EOF'
{
  "name": "Nexus V3 Development Environment",
  "dockerComposeFile": [
    "../../docker-compose.development-environment.yml"
  ],
  "service": "code-server",
  "workspaceFolder": "/home/coder/workspace",
  "shutdownAction": "stopCompose",
  
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "18"
    },
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-vscode.vscode-typescript-next",
        "bradlc.vscode-tailwindcss",
        "esbenp.prettier-vscode",
        "dbaeumer.vscode-eslint",
        "ms-vscode.vscode-json",
        "GraphQL.vscode-graphql",
        "ms-vscode.vscode-docker",
        "ms-vscode-remote.remote-containers",
        "ms-vscode.vscode-jest",
        "Orta.vscode-jest",
        "ms-playwright.playwright",
        "ms-vscode.vscode-chrome-debug",
        "msjsdiag.vscode-react-native"
      ],
      "settings": {
        "typescript.preferences.includePackageJsonAutoImports": "auto",
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
          "source.fixAll.eslint": true
        },
        "eslint.workingDirectories": ["apps", "packages"],
        "typescript.enablePromptUseWorkspaceTsdk": true,
        "debug.node.autoAttach": "on"
      }
    }
  },
  
  "forwardPorts": [
    3400,  // HMR Server
    3080,  // Dev Proxy HTTP
    3443,  // Dev Proxy HTTPS
    9229,  // Node.js Debugger
    3401,  // Debug Dashboard
    3402,  // Profiling Server
    3404,  // Dev Dashboard
    5440,  // Dev PostgreSQL
    6390,  // Dev Redis
    9200,  // Elasticsearch
    5601,  // Kibana
    16686, // Jaeger
    8025,  // MailHog
    9000,  // MinIO
    3309   // Dev Grafana
  ],
  
  "postCreateCommand": "npm install && npm run prepare",
  "postStartCommand": "npm run dev:setup",
  
  "remoteUser": "coder",
  "containerUser": "coder"
}
EOF

    # VS Code settings for development
    cat > vscode/settings.json << 'EOF'
{
  "typescript.preferences.includePackageJsonAutoImports": "auto",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true,
    "source.organizeImports": true
  },
  "eslint.workingDirectories": ["apps", "packages"],
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "debug.node.autoAttach": "on",
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/dist/**": true,
    "**/build/**": true,
    "**/.next/**": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true,
    "**/.next": true
  },
  "emmet.includeLanguages": {
    "javascript": "javascriptreact",
    "typescript": "typescriptreact"
  },
  "tailwindCSS.includeLanguages": {
    "javascript": "javascript",
    "html": "HTML"
  },
  "tailwindCSS.experimental.classRegex": [
    "tw`([^`]*)",
    "tw=\"([^\"]*)",
    "tw={\"([^\"}]*)",
    "tw\\.\\w+`([^`]*)",
    "tw\\(.*?\\)`([^`]*)"
  ]
}
EOF

    # Prometheus configuration for development
    cat > config/prometheus/dev-prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Development services
  - job_name: 'development-services'
    static_configs:
      - targets:
        - 'hmr-server:3400'
        - 'debug-server:3401'
        - 'profiling-server:3402'
        - 'dev-dashboard:3404'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # PostgreSQL metrics
  - job_name: 'dev-postgres'
    static_configs:
      - targets: ['dev-postgres:5432']

  # Redis metrics
  - job_name: 'dev-redis'
    static_configs:
      - targets: ['dev-redis:6379']
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # HMR Server Dockerfile
    cat > docker/hmr-server/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /workspace

# Install development dependencies
RUN apk add --no-cache git python3 make g++

# Copy package files
COPY package.json package-lock.json ./
RUN npm ci

# Install HMR and development tools
RUN npm install -g nodemon concurrently webpack-dev-server

# Copy source code
COPY . .

EXPOSE 3400 24678

CMD ["npm", "run", "dev:hmr"]
EOF

    cat > docker/hmr-server/package.json << 'EOF'
{
  "name": "hmr-server",
  "version": "1.0.0",
  "scripts": {
    "dev:hmr": "concurrently \"webpack serve --mode development --hot\" \"nodemon --inspect=0.0.0.0:9229 server.js\"",
    "dev": "webpack serve --mode development --hot --host 0.0.0.0 --port 3400"
  },
  "dependencies": {
    "webpack": "^5.89.0",
    "webpack-cli": "^5.1.0",
    "webpack-dev-server": "^4.15.0",
    "webpack-hot-middleware": "^2.25.0",
    "react-hot-loader": "^4.13.0",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "chokidar": "^3.5.0",
    "ws": "^8.14.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.0",
    "concurrently": "^8.2.0"
  }
}
EOF

    # Debug Server Dockerfile
    cat > docker/debug-server/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /workspace

# Install debugging tools
RUN npm install -g node-inspector chrome-remote-interface

# Copy package files
COPY package.json package-lock.json ./
RUN npm ci

EXPOSE 9229 9230 3401

CMD ["node", "--inspect=0.0.0.0:9229", "debug-server.js"]
EOF

    cat > docker/debug-server/package.json << 'EOF'
{
  "name": "debug-server",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.0",
    "chrome-remote-interface": "^0.33.0",
    "source-map-support": "^0.5.0",
    "inspector": "^0.5.0"
  }
}
EOF

    log "Docker images configuration created"
}

# Generate SSL certificates for development
generate_ssl_certs() {
    log "Generating SSL certificates for development..."
    
    if [ ! -f ssl/dev-cert.pem ]; then
        # Generate self-signed certificate for development
        openssl req -x509 -newkey rsa:4096 -keyout ssl/dev-key.pem -out ssl/dev-cert.pem -days 365 -nodes -subj "/C=US/ST=Development/L=Local/O=Nexus-V3/CN=localhost"
        log "SSL certificates generated"
    else
        log "SSL certificates already exist"
    fi
}

# Setup sample data
setup_sample_data() {
    log "Setting up sample data..."
    
    cat > data/sample-data.sql << 'EOF'
-- Sample data for development environment

-- Insert sample users
INSERT INTO users (email, username, password_hash, first_name, last_name, is_active) VALUES
('admin@nexus-v3.local', 'admin', '$2a$10$hash', 'Admin', 'User', true),
('developer@nexus-v3.local', 'developer', '$2a$10$hash', 'John', 'Developer', true),
('tester@nexus-v3.local', 'tester', '$2a$10$hash', 'Jane', 'Tester', true),
('designer@nexus-v3.local', 'designer', '$2a$10$hash', 'Alice', 'Designer', true);

-- Insert sample posts
INSERT INTO posts (user_id, title, content, slug, status, published_at) 
SELECT 
    u.id,
    'Sample Post ' || generate_series(1, 50),
    'This is sample content for development and testing purposes. Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
    'sample-post-' || generate_series(1, 50),
    CASE WHEN random() > 0.3 THEN 'published' ELSE 'draft' END,
    NOW() - INTERVAL '1 day' * (random() * 30)
FROM users u
WHERE u.username = 'developer';

-- Insert sample tags
INSERT INTO tags (name, slug, description) VALUES
('Development', 'development', 'Development related content'),
('Testing', 'testing', 'Testing and QA content'),
('Design', 'design', 'UI/UX design content'),
('Performance', 'performance', 'Performance optimization content'),
('Security', 'security', 'Security best practices');
EOF

    cat > data/dev-fixtures.sql << 'EOF'
-- Development fixtures for testing

-- Create test data for performance testing
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO analytics_events (event_type, user_id, properties, created_at)
        VALUES (
            CASE (i % 5)
                WHEN 0 THEN 'page_view'
                WHEN 1 THEN 'button_click'
                WHEN 2 THEN 'form_submit'
                WHEN 3 THEN 'api_call'
                ELSE 'user_action'
            END,
            (SELECT id FROM users ORDER BY random() LIMIT 1),
            jsonb_build_object(
                'page', '/test-page-' || (i % 10),
                'timestamp', NOW() - INTERVAL '1 hour' * (random() * 24),
                'session_id', 'session-' || (i % 100)
            ),
            NOW() - INTERVAL '1 hour' * (random() * 24)
        );
    END LOOP;
END $$;
EOF

    log "Sample data configured"
}

# Start services
start_services() {
    log "Starting Development Environment services..."
    
    # Generate SSL certificates first
    generate_ssl_certs
    
    # Setup sample data
    setup_sample_data
    
    # Pull required images
    docker-compose -f docker-compose.development-environment.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.development-environment.yml build
    
    # Start services in stages
    log "Starting database services..."
    docker-compose -f docker-compose.development-environment.yml up -d dev-postgres dev-redis
    sleep 30
    
    log "Starting core development services..."
    docker-compose -f docker-compose.development-environment.yml up -d hmr-server debug-server profiling-server
    sleep 20
    
    log "Starting supporting services..."
    docker-compose -f docker-compose.development-environment.yml up -d dev-proxy data-seeder file-watcher mock-server
    sleep 20
    
    log "Starting development tools..."
    docker-compose -f docker-compose.development-environment.yml up -d code-server dev-dashboard
    sleep 20
    
    log "Starting monitoring services..."
    docker-compose -f docker-compose.development-environment.yml up -d dev-elasticsearch dev-kibana dev-jaeger dev-prometheus dev-grafana
    sleep 30
    
    log "Starting utility services..."
    docker-compose -f docker-compose.development-environment.yml up -d dev-mailhog dev-minio
    
    log "Waiting for services to be ready..."
    sleep 60
    
    # Health checks
    check_service_health "Development PostgreSQL" "postgresql://dev_user:dev_password@localhost:5440/nexus_dev"
    check_service_health "Development Redis" "redis://localhost:6390"
    check_service_health "HMR Server" "http://localhost:3400"
    check_service_health "Debug Server" "http://localhost:3401"
    check_service_health "Profiling Server" "http://localhost:3402"
    check_service_health "Dev Dashboard" "http://localhost:3404"
    check_service_health "Code Server" "http://localhost:8080"
    check_service_health "Dev Grafana" "http://localhost:3309"
    check_service_health "Kibana" "http://localhost:5601"
    check_service_health "Jaeger" "http://localhost:16686"
    check_service_health "MailHog" "http://localhost:8025"
    check_service_health "MinIO" "http://localhost:9001"
    
    log "All services are running successfully!"
}

# Health check function
check_service_health() {
    local service_name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [[ $url == postgresql* ]]; then
            if command -v pg_isready &> /dev/null && pg_isready -d "$url" > /dev/null 2>&1; then
                log "$service_name is healthy"
                return 0
            fi
        elif [[ $url == redis* ]]; then
            if command -v redis-cli &> /dev/null && redis-cli -u "$url" ping > /dev/null 2>&1; then
                log "$service_name is healthy"
                return 0
            fi
        else
            if curl -s -f "$url" > /dev/null 2>&1; then
                log "$service_name is healthy"
                return 0
            fi
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
    log "Development Environment is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Code Server (VS Code):${NC} http://localhost:8080 (password: dev-password)"
    echo -e "${GREEN}Development App (HTTP):${NC} http://localhost:3080"
    echo -e "${GREEN}Development App (HTTPS):${NC} https://localhost:3443"
    echo -e "${GREEN}HMR Server:${NC} http://localhost:3400"
    echo -e "${GREEN}Debug Server:${NC} http://localhost:3401"
    echo -e "${GREEN}Profiling Server:${NC} http://localhost:3402"
    echo -e "${GREEN}Mock API Server:${NC} http://localhost:3403"
    echo -e "${GREEN}Dev Dashboard:${NC} http://localhost:3404"
    echo
    echo -e "${BLUE}=== DEVELOPMENT TOOLS ===${NC}"
    echo -e "${GREEN}Kibana (Logs):${NC} http://localhost:5601"
    echo -e "${GREEN}Jaeger (Tracing):${NC} http://localhost:16686"
    echo -e "${GREEN}MailHog (Email):${NC} http://localhost:8025"
    echo -e "${GREEN}MinIO (S3):${NC} http://localhost:9001 (dev-access-key/dev-secret-key)"
    echo -e "${GREEN}Dev Grafana:${NC} http://localhost:3309 (admin/dev-password)"
    echo -e "${GREEN}Dev Prometheus:${NC} http://localhost:9097"
    echo
    echo -e "${BLUE}=== DATABASE CONNECTIONS ===${NC}"
    echo "PostgreSQL: postgresql://dev_user:dev_password@localhost:5440/nexus_dev"
    echo "Redis: redis://localhost:6390"
    echo "Elasticsearch: http://localhost:9200"
    echo
    echo -e "${BLUE}=== DEBUGGING ===${NC}"
    echo "Node.js Debugger: localhost:9229"
    echo "Chrome DevTools: localhost:9230"
    echo "Chrome DevTools Protocol: localhost:9222"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Open VS Code in browser at http://localhost:8080"
    echo "2. Start development with hot reload at http://localhost:3080"
    echo "3. Debug your application at http://localhost:3401"
    echo "4. Profile performance at http://localhost:3402"
    echo "5. View logs in Kibana at http://localhost:5601"
    echo "6. Monitor with Grafana at http://localhost:3309"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Development Environment Setup..."
    
    check_prerequisites
    init_configs
    build_images
    start_services
    show_access_info
    
    log "Development Environment setup completed successfully!"
}

# Execute main function
main "$@"
