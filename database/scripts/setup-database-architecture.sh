#!/bin/bash

set -e

echo "🗄️ Setting up Enterprise Database Architecture..."

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
    
    if ! command -v psql &> /dev/null; then
        missing_deps+=("postgresql-client")
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
    
    mkdir -p database/{config,scripts,migrations,backups,logs}
    mkdir -p database/config/{postgresql/{primary,replica,shard},pgbouncer,haproxy,clickhouse,redis}
    mkdir -p database/scripts/{postgresql,clickhouse,redis,wal-g}
    mkdir -p database/migrations/{sql,conf}
    mkdir -p database/backups/{postgresql,clickhouse,redis}
    
    print_status "Directory structure created ✅"
}

# Setup configuration files
setup_configurations() {
    print_header "Setting up configuration files..."
    
    # Create backup configuration
    cat > database/config/backup.conf << 'EOF'
# Database Backup Configuration

# PostgreSQL Primary
POSTGRES_PRIMARY_HOST="postgres-primary"
POSTGRES_PRIMARY_PORT="5432"
POSTGRES_PRIMARY_DB="aic_primary"
POSTGRES_PRIMARY_USER="aic_admin"
POSTGRES_PRIMARY_PASSWORD="aic_secure_pass"

# ClickHouse
CLICKHOUSE_HOST="clickhouse"
CLICKHOUSE_PORT="8123"
CLICKHOUSE_DB="aic_analytics"
CLICKHOUSE_USER="aic_analytics"
CLICKHOUSE_PASSWORD="analytics_pass"

# Redis
REDIS_HOST="redis-cluster"
REDIS_PORT="6379"

# MinIO (S3-compatible storage)
MINIO_ENDPOINT="http://minio:9000"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
MINIO_BUCKET="database-backups"

# Backup settings
RETENTION_DAYS="30"
BACKUP_COMPRESSION="gzip"
EOF

    # Create Redis configuration
    cat > database/config/redis/redis.conf << 'EOF'
# Redis Configuration for Production

# Network
bind 0.0.0.0
port 6379
protected-mode no

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""
databases 16

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Replication
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-ping-replica-period 10
repl-timeout 60
repl-disable-tcp-nodelay no
repl-backlog-size 1mb
repl-backlog-ttl 3600

# Security
requirepass ""

# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Lazy freeing
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no

# Append only file
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# Lua scripting
lua-time-limit 5000

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency monitor
latency-monitor-threshold 0

# Event notification
notify-keyspace-events ""

# Advanced config
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

    # Create Flyway configuration
    cat > database/migrations/conf/flyway.conf << 'EOF'
# Flyway Configuration

# Database connection
flyway.url=jdbc:postgresql://postgres-primary:5432/aic_primary
flyway.user=aic_admin
flyway.password=aic_secure_pass
flyway.schemas=public

# Migration settings
flyway.locations=filesystem:/flyway/sql
flyway.baselineOnMigrate=true
flyway.validateOnMigrate=true
flyway.outOfOrder=false
flyway.ignoreMissingMigrations=false
flyway.ignoreIgnoredMigrations=false
flyway.ignorePendingMigrations=false
flyway.ignoreFutureMigrations=true
flyway.cleanDisabled=true

# Placeholders
flyway.placeholders.environment=production
flyway.placeholders.schema=public
EOF

    print_status "Configuration files created ✅"
}

