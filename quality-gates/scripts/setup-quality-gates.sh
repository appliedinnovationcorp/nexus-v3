#!/bin/bash

# Enterprise Quality Gates Setup Script
# Comprehensive quality assurance with 100% FOSS technologies

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
    
    # Check available disk space (minimum 10GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10485760 ]; then
        warn "Less than 10GB disk space available. Quality Gates may require more space."
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
    
    # SonarQube configuration
    cat > config/sonarqube/sonar.properties << 'EOF'
# SonarQube Configuration
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.context=/
sonar.ce.workerCount=4
sonar.search.javaOpts=-Xmx2g -Xms2g
sonar.web.javaOpts=-Xmx2g -Xms2g
sonar.log.level=INFO
sonar.path.logs=logs
sonar.path.temp=temp
EOF

    # ZAP configuration
    cat > config/zap/zap-baseline.conf << 'EOF'
# ZAP Baseline Configuration
rules.cookie.ignorelist=JSESSIONID,PHPSESSID
rules.pscanrules.cookiesamesite.level=LOW
rules.pscanrules.cookiesecureflag.level=LOW
rules.pscanrules.cookiehttponly.level=LOW
rules.common.sleep=15
EOF

    # Pa11y configuration
    cat > config/pa11y/config.json << 'EOF'
{
  "database": "mongodb://pa11y-mongo:27017/pa11y",
  "host": "0.0.0.0",
  "port": 4000,
  "webservice": {
    "database": "mongodb://pa11y-mongo:27017/pa11y",
    "host": "0.0.0.0",
    "port": 3000
  }
}
EOF

    # Lighthouse CI configuration
    cat > config/lighthouse/lighthouserc.json << 'EOF'
{
  "ci": {
    "collect": {
      "numberOfRuns": 3,
      "settings": {
        "chromeFlags": "--no-sandbox --headless"
      }
    },
    "assert": {
      "assertions": {
        "categories:performance": ["error", {"minScore": 0.8}],
        "categories:accessibility": ["error", {"minScore": 0.9}],
        "categories:best-practices": ["error", {"minScore": 0.8}],
        "categories:seo": ["error", {"minScore": 0.8}]
      }
    },
    "upload": {
      "target": "lhci",
      "serverBaseUrl": "http://lighthouse-ci:9001"
    }
  }
}
EOF

    # Semgrep configuration
    cat > config/semgrep/semgrep.yml << 'EOF'
rules:
  - id: hardcoded-secrets
    patterns:
      - pattern: password = "..."
      - pattern: api_key = "..."
      - pattern: secret = "..."
    message: Hardcoded secrets detected
    languages: [javascript, typescript, python, java]
    severity: ERROR
  
  - id: sql-injection
    patterns:
      - pattern: |
          $QUERY = "SELECT * FROM users WHERE id = " + $INPUT
    message: Potential SQL injection vulnerability
    languages: [javascript, typescript, python, java]
    severity: ERROR
    
  - id: xss-vulnerability
    patterns:
      - pattern: |
          $ELEMENT.innerHTML = $INPUT
    message: Potential XSS vulnerability
    languages: [javascript, typescript]
    severity: ERROR
EOF

    # Prometheus configuration
    cat > config/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "quality_gates_rules.yml"

scrape_configs:
  - job_name: 'quality-gates-orchestrator'
    static_configs:
      - targets: ['quality-gates-orchestrator:3001']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'sonarqube'
    static_configs:
      - targets: ['sonarqube:9000']
    metrics_path: '/api/monitoring/metrics'
    scrape_interval: 60s

  - job_name: 'lighthouse-ci'
    static_configs:
      - targets: ['lighthouse-ci:9001']
    metrics_path: '/metrics'
    scrape_interval: 60s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    # Grafana provisioning
    mkdir -p config/grafana/provisioning/{datasources,dashboards}
    
    cat > config/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://quality-prometheus:9090
    isDefault: true
    editable: true
