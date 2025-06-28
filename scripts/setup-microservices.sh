#!/bin/bash

set -e

echo "🚀 Setting up Microservices Architecture with DDD..."

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

# Check if Docker and Docker Compose are installed
check_dependencies() {
    print_header "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_status "Dependencies check passed ✅"
}

# Create necessary directories
create_directories() {
    print_header "Creating directory structure..."
    
    mkdir -p services/{user-domain,order-domain,inventory-domain,payment-domain,notification-domain,shared-kernel}/{src,tests}
    mkdir -p services/user-domain/src/{domain,application/{commands,queries,ports},infrastructure,presentation}
    mkdir -p services/order-domain/src/{domain,application/{commands,queries,ports},infrastructure,presentation}
    mkdir -p services/inventory-domain/src/{domain,application/{commands,queries,ports},infrastructure,presentation}
    mkdir -p infrastructure/{kong,kuma,monitoring/{prometheus,grafana/{dashboards,datasources}}}
    mkdir -p scripts/kafka
    
    print_status "Directory structure created ✅"
}

# Setup Kafka topics
setup_kafka_topics() {
    print_header "Setting up Kafka topics..."
    
    cat > scripts/kafka/create-topics.sh << 'EOF'
#!/bin/bash

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
sleep 30

# Create topics
docker exec kafka kafka-topics --create --topic user-domain --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic order-domain --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic inventory-domain --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic payment-domain --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic notification-domain --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists

# Create dead letter queue topics
docker exec kafka kafka-topics --create --topic user-domain-dlq --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic order-domain-dlq --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists
docker exec kafka kafka-topics --create --topic inventory-domain-dlq --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists

echo "Kafka topics created successfully!"
EOF

    chmod +x scripts/kafka/create-topics.sh
    print_status "Kafka topics setup script created ✅"
}

# Setup Kong configuration
setup_kong_config() {
    print_header "Setting up Kong configuration..."
    
    cat > scripts/setup-kong.sh << 'EOF'
#!/bin/bash

echo "Configuring Kong Gateway..."

# Wait for Kong to be ready
sleep 10

# Apply Kong configuration
docker exec kong kong config db_import /kong.yml

echo "Kong configuration applied successfully!"
EOF

    chmod +x scripts/setup-kong.sh
    print_status "Kong configuration script created ✅"
}

# Setup Grafana dashboards
setup_grafana_dashboards() {
    print_header "Setting up Grafana dashboards..."
    
    # Create datasource configuration
    cat > infrastructure/monitoring/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Create dashboard provisioning config
    cat > infrastructure/monitoring/grafana/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    print_status "Grafana configuration created ✅"
}

# Setup database schemas
setup_database_schemas() {
    print_header "Setting up database schemas..."
    
    cat > scripts/setup-databases.sh << 'EOF'
#!/bin/bash

echo "Setting up database schemas..."

# Wait for databases to be ready
sleep 15

# User domain schema
docker exec postgres-user psql -U user_service -d user_domain -c "
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    last_login_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
"

# Order domain schema
docker exec postgres-order psql -U order_service -d order_domain -c "
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
"

# Inventory domain schema
docker exec postgres-inventory psql -U inventory_service -d inventory_domain -c "
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
"

echo "Database schemas created successfully!"
EOF

    chmod +x scripts/setup-databases.sh
    print_status "Database setup script created ✅"
}

# Main setup function
main() {
    print_header "Starting Microservices Architecture Setup"
    
    check_dependencies
    create_directories
    setup_kafka_topics
    setup_kong_config
    setup_grafana_dashboards
    setup_database_schemas
    
    print_status "Setup completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Start the infrastructure: docker-compose -f infrastructure/docker/docker-compose.microservices.yml up -d"
    echo "2. Run Kafka topics setup: ./scripts/kafka/create-topics.sh"
    echo "3. Setup databases: ./scripts/setup-databases.sh"
    echo "4. Configure Kong: ./scripts/setup-kong.sh"
    echo ""
    echo "Access points:"
    echo "- Kong Gateway: http://localhost:8000"
    echo "- Kong Admin: http://localhost:8001"
    echo "- Kafka UI: http://localhost:8080"
    echo "- Kuma GUI: http://localhost:5685"
    echo "- Prometheus: http://localhost:9090"
    echo "- Grafana: http://localhost:3001 (admin/admin)"
    echo "- Jaeger: http://localhost:16686"
    echo "- Consul: http://localhost:8500"
    echo "- EventStore: http://localhost:2113"
}

# Run main function
main "$@"
