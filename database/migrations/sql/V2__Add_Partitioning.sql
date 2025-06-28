-- Add Partitioning for Large Tables
-- Version: 2.0.0
-- Description: Implement table partitioning for better performance on large datasets

-- Create partitioned events table for analytics
CREATE TABLE events (
    id BIGSERIAL,
    event_type VARCHAR(50) NOT NULL,
    user_id UUID,
    session_id VARCHAR(100),
    event_data JSONB NOT NULL,
    ip_address INET,
    user_agent TEXT,
    referrer TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Create partitions for events table (current year and next year)
CREATE TABLE events_2024 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE events_2025 PARTITION OF events
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Create indexes on partitioned tables
CREATE INDEX idx_events_2024_user_id ON events_2024 (user_id);
CREATE INDEX idx_events_2024_type ON events_2024 (event_type);
CREATE INDEX idx_events_2024_session ON events_2024 (session_id);
CREATE INDEX idx_events_2024_data ON events_2024 USING GIN (event_data);

CREATE INDEX idx_events_2025_user_id ON events_2025 (user_id);
CREATE INDEX idx_events_2025_type ON events_2025 (event_type);
CREATE INDEX idx_events_2025_session ON events_2025 (session_id);
CREATE INDEX idx_events_2025_data ON events_2025 USING GIN (event_data);

-- Create function to automatically create new partitions
CREATE OR REPLACE FUNCTION create_monthly_partition(table_name TEXT, start_date DATE)
RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    end_date DATE;
BEGIN
    partition_name := table_name || '_' || TO_CHAR(start_date, 'YYYY_MM');
    end_date := start_date + INTERVAL '1 month';
    
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
                    FOR VALUES FROM (%L) TO (%L)',
                   partition_name, table_name, start_date, end_date);
    
    -- Create indexes on the new partition
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_user_id ON %I (user_id)', 
                   partition_name, partition_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_type ON %I (event_type)', 
                   partition_name, partition_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_session ON %I (session_id)', 
                   partition_name, partition_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_data ON %I USING GIN (event_data)', 
                   partition_name, partition_name);
END;
$$ LANGUAGE plpgsql;

-- Create function to automatically manage partitions
CREATE OR REPLACE FUNCTION manage_partitions()
RETURNS VOID AS $$
DECLARE
    current_month DATE;
    next_month DATE;
BEGIN
    current_month := DATE_TRUNC('month', CURRENT_DATE);
    next_month := current_month + INTERVAL '1 month';
    
    -- Create next month's partition if it doesn't exist
    PERFORM create_monthly_partition('events', next_month);
    
    -- Drop old partitions (older than 2 years)
    PERFORM drop_old_partitions('events', INTERVAL '2 years');
END;
$$ LANGUAGE plpgsql;

-- Create function to drop old partitions
CREATE OR REPLACE FUNCTION drop_old_partitions(table_name TEXT, retention_period INTERVAL)
RETURNS VOID AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
BEGIN
    cutoff_date := CURRENT_DATE - retention_period;
    
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE tablename LIKE table_name || '_%'
        AND schemaname = 'public'
    LOOP
        -- Extract date from partition name and check if it's old enough to drop
        DECLARE
            partition_date DATE;
            date_part TEXT;
        BEGIN
            date_part := SUBSTRING(partition_record.tablename FROM '[0-9]{4}_[0-9]{2}$');
            IF date_part IS NOT NULL THEN
                partition_date := TO_DATE(REPLACE(date_part, '_', '-') || '-01', 'YYYY-MM-DD');
                IF partition_date < cutoff_date THEN
                    EXECUTE format('DROP TABLE IF EXISTS %I.%I', 
                                   partition_record.schemaname, partition_record.tablename);
                    RAISE NOTICE 'Dropped old partition: %', partition_record.tablename;
                END IF;
            END IF;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Partition the audit.change_log table by month
CREATE TABLE audit.change_log_new (
    id BIGSERIAL,
    table_name TEXT NOT NULL,
    record_id UUID,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT NOT NULL,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    session_id TEXT,
    ip_address INET,
    PRIMARY KEY (id, changed_at)
) PARTITION BY RANGE (changed_at);

-- Create partitions for audit log
CREATE TABLE audit.change_log_2024 PARTITION OF audit.change_log_new
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE audit.change_log_2025 PARTITION OF audit.change_log_new
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- Create indexes on audit partitions
CREATE INDEX idx_audit_2024_table_name ON audit.change_log_2024 (table_name);
CREATE INDEX idx_audit_2024_record_id ON audit.change_log_2024 (record_id);
CREATE INDEX idx_audit_2024_operation ON audit.change_log_2024 (operation);
CREATE INDEX idx_audit_2024_changed_by ON audit.change_log_2024 (changed_by);

