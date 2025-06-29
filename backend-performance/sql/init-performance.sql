-- Backend Performance Database Schema and Optimizations

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Enable query statistics
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET pg_stat_statements.max = 10000;

-- Performance monitoring tables
CREATE TABLE query_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    query_hash VARCHAR(64) NOT NULL,
    query_text TEXT NOT NULL,
    execution_count BIGINT DEFAULT 0,
    total_time DECIMAL(15,3) DEFAULT 0,
    mean_time DECIMAL(15,3) DEFAULT 0,
    min_time DECIMAL(15,3) DEFAULT 0,
    max_time DECIMAL(15,3) DEFAULT 0,
    stddev_time DECIMAL(15,3) DEFAULT 0,
    rows_affected BIGINT DEFAULT 0,
    cache_hit_ratio DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cache performance tracking
CREATE TABLE cache_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cache_key VARCHAR(255) NOT NULL,
    cache_type VARCHAR(50) NOT NULL, -- redis, memory, query
    hit_count BIGINT DEFAULT 0,
    miss_count BIGINT DEFAULT 0,
    hit_ratio DECIMAL(5,2) DEFAULT 0,
    avg_response_time DECIMAL(10,3) DEFAULT 0,
    data_size BIGINT DEFAULT 0,
    ttl INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- API endpoint performance
CREATE TABLE api_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status_code INTEGER NOT NULL,
    response_time DECIMAL(10,3) NOT NULL,
    request_size BIGINT DEFAULT 0,
    response_size BIGINT DEFAULT 0,
    user_id UUID,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Connection pool metrics
CREATE TABLE connection_pool_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_name VARCHAR(100) NOT NULL,
    total_connections INTEGER NOT NULL,
    active_connections INTEGER NOT NULL,
    idle_connections INTEGER NOT NULL,
    waiting_connections INTEGER NOT NULL,
    max_connections INTEGER NOT NULL,
    avg_wait_time DECIMAL(10,3) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Job queue performance
CREATE TABLE job_queue_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    queue_name VARCHAR(100) NOT NULL,
    job_type VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL, -- pending, active, completed, failed
    processing_time DECIMAL(10,3),
    wait_time DECIMAL(10,3),
    retry_count INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- Rate limiting logs
CREATE TABLE rate_limit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ip_address INET NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    requests_count INTEGER NOT NULL,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    blocked BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample application tables with performance optimizations
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    slug VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(20) DEFAULT 'draft',
    published_at TIMESTAMP,
    view_count BIGINT DEFAULT 0,
    like_count BIGINT DEFAULT 0,
    comment_count BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_approved BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    post_count BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE post_tags (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, tag_id)
);

