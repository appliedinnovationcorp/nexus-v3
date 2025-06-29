#!/bin/bash

# Enterprise Frontend Optimization Setup Script
# Comprehensive frontend optimization with 100% FOSS technologies

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
    
    # Check available disk space (minimum 15GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 15728640 ]; then
        warn "Less than 15GB disk space available. Frontend optimization may require more space."
    fi
    
    # Check available memory (minimum 8GB recommended)
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_memory" -lt 8192 ]; then
        warn "Less than 8GB RAM available. Performance may be impacted."
    fi
    
    log "Prerequisites check completed"
}

# Initialize configuration files
init_configs() {
    log "Initializing configuration files..."
    
    # Create directory structure
    mkdir -p config/{nginx/conf.d,varnish,redis,grafana/{provisioning,dashboards},prometheus}
    mkdir -p docker/{nextjs,nginx-cdn,image-optimizer,sw-builder,bundle-analyzer,webp-converter,critical-css,perf-monitor}
    mkdir -p ssl
    mkdir -p sql
    
    # NGINX CDN configuration
    cat > config/nginx/nginx.conf << 'EOF'
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

    # Cache settings
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=STATIC:10m inactive=7d use_temp_path=off;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # NGINX server configuration
    cat > config/nginx/conf.d/default.conf << 'EOF'
upstream nextjs_backend {
    server nextjs-app:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name localhost;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Static assets with long cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
        
        # Try WebP first
        location ~* \.(png|jpg|jpeg)$ {
            add_header Vary "Accept";
            try_files $uri$webp_suffix $uri =404;
        }
        
        proxy_pass http://nextjs_backend;
        proxy_cache STATIC;
        proxy_cache_valid 200 1d;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
    }

    # API routes - no cache
    location /api/ {
        proxy_pass http://nextjs_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Next.js pages
    location / {
        proxy_pass http://nextjs_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Cache HTML for 5 minutes
        proxy_cache STATIC;
        proxy_cache_valid 200 5m;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# WebP detection
map $http_accept $webp_suffix {
    default "";
    "~*webp" ".webp";
}
EOF

    # Varnish configuration
    cat > config/varnish/default.vcl << 'EOF'
vcl 4.1;

backend default {
    .host = "nginx-cdn";
    .port = "80";
    .connect_timeout = 60s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 60s;
}

sub vcl_recv {
    # Remove cookies for static assets
    if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg)(\?.*)?$") {
        unset req.http.Cookie;
    }

    # Remove tracking parameters
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
        set req.url = regsub(req.url, "\?&", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

    # Normalize Accept-Encoding
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|flv)$") {
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }
}

sub vcl_backend_response {
    # Cache static assets for 1 day
    if (bereq.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg)(\?.*)?$") {
        set beresp.ttl = 1d;
        set beresp.http.Cache-Control = "public, max-age=86400";
    }

    # Cache HTML for 5 minutes
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.ttl = 5m;
        set beresp.http.Cache-Control = "public, max-age=300";
    }

    # Enable ESI
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.do_esi = true;
    }
}

sub vcl_deliver {
    # Add cache hit/miss header
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Remove backend server info
    unset resp.http.Server;
    unset resp.http.X-Powered-By;
}
EOF

    # Redis configuration
    cat > config/redis/redis.conf << 'EOF'
# Redis configuration for frontend optimization
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
dbfilename dump.rdb
dir /data
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # Next.js Dockerfile
    cat > docker/nextjs/Dockerfile << 'EOF'
FROM node:18-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Environment variables for build
ENV NEXT_TELEMETRY_DISABLED 1
ENV NODE_ENV production

# Build application
RUN npm run build

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Automatically leverage output traces to reduce image size
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["node", "server.js"]
EOF

    # NGINX CDN Dockerfile
    cat > docker/nginx-cdn/Dockerfile << 'EOF'
FROM nginx:alpine

# Install brotli module
RUN apk add --no-cache nginx-mod-http-brotli

# Copy configuration
COPY ../../config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ../../config/nginx/conf.d /etc/nginx/conf.d

# Create cache directory
RUN mkdir -p /var/cache/nginx && \
    chown -R nginx:nginx /var/cache/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
EOF

    log "Docker images configuration created"
}

# Create optimization services
create_optimization_services() {
    log "Creating optimization services..."
    
    # Image Optimizer Service
    cat > docker/image-optimizer/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install sharp for image processing
RUN npm install sharp express cors multer

COPY package.json ./
COPY src/ ./src/

EXPOSE 3001

CMD ["node", "src/index.js"]
EOF

    cat > docker/image-optimizer/package.json << 'EOF'
{
  "name": "image-optimizer",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "multer": "^1.4.5",
    "sharp": "^0.32.0",
    "redis": "^4.6.0"
  }
}
EOF

    mkdir -p docker/image-optimizer/src
    cat > docker/image-optimizer/src/index.js << 'EOF'
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const sharp = require('sharp');
const Redis = require('redis');
const fs = require('fs').promises;
const path = require('path');

const app = express();
const port = 3001;

// Redis client
const redis = Redis.createClient({ url: process.env.REDIS_URL });
redis.connect();

