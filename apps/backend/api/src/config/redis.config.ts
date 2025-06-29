import { registerAs } from '@nestjs/config'

/**
 * Redis configuration
 * 
 * Provides comprehensive Redis configuration for caching, sessions,
 * and pub/sub functionality with connection pooling and failover.
 */
export const RedisConfig = registerAs('redis', () => ({
  // Connection
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
  password: process.env.REDIS_PASSWORD,
  username: process.env.REDIS_USERNAME,
  
  // Database Selection
  db: parseInt(process.env.REDIS_DB || '0', 10),
  cacheDb: parseInt(process.env.REDIS_CACHE_DB || '1', 10),
  sessionDb: parseInt(process.env.REDIS_SESSION_DB || '2', 10),
  queueDb: parseInt(process.env.REDIS_QUEUE_DB || '3', 10),
  
  // Connection Pool
  maxRetriesPerRequest: parseInt(process.env.REDIS_MAX_RETRIES || '3', 10),
  retryDelayOnFailover: parseInt(process.env.REDIS_RETRY_DELAY || '100', 10),
  connectTimeout: parseInt(process.env.REDIS_CONNECT_TIMEOUT || '10000', 10), // 10 seconds
  commandTimeout: parseInt(process.env.REDIS_COMMAND_TIMEOUT || '5000', 10), // 5 seconds
  lazyConnect: process.env.REDIS_LAZY_CONNECT === 'true',
  
  // Connection Pool Settings
  family: parseInt(process.env.REDIS_FAMILY || '4', 10), // IPv4
  keepAlive: parseInt(process.env.REDIS_KEEP_ALIVE || '30000', 10), // 30 seconds
  
  // Cluster Configuration (if using Redis Cluster)
  cluster: process.env.REDIS_CLUSTER === 'true' ? {
    enableOfflineQueue: false,
    redisOptions: {
      password: process.env.REDIS_PASSWORD,
    },
    clusterRetryDelayOnFailover: parseInt(process.env.REDIS_CLUSTER_RETRY_DELAY || '100', 10),
    clusterRetryDelayOnClusterDown: parseInt(process.env.REDIS_CLUSTER_DOWN_DELAY || '300', 10),
    clusterMaxRedirections: parseInt(process.env.REDIS_CLUSTER_MAX_REDIRECTIONS || '16', 10),
    scaleReads: process.env.REDIS_CLUSTER_SCALE_READS || 'master',
  } : null,
  
  // Sentinel Configuration (if using Redis Sentinel)
  sentinel: process.env.REDIS_SENTINEL === 'true' ? {
    sentinels: process.env.REDIS_SENTINELS?.split(',').map(sentinel => {
      const [host, port] = sentinel.split(':')
      return { host, port: parseInt(port, 10) }
    }) || [{ host: 'localhost', port: 26379 }],
    name: process.env.REDIS_SENTINEL_NAME || 'mymaster',
    password: process.env.REDIS_SENTINEL_PASSWORD,
    sentinelPassword: process.env.REDIS_SENTINEL_AUTH_PASSWORD,
  } : null,
  
  // Cache Configuration
  cache: {
    ttl: parseInt(process.env.CACHE_TTL || '300', 10), // 5 minutes default
    max: parseInt(process.env.CACHE_MAX_ITEMS || '1000', 10),
    refreshThreshold: parseInt(process.env.CACHE_REFRESH_THRESHOLD || '60', 10), // 1 minute
    
    // Cache key prefixes
    keyPrefix: process.env.CACHE_KEY_PREFIX || 'nexus:cache:',
    sessionPrefix: process.env.SESSION_KEY_PREFIX || 'nexus:session:',
    queuePrefix: process.env.QUEUE_KEY_PREFIX || 'nexus:queue:',
  },
  
  // Session Configuration
  session: {
    secret: process.env.SESSION_SECRET || 'your-super-secret-session-key-change-in-production',
    resave: process.env.SESSION_RESAVE === 'true',
    saveUninitialized: process.env.SESSION_SAVE_UNINITIALIZED === 'false',
    rolling: process.env.SESSION_ROLLING === 'true',
    cookie: {
      secure: process.env.NODE_ENV === 'production',
      httpOnly: true,
      maxAge: parseInt(process.env.SESSION_MAX_AGE || '86400000', 10), // 24 hours
      sameSite: process.env.SESSION_SAME_SITE || 'lax',
    },
  },
  
  // Pub/Sub Configuration
  pubsub: {
    retryDelayOnFailover: parseInt(process.env.PUBSUB_RETRY_DELAY || '100', 10),
    maxRetriesPerRequest: parseInt(process.env.PUBSUB_MAX_RETRIES || '3', 10),
    enableOfflineQueue: process.env.PUBSUB_OFFLINE_QUEUE === 'true',
  },
  
  // Performance Tuning
  performance: {
    // Disable Nagle's algorithm for better performance
    noDelay: process.env.REDIS_NO_DELAY !== 'false',
    
    // Connection pooling
    enableAutoPipelining: process.env.REDIS_AUTO_PIPELINING === 'true',
    maxScriptsCachingTime: parseInt(process.env.REDIS_SCRIPTS_CACHE_TIME || '60000', 10), // 1 minute
    
    // Memory optimization
    dropBufferSupport: process.env.REDIS_DROP_BUFFER_SUPPORT === 'true',
    enableReadyCheck: process.env.REDIS_READY_CHECK !== 'false',
  },
  
  // Monitoring and Logging
  monitoring: {
    enableLogging: process.env.REDIS_LOGGING === 'true' || process.env.NODE_ENV === 'development',
    logLevel: process.env.REDIS_LOG_LEVEL || 'info',
    enableMetrics: process.env.REDIS_METRICS === 'true',
  },
  
  // Health Check
  healthCheck: {
    enabled: process.env.REDIS_HEALTH_CHECK !== 'false',
    interval: parseInt(process.env.REDIS_HEALTH_INTERVAL || '30000', 10), // 30 seconds
    timeout: parseInt(process.env.REDIS_HEALTH_TIMEOUT || '5000', 10), // 5 seconds
  },
}))
