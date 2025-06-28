#!/bin/bash

set -e

echo "🔐 Setting up Authentication & Authorization System..."

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

# Create directory structure
create_directories() {
    print_header "Creating directory structure..."
    
    mkdir -p auth/{config,scripts,services,docs}
    mkdir -p auth/config/{keycloak/{themes,providers},nginx,redis,prometheus,grafana/{dashboards,datasources},vault}
    mkdir -p auth/services/auth-service/{src,tests,dist}
    mkdir -p auth/scripts/{keycloak,setup}
    
    print_status "Directory structure created ✅"
}

# Setup configuration files
setup_configurations() {
    print_header "Setting up configuration files..."
    
    # Create Redis auth configuration
    cat > auth/config/redis/redis-auth.conf << 'EOF'
# Redis Configuration for Authentication System

# Network
bind 0.0.0.0
port 6379
protected-mode no

# General
daemonize no
supervised no
loglevel notice
databases 16

# Memory management
maxmemory 1gb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# Security
requirepass auth_redis_secure_pass

# Performance
tcp-keepalive 300
timeout 0
tcp-backlog 511
EOF

    # Create Nginx configuration
    cat > auth/config/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream keycloak {
        server keycloak:8080;
    }
    
    upstream auth-service {
        server auth-service:3000;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/s;

    server {
        listen 80;
        server_name localhost;

        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy strict-origin-when-cross-origin;

        # Keycloak proxy
        location /auth/ {
            limit_req zone=auth burst=20 nodelay;
            proxy_pass http://keycloak/auth/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Auth service proxy
        location /api/ {
            limit_req zone=api burst=50 nodelay;
            proxy_pass http://auth-service/api/;
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

    # Create Prometheus configuration
    cat > auth/config/prometheus/prometheus-auth.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Keycloak metrics
  - job_name: 'keycloak'
    static_configs:
      - targets: ['keycloak:8080']
    metrics_path: '/auth/realms/master/metrics'
    scrape_interval: 30s

  # Auth service metrics
  - job_name: 'auth-service'
    static_configs:
      - targets: ['auth-service:3000']
    metrics_path: '/metrics'
    scrape_interval: 15s

  # Redis metrics
  - job_name: 'redis-auth'
    static_configs:
      - targets: ['redis-exporter:9121']

  # PostgreSQL metrics
  - job_name: 'postgres-auth'
    static_configs:
      - targets: ['postgres-exporter:9187']

  # Nginx metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
EOF

    # Create Grafana datasource configuration
    cat > auth/config/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-auth:9090
    isDefault: true
    editable: true
EOF

    print_status "Configuration files created ✅"
}

# Setup Keycloak realm configuration
setup_keycloak_config() {
    print_header "Setting up Keycloak configuration..."
    
    cat > auth/scripts/keycloak/setup-realm.sh << 'EOF'
#!/bin/bash

# Keycloak Realm Setup Script

set -e

echo "Setting up Keycloak realm and client..."

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready..."
until curl -f http://keycloak:8080/auth/realms/master > /dev/null 2>&1; do
    echo "Waiting for Keycloak..."
    sleep 5
done

# Get admin token
ADMIN_TOKEN=$(curl -s -X POST \
  http://keycloak:8080/auth/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin_secure_pass" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
    echo "Failed to get admin token"
    exit 1
fi

# Create realm
curl -s -X POST \
  http://keycloak:8080/auth/admin/realms \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "aic-realm",
    "displayName": "AIC Authentication Realm",
    "enabled": true,
    "registrationAllowed": true,
    "registrationEmailAsUsername": true,
    "rememberMe": true,
    "verifyEmail": true,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true,
    "permanentLockout": false,
    "maxFailureWaitSeconds": 900,
    "minimumQuickLoginWaitSeconds": 60,
    "waitIncrementSeconds": 60,
    "quickLoginCheckMilliSeconds": 1000,
    "maxDeltaTimeSeconds": 43200,
    "failureFactor": 30
  }'

# Create client
curl -s -X POST \
  http://keycloak:8080/auth/admin/realms/aic-realm/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "aic-client",
    "name": "AIC Application Client",
    "description": "Main application client for AIC system",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "your-client-secret",
    "redirectUris": [
      "http://localhost:3000/*",
      "http://localhost:8080/*"
    ],
    "webOrigins": [
      "http://localhost:3000",
      "http://localhost:8080"
    ],
    "protocol": "openid-connect",
    "publicClient": false,
    "bearerOnly": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "authorizationServicesEnabled": true,
    "fullScopeAllowed": true
  }'

# Create user roles
curl -s -X POST \
  http://keycloak:8080/auth/admin/realms/aic-realm/roles \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "admin", "description": "Administrator role"}'

curl -s -X POST \
  http://keycloak:8080/auth/admin/realms/aic-realm/roles \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "user", "description": "Regular user role"}'

curl -s -X POST \
  http://keycloak:8080/auth/admin/realms/aic-realm/roles \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "api_user", "description": "API user role"}'

echo "Keycloak realm and client setup completed!"
EOF

    chmod +x auth/scripts/keycloak/setup-realm.sh

    print_status "Keycloak configuration created ✅"
}

# Setup monitoring dashboards
setup_monitoring() {
    print_header "Setting up monitoring dashboards..."
    
    # Create Grafana dashboard for authentication metrics
    cat > auth/config/grafana/dashboards/auth-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Authentication & Authorization Dashboard",
    "tags": ["auth", "security"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Login Attempts",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(auth_login_attempts_total[5m])",
            "legendFormat": "Login Rate"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Failed Logins",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(auth_login_failures_total[5m])",
            "legendFormat": "Failure Rate"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Active Sessions",
        "type": "stat",
        "targets": [
          {
            "expr": "auth_active_sessions",
            "legendFormat": "Active Sessions"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "API Key Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(auth_api_key_requests_total[5m])",
            "legendFormat": "API Requests/sec"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
EOF

    print_status "Monitoring dashboards created ✅"
}

# Setup test scripts
setup_test_scripts() {
    print_header "Setting up test scripts..."
    
    cat > auth/scripts/test-auth-system.sh << 'EOF'
#!/bin/bash

# Authentication System Test Script

set -e

echo "🧪 Testing Authentication System..."

BASE_URL="http://localhost:3000/api"
KEYCLOAK_URL="http://localhost:8080/auth"

# Test health endpoint
echo "Testing health endpoint..."
curl -f "$BASE_URL/health" || {
    echo "❌ Health check failed"
    exit 1
}
echo "✅ Health check passed"

# Test user registration
echo "Testing user registration..."
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "test@example.com",
        "username": "testuser",
        "password": "SecurePassword123!",
        "firstName": "Test",
        "lastName": "User"
    }')

if echo "$REGISTER_RESPONSE" | grep -q "error"; then
    echo "❌ Registration failed: $REGISTER_RESPONSE"
else
    echo "✅ Registration successful"
fi

# Test user login
echo "Testing user login..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "test@example.com",
        "password": "SecurePassword123!"
    }')

if echo "$LOGIN_RESPONSE" | grep -q "accessToken"; then
    echo "✅ Login successful"
    ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken')
else
    echo "❌ Login failed: $LOGIN_RESPONSE"
    exit 1
fi

# Test protected endpoint
echo "Testing protected endpoint..."
PROTECTED_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$BASE_URL/user/profile")

if echo "$PROTECTED_RESPONSE" | grep -q "error"; then
    echo "❌ Protected endpoint failed: $PROTECTED_RESPONSE"
else
    echo "✅ Protected endpoint accessible"
fi

# Test API key creation
echo "Testing API key creation..."
API_KEY_RESPONSE=$(curl -s -X POST "$BASE_URL/api-keys" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test API Key",
        "scopes": ["read", "write"]
    }')

if echo "$API_KEY_RESPONSE" | grep -q "key"; then
    echo "✅ API key creation successful"
    API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.key')
else
    echo "❌ API key creation failed: $API_KEY_RESPONSE"
fi

# Test API key authentication
if [ -n "$API_KEY" ]; then
    echo "Testing API key authentication..."
    API_AUTH_RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" \
        "$BASE_URL/user/profile")
    
    if echo "$API_AUTH_RESPONSE" | grep -q "error"; then
        echo "❌ API key authentication failed: $API_AUTH_RESPONSE"
    else
        echo "✅ API key authentication successful"
    fi
fi

echo "🎉 Authentication system tests completed!"
EOF

    chmod +x auth/scripts/test-auth-system.sh

    print_status "Test scripts created ✅"
}

# Create comprehensive documentation
create_documentation() {
    print_header "Creating documentation..."
    
    cat > auth/README-AUTH-SYSTEM.md << 'EOF'
# Authentication & Authorization System

## 🔐 Overview

This is a comprehensive authentication and authorization system built with best-of-breed FOSS technologies:

- **Identity Provider**: Keycloak for OAuth 2.0/OpenID Connect
- **Multi-Factor Authentication**: TOTP, SMS, Email, WebAuthn
- **Role-Based Access Control**: Fine-grained permissions with Casbin
- **API Key Management**: Automated generation, rotation, and revocation
- **Session Management**: Secure cookie-based sessions with Redis storage

## 🏗️ Architecture

### Core Components
- **Keycloak**: Identity and Access Management
- **Auth Service**: Custom authentication logic and APIs
- **PostgreSQL**: User data and RBAC configuration
- **Redis**: Session storage and caching
- **Casbin**: Policy engine for authorization

### Security Features
- JWT tokens with automatic rotation
- Multi-factor authentication support
- Rate limiting and brute force protection
- Session security with device fingerprinting
- API key scoping and IP restrictions
- Comprehensive audit logging

## 🚀 Quick Start

### 1. Start the System

```bash
# Start all authentication services
docker-compose -f auth/docker-compose.auth.yml up -d

# Wait for services to be ready
sleep 30

# Setup Keycloak realm
./auth/scripts/keycloak/setup-realm.sh
```

### 2. Test the System

```bash
# Run comprehensive tests
./auth/scripts/test-auth-system.sh
```

### 3. Access Points

- **Auth Service API**: http://localhost:3000/api
- **Keycloak Admin**: http://localhost:8080/auth/admin (admin/admin_secure_pass)
- **Grafana Dashboard**: http://localhost:3002 (admin/admin)
- **Prometheus Metrics**: http://localhost:9091
- **MailHog (Email Testing)**: http://localhost:8025

## 🔑 Authentication Methods

### 1. JWT Token Authentication

```bash
# Login to get tokens
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password"
  }'

# Use access token
curl -H "Authorization: Bearer <access_token>" \
  http://localhost:3000/api/user/profile
```

### 2. API Key Authentication

```bash
# Create API key
curl -X POST http://localhost:3000/api/api-keys \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My API Key",
    "scopes": ["read", "write"]
  }'

# Use API key
curl -H "X-API-Key: <api_key>" \
  http://localhost:3000/api/user/profile
```

### 3. OAuth 2.0/OpenID Connect

```bash
# Authorization Code Flow
GET http://localhost:8080/auth/realms/aic-realm/protocol/openid-connect/auth?
  client_id=aic-client&
  response_type=code&
  redirect_uri=http://localhost:3000/callback&
  scope=openid profile email
```

## 🛡️ Multi-Factor Authentication

### Setup TOTP

```bash
curl -X POST http://localhost:3000/api/mfa/setup/totp \
  -H "Authorization: Bearer <access_token>"
```

### Setup SMS MFA

```bash
curl -X POST http://localhost:3000/api/mfa/setup/sms \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "+1234567890"}'
```

### Verify MFA

```bash
curl -X POST http://localhost:3000/api/mfa/verify \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "methodType": "TOTP",
    "code": "123456"
  }'
```

## 🎭 Role-Based Access Control

### Create Role

```bash
curl -X POST http://localhost:3000/api/roles \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "editor",
    "displayName": "Content Editor",
    "description": "Can create and edit content"
  }'
```

### Assign Role to User

```bash
curl -X POST http://localhost:3000/api/users/{userId}/roles \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"roleId": "<role_id>"}'
```

### Check Permissions

```bash
curl -X POST http://localhost:3000/api/permissions/check \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "resource": "articles",
    "action": "create"
  }'
```

## 🔧 API Key Management

### Create API Key

```bash
curl -X POST http://localhost:3000/api/api-keys \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Production API Key",
    "description": "Key for production application",
    "scopes": ["read", "write"],
    "rateLimitPerHour": 1000,
    "rateLimitPerDay": 10000,
    "allowedIps": ["192.168.1.100"],
    "expiresAt": "2024-12-31T23:59:59Z",
    "autoRotate": true,
    "rotationIntervalDays": 90
  }'
```

### Rotate API Key

```bash
curl -X POST http://localhost:3000/api/api-keys/{keyId}/rotate \
  -H "Authorization: Bearer <access_token>"
```

## 📊 Monitoring & Analytics

### Authentication Metrics

- Login success/failure rates
- MFA usage statistics
- API key usage patterns
- Session duration analytics
- Geographic login distribution

### Security Alerts

- Failed login attempts
- Suspicious login patterns
- API key misuse
- Session anomalies
- Permission violations

## 🔒 Security Best Practices

### Password Policy
- Minimum 8 characters
- Must include uppercase, lowercase, numbers, and symbols
- Password history enforcement
- Regular password expiration

### Session Security
- Secure, HttpOnly, SameSite cookies
- Session timeout and renewal
- Device fingerprinting
- IP address validation

### API Security
- Rate limiting per endpoint
- Scope-based access control
- IP and domain restrictions
- Automatic key rotation

## 🧪 Testing

### Unit Tests
```bash
cd auth/services/auth-service
npm test
```

### Integration Tests
```bash
./auth/scripts/test-auth-system.sh
```

### Load Testing
```bash
# Install k6
curl https://github.com/grafana/k6/releases/download/v0.45.0/k6-v0.45.0-linux-amd64.tar.gz -L | tar xvz --strip-components 1

# Run load test
k6 run auth/scripts/load-test.js
```

## 🔧 Configuration

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://auth_admin:auth_secure_pass@postgres-auth:5432/auth_system
REDIS_URL=redis://redis-auth:6379

# Keycloak
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_REALM=aic-realm
KEYCLOAK_CLIENT_ID=aic-client
KEYCLOAK_CLIENT_SECRET=your-client-secret

# JWT
JWT_SECRET=your-super-secure-jwt-secret-key-here
JWT_REFRESH_SECRET=your-super-secure-refresh-secret-key-here

# Security
BCRYPT_ROUNDS=12
MAX_FAILED_ATTEMPTS=5
LOCKOUT_DURATION=900000
SESSION_TIMEOUT=3600000

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

### Keycloak Configuration

- Realm: `aic-realm`
- Client: `aic-client`
- Supported flows: Authorization Code, Direct Access Grants
- Token settings: Access token lifespan, refresh token lifespan
- Security settings: Brute force protection, password policy

## 📚 API Documentation

### Authentication Endpoints

- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/logout` - User logout
- `POST /api/auth/refresh` - Refresh access token
- `POST /api/auth/forgot-password` - Password reset request
- `POST /api/auth/reset-password` - Password reset confirmation

### MFA Endpoints

- `POST /api/mfa/setup/totp` - Setup TOTP MFA
- `POST /api/mfa/setup/sms` - Setup SMS MFA
- `POST /api/mfa/setup/email` - Setup Email MFA
- `POST /api/mfa/verify` - Verify MFA code
- `DELETE /api/mfa/disable` - Disable MFA

### RBAC Endpoints

- `GET /api/roles` - List roles
- `POST /api/roles` - Create role
- `GET /api/permissions` - List permissions
- `POST /api/permissions/check` - Check permission
- `POST /api/users/{id}/roles` - Assign role to user

### API Key Endpoints

- `GET /api/api-keys` - List API keys
- `POST /api/api-keys` - Create API key
- `PUT /api/api-keys/{id}` - Update API key
- `DELETE /api/api-keys/{id}` - Delete API key
- `POST /api/api-keys/{id}/rotate` - Rotate API key

This authentication system provides enterprise-grade security with comprehensive features for modern applications.
EOF

    print_status "Documentation created ✅"
}

# Main setup function
main() {
    print_header "Starting Authentication & Authorization System Setup"
    
    check_dependencies
    create_directories
    setup_configurations
    setup_keycloak_config
    setup_monitoring
    setup_test_scripts
    create_documentation
    
    print_status "Authentication system setup completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Start services: docker-compose -f auth/docker-compose.auth.yml up -d"
    echo "2. Setup Keycloak: ./auth/scripts/keycloak/setup-realm.sh"
    echo "3. Test system: ./auth/scripts/test-auth-system.sh"
    echo ""
    echo "Access points:"
    echo "- Auth Service API: http://localhost:3000/api"
    echo "- Keycloak Admin: http://localhost:8080/auth/admin (admin/admin_secure_pass)"
    echo "- Grafana Dashboard: http://localhost:3002 (admin/admin)"
    echo "- Prometheus Metrics: http://localhost:9091"
    echo "- MailHog (Email Testing): http://localhost:8025"
}

# Run main function
main "$@"
