-- Frontend Performance Monitoring Database Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Performance audits table
CREATE TABLE performance_audits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    url VARCHAR(500) NOT NULL,
    performance_score INTEGER,
    accessibility_score INTEGER,
    best_practices_score INTEGER,
    seo_score INTEGER,
    pwa_score INTEGER,
    fcp DECIMAL(10,2), -- First Contentful Paint
    lcp DECIMAL(10,2), -- Largest Contentful Paint
    fid DECIMAL(10,2), -- First Input Delay
    cls DECIMAL(10,4), -- Cumulative Layout Shift
    tti DECIMAL(10,2), -- Time to Interactive
    tbt DECIMAL(10,2), -- Total Blocking Time
    si DECIMAL(10,2),  -- Speed Index
    total_byte_weight BIGINT,
    unused_css BIGINT,
    unused_js BIGINT,
    audit_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Real User Monitoring (RUM) metrics
CREATE TABLE rum_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    page VARCHAR(500) NOT NULL,
    fcp DECIMAL(10,2),
    lcp DECIMAL(10,2),
    fid DECIMAL(10,2),
    cls DECIMAL(10,4),
    ttfb DECIMAL(10,2), -- Time to First Byte
    user_agent TEXT,
    connection_type VARCHAR(50),
    session_id VARCHAR(100),
    user_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Performance budgets
CREATE TABLE performance_budgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project VARCHAR(100) NOT NULL,
    page VARCHAR(500) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    budget_value DECIMAL(10,2) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Performance alerts
CREATE TABLE performance_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    audit_id UUID REFERENCES performance_audits(id),
    alert_type VARCHAR(50) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    threshold_value DECIMAL(10,2),
    actual_value DECIMAL(10,2),
    severity VARCHAR(20) DEFAULT 'medium',
    is_resolved BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

-- Bundle analysis results
CREATE TABLE bundle_analysis (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project VARCHAR(100) NOT NULL,
    build_id VARCHAR(100),
    total_size BIGINT,
    gzipped_size BIGINT,
    chunk_count INTEGER,
    asset_count INTEGER,
    analysis_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Image optimization tracking
CREATE TABLE image_optimizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_filename VARCHAR(255) NOT NULL,
    optimized_filename VARCHAR(255) NOT NULL,
    original_size BIGINT,
    optimized_size BIGINT,
    compression_ratio DECIMAL(5,2),
    format_original VARCHAR(10),
    format_optimized VARCHAR(10),
    optimization_settings JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CDN cache performance
CREATE TABLE cdn_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    url VARCHAR(500) NOT NULL,
    cache_status VARCHAR(20), -- HIT, MISS, STALE
    response_time DECIMAL(10,2),
    cache_age INTEGER,
    edge_location VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Service worker metrics
CREATE TABLE sw_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL, -- install, activate, fetch, sync
    cache_hit_ratio DECIMAL(5,2),
    offline_requests INTEGER,
    background_syncs INTEGER,
    push_notifications INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_performance_audits_url_date ON performance_audits(url, created_at DESC);
CREATE INDEX idx_performance_audits_scores ON performance_audits(performance_score, accessibility_score, created_at DESC);
CREATE INDEX idx_rum_metrics_page_date ON rum_metrics(page, created_at DESC);
CREATE INDEX idx_rum_metrics_vitals ON rum_metrics(fcp, lcp, fid, cls, created_at DESC);
CREATE INDEX idx_performance_budgets_project ON performance_budgets(project, is_active);
CREATE INDEX idx_performance_alerts_unresolved ON performance_alerts(is_resolved, created_at DESC);
CREATE INDEX idx_bundle_analysis_project_date ON bundle_analysis(project, created_at DESC);
CREATE INDEX idx_image_optimizations_date ON image_optimizations(created_at DESC);
CREATE INDEX idx_cdn_performance_url_date ON cdn_performance(url, created_at DESC);
CREATE INDEX idx_sw_metrics_type_date ON sw_metrics(event_type, created_at DESC);

-- Insert default performance budgets
INSERT INTO performance_budgets (project, page, metric_name, budget_value) VALUES
('nexus-v3', '/', 'performance', 90),
('nexus-v3', '/', 'accessibility', 95),
('nexus-v3', '/', 'bestPractices', 90),
('nexus-v3', '/', 'seo', 90),
('nexus-v3', '/', 'fcp', 1800),
('nexus-v3', '/', 'lcp', 2500),
('nexus-v3', '/', 'fid', 100),
('nexus-v3', '/', 'cls', 0.1),
('nexus-v3', '/', 'tti', 3800),
('nexus-v3', '/', 'tbt', 300),
('nexus-v3', '/', 'si', 3400);

-- Views for reporting
CREATE VIEW performance_summary AS
SELECT 
    url,
    DATE(created_at) as audit_date,
    AVG(performance_score) as avg_performance,
    AVG(accessibility_score) as avg_accessibility,
    AVG(best_practices_score) as avg_best_practices,
    AVG(seo_score) as avg_seo,
    AVG(fcp) as avg_fcp,
    AVG(lcp) as avg_lcp,
    AVG(fid) as avg_fid,
    AVG(cls) as avg_cls,
    COUNT(*) as audit_count
FROM performance_audits
GROUP BY url, DATE(created_at)
ORDER BY audit_date DESC;

CREATE VIEW rum_summary AS
SELECT 
    page,
    DATE(created_at) as metric_date,
    AVG(fcp) as avg_fcp,
    AVG(lcp) as avg_lcp,
    AVG(fid) as avg_fid,
    AVG(cls) as avg_cls,
    AVG(ttfb) as avg_ttfb,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fcp) as p75_fcp,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lcp) as p75_lcp,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fid) as p75_fid,
    COUNT(*) as sample_count
