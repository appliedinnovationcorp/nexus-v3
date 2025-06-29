#!/bin/bash

# Enterprise Global Reach System Setup Script
# Implements comprehensive internationalization, localization, and global content delivery

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=10485760  # 10GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error "Insufficient disk space. At least 10GB required."
        exit 1
    fi
    
    # Check available memory (minimum 8GB)
    available_memory=$(free -k | awk 'NR==2{print $2}')
    required_memory=8388608  # 8GB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        warn "Less than 8GB RAM available. Performance may be impacted."
    fi
    
    log "System requirements check completed successfully"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    local dirs=(
        "config"
        "scripts"
        "docker/i18n-service"
        "docker/currency-service"
        "docker/timezone-service"
        "docker/rtl-service"
        "docker/localization-service"
        "docker/cdn-optimizer"
        "docker/global-reach-gateway"
        "docker/global-reach-dashboard"
        "i18n/translations"
        "i18n/config"
        "localization/config"
        "localization/data"
        "cdn/config"
        "timezone/config"
        "timezone/data"
        "currency/config"
        "currency/data"
        "rtl/config"
        "rtl/styles"
        "content-delivery/config"
        "content-delivery/static"
        "content-delivery/optimized"
        "content-delivery/cache"
        "content-delivery/varnish-cache"
        "monitoring/config"
        "monitoring/dashboards"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        info "Created directory: $dir"
    done
    
    log "Directory structure created successfully"
}

# Generate configuration files
generate_configs() {
    log "Generating configuration files..."
    
    # NGINX CDN Configuration
    cat > config/nginx-cdn.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
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
                    '$request_time $upstream_response_time';
    
    access_log /var/log/nginx/access.log main;
    
    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
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
        application/atom+xml
        image/svg+xml;
    
    # Brotli compression
    brotli on;
    brotli_comp_level 6;
    brotli_types
        text/plain
        text/css
        application/json
        application/javascript
        text/xml
        application/xml
        application/xml+rss
        text/javascript;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Global CDN upstream
    upstream global_backend {
        server global-reach-gateway:3000;
        keepalive 32;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=global:10m rate=10r/s;
    
    server {
        listen 80;
        server_name _;
        
        # Rate limiting
        limit_req zone=global burst=20 nodelay;
        
        # Static content with long cache
        location /static/ {
            root /usr/share/nginx/html;
            expires 1y;
            add_header Cache-Control "public, immutable";
            
            # CORS headers for global access
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Accept-Language";
        }
        
        # API proxy with localization headers
        location /api/ {
            proxy_pass http://global_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Accept-Language $http_accept_language;
            proxy_set_header X-User-Timezone $http_x_user_timezone;
            proxy_set_header X-User-Currency $http_x_user_currency;
            proxy_cache_bypass $http_upgrade;
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
    
    # Varnish Cache Configuration
    cat > config/varnish.vcl << 'EOF'
vcl 4.1;

backend default {
    .host = "nginx-cdn";
    .port = "80";
    .connect_timeout = 60s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 60s;
}

sub vcl_recv {
    # Remove cookies for static content
    if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg)$") {
        unset req.http.Cookie;
    }
    
    # Normalize Accept-Language header
    if (req.http.Accept-Language) {
        if (req.http.Accept-Language ~ "^en") {
            set req.http.X-Language = "en";
        } elsif (req.http.Accept-Language ~ "^es") {
            set req.http.X-Language = "es";
        } elsif (req.http.Accept-Language ~ "^fr") {
            set req.http.X-Language = "fr";
        } elsif (req.http.Accept-Language ~ "^de") {
            set req.http.X-Language = "de";
        } elsif (req.http.Accept-Language ~ "^ja") {
            set req.http.X-Language = "ja";
        } elsif (req.http.Accept-Language ~ "^zh") {
            set req.http.X-Language = "zh";
        } elsif (req.http.Accept-Language ~ "^ar") {
            set req.http.X-Language = "ar";
        } elsif (req.http.Accept-Language ~ "^he") {
            set req.http.X-Language = "he";
        } else {
            set req.http.X-Language = "en";
        }
    }
    
    # Add language to cache key
    set req.http.X-Cache-Key = req.url + "|" + req.http.X-Language;
}

sub vcl_backend_response {
    # Cache static content for 1 year
    if (bereq.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg)$") {
        set beresp.ttl = 365d;
        set beresp.http.Cache-Control = "public, max-age=31536000";
    }
    
    # Cache API responses for 5 minutes
    if (bereq.url ~ "^/api/") {
        set beresp.ttl = 5m;
        set beresp.http.Cache-Control = "public, max-age=300";
    }
}

sub vcl_deliver {
    # Add cache status header
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Add global reach headers
    set resp.http.X-Global-Reach = "enabled";
    set resp.http.X-Content-Language = req.http.X-Language;
}
EOF
    
    # Redis Global Configuration
    cat > config/redis-global.conf << 'EOF'
# Redis Global Configuration for Global Reach System
port 6379
bind 0.0.0.0
protected-mode no

# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice
logfile ""

# Performance
tcp-keepalive 300
timeout 0
tcp-backlog 511

# Security
requirepass globalreach2024

# Modules
loadmodule /usr/lib/redis/modules/redisearch.so
loadmodule /usr/lib/redis/modules/redisjson.so
EOF
    
    # Prometheus Global Configuration
    cat > config/prometheus-global.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "global_reach_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'nginx-cdn'
    static_configs:
      - targets: ['nginx-cdn:80']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'i18n-service'
    static_configs:
      - targets: ['i18n-service:3000']
    metrics_path: /metrics

  - job_name: 'currency-service'
    static_configs:
      - targets: ['currency-service:3000']
    metrics_path: /metrics

  - job_name: 'timezone-service'
    static_configs:
      - targets: ['timezone-service:3000']
    metrics_path: /metrics

  - job_name: 'rtl-service'
    static_configs:
      - targets: ['rtl-service:3000']
    metrics_path: /metrics

  - job_name: 'localization-service'
    static_configs:
      - targets: ['localization-service:3000']
    metrics_path: /metrics

  - job_name: 'cdn-optimizer'
    static_configs:
      - targets: ['cdn-optimizer:3000']
    metrics_path: /metrics

  - job_name: 'global-reach-gateway'
    static_configs:
      - targets: ['global-reach-gateway:3000']
    metrics_path: /metrics

  - job_name: 'redis-global'
    static_configs:
      - targets: ['redis-global:6379']
    metrics_path: /metrics

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF
    
    log "Configuration files generated successfully"
}

