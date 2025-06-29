#!/bin/bash

# Enterprise Backend Performance Setup Script
# Comprehensive backend optimization with 100% FOSS technologies

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
    
    # Check available disk space (minimum 20GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 20971520 ]; then
        warn "Less than 20GB disk space available. Backend performance system may require more space."
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
    mkdir -p config/{postgres,redis,nginx,pgbouncer,grafana/{provisioning,dashboards},prometheus}
    mkdir -p docker/{backend-api,bull-dashboard,job-worker,nginx-lb,backend-monitor,query-analyzer,cache-warmer}
    mkdir -p sql
    mkdir -p ssl
    mkdir -p logs
    
    # PostgreSQL configuration
    cat > config/postgres/postgresql.conf << 'EOF'
# PostgreSQL Performance Configuration

# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 200
superuser_reserved_connections = 3

# Memory Settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
dynamic_shared_memory_type = posix

# Checkpoint Settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200

# Write Ahead Log
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
hot_standby = on
hot_standby_feedback = on

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_error_verbosity = default

# Autovacuum
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.2
autovacuum_analyze_scale_factor = 0.1
autovacuum_freeze_max_age = 200000000
autovacuum_multixact_freeze_max_age = 400000000
autovacuum_vacuum_cost_delay = 20ms
autovacuum_vacuum_cost_limit = 200

# Client Connection Defaults
timezone = 'UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'
EOF

    # PostgreSQL HBA configuration
    cat > config/postgres/pg_hba.conf << 'EOF'
# PostgreSQL Client Authentication Configuration

# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    replication     replicator      0.0.0.0/0               md5
EOF

    # Redis Master configuration
    cat > config/redis/redis-master.conf << 'EOF'
# Redis Master Configuration
bind 0.0.0.0
port 6379
timeout 0
keepalive 60

# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Persistence
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Replication
# masterauth password
# requirepass password

# Logging
loglevel notice
logfile ""

# Performance
tcp-keepalive 300
tcp-backlog 511
databases 16
EOF

    # Redis Slave configuration
    cat > config/redis/redis-slave.conf << 'EOF'
# Redis Slave Configuration
bind 0.0.0.0
port 6379
timeout 0
keepalive 60

# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Replication
replicaof redis-master 6379
replica-read-only yes
replica-serve-stale-data yes

# Persistence
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Logging
loglevel notice
logfile ""
EOF

    # Redis Sentinel configuration
    cat > config/redis/sentinel.conf << 'EOF'
# Redis Sentinel Configuration
bind 0.0.0.0
port 26379

# Monitor master
sentinel monitor mymaster redis-master 6379 2
sentinel down-after-milliseconds mymaster 30000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 180000

# Logging
logfile ""
EOF

    # Redis Queue configuration
    cat > config/redis/redis-queue.conf << 'EOF'
# Redis Queue Configuration
bind 0.0.0.0
port 6379
timeout 0
keepalive 60

# Memory management
maxmemory 1gb
maxmemory-policy noeviction

# Persistence
appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Logging
loglevel notice
logfile ""
EOF

    # PgBouncer configuration
    cat > config/pgbouncer/pgbouncer.ini << 'EOF'
[databases]
nexus_db = host=postgres-primary port=5432 dbname=nexus_db

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
admin_users = nexus_user
pool_mode = transaction
server_reset_query = DISCARD ALL
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 10
reserve_pool_size = 5
server_lifetime = 3600
server_idle_timeout = 600
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
EOF

    cat > config/pgbouncer/userlist.txt << 'EOF'
