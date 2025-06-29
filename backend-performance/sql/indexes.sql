-- Comprehensive Database Indexing Strategy for Performance Optimization

-- Users table indexes
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);
CREATE INDEX CONCURRENTLY idx_users_username ON users(username);
CREATE INDEX CONCURRENTLY idx_users_active ON users(is_active) WHERE is_active = true;
CREATE INDEX CONCURRENTLY idx_users_last_login ON users(last_login_at DESC) WHERE last_login_at IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_users_created_at ON users(created_at DESC);
CREATE INDEX CONCURRENTLY idx_users_name_search ON users USING gin(to_tsvector('english', first_name || ' ' || last_name));

-- User sessions indexes
CREATE INDEX CONCURRENTLY idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX CONCURRENTLY idx_user_sessions_token ON user_sessions(session_token);
CREATE INDEX CONCURRENTLY idx_user_sessions_expires ON user_sessions(expires_at) WHERE expires_at > NOW();
CREATE INDEX CONCURRENTLY idx_user_sessions_ip ON user_sessions(ip_address);

-- Posts table indexes
CREATE INDEX CONCURRENTLY idx_posts_user_id ON posts(user_id);
CREATE INDEX CONCURRENTLY idx_posts_slug ON posts(slug);
CREATE INDEX CONCURRENTLY idx_posts_status ON posts(status);
CREATE INDEX CONCURRENTLY idx_posts_published ON posts(published_at DESC) WHERE status = 'published';
CREATE INDEX CONCURRENTLY idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX CONCURRENTLY idx_posts_view_count ON posts(view_count DESC);
CREATE INDEX CONCURRENTLY idx_posts_like_count ON posts(like_count DESC);
CREATE INDEX CONCURRENTLY idx_posts_search ON posts USING gin(to_tsvector('english', title || ' ' || content));
CREATE INDEX CONCURRENTLY idx_posts_user_status ON posts(user_id, status);
CREATE INDEX CONCURRENTLY idx_posts_status_published ON posts(status, published_at DESC);

