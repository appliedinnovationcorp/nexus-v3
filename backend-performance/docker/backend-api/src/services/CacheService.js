const Redis = require('ioredis');
const NodeCache = require('node-cache');
const LRU = require('lru-cache');
const winston = require('winston');

class CacheService {
  constructor() {
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'logs/cache-service.log' })
      ]
    });

    // Redis cluster configuration
    this.redis = new Redis.Cluster([
      {
        host: process.env.REDIS_HOST || 'redis-master',
        port: process.env.REDIS_PORT || 6379,
      }
    ], {
      redisOptions: {
        password: process.env.REDIS_PASSWORD,
        retryDelayOnFailover: 100,
        maxRetriesPerRequest: 3,
        lazyConnect: true,
      },
      enableOfflineQueue: false,
      retryDelayOnClusterDown: 300,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
      scaleReads: 'slave',
    });

    // Fallback to single Redis instance if cluster fails
    this.redis.on('error', (err) => {
      this.logger.error('Redis cluster error, falling back to single instance', { error: err.message });
      this.redis = new Redis({
        host: process.env.REDIS_HOST || 'redis-master',
        port: process.env.REDIS_PORT || 6379,
        password: process.env.REDIS_PASSWORD,
        retryDelayOnFailover: 100,
        maxRetriesPerRequest: 3,
        lazyConnect: true,
      });
    });

    // In-memory cache for frequently accessed data
    this.memoryCache = new NodeCache({
      stdTTL: 300, // 5 minutes default TTL
      checkperiod: 60, // Check for expired keys every minute
      useClones: false, // Better performance, but be careful with object mutations
      maxKeys: 10000, // Maximum number of keys
    });

    // LRU cache for query results
    this.queryCache = new LRU({
      max: 1000, // Maximum number of items
      ttl: 1000 * 60 * 15, // 15 minutes TTL
      allowStale: true,
      updateAgeOnGet: true,
    });

    // Cache statistics
    this.stats = {
      redis: { hits: 0, misses: 0, errors: 0 },
      memory: { hits: 0, misses: 0 },
      query: { hits: 0, misses: 0 },
    };

    // Cache invalidation patterns
    this.invalidationPatterns = new Map();
    this.setupInvalidationPatterns();

    // Connect to Redis
    this.connect();
  }

  async connect() {
    try {
      await this.redis.connect();
      this.logger.info('Connected to Redis cache');
    } catch (error) {
      this.logger.error('Failed to connect to Redis', { error: error.message });
    }
  }

  setupInvalidationPatterns() {
    // Define cache invalidation patterns
    this.invalidationPatterns.set('user:*', ['user:list', 'dashboard:stats']);
    this.invalidationPatterns.set('post:*', ['post:list', 'post:popular', 'dashboard:stats']);
    this.invalidationPatterns.set('comment:*', ['comment:list', 'post:*', 'dashboard:stats']);
    this.invalidationPatterns.set('tag:*', ['tag:list', 'post:*']);
  }

  // Multi-layer cache get
  async get(key, options = {}) {
    const { useMemory = true, useQuery = false, useRedis = true } = options;
    
    try {
      // Try memory cache first (fastest)
      if (useMemory) {
        const memoryResult = this.memoryCache.get(key);
        if (memoryResult !== undefined) {
          this.stats.memory.hits++;
          this.logger.debug('Cache hit (memory)', { key });
          return memoryResult;
        }
        this.stats.memory.misses++;
      }

      // Try query cache
      if (useQuery) {
        const queryResult = this.queryCache.get(key);
        if (queryResult !== undefined) {
          this.stats.query.hits++;
          this.logger.debug('Cache hit (query)', { key });
          
          // Populate memory cache for next time
          if (useMemory) {
            this.memoryCache.set(key, queryResult, options.ttl || 300);
          }
          
          return queryResult;
        }
        this.stats.query.misses++;
      }

      // Try Redis cache
      if (useRedis) {
        const redisResult = await this.redis.get(key);
        if (redisResult !== null) {
          this.stats.redis.hits++;
          this.logger.debug('Cache hit (Redis)', { key });
          
          const parsedResult = JSON.parse(redisResult);
          
          // Populate higher-level caches
          if (useMemory) {
            this.memoryCache.set(key, parsedResult, options.ttl || 300);
          }
          if (useQuery) {
            this.queryCache.set(key, parsedResult);
          }
          
          return parsedResult;
        }
        this.stats.redis.misses++;
      }

      return null;
    } catch (error) {
      this.stats.redis.errors++;
      this.logger.error('Cache get error', { key, error: error.message });
      return null;
    }
  }

  // Multi-layer cache set
  async set(key, value, ttl = 3600, options = {}) {
    const { useMemory = true, useQuery = false, useRedis = true } = options;
    
    try {
      const promises = [];

      // Set in Redis
      if (useRedis) {
        promises.push(
          this.redis.setex(key, ttl, JSON.stringify(value))
        );
      }

      // Set in memory cache
      if (useMemory) {
        this.memoryCache.set(key, value, ttl);
      }

      // Set in query cache
      if (useQuery) {
        this.queryCache.set(key, value);
      }

      await Promise.all(promises);
      this.logger.debug('Cache set', { key, ttl });
      
      return true;
    } catch (error) {
      this.stats.redis.errors++;
      this.logger.error('Cache set error', { key, error: error.message });
      return false;
    }
  }

  // Cache with automatic refresh
  async getOrSet(key, fetchFunction, ttl = 3600, options = {}) {
    const cached = await this.get(key, options);
    
    if (cached !== null) {
      return cached;
    }

    try {
      const value = await fetchFunction();
      await this.set(key, value, ttl, options);
      return value;
    } catch (error) {
      this.logger.error('Cache getOrSet error', { key, error: error.message });
      throw error;
    }
  }

  // Batch operations
  async mget(keys, options = {}) {
    try {
      const results = {};
      const redisKeys = [];
      
      // Check memory cache first
      for (const key of keys) {
        const memoryResult = this.memoryCache.get(key);
        if (memoryResult !== undefined) {
          results[key] = memoryResult;
          this.stats.memory.hits++;
        } else {
          redisKeys.push(key);
          this.stats.memory.misses++;
        }
      }

      // Get remaining keys from Redis
      if (redisKeys.length > 0) {
        const redisResults = await this.redis.mget(redisKeys);
        
        for (let i = 0; i < redisKeys.length; i++) {
          const key = redisKeys[i];
          const value = redisResults[i];
          
          if (value !== null) {
            const parsedValue = JSON.parse(value);
            results[key] = parsedValue;
            
            // Populate memory cache
            this.memoryCache.set(key, parsedValue, options.ttl || 300);
            this.stats.redis.hits++;
          } else {
            results[key] = null;
            this.stats.redis.misses++;
          }
        }
      }

      return results;
    } catch (error) {
      this.stats.redis.errors++;
      this.logger.error('Cache mget error', { keys, error: error.message });
      return {};
    }
  }

  async mset(keyValuePairs, ttl = 3600) {
    try {
      const pipeline = this.redis.pipeline();
      
      for (const [key, value] of Object.entries(keyValuePairs)) {
        pipeline.setex(key, ttl, JSON.stringify(value));
        
        // Also set in memory cache
        this.memoryCache.set(key, value, ttl);
      }

      await pipeline.exec();
      this.logger.debug('Cache mset', { count: Object.keys(keyValuePairs).length });
      
      return true;
    } catch (error) {
      this.stats.redis.errors++;
      this.logger.error('Cache mset error', { error: error.message });
      return false;
    }
  }

  // Cache invalidation
  async del(key) {
    try {
      const promises = [
        this.redis.del(key),
      ];

      // Remove from memory caches
      this.memoryCache.del(key);
      this.queryCache.delete(key);

      await Promise.all(promises);
      
      // Trigger pattern-based invalidation
      await this.invalidatePatterns(key);
      
      this.logger.debug('Cache deleted', { key });
      return true;
    } catch (error) {
      this.stats.redis.errors++;
      this.logger.error('Cache delete error', { key, error: error.message });
      return false;
    }
  }

  async invalidatePatterns(key) {
    try {
      for (const [pattern, relatedKeys] of this.invalidationPatterns.entries()) {
        if (this.matchPattern(key, pattern)) {
          for (const relatedKey of relatedKeys) {
            if (relatedKey.includes('*')) {
              // Handle wildcard patterns
              const keys = await this.redis.keys(relatedKey);
              if (keys.length > 0) {
                await this.redis.del(...keys);
                keys.forEach(k => {
                  this.memoryCache.del(k);
                  this.queryCache.delete(k);
                });
              }
            } else {
              await this.del(relatedKey);
            }
          }
        }
      }
    } catch (error) {
      this.logger.error('Pattern invalidation error', { key, error: error.message });
    }
  }

  matchPattern(key, pattern) {
    const regex = new RegExp(pattern.replace(/\*/g, '.*'));
    return regex.test(key);
  }

  // Cache warming
  async warmCache(warmingConfig) {
    this.logger.info('Starting cache warming');
    
    try {
      for (const config of warmingConfig) {
        const { key, fetchFunction, ttl, options } = config;
        
        try {
          const value = await fetchFunction();
          await this.set(key, value, ttl, options);
          this.logger.debug('Cache warmed', { key });
        } catch (error) {
          this.logger.error('Cache warming error', { key, error: error.message });
        }
      }
      
      this.logger.info('Cache warming completed');
    } catch (error) {
      this.logger.error('Cache warming failed', { error: error.message });
    }
  }

  // Cache statistics and monitoring
  getStats() {
    return {
      redis: { ...this.stats.redis },
      memory: { 
        ...this.stats.memory,
        keys: this.memoryCache.keys().length,
        size: this.memoryCache.getStats()
      },
      query: {
        ...this.stats.query,
        size: this.queryCache.size,
        maxSize: this.queryCache.max
      }
    };
  }

  // Cache health check
  async healthCheck() {
    try {
      await this.redis.ping();
      return { status: 'healthy', redis: 'connected' };
    } catch (error) {
      return { status: 'unhealthy', redis: 'disconnected', error: error.message };
    }
  }

  // Cleanup and close connections
  async close() {
    try {
      await this.redis.quit();
      this.memoryCache.close();
      this.queryCache.clear();
      this.logger.info('Cache service closed');
    } catch (error) {
      this.logger.error('Error closing cache service', { error: error.message });
    }
  }

  // Advanced caching strategies
  
  // Cache-aside pattern
  async cacheAside(key, fetchFunction, ttl = 3600) {
    return this.getOrSet(key, fetchFunction, ttl);
  }

  // Write-through pattern
  async writeThrough(key, value, persistFunction, ttl = 3600) {
    try {
      // Write to database first
      await persistFunction(value);
      
      // Then update cache
      await this.set(key, value, ttl);
      
      return value;
    } catch (error) {
      this.logger.error('Write-through error', { key, error: error.message });
      throw error;
    }
  }

  // Write-behind pattern (async write)
  async writeBehind(key, value, persistFunction, ttl = 3600) {
    try {
      // Update cache immediately
      await this.set(key, value, ttl);
      
      // Schedule async write to database
      setImmediate(async () => {
        try {
          await persistFunction(value);
        } catch (error) {
          this.logger.error('Write-behind persist error', { key, error: error.message });
        }
      });
      
      return value;
    } catch (error) {
      this.logger.error('Write-behind error', { key, error: error.message });
      throw error;
    }
  }

  // Refresh-ahead pattern
  async refreshAhead(key, fetchFunction, ttl = 3600, refreshThreshold = 0.8) {
    const cached = await this.get(key);
    
    if (cached !== null) {
      // Check if we need to refresh proactively
      const keyTtl = await this.redis.ttl(key);
      const refreshTime = ttl * refreshThreshold;
      
      if (keyTtl > 0 && keyTtl < refreshTime) {
        // Refresh in background
        setImmediate(async () => {
          try {
            const newValue = await fetchFunction();
            await this.set(key, newValue, ttl);
          } catch (error) {
            this.logger.error('Refresh-ahead error', { key, error: error.message });
          }
        });
      }
      
      return cached;
    }

    // Cache miss, fetch and cache
    return this.getOrSet(key, fetchFunction, ttl);
  }
}

module.exports = CacheService;