"nexus_user" "SCRAM-SHA-256$4096:salt$hash:serverkey"
EOF

    # NGINX Load Balancer configuration
    cat > config/nginx/nginx-lb.conf << 'EOF'
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
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';
    
    access_log /var/log/nginx/access.log main;

    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
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
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    # Upstream backend servers
    upstream backend_api {
        least_conn;
        server backend-api:3100 max_fails=3 fail_timeout=30s;
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

        # API endpoints
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://backend_api;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            # Timeouts
            proxy_connect_timeout 5s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            # Buffer settings
            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
        }

        # Authentication endpoints with stricter rate limiting
        location /api/auth/ {
            limit_req zone=login burst=5 nodelay;
            
            proxy_pass http://backend_api;
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

        # Status page
        location /nginx_status {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            allow 10.0.0.0/8;
            allow 172.16.0.0/12;
            allow 192.168.0.0/16;
            deny all;
        }
    }
}
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # Backend API Dockerfile
    cat > docker/backend-api/Dockerfile << 'EOF'
FROM node:18-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --only=production

# Build the source code
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Production image
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY --from=builder /app/package.json ./package.json

USER nextjs

EXPOSE 3100

ENV PORT 3100
ENV HOSTNAME "0.0.0.0"

CMD ["node", "src/index.js"]
EOF

    # Backend API package.json
    cat > docker/backend-api/package.json << 'EOF'
{
  "name": "backend-api-optimized",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "compression": "^1.7.4",
    "express-rate-limit": "^7.1.0",
    "express-slow-down": "^2.0.1",
    "pg": "^8.11.0",
    "redis": "^4.6.0",
    "ioredis": "^5.3.0",
    "bull": "^4.12.0",
    "jsonwebtoken": "^9.0.0",
    "bcryptjs": "^2.4.3",
    "joi": "^17.11.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "response-time": "^2.3.2",
    "express-status-monitor": "^1.3.4",
    "node-cache": "^5.1.2",
    "lru-cache": "^10.0.0"
  }
}
EOF

    log "Docker images configuration created"
}

# Create backend services
create_backend_services() {
    log "Creating backend services..."
    
    # Main backend API
    mkdir -p docker/backend-api/src/{controllers,services,middleware,models,utils,routes}
    
    cat > docker/backend-api/src/index.js << 'EOF'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const slowDown = require('express-slow-down');
const responseTime = require('response-time');
const monitor = require('express-status-monitor');
const winston = require('winston');
const client = require('prom-client');

// Import services
const DatabaseService = require('./services/DatabaseService');
const CacheService = require('./services/CacheService');
const QueueService = require('./services/QueueService');

// Import middleware
const authMiddleware = require('./middleware/auth');
const cacheMiddleware = require('./middleware/cache');
const metricsMiddleware = require('./middleware/metrics');

// Import routes
const apiRoutes = require('./routes/api');
const authRoutes = require('./routes/auth');

const app = express();
const port = process.env.PORT || 3100;

// Configure logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/backend-api.log' })
  ]
});

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// Initialize services
const dbService = new DatabaseService();
const cacheService = new CacheService();
const queueService = new QueueService();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
}));

// Performance middleware
app.use(compression());
app.use(responseTime());

// Status monitoring
app.use(monitor({
  title: 'Backend API Performance Monitor',
  path: '/status',
  spans: [
    { interval: 1, retention: 60 },
    { interval: 5, retention: 60 },
    { interval: 15, retention: 60 }
  ],
  chartVisibility: {
    cpu: true,
    mem: true,
    load: true,
    responseTime: true,
    rps: true,
    statusCodes: true
  },
  healthChecks: [
    {
      protocol: 'http',
      host: 'localhost',
      path: '/health',
      port: port
    }
  ]
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

const speedLimiter = slowDown({
  windowMs: 15 * 60 * 1000,
  delayAfter: 50,
  delayMs: 500,
  maxDelayMs: 20000,
});

app.use('/api/', limiter);
app.use('/api/', speedLimiter);

// CORS
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true,
  optionsSuccessStatus: 200
}));

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Metrics middleware
app.use(metricsMiddleware(httpRequestDuration, httpRequestsTotal));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api', authMiddleware, cacheMiddleware, apiRoutes);

