-- Initial Database Schema Migration
-- Version: 1.0.0
-- Description: Create initial tables and indexes for the application

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS analytics;

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    email_verified BOOLEAN DEFAULT FALSE,
    phone VARCHAR(20),
    date_of_birth DATE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 0
);

-- Create indexes for users table
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_status ON users (status);
CREATE INDEX idx_users_created_at ON users (created_at);
CREATE INDEX idx_users_last_login ON users (last_login_at);

-- Products table
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    sku VARCHAR(100) UNIQUE NOT NULL,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    cost DECIMAL(10,2) CHECK (cost >= 0),
    category_id UUID,
    brand VARCHAR(100),
    weight DECIMAL(8,3),
    dimensions JSONB,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'DISCONTINUED')),
    tags TEXT[],
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 0
);

-- Create indexes for products table
CREATE INDEX idx_products_sku ON products (sku);
CREATE INDEX idx_products_name ON products (name);
CREATE INDEX idx_products_category ON products (category_id);
CREATE INDEX idx_products_status ON products (status);
CREATE INDEX idx_products_price ON products (price);
CREATE INDEX idx_products_tags ON products USING GIN (tags);
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Categories table
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES categories(id),
    slug VARCHAR(255) UNIQUE NOT NULL,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for categories table
CREATE INDEX idx_categories_parent ON categories (parent_id);
CREATE INDEX idx_categories_slug ON categories (slug);
CREATE INDEX idx_categories_active ON categories (is_active);

-- Add foreign key constraint for products
ALTER TABLE products ADD CONSTRAINT fk_products_category 
    FOREIGN KEY (category_id) REFERENCES categories(id);

-- Inventory table
CREATE TABLE inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id),
    warehouse_id UUID,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    reserved_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
    reorder_level INTEGER DEFAULT 10,
    max_stock_level INTEGER,
    last_restocked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 0,
    CONSTRAINT chk_inventory_quantities CHECK (reserved_quantity <= quantity)
);

-- Create indexes for inventory table
CREATE INDEX idx_inventory_product ON inventory (product_id);
CREATE INDEX idx_inventory_warehouse ON inventory (warehouse_id);
CREATE INDEX idx_inventory_quantity ON inventory (quantity);
CREATE INDEX idx_inventory_low_stock ON inventory (quantity) WHERE quantity <= reorder_level;

-- Orders table
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number VARCHAR(50) UNIQUE NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' 
        CHECK (status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUNDED')),
    subtotal DECIMAL(10,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    shipping_amount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (shipping_amount >= 0),
    discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    currency VARCHAR(3) DEFAULT 'USD',
    payment_status VARCHAR(20) DEFAULT 'PENDING' 
        CHECK (payment_status IN ('PENDING', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED')),
    shipping_address JSONB,
    billing_address JSONB,
    notes TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 0
);

-- Create indexes for orders table
CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_orders_status ON orders (status);
CREATE INDEX idx_orders_payment_status ON orders (payment_status);
CREATE INDEX idx_orders_created_at ON orders (created_at);
CREATE INDEX idx_orders_total ON orders (total_amount);
CREATE INDEX idx_orders_number ON orders (order_number);

-- Order items table
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    total_price DECIMAL(10,2) NOT NULL CHECK (total_price >= 0),
    product_snapshot JSONB, -- Store product details at time of order
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for order_items table
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);

-- Payments table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id),
    payment_method VARCHAR(50) NOT NULL,
    payment_provider VARCHAR(50),
    provider_transaction_id VARCHAR(255),
    amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' 
        CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED', 'REFUNDED')),
    gateway_response JSONB,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for payments table
CREATE INDEX idx_payments_order ON payments (order_id);
CREATE INDEX idx_payments_status ON payments (status);
CREATE INDEX idx_payments_provider_tx ON payments (provider_transaction_id);
CREATE INDEX idx_payments_created_at ON payments (created_at);

-- Audit log table
CREATE TABLE audit.change_log (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id UUID,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT NOT NULL,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    session_id TEXT,
    ip_address INET
);

-- Create indexes for audit table
CREATE INDEX idx_audit_table_name ON audit.change_log (table_name);
CREATE INDEX idx_audit_record_id ON audit.change_log (record_id);
CREATE INDEX idx_audit_operation ON audit.change_log (operation);
CREATE INDEX idx_audit_changed_at ON audit.change_log (changed_at);
CREATE INDEX idx_audit_changed_by ON audit.change_log (changed_by);

-- Create audit trigger function
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
        session_id
    ) VALUES (
        TG_TABLE_NAME,
        record_id,
        TG_OP,
        old_data,
        new_data,
        current_user,
        current_setting('application_name', true)
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for audit logging
CREATE TRIGGER users_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER products_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER orders_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER inventory_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON inventory
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create updated_at triggers
CREATE TRIGGER users_updated_at_trigger
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER products_updated_at_trigger
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER categories_updated_at_trigger
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER orders_updated_at_trigger
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER inventory_updated_at_trigger
    BEFORE UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER payments_updated_at_trigger
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create analytics views
CREATE VIEW analytics.user_stats AS
SELECT 
    u.id,
    u.email,
    u.status,
    u.created_at as registration_date,
    u.last_login_at,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    COALESCE(AVG(o.total_amount), 0) as avg_order_value
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.email, u.status, u.created_at, u.last_login_at;

CREATE VIEW analytics.product_performance AS
SELECT 
    p.id,
    p.name,
    p.sku,
    p.price,
    COUNT(oi.id) as times_ordered,
    COALESCE(SUM(oi.quantity), 0) as total_quantity_sold,
    COALESCE(SUM(oi.total_price), 0) as total_revenue
FROM products p
LEFT JOIN order_items oi ON p.id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.id
WHERE o.status NOT IN ('CANCELLED', 'REFUNDED')
GROUP BY p.id, p.name, p.sku, p.price;

CREATE VIEW analytics.daily_sales AS
SELECT 
    DATE(created_at) as sale_date,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value,
    COUNT(DISTINCT user_id) as unique_customers
FROM orders
WHERE status NOT IN ('CANCELLED', 'REFUNDED')
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- Insert sample data
INSERT INTO categories (name, description, slug) VALUES
('Electronics', 'Electronic devices and accessories', 'electronics'),
('Clothing', 'Apparel and fashion items', 'clothing'),
('Books', 'Books and educational materials', 'books'),
('Home & Garden', 'Home improvement and garden supplies', 'home-garden');

-- Create sequence for order numbers
CREATE SEQUENCE order_number_seq START 1000;

-- Create function to generate order numbers
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TEXT AS $$
BEGIN
    RETURN 'ORD-' || TO_CHAR(NOW(), 'YYYY') || '-' || LPAD(nextval('order_number_seq')::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-generate order numbers
CREATE OR REPLACE FUNCTION set_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
        NEW.order_number := generate_order_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_set_order_number_trigger
    BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION set_order_number();

-- Create constraint to ensure order total matches items
CREATE OR REPLACE FUNCTION validate_order_total()
RETURNS TRIGGER AS $$
DECLARE
    calculated_subtotal DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(total_price), 0) INTO calculated_subtotal
    FROM order_items
    WHERE order_id = NEW.order_id;
    
    UPDATE orders 
    SET subtotal = calculated_subtotal,
        total_amount = calculated_subtotal + tax_amount + shipping_amount - discount_amount
    WHERE id = NEW.order_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_items_update_total_trigger
    AFTER INSERT OR UPDATE OR DELETE ON order_items
    FOR EACH ROW EXECUTE FUNCTION validate_order_total();
