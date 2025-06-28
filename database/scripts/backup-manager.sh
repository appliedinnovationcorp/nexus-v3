#!/bin/bash

# Database Backup and Recovery Manager
# Supports PostgreSQL, ClickHouse, and Redis backups with point-in-time recovery

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/backup.conf"
LOG_FILE="${SCRIPT_DIR}/../logs/backup.log"
BACKUP_BASE_DIR="${SCRIPT_DIR}/../backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log_warning "Config file not found, using defaults"
        # Default configuration
        POSTGRES_PRIMARY_HOST="postgres-primary"
        POSTGRES_PRIMARY_PORT="5432"
        POSTGRES_PRIMARY_DB="aic_primary"
        POSTGRES_PRIMARY_USER="aic_admin"
        POSTGRES_PRIMARY_PASSWORD="aic_secure_pass"
        
        CLICKHOUSE_HOST="clickhouse"
        CLICKHOUSE_PORT="8123"
        CLICKHOUSE_DB="aic_analytics"
        CLICKHOUSE_USER="aic_analytics"
        CLICKHOUSE_PASSWORD="analytics_pass"
        
        REDIS_HOST="redis-cluster"
        REDIS_PORT="6379"
        
        MINIO_ENDPOINT="http://minio:9000"
        MINIO_ACCESS_KEY="minioadmin"
        MINIO_SECRET_KEY="minioadmin123"
        MINIO_BUCKET="database-backups"
        
        RETENTION_DAYS="30"
        BACKUP_COMPRESSION="gzip"
    fi
}

# Create necessary directories
setup_directories() {
    mkdir -p "$BACKUP_BASE_DIR"/{postgresql,clickhouse,redis,logs}
    mkdir -p "$(dirname "$LOG_FILE")"
}

# PostgreSQL Backup Functions
backup_postgresql_primary() {
    log "Starting PostgreSQL primary backup..."
    
    local backup_name="postgresql_primary_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_BASE_DIR/postgresql/$backup_name"
    
    mkdir -p "$backup_dir"
    
    # Create base backup
    PGPASSWORD="$POSTGRES_PRIMARY_PASSWORD" pg_basebackup \
        -h "$POSTGRES_PRIMARY_HOST" \
        -p "$POSTGRES_PRIMARY_PORT" \
        -U "$POSTGRES_PRIMARY_USER" \
        -D "$backup_dir" \
        -Ft -z -P -v \
        --wal-method=stream
    
    if [[ $? -eq 0 ]]; then
        log "PostgreSQL primary backup completed: $backup_name"
        
        # Upload to MinIO if configured
        if command -v mc &> /dev/null; then
            upload_to_minio "$backup_dir" "postgresql/$backup_name"
        fi
        
        # Create backup metadata
        create_backup_metadata "postgresql" "$backup_name" "$backup_dir"
        
        return 0
    else
        log_error "PostgreSQL primary backup failed"
        return 1
    fi
}

backup_postgresql_logical() {
    log "Starting PostgreSQL logical backup..."
    
    local backup_name="postgresql_logical_$(date +%Y%m%d_%H%M%S)"
    local backup_file="$BACKUP_BASE_DIR/postgresql/${backup_name}.sql"
    
    # Create logical backup using pg_dump
    PGPASSWORD="$POSTGRES_PRIMARY_PASSWORD" pg_dump \
        -h "$POSTGRES_PRIMARY_HOST" \
        -p "$POSTGRES_PRIMARY_PORT" \
        -U "$POSTGRES_PRIMARY_USER" \
        -d "$POSTGRES_PRIMARY_DB" \
        --verbose \
        --no-owner \
        --no-privileges \
        --create \
        --clean \
        --if-exists \
        -f "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        # Compress the backup
        if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi
        
        log "PostgreSQL logical backup completed: $backup_name"
        
        # Upload to MinIO
        if command -v mc &> /dev/null; then
            upload_to_minio "$backup_file" "postgresql/logical/$backup_name"
        fi
        
        return 0
    else
        log_error "PostgreSQL logical backup failed"
        return 1
    fi
}

