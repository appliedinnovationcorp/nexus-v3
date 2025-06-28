-- Authentication System Database Schema
-- Initialize tables for RBAC, API keys, sessions, and MFA

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create schemas
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS rbac;
CREATE SCHEMA IF NOT EXISTS audit;

-- Users table (extends Keycloak users)
CREATE TABLE auth.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    keycloak_id VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    email_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,
    mfa_enabled BOOLEAN DEFAULT FALSE,
    mfa_secret VARCHAR(255),
    backup_codes TEXT[],
    last_login_at TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    password_changed_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'LOCKED')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 0
);

-- Create indexes for users table
CREATE INDEX idx_users_keycloak_id ON auth.users (keycloak_id);
CREATE INDEX idx_users_email ON auth.users (email);
CREATE INDEX idx_users_username ON auth.users (username);
CREATE INDEX idx_users_status ON auth.users (status);
CREATE INDEX idx_users_mfa_enabled ON auth.users (mfa_enabled);

-- Sessions table
CREATE TABLE auth.sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_token VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ip_address INET,
    user_agent TEXT,
    device_fingerprint VARCHAR(255),
    is_mobile BOOLEAN DEFAULT FALSE,
    location JSONB,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    logout_reason VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for sessions table
CREATE INDEX idx_sessions_token ON auth.sessions (session_token);
CREATE INDEX idx_sessions_user_id ON auth.sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON auth.sessions (expires_at);
CREATE INDEX idx_sessions_active ON auth.sessions (is_active) WHERE is_active = TRUE;

-- API Keys table
CREATE TABLE auth.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key_id VARCHAR(50) UNIQUE NOT NULL,
    key_hash VARCHAR(255) NOT NULL,
    key_prefix VARCHAR(20) NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    scopes TEXT[] DEFAULT '{}',
    rate_limit_per_hour INTEGER DEFAULT 1000,
    rate_limit_per_day INTEGER DEFAULT 10000,
    allowed_ips INET[],
    allowed_domains TEXT[],
    last_used_at TIMESTAMP WITH TIME ZONE,
    usage_count BIGINT DEFAULT 0,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    auto_rotate BOOLEAN DEFAULT FALSE,
    rotation_interval_days INTEGER DEFAULT 90,
    next_rotation_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for API keys table
CREATE INDEX idx_api_keys_key_id ON auth.api_keys (key_id);
CREATE INDEX idx_api_keys_user_id ON auth.api_keys (user_id);
CREATE INDEX idx_api_keys_active ON auth.api_keys (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_api_keys_expires_at ON auth.api_keys (expires_at);
CREATE INDEX idx_api_keys_rotation ON auth.api_keys (next_rotation_at) WHERE auto_rotate = TRUE;

-- MFA Methods table
CREATE TABLE auth.mfa_methods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    method_type VARCHAR(20) NOT NULL CHECK (method_type IN ('TOTP', 'SMS', 'EMAIL', 'WEBAUTHN', 'BACKUP_CODES')),
    method_data JSONB NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    backup_codes TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    verified_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for MFA methods table
CREATE INDEX idx_mfa_methods_user_id ON auth.mfa_methods (user_id);
CREATE INDEX idx_mfa_methods_type ON auth.mfa_methods (method_type);
CREATE INDEX idx_mfa_methods_primary ON auth.mfa_methods (is_primary) WHERE is_primary = TRUE;

-- RBAC: Roles table
CREATE TABLE rbac.roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200),
    description TEXT,
    parent_role_id UUID REFERENCES rbac.roles(id),
    is_system_role BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for roles table
CREATE INDEX idx_roles_name ON rbac.roles (name);
CREATE INDEX idx_roles_parent ON rbac.roles (parent_role_id);
CREATE INDEX idx_roles_active ON rbac.roles (is_active) WHERE is_active = TRUE;

-- RBAC: Permissions table
CREATE TABLE rbac.permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200),
    description TEXT,
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    conditions JSONB DEFAULT '{}',
    is_system_permission BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for permissions table
CREATE INDEX idx_permissions_name ON rbac.permissions (name);
CREATE INDEX idx_permissions_resource ON rbac.permissions (resource);
CREATE INDEX idx_permissions_action ON rbac.permissions (action);
CREATE INDEX idx_permissions_resource_action ON rbac.permissions (resource, action);

