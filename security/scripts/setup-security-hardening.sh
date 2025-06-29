#!/bin/bash

set -e

echo "🔒 Setting up Security Hardening System..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[SETUP]${NC} $1"
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
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Create directory structure
create_directories() {
    print_header "Creating directory structure..."
    
    mkdir -p security/{config,scripts,services,reports,docs}
    mkdir -p security/config/{vault,vault-agent,nginx-security,modsecurity,falco,prometheus-security,grafana-security/{dashboards,datasources}}
    mkdir -p security/services/{security-service,security-scanner,security-exporter}
    mkdir -p security/scripts/{vault,scanning,monitoring}
    mkdir -p security/reports/{zap,snyk,dependency-check,sonarqube}
    
    print_status "Directory structure created ✅"
}

# Setup SSL certificates
setup_ssl_certificates() {
    print_header "Setting up SSL certificates..."
    
    mkdir -p security/config/nginx-security/ssl
    
    # Generate self-signed certificate for development
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout security/config/nginx-security/ssl/nginx.key \
        -out security/config/nginx-security/ssl/nginx.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    
    print_status "SSL certificates created ✅"
}

# Setup Vault initialization script
setup_vault_scripts() {
    print_header "Setting up Vault scripts..."
    
    cat > security/scripts/vault/init-vault.sh << 'EOF'
#!/bin/bash

set -e

echo "Initializing HashiCorp Vault..."

# Wait for Vault to be ready
until curl -f http://vault:8200/v1/sys/health > /dev/null 2>&1; do
    echo "Waiting for Vault to be ready..."
    sleep 5
done

# Initialize Vault (only if not already initialized)
if ! curl -s http://vault:8200/v1/sys/init | grep -q '"initialized":true'; then
    echo "Initializing Vault..."
    
    INIT_RESPONSE=$(curl -s -X POST http://vault:8200/v1/sys/init \
        -d '{
            "secret_shares": 5,
            "secret_threshold": 3
        }')
    
    echo "$INIT_RESPONSE" > /vault/init-keys.json
    
    # Extract unseal keys and root token
    UNSEAL_KEY_1=$(echo "$INIT_RESPONSE" | jq -r '.keys[0]')
    UNSEAL_KEY_2=$(echo "$INIT_RESPONSE" | jq -r '.keys[1]')
    UNSEAL_KEY_3=$(echo "$INIT_RESPONSE" | jq -r '.keys[2]')
    ROOT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.root_token')
    
    # Unseal Vault
    curl -s -X POST http://vault:8200/v1/sys/unseal -d "{\"key\": \"$UNSEAL_KEY_1\"}"
    curl -s -X POST http://vault:8200/v1/sys/unseal -d "{\"key\": \"$UNSEAL_KEY_2\"}"
    curl -s -X POST http://vault:8200/v1/sys/unseal -d "{\"key\": \"$UNSEAL_KEY_3\"}"
    
    echo "Vault initialized and unsealed!"
    echo "Root token: $ROOT_TOKEN"
    
    # Enable secrets engines
    curl -s -X POST http://vault:8200/v1/sys/mounts/secret \
        -H "X-Vault-Token: $ROOT_TOKEN" \
        -d '{
            "type": "kv",
            "options": {
                "version": "2"
            }
        }'
    
    curl -s -X POST http://vault:8200/v1/sys/mounts/database \
        -H "X-Vault-Token: $ROOT_TOKEN" \
        -d '{"type": "database"}'
    
    curl -s -X POST http://vault:8200/v1/sys/mounts/transit \
        -H "X-Vault-Token: $ROOT_TOKEN" \
        -d '{"type": "transit"}'
    
    curl -s -X POST http://vault:8200/v1/sys/mounts/pki \
        -H "X-Vault-Token: $ROOT_TOKEN" \
        -d '{"type": "pki"}'
    
    echo "Secrets engines enabled!"
    
