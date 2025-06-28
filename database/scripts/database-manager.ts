import { Pool, PoolClient } from 'pg';
import Redis from 'ioredis';
import { ClickHouse } from '@clickhouse/client';

// Database connection configuration
interface DatabaseConfig {
  primary: {
    host: string;
    port: number;
    database: string;
    username: string;
    password: string;
  };
  replicas: Array<{
    host: string;
    port: number;
    database: string;
    username: string;
    password: string;
  }>;
  shards: Array<{
    id: number;
    host: string;
    port: number;
    database: string;
    username: string;
    password: string;
    minKey: number;
    maxKey: number;
  }>;
  clickhouse: {
    host: string;
    port: number;
    database: string;
    username: string;
    password: string;
  };
  redis: {
    host: string;
    port: number;
    password?: string;
  };
}

// Shard routing strategy
export class ShardRouter {
  private shards: DatabaseConfig['shards'];

  constructor(shards: DatabaseConfig['shards']) {
    this.shards = shards.sort((a, b) => a.minKey - b.minKey);
  }

  getShardForKey(key: number): DatabaseConfig['shards'][0] {
    const shard = this.shards.find(s => key >= s.minKey && key <= s.maxKey);
    if (!shard) {
      throw new Error(`No shard found for key: ${key}`);
    }
    return shard;
  }

  getShardForUserId(userId: string): DatabaseConfig['shards'][0] {
    // Simple hash-based sharding
    const hash = this.hashString(userId);
    const shardKey = hash % 1000000; // Assuming 1M keys per shard
    return this.getShardForKey(shardKey);
  }

  private hashString(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash);
  }

  getAllShards(): DatabaseConfig['shards'] {
    return [...this.shards];
  }
}

// Connection pool manager
export class ConnectionPoolManager {
  private primaryPool: Pool;
  private replicaPools: Pool[] = [];
  private shardPools: Map<number, Pool> = new Map();
  private clickhouseClient: ClickHouse;
  private redisClient: Redis;
  private shardRouter: ShardRouter;
  private replicaIndex = 0;

  constructor(private config: DatabaseConfig) {
    this.shardRouter = new ShardRouter(config.shards);
    this.initializePools();
  }

  private initializePools(): void {
    // Initialize primary pool
    this.primaryPool = new Pool({
      host: this.config.primary.host,
      port: this.config.primary.port,
      database: this.config.primary.database,
      user: this.config.primary.username,
      password: this.config.primary.password,
      max: 20,
      min: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      statement_timeout: 30000,
      query_timeout: 30000,
    });

    // Initialize replica pools
    this.config.replicas.forEach(replica => {
      const pool = new Pool({
        host: replica.host,
        port: replica.port,
        database: replica.database,
        user: replica.username,
        password: replica.password,
        max: 15,
        min: 3,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 5000,
        statement_timeout: 30000,
        query_timeout: 30000,
      });
      this.replicaPools.push(pool);
    });

    // Initialize shard pools
    this.config.shards.forEach(shard => {
      const pool = new Pool({
        host: shard.host,
        port: shard.port,
        database: shard.database,
        user: shard.username,
        password: shard.password,
        max: 10,
        min: 2,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 5000,
        statement_timeout: 30000,
        query_timeout: 30000,
      });
      this.shardPools.set(shard.id, pool);
    });

    // Initialize ClickHouse client
    this.clickhouseClient = new ClickHouse({
      host: `http://${this.config.clickhouse.host}:${this.config.clickhouse.port}`,
      database: this.config.clickhouse.database,
      username: this.config.clickhouse.username,
      password: this.config.clickhouse.password,
      request_timeout: 30000,
      max_open_connections: 10,
    });

    // Initialize Redis client
    this.redisClient = new Redis({
      host: this.config.redis.host,
      port: this.config.redis.port,
      password: this.config.redis.password,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    });
  }

  // Get primary connection for writes
  async getPrimaryConnection(): Promise<PoolClient> {
    return this.primaryPool.connect();
  }