-- RBAC: Role-Permission mapping
CREATE TABLE rbac.role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id UUID NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES rbac.permissions(id) ON DELETE CASCADE,
    granted_by UUID REFERENCES auth.users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    conditions JSONB DEFAULT '{}',
    UNIQUE(role_id, permission_id)
);

-- Create indexes for role-permissions table
CREATE INDEX idx_role_permissions_role ON rbac.role_permissions (role_id);
CREATE INDEX idx_role_permissions_permission ON rbac.role_permissions (permission_id);

-- RBAC: User-Role mapping
CREATE TABLE rbac.user_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES auth.users(id),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    conditions JSONB DEFAULT '{}',
    UNIQUE(user_id, role_id)
);

-- Create indexes for user-roles table
CREATE INDEX idx_user_roles_user ON rbac.user_roles (user_id);
CREATE INDEX idx_user_roles_role ON rbac.user_roles (role_id);
CREATE INDEX idx_user_roles_active ON rbac.user_roles (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_user_roles_expires ON rbac.user_roles (expires_at);

-- RBAC: Groups table
CREATE TABLE rbac.groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200),
    description TEXT,
    parent_group_id UUID REFERENCES rbac.groups(id),
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for groups table
CREATE INDEX idx_groups_name ON rbac.groups (name);
CREATE INDEX idx_groups_parent ON rbac.groups (parent_group_id);
CREATE INDEX idx_groups_active ON rbac.groups (is_active) WHERE is_active = TRUE;

-- RBAC: User-Group mapping
CREATE TABLE rbac.user_groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES rbac.groups(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES auth.users(id),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(user_id, group_id)
);

-- Create indexes for user-groups table
CREATE INDEX idx_user_groups_user ON rbac.user_groups (user_id);
CREATE INDEX idx_user_groups_group ON rbac.user_groups (group_id);
CREATE INDEX idx_user_groups_active ON rbac.user_groups (is_active) WHERE is_active = TRUE;

-- RBAC: Group-Role mapping
CREATE TABLE rbac.group_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES rbac.groups(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES auth.users(id),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(group_id, role_id)
);

-- Create indexes for group-roles table
CREATE INDEX idx_group_roles_group ON rbac.group_roles (group_id);
CREATE INDEX idx_group_roles_role ON rbac.group_roles (role_id);
CREATE INDEX idx_group_roles_active ON rbac.group_roles (is_active) WHERE is_active = TRUE;

-- Audit Log table
CREATE TABLE audit.auth_events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    session_id UUID REFERENCES auth.sessions(id),
    api_key_id UUID REFERENCES auth.api_keys(id),
    ip_address INET,
    user_agent TEXT,
    resource VARCHAR(200),
    action VARCHAR(100),
    result VARCHAR(20) NOT NULL CHECK (result IN ('SUCCESS', 'FAILURE', 'ERROR')),
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for audit table
CREATE INDEX idx_auth_events_type ON audit.auth_events (event_type);
CREATE INDEX idx_auth_events_user ON audit.auth_events (user_id);
CREATE INDEX idx_auth_events_created_at ON audit.auth_events (created_at);
CREATE INDEX idx_auth_events_result ON audit.auth_events (result);
CREATE INDEX idx_auth_events_ip ON audit.auth_events (ip_address);

-- JWT Blacklist table
CREATE TABLE auth.jwt_blacklist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    jti VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID REFERENCES auth.users(id),
    token_type VARCHAR(20) NOT NULL CHECK (token_type IN ('ACCESS', 'REFRESH')),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    blacklisted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reason VARCHAR(100)
);

-- Create indexes for JWT blacklist table
CREATE INDEX idx_jwt_blacklist_jti ON auth.jwt_blacklist (jti);
CREATE INDEX idx_jwt_blacklist_expires ON auth.jwt_blacklist (expires_at);
CREATE INDEX idx_jwt_blacklist_user ON auth.jwt_blacklist (user_id);

-- Rate Limiting table
CREATE TABLE auth.rate_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    identifier VARCHAR(255) NOT NULL,
    identifier_type VARCHAR(20) NOT NULL CHECK (identifier_type IN ('IP', 'USER', 'API_KEY')),
    endpoint VARCHAR(200),
    request_count INTEGER DEFAULT 1,
    window_start TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    window_end TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(identifier, identifier_type, endpoint, window_start)
);