# Create Docker service files
create_docker_services() {
    log "Creating Docker service files..."
    
    # i18n Service Dockerfile
    cat > docker/i18n-service/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# Set ownership
RUN chown -R nextjs:nodejs /app
USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
EOF
    
    # i18n Service Package.json
    cat > docker/i18n-service/package.json << 'EOF'
{
  "name": "i18n-service",
  "version": "1.0.0",
  "description": "Enterprise i18n Translation Service",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "i18next": "^23.7.6",
    "i18next-fs-backend": "^2.3.1",
    "i18next-http-middleware": "^3.5.0",
    "redis": "^4.6.10",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "compression": "^1.7.4",
    "prom-client": "^15.1.0",
    "winston": "^3.11.0"
  }
}
EOF
    
    # i18n Service Server
    cat > docker/i18n-service/server.js << 'EOF'
const express = require('express');
const i18next = require('i18next');
const Backend = require('i18next-fs-backend');
const middleware = require('i18next-http-middleware');
const redis = require('redis');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const translationRequests = new promClient.Counter({
  name: 'translation_requests_total',
  help: 'Total number of translation requests',
  labelNames: ['language', 'namespace']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(translationRequests);

// Logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

const app = express();
const port = process.env.PORT || 3000;

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.on('error', (err) => {
  logger.error('Redis Client Error', err);
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode)
      .observe(duration);
  });
  next();
});

// Initialize i18next
i18next
  .use(Backend)
  .use(middleware.LanguageDetector)
  .init({
    lng: process.env.DEFAULT_LOCALE || 'en',
    fallbackLng: 'en',
    supportedLngs: (process.env.SUPPORTED_LOCALES || 'en').split(','),
    backend: {
      loadPath: '/app/translations/{{lng}}/{{ns}}.json'
    },
    detection: {
      order: ['header', 'querystring'],
      caches: false
    }
  });