else
    echo "Vault is already initialized"
fi
EOF

    chmod +x security/scripts/vault/init-vault.sh
    
    print_status "Vault scripts created ✅"
}

# Setup security scanning scripts
setup_scanning_scripts() {
    print_header "Setting up security scanning scripts..."
    
    cat > security/scripts/scanning/run-security-scan.sh << 'EOF'
#!/bin/bash

set -e

echo "🔍 Running comprehensive security scan..."

TARGET_URL=${1:-"http://security-service:3000"}
REPORT_DIR="/reports"

# Create report directory
mkdir -p "$REPORT_DIR"

echo "Starting OWASP ZAP scan..."
# ZAP baseline scan
docker run --rm -v "$REPORT_DIR":/zap/wrk/:rw \
    -t owasp/zap2docker-stable zap-baseline.py \
    -t "$TARGET_URL" \
    -J zap-baseline-report.json \
    -H zap-baseline-report.html

echo "Starting dependency vulnerability scan..."
# Snyk scan (if token is available)
if [ -n "$SNYK_TOKEN" ]; then
    docker run --rm -v "$(pwd)":/app -v "$REPORT_DIR":/reports \
        -e SNYK_TOKEN="$SNYK_TOKEN" \
        snyk/snyk:node test --json > "$REPORT_DIR/snyk-report.json" || true
fi

# OWASP Dependency Check
docker run --rm -v "$(pwd)":/src -v "$REPORT_DIR":/reports \
    owasp/dependency-check:latest \
    --scan /src \
    --format ALL \
    --out /reports \
    --project "Security Scan"

echo "Security scan completed! Reports available in $REPORT_DIR"
EOF

    chmod +x security/scripts/scanning/run-security-scan.sh
    
    print_status "Scanning scripts created ✅"
}

# Setup monitoring configuration
setup_monitoring_config() {
    print_header "Setting up monitoring configuration..."
    
    # Prometheus configuration for security metrics
    cat > security/config/prometheus-security/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Security service metrics
  - job_name: 'security-service'
    static_configs:
      - targets: ['security-service:3000']
    metrics_path: '/metrics'
    scrape_interval: 15s

  # Vault metrics
  - job_name: 'vault'
    static_configs:
      - targets: ['vault:8200']
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']

  # Nginx metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-security:80']
    metrics_path: '/nginx_status'

  # Security scanner metrics
  - job_name: 'security-scanner'
    static_configs:
      - targets: ['security-exporter:9200']
    scrape_interval: 30s

  # Node exporter for system metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

    # Grafana datasource configuration
    cat > security/config/grafana-security/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-security:9090
    isDefault: true
    editable: true
EOF

    print_status "Monitoring configuration created ✅"
}

# Setup Falco rules
setup_falco_config() {
    print_header "Setting up Falco runtime security monitoring..."
    
    cat > security/config/falco/falco_rules.yaml << 'EOF'
# Custom Falco rules for security monitoring

- rule: Detect crypto mining
  desc: Detect cryptocurrency mining
  condition: spawned_process and proc.name in (xmrig, minergate)
  output: Crypto mining detected (user=%user.name command=%proc.cmdline)
  priority: CRITICAL

- rule: Detect privilege escalation
  desc: Detect attempts to escalate privileges
  condition: spawned_process and proc.name in (sudo, su) and not user.name in (root, admin)
  output: Privilege escalation attempt (user=%user.name command=%proc.cmdline)
  priority: HIGH

- rule: Detect suspicious network activity
  desc: Detect suspicious network connections
  condition: inbound_outbound and fd.sport in (4444, 5555, 6666, 7777, 8888, 9999)
  output: Suspicious network activity (connection=%fd.name sport=%fd.sport dport=%fd.dport)
  priority: HIGH

- rule: Detect file system changes in sensitive directories
  desc: Detect unauthorized changes to sensitive directories
  condition: open_write and fd.name startswith /etc
  output: Sensitive file modified (file=%fd.name user=%user.name command=%proc.cmdline)
  priority: MEDIUM

- rule: Detect container escape attempts
  desc: Detect attempts to escape from containers
  condition: spawned_process and proc.name in (docker, kubectl, crictl)
  output: Container escape attempt detected (user=%user.name command=%proc.cmdline)
  priority: CRITICAL
EOF

    print_status "Falco configuration created ✅"
}