-- Create indexes for rate limits table
CREATE INDEX idx_rate_limits_identifier ON auth.rate_limits (identifier, identifier_type);
CREATE INDEX idx_rate_limits_window ON auth.rate_limits (window_end);
CREATE INDEX idx_rate_limits_endpoint ON auth.rate_limits (endpoint);

-- Functions for RBAC
CREATE OR REPLACE FUNCTION rbac.get_user_permissions(p_user_id UUID)
RETURNS TABLE (
    permission_name VARCHAR(100),
    resource VARCHAR(100),
    action VARCHAR(50),
    conditions JSONB
) AS $$
BEGIN
    RETURN QUERY
    WITH user_direct_roles AS (
        SELECT ur.role_id
        FROM rbac.user_roles ur
        WHERE ur.user_id = p_user_id
        AND ur.is_active = TRUE
        AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
    ),
    user_group_roles AS (
        SELECT gr.role_id
        FROM rbac.user_groups ug
        JOIN rbac.group_roles gr ON ug.group_id = gr.group_id
        WHERE ug.user_id = p_user_id
        AND ug.is_active = TRUE
        AND gr.is_active = TRUE
    ),
    all_user_roles AS (
        SELECT role_id FROM user_direct_roles
        UNION
        SELECT role_id FROM user_group_roles
    )
    SELECT DISTINCT
        p.name,
        p.resource,
        p.action,
        COALESCE(rp.conditions, p.conditions) as conditions
    FROM all_user_roles aur
    JOIN rbac.role_permissions rp ON aur.role_id = rp.role_id
    JOIN rbac.permissions p ON rp.permission_id = p.id
    JOIN rbac.roles r ON aur.role_id = r.id
    WHERE r.is_active = TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to check user permission
CREATE OR REPLACE FUNCTION rbac.check_user_permission(
    p_user_id UUID,
    p_resource VARCHAR(100),
    p_action VARCHAR(50)
) RETURNS BOOLEAN AS $$
DECLARE
    has_permission BOOLEAN := FALSE;
BEGIN
    SELECT EXISTS(
        SELECT 1
        FROM rbac.get_user_permissions(p_user_id) up
        WHERE up.resource = p_resource
        AND up.action = p_action
    ) INTO has_permission;
    
    RETURN has_permission;
END;
$$ LANGUAGE plpgsql;