  // Get replica connection for reads (round-robin)
  async getReplicaConnection(): Promise<PoolClient> {
    if (this.replicaPools.length === 0) {
      return this.getPrimaryConnection();
    }

    const pool = this.replicaPools[this.replicaIndex];
    this.replicaIndex = (this.replicaIndex + 1) % this.replicaPools.length;
    
    try {
      return await pool.connect();
    } catch (error) {
      console.warn('Replica connection failed, falling back to primary:', error);
      return this.getPrimaryConnection();
    }
  }

  // Get shard connection
  async getShardConnection(userId: string): Promise<PoolClient> {
    const shard = this.shardRouter.getShardForUserId(userId);
    const pool = this.shardPools.get(shard.id);
    
    if (!pool) {
      throw new Error(`No pool found for shard ${shard.id}`);
    }

    return pool.connect();
  }

  // Get ClickHouse client
  getClickHouseClient(): ClickHouse {
    return this.clickhouseClient;
  }

  // Get Redis client
  getRedisClient(): Redis {
    return this.redisClient;
  }

  // Execute query on primary
  async executeOnPrimary<T = any>(query: string, params?: any[]): Promise<T[]> {
    const client = await this.getPrimaryConnection();
    try {
      const result = await client.query(query, params);
      return result.rows;
    } finally {
      client.release();
    }
  }

  // Execute query on replica
  async executeOnReplica<T = any>(query: string, params?: any[]): Promise<T[]> {
    const client = await this.getReplicaConnection();
    try {
      const result = await client.query(query, params);
      return result.rows;
    } finally {
      client.release();
    }
  }

  // Execute query on shard
  async executeOnShard<T = any>(userId: string, query: string, params?: any[]): Promise<T[]> {
    const client = await this.getShardConnection(userId);
    try {
      const result = await client.query(query, params);
      return result.rows;
    } finally {
      client.release();
    }
  }

  // Execute query on all shards and aggregate results
  async executeOnAllShards<T = any>(query: string, params?: any[]): Promise<T[]> {
    const promises = this.shardRouter.getAllShards().map(async (shard) => {
      const pool = this.shardPools.get(shard.id);
      if (!pool) return [];

      const client = await pool.connect();
      try {
        const result = await client.query(query, params);
        return result.rows;
      } finally {
        client.release();
      }
    });

    const results = await Promise.all(promises);
    return results.flat();
  }

  // Execute analytics query on ClickHouse
  async executeAnalyticsQuery<T = any>(query: string): Promise<T[]> {
    const result = await this.clickhouseClient.query({
      query,
      format: 'JSONEachRow',
    });
    
    const data = await result.json<T>();
    return Array.isArray(data) ? data : [data];
  }

  // Cache operations
  async cacheGet(key: string): Promise<string | null> {
    return this.redisClient.get(key);
  }

  async cacheSet(key: string, value: string, ttl?: number): Promise<void> {
    if (ttl) {
      await this.redisClient.setex(key, ttl, value);
    } else {
      await this.redisClient.set(key, value);
    }
  }

  async cacheDel(key: string): Promise<void> {
    await this.redisClient.del(key);
  }

  // Health checks
  async checkHealth(): Promise<{
    primary: boolean;
    replicas: boolean[];
    shards: boolean[];
    clickhouse: boolean;
    redis: boolean;
  }> {
    const health = {
      primary: false,
      replicas: [] as boolean[],
      shards: [] as boolean[],
      clickhouse: false,
      redis: false,
    };

    // Check primary
    try {
      await this.executeOnPrimary('SELECT 1');
      health.primary = true;
    } catch (error) {
      console.error('Primary health check failed:', error);
    }

    // Check replicas
    for (let i = 0; i < this.replicaPools.length; i++) {
      try {
        const client = await this.replicaPools[i].connect();
        await client.query('SELECT 1');
        client.release();
        health.replicas[i] = true;
      } catch (error) {
        console.error(`Replica ${i} health check failed:`, error);
        health.replicas[i] = false;
      }
    }

    // Check shards
    for (const [shardId, pool] of this.shardPools) {
      try {
        const client = await pool.connect();
        await client.query('SELECT 1');
        client.release();
        health.shards[shardId - 1] = true;
      } catch (error) {
        console.error(`Shard ${shardId} health check failed:`, error);
        health.shards[shardId - 1] = false;
      }
    }

    // Check ClickHouse
    try {
      await this.clickhouseClient.query({ query: 'SELECT 1' });
      health.clickhouse = true;
    } catch (error) {
      console.error('ClickHouse health check failed:', error);
    }

    // Check Redis
    try {
      await this.redisClient.ping();
      health.redis = true;
    } catch (error) {
      console.error('Redis health check failed:', error);
    }

    return health;
  }

