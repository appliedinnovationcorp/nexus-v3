import { registerAs } from '@nestjs/config'

/**
 * Database configuration
 * 
 * Provides comprehensive database configuration for TypeORM with
 * connection pooling, SSL, and performance optimizations.
 */
export const DatabaseConfig = registerAs('database', () => ({
  // Connection
  url: process.env.DATABASE_URL || 'postgresql://postgres:password@localhost:5432/nexus',
  type: 'postgres' as const,
  
  // Connection Pool
  maxConnections: parseInt(process.env.DB_MAX_CONNECTIONS || '20', 10),
  minConnections: parseInt(process.env.DB_MIN_CONNECTIONS || '5', 10),
  acquireTimeout: parseInt(process.env.DB_ACQUIRE_TIMEOUT || '60000', 10), // 60 seconds
  timeout: parseInt(process.env.DB_TIMEOUT || '30000', 10), // 30 seconds
  
  // SSL Configuration
  ssl: process.env.DB_SSL === 'true' ? {
    rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false',
    ca: process.env.DB_SSL_CA,
    cert: process.env.DB_SSL_CERT,
    key: process.env.DB_SSL_KEY,
  } : false,
  
  // Performance
  synchronize: process.env.NODE_ENV === 'development' && process.env.DB_SYNCHRONIZE !== 'false',
  logging: process.env.DB_LOGGING === 'true' || process.env.NODE_ENV === 'development',
  cache: process.env.DB_CACHE === 'true' ? {
    type: 'redis' as const,
    options: {
      host: process.env.REDIS_HOST || 'localhost',
      port: parseInt(process.env.REDIS_PORT || '6379', 10),
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_CACHE_DB || '1', 10),
    },
    duration: parseInt(process.env.DB_CACHE_DURATION || '30000', 10), // 30 seconds
  } : false,
  
  // Migration
  migrationsRun: process.env.DB_MIGRATIONS_RUN === 'true',
  migrationsTableName: process.env.DB_MIGRATIONS_TABLE || 'migrations',
  
  // Retry Logic
  retryAttempts: parseInt(process.env.DB_RETRY_ATTEMPTS || '3', 10),
  retryDelay: parseInt(process.env.DB_RETRY_DELAY || '3000', 10), // 3 seconds
  
  // Query Performance
  maxQueryExecutionTime: parseInt(process.env.DB_MAX_QUERY_TIME || '10000', 10), // 10 seconds
  
  // Entity Configuration
  entities: ['dist/**/*.entity{.ts,.js}'],
  migrations: ['dist/migrations/*{.ts,.js}'],
  subscribers: ['dist/**/*.subscriber{.ts,.js}'],
  
  // CLI Configuration (for migrations)
  cli: {
    entitiesDir: 'src/entities',
    migrationsDir: 'src/migrations',
    subscribersDir: 'src/subscribers',
  },
  
  // Extra Options
  extra: {
    // Connection pool settings
    max: parseInt(process.env.DB_POOL_MAX || '20', 10),
    min: parseInt(process.env.DB_POOL_MIN || '5', 10),
    idle: parseInt(process.env.DB_POOL_IDLE || '10000', 10), // 10 seconds
    acquire: parseInt(process.env.DB_POOL_ACQUIRE || '60000', 10), // 60 seconds
    evict: parseInt(process.env.DB_POOL_EVICT || '1000', 10), // 1 second
    
    // Connection settings
    idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT || '30000', 10), // 30 seconds
    connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT || '2000', 10), // 2 seconds
    
    // Statement timeout
    statement_timeout: parseInt(process.env.DB_STATEMENT_TIMEOUT || '30000', 10), // 30 seconds
    query_timeout: parseInt(process.env.DB_QUERY_TIMEOUT || '30000', 10), // 30 seconds
    
    // Application name for monitoring
    application_name: process.env.DB_APPLICATION_NAME || 'nexus-api',
  },
}))