// Health check
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    await dbService.healthCheck();
    
    // Check Redis connection
    await cacheService.healthCheck();
    
    // Check queue connection
    await queueService.healthCheck();
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        database: 'healthy',
        cache: 'healthy',
        queue: 'healthy'
      }
    });
  } catch (error) {
    logger.error('Health check failed', { error: error.message });
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Error handling middleware
app.use((error, req, res, next) => {
  logger.error('Unhandled error', {
    error: error.message,
    stack: error.stack,
    url: req.url,
    method: req.method
  });
  
  res.status(500).json({
    error: 'Internal server error',
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    timestamp: new Date().toISOString()
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down gracefully');
  
  // Close database connections
  await dbService.close();
  
  // Close Redis connections
  await cacheService.close();
  
  // Close queue connections
  await queueService.close();
  
  process.exit(0);
});

// Start server
app.listen(port, '0.0.0.0', () => {
  logger.info(`Backend API listening on port ${port}`);
});

module.exports = app;
EOF

    log "Backend services created"
}

# Start services
start_services() {
    log "Starting Backend Performance services..."
    
    # Pull required images
    docker-compose -f docker-compose.backend-performance.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.backend-performance.yml build
    
    # Start services
    docker-compose -f docker-compose.backend-performance.yml up -d
    
    log "Waiting for services to be ready..."
    sleep 60
    
    # Health checks
    check_service_health "PostgreSQL Primary" "postgresql://nexus_user:nexus_password@localhost:5432/nexus_db"
    check_service_health "Redis Master" "redis://localhost:6379"
    check_service_health "Backend API" "http://localhost:3100/health"
    check_service_health "NGINX Load Balancer" "http://localhost:8090/health"
    check_service_health "PgBouncer" "postgresql://nexus_user:nexus_password@localhost:6432/nexus_db"
    check_service_health "Backend Grafana" "http://localhost:3104"
    check_service_health "Backend Prometheus" "http://localhost:9093"
    
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
            if pg_isready -d "$url" > /dev/null 2>&1; then
                log "$service_name is healthy"
                return 0
            fi
        elif [[ $url == redis* ]]; then
            if redis-cli -u "$url" ping > /dev/null 2>&1; then
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
    log "Backend Performance System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Backend API:${NC} http://localhost:3100"
    echo -e "${GREEN}NGINX Load Balancer:${NC} http://localhost:8090"
    echo -e "${GREEN}Bull Queue Dashboard:${NC} http://localhost:3101"
    echo -e "${GREEN}Backend Monitor:${NC} http://localhost:3102"
    echo -e "${GREEN}Query Analyzer:${NC} http://localhost:3103"
    echo -e "${GREEN}Backend Grafana:${NC} http://localhost:3104 (admin/admin)"
    echo -e "${GREEN}Backend Prometheus:${NC} http://localhost:9093"
    echo -e "${GREEN}PostgreSQL Primary:${NC} localhost:5432"
    echo -e "${GREEN}PostgreSQL Replica:${NC} localhost:5433"
    echo -e "${GREEN}PgBouncer:${NC} localhost:6432"
    echo -e "${GREEN}Redis Master:${NC} localhost:6379"
    echo -e "${GREEN}Redis Queue:${NC} localhost:6381"
    echo
    echo -e "${BLUE}=== DATABASE CONNECTIONS ===${NC}"
    echo "Primary DB: postgresql://nexus_user:nexus_password@localhost:5432/nexus_db"
    echo "Replica DB: postgresql://nexus_user:nexus_password@localhost:5433/nexus_db"
    echo "PgBouncer: postgresql://nexus_user:nexus_password@localhost:6432/nexus_db"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Access optimized API at http://localhost:8090/api"
    echo "2. Monitor performance in Grafana at http://localhost:3104"
    echo "3. View queue jobs at http://localhost:3101"
    echo "4. Analyze queries at http://localhost:3103"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Backend Performance Setup..."
    
    check_prerequisites
    init_configs
    build_images
    create_backend_services
    start_services
    show_access_info
    
    log "Backend Performance setup completed successfully!"
}

# Execute main function
main "$@"