// Multer configuration
const upload = multer({ dest: '/tmp/uploads/' });

app.use(cors());
app.use(express.json());

// Image optimization endpoint
app.post('/optimize', upload.single('image'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'No image file provided' });
        }

        const { width, height, quality = 80, format = 'webp' } = req.body;
        const inputPath = req.file.path;
        const outputFilename = `${Date.now()}-${req.file.originalname.split('.')[0]}.${format}`;
        const outputPath = path.join('/app/storage', outputFilename);

        // Optimize image
        let sharpInstance = sharp(inputPath);

        if (width || height) {
            sharpInstance = sharpInstance.resize(parseInt(width), parseInt(height), {
                fit: 'inside',
                withoutEnlargement: true
            });
        }

        if (format === 'webp') {
            sharpInstance = sharpInstance.webp({ quality: parseInt(quality) });
        } else if (format === 'jpeg') {
            sharpInstance = sharpInstance.jpeg({ quality: parseInt(quality) });
        } else if (format === 'png') {
            sharpInstance = sharpInstance.png({ quality: parseInt(quality) });
        }

        await sharpInstance.toFile(outputPath);

        // Clean up temp file
        await fs.unlink(inputPath);

        // Cache result
        const cacheKey = `image:${req.file.originalname}:${width}:${height}:${quality}:${format}`;
        await redis.setEx(cacheKey, 86400, outputFilename);

        res.json({
            success: true,
            filename: outputFilename,
            url: `/static/${outputFilename}`
        });
    } catch (error) {
        console.error('Image optimization error:', error);
        res.status(500).json({ error: 'Image optimization failed' });
    }
});

// Batch optimization endpoint
app.post('/optimize-batch', upload.array('images', 10), async (req, res) => {
    try {
        const { width, height, quality = 80, format = 'webp' } = req.body;
        const results = [];

        for (const file of req.files) {
            const inputPath = file.path;
            const outputFilename = `${Date.now()}-${file.originalname.split('.')[0]}.${format}`;
            const outputPath = path.join('/app/storage', outputFilename);

            let sharpInstance = sharp(inputPath);

            if (width || height) {
                sharpInstance = sharpInstance.resize(parseInt(width), parseInt(height), {
                    fit: 'inside',
                    withoutEnlargement: true
                });
            }

            if (format === 'webp') {
                sharpInstance = sharpInstance.webp({ quality: parseInt(quality) });
            }

            await sharpInstance.toFile(outputPath);
            await fs.unlink(inputPath);

            results.push({
                original: file.originalname,
                optimized: outputFilename,
                url: `/static/${outputFilename}`
            });
        }

        res.json({ success: true, results });
    } catch (error) {
        console.error('Batch optimization error:', error);
        res.status(500).json({ error: 'Batch optimization failed' });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

app.listen(port, '0.0.0.0', () => {
    console.log(`Image optimizer listening on port ${port}`);
});
EOF

    log "Optimization services created"
}

# Start services
start_services() {
    log "Starting Frontend Optimization services..."
    
    # Pull required images
    docker-compose -f docker-compose.frontend-optimization.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.frontend-optimization.yml build
    
    # Start services
    docker-compose -f docker-compose.frontend-optimization.yml up -d
    
    log "Waiting for services to be ready..."
    sleep 30
    
    # Health checks
    check_service_health "Next.js App" "http://localhost:3000/api/health"
    check_service_health "NGINX CDN" "http://localhost:8080/health"
    check_service_health "Varnish Cache" "http://localhost:8081"
    check_service_health "Image Optimizer" "http://localhost:3001/health"
    check_service_health "Frontend Grafana" "http://localhost:3004"
    check_service_health "Frontend Prometheus" "http://localhost:9092"
    
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
    log "Frontend Optimization System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Next.js Application:${NC} http://localhost:3000"
    echo -e "${GREEN}NGINX CDN:${NC} http://localhost:8080"
    echo -e "${GREEN}Varnish Cache:${NC} http://localhost:8081"
    echo -e "${GREEN}Image Optimizer:${NC} http://localhost:3001"
    echo -e "${GREEN}Bundle Analyzer:${NC} http://localhost:8888"
    echo -e "${GREEN}Lighthouse Performance:${NC} http://localhost:9002"
    echo -e "${GREEN}WebP Converter:${NC} http://localhost:3002"
    echo -e "${GREEN}Performance Monitor:${NC} http://localhost:3003"
    echo -e "${GREEN}Frontend Grafana:${NC} http://localhost:3004 (admin/admin)"
    echo -e "${GREEN}Frontend Prometheus:${NC} http://localhost:9092"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Access your optimized application at http://localhost:8081 (Varnish)"
    echo "2. Monitor performance in Grafana at http://localhost:3004"
    echo "3. Analyze bundles at http://localhost:8888"
    echo "4. Optimize images via API at http://localhost:3001/optimize"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Frontend Optimization Setup..."
    
    check_prerequisites
    init_configs
    build_images
    create_optimization_services
    start_services
    show_access_info
    
    log "Frontend Optimization setup completed successfully!"
}

# Execute main function
main "$@"
