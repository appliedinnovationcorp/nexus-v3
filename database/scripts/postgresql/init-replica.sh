#!/bin/bash
set -e

echo "Initializing PostgreSQL Replica..."

# Wait for primary to be ready
until pg_isready -h "$POSTGRES_PRIMARY_HOST" -p "$POSTGRES_PRIMARY_PORT" -U "$POSTGRES_REPLICATION_USER"; do
    echo "Waiting for primary database to be ready..."
    sleep 2
done

# Stop PostgreSQL if running
pg_ctl stop -D "$PGDATA" -m fast || true

# Remove existing data directory
rm -rf "$PGDATA"/*

# Create base backup from primary
PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_basebackup \
    -h "$POSTGRES_PRIMARY_HOST" \
    -p "$POSTGRES_PRIMARY_PORT" \
    -U "$POSTGRES_REPLICATION_USER" \
    -D "$PGDATA" \
    -Fp -Xs -P -R

# Create recovery configuration
cat > "$PGDATA/postgresql.auto.conf" <<EOF
# Replica-specific settings
primary_conninfo = 'host=$POSTGRES_PRIMARY_HOST port=$POSTGRES_PRIMARY_PORT user=$POSTGRES_REPLICATION_USER password=$POSTGRES_REPLICATION_PASSWORD'
primary_slot_name = 'replica_slot_$(hostname)'
hot_standby = on
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = on
EOF

# Create standby signal file
touch "$PGDATA/standby.signal"

# Set proper permissions
chmod 600 "$PGDATA/postgresql.auto.conf"
chown postgres:postgres "$PGDATA/postgresql.auto.conf"

echo "PostgreSQL Replica initialization completed!"
