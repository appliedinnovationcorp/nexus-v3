#!/bin/bash
set -e

echo "Initializing PostgreSQL Primary Database..."

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create replication user
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'repl_pass';
    
    -- Create application users
    CREATE USER app_user WITH ENCRYPTED PASSWORD 'app_pass';
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO app_user;
    
    -- Create extensions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    CREATE EXTENSION IF NOT EXISTS "btree_gin";
    CREATE EXTENSION IF NOT EXISTS "btree_gist";
    
    -- Create schemas
    CREATE SCHEMA IF NOT EXISTS audit;
    CREATE SCHEMA IF NOT EXISTS analytics;
    
    -- Grant permissions
    GRANT USAGE ON SCHEMA public TO app_user;
    GRANT USAGE ON SCHEMA audit TO app_user;
    GRANT CREATE ON SCHEMA public TO app_user;
    
    -- Create audit table for change tracking
    CREATE TABLE IF NOT EXISTS audit.change_log (
        id BIGSERIAL PRIMARY KEY,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        old_data JSONB,
        new_data JSONB,
        changed_by TEXT NOT NULL,
        changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Create function for audit logging
    CREATE OR REPLACE FUNCTION audit.log_changes()
    RETURNS TRIGGER AS \$\$
    BEGIN
        IF TG_OP = 'DELETE' THEN
            INSERT INTO audit.change_log (table_name, operation, old_data, changed_by)
            VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), current_user);
            RETURN OLD;
        ELSIF TG_OP = 'UPDATE' THEN
            INSERT INTO audit.change_log (table_name, operation, old_data, new_data, changed_by)
            VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), row_to_json(NEW), current_user);
            RETURN NEW;
        ELSIF TG_OP = 'INSERT' THEN
            INSERT INTO audit.change_log (table_name, operation, new_data, changed_by)
            VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW), current_user);
            RETURN NEW;
        END IF;
        RETURN NULL;
    END;
    \$\$ LANGUAGE plpgsql;
    
    -- Create monitoring views
    CREATE OR REPLACE VIEW analytics.database_stats AS
    SELECT 
        schemaname,
        tablename,
        attname,
        n_distinct,
        correlation,
        most_common_vals,
        most_common_freqs
    FROM pg_stats
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog');
    
    CREATE OR REPLACE VIEW analytics.query_performance AS
    SELECT 
        query,
        calls,
        total_exec_time,
        mean_exec_time,
        stddev_exec_time,
        rows,
        100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC;
    
    -- Create partitioned table example
    CREATE TABLE IF NOT EXISTS events (
        id BIGSERIAL,
        event_type TEXT NOT NULL,
        event_data JSONB NOT NULL,
        user_id BIGINT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        PRIMARY KEY (id, created_at)
    ) PARTITION BY RANGE (created_at);
    
    -- Create initial partitions
    CREATE TABLE IF NOT EXISTS events_2024 PARTITION OF events
        FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
    
    CREATE TABLE IF NOT EXISTS events_2025 PARTITION OF events
        FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
    
    -- Create indexes
    CREATE INDEX IF NOT EXISTS idx_events_user_id ON events (user_id);
    CREATE INDEX IF NOT EXISTS idx_events_type ON events (event_type);
    CREATE INDEX IF NOT EXISTS idx_events_created_at ON events (created_at);
    CREATE INDEX IF NOT EXISTS idx_events_data_gin ON events USING GIN (event_data);
    
    -- Grant permissions on new objects
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
    GRANT SELECT ON ALL TABLES IN SCHEMA audit TO app_user;
    GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO app_user;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
EOSQL

echo "PostgreSQL Primary initialization completed!"