FROM rum_metrics
GROUP BY page, DATE(created_at)
ORDER BY metric_date DESC;

-- Functions for performance analysis
CREATE OR REPLACE FUNCTION get_performance_trend(
    p_url VARCHAR(500),
    p_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    date DATE,
    performance_score DECIMAL,
    accessibility_score DECIMAL,
    fcp DECIMAL,
    lcp DECIMAL,
    cls DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        DATE(pa.created_at) as date,
        AVG(pa.performance_score)::DECIMAL as performance_score,
        AVG(pa.accessibility_score)::DECIMAL as accessibility_score,
        AVG(pa.fcp)::DECIMAL as fcp,
        AVG(pa.lcp)::DECIMAL as lcp,
        AVG(pa.cls)::DECIMAL as cls
    FROM performance_audits pa
    WHERE pa.url = p_url 
      AND pa.created_at >= CURRENT_DATE - INTERVAL '1 day' * p_days
    GROUP BY DATE(pa.created_at)
    ORDER BY date DESC;
END;
$$ LANGUAGE plpgsql;

-- Trigger for performance alerts
CREATE OR REPLACE FUNCTION check_performance_thresholds()
RETURNS TRIGGER AS $$
DECLARE
    budget_record RECORD;
BEGIN
    -- Check against performance budgets
    FOR budget_record IN 
        SELECT * FROM performance_budgets 
        WHERE project = 'nexus-v3' 
          AND page = NEW.url 
          AND is_active = true
    LOOP
        -- Check if metric violates budget
        CASE budget_record.metric_name
            WHEN 'performance' THEN
                IF NEW.performance_score < budget_record.budget_value THEN
                    INSERT INTO performance_alerts (audit_id, alert_type, metric_name, threshold_value, actual_value, severity)
                    VALUES (NEW.id, 'BUDGET_VIOLATION', 'performance', budget_record.budget_value, NEW.performance_score, 'high');
                END IF;
            WHEN 'fcp' THEN
                IF NEW.fcp > budget_record.budget_value THEN
                    INSERT INTO performance_alerts (audit_id, alert_type, metric_name, threshold_value, actual_value, severity)
                    VALUES (NEW.id, 'BUDGET_VIOLATION', 'fcp', budget_record.budget_value, NEW.fcp, 'medium');
                END IF;
            WHEN 'lcp' THEN
                IF NEW.lcp > budget_record.budget_value THEN
                    INSERT INTO performance_alerts (audit_id, alert_type, metric_name, threshold_value, actual_value, severity)
                    VALUES (NEW.id, 'BUDGET_VIOLATION', 'lcp', budget_record.budget_value, NEW.lcp, 'high');
                END IF;
            WHEN 'cls' THEN
                IF NEW.cls > budget_record.budget_value THEN
                    INSERT INTO performance_alerts (audit_id, alert_type, metric_name, threshold_value, actual_value, severity)
                    VALUES (NEW.id, 'BUDGET_VIOLATION', 'cls', budget_record.budget_value, NEW.cls, 'medium');
                END IF;
        END CASE;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER performance_audit_alert_trigger
    AFTER INSERT ON performance_audits
    FOR EACH ROW
    EXECUTE FUNCTION check_performance_thresholds();