-- Comments table indexes
CREATE INDEX CONCURRENTLY idx_comments_post_id ON comments(post_id);
CREATE INDEX CONCURRENTLY idx_comments_user_id ON comments(user_id);
CREATE INDEX CONCURRENTLY idx_comments_parent_id ON comments(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_comments_approved ON comments(is_approved) WHERE is_approved = true;
CREATE INDEX CONCURRENTLY idx_comments_created_at ON comments(created_at DESC);
CREATE INDEX CONCURRENTLY idx_comments_post_approved ON comments(post_id, is_approved, created_at DESC);

-- Tags table indexes
CREATE INDEX CONCURRENTLY idx_tags_name ON tags(name);
CREATE INDEX CONCURRENTLY idx_tags_slug ON tags(slug);
CREATE INDEX CONCURRENTLY idx_tags_post_count ON tags(post_count DESC);

-- Post tags junction table indexes
CREATE INDEX CONCURRENTLY idx_post_tags_post_id ON post_tags(post_id);
CREATE INDEX CONCURRENTLY idx_post_tags_tag_id ON post_tags(tag_id);

-- Analytics events indexes (partitioned table)
CREATE INDEX CONCURRENTLY idx_analytics_events_type ON analytics_events(event_type);
CREATE INDEX CONCURRENTLY idx_analytics_events_user_id ON analytics_events(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_analytics_events_session_id ON analytics_events(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_analytics_events_created_at ON analytics_events(created_at DESC);
CREATE INDEX CONCURRENTLY idx_analytics_events_ip ON analytics_events(ip_address);
CREATE INDEX CONCURRENTLY idx_analytics_events_properties ON analytics_events USING gin(properties);

-- Performance monitoring indexes
CREATE INDEX CONCURRENTLY idx_query_performance_hash ON query_performance(query_hash);
CREATE INDEX CONCURRENTLY idx_query_performance_mean_time ON query_performance(mean_time DESC);
CREATE INDEX CONCURRENTLY idx_query_performance_execution_count ON query_performance(execution_count DESC);
CREATE INDEX CONCURRENTLY idx_query_performance_updated_at ON query_performance(updated_at DESC);

CREATE INDEX CONCURRENTLY idx_cache_performance_key ON cache_performance(cache_key);
CREATE INDEX CONCURRENTLY idx_cache_performance_type ON cache_performance(cache_type);
CREATE INDEX CONCURRENTLY idx_cache_performance_hit_ratio ON cache_performance(hit_ratio DESC);
CREATE INDEX CONCURRENTLY idx_cache_performance_updated_at ON cache_performance(updated_at DESC);

CREATE INDEX CONCURRENTLY idx_api_performance_endpoint ON api_performance(endpoint);
CREATE INDEX CONCURRENTLY idx_api_performance_method ON api_performance(method);
CREATE INDEX CONCURRENTLY idx_api_performance_status ON api_performance(status_code);
CREATE INDEX CONCURRENTLY idx_api_performance_response_time ON api_performance(response_time DESC);
CREATE INDEX CONCURRENTLY idx_api_performance_created_at ON api_performance(created_at DESC);
CREATE INDEX CONCURRENTLY idx_api_performance_user_id ON api_performance(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_api_performance_ip ON api_performance(ip_address);
CREATE INDEX CONCURRENTLY idx_api_performance_endpoint_method ON api_performance(endpoint, method, created_at DESC);

CREATE INDEX CONCURRENTLY idx_connection_pool_metrics_pool_name ON connection_pool_metrics(pool_name);
CREATE INDEX CONCURRENTLY idx_connection_pool_metrics_created_at ON connection_pool_metrics(created_at DESC);

CREATE INDEX CONCURRENTLY idx_job_queue_metrics_queue_name ON job_queue_metrics(queue_name);
CREATE INDEX CONCURRENTLY idx_job_queue_metrics_job_type ON job_queue_metrics(job_type);
CREATE INDEX CONCURRENTLY idx_job_queue_metrics_status ON job_queue_metrics(status);
CREATE INDEX CONCURRENTLY idx_job_queue_metrics_created_at ON job_queue_metrics(created_at DESC);
CREATE INDEX CONCURRENTLY idx_job_queue_metrics_processing_time ON job_queue_metrics(processing_time DESC) WHERE processing_time IS NOT NULL;

CREATE INDEX CONCURRENTLY idx_rate_limit_logs_ip ON rate_limit_logs(ip_address);
CREATE INDEX CONCURRENTLY idx_rate_limit_logs_endpoint ON rate_limit_logs(endpoint);
CREATE INDEX CONCURRENTLY idx_rate_limit_logs_window ON rate_limit_logs(window_start, window_end);
CREATE INDEX CONCURRENTLY idx_rate_limit_logs_blocked ON rate_limit_logs(blocked) WHERE blocked = true;

-- Composite indexes for common query patterns
CREATE INDEX CONCURRENTLY idx_posts_user_published ON posts(user_id, published_at DESC) WHERE status = 'published';
CREATE INDEX CONCURRENTLY idx_comments_post_approved_created ON comments(post_id, is_approved, created_at DESC);
CREATE INDEX CONCURRENTLY idx_api_perf_endpoint_time ON api_performance(endpoint, created_at DESC, response_time);
CREATE INDEX CONCURRENTLY idx_users_active_login ON users(is_active, last_login_at DESC) WHERE is_active = true;

-- Partial indexes for better performance on filtered queries
CREATE INDEX CONCURRENTLY idx_posts_published_only ON posts(published_at DESC, view_count DESC) WHERE status = 'published';
CREATE INDEX CONCURRENTLY idx_comments_approved_only ON comments(post_id, created_at DESC) WHERE is_approved = true;
CREATE INDEX CONCURRENTLY idx_sessions_active_only ON user_sessions(user_id, created_at DESC) WHERE expires_at > NOW();
CREATE INDEX CONCURRENTLY idx_api_errors_only ON api_performance(endpoint, created_at DESC) WHERE status_code >= 400;
CREATE INDEX CONCURRENTLY idx_slow_queries_only ON api_performance(endpoint, response_time DESC) WHERE response_time > 1000;

-- Expression indexes for computed values
CREATE INDEX CONCURRENTLY idx_posts_title_length ON posts((length(title)));
CREATE INDEX CONCURRENTLY idx_posts_content_length ON posts((length(content)));
CREATE INDEX CONCURRENTLY idx_users_full_name ON users((first_name || ' ' || last_name));
CREATE INDEX CONCURRENTLY idx_api_perf_hour ON api_performance(date_trunc('hour', created_at));
CREATE INDEX CONCURRENTLY idx_analytics_date ON analytics_events(date_trunc('day', created_at));

-- GIN indexes for full-text search and JSON operations
CREATE INDEX CONCURRENTLY idx_posts_fts ON posts USING gin(to_tsvector('english', title || ' ' || coalesce(content, '')));
CREATE INDEX CONCURRENTLY idx_users_fts ON users USING gin(to_tsvector('english', first_name || ' ' || last_name || ' ' || email));
CREATE INDEX CONCURRENTLY idx_analytics_properties_gin ON analytics_events USING gin(properties);

-- BRIN indexes for time-series data (more space-efficient for large tables)
CREATE INDEX CONCURRENTLY idx_api_performance_created_brin ON api_performance USING brin(created_at);
CREATE INDEX CONCURRENTLY idx_analytics_events_created_brin ON analytics_events USING brin(created_at);

-- Hash indexes for exact equality lookups (PostgreSQL 10+)
CREATE INDEX CONCURRENTLY idx_users_email_hash ON users USING hash(email);
CREATE INDEX CONCURRENTLY idx_posts_slug_hash ON posts USING hash(slug);
CREATE INDEX CONCURRENTLY idx_user_sessions_token_hash ON user_sessions USING hash(session_token);

-- Covering indexes (INCLUDE clause) for index-only scans
CREATE INDEX CONCURRENTLY idx_posts_published_covering ON posts(published_at DESC) 
    INCLUDE (id, title, user_id, view_count) WHERE status = 'published';

CREATE INDEX CONCURRENTLY idx_users_active_covering ON users(created_at DESC) 
    INCLUDE (id, email, first_name, last_name) WHERE is_active = true;

CREATE INDEX CONCURRENTLY idx_comments_post_covering ON comments(post_id, created_at DESC) 
    INCLUDE (id, user_id, content) WHERE is_approved = true;

-- Statistics targets for better query planning
ALTER TABLE posts ALTER COLUMN view_count SET STATISTICS 1000;
ALTER TABLE posts ALTER COLUMN like_count SET STATISTICS 1000;
ALTER TABLE api_performance ALTER COLUMN response_time SET STATISTICS 1000;
ALTER TABLE users ALTER COLUMN created_at SET STATISTICS 1000;
ALTER TABLE posts ALTER COLUMN created_at SET STATISTICS 1000;

-- Create custom statistics for correlated columns
CREATE STATISTICS stats_posts_user_status ON user_id, status FROM posts;
CREATE STATISTICS stats_comments_post_approved ON post_id, is_approved FROM comments;
CREATE STATISTICS stats_api_endpoint_method ON endpoint, method FROM api_performance;

-- Analyze tables to update statistics
ANALYZE users;
ANALYZE user_sessions;
ANALYZE posts;
ANALYZE comments;
ANALYZE tags;
ANALYZE post_tags;
ANALYZE analytics_events;
ANALYZE query_performance;
ANALYZE cache_performance;
ANALYZE api_performance;
ANALYZE connection_pool_metrics;
ANALYZE job_queue_metrics;
ANALYZE rate_limit_logs;

-- Create index usage monitoring view
CREATE OR REPLACE VIEW index_usage_stats AS
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan,
    CASE 
        WHEN idx_scan = 0 THEN 'Never Used'
        WHEN idx_scan < 100 THEN 'Rarely Used'
        WHEN idx_scan < 1000 THEN 'Moderately Used'
        ELSE 'Frequently Used'
    END as usage_category,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Create table size monitoring view
CREATE OR REPLACE VIEW table_size_stats AS
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup > 0 
        THEN round((n_dead_tup::float / n_live_tup::float) * 100, 2)
        ELSE 0 
    END as dead_tuple_ratio
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Function to identify missing indexes
CREATE OR REPLACE FUNCTION suggest_missing_indexes()
RETURNS TABLE (
    query_text TEXT,
    calls BIGINT,
    mean_time NUMERIC,
    suggested_index TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pss.query,
        pss.calls,
        pss.mean_exec_time,
        'Consider adding index on frequently filtered columns' as suggested_index
    FROM pg_stat_statements pss
    WHERE pss.mean_exec_time > 100  -- queries taking more than 100ms on average
      AND pss.calls > 10           -- called more than 10 times
      AND pss.query ILIKE '%WHERE%' -- has WHERE clause
    ORDER BY pss.mean_exec_time DESC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- Function to identify unused indexes
CREATE OR REPLACE FUNCTION identify_unused_indexes()
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    index_name TEXT,
    index_size TEXT,
    scans BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pui.schemaname::TEXT,
        pui.tablename::TEXT,
        pui.indexname::TEXT,
        pg_size_pretty(pg_relation_size(pui.indexrelid))::TEXT,
        pui.idx_scan
    FROM pg_stat_user_indexes pui
    WHERE pui.idx_scan < 10  -- Less than 10 scans
      AND pg_relation_size(pui.indexrelid) > 1024 * 1024  -- Larger than 1MB
    ORDER BY pg_relation_size(pui.indexrelid) DESC;
END;
$$ LANGUAGE plpgsql;