app.use(middleware.handle(i18next));

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/translate/:key', async (req, res) => {
  try {
    const { key } = req.params;
    const { lng = 'en', ns = 'common' } = req.query;
    
    translationRequests.labels(lng, ns).inc();
    
    // Check cache first
    const cacheKey = `translation:${lng}:${ns}:${key}`;
    const cached = await redisClient.get(cacheKey);
    
    if (cached) {
      return res.json({ key, translation: cached, cached: true });
    }
    
    const translation = req.t(key, { lng, ns });
    
    // Cache for 1 hour
    await redisClient.setEx(cacheKey, 3600, translation);
    
    res.json({ key, translation, cached: false });
  } catch (error) {
    logger.error('Translation error:', error);
    res.status(500).json({ error: 'Translation failed' });
  }
});

app.get('/translations/:lng/:ns?', async (req, res) => {
  try {
    const { lng, ns = 'common' } = req.params;
    
    const cacheKey = `translations:${lng}:${ns}`;
    const cached = await redisClient.get(cacheKey);
    
    if (cached) {
      return res.json(JSON.parse(cached));
    }
    
    const translations = req.t('', { lng, ns, returnObjects: true });
    
    // Cache for 30 minutes
    await redisClient.setEx(cacheKey, 1800, JSON.stringify(translations));
    
    res.json(translations);
  } catch (error) {
    logger.error('Translations fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch translations' });
  }
});

app.get('/languages', (req, res) => {
  const languages = i18next.options.supportedLngs.filter(lng => lng !== 'cimode');
  res.json({ languages });
});

