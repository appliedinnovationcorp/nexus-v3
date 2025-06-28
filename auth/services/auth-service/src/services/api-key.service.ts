import crypto from 'crypto';
import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';
import cron from 'node-cron';

import {
  ApiKeyService,
  ApiKeyCreateRequest,
  ApiKeyResponse,
  ApiKey,
  AuthError,
  RateLimitError
} from '../types/auth.types';

import { ApiKeyRepository } from '../repositories/api-key.repository';
import { UserRepository } from '../repositories/user.repository';
import { AuditService } from './audit.service';
import { RateLimitService } from './rate-limit.service';
import { NotificationService } from './notification.service';
import { RedisService } from './redis.service';
import { logger } from '../utils/logger';
import { config } from '../config';

export class ApiKeyServiceImpl implements ApiKeyService {
  private readonly KEY_PREFIX = 'ak_';
  private readonly KEY_LENGTH = 32;

  constructor(
    private readonly apiKeyRepository: ApiKeyRepository,
    private readonly userRepository: UserRepository,
    private readonly auditService: AuditService,
    private readonly rateLimitService: RateLimitService,
    private readonly notificationService: NotificationService,
    private readonly redisService: RedisService
  ) {
    this.setupAutomaticRotation();
  }

  async createApiKey(userId: string, request: ApiKeyCreateRequest): Promise<ApiKeyResponse> {
    try {
      // Verify user exists
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Check if user has reached API key limit
      const existingKeys = await this.apiKeyRepository.findByUserId(userId);
      const activeKeys = existingKeys.filter(key => key.isActive);
      
      if (activeKeys.length >= 10) { // Configurable limit
        throw new AuthError('API key limit reached', 'API_KEY_LIMIT_REACHED', 400);
      }

      // Generate API key
      const rawKey = this.generateApiKey();
      const keyId = this.generateKeyId();
      const keyPrefix = rawKey.substring(0, 8);
      const keyHash = await bcrypt.hash(rawKey, 12);

      // Set default values
      const apiKeyData: Partial<ApiKey> = {
        keyId,
        keyHash,
        keyPrefix,
        userId,
        name: request.name,
        description: request.description,
        scopes: request.scopes || [],
        rateLimitPerHour: request.rateLimitPerHour || 1000,
        rateLimitPerDay: request.rateLimitPerDay || 10000,
        allowedIps: request.allowedIps,
        allowedDomains: request.allowedDomains,
        expiresAt: request.expiresAt,
        isActive: true,
        autoRotate: request.autoRotate || false,
        rotationIntervalDays: request.rotationIntervalDays || 90,
        usageCount: 0
      };

      // Set next rotation date if auto-rotate is enabled
      if (apiKeyData.autoRotate) {
        apiKeyData.nextRotationAt = new Date(
          Date.now() + (apiKeyData.rotationIntervalDays! * 24 * 60 * 60 * 1000)
        );
      }

      // Create API key
      const apiKey = await this.apiKeyRepository.create(apiKeyData);

      // Cache API key for faster lookups
      await this.cacheApiKey(apiKey);

      // Log API key creation
      await this.auditService.logAuthEvent({
        eventType: 'API_KEY_CREATED',
        userId,
        apiKeyId: apiKey.id,
        result: 'SUCCESS',
        metadata: {
          keyId: apiKey.keyId,
          name: apiKey.name,
          scopes: apiKey.scopes
        }
      });

      // Send notification
      await this.notificationService.sendApiKeyCreatedNotification(user, apiKey);

      // Return response with the raw key (only time it's exposed)
      return {
        ...this.sanitizeApiKey(apiKey),
        key: rawKey
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('API key creation error:', error);
      throw new AuthError('API key creation failed', 'API_KEY_CREATE_ERROR', 500);
    }
  }

  async getApiKeys(userId: string): Promise<ApiKeyResponse[]> {
    try {
      const apiKeys = await this.apiKeyRepository.findByUserId(userId);
      return apiKeys.map(key => this.sanitizeApiKey(key));

    } catch (error) {
      logger.error('Get API keys error:', error);
      throw new AuthError('Failed to retrieve API keys', 'API_KEY_GET_ERROR', 500);
    }
  }

  async getApiKey(keyId: string): Promise<ApiKeyResponse | null> {
    try {
      const apiKey = await this.apiKeyRepository.findByKeyId(keyId);
      return apiKey ? this.sanitizeApiKey(apiKey) : null;

    } catch (error) {
      logger.error('Get API key error:', error);
      throw new AuthError('Failed to retrieve API key', 'API_KEY_GET_ERROR', 500);
    }
  }

  async updateApiKey(keyId: string, updates: Partial<ApiKeyCreateRequest>): Promise<ApiKeyResponse> {
    try {
      const existingKey = await this.apiKeyRepository.findByKeyId(keyId);
      if (!existingKey) {
        throw new AuthError('API key not found', 'API_KEY_NOT_FOUND', 404);
      }

      // Prepare updates
      const updateData: Partial<ApiKey> = {
        name: updates.name,
        description: updates.description,
        scopes: updates.scopes,
        rateLimitPerHour: updates.rateLimitPerHour,
        rateLimitPerDay: updates.rateLimitPerDay,
        allowedIps: updates.allowedIps,
        allowedDomains: updates.allowedDomains,
        expiresAt: updates.expiresAt,
        autoRotate: updates.autoRotate,
        rotationIntervalDays: updates.rotationIntervalDays
      };

      // Update next rotation date if auto-rotate settings changed
      if (updates.autoRotate !== undefined || updates.rotationIntervalDays !== undefined) {
        if (updateData.autoRotate) {
          const intervalDays = updateData.rotationIntervalDays || existingKey.rotationIntervalDays;
          updateData.nextRotationAt = new Date(
            Date.now() + (intervalDays * 24 * 60 * 60 * 1000)
          );
        } else {
          updateData.nextRotationAt = undefined;
        }
      }

      // Update API key
      const updatedKey = await this.apiKeyRepository.update(existingKey.id, updateData);

      // Update cache
      await this.cacheApiKey(updatedKey);

      // Log API key update
      await this.auditService.logAuthEvent({
        eventType: 'API_KEY_UPDATED',
        userId: existingKey.userId,
        apiKeyId: existingKey.id,
        result: 'SUCCESS',
        metadata: {
          keyId: existingKey.keyId,
          updates: Object.keys(updateData)
        }
      });

      return this.sanitizeApiKey(updatedKey);

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('API key update error:', error);
      throw new AuthError('API key update failed', 'API_KEY_UPDATE_ERROR', 500);
    }
  }

  async deleteApiKey(keyId: string): Promise<void> {
    try {
      const apiKey = await this.apiKeyRepository.findByKeyId(keyId);
      if (!apiKey) {
        throw new AuthError('API key not found', 'API_KEY_NOT_FOUND', 404);
      }

      // Soft delete by deactivating
      await this.apiKeyRepository.update(apiKey.id, {
        isActive: false,
        updatedAt: new Date()
      });

      // Remove from cache
      await this.removeCachedApiKey(keyId);

      // Log API key deletion
      await this.auditService.logAuthEvent({
        eventType: 'API_KEY_DELETED',
        userId: apiKey.userId,
        apiKeyId: apiKey.id,
        result: 'SUCCESS',
        metadata: {
          keyId: apiKey.keyId,
          name: apiKey.name
        }
      });

      // Send notification
      if (apiKey.userId) {
        const user = await this.userRepository.findById(apiKey.userId);
        if (user) {
          await this.notificationService.sendApiKeyDeletedNotification(user, apiKey);
        }
      }

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('API key deletion error:', error);
      throw new AuthError('API key deletion failed', 'API_KEY_DELETE_ERROR', 500);
    }
  }

  async rotateApiKey(keyId: string): Promise<{ keyId: string; key: string }> {
    try {
      const existingKey = await this.apiKeyRepository.findByKeyId(keyId);
      if (!existingKey) {
        throw new AuthError('API key not found', 'API_KEY_NOT_FOUND', 404);
      }

      // Generate new key
      const newRawKey = this.generateApiKey();
      const newKeyId = this.generateKeyId();
      const newKeyPrefix = newRawKey.substring(0, 8);
      const newKeyHash = await bcrypt.hash(newRawKey, 12);

      // Update the existing key with new values
      const rotatedKey = await this.apiKeyRepository.update(existingKey.id, {
        keyId: newKeyId,
        keyHash: newKeyHash,
        keyPrefix: newKeyPrefix,
        nextRotationAt: existingKey.autoRotate 
          ? new Date(Date.now() + (existingKey.rotationIntervalDays * 24 * 60 * 60 * 1000))
          : undefined,
        updatedAt: new Date()
      });

      // Update cache
      await this.removeCachedApiKey(keyId); // Remove old key
      await this.cacheApiKey(rotatedKey); // Cache new key

      // Log rotation
      await this.auditService.logAuthEvent({
        eventType: 'API_KEY_ROTATED',
        userId: existingKey.userId,
        apiKeyId: existingKey.id,
        result: 'SUCCESS',
        metadata: {
          oldKeyId: keyId,
          newKeyId: newKeyId,
          automatic: false
        }
      });

      // Send notification
      if (existingKey.userId) {
        const user = await this.userRepository.findById(existingKey.userId);
        if (user) {
          await this.notificationService.sendApiKeyRotatedNotification(user, rotatedKey);
        }
      }

      return {
        keyId: newKeyId,
        key: newRawKey
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('API key rotation error:', error);
      throw new AuthError('API key rotation failed', 'API_KEY_ROTATE_ERROR', 500);
    }
  }

  async validateApiKey(key: string): Promise<ApiKey | null> {
    try {
      // Extract key prefix for faster lookup
      const keyPrefix = key.substring(0, 8);
      
      // Try cache first
      const cacheKey = `api_key_prefix:${keyPrefix}`;
      const cachedKeyIds = await this.redisService.get(cacheKey);
      
      let candidateKeys: ApiKey[] = [];
      
      if (cachedKeyIds) {
        const keyIds = JSON.parse(cachedKeyIds);
        candidateKeys = await Promise.all(
          keyIds.map((keyId: string) => this.apiKeyRepository.findByKeyId(keyId))
        );
        candidateKeys = candidateKeys.filter(Boolean);
      } else {
        // Fallback to database lookup by prefix
        candidateKeys = await this.apiKeyRepository.findByPrefix(keyPrefix);
        
        // Cache the key IDs for this prefix
        const keyIds = candidateKeys.map(k => k.keyId);
        await this.redisService.setWithExpiry(cacheKey, JSON.stringify(keyIds), 300);
      }

      // Verify the key against candidates
      for (const candidateKey of candidateKeys) {
        if (!candidateKey.isActive) continue;
        
        // Check expiration
        if (candidateKey.expiresAt && candidateKey.expiresAt < new Date()) {
          continue;
        }

        // Verify key hash
        const isValid = await bcrypt.compare(key, candidateKey.keyHash);
        if (isValid) {
          // Update last used timestamp and usage count
          await this.apiKeyRepository.update(candidateKey.id, {
            lastUsedAt: new Date(),
            usageCount: candidateKey.usageCount + 1
          });

          return candidateKey;
        }
      }

      return null;

    } catch (error) {
      logger.error('API key validation error:', error);
      return null;
    }
  }

  async checkApiKeyRateLimit(apiKey: ApiKey, endpoint?: string): Promise<void> {
    try {
      const identifier = `api_key:${apiKey.keyId}`;
      
      // Check hourly limit
      await this.rateLimitService.checkRateLimit(
        identifier,
        endpoint || 'api',
        'API_KEY',
        apiKey.rateLimitPerHour,
        3600 // 1 hour
      );

      // Check daily limit
      await this.rateLimitService.checkRateLimit(
        identifier + ':daily',
        endpoint || 'api',
        'API_KEY',
        apiKey.rateLimitPerDay,
        86400 // 24 hours
      );

    } catch (error) {
      if (error instanceof RateLimitError) {
        // Log rate limit exceeded
        await this.auditService.logAuthEvent({
          eventType: 'API_KEY_RATE_LIMIT_EXCEEDED',
          userId: apiKey.userId,
          apiKeyId: apiKey.id,
          result: 'FAILURE',
          metadata: {
            keyId: apiKey.keyId,
            endpoint
          }
        });
      }
      throw error;
    }
  }

  async rotateExpiredKeys(): Promise<void> {
    try {
      const keysToRotate = await this.apiKeyRepository.findKeysForRotation();
      
      logger.info(`Found ${keysToRotate.length} API keys for automatic rotation`);

      for (const key of keysToRotate) {
        try {
          await this.rotateApiKey(key.keyId);
          
          // Log automatic rotation
          await this.auditService.logAuthEvent({
            eventType: 'API_KEY_AUTO_ROTATED',
            userId: key.userId,
            apiKeyId: key.id,
            result: 'SUCCESS',
            metadata: {
              keyId: key.keyId,
              automatic: true
            }
          });

        } catch (error) {
          logger.error(`Failed to rotate API key ${key.keyId}:`, error);
          
          // Log rotation failure
          await this.auditService.logAuthEvent({
            eventType: 'API_KEY_ROTATION_FAILED',
            userId: key.userId,
            apiKeyId: key.id,
            result: 'FAILURE',
            errorMessage: error instanceof Error ? error.message : 'Unknown error',
            metadata: {
              keyId: key.keyId,
              automatic: true
            }
          });
        }
      }

    } catch (error) {
      logger.error('Automatic key rotation error:', error);
    }
  }

  private setupAutomaticRotation(): void {
    // Run automatic rotation daily at 2 AM
    cron.schedule('0 2 * * *', async () => {
      logger.info('Starting automatic API key rotation');
      await this.rotateExpiredKeys();
    });

    logger.info('Automatic API key rotation scheduled');
  }

  private generateApiKey(): string {
    return crypto.randomBytes(this.KEY_LENGTH).toString('hex');
  }

  private generateKeyId(): string {
    return this.KEY_PREFIX + crypto.randomBytes(16).toString('hex');
  }

  private async cacheApiKey(apiKey: ApiKey): Promise<void> {
    const cacheKey = `api_key:${apiKey.keyId}`;
    await this.redisService.setWithExpiry(
      cacheKey,
      JSON.stringify(apiKey),
      3600 // 1 hour
    );

    // Also cache by prefix for faster validation
    const prefixKey = `api_key_prefix:${apiKey.keyPrefix}`;
    const existingKeys = await this.redisService.get(prefixKey);
    const keyIds = existingKeys ? JSON.parse(existingKeys) : [];
    
    if (!keyIds.includes(apiKey.keyId)) {
      keyIds.push(apiKey.keyId);
      await this.redisService.setWithExpiry(prefixKey, JSON.stringify(keyIds), 300);
    }
  }

  private async removeCachedApiKey(keyId: string): Promise<void> {
    await this.redisService.delete(`api_key:${keyId}`);
    
    // Also remove from prefix cache
    const apiKey = await this.apiKeyRepository.findByKeyId(keyId);
    if (apiKey) {
      const prefixKey = `api_key_prefix:${apiKey.keyPrefix}`;
      const existingKeys = await this.redisService.get(prefixKey);
      
      if (existingKeys) {
        const keyIds = JSON.parse(existingKeys);
        const updatedKeyIds = keyIds.filter((id: string) => id !== keyId);
        
        if (updatedKeyIds.length > 0) {
          await this.redisService.setWithExpiry(prefixKey, JSON.stringify(updatedKeyIds), 300);
        } else {
          await this.redisService.delete(prefixKey);
        }
      }
    }
  }

  private sanitizeApiKey(apiKey: ApiKey): ApiKeyResponse {
    const { keyHash, ...sanitized } = apiKey;
    return sanitized as ApiKeyResponse;
  }
}