  // Graceful shutdown
  async close(): Promise<void> {
    const closePromises: Promise<void>[] = [];

    // Close primary pool
    closePromises.push(this.primaryPool.end());

    // Close replica pools
    this.replicaPools.forEach(pool => {
      closePromises.push(pool.end());
    });

    // Close shard pools
    this.shardPools.forEach(pool => {
      closePromises.push(pool.end());
    });

    // Close ClickHouse client
    closePromises.push(this.clickhouseClient.close());

    // Close Redis client
    closePromises.push(this.redisClient.quit());

    await Promise.all(closePromises);
  }
}

// Database manager with high-level operations
export class DatabaseManager {
  constructor(private poolManager: ConnectionPoolManager) {}

  // User operations with sharding
  async createUser(userData: any): Promise<string> {
    const userId = userData.id || require('crypto').randomUUID();
    
    // Insert into primary database
    await this.poolManager.executeOnPrimary(
      'INSERT INTO users (id, email, username, password_hash) VALUES ($1, $2, $3, $4)',
      [userId, userData.email, userData.username, userData.passwordHash]
    );

    // Insert into appropriate shard
    await this.poolManager.executeOnShard(
      userId,
      'INSERT INTO users_shard (user_id, email, username, shard_key) VALUES ($1, $2, $3, $4)',
      [userId, userData.email, userData.username, this.getShardKey(userId)]
    );

    // Cache user data
    await this.poolManager.cacheSet(
      `user:${userId}`,
      JSON.stringify(userData),
      3600 // 1 hour TTL
    );

    return userId;
  }

  async getUserById(userId: string): Promise<any> {
    // Try cache first
    const cached = await this.poolManager.cacheGet(`user:${userId}`);
    if (cached) {
      return JSON.parse(cached);
    }

    // Query from replica
    const users = await this.poolManager.executeOnReplica(
      'SELECT * FROM users WHERE id = $1',
      [userId]
    );

    if (users.length > 0) {
      // Cache the result
      await this.poolManager.cacheSet(
        `user:${userId}`,
        JSON.stringify(users[0]),
        3600
      );
      return users[0];
    }

    return null;
  }

  // Analytics operations
  async getUserAnalytics(userId: string, startDate: Date, endDate: Date): Promise<any> {
    const query = `
      SELECT 
        count() as total_events,
        countIf(event_type = 'page_view') as page_views,
        countIf(event_type = 'purchase') as purchases,
        sumIf(toDecimal64(JSONExtractString(event_data, 'amount'), 2), event_type = 'purchase') as total_revenue
      FROM events_analytics
      WHERE user_id = {userId:UInt64}
        AND event_timestamp BETWEEN {startDate:DateTime} AND {endDate:DateTime}
    `;

    const results = await this.poolManager.executeAnalyticsQuery(query);
    return results[0] || {};
  }

  async getDailyMetrics(date: Date): Promise<any> {
    const query = `
      SELECT 
        toDate(event_timestamp) as date,
        count() as total_events,
        uniq(user_id) as unique_users,
        countIf(event_type = 'purchase') as purchases,
        sumIf(toDecimal64(JSONExtractString(event_data, 'amount'), 2), event_type = 'purchase') as revenue
      FROM events_analytics
      WHERE toDate(event_timestamp) = {date:Date}
      GROUP BY date
    `;

    const results = await this.poolManager.executeAnalyticsQuery(query);
    return results[0] || {};
  }

