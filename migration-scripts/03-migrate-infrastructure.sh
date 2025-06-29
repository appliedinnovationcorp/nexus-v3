#!/bin/bash

# Migration Script 03: Infrastructure Layer Migration
# This script migrates data repositories, external services, and messaging infrastructure

set -e

echo "🏗️  Starting Infrastructure Layer Migration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to safely copy files
safe_copy() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        echo -e "${GREEN}✅ Copied $desc: $src -> $dest${NC}"
    elif [ -d "$src" ]; then
        cp -r "$src"/* "$dest"/ 2>/dev/null || true
        echo -e "${GREEN}✅ Copied $desc directory: $src -> $dest${NC}"
    else
        echo -e "${YELLOW}⚠️  Source not found for $desc: $src${NC}"
    fi
}

# Helper function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local desc="$3"
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✅ Created $desc: $file_path${NC}"
}

echo -e "${BLUE}🗄️  Step 1: Creating Repository Interfaces...${NC}"

# Create repository interfaces
create_file "src/Infrastructure/Data/Repositories/IUserRepository.ts" "import { UserAggregate } from '../../../Domain/Aggregates/UserAggregate';

export interface IUserRepository {
  findById(id: string): Promise<UserAggregate | null>;
  findByEmail(email: string): Promise<UserAggregate | null>;
  findMany(options: {
    page: number;
    limit: number;
    search?: string;
  }): Promise<{ users: UserAggregate[]; total: number }>;
  save(userAggregate: UserAggregate): Promise<void>;
  delete(id: string): Promise<void>;
}" "User Repository Interface"

create_file "src/Infrastructure/Data/Repositories/IAuthRepository.ts" "import { AuthAggregate } from '../../../Domain/Aggregates/AuthAggregate';

export interface IAuthRepository {
  findById(id: string): Promise<AuthAggregate | null>;
  findByUserId(userId: string): Promise<AuthAggregate[]>;
  findByToken(token: string): Promise<AuthAggregate | null>;
  save(authAggregate: AuthAggregate): Promise<void>;
  delete(id: string): Promise<void>;
  deleteExpired(): Promise<void>;
}" "Auth Repository Interface"

echo -e "${BLUE}💾 Step 2: Migrating Database Repositories...${NC}"

# Migrate existing repositories
safe_copy "services/user-domain/src/infrastructure/postgres-user-repository.ts" "src/Infrastructure/Data/Repositories/PostgresUserRepository.ts" "Postgres User Repository"
safe_copy "services/user-domain/src/infrastructure/redis-user-read-model.ts" "src/Infrastructure/Data/Repositories/RedisUserReadModel.ts" "Redis User Read Model"

# Create PostgreSQL User Repository
create_file "src/Infrastructure/Data/Repositories/PostgresUserRepository.ts" "import { Pool } from 'pg';
import { IUserRepository } from './IUserRepository';
import { UserAggregate } from '../../../Domain/Aggregates/UserAggregate';
import { User } from '../../../Domain/Entities/User';

export class PostgresUserRepository implements IUserRepository {
  constructor(private readonly pool: Pool) {}

  public async findById(id: string): Promise<UserAggregate | null> {
    const query = 'SELECT * FROM users WHERE id = \$1';
    const result = await this.pool.query(query, [id]);
    
    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    const user = new User(
      row.id,
      row.email,
      row.name,
      row.created_at,
      row.updated_at
    );

    return new UserAggregate(user);
  }

  public async findByEmail(email: string): Promise<UserAggregate | null> {
    const query = 'SELECT * FROM users WHERE email = \$1';
    const result = await this.pool.query(query, [email]);
    
    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    const user = new User(
      row.id,
      row.email,
      row.name,
      row.created_at,
      row.updated_at
    );

    return new UserAggregate(user);
  }

  public async findMany(options: {
    page: number;
    limit: number;
    search?: string;
  }): Promise<{ users: UserAggregate[]; total: number }> {
    const offset = (options.page - 1) * options.limit;
    let query = 'SELECT * FROM users';
    let countQuery = 'SELECT COUNT(*) FROM users';
    const params: any[] = [];

    if (options.search) {
      query += ' WHERE name ILIKE \$1 OR email ILIKE \$1';
      countQuery += ' WHERE name ILIKE \$1 OR email ILIKE \$1';
      params.push(\`%\${options.search}%\`);
    }

    query += \` ORDER BY created_at DESC LIMIT \$\${params.length + 1} OFFSET \$\${params.length + 2}\`;
    params.push(options.limit, offset);

    const [dataResult, countResult] = await Promise.all([
      this.pool.query(query, params),
      this.pool.query(countQuery, options.search ? [params[0]] : [])
    ]);

    const users = dataResult.rows.map(row => {
      const user = new User(
        row.id,
        row.email,
        row.name,
        row.created_at,
        row.updated_at
      );
      return new UserAggregate(user);
    });

    return {
      users,
      total: parseInt(countResult.rows[0].count)
    };
  }

  public async save(userAggregate: UserAggregate): Promise<void> {
    const user = userAggregate.getUser();
    const query = \`
      INSERT INTO users (id, email, name, created_at, updated_at)
      VALUES (\$1, \$2, \$3, \$4, \$5)
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name,
        updated_at = EXCLUDED.updated_at
    \`;

    await this.pool.query(query, [
      user.id,
      user.email,
      user.name,
      user.createdAt,
      user.updatedAt
    ]);
  }

  public async delete(id: string): Promise<void> {
    const query = 'DELETE FROM users WHERE id = \$1';
    await this.pool.query(query, [id]);
  }
}" "PostgreSQL User Repository"

# Create Auth Repository
create_file "src/Infrastructure/Data/Repositories/PostgresAuthRepository.ts" "import { Pool } from 'pg';
import { IAuthRepository } from './IAuthRepository';
import { AuthAggregate } from '../../../Domain/Aggregates/AuthAggregate';
import { Auth } from '../../../Domain/Entities/Auth';

export class PostgresAuthRepository implements IAuthRepository {
  constructor(private readonly pool: Pool) {}

  public async findById(id: string): Promise<AuthAggregate | null> {
    const query = 'SELECT * FROM auths WHERE id = \$1';
    const result = await this.pool.query(query, [id]);
    
    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    const auth = new Auth(
      row.id,
      row.user_id,
      row.provider,
      row.token,
      row.expires_at,
      row.created_at
    );

    return new AuthAggregate(auth);
  }

  public async findByUserId(userId: string): Promise<AuthAggregate[]> {
    const query = 'SELECT * FROM auths WHERE user_id = \$1 ORDER BY created_at DESC';
    const result = await this.pool.query(query, [userId]);
    
    return result.rows.map(row => {
      const auth = new Auth(
        row.id,
        row.user_id,
        row.provider,
        row.token,
        row.expires_at,
        row.created_at
      );
      return new AuthAggregate(auth);
    });
  }

  public async findByToken(token: string): Promise<AuthAggregate | null> {
    const query = 'SELECT * FROM auths WHERE token = \$1 AND expires_at > NOW()';
    const result = await this.pool.query(query, [token]);
    
    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    const auth = new Auth(
      row.id,
      row.user_id,
      row.provider,
      row.token,
      row.expires_at,
      row.created_at
    );

    return new AuthAggregate(auth);
  }

  public async save(authAggregate: AuthAggregate): Promise<void> {
    const auth = authAggregate.getAuth();
    const query = \`
      INSERT INTO auths (id, user_id, provider, token, expires_at, created_at)
      VALUES (\$1, \$2, \$3, \$4, \$5, \$6)
      ON CONFLICT (id) DO UPDATE SET
        token = EXCLUDED.token,
        expires_at = EXCLUDED.expires_at
    \`;

    await this.pool.query(query, [
      auth.id,
      auth.userId,
      auth.provider,
      auth.token,
      auth.expiresAt,
      auth.createdAt
    ]);
  }

  public async delete(id: string): Promise<void> {
    const query = 'DELETE FROM auths WHERE id = \$1';
    await this.pool.query(query, [id]);
  }

  public async deleteExpired(): Promise<void> {
    const query = 'DELETE FROM auths WHERE expires_at <= NOW()';
    await this.pool.query(query);
  }
}" "PostgreSQL Auth Repository"

echo -e "${BLUE}📊 Step 3: Migrating Database Migrations...${NC}"

# Create migrations directory and migrate existing migrations
mkdir -p src/Infrastructure/Data/Migrations

# Migrate existing SQL migrations
if [ -d "database/migrations/sql" ]; then
    safe_copy "database/migrations/sql" "src/Infrastructure/Data/Migrations" "SQL Migrations"
fi

if [ -d "packages/database/src/migrations" ]; then
    safe_copy "packages/database/src/migrations" "src/Infrastructure/Data/Migrations" "Package Migrations"
fi

# Create initial migration
create_file "src/Infrastructure/Data/Migrations/001_initial_schema.sql" "-- Initial database schema
CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Auths table
CREATE TABLE IF NOT EXISTS auths (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    token TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_auths_user_id ON auths(user_id);
CREATE INDEX IF NOT EXISTS idx_auths_token ON auths(token);
CREATE INDEX IF NOT EXISTS idx_auths_expires_at ON auths(expires_at);

-- Updated at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
\$\$ language 'plpgsql';

-- Updated at trigger
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();" "Initial Schema Migration"

echo -e "${BLUE}🔌 Step 4: Creating External Service Interfaces...${NC}"

# Create external service interfaces
create_file "src/Infrastructure/ExternalServices/IEmailService.ts" "export interface IEmailService {
  sendWelcomeEmail(email: string, name: string): Promise<void>;
  sendPasswordResetEmail(email: string, resetToken: string): Promise<void>;
  sendNotificationEmail(email: string, subject: string, content: string): Promise<void>;
}" "Email Service Interface"

create_file "src/Infrastructure/ExternalServices/IPasswordService.ts" "export interface IPasswordService {
  hash(password: string): Promise<string>;
  verify(password: string, hash: string): Promise<boolean>;
}" "Password Service Interface"

create_file "src/Infrastructure/ExternalServices/ITokenService.ts" "export interface ITokenService {
  generate(userId: string): Promise<string>;
  verify(token: string): Promise<{ userId: string; isValid: boolean }>;
  refresh(token: string): Promise<string>;
}" "Token Service Interface"

create_file "src/Infrastructure/ExternalServices/ILogger.ts" "export interface ILogger {
  info(message: string, meta?: any): void;
  error(message: string, meta?: any): void;
  warn(message: string, meta?: any): void;
  debug(message: string, meta?: any): void;
}" "Logger Interface"

create_file "src/Infrastructure/ExternalServices/ISecurityService.ts" "export interface ISecurityService {
  recordFailedLogin(userId: string): Promise<void>;
  checkSuspiciousActivity(userId: string): Promise<boolean>;
  blockUser(userId: string, reason: string): Promise<void>;
}" "Security Service Interface"

echo -e "${BLUE}⚙️  Step 5: Migrating External Service Implementations...${NC}"

# Migrate existing auth services
if [ -d "auth/services/auth-service/src/services" ]; then
    for service_file in auth/services/auth-service/src/services/*.ts; do
        if [ -f "$service_file" ]; then
            filename=$(basename "$service_file")
            safe_copy "$service_file" "src/Infrastructure/ExternalServices/$filename" "Auth Service"
        fi
    done
fi

# Create Email Service implementation
create_file "src/Infrastructure/ExternalServices/NodemailerEmailService.ts" "import nodemailer from 'nodemailer';
import { IEmailService } from './IEmailService';

export class NodemailerEmailService implements IEmailService {
  private transporter: nodemailer.Transporter;

  constructor(config: {
    host: string;
    port: number;
    secure: boolean;
    auth: {
      user: string;
      pass: string;
    };
  }) {
    this.transporter = nodemailer.createTransporter(config);
  }

  public async sendWelcomeEmail(email: string, name: string): Promise<void> {
    const mailOptions = {
      from: process.env.FROM_EMAIL || 'noreply@example.com',
      to: email,
      subject: 'Welcome to our platform!',
      html: \`
        <h1>Welcome, \${name}!</h1>
        <p>Thank you for joining our platform. We're excited to have you on board.</p>
      \`
    };

    await this.transporter.sendMail(mailOptions);
  }

  public async sendPasswordResetEmail(email: string, resetToken: string): Promise<void> {
    const resetUrl = \`\${process.env.FRONTEND_URL}/reset-password?token=\${resetToken}\`;
    
    const mailOptions = {
      from: process.env.FROM_EMAIL || 'noreply@example.com',
      to: email,
      subject: 'Password Reset Request',
      html: \`
        <h1>Password Reset</h1>
        <p>Click the link below to reset your password:</p>
        <a href=\"\${resetUrl}\">Reset Password</a>
        <p>This link will expire in 1 hour.</p>
      \`
    };

    await this.transporter.sendMail(mailOptions);
  }

  public async sendNotificationEmail(email: string, subject: string, content: string): Promise<void> {
    const mailOptions = {
      from: process.env.FROM_EMAIL || 'noreply@example.com',
      to: email,
      subject,
      html: content
    };

    await this.transporter.sendMail(mailOptions);
  }
}" "Nodemailer Email Service"

# Create Password Service implementation
create_file "src/Infrastructure/ExternalServices/BcryptPasswordService.ts" "import bcrypt from 'bcryptjs';
import { IPasswordService } from './IPasswordService';

export class BcryptPasswordService implements IPasswordService {
  private readonly saltRounds = 12;

  public async hash(password: string): Promise<string> {
    return bcrypt.hash(password, this.saltRounds);
  }

  public async verify(password: string, hash: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }
}" "Bcrypt Password Service"

# Create Token Service implementation
create_file "src/Infrastructure/ExternalServices/JwtTokenService.ts" "import jwt from 'jsonwebtoken';
import { ITokenService } from './ITokenService';

export class JwtTokenService implements ITokenService {
  private readonly secret: string;
  private readonly expiresIn: string;

  constructor(secret: string, expiresIn: string = '24h') {
    this.secret = secret;
    this.expiresIn = expiresIn;
  }

  public async generate(userId: string): Promise<string> {
    return jwt.sign({ userId }, this.secret, { expiresIn: this.expiresIn });
  }

  public async verify(token: string): Promise<{ userId: string; isValid: boolean }> {
    try {
      const decoded = jwt.verify(token, this.secret) as { userId: string };
      return { userId: decoded.userId, isValid: true };
    } catch (error) {
      return { userId: '', isValid: false };
    }
  }

  public async refresh(token: string): Promise<string> {
    const { userId, isValid } = await this.verify(token);
    if (!isValid) {
      throw new Error('Invalid token');
    }
    return this.generate(userId);
  }
}" "JWT Token Service"

# Create Logger implementation
create_file "src/Infrastructure/ExternalServices/WinstonLogger.ts" "import winston from 'winston';
import { ILogger } from './ILogger';

export class WinstonLogger implements ILogger {
  private logger: winston.Logger;

  constructor() {
    this.logger = winston.createLogger({
      level: process.env.LOG_LEVEL || 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      transports: [
        new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
        new winston.transports.File({ filename: 'logs/combined.log' }),
        new winston.transports.Console({
          format: winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
          )
        })
      ]
    });
  }

  public info(message: string, meta?: any): void {
    this.logger.info(message, meta);
  }

  public error(message: string, meta?: any): void {
    this.logger.error(message, meta);
  }

  public warn(message: string, meta?: any): void {
    this.logger.warn(message, meta);
  }

  public debug(message: string, meta?: any): void {
    this.logger.debug(message, meta);
  }
}" "Winston Logger"

echo -e "${BLUE}📡 Step 6: Creating Messaging Infrastructure...${NC}"

# Migrate existing event publisher
safe_copy "services/user-domain/src/infrastructure/kafka-event-publisher.ts" "src/Infrastructure/Messaging/EventPublisher.ts" "Event Publisher"

# Create messaging interfaces
create_file "src/Infrastructure/Messaging/IEventPublisher.ts" "import { DomainEvent } from '../../SharedKernel/DomainEvent';

export interface IEventPublisher {
  publish(event: DomainEvent): Promise<void>;
  publishBatch(events: DomainEvent[]): Promise<void>;
}" "Event Publisher Interface"

create_file "src/Infrastructure/Messaging/IEventSubscriber.ts" "import { DomainEvent } from '../../SharedKernel/DomainEvent';

export interface IEventSubscriber {
  subscribe(eventType: string, handler: (event: DomainEvent) => Promise<void>): void;
  unsubscribe(eventType: string): void;
}" "Event Subscriber Interface"

# Create in-memory event publisher for development
create_file "src/Infrastructure/Messaging/InMemoryEventPublisher.ts" "import { IEventPublisher } from './IEventPublisher';
import { DomainEvent } from '../../SharedKernel/DomainEvent';
import { ILogger } from '../ExternalServices/ILogger';

export class InMemoryEventPublisher implements IEventPublisher {
  private handlers: Map<string, Array<(event: DomainEvent) => Promise<void>>> = new Map();

  constructor(private readonly logger: ILogger) {}

  public async publish(event: DomainEvent): Promise<void> {
    const eventName = event.getEventName();
    const handlers = this.handlers.get(eventName) || [];

    this.logger.info(\`Publishing event: \${eventName}\`, { event });

    for (const handler of handlers) {
      try {
        await handler(event);
      } catch (error) {
        this.logger.error(\`Error handling event \${eventName}\`, { error, event });
      }
    }
  }

  public async publishBatch(events: DomainEvent[]): Promise<void> {
    for (const event of events) {
      await this.publish(event);
    }
  }

  public subscribe(eventType: string, handler: (event: DomainEvent) => Promise<void>): void {
    if (!this.handlers.has(eventType)) {
      this.handlers.set(eventType, []);
    }
    this.handlers.get(eventType)!.push(handler);
  }
}" "In-Memory Event Publisher"

echo -e "${BLUE}🔧 Step 7: Creating Database Configuration...${NC}"

# Create database configuration
create_file "src/Infrastructure/Data/DatabaseConfig.ts" "import { Pool } from 'pg';

export class DatabaseConfig {
  private static pool: Pool;

  public static getPool(): Pool {
    if (!this.pool) {
      this.pool = new Pool({
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432'),
        database: process.env.DB_NAME || 'nexus_v3',
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASSWORD || 'password',
        max: parseInt(process.env.DB_POOL_MAX || '20'),
        idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT || '30000'),
        connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT || '2000'),
      });
    }
    return this.pool;
  }

  public static async closePool(): Promise<void> {
    if (this.pool) {
      await this.pool.end();
    }
  }
}" "Database Configuration"

# Create database setup
create_file "src/Infrastructure/Data/DatabaseSetup.ts" "import { Pool } from 'pg';
import { DatabaseConfig } from './DatabaseConfig';
import fs from 'fs';
import path from 'path';

export class DatabaseSetup {
  private pool: Pool;

  constructor() {
    this.pool = DatabaseConfig.getPool();
  }

  public async initialize(): Promise<void> {
    await this.runMigrations();
  }

  private async runMigrations(): Promise<void> {
    const migrationsDir = path.join(__dirname, 'Migrations');
    
    if (!fs.existsSync(migrationsDir)) {
      console.log('No migrations directory found, skipping migrations');
      return;
    }

    const migrationFiles = fs.readdirSync(migrationsDir)
      .filter(file => file.endsWith('.sql'))
      .sort();

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');
      
      try {
        await this.pool.query(sql);
        console.log(\`Migration \${file} executed successfully\`);
      } catch (error) {
        console.error(\`Error executing migration \${file}:\`, error);
        throw error;
      }
    }
  }
}" "Database Setup"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["03-infrastructure"] = "completed" | .current_phase = "04-presentation"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Infrastructure Layer Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Repository Interfaces: $(find src/Infrastructure/Data/Repositories -name "I*.ts" | wc -l) files"
echo -e "  • Repository Implementations: $(find src/Infrastructure/Data/Repositories -name "*.ts" -not -name "I*.ts" | wc -l) files"
echo -e "  • Database Migrations: $(find src/Infrastructure/Data/Migrations -name "*.sql" | wc -l) files"
echo -e "  • External Service Interfaces: $(find src/Infrastructure/ExternalServices -name "I*.ts" | wc -l) files"
echo -e "  • External Service Implementations: $(find src/Infrastructure/ExternalServices -name "*.ts" -not -name "I*.ts" | wc -l) files"
echo -e "  • Messaging Components: $(find src/Infrastructure/Messaging -name "*.ts" | wc -l) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/04-migrate-presentation.sh${NC}"
