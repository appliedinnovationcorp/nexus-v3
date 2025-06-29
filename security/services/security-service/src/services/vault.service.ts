import axios, { AxiosInstance } from 'axios';
import crypto from 'crypto';
import { logger } from '../utils/logger';

export interface VaultConfig {
  address: string;
  token: string;
  namespace?: string;
  timeout: number;
  retries: number;
}

export interface SecretData {
  [key: string]: any;
}

export interface DatabaseCredentials {
  username: string;
  password: string;
  ttl?: number;
}

export interface EncryptionResult {
  ciphertext: string;
  key_version: number;
}

export interface DecryptionResult {
  plaintext: string;
}

export class VaultService {
  private client: AxiosInstance;
  private config: VaultConfig;
  private tokenRenewalTimer?: NodeJS.Timeout;

  constructor(config: VaultConfig) {
    this.config = config;
    this.client = axios.create({
      baseURL: config.address,
      timeout: config.timeout,
      headers: {
        'X-Vault-Token': config.token,
        'Content-Type': 'application/json'
      }
    });

    if (config.namespace) {
      this.client.defaults.headers['X-Vault-Namespace'] = config.namespace;
    }

    this.setupInterceptors();
    this.startTokenRenewal();
  }

  // Key-Value Secrets Engine (v2)
  async writeSecret(path: string, data: SecretData, version?: number): Promise<void> {
    try {
      const payload = {
        data,
        options: version ? { cas: version } : {}
      };

      await this.client.post(`/v1/secret/data/${path}`, payload);
      logger.info(`Secret written to path: ${path}`);
    } catch (error) {
      logger.error(`Failed to write secret to ${path}:`, error);
      throw new Error(`Failed to write secret: ${this.getErrorMessage(error)}`);
    }
  }