  // Cross-shard operations
  async getUsersByEmail(email: string): Promise<any[]> {
    return this.poolManager.executeOnAllShards(
      'SELECT * FROM users_shard WHERE email = $1',
      [email]
    );
  }

  async getTotalUserCount(): Promise<number> {
    const results = await this.poolManager.executeOnAllShards(
      'SELECT COUNT(*) as count FROM users_shard'
    );
    
    return results.reduce((total, result) => total + parseInt(result.count), 0);
  }

  private getShardKey(userId: string): number {
    // Simple hash-based shard key generation
    let hash = 0;
    for (let i = 0; i < userId.length; i++) {
      const char = userId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash) % 1000000;
  }
}

// Export configuration factory
export function createDatabaseConfig(): DatabaseConfig {
  return {
    primary: {
      host: process.env.POSTGRES_PRIMARY_HOST || 'localhost',
      port: parseInt(process.env.POSTGRES_PRIMARY_PORT || '5432'),
      database: process.env.POSTGRES_PRIMARY_DB || 'aic_primary',
      username: process.env.POSTGRES_PRIMARY_USER || 'aic_admin',
      password: process.env.POSTGRES_PRIMARY_PASSWORD || 'aic_secure_pass',
    },
    replicas: [
      {
        host: process.env.POSTGRES_REPLICA1_HOST || 'localhost',
        port: parseInt(process.env.POSTGRES_REPLICA1_PORT || '5433'),
        database: process.env.POSTGRES_REPLICA1_DB || 'aic_primary',
        username: process.env.POSTGRES_REPLICA1_USER || 'aic_admin',
        password: process.env.POSTGRES_REPLICA1_PASSWORD || 'aic_secure_pass',
      },
      {
        host: process.env.POSTGRES_REPLICA2_HOST || 'localhost',
        port: parseInt(process.env.POSTGRES_REPLICA2_PORT || '5434'),
        database: process.env.POSTGRES_REPLICA2_DB || 'aic_primary',
        username: process.env.POSTGRES_REPLICA2_USER || 'aic_admin',
        password: process.env.POSTGRES_REPLICA2_PASSWORD || 'aic_secure_pass',
      },
    ],
    shards: [
      {
        id: 1,
        host: process.env.POSTGRES_SHARD1_HOST || 'localhost',
        port: parseInt(process.env.POSTGRES_SHARD1_PORT || '5435'),
        database: process.env.POSTGRES_SHARD1_DB || 'aic_shard_1',
        username: process.env.POSTGRES_SHARD1_USER || 'aic_shard_user',
        password: process.env.POSTGRES_SHARD1_PASSWORD || 'shard_pass_1',
        minKey: 0,
        maxKey: 999999,
      },
      {
        id: 2,
        host: process.env.POSTGRES_SHARD2_HOST || 'localhost',
        port: parseInt(process.env.POSTGRES_SHARD2_PORT || '5436'),
        database: process.env.POSTGRES_SHARD2_DB || 'aic_shard_2',
        username: process.env.POSTGRES_SHARD2_USER || 'aic_shard_user',
        password: process.env.POSTGRES_SHARD2_PASSWORD || 'shard_pass_2',
        minKey: 1000000,
        maxKey: 1999999,
      },
    ],
    clickhouse: {
      host: process.env.CLICKHOUSE_HOST || 'localhost',
      port: parseInt(process.env.CLICKHOUSE_PORT || '8123'),
      database: process.env.CLICKHOUSE_DB || 'aic_analytics',
      username: process.env.CLICKHOUSE_USER || 'aic_analytics',
      password: process.env.CLICKHOUSE_PASSWORD || 'analytics_pass',
    },
    redis: {
      host: process.env.REDIS_HOST || 'localhost',
      port: parseInt(process.env.REDIS_PORT || '6379'),
      password: process.env.REDIS_PASSWORD,
    },
  };
}
