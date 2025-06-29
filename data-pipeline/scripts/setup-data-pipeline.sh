#!/bin/bash

# Enterprise Data Pipeline Setup Script
# Comprehensive data analytics with 100% FOSS technologies

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
    
    # Check available disk space (minimum 50GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 52428800 ]; then
        warn "Less than 50GB disk space available. Data pipeline may require more space."
    fi
    
    # Check available memory (minimum 32GB recommended)
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_memory" -lt 32768 ]; then
        warn "Less than 32GB RAM available. Performance may be impacted with big data processing."
    fi
    
    log "Prerequisites check completed"
}

# Initialize configuration files
init_configs() {
    log "Initializing configuration files..."
    
    # Create directory structure
    mkdir -p config/{clickhouse,airflow,superset,prometheus,grafana/{data-pipeline-provisioning,data-pipeline-dashboards},event-tracker,analytics-engine,ab-testing,journey-analytics,data-quality}
    mkdir -p docker/{airflow,superset,event-tracker,analytics-engine,ab-testing-service,journey-analytics,data-quality-monitor}
    mkdir -p airflow/{dags,logs,plugins}
    mkdir -p spark/{jobs,jars}
    mkdir -p sql
    mkdir -p logs
    
    # ClickHouse configuration
    cat > config/clickhouse/config.xml << 'EOF'
<?xml version="1.0"?>
<clickhouse>
    <logger>
        <level>information</level>
        <console>true</console>
    </logger>
    
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    
    <listen_host>0.0.0.0</listen_host>
    
    <max_connections>4096</max_connections>
    <keep_alive_timeout>3</keep_alive_timeout>
    <max_concurrent_queries>100</max_concurrent_queries>
    <uncompressed_cache_size>8589934592</uncompressed_cache_size>
    <mark_cache_size>5368709120</mark_cache_size>
    
    <path>/var/lib/clickhouse/</path>
    <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
    <user_files_path>/var/lib/clickhouse/user_files/</user_files_path>
    
    <users_config>users.xml</users_config>
    
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    
    <timezone>UTC</timezone>
    
    <mlock_executable>false</mlock_executable>
    
    <remote_servers>
        <analytics_cluster>
            <shard>
                <replica>
                    <host>clickhouse</host>
                    <port>9000</port>
                </replica>
            </shard>
        </analytics_cluster>
    </remote_servers>
    
    <zookeeper incl="zookeeper-servers" optional="true" />
    
    <macros incl="macros" optional="true" />
    
    <builtin_dictionaries_reload_interval>3600</builtin_dictionaries_reload_interval>
    
    <max_session_timeout>3600</max_session_timeout>
    <default_session_timeout>60</default_session_timeout>
    
    <query_log>
        <database>system</database>
        <table>query_log</table>
        <partition_by>toYYYYMM(event_date)</partition_by>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </query_log>
    
    <trace_log>
        <database>system</database>
        <table>trace_log</table>
        <partition_by>toYYYYMM(event_date)</partition_by>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </trace_log>
</clickhouse>
EOF

    cat > config/clickhouse/users.xml << 'EOF'
<?xml version="1.0"?>
<clickhouse>
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
        </default>
        
        <readonly>
            <readonly>1</readonly>
        </readonly>
    </profiles>
    
    <users>
        <default>
            <password></password>
            <networks incl="networks" />
            <profile>default</profile>
            <quota>default</quota>
        </default>
        
        <analytics_user>
            <password>analytics_password</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <databases>
                <database>analytics</database>
            </databases>
        </analytics_user>
    </users>
    
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF

    # Superset configuration
    cat > config/superset/superset_config.py << 'EOF'
import os
from cachelib.redis import RedisCache

# Database configuration
SQLALCHEMY_DATABASE_URI = 'postgresql://superset:superset@superset-postgres:5432/superset'

# Redis configuration
REDIS_HOST = 'superset-redis'
REDIS_PORT = 6379
REDIS_DB = 0

# Cache configuration
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': REDIS_HOST,
    'CACHE_REDIS_PORT': REDIS_PORT,
    'CACHE_REDIS_DB': REDIS_DB,
}