# Create comprehensive documentation
create_documentation() {
    print_header "Creating documentation..."
    
    cat > security/README-SECURITY-HARDENING.md << 'EOF'
# Security Hardening System

## 🔒 Overview

This is a comprehensive security hardening solution using best-of-breed FOSS technologies:

- **Content Security Policy**: Comprehensive CSP headers with nonce-based protection
- **OWASP Security Scanning**: ZAP integration for automated security testing
- **Dependency Scanning**: Snyk, npm audit, and OWASP Dependency Check
- **Secrets Management**: HashiCorp Vault for secure secret storage and rotation
- **Input Validation**: Comprehensive validation and sanitization framework
- **SQL Injection Prevention**: Parameterized queries and ORM security
- **XSS Protection**: Multi-layered XSS prevention and sanitization

## 🏗️ Architecture

### Security Controls
- **Prevention**: CSP, Input validation, Output encoding, Parameterized queries
- **Detection**: Security scanning, Vulnerability assessment, Runtime monitoring
- **Response**: Incident response, Automated remediation, Security alerting

### Technology Stack
- **HashiCorp Vault**: Secrets management and encryption
- **OWASP ZAP**: Dynamic application security testing
- **SonarQube**: Static code analysis and security scanning
- **Snyk**: Dependency vulnerability scanning
- **Falco**: Runtime security monitoring
- **ModSecurity**: Web application firewall

## 🚀 Quick Start

### 1. Start Security Infrastructure

```bash
# Start all security services
docker-compose -f security/docker-compose.security.yml up -d

# Initialize Vault
./security/scripts/vault/init-vault.sh

# Wait for services to be ready
sleep 30
```

### 2. Run Security Scans

```bash
# Run comprehensive security scan
./security/scripts/scanning/run-security-scan.sh http://localhost:3010

# Run dependency vulnerability scan
docker-compose -f security/docker-compose.security.yml run --rm snyk-monitor

# Run OWASP Dependency Check
docker-compose -f security/docker-compose.security.yml run --rm dependency-check
```

### 3. Access Security Dashboards

- **Vault UI**: http://localhost:8200
- **OWASP ZAP**: http://localhost:8090
- **SonarQube**: http://localhost:9000 (admin/admin)
- **Security Dashboard**: http://localhost:3003 (admin/admin)
- **Prometheus**: http://localhost:9092

## 🛡️ Security Features

### Content Security Policy
```javascript
// Automatic CSP header generation with nonce
app.use(securityMiddleware.contentSecurityPolicy());

// Nonce usage in templates
<script nonce="${nonce}">
  // Your secure script here
</script>
```

### Input Validation & Sanitization
```javascript
// Comprehensive input validation
app.post('/api/users', 
  securityMiddleware.validateAndSanitize([
    ValidationRules.email(),
    ValidationRules.password(),
    ValidationRules.noSqlInjection()
  ]),
  userController.create
);
```

### XSS Protection
```javascript
// Multi-layered XSS protection
app.use(securityMiddleware.xssProtection());

// Automatic sanitization of user input
const sanitizedInput = DOMPurify.sanitize(userInput);
```

### SQL Injection Prevention
```javascript
// Parameterized queries
const user = await db.query(
  'SELECT * FROM users WHERE email = $1',
  [email]
);

// ORM with built-in protection
const user = await User.findOne({ where: { email } });
```

### Secrets Management with Vault
```javascript
// Read secrets from Vault
const dbCredentials = await vaultService.getDatabaseCredentials('app-role');

// Encrypt sensitive data
const encrypted = await vaultService.encrypt('app-key', sensitiveData);

// Generate dynamic certificates
const cert = await vaultService.generateCertificate('web-server', 'app.example.com');
```

## 🔍 Security Scanning

### OWASP ZAP Integration
```javascript
// Automated security scanning
const scanner = createOwaspZapScanner({
  zapUrl: 'http://owasp-zap:8080',
  timeout: 30000
});

const scanId = await scanner.startActiveScan({
  url: 'http://target-app:3000',
  authentication: {
    method: 'form',
    loginUrl: '/login',
    username: 'testuser',
    password: 'testpass'
  }
});

const results = await scanner.getScanResults();
```

### Dependency Vulnerability Scanning
```javascript
// Multi-scanner dependency checking
const scanner = createDependencyScanner({
  enabledScanners: ['npm-audit', 'snyk', 'owasp-dc'],
  outputDir: './reports',
  severityThreshold: 'medium'
});

const results = await scanner.scanProject('./');
```

## 📊 Security Monitoring

### Real-Time Security Metrics
- Failed authentication attempts
- SQL injection attempts
- XSS attack attempts
- Rate limiting violations
- Suspicious file access
- Container escape attempts

### Security Dashboards
- Vulnerability trends over time
- Security scan results
- Runtime security events
- Compliance status
- Incident response metrics

## 🔧 Configuration

### Environment Variables
```bash
# Vault configuration
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=your-vault-token

# Security settings
CSP_NONCE_SECRET=your-csp-secret
SECURITY_HEADERS_ENABLED=true
INPUT_VALIDATION_STRICT=true
XSS_PROTECTION_ENABLED=true
SQL_INJECTION_PROTECTION=true

# Scanning configuration
SNYK_TOKEN=your-snyk-token
SONARQUBE_TOKEN=your-sonarqube-token
```

### Security Policies
```javascript
// CSP configuration
const cspConfig = {
  defaultSrc: ["'self'"],
  scriptSrc: ["'self'", "'nonce-{nonce}'", "'strict-dynamic'"],
  styleSrc: ["'self'", "'unsafe-inline'"],
  imgSrc: ["'self'", "data:", "https:"],
  connectSrc: ["'self'"],
  frameSrc: ["'none'"],
  objectSrc: ["'none'"]
};
```

## 🚨 Incident Response

### Automated Response
- Automatic blocking of malicious IPs
- Rate limiting escalation
- Alert generation for security events
- Automated vulnerability patching
- Container isolation for suspicious activity

### Manual Response Procedures
1. **Security Alert Triage**
2. **Incident Classification**
3. **Containment Actions**
4. **Evidence Collection**
5. **Recovery Procedures**
6. **Post-Incident Review**

This security hardening system provides comprehensive protection against modern web application threats using industry-standard FOSS tools and practices.
EOF

    print_status "Documentation created ✅"
}

# Main setup function
main() {
    print_header "Starting Security Hardening System Setup"
    
    check_dependencies
    create_directories
    setup_ssl_certificates
    setup_vault_scripts
    setup_scanning_scripts
    setup_monitoring_config
    setup_falco_config
    create_documentation
    
    print_status "Security hardening setup completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Start services: docker-compose -f security/docker-compose.security.yml up -d"
    echo "2. Initialize Vault: ./security/scripts/vault/init-vault.sh"
    echo "3. Run security scan: ./security/scripts/scanning/run-security-scan.sh"
    echo ""
    echo "Access points:"
    echo "- Vault UI: http://localhost:8200"
    echo "- OWASP ZAP: http://localhost:8090"
    echo "- SonarQube: http://localhost:9000 (admin/admin)"
    echo "- Security Dashboard: http://localhost:3003 (admin/admin)"
    echo "- Security Service: https://localhost:8443"
}

# Run main function
main "$@"