# ClickHouse Backup Functions
backup_clickhouse() {
    log "Starting ClickHouse backup..."
    
    local backup_name="clickhouse_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_BASE_DIR/clickhouse/$backup_name"
    
    mkdir -p "$backup_dir"
    
    # Get list of databases
    local databases=$(curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/" \
        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" \
        --data "SHOW DATABASES FORMAT TSV" | grep -v system)
    
    # Backup each database
    while IFS= read -r database; do
        if [[ -n "$database" ]]; then
            log "Backing up ClickHouse database: $database"
            
            # Get tables in database
            local tables=$(curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/" \
                --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" \
                --data "SHOW TABLES FROM $database FORMAT TSV")
            
            # Create database directory
            mkdir -p "$backup_dir/$database"
            
            # Backup each table
            while IFS= read -r table; do
                if [[ -n "$table" ]]; then
                    log "Backing up table: $database.$table"
                    
                    # Export table schema
                    curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/" \
                        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" \
                        --data "SHOW CREATE TABLE $database.$table FORMAT TSV" \
                        > "$backup_dir/$database/${table}_schema.sql"
                    
                    # Export table data
                    curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/" \
                        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" \
                        --data "SELECT * FROM $database.$table FORMAT Native" \
                        > "$backup_dir/$database/${table}_data.native"
                fi
            done <<< "$tables"
        fi
    done <<< "$databases"
    
    # Compress backup directory
    if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
        tar -czf "${backup_dir}.tar.gz" -C "$BACKUP_BASE_DIR/clickhouse" "$backup_name"
        rm -rf "$backup_dir"
        backup_dir="${backup_dir}.tar.gz"
    fi
    
    log "ClickHouse backup completed: $backup_name"
    
    # Upload to MinIO
    if command -v mc &> /dev/null; then
        upload_to_minio "$backup_dir" "clickhouse/$backup_name"
    fi
    
    return 0
}