EOF

    cat > config/grafana/provisioning/dashboards/quality-gates.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'quality-gates'
    orgId: 1
    folder: 'Quality Gates'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log "Configuration files initialized"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # ESLint Daemon Dockerfile
    cat > docker/eslint-daemon/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install ESLint and plugins globally
RUN npm install -g \
    eslint \
    @typescript-eslint/parser \
    @typescript-eslint/eslint-plugin \
    eslint-plugin-react \
    eslint-plugin-react-hooks \
    eslint-plugin-jsx-a11y \
    eslint-plugin-import \
    eslint-plugin-security \
    eslint-plugin-sonarjs

# Create ESLint daemon script
COPY eslint-daemon.js /app/
COPY package.json /app/

RUN npm install

EXPOSE 7777

CMD ["node", "eslint-daemon.js"]
EOF

    cat > docker/eslint-daemon/package.json << 'EOF'
{
  "name": "eslint-daemon",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

    cat > docker/eslint-daemon/eslint-daemon.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { exec } = require('child_process');
const path = require('path');

const app = express();
const port = 7777;

app.use(cors());
app.use(express.json());

app.post('/lint', (req, res) => {
    const { files, config } = req.body;
    const configPath = config || '/workspace/.eslintrc.js';
    
    const command = `eslint ${files.join(' ')} --config ${configPath} --format json`;
    
    exec(command, { cwd: '/workspace' }, (error, stdout, stderr) => {
        if (error && error.code !== 1) {
            return res.status(500).json({ error: stderr });
        }
        
        try {
            const results = JSON.parse(stdout);
            res.json(results);
        } catch (parseError) {
            res.status(500).json({ error: 'Failed to parse ESLint output' });
        }
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

app.listen(port, '0.0.0.0', () => {
    console.log(`ESLint daemon listening on port ${port}`);
});
EOF

    # Quality Gates Orchestrator
    cat > docker/orchestrator/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --only=production

COPY src/ ./src/
COPY config/ ./config/

EXPOSE 3001

CMD ["node", "src/index.js"]
EOF

    cat > docker/orchestrator/package.json << 'EOF'
{
  "name": "quality-gates-orchestrator",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "redis": "^4.6.0",
    "pg": "^8.11.0",
    "winston": "^3.11.0",
    "cron": "^3.1.0",
    "prom-client": "^15.0.0"
  }
}
EOF

    # Dashboard Dockerfile
    cat > docker/dashboard/Dockerfile << 'EOF'
FROM node:18-alpine as builder

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

COPY public/ ./public/
COPY src/ ./src/
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
EOF

    log "Docker images configuration created"
}

# Create orchestrator application
create_orchestrator() {
    log "Creating Quality Gates Orchestrator..."
    
    mkdir -p docker/orchestrator/src/{controllers,services,models,middleware,utils}
    
    # Main application file
    cat > docker/orchestrator/src/index.js << 'EOF'
const express = require('express');
const cors = require('cors');
const winston = require('winston');
const client = require('prom-client');
const cron = require('cron');

const qualityGatesController = require('./controllers/qualityGatesController');
const metricsController = require('./controllers/metricsController');
const healthController = require('./controllers/healthController');

const app = express();
const port = process.env.PORT || 3001;

// Configure logging
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'quality-gates.log' })
    ]
});

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const qualityGateExecutions = new client.Counter({
    name: 'quality_gate_executions_total',
    help: 'Total number of quality gate executions',
    labelNames: ['project', 'gate_type', 'status'],
    registers: [register]
});

const qualityGateDuration = new client.Histogram({
    name: 'quality_gate_duration_seconds',
    help: 'Duration of quality gate executions',
    labelNames: ['project', 'gate_type'],
    registers: [register]
});

// Middleware
app.use(cors());
app.use(express.json());
app.use((req, res, next) => {
    logger.info(`${req.method} ${req.path}`, { 
        ip: req.ip, 
        userAgent: req.get('User-Agent') 
    });
    next();
});