-- Partitioned table for high-volume data
CREATE TABLE analytics_events (
    id UUID DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    user_id UUID,
    session_id UUID,
    properties JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for analytics
CREATE TABLE analytics_events_2024_01 PARTITION OF analytics_events
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE analytics_events_2024_02 PARTITION OF analytics_events
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE analytics_events_2024_03 PARTITION OF analytics_events
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

-- Functions for performance monitoring
CREATE OR REPLACE FUNCTION update_query_performance()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE query_performance 
    SET 
        execution_count = execution_count + 1,
        total_time = total_time + NEW.total_time,
        mean_time = (total_time + NEW.total_time) / (execution_count + 1),
        min_time = LEAST(min_time, NEW.total_time),
        max_time = GREATEST(max_time, NEW.total_time),
        updated_at = CURRENT_TIMESTAMP
    WHERE query_hash = NEW.query_hash;
    
    IF NOT FOUND THEN
        INSERT INTO query_performance (query_hash, query_text, execution_count, total_time, mean_time, min_time, max_time)
        VALUES (NEW.query_hash, NEW.query_text, 1, NEW.total_time, NEW.total_time, NEW.total_time, NEW.total_time);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to get slow queries
CREATE OR REPLACE FUNCTION get_slow_queries(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
    query_text TEXT,
    execution_count BIGINT,
    mean_time DECIMAL,
    total_time DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        qp.query_text,
        qp.execution_count,
        qp.mean_time,
        qp.total_time
    FROM query_performance qp
    ORDER BY qp.mean_time DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function to analyze cache performance
CREATE OR REPLACE FUNCTION analyze_cache_performance()
RETURNS TABLE (
    cache_type VARCHAR,
    total_requests BIGINT,
    hit_ratio DECIMAL,
    avg_response_time DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cp.cache_type,
        (cp.hit_count + cp.miss_count) as total_requests,
        CASE 
            WHEN (cp.hit_count + cp.miss_count) > 0 
            THEN ROUND((cp.hit_count::DECIMAL / (cp.hit_count + cp.miss_count)) * 100, 2)
            ELSE 0
        END as hit_ratio,
        cp.avg_response_time
    FROM cache_performance cp
    GROUP BY cp.cache_type, cp.hit_count, cp.miss_count, cp.avg_response_time
    ORDER BY hit_ratio DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get API performance metrics
CREATE OR REPLACE FUNCTION get_api_performance_summary(hours INTEGER DEFAULT 24)
RETURNS TABLE (
    endpoint VARCHAR,
    method VARCHAR,
    request_count BIGINT,
    avg_response_time DECIMAL,
    p95_response_time DECIMAL,
    error_rate DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ap.endpoint,
        ap.method,
        COUNT(*) as request_count,
        ROUND(AVG(ap.response_time), 3) as avg_response_time,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ap.response_time), 3) as p95_response_time,
        ROUND((COUNT(*) FILTER (WHERE ap.status_code >= 400)::DECIMAL / COUNT(*)) * 100, 2) as error_rate
    FROM api_performance ap
    WHERE ap.created_at >= NOW() - INTERVAL '1 hour' * hours
    GROUP BY ap.endpoint, ap.method
    ORDER BY request_count DESC;
END;
$$ LANGUAGE plpgsql;

-- Materialized view for dashboard metrics
CREATE MATERIALIZED VIEW dashboard_metrics AS
SELECT 
    'users' as metric_type,
    COUNT(*)::TEXT as value,
    'Total Users' as label,
    NOW() as updated_at
FROM users
WHERE is_active = true

UNION ALL

SELECT 
    'posts' as metric_type,
    COUNT(*)::TEXT as value,
    'Total Posts' as label,
    NOW() as updated_at
FROM posts
WHERE status = 'published'

UNION ALL

SELECT 
    'comments' as metric_type,
    COUNT(*)::TEXT as value,
    'Total Comments' as label,
    NOW() as updated_at
FROM comments
WHERE is_approved = true

UNION ALL

SELECT 
    'avg_response_time' as metric_type,
    ROUND(AVG(response_time), 2)::TEXT as value,
    'Avg Response Time (ms)' as label,
    NOW() as updated_at
FROM api_performance
WHERE created_at >= NOW() - INTERVAL '1 hour';

-- Create unique index on materialized view
CREATE UNIQUE INDEX idx_dashboard_metrics_type ON dashboard_metrics(metric_type);

-- Function to refresh dashboard metrics
CREATE OR REPLACE FUNCTION refresh_dashboard_metrics()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_metrics;
END;
$$ LANGUAGE plpgsql;

-- Insert sample data for testing
INSERT INTO users (email, username, password_hash, first_name, last_name) VALUES
('admin@example.com', 'admin', '$2a$10$hash', 'Admin', 'User'),
('user1@example.com', 'user1', '$2a$10$hash', 'John', 'Doe'),
('user2@example.com', 'user2', '$2a$10$hash', 'Jane', 'Smith');

INSERT INTO tags (name, slug, description) VALUES
('Technology', 'technology', 'Technology related posts'),
('Performance', 'performance', 'Performance optimization posts'),
('Database', 'database', 'Database related posts');

-- Insert sample posts
INSERT INTO posts (user_id, title, content, slug, status, published_at) 
SELECT 
    u.id,
    'Sample Post ' || generate_series(1, 100),
    'This is sample content for post ' || generate_series(1, 100),
    'sample-post-' || generate_series(1, 100),
    'published',
    NOW() - INTERVAL '1 day' * (random() * 30)
FROM users u
WHERE u.username = 'admin';

-- Performance monitoring triggers
CREATE OR REPLACE FUNCTION log_api_performance()
RETURNS TRIGGER AS $$
BEGIN
    -- This would be called from application code
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Scheduled job to refresh materialized views
CREATE OR REPLACE FUNCTION schedule_maintenance()
RETURNS VOID AS $$
BEGIN
    -- Refresh dashboard metrics every 5 minutes
    PERFORM refresh_dashboard_metrics();
    
    -- Update table statistics
    ANALYZE users;
    ANALYZE posts;
    ANALYZE comments;
    ANALYZE api_performance;
    
    -- Clean up old performance data (keep 30 days)
    DELETE FROM api_performance WHERE created_at < NOW() - INTERVAL '30 days';
    DELETE FROM cache_performance WHERE created_at < NOW() - INTERVAL '30 days';
    DELETE FROM rate_limit_logs WHERE created_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;