# Feature flags
FEATURE_FLAGS = {
    'ENABLE_TEMPLATE_PROCESSING': True,
    'DASHBOARD_NATIVE_FILTERS': True,
    'DASHBOARD_CROSS_FILTERS': True,
    'DASHBOARD_RBAC': True,
    'ENABLE_EXPLORE_JSON_CSRF_PROTECTION': True,
    'ENABLE_EXPLORE_DRAG_AND_DROP': True,
    'GLOBAL_ASYNC_QUERIES': True,
    'VERSIONED_EXPORT': True,
}

# Security
SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'your-secret-key-here')
WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = None

# Async query configuration
RESULTS_BACKEND = RedisCache(
    host=REDIS_HOST,
    port=REDIS_PORT,
    db=1,
    key_prefix='superset_results'
)

# Email configuration (optional)
SMTP_HOST = 'localhost'
SMTP_STARTTLS = True
SMTP_SSL = False
SMTP_USER = 'superset'
SMTP_PORT = 25
SMTP_PASSWORD = 'superset'
SMTP_MAIL_FROM = 'superset@localhost'

# Webdriver configuration for reports
WEBDRIVER_BASEURL = 'http://superset:8088/'
WEBDRIVER_BASEURL_USER_FRIENDLY = 'http://localhost:8088/'

# Custom security manager (optional)
# CUSTOM_SECURITY_MANAGER = CustomSecurityManager

# Database connections
DATABASES = {
    'clickhouse': {
        'engine': 'clickhouse+native',
        'host': 'clickhouse',
        'port': 9000,
        'database': 'analytics',
        'username': 'analytics_user',
        'password': 'analytics_password',
    }
}
EOF

    # Airflow DAG for ETL pipeline
    cat > airflow/dags/analytics_etl_pipeline.py << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.http.sensors.http import HttpSensor

default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'analytics_etl_pipeline',
    default_args=default_args,
    description='Analytics ETL Pipeline',
    schedule_interval=timedelta(hours=1),
    catchup=False,
    tags=['analytics', 'etl'],
)

def extract_events_data(**context):
    """Extract events data from Kafka topics"""
    import json
    from kafka import KafkaConsumer
    
    consumer = KafkaConsumer(
        'user_events',
        'page_views',
        'conversions',
        bootstrap_servers=['kafka:29092'],
        value_deserializer=lambda x: json.loads(x.decode('utf-8'))
    )
    
    events = []
    for message in consumer:
        events.append(message.value)
        if len(events) >= 1000:  # Batch processing
            break
    
    return events

def transform_events_data(**context):
    """Transform and clean events data"""
    events = context['task_instance'].xcom_pull(task_ids='extract_events')
    
    transformed_events = []
    for event in events:
        # Data cleaning and transformation logic
        transformed_event = {
            'user_id': event.get('user_id'),
            'event_type': event.get('event_type'),
            'timestamp': event.get('timestamp'),
            'properties': event.get('properties', {}),
            'session_id': event.get('session_id'),
            'page_url': event.get('page_url'),
            'referrer': event.get('referrer'),
        }
        transformed_events.append(transformed_event)
    
    return transformed_events

def load_to_clickhouse(**context):
    """Load transformed data to ClickHouse"""
    import clickhouse_connect
    
    events = context['task_instance'].xcom_pull(task_ids='transform_events')
    
    client = clickhouse_connect.get_client(
        host='clickhouse',
        port=8123,
        database='analytics',
        username='analytics_user',
        password='analytics_password'
    )
    
    # Insert data into ClickHouse
    client.insert('events', events)
    
    return len(events)

# Define tasks
extract_task = PythonOperator(
    task_id='extract_events',
    python_callable=extract_events_data,
    dag=dag,
)

transform_task = PythonOperator(
    task_id='transform_events',
    python_callable=transform_events_data,
    dag=dag,
)