  async readSecret(path: string, version?: number): Promise<SecretData | null> {
    try {
      const url = version 
        ? `/v1/secret/data/${path}?version=${version}`
        : `/v1/secret/data/${path}`;
      
      const response = await this.client.get(url);
      return response.data.data.data;
    } catch (error) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return null;
      }
      logger.error(`Failed to read secret from ${path}:`, error);
      throw new Error(`Failed to read secret: ${this.getErrorMessage(error)}`);
    }
  }

  async deleteSecret(path: string, versions?: number[]): Promise<void> {
    try {
      if (versions && versions.length > 0) {
        // Delete specific versions
        await this.client.post(`/v1/secret/delete/${path}`, { versions });
      } else {
        // Delete latest version
        await this.client.delete(`/v1/secret/data/${path}`);
      }
      logger.info(`Secret deleted from path: ${path}`);
    } catch (error) {
      logger.error(`Failed to delete secret from ${path}:`, error);
      throw new Error(`Failed to delete secret: ${this.getErrorMessage(error)}`);
    }
  }

  async listSecrets(path: string): Promise<string[]> {
    try {
      const response = await this.client.get(`/v1/secret/metadata/${path}?list=true`);
      return response.data.data.keys || [];
    } catch (error) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return [];
      }
      logger.error(`Failed to list secrets at ${path}:`, error);
      throw new Error(`Failed to list secrets: ${this.getErrorMessage(error)}`);
    }
  }

  // Dynamic Database Secrets
  async getDatabaseCredentials(role: string): Promise<DatabaseCredentials> {
    try {
      const response = await this.client.get(`/v1/database/creds/${role}`);
      const { username, password } = response.data.data;
      
      logger.info(`Generated database credentials for role: ${role}`);
      return {
        username,
        password,
        ttl: response.data.lease_duration
      };
    } catch (error) {
      logger.error(`Failed to get database credentials for role ${role}:`, error);
      throw new Error(`Failed to get database credentials: ${this.getErrorMessage(error)}`);
    }
  }

  async revokeDatabaseCredentials(leaseId: string): Promise<void> {
    try {
      await this.client.put('/v1/sys/leases/revoke', { lease_id: leaseId });
      logger.info(`Revoked database credentials with lease: ${leaseId}`);
    } catch (error) {
      logger.error(`Failed to revoke database credentials ${leaseId}:`, error);
      throw new Error(`Failed to revoke credentials: ${this.getErrorMessage(error)}`);
    }
  }

  // Transit Secrets Engine (Encryption as a Service)
  async encrypt(keyName: string, plaintext: string, context?: string): Promise<EncryptionResult> {
    try {
      const payload: any = {
        plaintext: Buffer.from(plaintext).toString('base64')
      };

      if (context) {
        payload.context = Buffer.from(context).toString('base64');
      }

      const response = await this.client.post(`/v1/transit/encrypt/${keyName}`, payload);
      return {
        ciphertext: response.data.data.ciphertext,
        key_version: response.data.data.key_version
      };
    } catch (error) {
      logger.error(`Failed to encrypt with key ${keyName}:`, error);
      throw new Error(`Failed to encrypt: ${this.getErrorMessage(error)}`);
    }
  }

  async decrypt(keyName: string, ciphertext: string, context?: string): Promise<DecryptionResult> {
    try {
      const payload: any = { ciphertext };

      if (context) {
        payload.context = Buffer.from(context).toString('base64');
      }

      const response = await this.client.post(`/v1/transit/decrypt/${keyName}`, payload);
      const plaintext = Buffer.from(response.data.data.plaintext, 'base64').toString();
      
      return { plaintext };
    } catch (error) {
      logger.error(`Failed to decrypt with key ${keyName}:`, error);
      throw new Error(`Failed to decrypt: ${this.getErrorMessage(error)}`);
    }
  }

  async generateDataKey(keyName: string, keyType: 'plaintext' | 'wrapped' = 'plaintext'): Promise<{
    plaintext?: string;
    ciphertext: string;
  }> {
    try {
      const endpoint = keyType === 'plaintext' 
        ? `/v1/transit/datakey/plaintext/${keyName}`
        : `/v1/transit/datakey/wrapped/${keyName}`;

      const response = await this.client.post(endpoint, {});
      return response.data.data;
    } catch (error) {
      logger.error(`Failed to generate data key with ${keyName}:`, error);
      throw new Error(`Failed to generate data key: ${this.getErrorMessage(error)}`);
    }
  }

  // PKI Secrets Engine
  async generateCertificate(role: string, commonName: string, options?: {
    altNames?: string[];
    ipSans?: string[];
    ttl?: string;
  }): Promise<{
    certificate: string;
    private_key: string;
    ca_chain: string[];
    serial_number: string;
  }> {
    try {
      const payload: any = {
        common_name: commonName
      };

      if (options?.altNames) {
        payload.alt_names = options.altNames.join(',');
      }
      if (options?.ipSans) {
        payload.ip_sans = options.ipSans.join(',');
      }
      if (options?.ttl) {
        payload.ttl = options.ttl;
      }

      const response = await this.client.post(`/v1/pki/issue/${role}`, payload);
      return response.data.data;
    } catch (error) {
      logger.error(`Failed to generate certificate for ${commonName}:`, error);
      throw new Error(`Failed to generate certificate: ${this.getErrorMessage(error)}`);
    }
  }

  async revokeCertificate(serialNumber: string): Promise<void> {
    try {
      await this.client.post('/v1/pki/revoke', {
        serial_number: serialNumber
      });
      logger.info(`Revoked certificate with serial: ${serialNumber}`);
    } catch (error) {
      logger.error(`Failed to revoke certificate ${serialNumber}:`, error);
      throw new Error(`Failed to revoke certificate: ${this.getErrorMessage(error)}`);
    }
  }

  // AWS Secrets Engine
  async getAwsCredentials(role: string): Promise<{
    access_key: string;
    secret_key: string;
    security_token?: string;
  }> {
    try {
      const response = await this.client.get(`/v1/aws/creds/${role}`);
      return response.data.data;
    } catch (error) {
      logger.error(`Failed to get AWS credentials for role ${role}:`, error);
      throw new Error(`Failed to get AWS credentials: ${this.getErrorMessage(error)}`);
    }
  }

  // Token Management
  async renewToken(): Promise<void> {
    try {
      const response = await this.client.post('/v1/auth/token/renew-self');
      const newTtl = response.data.auth.lease_duration;
      
      logger.info(`Token renewed successfully, new TTL: ${newTtl}s`);
      
      // Update token in headers if a new one is provided
      if (response.data.auth.client_token) {
        this.client.defaults.headers['X-Vault-Token'] = response.data.auth.client_token;
      }
    } catch (error) {
      logger.error('Failed to renew token:', error);
      throw new Error(`Failed to renew token: ${this.getErrorMessage(error)}`);
    }
  }

  async lookupToken(): Promise<{
    ttl: number;
    renewable: boolean;
    policies: string[];
  }> {
    try {
      const response = await this.client.get('/v1/auth/token/lookup-self');
      return {
        ttl: response.data.data.ttl,
        renewable: response.data.data.renewable,
        policies: response.data.data.policies
      };
    } catch (error) {
      logger.error('Failed to lookup token:', error);
      throw new Error(`Failed to lookup token: ${this.getErrorMessage(error)}`);
    }
  }

  // Health and Status
  async getHealth(): Promise<{
    initialized: boolean;
    sealed: boolean;
    standby: boolean;
    version: string;
  }> {
    try {
      const response = await this.client.get('/v1/sys/health');
      return {
        initialized: response.data.initialized,
        sealed: response.data.sealed,
        standby: response.data.standby,
        version: response.data.version
      };
    } catch (error) {
      // Health endpoint returns different status codes for different states
      if (axios.isAxiosError(error) && error.response) {
        return {
          initialized: error.response.data?.initialized || false,
          sealed: error.response.data?.sealed || true,
          standby: error.response.data?.standby || false,
          version: error.response.data?.version || 'unknown'
        };
      }
      throw new Error(`Failed to get health status: ${this.getErrorMessage(error)}`);
    }
  }

  // Utility Methods
  async createTransitKey(keyName: string, keyType: 'aes256-gcm96' | 'chacha20-poly1305' | 'ed25519' | 'ecdsa-p256' | 'rsa-2048' | 'rsa-3072' | 'rsa-4096' = 'aes256-gcm96'): Promise<void> {
    try {
      await this.client.post(`/v1/transit/keys/${keyName}`, {
        type: keyType,
        exportable: false,
        allow_plaintext_backup: false
      });
      logger.info(`Created transit key: ${keyName}`);
    } catch (error) {
      logger.error(`Failed to create transit key ${keyName}:`, error);
      throw new Error(`Failed to create transit key: ${this.getErrorMessage(error)}`);
    }
  }

  async rotateTransitKey(keyName: string): Promise<void> {
    try {
      await this.client.post(`/v1/transit/keys/${keyName}/rotate`);
      logger.info(`Rotated transit key: ${keyName}`);
    } catch (error) {
      logger.error(`Failed to rotate transit key ${keyName}:`, error);
      throw new Error(`Failed to rotate transit key: ${this.getErrorMessage(error)}`);
    }
  }

  // Secret rotation utilities
  async rotateSecret(path: string, generator: () => Promise<SecretData>): Promise<void> {
    try {
      const newSecret = await generator();
      await this.writeSecret(path, newSecret);
      logger.info(`Rotated secret at path: ${path}`);
    } catch (error) {
      logger.error(`Failed to rotate secret at ${path}:`, error);
      throw new Error(`Failed to rotate secret: ${this.getErrorMessage(error)}`);
    }
  }

  // Batch operations
  async batchWriteSecrets(secrets: Array<{ path: string; data: SecretData }>): Promise<void> {
    const promises = secrets.map(({ path, data }) => this.writeSecret(path, data));
    await Promise.all(promises);
    logger.info(`Batch wrote ${secrets.length} secrets`);
  }

  async batchReadSecrets(paths: string[]): Promise<Array<{ path: string; data: SecretData | null }>> {
    const promises = paths.map(async (path) => ({
      path,
      data: await this.readSecret(path)
    }));
    return Promise.all(promises);
  }

  // Cleanup and shutdown
  async shutdown(): Promise<void> {
    if (this.tokenRenewalTimer) {
      clearInterval(this.tokenRenewalTimer);
    }
    logger.info('Vault service shutdown completed');
  }

  // Private methods
  private setupInterceptors(): void {
    // Request interceptor for logging
    this.client.interceptors.request.use(
      (config) => {
        logger.debug(`Vault request: ${config.method?.toUpperCase()} ${config.url}`);
        return config;
      },
      (error) => {
        logger.error('Vault request error:', error);
        return Promise.reject(error);
      }
    );

    // Response interceptor for error handling
    this.client.interceptors.response.use(
      (response) => {
        logger.debug(`Vault response: ${response.status} ${response.config.url}`);
        return response;
      },
      async (error) => {
        if (axios.isAxiosError(error)) {
          // Handle token expiration
          if (error.response?.status === 403) {
            logger.warn('Vault token may be expired, attempting renewal');
            try {
              await this.renewToken();
              // Retry the original request
              return this.client.request(error.config!);
            } catch (renewError) {
              logger.error('Failed to renew token:', renewError);
            }
          }
        }
        return Promise.reject(error);
      }
    );
  }

  private startTokenRenewal(): void {
    // Renew token every hour
    this.tokenRenewalTimer = setInterval(async () => {
      try {
        const tokenInfo = await this.lookupToken();
        
        // Renew if TTL is less than 2 hours and renewable
        if (tokenInfo.ttl < 7200 && tokenInfo.renewable) {
          await this.renewToken();
        }
      } catch (error) {
        logger.error('Automatic token renewal failed:', error);
      }
    }, 3600000); // 1 hour
  }

  private getErrorMessage(error: any): string {
    if (axios.isAxiosError(error)) {
      return error.response?.data?.errors?.[0] || error.message;
    }
    return error.message || 'Unknown error';
  }
}