# Redis Backup Functions
backup_redis() {
    log "Starting Redis backup..."
    
    local backup_name="redis_$(date +%Y%m%d_%H%M%S)"
    local backup_file="$BACKUP_BASE_DIR/redis/${backup_name}.rdb"
    
    # Create Redis backup using BGSAVE
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE
    
    # Wait for backup to complete
    while [[ $(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE) -eq $(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE) ]]; do
        sleep 1
    done
    
    # Copy the RDB file
    docker cp redis-cluster:/data/dump.rdb "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        # Compress the backup
        if [[ "$BACKUP_COMPRESSION" == "gzip" ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi
        
        log "Redis backup completed: $backup_name"
        
        # Upload to MinIO
        if command -v mc &> /dev/null; then
            upload_to_minio "$backup_file" "redis/$backup_name"
        fi
        
        return 0
    else
        log_error "Redis backup failed"
        return 1
    fi
}

# MinIO Upload Function
upload_to_minio() {
    local source_path="$1"
    local dest_path="$2"
    
    log "Uploading backup to MinIO: $dest_path"
    
    # Configure MinIO client
    mc alias set backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
    
    # Create bucket if it doesn't exist
    mc mb "backup/$MINIO_BUCKET" 2>/dev/null || true
    
    # Upload file or directory
    if [[ -d "$source_path" ]]; then
        mc cp -r "$source_path" "backup/$MINIO_BUCKET/$dest_path/"
    else
        mc cp "$source_path" "backup/$MINIO_BUCKET/$dest_path"
    fi
    
    if [[ $? -eq 0 ]]; then
        log "Upload completed successfully"
    else
        log_error "Upload failed"
    fi
}

# Backup Metadata
create_backup_metadata() {
    local backup_type="$1"
    local backup_name="$2"
    local backup_path="$3"
    
    local metadata_file="$BACKUP_BASE_DIR/${backup_type}/${backup_name}.metadata"
    
    cat > "$metadata_file" <<EOF
{
    "backup_name": "$backup_name",
    "backup_type": "$backup_type",
    "backup_path": "$backup_path",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "size_bytes": $(du -sb "$backup_path" | cut -f1),
    "checksum": "$(sha256sum "$backup_path" | cut -d' ' -f1)",
    "retention_until": "$(date -u -d "+$RETENTION_DAYS days" +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Point-in-Time Recovery Functions
restore_postgresql_pitr() {
    local target_time="$1"
    local restore_dir="$2"
    
    log "Starting PostgreSQL Point-in-Time Recovery to: $target_time"
    
    if [[ -z "$target_time" || -z "$restore_dir" ]]; then
        log_error "Target time and restore directory are required"
        return 1
    fi
    
    # Find the latest base backup before target time
    local base_backup=$(find "$BACKUP_BASE_DIR/postgresql" -name "postgresql_primary_*" -type d | \
        sort -r | head -1)
    
    if [[ -z "$base_backup" ]]; then
        log_error "No base backup found for PITR"
        return 1
    fi
    
    log "Using base backup: $base_backup"
    
    # Copy base backup to restore directory
    cp -r "$base_backup"/* "$restore_dir/"
    
    # Create recovery configuration
    cat > "$restore_dir/postgresql.auto.conf" <<EOF
restore_command = 'wal-g wal-fetch %f %p'
recovery_target_time = '$target_time'
recovery_target_action = 'promote'
EOF
    
    # Create recovery signal file
    touch "$restore_dir/recovery.signal"
    
    log "PITR setup completed. Start PostgreSQL with data directory: $restore_dir"
    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    # PostgreSQL backups
    find "$BACKUP_BASE_DIR/postgresql" -type d -name "postgresql_primary_*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;
    find "$BACKUP_BASE_DIR/postgresql" -type f -name "postgresql_logical_*" -mtime +$RETENTION_DAYS -delete
    
    # ClickHouse backups
    find "$BACKUP_BASE_DIR/clickhouse" -type f -name "clickhouse_*" -mtime +$RETENTION_DAYS -delete
    
    # Redis backups
    find "$BACKUP_BASE_DIR/redis" -type f -name "redis_*" -mtime +$RETENTION_DAYS -delete
    
    log "Cleanup completed"
}

# Health check for backup system
health_check() {
    log "Performing backup system health check..."
    
    local health_status=0
    
    # Check PostgreSQL connectivity
    if PGPASSWORD="$POSTGRES_PRIMARY_PASSWORD" pg_isready -h "$POSTGRES_PRIMARY_HOST" -p "$POSTGRES_PRIMARY_PORT" -U "$POSTGRES_PRIMARY_USER"; then
        log "PostgreSQL: OK"
    else
        log_error "PostgreSQL: FAILED"
        health_status=1
    fi
    
    # Check ClickHouse connectivity
    if curl -s "http://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/ping" > /dev/null; then
        log "ClickHouse: OK"
    else
        log_error "ClickHouse: FAILED"
        health_status=1
    fi
    
    # Check Redis connectivity
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null; then
        log "Redis: OK"
    else
        log_error "Redis: FAILED"
        health_status=1
    fi
    
    # Check MinIO connectivity
    if command -v mc &> /dev/null; then
        mc alias set backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" > /dev/null 2>&1
        if mc ls backup > /dev/null 2>&1; then
            log "MinIO: OK"
        else
            log_error "MinIO: FAILED"
            health_status=1
        fi
    else
        log_warning "MinIO client not installed"
    fi
    
    # Check backup directories
    if [[ -d "$BACKUP_BASE_DIR" && -w "$BACKUP_BASE_DIR" ]]; then
        log "Backup directories: OK"
    else
        log_error "Backup directories: FAILED"
        health_status=1
    fi
    
    return $health_status
}

# Main function
main() {
    local command="$1"
    
    load_config
    setup_directories
    
    case "$command" in
        "backup-postgresql")
            backup_postgresql_primary
            ;;
        "backup-postgresql-logical")
            backup_postgresql_logical
            ;;
        "backup-clickhouse")
            backup_clickhouse
            ;;
        "backup-redis")
            backup_redis
            ;;
        "backup-all")
            backup_postgresql_primary
            backup_clickhouse
            backup_redis
            ;;
        "restore-pitr")
            restore_postgresql_pitr "$2" "$3"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "health-check")
            health_check
            ;;
        *)
            echo "Usage: $0 {backup-postgresql|backup-postgresql-logical|backup-clickhouse|backup-redis|backup-all|restore-pitr|cleanup|health-check}"
            echo ""
            echo "Commands:"
            echo "  backup-postgresql         - Create PostgreSQL base backup"
            echo "  backup-postgresql-logical - Create PostgreSQL logical backup"
            echo "  backup-clickhouse         - Create ClickHouse backup"
            echo "  backup-redis              - Create Redis backup"
            echo "  backup-all                - Create all backups"
            echo "  restore-pitr <time> <dir> - Restore PostgreSQL to point in time"
            echo "  cleanup                   - Remove old backups"
            echo "  health-check              - Check backup system health"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
