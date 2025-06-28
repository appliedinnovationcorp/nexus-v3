#!/bin/bash
set -e

echo "Initializing PostgreSQL Shard Database..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create extensions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    CREATE EXTENSION IF NOT EXISTS "btree_gin";
    CREATE EXTENSION IF NOT EXISTS "btree_gist";
    
    -- Create application user
    CREATE USER app_shard_user WITH ENCRYPTED PASSWORD 'shard_app_pass';
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO app_shard_user;
    GRANT USAGE ON SCHEMA public TO app_shard_user;
    GRANT CREATE ON SCHEMA public TO app_shard_user;
    
    -- Create shard-specific tables
    CREATE TABLE IF NOT EXISTS users_shard (
        id BIGSERIAL PRIMARY KEY,
        user_id BIGINT NOT NULL,
        email VARCHAR(255) NOT NULL,
        username VARCHAR(100) NOT NULL,
        status VARCHAR(20) DEFAULT 'ACTIVE',
        shard_key BIGINT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        CONSTRAINT users_shard_email_key UNIQUE (email),
        CONSTRAINT users_shard_username_key UNIQUE (username)
    );
    
    CREATE TABLE IF NOT EXISTS orders_shard (
        id BIGSERIAL PRIMARY KEY,
        order_id BIGINT NOT NULL,
        user_id BIGINT NOT NULL,
        status VARCHAR(20) DEFAULT 'PENDING',
        total_amount DECIMAL(10,2) NOT NULL,
        shard_key BIGINT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Create indexes for sharded tables
    CREATE INDEX IF NOT EXISTS idx_users_shard_user_id ON users_shard (user_id);
    CREATE INDEX IF NOT EXISTS idx_users_shard_shard_key ON users_shard (shard_key);
    CREATE INDEX IF NOT EXISTS idx_users_shard_email ON users_shard (email);
    CREATE INDEX IF NOT EXISTS idx_users_shard_status ON users_shard (status);
    
    CREATE INDEX IF NOT EXISTS idx_orders_shard_order_id ON orders_shard (order_id);
    CREATE INDEX IF NOT EXISTS idx_orders_shard_user_id ON orders_shard (user_id);
    CREATE INDEX IF NOT EXISTS idx_orders_shard_shard_key ON orders_shard (shard_key);
    CREATE INDEX IF NOT EXISTS idx_orders_shard_status ON orders_shard (status);
    CREATE INDEX IF NOT EXISTS idx_orders_shard_created_at ON orders_shard (created_at);
    
    -- Create shard metadata table
    CREATE TABLE IF NOT EXISTS shard_metadata (
        shard_id INTEGER PRIMARY KEY,
        shard_name VARCHAR(100) NOT NULL,
        min_key BIGINT NOT NULL,
        max_key BIGINT NOT NULL,
        status VARCHAR(20) DEFAULT 'ACTIVE',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    
    -- Insert shard metadata (this would be different for each shard)
    INSERT INTO shard_metadata (shard_id, shard_name, min_key, max_key) 
    VALUES (1, 'shard_1', 0, 999999)
    ON CONFLICT (shard_id) DO NOTHING;
    
    -- Grant permissions
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_shard_user;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_shard_user;
    
    -- Create function to determine shard key
    CREATE OR REPLACE FUNCTION get_shard_key(input_id BIGINT)
    RETURNS BIGINT AS \$\$
    BEGIN
        RETURN input_id % 1000000;
    END;
    \$\$ LANGUAGE plpgsql IMMUTABLE;
    
    -- Create trigger to automatically set shard_key
    CREATE OR REPLACE FUNCTION set_shard_key()
    RETURNS TRIGGER AS \$\$
    BEGIN
        NEW.shard_key := get_shard_key(NEW.user_id);
        RETURN NEW;
    END;
    \$\$ LANGUAGE plpgsql;
    
    CREATE TRIGGER users_shard_set_shard_key
        BEFORE INSERT ON users_shard
        FOR EACH ROW
        EXECUTE FUNCTION set_shard_key();
        
    CREATE TRIGGER orders_shard_set_shard_key
        BEFORE INSERT ON orders_shard
        FOR EACH ROW
        EXECUTE FUNCTION set_shard_key();
EOSQL

echo "PostgreSQL Shard initialization completed!"