// Factory function
export function createVaultService(config: VaultConfig): VaultService {
  return new VaultService(config);
}

// Utility functions for common secret patterns
export class SecretGenerators {
  static async generateDatabasePassword(): Promise<string> {
    return crypto.randomBytes(32).toString('base64').replace(/[+/=]/g, '').substring(0, 32);
  }

  static async generateApiKey(): Promise<string> {
    return 'ak_' + crypto.randomBytes(32).toString('hex');
  }

  static async generateJwtSecret(): Promise<string> {
    return crypto.randomBytes(64).toString('hex');
  }

  static async generateEncryptionKey(): Promise<string> {
    return crypto.randomBytes(32).toString('base64');
  }
}

// Secret rotation scheduler
export class SecretRotationScheduler {
  private intervals: Map<string, NodeJS.Timeout> = new Map();

  constructor(private vaultService: VaultService) {}

  scheduleRotation(
    secretPath: string,
    generator: () => Promise<SecretData>,
    intervalMs: number
  ): void {
    const interval = setInterval(async () => {
      try {
        await this.vaultService.rotateSecret(secretPath, generator);
        logger.info(`Scheduled rotation completed for: ${secretPath}`);
      } catch (error) {
        logger.error(`Scheduled rotation failed for ${secretPath}:`, error);
      }
    }, intervalMs);

    this.intervals.set(secretPath, interval);
    logger.info(`Scheduled rotation for ${secretPath} every ${intervalMs}ms`);
  }

  cancelRotation(secretPath: string): void {
    const interval = this.intervals.get(secretPath);
    if (interval) {
      clearInterval(interval);
      this.intervals.delete(secretPath);
      logger.info(`Cancelled rotation schedule for: ${secretPath}`);
    }
  }

  shutdown(): void {
    for (const [path, interval] of this.intervals) {
      clearInterval(interval);
    }
    this.intervals.clear();
    logger.info('Secret rotation scheduler shutdown completed');
  }
}