load_task = PythonOperator(
    task_id='load_to_clickhouse',
    python_callable=load_to_clickhouse,
    dag=dag,
)

# Health check task
health_check = HttpSensor(
    task_id='clickhouse_health_check',
    http_conn_id='clickhouse_default',
    endpoint='ping',
    timeout=20,
    poke_interval=5,
    dag=dag,
)

# Aggregation task
aggregate_task = BashOperator(
    task_id='run_aggregations',
    bash_command='spark-submit --master spark://spark-master:7077 /opt/spark-jobs/daily_aggregations.py',
    dag=dag,
)

# Set task dependencies
health_check >> extract_task >> transform_task >> load_task >> aggregate_task
EOF

    # Prometheus configuration for data pipeline
    cat > config/prometheus/data-pipeline-prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  # Data pipeline services
  - job_name: 'data-pipeline-services'
    static_configs:
      - targets:
        - 'event-tracker:3500'
        - 'analytics-engine:3501'
        - 'ab-testing-service:3502'
        - 'journey-analytics:3503'
        - 'data-quality-monitor:3504'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # ClickHouse metrics
  - job_name: 'clickhouse'
    static_configs:
      - targets: ['clickhouse:8123']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Kafka metrics
  - job_name: 'kafka'
    static_configs:
      - targets: ['kafka:9092']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Spark metrics
  - job_name: 'spark'
    static_configs:
      - targets: 
        - 'spark-master:8080'
        - 'spark-worker-1:8081'
        - 'spark-worker-2:8081'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Airflow metrics
  - job_name: 'airflow'
    static_configs:
      - targets: ['airflow-webserver:8080']
    metrics_path: '/admin/metrics'
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
    
    # Airflow Dockerfile
    cat > docker/airflow/Dockerfile << 'EOF'
FROM apache/airflow:2.7.2-python3.11

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Install additional Python packages
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# Copy custom plugins and configurations
COPY plugins/ /opt/airflow/plugins/
COPY config/ /opt/airflow/config/
EOF

    cat > docker/airflow/requirements.txt << 'EOF'
apache-airflow-providers-postgres==5.7.1
apache-airflow-providers-redis==3.4.0
apache-airflow-providers-http==4.6.0
clickhouse-connect==0.6.19
kafka-python==2.0.2
pandas==2.1.3
numpy==1.24.3
scipy==1.11.4
scikit-learn==1.3.2
EOF

    # Event Tracker Dockerfile
    cat > docker/event-tracker/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

EXPOSE 3500

CMD ["node", "src/index.js"]
EOF

    cat > docker/event-tracker/package.json << 'EOF'
{
  "name": "event-tracker",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "compression": "^1.7.4",
    "kafkajs": "^2.2.4",
    "@clickhouse/client": "^0.2.5",
    "redis": "^4.6.0",
    "joi": "^17.11.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "uuid": "^9.0.0",
    "geoip-lite": "^1.4.7",
    "user-agent-parser": "^0.7.33"
  }
}
EOF

    log "Docker images configuration created"
}