// Routes
app.use('/api/quality-gates', qualityGatesController);
app.use('/api/metrics', metricsController);
app.use('/health', healthController);

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

// Scheduled quality gate runs
const scheduledJob = new cron.CronJob('0 */6 * * *', async () => {
    logger.info('Running scheduled quality gates');
    // Implementation for scheduled runs
});

scheduledJob.start();

app.listen(port, '0.0.0.0', () => {
    logger.info(`Quality Gates Orchestrator listening on port ${port}`);
});

module.exports = { app, logger, qualityGateExecutions, qualityGateDuration };
EOF

    # Quality Gates Controller
    cat > docker/orchestrator/src/controllers/qualityGatesController.js << 'EOF'
const express = require('express');
const router = express.Router();
const QualityGateService = require('../services/qualityGateService');

const qualityGateService = new QualityGateService();

// Execute quality gates for a project
router.post('/execute', async (req, res) => {
    try {
        const { project, gates, config } = req.body;
        
        if (!project || !gates) {
            return res.status(400).json({ 
                error: 'Project and gates are required' 
            });
        }

        const results = await qualityGateService.executeGates(project, gates, config);
        
        res.json({
            project,
            timestamp: new Date().toISOString(),
            results,
            overall: results.every(r => r.passed) ? 'PASSED' : 'FAILED'
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get quality gate history
router.get('/history/:project', async (req, res) => {
    try {
        const { project } = req.params;
        const { limit = 50, offset = 0 } = req.query;
        
        const history = await qualityGateService.getHistory(project, limit, offset);
        res.json(history);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get quality gate configuration
router.get('/config/:project', async (req, res) => {
    try {
        const { project } = req.params;
        const config = await qualityGateService.getConfig(project);
        res.json(config);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Update quality gate configuration
router.put('/config/:project', async (req, res) => {
    try {
        const { project } = req.params;
        const config = req.body;
        
        await qualityGateService.updateConfig(project, config);
        res.json({ message: 'Configuration updated successfully' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;
EOF

    log "Quality Gates Orchestrator created"
}

# Create dashboard application
create_dashboard() {
    log "Creating Quality Gates Dashboard..."
    
    mkdir -p docker/dashboard/{src,public}
    
    cat > docker/dashboard/package.json << 'EOF'
{
  "name": "quality-gates-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.8.0",
    "axios": "^1.6.0",
    "@mui/material": "^5.15.0",
    "@mui/icons-material": "^5.15.0",
    "@emotion/react": "^11.11.0",
    "@emotion/styled": "^11.11.0",
    "recharts": "^2.8.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "devDependencies": {
    "react-scripts": "5.0.1"
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOF

    cat > docker/dashboard/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 3000;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /api {
            proxy_pass http://quality-gates-orchestrator:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    log "Quality Gates Dashboard created"
}

# Initialize database
init_database() {
    log "Initializing database schema..."
    
    cat > sql/init.sql << 'EOF'
-- Quality Gates Database Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    repository_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Quality gate configurations
CREATE TABLE quality_gate_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    gate_type VARCHAR(100) NOT NULL,
    configuration JSONB NOT NULL,
    thresholds JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Quality gate executions
CREATE TABLE quality_gate_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    gate_type VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL,
    results JSONB NOT NULL,
    metrics JSONB,
    duration_ms INTEGER,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    commit_hash VARCHAR(40),
    branch VARCHAR(255)
);

-- Quality metrics history
CREATE TABLE quality_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    metric_type VARCHAR(100) NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    value DECIMAL(10,4) NOT NULL,
    threshold DECIMAL(10,4),
    status VARCHAR(50) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    execution_id UUID REFERENCES quality_gate_executions(id)
);

-- Indexes for performance
CREATE INDEX idx_executions_project_date ON quality_gate_executions(project_id, executed_at DESC);
CREATE INDEX idx_metrics_project_type ON quality_metrics(project_id, metric_type, recorded_at DESC);
CREATE INDEX idx_configs_project_active ON quality_gate_configs(project_id, is_active);

-- Insert default project
INSERT INTO projects (name, description) VALUES 
('nexus-v3', 'Enterprise full-stack monorepo with comprehensive quality gates');

-- Insert default quality gate configurations
INSERT INTO quality_gate_configs (project_id, gate_type, configuration, thresholds) VALUES
((SELECT id FROM projects WHERE name = 'nexus-v3'), 'code_quality', 
 '{"sonarqube_url": "http://sonarqube:9000", "project_key": "nexus-v3"}',
 '{"coverage": 80, "duplicated_lines_density": 3, "maintainability_rating": "A", "reliability_rating": "A", "security_rating": "A"}'),
 
((SELECT id FROM projects WHERE name = 'nexus-v3'), 'security_scan',
 '{"zap_url": "http://zap:8080", "trivy_url": "http://trivy:4954"}',
 '{"high_vulnerabilities": 0, "medium_vulnerabilities": 5, "low_vulnerabilities": 20}'),
 
((SELECT id FROM projects WHERE name = 'nexus-v3'), 'performance',
 '{"lighthouse_url": "http://lighthouse-ci:9001"}',
 '{"performance_score": 80, "accessibility_score": 90, "best_practices_score": 80, "seo_score": 80}'),
 
((SELECT id FROM projects WHERE name = 'nexus-v3'), 'accessibility',
 '{"pa11y_url": "http://pa11y-dashboard:4000"}',
 '{"errors": 0, "warnings": 5, "notices": 20}');
EOF

    log "Database schema initialized"
}

# Start services
start_services() {
    log "Starting Quality Gates services..."
    
    # Pull required images
    docker-compose -f docker-compose.quality-gates.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.quality-gates.yml build
    
    # Start services
    docker-compose -f docker-compose.quality-gates.yml up -d
    
    log "Waiting for services to be ready..."
    sleep 30
    
    # Health checks
    check_service_health "SonarQube" "http://localhost:9000/api/system/status"
    check_service_health "OWASP ZAP" "http://localhost:8080"
    check_service_health "Pa11y Dashboard" "http://localhost:4000"
    check_service_health "Lighthouse CI" "http://localhost:9001"
    check_service_health "Quality Gates Orchestrator" "http://localhost:3001/health"
    check_service_health "Quality Gates Dashboard" "http://localhost:3002"
    check_service_health "Grafana" "http://localhost:3003"
    check_service_health "Prometheus" "http://localhost:9091"
    
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
    log "Quality Gates System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Quality Gates Dashboard:${NC} http://localhost:3002"
    echo -e "${GREEN}SonarQube:${NC} http://localhost:9000 (admin/admin)"
    echo -e "${GREEN}OWASP ZAP:${NC} http://localhost:8080"
    echo -e "${GREEN}Pa11y Dashboard:${NC} http://localhost:4000"
    echo -e "${GREEN}Lighthouse CI:${NC} http://localhost:9001"
    echo -e "${GREEN}Grafana:${NC} http://localhost:3003 (admin/admin)"
    echo -e "${GREEN}Prometheus:${NC} http://localhost:9091"
    echo -e "${GREEN}Quality Gates API:${NC} http://localhost:3001"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Configure your project in SonarQube"
    echo "2. Set up quality gate thresholds in the dashboard"
    echo "3. Run quality gates: curl -X POST http://localhost:3001/api/quality-gates/execute"
    echo "4. View results in Grafana dashboards"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Quality Gates Setup..."
    
    check_prerequisites
    init_configs
    build_images
    create_orchestrator
    create_dashboard
    init_database
    start_services
    show_access_info
    
    log "Quality Gates setup completed successfully!"
}

# Execute main function
main "$@"