CREATE INDEX idx_audit_2025_table_name ON audit.change_log_2025 (table_name);
CREATE INDEX idx_audit_2025_record_id ON audit.change_log_2025 (record_id);
CREATE INDEX idx_audit_2025_operation ON audit.change_log_2025 (operation);
CREATE INDEX idx_audit_2025_changed_by ON audit.change_log_2025 (changed_by);

-- Migrate existing audit data (if any)
INSERT INTO audit.change_log_new SELECT * FROM audit.change_log;

-- Drop old audit table and rename new one
DROP TABLE audit.change_log;
ALTER TABLE audit.change_log_new RENAME TO change_log;

-- Update audit trigger to work with partitioned table
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS TRIGGER AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    record_id UUID;
BEGIN
    -- Extract record ID
    IF TG_OP = 'DELETE' THEN
        record_id := OLD.id;
        old_data := row_to_json(OLD)::JSONB;
    ELSE
        record_id := NEW.id;
        new_data := row_to_json(NEW)::JSONB;
        IF TG_OP = 'UPDATE' THEN
            old_data := row_to_json(OLD)::JSONB;
        END IF;
    END IF;

    -- Insert audit record
    INSERT INTO audit.change_log (
        table_name, 
        record_id, 
        operation, 
        old_data, 
        new_data, 
        changed_by,
        session_id,
        changed_at
    ) VALUES (
        TG_TABLE_NAME,
        record_id,
        TG_OP,
        old_data,
        new_data,
        current_user,
        current_setting('application_name', true),
        NOW()
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create a scheduled job to manage partitions (using pg_cron if available)
-- This would typically be handled by an external scheduler in production
CREATE OR REPLACE FUNCTION schedule_partition_maintenance()
RETURNS VOID AS $$
BEGIN
    -- This function would be called by a scheduler (cron, etc.)
    PERFORM manage_partitions();
    
    -- Log the maintenance activity
    INSERT INTO events (event_type, event_data, created_at)
    VALUES ('partition_maintenance', '{"action": "manage_partitions"}', NOW());
END;
$$ LANGUAGE plpgsql;

-- Create materialized view for analytics performance
CREATE MATERIALIZED VIEW analytics.monthly_user_activity AS
SELECT 
    DATE_TRUNC('month', e.created_at) as month,
    COUNT(DISTINCT e.user_id) as active_users,
    COUNT(*) as total_events,
    COUNT(*) FILTER (WHERE e.event_type = 'page_view') as page_views,
    COUNT(*) FILTER (WHERE e.event_type = 'purchase') as purchases,
    COUNT(*) FILTER (WHERE e.event_type = 'login') as logins
FROM events e
WHERE e.user_id IS NOT NULL
GROUP BY DATE_TRUNC('month', e.created_at);

-- Create unique index on materialized view
CREATE UNIQUE INDEX idx_monthly_user_activity_month 
ON analytics.monthly_user_activity (month);

-- Create function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_analytics_views()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.monthly_user_activity;
    
    -- Log the refresh activity
    INSERT INTO events (event_type, event_data, created_at)
    VALUES ('analytics_refresh', '{"view": "monthly_user_activity"}', NOW());
END;
$$ LANGUAGE plpgsql;

-- Add table for storing partition metadata
CREATE TABLE partition_metadata (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    partition_name VARCHAR(100) NOT NULL,
    partition_start DATE NOT NULL,
    partition_end DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    row_count BIGINT,
    size_bytes BIGINT,
    last_analyzed TIMESTAMP WITH TIME ZONE
);

-- Create function to update partition statistics
CREATE OR REPLACE FUNCTION update_partition_stats()
RETURNS VOID AS $$
DECLARE
    partition_record RECORD;
    row_count BIGINT;
    size_bytes BIGINT;
BEGIN
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE tablename LIKE 'events_%'
        AND schemaname = 'public'
    LOOP
        -- Get row count
        EXECUTE format('SELECT COUNT(*) FROM %I.%I', 
                       partition_record.schemaname, partition_record.tablename)
        INTO row_count;
        
        -- Get table size
        SELECT pg_total_relation_size(format('%I.%I', 
                                           partition_record.schemaname, 
                                           partition_record.tablename))
        INTO size_bytes;
        
        -- Update or insert partition metadata
        INSERT INTO partition_metadata (table_name, partition_name, partition_start, partition_end, row_count, size_bytes, last_analyzed)
        VALUES ('events', partition_record.tablename, '2024-01-01', '2024-12-31', row_count, size_bytes, NOW())
        ON CONFLICT (table_name, partition_name) 
        DO UPDATE SET 
            row_count = EXCLUDED.row_count,
            size_bytes = EXCLUDED.size_bytes,
            last_analyzed = EXCLUDED.last_analyzed;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