# Setup ClickHouse schema
setup_clickhouse_schema() {
    log "Setting up ClickHouse schema..."
    
    cat > sql/clickhouse-init.sql << 'EOF'
-- Create analytics database
CREATE DATABASE IF NOT EXISTS analytics;

-- Use analytics database
USE analytics;

-- Events table for raw event data
CREATE TABLE IF NOT EXISTS events (
    event_id String,
    user_id String,
    session_id String,
    event_type String,
    timestamp DateTime64(3),
    page_url String,
    referrer String,
    user_agent String,
    ip_address String,
    country String,
    city String,
    properties String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (event_type, user_id, timestamp)
SETTINGS index_granularity = 8192;

-- Page views table
CREATE TABLE IF NOT EXISTS page_views (
    view_id String,
    user_id String,
    session_id String,
    page_url String,
    page_title String,
    referrer String,
    timestamp DateTime64(3),
    duration_seconds UInt32,
    scroll_depth Float32,
    user_agent String,
    ip_address String,
    country String,
    city String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp)
SETTINGS index_granularity = 8192;

-- User sessions table
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id String,
    user_id String,
    start_time DateTime64(3),
    end_time DateTime64(3),
    duration_seconds UInt32,
    page_views UInt32,
    events UInt32,
    bounce Boolean,
    conversion Boolean,
    utm_source String,
    utm_medium String,
    utm_campaign String,
    referrer String,
    landing_page String,
    exit_page String,
    user_agent String,
    ip_address String,
    country String,
    city String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(start_time)
ORDER BY (user_id, start_time)
SETTINGS index_granularity = 8192;

-- Conversions table
CREATE TABLE IF NOT EXISTS conversions (
    conversion_id String,
    user_id String,
    session_id String,
    event_type String,
    conversion_value Float64,
    currency String,
    timestamp DateTime64(3),
    attribution_source String,
    attribution_medium String,
    attribution_campaign String,
    funnel_step String,
    properties String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp)
SETTINGS index_granularity = 8192;

-- A/B test results table
CREATE TABLE IF NOT EXISTS ab_test_results (
    test_id String,
    variant_id String,
    user_id String,
    session_id String,
    assignment_time DateTime64(3),
    conversion_time Nullable(DateTime64(3)),
    converted Boolean,
    conversion_value Float64,
    properties String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(assignment_time)
ORDER BY (test_id, variant_id, user_id)
SETTINGS index_granularity = 8192;

-- User journey events table
CREATE TABLE IF NOT EXISTS user_journey_events (
    journey_id String,
    user_id String,
    session_id String,
    step_number UInt32,
    step_name String,
    step_type String,
    timestamp DateTime64(3),
    duration_seconds UInt32,
    success Boolean,
    properties String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, journey_id, step_number)
SETTINGS index_granularity = 8192;

-- Daily aggregations materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_events_mv
TO daily_events_summary
AS SELECT
    toDate(timestamp) as date,
    event_type,
    country,
    count() as event_count,
    uniq(user_id) as unique_users,
    uniq(session_id) as unique_sessions
FROM events
GROUP BY date, event_type, country;

-- Create summary table for materialized view
CREATE TABLE IF NOT EXISTS daily_events_summary (
    date Date,
    event_type String,
    country String,
    event_count UInt64,
    unique_users UInt64,
    unique_sessions UInt64
) ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, event_type, country)
SETTINGS index_granularity = 8192;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_events_user_id ON events (user_id) TYPE bloom_filter GRANULARITY 1;
CREATE INDEX IF NOT EXISTS idx_events_session_id ON events (session_id) TYPE bloom_filter GRANULARITY 1;
CREATE INDEX IF NOT EXISTS idx_page_views_user_id ON page_views (user_id) TYPE bloom_filter GRANULARITY 1;
CREATE INDEX IF NOT EXISTS idx_conversions_user_id ON conversions (user_id) TYPE bloom_filter GRANULARITY 1;
EOF

    log "ClickHouse schema configured"
}

# Start services
start_services() {
    log "Starting Data Pipeline services..."
    
    # Setup ClickHouse schema
    setup_clickhouse_schema
    
    # Pull required images
    docker-compose -f docker-compose.data-pipeline.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.data-pipeline.yml build
    
    # Start services in stages
    log "Starting foundational services..."
    docker-compose -f docker-compose.data-pipeline.yml up -d zookeeper
    sleep 20
    
    log "Starting Kafka..."
    docker-compose -f docker-compose.data-pipeline.yml up -d kafka
    sleep 30
    
    log "Starting data warehouse..."
    docker-compose -f docker-compose.data-pipeline.yml up -d clickhouse
    sleep 30
    
    log "Starting Airflow services..."
    docker-compose -f docker-compose.data-pipeline.yml up -d postgres-airflow redis-airflow
    sleep 20
    docker-compose -f docker-compose.data-pipeline.yml up -d airflow-webserver airflow-scheduler airflow-worker
    sleep 30
    
    log "Starting Spark cluster..."
    docker-compose -f docker-compose.data-pipeline.yml up -d spark-master spark-worker-1 spark-worker-2
    sleep 30
    
    log "Starting analytics services..."
    docker-compose -f docker-compose.data-pipeline.yml up -d event-tracker analytics-engine ab-testing-service journey-analytics
    sleep 30
    
    log "Starting BI and monitoring..."
    docker-compose -f docker-compose.data-pipeline.yml up -d superset-postgres superset-redis superset
    docker-compose -f docker-compose.data-pipeline.yml up -d data-pipeline-prometheus data-pipeline-grafana
    sleep 30
    
    log "Starting remaining services..."
    docker-compose -f docker-compose.data-pipeline.yml up -d kafka-ui schema-registry kafka-connect data-quality-monitor
    
    log "Waiting for services to be ready..."
    sleep 90
    
    # Health checks
    check_service_health "Kafka" "http://localhost:9092"
    check_service_health "ClickHouse" "http://localhost:8123/ping"
    check_service_health "Airflow" "http://localhost:8081"
    check_service_health "Spark Master" "http://localhost:8082"
    check_service_health "Superset" "http://localhost:8088"
    check_service_health "Event Tracker" "http://localhost:3500/health"
    check_service_health "Analytics Engine" "http://localhost:3501/health"
    check_service_health "A/B Testing Service" "http://localhost:3502/health"
    check_service_health "Journey Analytics" "http://localhost:3503/health"
    check_service_health "Data Quality Monitor" "http://localhost:3504/health"
    check_service_health "Data Pipeline Grafana" "http://localhost:3310"
    check_service_health "Kafka UI" "http://localhost:8080"
    
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
    log "Data Pipeline System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Kafka UI:${NC} http://localhost:8080"
    echo -e "${GREEN}Airflow:${NC} http://localhost:8081 (admin/admin)"
    echo -e "${GREEN}Spark Master:${NC} http://localhost:8082"
    echo -e "${GREEN}Spark Worker 1:${NC} http://localhost:8083"
    echo -e "${GREEN}Spark Worker 2:${NC} http://localhost:8084"
    echo -e "${GREEN}Schema Registry:${NC} http://localhost:8085"
    echo -e "${GREEN}Kafka Connect:${NC} http://localhost:8086"
    echo -e "${GREEN}Superset:${NC} http://localhost:8088 (admin/admin)"
    echo -e "${GREEN}Data Pipeline Grafana:${NC} http://localhost:3310 (admin/admin)"
    echo -e "${GREEN}Data Pipeline Prometheus:${NC} http://localhost:9098"
    echo
    echo -e "${BLUE}=== API ENDPOINTS ===${NC}"
    echo -e "${GREEN}Event Tracker:${NC} http://localhost:3500"
    echo -e "${GREEN}Analytics Engine:${NC} http://localhost:3501"
    echo -e "${GREEN}A/B Testing Service:${NC} http://localhost:3502"
    echo -e "${GREEN}Journey Analytics:${NC} http://localhost:3503"
    echo -e "${GREEN}Data Quality Monitor:${NC} http://localhost:3504"
    echo
    echo -e "${BLUE}=== DATABASE CONNECTIONS ===${NC}"
    echo "ClickHouse: http://localhost:8123 (analytics_user/analytics_password)"
    echo "ClickHouse Native: localhost:9000"
    echo "Kafka: localhost:9092"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Send events to Event Tracker at http://localhost:3500/track"
    echo "2. View real-time analytics in Superset at http://localhost:8088"
    echo "3. Monitor data pipeline in Grafana at http://localhost:3310"
    echo "4. Manage ETL workflows in Airflow at http://localhost:8081"
    echo "5. Analyze big data with Spark at http://localhost:8082"
    echo "6. Set up A/B tests at http://localhost:3502"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Data Pipeline Setup..."
    
    check_prerequisites
    init_configs
    build_images
    start_services
    show_access_info
    
    log "Data Pipeline setup completed successfully!"
}

# Execute main function
main "$@"
