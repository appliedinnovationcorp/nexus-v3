#!/bin/bash

set -e

echo "📋 Setting up Compliance System..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Create directory structure
create_directories() {
    print_header "Creating directory structure..."
    
    mkdir -p compliance/{config,scripts,services,dags,reports,docs}
    mkdir -p compliance/config/{logstash,opa,airflow,grafana-compliance/{dashboards,datasources},prometheus-compliance}
    mkdir -p compliance/services/{compliance-service,anonymization-service,consent-service,audit-service}
    mkdir -p compliance/scripts/{gdpr,soc2,audit,retention}
    mkdir -p compliance/reports/{gdpr,soc2,audit,retention}
    
    print_status "Directory structure created ✅"
}

# Setup configuration files
setup_configurations() {
    print_header "Setting up configuration files..."
    
    # Logstash configuration
    cat > compliance/config/logstash/logstash.conf << 'EOF'
input {
  beats {
    port => 5044
  }
  
  kafka {
    bootstrap_servers => "kafka:29092"
    topics => ["audit-events", "compliance-events"]
    codec => json
  }
  
  http {
    port => 8080
    codec => json
  }
}

filter {
  if [event_type] == "audit" {
    mutate {
      add_field => { "[@metadata][index]" => "audit-logs" }
    }
  } else if [event_type] == "compliance" {
    mutate {
      add_field => { "[@metadata][index]" => "compliance-logs" }
    }
  }
  
  # Add compliance classification
  if [data_classification] {
    mutate {
      add_field => { "compliance_required" => "true" }
    }
  }
  
  # GDPR data subject identification
  if [user_id] or [email] or [personal_data] {
    mutate {
      add_field => { "gdpr_relevant" => "true" }
    }
  }
  
  # SOC 2 control mapping
  if [control_id] {
    mutate {
      add_field => { "soc2_control" => "%{control_id}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "%{[@metadata][index]}-%{+YYYY.MM.dd}"
  }
  
  # Send to compliance monitoring
  if [compliance_required] == "true" {
    http {
      url => "http://compliance-service:3000/api/events"
      http_method => "post"
      format => "json"
    }
  }
}
EOF

    # OPA policies
    cat > compliance/config/opa/policies/gdpr.rego << 'EOF'
package gdpr

# GDPR Compliance Policies

# Data processing lawful basis check
allow_processing {
    input.lawful_basis
    input.lawful_basis != ""
    valid_lawful_basis[input.lawful_basis]
}

valid_lawful_basis := {
    "consent",
    "contract",
    "legal_obligation",
    "vital_interests",
    "public_task",
    "legitimate_interests"
}

# Consent validation
valid_consent {
    input.consent.given == true
    input.consent.withdrawn == false
    input.consent.method != "pre_ticked"
    input.consent.specific == true
}

# Data retention compliance
retention_compliant {
    input.retention_period > 0
    input.data_age <= input.retention_period
    not legal_hold_active
}

legal_hold_active {
    input.legal_holds[_].status == "active"
}

# Data subject rights
allow_data_access {
    input.request_type == "access"
    input.identity_verified == true
}

allow_data_deletion {
    input.request_type == "deletion"
    input.identity_verified == true
    not legal_hold_active
    not legitimate_interest_override
}

legitimate_interest_override {
    input.processing_purpose == "legal_compliance"
}
EOF

    print_status "Configuration files created ✅"
}

# Setup compliance database schema
setup_database_schema() {
    print_header "Setting up compliance database schema..."
    
    cat > compliance/scripts/init-compliance-db.sql << 'EOF'
-- Compliance Database Schema

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS compliance;
CREATE SCHEMA IF NOT EXISTS gdpr;
CREATE SCHEMA IF NOT EXISTS soc2;
CREATE SCHEMA IF NOT EXISTS audit;

-- GDPR Tables
CREATE TABLE gdpr.data_subjects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    nationality VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE gdpr.consent_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    data_subject_id UUID REFERENCES gdpr.data_subjects(id),
    purpose VARCHAR(255) NOT NULL,
    lawful_basis VARCHAR(50) NOT NULL,
    consent_given BOOLEAN NOT NULL,
    consent_withdrawn BOOLEAN DEFAULT FALSE,
    consent_date TIMESTAMP WITH TIME ZONE NOT NULL,
    withdrawal_date TIMESTAMP WITH TIME ZONE,
    consent_method VARCHAR(50) NOT NULL,
    consent_version VARCHAR(20) DEFAULT '1.0',
    processing_categories TEXT[],
    data_categories TEXT[],
    retention_period INTEGER,
    third_party_sharing BOOLEAN DEFAULT FALSE,
    third_parties TEXT[],
    metadata JSONB DEFAULT '{}'
);

CREATE TABLE gdpr.data_processing_activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    data_subject_id UUID REFERENCES gdpr.data_subjects(id),
    activity_type VARCHAR(100) NOT NULL,
    purpose VARCHAR(255) NOT NULL,
    lawful_basis VARCHAR(50) NOT NULL,
    data_categories TEXT[],
    processing_methods TEXT[],
    retention_period INTEGER,
    third_party_involvement BOOLEAN DEFAULT FALSE,
    cross_border_transfer BOOLEAN DEFAULT FALSE,
    safeguards TEXT[],
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

-- SOC 2 Tables
CREATE TABLE soc2.controls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category VARCHAR(50) NOT NULL,
    control_id VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    risk_level VARCHAR(20) DEFAULT 'MEDIUM',
    control_type VARCHAR(20) NOT NULL,
    frequency VARCHAR(20) NOT NULL,
    owner VARCHAR(100) NOT NULL,
    implementation_status VARCHAR(30) DEFAULT 'NOT_IMPLEMENTED',
    testing_status VARCHAR(30) DEFAULT 'NOT_TESTED',
    last_tested TIMESTAMP WITH TIME ZONE,
    next_test_due TIMESTAMP WITH TIME ZONE,
    evidence_required TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE soc2.evidence (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    control_id UUID REFERENCES soc2.controls(id),
    evidence_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    file_path VARCHAR(500),
    collected_by VARCHAR(100) NOT NULL,
    collected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewed_by VARCHAR(100),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    approved BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'
);

-- Audit Tables
CREATE TABLE audit.events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    user_id UUID,
    session_id UUID,
    resource VARCHAR(200),
    action VARCHAR(100),
    result VARCHAR(20) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    request_id VARCHAR(100),
    correlation_id VARCHAR(100),
    event_data JSONB,
    risk_score INTEGER,
    compliance_tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Compliance Tables
CREATE TABLE compliance.data_retention_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    retention_period_days INTEGER NOT NULL,
    policy_reason VARCHAR(255),
    legal_basis VARCHAR(100),
    anonymization_required BOOLEAN DEFAULT FALSE,
    created_by VARCHAR(100) NOT NULL,
    approved_by VARCHAR(100),
    effective_date DATE NOT NULL,
    review_date DATE,
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE compliance.legal_holds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID,
    hold_reason TEXT NOT NULL,
    case_number VARCHAR(100),
    created_by VARCHAR(100) NOT NULL,
    approved_by VARCHAR(100),
    status VARCHAR(20) DEFAULT 'ACTIVE',
    expiration_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX idx_consent_records_data_subject ON gdpr.consent_records(data_subject_id);
CREATE INDEX idx_consent_records_purpose ON gdpr.consent_records(purpose);
CREATE INDEX idx_processing_activities_data_subject ON gdpr.data_processing_activities(data_subject_id);
CREATE INDEX idx_controls_category ON soc2.controls(category);
CREATE INDEX idx_controls_owner ON soc2.controls(owner);
CREATE INDEX idx_audit_events_type ON audit.events(event_type);
CREATE INDEX idx_audit_events_user ON audit.events(user_id);
CREATE INDEX idx_audit_events_created_at ON audit.events(created_at);
CREATE INDEX idx_legal_holds_table ON compliance.legal_holds(table_name);
CREATE INDEX idx_legal_holds_status ON compliance.legal_holds(status);
EOF

    print_status "Database schema created ✅"
}

# Setup monitoring dashboards
setup_monitoring() {
    print_header "Setting up compliance monitoring..."
    
    # Prometheus configuration
    cat > compliance/config/prometheus-compliance/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'compliance-service'
    static_configs:
      - targets: ['compliance-service:3000']
    metrics_path: '/metrics'

  - job_name: 'anonymization-service'
    static_configs:
      - targets: ['anonymization-service:3000']
    metrics_path: '/metrics'

  - job_name: 'consent-service'
    static_configs:
      - targets: ['consent-service:3000']
    metrics_path: '/metrics'

  - job_name: 'audit-service'
    static_configs:
      - targets: ['audit-service:3000']
    metrics_path: '/metrics'

  - job_name: 'elasticsearch'
    static_configs:
      - targets: ['elasticsearch:9200']
    metrics_path: '/_prometheus/metrics'
EOF

    # Grafana datasource
    cat > compliance/config/grafana-compliance/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-compliance:9090
    isDefault: true
    editable: true

  - name: Elasticsearch
    type: elasticsearch
    access: proxy
    url: http://elasticsearch:9200
    database: "audit-logs-*"
    timeField: "@timestamp"
    editable: true
EOF

    print_status "Monitoring configuration created ✅"
}

# Create documentation
create_documentation() {
    print_header "Creating documentation..."
    
    cat > compliance/README-COMPLIANCE-SYSTEM.md << 'EOF'
# Compliance System

## 🏛️ Overview

Comprehensive compliance solution with GDPR, SOC 2 Type II, audit logging, data retention, and privacy by design.

### Key Features
- **GDPR Compliance**: Data anonymization, consent management, data subject rights
- **SOC 2 Type II**: Security controls framework with continuous monitoring
- **Audit Logging**: Immutable audit trails with tamper-proof logging
- **Data Retention**: Automated data lifecycle management and purging
- **Privacy by Design**: Built-in privacy controls and data minimization

## 🚀 Quick Start

```bash
# Start compliance infrastructure
docker-compose -f compliance/docker-compose.compliance.yml up -d

# Initialize database
docker exec postgres-compliance psql -U compliance_admin -d compliance_db -f /docker-entrypoint-initdb.d/init-compliance-db.sql

# Access dashboards
# - Kibana: http://localhost:5601
# - Airflow: http://localhost:8081
# - Grafana: http://localhost:3004
```

## 📊 Compliance Dashboards

### GDPR Dashboard
- Data subject requests tracking
- Consent management overview
- Data processing activities
- Retention policy compliance
- Privacy impact assessments

### SOC 2 Dashboard
- Control effectiveness monitoring
- Evidence collection status
- Finding remediation tracking
- Compliance posture overview
- Audit readiness metrics

### Audit Dashboard
- Real-time event monitoring
- Compliance event correlation
- Risk scoring and alerting
- Forensic investigation tools
- Compliance reporting

## 🔧 Configuration

### Environment Variables
```bash
# Database
DATABASE_URL=postgresql://compliance_admin:compliance_secure_pass@postgres-compliance:5432/compliance_db

# Elasticsearch
ELASTICSEARCH_URL=http://elasticsearch:9200

# Services
GDPR_ANONYMIZATION_ENABLED=true
SOC2_MONITORING_ENABLED=true
AUDIT_LOGGING_ENABLED=true
DATA_RETENTION_ENABLED=true
```

This compliance system provides enterprise-grade compliance capabilities using 100% FOSS technologies.
EOF

    print_status "Documentation created ✅"
}

# Main setup function
main() {
    print_header "Starting Compliance System Setup"
    
    check_dependencies
    create_directories
    setup_configurations
    setup_database_schema
    setup_monitoring
    create_documentation
    
    print_status "Compliance system setup completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Start services: docker-compose -f compliance/docker-compose.compliance.yml up -d"
    echo "2. Initialize database: Run the SQL initialization script"
    echo "3. Configure Airflow DAGs for data retention"
    echo ""
    echo "Access points:"
    echo "- Kibana (Audit Logs): http://localhost:5601"
    echo "- Airflow (Data Retention): http://localhost:8081"
    echo "- Grafana (Compliance Metrics): http://localhost:3004"
    echo "- Compliance Service: http://localhost:3020"
}

main "$@"
