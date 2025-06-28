import Redis from 'ioredis';
import { UserReadModel, UserReadModelRepository } from '../application/queries/get-user.query';

export class RedisUserReadModelRepository implements UserReadModelRepository {
  private readonly keyPrefix = 'user:';
  private readonly emailIndexPrefix = 'user:email:';

  constructor(private readonly redis: Redis) {}

  async findById(id: string): Promise<UserReadModel | null> {
    const key = this.keyPrefix + id;
    const data = await this.redis.hgetall(key);
    
    if (Object.keys(data).length === 0) {
      return null;
    }

    return this.mapToReadModel(data);
  }

  async findByEmail(email: string): Promise<UserReadModel | null> {
    const indexKey = this.emailIndexPrefix + email;
    const userId = await this.redis.get(indexKey);
    
    if (!userId) {
      return null;
    }

    return this.findById(userId);
  }

  async findAll(limit: number = 50, offset: number = 0): Promise<UserReadModel[]> {
    const pattern = this.keyPrefix + '*';
    const keys = await this.redis.keys(pattern);
    
    const paginatedKeys = keys.slice(offset, offset + limit);
    const pipeline = this.redis.pipeline();
    
    paginatedKeys.forEach(key => {
      pipeline.hgetall(key);
    });

    const results = await pipeline.exec();
    
    if (!results) {
      return [];
    }

    return results
      .map(([err, data]) => {
        if (err || !data) return null;
        return this.mapToReadModel(data as Record<string, string>);
      })
      .filter((user): user is UserReadModel => user !== null);
  }

  async save(user: UserReadModel): Promise<void> {
    const key = this.keyPrefix + user.id;
    const emailIndexKey = this.emailIndexPrefix + user.email;

    const pipeline = this.redis.pipeline();
    
    // Save user data
    pipeline.hmset(key, {
      id: user.id,
      email: user.email,
      username: user.username,
      status: user.status,
      lastLoginAt: user.lastLoginAt?.toISOString() || '',
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString(),
      version: user.version.toString(),
      lastUpdated: user.lastUpdated.toISOString()
    });

    // Create email index
    pipeline.set(emailIndexKey, user.id);

    // Set TTL (optional - for cache expiration)
    pipeline.expire(key, 3600 * 24); // 24 hours
    pipeline.expire(emailIndexKey, 3600 * 24);

    await pipeline.exec();
  }

  async update(id: string, updates: Partial<UserReadModel>): Promise<void> {
    const existing = await this.findById(id);
    if (!existing) {
      throw new Error(`User with id ${id} not found`);
    }

    const updated: UserReadModel = {
      ...existing,
      ...updates,
      lastUpdated: new Date()
    };

    await this.save(updated);
  }

  async delete(id: string): Promise<void> {
    const user = await this.findById(id);
    if (!user) {
      return;
    }

    const key = this.keyPrefix + id;
    const emailIndexKey = this.emailIndexPrefix + user.email;

    const pipeline = this.redis.pipeline();
    pipeline.del(key);
    pipeline.del(emailIndexKey);
    
    await pipeline.exec();
  }

  private mapToReadModel(data: Record<string, string>): UserReadModel {
    return {
      id: data.id,
      email: data.email,
      username: data.username,
      status: data.status,
      lastLoginAt: data.lastLoginAt ? new Date(data.lastLoginAt) : undefined,
      createdAt: new Date(data.createdAt),
      updatedAt: new Date(data.updatedAt),
      version: parseInt(data.version, 10),
      lastUpdated: new Date(data.lastUpdated)
    };
  }
}