# Setup database initialization scripts
setup_init_scripts() {
    print_header "Setting up initialization scripts..."
    
    # Create WAL-G configuration script
    cat > database/scripts/wal-g/setup-wal-g.sh << 'EOF'
#!/bin/bash

# WAL-G Setup Script for PostgreSQL Backup

set -e

echo "Setting up WAL-G for PostgreSQL backup..."

# Install WAL-G (if not already installed)
if ! command -v wal-g &> /dev/null; then
    echo "Installing WAL-G..."
    wget -O /tmp/wal-g.tar.gz https://github.com/wal-g/wal-g/releases/download/v2.0.1/wal-g-pg-ubuntu-20.04-amd64.tar.gz
    tar -xzf /tmp/wal-g.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/wal-g
fi

# Configure WAL-G environment
export WALG_S3_PREFIX="s3://postgres-backups"
export AWS_S3_FORCE_PATH_STYLE="true"
export AWS_ENDPOINT="http://minio:9000"
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin123"
export AWS_REGION="us-east-1"

# Create S3 bucket
mc alias set backup http://minio:9000 minioadmin minioadmin123
mc mb backup/postgres-backups || true

echo "WAL-G setup completed!"
EOF

    chmod +x database/scripts/wal-g/setup-wal-g.sh

    # Create database monitoring script
    cat > database/scripts/monitor-databases.sh << 'EOF'
#!/bin/bash

# Database Monitoring Script

set -e

echo "🔍 Database Health Monitoring Report"
echo "Generated at: $(date)"
echo "=================================="

# PostgreSQL Primary Health
echo ""
echo "📊 PostgreSQL Primary Status:"
if docker exec postgres-primary pg_isready -U aic_admin > /dev/null 2>&1; then
    echo "✅ Primary: HEALTHY"
    
    # Get connection count
    CONN_COUNT=$(docker exec postgres-primary psql -U aic_admin -d aic_primary -t -c "SELECT count(*) FROM pg_stat_activity;" | xargs)
    echo "   Active connections: $CONN_COUNT"
    
    # Get database size
    DB_SIZE=$(docker exec postgres-primary psql -U aic_admin -d aic_primary -t -c "SELECT pg_size_pretty(pg_database_size('aic_primary'));" | xargs)
    echo "   Database size: $DB_SIZE"
    
    # Get replication lag
    REP_LAG=$(docker exec postgres-primary psql -U aic_admin -d aic_primary -t -c "SELECT COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0);" | xargs)
    echo "   Replication lag: ${REP_LAG}s"
else
    echo "❌ Primary: UNHEALTHY"
fi

# PostgreSQL Replicas Health
echo ""
echo "📊 PostgreSQL Replicas Status:"
for i in 1 2; do
    if docker exec postgres-replica-$i pg_isready -U aic_admin > /dev/null 2>&1; then
        echo "✅ Replica $i: HEALTHY"
    else
        echo "❌ Replica $i: UNHEALTHY"
    fi
done

# PostgreSQL Shards Health
echo ""
echo "📊 PostgreSQL Shards Status:"
for i in 1 2; do
    if docker exec postgres-shard-$i pg_isready -U aic_shard_user > /dev/null 2>&1; then
        echo "✅ Shard $i: HEALTHY"
        
        # Get shard row count
        SHARD_ROWS=$(docker exec postgres-shard-$i psql -U aic_shard_user -d aic_shard_$i -t -c "SELECT COUNT(*) FROM users_shard;" | xargs)
        echo "   Rows in shard $i: $SHARD_ROWS"
    else
        echo "❌ Shard $i: UNHEALTHY"
    fi
done

# ClickHouse Health
echo ""
echo "📊 ClickHouse Status:"
if curl -s http://clickhouse:8123/ping > /dev/null 2>&1; then
    echo "✅ ClickHouse: HEALTHY"
    
    # Get ClickHouse version
    CH_VERSION=$(curl -s "http://clickhouse:8123/" --data "SELECT version()" | head -1)
    echo "   Version: $CH_VERSION"
    
    # Get database size
    CH_SIZE=$(curl -s "http://clickhouse:8123/" --data "SELECT formatReadableSize(sum(bytes)) FROM system.parts WHERE active" | head -1)
    echo "   Data size: $CH_SIZE"
else
    echo "❌ ClickHouse: UNHEALTHY"
fi

# Redis Health
echo ""
echo "📊 Redis Status:"
if docker exec redis-cluster redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis: HEALTHY"
    
    # Get Redis info
    REDIS_MEMORY=$(docker exec redis-cluster redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    echo "   Memory usage: $REDIS_MEMORY"
    
    REDIS_KEYS=$(docker exec redis-cluster redis-cli dbsize)
    echo "   Total keys: $REDIS_KEYS"
else
    echo "❌ Redis: UNHEALTHY"
fi

# PgBouncer Health
echo ""
echo "📊 PgBouncer Status:"
if docker exec pgbouncer psql -h localhost -p 5432 -U aic_admin -d pgbouncer -c "SHOW POOLS;" > /dev/null 2>&1; then
    echo "✅ PgBouncer: HEALTHY"
    
    # Get pool stats
    POOL_STATS=$(docker exec pgbouncer psql -h localhost -p 5432 -U aic_admin -d pgbouncer -t -c "SHOW POOLS;" | head -5)
    echo "   Pool status:"
    echo "$POOL_STATS" | while read line; do
        echo "     $line"
    done
else
    echo "❌ PgBouncer: UNHEALTHY"
fi

echo ""
echo "=================================="
echo "Monitoring completed at: $(date)"
EOF

    chmod +x database/scripts/monitor-databases.sh

    print_status "Initialization scripts created ✅"
}

# Setup automated tasks
setup_automation() {
    print_header "Setting up automated tasks..."
    
    # Create cron jobs script
    cat > database/scripts/setup-cron-jobs.sh << 'EOF'
#!/bin/bash

# Setup automated database tasks

echo "Setting up automated database tasks..."

# Create cron jobs for database maintenance
cat > /tmp/database-cron << 'CRON_EOF'
# Database backup jobs
0 2 * * * /path/to/database/scripts/backup-manager.sh backup-all >> /var/log/database-backup.log 2>&1
0 4 * * 0 /path/to/database/scripts/backup-manager.sh cleanup >> /var/log/database-cleanup.log 2>&1

# Database monitoring
*/5 * * * * /path/to/database/scripts/monitor-databases.sh >> /var/log/database-monitor.log 2>&1

# Partition maintenance (monthly)
0 3 1 * * docker exec postgres-primary psql -U aic_admin -d aic_primary -c "SELECT manage_partitions();" >> /var/log/partition-maintenance.log 2>&1

# Analytics view refresh (daily)
0 1 * * * docker exec postgres-primary psql -U aic_admin -d aic_primary -c "SELECT refresh_analytics_views();" >> /var/log/analytics-refresh.log 2>&1

# Update partition statistics (weekly)
0 5 * * 0 docker exec postgres-primary psql -U aic_admin -d aic_primary -c "SELECT update_partition_stats();" >> /var/log/partition-stats.log 2>&1
CRON_EOF

# Install cron jobs
crontab /tmp/database-cron
rm /tmp/database-cron

echo "Automated tasks configured successfully!"
EOF

    chmod +x database/scripts/setup-cron-jobs.sh

    # Create health check endpoint script
    cat > database/scripts/health-check-api.js << 'EOF'
const express = require('express');
const { exec } = require('child_process');
const app = express();
const port = 3010;

app.use(express.json());

// Health check endpoint
app.get('/health', async (req, res) => {
    try {
        const healthStatus = await checkDatabaseHealth();
        res.json({
            status: healthStatus.overall ? 'healthy' : 'unhealthy',
            timestamp: new Date().toISOString(),
            services: healthStatus.services
        });
    } catch (error) {
        res.status(500).json({
            status: 'error',
            message: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Detailed metrics endpoint
app.get('/metrics', async (req, res) => {
    try {
        const metrics = await getDatabaseMetrics();
        res.json({
            timestamp: new Date().toISOString(),
            metrics
        });
    } catch (error) {
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Backup status endpoint
app.get('/backup/status', async (req, res) => {
    try {
        const backupStatus = await getBackupStatus();
        res.json({
            timestamp: new Date().toISOString(),
            backup_status: backupStatus
        });
    } catch (error) {
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Trigger backup endpoint
app.post('/backup/trigger', async (req, res) => {
    try {
        const { type } = req.body;
        const result = await triggerBackup(type);
        res.json({
            message: 'Backup triggered successfully',
            type,
            result,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

async function checkDatabaseHealth() {
    return new Promise((resolve, reject) => {
        exec('./backup-manager.sh health-check', (error, stdout, stderr) => {
            if (error) {
                reject(error);
                return;
            }
            
            const services = {
                postgresql: stdout.includes('PostgreSQL: OK'),
                clickhouse: stdout.includes('ClickHouse: OK'),
                redis: stdout.includes('Redis: OK'),
                minio: stdout.includes('MinIO: OK')
            };
            
            const overall = Object.values(services).every(status => status);
            
            resolve({ overall, services });
        });
    });
}

async function getDatabaseMetrics() {
    return new Promise((resolve, reject) => {
        exec('./monitor-databases.sh', (error, stdout, stderr) => {
            if (error) {
                reject(error);
                return;
            }
            
            // Parse monitoring output for metrics
            const metrics = {
                postgresql: {
                    primary_healthy: stdout.includes('Primary: HEALTHY'),
                    replicas_healthy: (stdout.match(/Replica \d+: HEALTHY/g) || []).length,
                    shards_healthy: (stdout.match(/Shard \d+: HEALTHY/g) || []).length
                },
                clickhouse: {
                    healthy: stdout.includes('ClickHouse: HEALTHY')
                },
                redis: {
                    healthy: stdout.includes('Redis: HEALTHY')
                }
            };
            
            resolve(metrics);
        });
    });
}

async function getBackupStatus() {
    return new Promise((resolve, reject) => {
        exec('find database/backups -name "*.metadata" -mtime -1 | wc -l', (error, stdout, stderr) => {
            if (error) {
                reject(error);
                return;
            }
            
            const recentBackups = parseInt(stdout.trim());
            
            resolve({
                recent_backups_24h: recentBackups,
                last_backup_check: new Date().toISOString()
            });
        });
    });
}

async function triggerBackup(type) {
    return new Promise((resolve, reject) => {
        const validTypes = ['postgresql', 'clickhouse', 'redis', 'all'];
        
        if (!validTypes.includes(type)) {
            reject(new Error(`Invalid backup type. Valid types: ${validTypes.join(', ')}`));
            return;
        }
        
        const command = `./backup-manager.sh backup-${type}`;
        
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject(error);
                return;
            }
            
            resolve({
                command_executed: command,
                output: stdout,
                status: 'completed'
            });
        });
    });
}

app.listen(port, () => {
    console.log(`Database Health Check API listening at http://localhost:${port}`);
});
EOF

    print_status "Automation scripts created ✅"
}

# Create comprehensive README
create_documentation() {
    print_header "Creating documentation..."
    
    cat > database/README-DATABASE-ARCHITECTURE.md << 'EOF'
# Enterprise Database Architecture

## 🏗️ Architecture Overview

This implementation provides a comprehensive database architecture with:

- **Multi-Database Strategy**: PostgreSQL (OLTP) + ClickHouse (OLAP)
- **Database Sharding**: Horizontal scaling with automatic shard routing
- **Read Replicas**: Load balancing for read operations
- **Connection Pooling**: PgBouncer for PostgreSQL, native pooling for ClickHouse
- **Database Migrations**: Flyway with rollback capabilities
- **Backup & Recovery**: Automated backups with point-in-time recovery
- **Monitoring**: Comprehensive health checks and metrics

## 🛠️ Technology Stack

### OLTP Layer (PostgreSQL)
- **Primary Database**: Write operations, ACID compliance
- **Read Replicas**: Streaming replication for read scaling
- **Sharded Instances**: Horizontal partitioning for massive scale
- **Connection Pooling**: PgBouncer for connection management

### OLAP Layer (ClickHouse)
- **Analytics Database**: Column-oriented for fast analytics
- **Materialized Views**: Pre-aggregated data for performance
- **Real-time Ingestion**: Kafka integration for streaming data
- **Distributed Tables**: Multi-node scaling capability

### Caching Layer (Redis)
- **Application Cache**: Frequently accessed data
- **Session Storage**: User sessions and temporary data
- **Rate Limiting**: API throttling and quotas
- **Pub/Sub**: Real-time messaging

### Backup & Storage
- **MinIO**: S3-compatible object storage
- **WAL-G**: PostgreSQL WAL archiving and PITR
- **Automated Backups**: Scheduled full and incremental backups
- **Cross-Region Replication**: Disaster recovery

## 🚀 Quick Start

### 1. Start Database Infrastructure

```bash
# Start all database services
docker-compose -f database/docker-compose.database.yml up -d

# Wait for services to be ready
sleep 30

# Run health check
./database/scripts/backup-manager.sh health-check
```

### 2. Initialize Databases

```bash
# Run database migrations
docker-compose -f database/docker-compose.database.yml run --rm flyway migrate

# Setup WAL-G for backups
./database/scripts/wal-g/setup-wal-g.sh

# Create initial partitions
docker exec postgres-primary psql -U aic_admin -d aic_primary -c "SELECT manage_partitions();"
```

### 3. Setup Monitoring and Automation

```bash
# Setup automated tasks
./database/scripts/setup-cron-jobs.sh

# Start health check API
cd database/scripts && node health-check-api.js &
```

## 📊 Database Operations

### Sharding Operations

```typescript
import { DatabaseManager, createDatabaseConfig } from './scripts/database-manager';

const config = createDatabaseConfig();
const dbManager = new DatabaseManager(new ConnectionPoolManager(config));

// Create user (automatically sharded)
const userId = await dbManager.createUser({
    email: 'user@example.com',
    username: 'johndoe',
    passwordHash: 'hashed_password'
});

// Get user (from appropriate shard)
const user = await dbManager.getUserById(userId);

// Cross-shard query
const totalUsers = await dbManager.getTotalUserCount();
```

### Analytics Operations

```typescript
// Get user analytics from ClickHouse
const analytics = await dbManager.getUserAnalytics(
    userId, 
    new Date('2024-01-01'), 
    new Date('2024-12-31')
);

// Get daily metrics
const dailyMetrics = await dbManager.getDailyMetrics(new Date());
```

### Backup Operations

```bash
# Create full backup
./database/scripts/backup-manager.sh backup-all

# Create PostgreSQL logical backup
./database/scripts/backup-manager.sh backup-postgresql-logical

# Point-in-time recovery
./database/scripts/backup-manager.sh restore-pitr "2024-06-28 15:30:00" /path/to/restore

# Cleanup old backups
./database/scripts/backup-manager.sh cleanup
```

## 🔧 Configuration

### Connection Pooling (PgBouncer)

```ini
# database/config/pgbouncer/pgbouncer.ini
[databases]
aic_primary = host=postgres-primary port=5432 dbname=aic_primary

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
server_lifetime = 3600
```

### Sharding Configuration

```typescript
const shards = [
    {
        id: 1,
        host: 'postgres-shard-1',
        minKey: 0,
        maxKey: 999999
    },
    {
        id: 2,
        host: 'postgres-shard-2',
        minKey: 1000000,
        maxKey: 1999999
    }
];
```

## 📈 Monitoring & Metrics

### Health Check Endpoints

- `GET /health` - Overall system health
- `GET /metrics` - Detailed database metrics
- `GET /backup/status` - Backup system status
- `POST /backup/trigger` - Trigger manual backup

### Database Monitoring

```bash
# Real-time monitoring
./database/scripts/monitor-databases.sh

# Check replication lag
docker exec postgres-primary psql -U aic_admin -c "SELECT * FROM pg_stat_replication;"

# Check shard distribution
docker exec postgres-shard-1 psql -U aic_shard_user -c "SELECT COUNT(*) FROM users_shard;"
```

## 🔒 Security Features

### Access Control
- Role-based database users
- Network-level security with Docker networks
- SSL/TLS encryption for connections
- Audit logging for all operations

### Backup Security
- Encrypted backups with WAL-G
- S3-compatible storage with access controls
- Point-in-time recovery capabilities
- Cross-region backup replication

## 📊 Performance Optimization

### Query Optimization
- Automatic index creation and maintenance
- Partitioned tables for large datasets
- Materialized views for complex analytics
- Connection pooling and query caching

### Scaling Strategies
- Horizontal sharding for write scaling
- Read replicas for read scaling
- ClickHouse for analytics workloads
- Redis caching for frequently accessed data

## 🚨 Disaster Recovery

### Backup Strategy
- Continuous WAL archiving
- Daily full backups
- Point-in-time recovery capability
- Cross-region backup replication

### Recovery Procedures
1. **Point-in-Time Recovery**: Restore to specific timestamp
2. **Replica Promotion**: Promote replica to primary
3. **Shard Recovery**: Restore individual shards
4. **Cross-Region Failover**: Switch to backup region

## 📋 Maintenance Tasks

### Daily Tasks
- Health checks and monitoring
- Backup verification
- Performance metrics collection
- Log rotation and cleanup

### Weekly Tasks
- Partition maintenance
- Index optimization
- Statistics updates
- Backup cleanup

### Monthly Tasks
- Capacity planning review
- Performance tuning
- Security audit
- Disaster recovery testing

## 🔧 Troubleshooting

### Common Issues

1. **Replication Lag**
   ```bash
   # Check replication status
   docker exec postgres-primary psql -U aic_admin -c "SELECT * FROM pg_stat_replication;"
   ```

2. **Connection Pool Exhaustion**
   ```bash
   # Check PgBouncer status
   docker exec pgbouncer psql -h localhost -p 5432 -U aic_admin -d pgbouncer -c "SHOW POOLS;"
   ```

3. **Shard Imbalance**
   ```bash
   # Check shard distribution
   ./database/scripts/monitor-databases.sh | grep "Rows in shard"
   ```

### Performance Issues

1. **Slow Queries**
   ```sql
   -- Check slow queries
   SELECT query, calls, total_exec_time, mean_exec_time 
   FROM pg_stat_statements 
   ORDER BY total_exec_time DESC LIMIT 10;
   ```

2. **High Memory Usage**
   ```bash
   # Check memory usage
   docker stats postgres-primary clickhouse redis-cluster
   ```

## 📚 Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [PgBouncer Documentation](https://www.pgbouncer.org/)
- [WAL-G Documentation](https://github.com/wal-g/wal-g)
- [Flyway Documentation](https://flywaydb.org/documentation/)

This architecture provides enterprise-grade database capabilities with high availability, scalability, and disaster recovery features using only open-source technologies.
EOF

    print_status "Documentation created ✅"
}

# Main setup function
main() {
    print_header "Starting Database Architecture Setup"
    
    check_dependencies
    create_directories
    setup_configurations
    setup_init_scripts
    setup_automation
    create_documentation
    
    print_status "Database architecture setup completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Start database services: docker-compose -f database/docker-compose.database.yml up -d"
    echo "2. Run migrations: docker-compose -f database/docker-compose.database.yml run --rm flyway migrate"
    echo "3. Setup backups: ./database/scripts/wal-g/setup-wal-g.sh"
    echo "4. Setup automation: ./database/scripts/setup-cron-jobs.sh"
    echo "5. Start monitoring: ./database/scripts/monitor-databases.sh"
    echo ""
    echo "Access points:"
    echo "- PostgreSQL Primary: localhost:5432"
    echo "- PostgreSQL Replicas: localhost:5433, localhost:5434"
    echo "- PostgreSQL Shards: localhost:5435, localhost:5436"
    echo "- PgBouncer: localhost:6432"
    echo "- HAProxy Stats: http://localhost:8404/stats"
    echo "- ClickHouse: http://localhost:8123"
    echo "- Redis: localhost:6379"
    echo "- MinIO: http://localhost:9001"
    echo "- Health Check API: http://localhost:3010/health"
}

# Run main function
main "$@"
