-- ClickHouse Analytics Database Initialization

-- Create database
CREATE DATABASE IF NOT EXISTS aic_analytics;

-- Use the analytics database
USE aic_analytics;

-- Create users analytics table
CREATE TABLE IF NOT EXISTS users_analytics (
    user_id UInt64,
    email String,
    username String,
    status String,
    registration_date DateTime,
    last_login_date DateTime,
    total_orders UInt32 DEFAULT 0,
    total_spent Decimal(10,2) DEFAULT 0,
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (user_id, registration_date)
PARTITION BY toYYYYMM(registration_date)
TTL registration_date + INTERVAL 7 YEAR;

-- Create orders analytics table
CREATE TABLE IF NOT EXISTS orders_analytics (
    order_id UInt64,
    user_id UInt64,
    status String,
    total_amount Decimal(10,2),
    order_date DateTime,
    completion_date DateTime,
    payment_method String,
    shipping_country String,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (user_id, order_date)
PARTITION BY toYYYYMM(order_date)
TTL order_date + INTERVAL 5 YEAR;

-- Create events analytics table for real-time analytics
CREATE TABLE IF NOT EXISTS events_analytics (
    event_id String,
    event_type String,
    user_id UInt64,
    session_id String,
    event_data String,
    event_timestamp DateTime,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (event_type, event_timestamp)
PARTITION BY toYYYYMMDD(event_timestamp)
TTL event_timestamp + INTERVAL 2 YEAR;

-- Create materialized view for user metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS user_metrics_mv
ENGINE = SummingMergeTree()
ORDER BY (user_id, date)
AS SELECT
    user_id,
    toDate(event_timestamp) as date,
    count() as event_count,
    countIf(event_type = 'page_view') as page_views,
    countIf(event_type = 'purchase') as purchases,
    sumIf(toDecimal64(JSONExtractString(event_data, 'amount'), 2), event_type = 'purchase') as revenue
FROM events_analytics
GROUP BY user_id, date;

-- Create materialized view for daily metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_metrics_mv
ENGINE = SummingMergeTree()
ORDER BY date
AS SELECT
    toDate(event_timestamp) as date,
    count() as total_events,
    uniq(user_id) as unique_users,
    countIf(event_type = 'registration') as new_registrations,
    countIf(event_type = 'purchase') as total_purchases,
    sumIf(toDecimal64(JSONExtractString(event_data, 'amount'), 2), event_type = 'purchase') as total_revenue
FROM events_analytics
GROUP BY date;

-- Create distributed table for multi-node setup (if needed)
CREATE TABLE IF NOT EXISTS events_analytics_distributed AS events_analytics
ENGINE = Distributed('cluster', 'aic_analytics', 'events_analytics', rand());

-- Create Kafka engine table for real-time data ingestion
CREATE TABLE IF NOT EXISTS events_kafka_queue (
    event_id String,
    event_type String,
    user_id UInt64,
    session_id String,
    event_data String,
    event_timestamp DateTime
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'analytics-events',
    kafka_group_name = 'clickhouse-consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2;

-- Create materialized view to move data from Kafka to main table
CREATE MATERIALIZED VIEW IF NOT EXISTS events_kafka_mv TO events_analytics AS
SELECT
    event_id,
    event_type,
    user_id,
    session_id,
    event_data,
    event_timestamp
FROM events_kafka_queue;

-- Create aggregated tables for faster queries
CREATE TABLE IF NOT EXISTS user_daily_stats (
    user_id UInt64,
    date Date,
    page_views UInt32,
    session_duration UInt32,
    purchases UInt32,
    revenue Decimal(10,2)
) ENGINE = SummingMergeTree()
ORDER BY (user_id, date)
PARTITION BY toYYYYMM(date);

CREATE TABLE IF NOT EXISTS product_analytics (
    product_id UInt64,
    product_name String,
    category String,
    views UInt32,
    purchases UInt32,
    revenue Decimal(10,2),
    date Date
) ENGINE = SummingMergeTree()
ORDER BY (product_id, date)
PARTITION BY toYYYYMM(date);

-- Create functions for common analytics queries
CREATE OR REPLACE FUNCTION getUserMetrics(user_id_param UInt64, start_date Date, end_date Date)
RETURNS TABLE (
    total_events UInt64,
    page_views UInt64,
    purchases UInt64,
    total_revenue Decimal(10,2)
) AS $$
SELECT
    count() as total_events,
    countIf(event_type = 'page_view') as page_views,
    countIf(event_type = 'purchase') as purchases,
    sumIf(toDecimal64(JSONExtractString(event_data, 'amount'), 2), event_type = 'purchase') as total_revenue
FROM events_analytics
WHERE user_id = user_id_param
  AND toDate(event_timestamp) BETWEEN start_date AND end_date;
$$;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_events_user_id ON events_analytics (user_id) TYPE minmax GRANULARITY 1;
CREATE INDEX IF NOT EXISTS idx_events_type ON events_analytics (event_type) TYPE set(100) GRANULARITY 1;
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events_analytics (event_timestamp) TYPE minmax GRANULARITY 1;

-- Create sample data for testing
INSERT INTO users_analytics VALUES
(1, 'user1@example.com', 'user1', 'active', '2024-01-01 10:00:00', '2024-06-28 15:30:00', 5, 150.00, now(), now()),
(2, 'user2@example.com', 'user2', 'active', '2024-01-15 14:30:00', '2024-06-27 09:15:00', 3, 89.99, now(), now()),
(3, 'user3@example.com', 'user3', 'inactive', '2024-02-01 09:15:00', '2024-05-15 11:45:00', 1, 25.50, now(), now());

INSERT INTO events_analytics VALUES
('evt1', 'page_view', 1, 'sess1', '{"page": "/home"}', '2024-06-28 10:00:00', now()),
('evt2', 'purchase', 1, 'sess1', '{"amount": "50.00", "product_id": "123"}', '2024-06-28 10:15:00', now()),
('evt3', 'page_view', 2, 'sess2', '{"page": "/products"}', '2024-06-28 11:00:00', now()),
('evt4', 'purchase', 2, 'sess2', '{"amount": "29.99", "product_id": "456"}', '2024-06-28 11:30:00', now());

-- Create views for common business queries
CREATE VIEW IF NOT EXISTS top_users_by_revenue AS
SELECT
    user_id,
    sum(revenue) as total_revenue,
    count() as total_purchases
FROM user_metrics_mv
GROUP BY user_id
ORDER BY total_revenue DESC
LIMIT 100;

CREATE VIEW IF NOT EXISTS daily_revenue_trend AS
SELECT
    date,
    sum(total_revenue) as revenue,
    sum(total_purchases) as purchases,
    sum(unique_users) as active_users
FROM daily_metrics_mv
GROUP BY date
ORDER BY date DESC;

-- Create retention analysis view
CREATE VIEW IF NOT EXISTS user_retention AS
SELECT
    registration_cohort,
    days_since_registration,
    count(DISTINCT user_id) as retained_users,
    retained_users / first_value(retained_users) OVER (PARTITION BY registration_cohort ORDER BY days_since_registration) as retention_rate
FROM (
    SELECT
        u.user_id,
        toStartOfMonth(u.registration_date) as registration_cohort,
        dateDiff('day', u.registration_date, e.event_timestamp) as days_since_registration
    FROM users_analytics u
    JOIN events_analytics e ON u.user_id = e.user_id
    WHERE e.event_timestamp >= u.registration_date
) t
GROUP BY registration_cohort, days_since_registration
ORDER BY registration_cohort, days_since_registration;