-- Function to log authentication events
CREATE OR REPLACE FUNCTION audit.log_auth_event(
    p_event_type VARCHAR(50),
    p_user_id UUID DEFAULT NULL,
    p_session_id UUID DEFAULT NULL,
    p_api_key_id UUID DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_resource VARCHAR(200) DEFAULT NULL,
    p_action VARCHAR(100) DEFAULT NULL,
    p_result VARCHAR(20) DEFAULT 'SUCCESS',
    p_error_message TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    event_id BIGINT;
BEGIN
    INSERT INTO audit.auth_events (
        event_type, user_id, session_id, api_key_id, ip_address,
        user_agent, resource, action, result, error_message, metadata
    ) VALUES (
        p_event_type, p_user_id, p_session_id, p_api_key_id, p_ip_address,
        p_user_agent, p_resource, p_action, p_result, p_error_message, p_metadata
    ) RETURNING id INTO event_id;
    
    RETURN event_id;
END;
$$ LANGUAGE plpgsql;

-- Function to clean expired sessions
CREATE OR REPLACE FUNCTION auth.cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM auth.sessions
    WHERE expires_at < NOW()
    OR (last_activity_at < NOW() - INTERVAL '30 days' AND is_active = FALSE);
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to clean expired JWT blacklist entries
CREATE OR REPLACE FUNCTION auth.cleanup_expired_jwt_blacklist()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM auth.jwt_blacklist
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to rotate API keys
CREATE OR REPLACE FUNCTION auth.rotate_api_key(p_key_id VARCHAR(50))
RETURNS TABLE (
    new_key_id VARCHAR(50),
    new_key_hash VARCHAR(255),
    new_key_prefix VARCHAR(20)
) AS $$
DECLARE
    new_id VARCHAR(50);
    new_hash VARCHAR(255);
    new_prefix VARCHAR(20);
    new_key VARCHAR(64);
BEGIN
    -- Generate new API key
    new_key := encode(gen_random_bytes(32), 'hex');
    new_id := 'ak_' || encode(gen_random_bytes(16), 'hex');
    new_prefix := substring(new_key from 1 for 8);
    new_hash := crypt(new_key, gen_salt('bf', 12));
    
    -- Update the existing key
    UPDATE auth.api_keys
    SET key_id = new_id,
        key_hash = new_hash,
        key_prefix = new_prefix,
        next_rotation_at = CASE 
            WHEN auto_rotate THEN NOW() + (rotation_interval_days || ' days')::INTERVAL
            ELSE NULL
        END,
        updated_at = NOW()
    WHERE key_id = p_key_id;
    
    RETURN QUERY SELECT new_id, new_hash, new_prefix;
END;
$$ LANGUAGE plpgsql;

-- Insert default roles and permissions
INSERT INTO rbac.roles (name, display_name, description, is_system_role) VALUES
('super_admin', 'Super Administrator', 'Full system access', TRUE),
('admin', 'Administrator', 'Administrative access', TRUE),
('user_manager', 'User Manager', 'User management access', TRUE),
('user', 'Regular User', 'Standard user access', TRUE),
('api_user', 'API User', 'API access only', TRUE),
('readonly', 'Read Only', 'Read-only access', TRUE);

-- Insert default permissions
INSERT INTO rbac.permissions (name, display_name, resource, action, is_system_permission) VALUES
-- User management
('users.create', 'Create Users', 'users', 'create', TRUE),
('users.read', 'Read Users', 'users', 'read', TRUE),
('users.update', 'Update Users', 'users', 'update', TRUE),
('users.delete', 'Delete Users', 'users', 'delete', TRUE),
('users.list', 'List Users', 'users', 'list', TRUE),

-- Role management
('roles.create', 'Create Roles', 'roles', 'create', TRUE),
('roles.read', 'Read Roles', 'roles', 'read', TRUE),
('roles.update', 'Update Roles', 'roles', 'update', TRUE),
('roles.delete', 'Delete Roles', 'roles', 'delete', TRUE),
('roles.assign', 'Assign Roles', 'roles', 'assign', TRUE),

-- API key management
('api_keys.create', 'Create API Keys', 'api_keys', 'create', TRUE),
('api_keys.read', 'Read API Keys', 'api_keys', 'read', TRUE),
('api_keys.update', 'Update API Keys', 'api_keys', 'update', TRUE),
('api_keys.delete', 'Delete API Keys', 'api_keys', 'delete', TRUE),
('api_keys.rotate', 'Rotate API Keys', 'api_keys', 'rotate', TRUE),

-- System administration
('system.admin', 'System Administration', 'system', 'admin', TRUE),
('system.monitor', 'System Monitoring', 'system', 'monitor', TRUE),
('audit.read', 'Read Audit Logs', 'audit', 'read', TRUE);

-- Assign permissions to roles
WITH role_permission_mappings AS (
    SELECT 
        r.id as role_id,
        p.id as permission_id
    FROM rbac.roles r
    CROSS JOIN rbac.permissions p
    WHERE 
        (r.name = 'super_admin') OR
        (r.name = 'admin' AND p.name NOT LIKE 'system.%') OR
        (r.name = 'user_manager' AND p.name LIKE 'users.%') OR
        (r.name = 'user' AND p.name IN ('users.read', 'api_keys.read', 'api_keys.create')) OR
        (r.name = 'api_user' AND p.name LIKE 'api_keys.%') OR
        (r.name = 'readonly' AND p.action = 'read')
)
INSERT INTO rbac.role_permissions (role_id, permission_id)
SELECT role_id, permission_id FROM role_permission_mappings;

-- Create triggers for updated_at columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    IF TG_TABLE_NAME IN ('users', 'api_keys') THEN
        NEW.version = OLD.version + 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at_trigger
    BEFORE UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER api_keys_updated_at_trigger
    BEFORE UPDATE ON auth.api_keys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER roles_updated_at_trigger
    BEFORE UPDATE ON rbac.roles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER groups_updated_at_trigger
    BEFORE UPDATE ON rbac.groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