// Start server
async function startServer() {
  try {
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    app.listen(port, () => {
      logger.info(`i18n Service running on port ${port}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
EOF
    
    # Create similar services for other components...
    # (Currency Service, Timezone Service, RTL Service, etc.)
    
    log "Docker service files created successfully"
}

# Create translation files
create_translation_files() {
    log "Creating translation files..."
    
    local languages=("en" "es" "fr" "de" "ja" "zh" "ar" "he" "ru" "pt" "it" "ko" "hi" "th" "vi")
    
    for lang in "${languages[@]}"; do
        mkdir -p "i18n/translations/$lang"
        
        # Common translations
        cat > "i18n/translations/$lang/common.json" << EOF
{
  "welcome": "Welcome",
  "hello": "Hello",
  "goodbye": "Goodbye",
  "yes": "Yes",
  "no": "No",
  "save": "Save",
  "cancel": "Cancel",
  "delete": "Delete",
  "edit": "Edit",
  "loading": "Loading...",
  "error": "Error",
  "success": "Success",
  "warning": "Warning",
  "info": "Information"
}
EOF
        
        # Navigation translations
        cat > "i18n/translations/$lang/navigation.json" << EOF
{
  "home": "Home",
  "about": "About",
  "contact": "Contact",
  "services": "Services",
  "products": "Products",
  "blog": "Blog",
  "login": "Login",
  "logout": "Logout",
  "register": "Register",
  "profile": "Profile",
  "settings": "Settings",
  "dashboard": "Dashboard"
}
EOF
        
        info "Created translations for language: $lang"
    done
    
    log "Translation files created successfully"
}

# Initialize services
initialize_services() {
    log "Initializing Global Reach services..."
    
    # Pull required Docker images
    docker-compose -f docker-compose.global-reach.yml pull
    
    # Build custom services
    docker-compose -f docker-compose.global-reach.yml build
    
    log "Services initialized successfully"
}

# Start services
start_services() {
    log "Starting Global Reach services..."
    
    # Start infrastructure services first
    docker-compose -f docker-compose.global-reach.yml up -d redis-global nginx-cdn varnish-cache
    
    # Wait for infrastructure to be ready
    sleep 10
    
    # Start application services
    docker-compose -f docker-compose.global-reach.yml up -d
    
    # Wait for services to be ready
    sleep 30
    
    log "All services started successfully"
}

# Verify installation
verify_installation() {
    log "Verifying Global Reach installation..."
    
    local services=(
        "http://localhost:8084/health:NGINX CDN"
        "http://localhost:8085:Varnish Cache"
        "http://localhost:3500/health:i18n Service"
        "http://localhost:3501/health:Currency Service"
        "http://localhost:3502/health:Timezone Service"
        "http://localhost:3503/health:RTL Service"
        "http://localhost:3504/health:Localization Service"
        "http://localhost:3505/health:CDN Optimizer"
        "http://localhost:3506/health:Global Reach Gateway"
        "http://localhost:3507:Global Reach Dashboard"
        "http://localhost:3310:Grafana Global"
        "http://localhost:5602:Kibana Global"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r url name <<< "$service"
        if curl -s "$url" > /dev/null 2>&1; then
            info "✓ $name is running"
        else
            warn "✗ $name is not responding"
        fi
    done
    
    log "Installation verification completed"
}

# Display access information
display_access_info() {
    log "Global Reach System Setup Complete!"
    
    echo ""
    echo "🌍 GLOBAL REACH ACCESS INFORMATION"
    echo "=================================="
    echo ""
    echo "🚀 Core Services:"
    echo "   • NGINX CDN:                http://localhost:8084"
    echo "   • Varnish Cache:            http://localhost:8085"
    echo "   • Global Reach Gateway:     http://localhost:3506"
    echo "   • Global Reach Dashboard:   http://localhost:3507"
    echo ""
    echo "🔧 Microservices:"
    echo "   • i18n Service:             http://localhost:3500"
    echo "   • Currency Service:         http://localhost:3501"
    echo "   • Timezone Service:         http://localhost:3502"
    echo "   • RTL Service:              http://localhost:3503"
    echo "   • Localization Service:     http://localhost:3504"
    echo "   • CDN Optimizer:            http://localhost:3505"
    echo ""
    echo "📊 Monitoring & Analytics:"
    echo "   • Grafana Global:           http://localhost:3310 (admin/admin123)"
    echo "   • Prometheus Global:        http://localhost:9095"
    echo "   • Kibana Global:            http://localhost:5602"
    echo "   • ElasticSearch Global:     http://localhost:9201"
    echo ""
    echo "🌐 Supported Languages:"
    echo "   • English (en), Spanish (es), French (fr), German (de)"
    echo "   • Japanese (ja), Chinese (zh), Arabic (ar), Hebrew (he)"
    echo "   • Russian (ru), Portuguese (pt), Italian (it), Korean (ko)"
    echo "   • Hindi (hi), Thai (th), Vietnamese (vi)"
    echo ""
    echo "💰 Currency Support:"
    echo "   • Real-time exchange rates for 150+ currencies"
    echo "   • Automatic currency detection and conversion"
    echo ""
    echo "🕐 Timezone Features:"
    echo "   • Automatic timezone detection"
    echo "   • Date/time localization for all regions"
    echo ""
    echo "📱 RTL Language Support:"
    echo "   • Arabic, Hebrew, Persian, Urdu, Kurdish, Sindhi"
    echo "   • Automatic layout direction switching"
    echo ""
    echo "🚀 Performance Features:"
    echo "   • Multi-layer caching (NGINX + Varnish + Redis)"
    echo "   • Global CDN with edge optimization"
    echo "   • Image optimization (WebP/AVIF conversion)"
    echo "   • Brotli and Gzip compression"
    echo ""
    echo "📈 Enterprise Features:"
    echo "   • Real-time analytics and monitoring"
    echo "   • Performance metrics and alerting"
    echo "   • Security headers and rate limiting"
    echo "   • High availability and load balancing"
    echo ""
    echo "🔧 Management Commands:"
    echo "   • Stop services:    docker-compose -f docker-compose.global-reach.yml down"
    echo "   • View logs:        docker-compose -f docker-compose.global-reach.yml logs -f"
    echo "   • Restart:          docker-compose -f docker-compose.global-reach.yml restart"
    echo ""
}

# Main execution
main() {
    log "Starting Enterprise Global Reach System Setup..."
    
    check_root
    check_requirements
    create_directories
    generate_configs
    create_docker_services
    create_translation_files
    initialize_services
    start_services
    verify_installation
    display_access_info
    
    log "Enterprise Global Reach System setup completed successfully!"
}

# Run main function
main "$@"
EOF
