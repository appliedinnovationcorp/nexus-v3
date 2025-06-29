import crypto from 'crypto';
import { logger } from '../utils/logger';

export interface AnonymizationConfig {
  algorithm: AnonymizationAlgorithm;
  parameters: Record<string, any>;
  preserveFormat: boolean;
  reversible: boolean;
  keyDerivation?: KeyDerivationConfig;
}

export interface KeyDerivationConfig {
  algorithm: 'PBKDF2' | 'scrypt' | 'argon2';
  salt: string;
  iterations: number;
  keyLength: number;
}

export interface AnonymizationResult {
  originalValue: string;
  anonymizedValue: string;
  algorithm: AnonymizationAlgorithm;
  metadata: {
    timestamp: Date;
    preservedFormat: boolean;
    reversible: boolean;
    qualityMetrics?: QualityMetrics;
  };
}

export interface QualityMetrics {
  informationLoss: number;
  dataUtility: number;
  privacyLevel: number;
  kAnonymity?: number;
  lDiversity?: number;
  tCloseness?: number;
}

export interface DatasetAnonymizationResult {
  originalRecords: number;
  anonymizedRecords: number;
  suppressedRecords: number;
  generalizedFields: string[];
  qualityMetrics: QualityMetrics;
  anonymizationLog: AnonymizationLogEntry[];
}

export interface AnonymizationLogEntry {
  field: string;
  algorithm: AnonymizationAlgorithm;
  parameters: Record<string, any>;
  recordsAffected: number;
  informationLoss: number;
}

export enum AnonymizationAlgorithm {
  // Pseudonymization
  DETERMINISTIC_ENCRYPTION = 'deterministic_encryption',
  FORMAT_PRESERVING_ENCRYPTION = 'format_preserving_encryption',
  TOKENIZATION = 'tokenization',
  HASHING = 'hashing',
  
  // Generalization
  K_ANONYMITY = 'k_anonymity',
  L_DIVERSITY = 'l_diversity',
  T_CLOSENESS = 't_closeness',
  
  // Perturbation
  NOISE_ADDITION = 'noise_addition',
  DIFFERENTIAL_PRIVACY = 'differential_privacy',
  
  // Suppression
  RECORD_SUPPRESSION = 'record_suppression',
  FIELD_SUPPRESSION = 'field_suppression',
  
  // Synthetic Data
  SYNTHETIC_DATA_GENERATION = 'synthetic_data_generation',
  
  // Masking
  PARTIAL_MASKING = 'partial_masking',
  RANDOM_SUBSTITUTION = 'random_substitution'
}

export enum DataType {
  EMAIL = 'email',
  PHONE = 'phone',
  SSN = 'ssn',
  CREDIT_CARD = 'credit_card',
  NAME = 'name',
  ADDRESS = 'address',
  DATE_OF_BIRTH = 'date_of_birth',
  IP_ADDRESS = 'ip_address',
  NUMERIC = 'numeric',
  TEXT = 'text',
  CATEGORICAL = 'categorical'
}

export class AnonymizationService {
  private readonly encryptionKey: Buffer;
  private readonly tokenMap: Map<string, string> = new Map();
  private readonly reverseTokenMap: Map<string, string> = new Map();

  constructor(private readonly masterKey: string) {
    this.encryptionKey = this.deriveKey(masterKey);
  }

  // Single Value Anonymization
  async anonymizeValue(
    value: string,
    dataType: DataType,
    config: AnonymizationConfig
  ): Promise<AnonymizationResult> {
    try {
      let anonymizedValue: string;
      const startTime = Date.now();

      switch (config.algorithm) {
        case AnonymizationAlgorithm.DETERMINISTIC_ENCRYPTION:
          anonymizedValue = await this.deterministicEncryption(value, config);
          break;
        
        case AnonymizationAlgorithm.FORMAT_PRESERVING_ENCRYPTION:
          anonymizedValue = await this.formatPreservingEncryption(value, dataType, config);
          break;
        
        case AnonymizationAlgorithm.TOKENIZATION:
          anonymizedValue = await this.tokenization(value, config);
          break;
        
        case AnonymizationAlgorithm.HASHING:
          anonymizedValue = await this.hashing(value, config);
          break;
        
        case AnonymizationAlgorithm.PARTIAL_MASKING:
          anonymizedValue = await this.partialMasking(value, dataType, config);
          break;
        
        case AnonymizationAlgorithm.RANDOM_SUBSTITUTION:
          anonymizedValue = await this.randomSubstitution(value, dataType, config);
          break;
        
        case AnonymizationAlgorithm.NOISE_ADDITION:
          anonymizedValue = await this.noiseAddition(value, config);
          break;
        
        default:
          throw new Error(`Unsupported anonymization algorithm: ${config.algorithm}`);
      }

      const processingTime = Date.now() - startTime;

      const result: AnonymizationResult = {
        originalValue: value,
        anonymizedValue,
        algorithm: config.algorithm,
        metadata: {
          timestamp: new Date(),
          preservedFormat: config.preserveFormat,
          reversible: config.reversible,
          qualityMetrics: await this.calculateQualityMetrics(value, anonymizedValue, config)
        }
      };

      logger.debug(`Anonymized value using ${config.algorithm} in ${processingTime}ms`);
      return result;

    } catch (error) {
      logger.error('Value anonymization failed:', error);
      throw new Error(`Anonymization failed: ${error}`);
    }
  }

  // Dataset Anonymization
  async anonymizeDataset(
    dataset: Record<string, any>[],
    fieldConfigs: Record<string, { dataType: DataType; config: AnonymizationConfig }>,
    globalConfig?: {
      kAnonymity?: number;
      lDiversity?: number;
      tCloseness?: number;
      suppressionThreshold?: number;
    }
  ): Promise<DatasetAnonymizationResult> {
    try {
      const startTime = Date.now();
      const originalRecords = dataset.length;
      let anonymizedDataset = [...dataset];
      const anonymizationLog: AnonymizationLogEntry[] = [];
      const generalizedFields: string[] = [];

      // Apply field-level anonymization
      for (const [fieldName, fieldConfig] of Object.entries(fieldConfigs)) {
        const fieldStartTime = Date.now();
        let recordsAffected = 0;
        let totalInformationLoss = 0;

        for (let i = 0; i < anonymizedDataset.length; i++) {
          const record = anonymizedDataset[i];
          if (record[fieldName] !== undefined && record[fieldName] !== null) {
            const originalValue = String(record[fieldName]);
            const result = await this.anonymizeValue(
              originalValue,
              fieldConfig.dataType,
              fieldConfig.config
            );
            
            record[fieldName] = result.anonymizedValue;
            recordsAffected++;
            
            if (result.metadata.qualityMetrics) {
              totalInformationLoss += result.metadata.qualityMetrics.informationLoss;
            }
          }
        }

        const avgInformationLoss = recordsAffected > 0 ? totalInformationLoss / recordsAffected : 0;
        
        anonymizationLog.push({
          field: fieldName,
          algorithm: fieldConfig.config.algorithm,
          parameters: fieldConfig.config.parameters,
          recordsAffected,
          informationLoss: avgInformationLoss
        });

        logger.info(`Anonymized field ${fieldName}: ${recordsAffected} records in ${Date.now() - fieldStartTime}ms`);
      }

      // Apply global privacy models if specified
      if (globalConfig?.kAnonymity) {
        const kAnonymityResult = await this.applyKAnonymity(
          anonymizedDataset,
          Object.keys(fieldConfigs),
          globalConfig.kAnonymity
        );
        anonymizedDataset = kAnonymityResult.dataset;
        generalizedFields.push(...kAnonymityResult.generalizedFields);
      }

      if (globalConfig?.lDiversity) {
        anonymizedDataset = await this.applyLDiversity(
          anonymizedDataset,
          Object.keys(fieldConfigs),
          globalConfig.lDiversity
        );
      }

      if (globalConfig?.tCloseness) {
        anonymizedDataset = await this.applyTCloseness(
          anonymizedDataset,
          Object.keys(fieldConfigs),
          globalConfig.tCloseness
        );
      }

      // Calculate overall quality metrics
      const qualityMetrics = await this.calculateDatasetQualityMetrics(
        dataset,
        anonymizedDataset,
        fieldConfigs
      );

      const result: DatasetAnonymizationResult = {
        originalRecords,
        anonymizedRecords: anonymizedDataset.length,
        suppressedRecords: originalRecords - anonymizedDataset.length,
        generalizedFields,
        qualityMetrics,
        anonymizationLog
      };

      const totalTime = Date.now() - startTime;
      logger.info(`Dataset anonymization completed in ${totalTime}ms: ${result.originalRecords} → ${result.anonymizedRecords} records`);

      return result;

    } catch (error) {
      logger.error('Dataset anonymization failed:', error);
      throw new Error(`Dataset anonymization failed: ${error}`);
    }
  }

  // De-anonymization (for reversible algorithms)
  async deanonymizeValue(
    anonymizedValue: string,
    algorithm: AnonymizationAlgorithm,
    config: AnonymizationConfig
  ): Promise<string> {
    try {
      if (!config.reversible) {
        throw new Error('Algorithm is not reversible');
      }

      switch (algorithm) {
        case AnonymizationAlgorithm.DETERMINISTIC_ENCRYPTION:
          return await this.deterministicDecryption(anonymizedValue, config);
        
        case AnonymizationAlgorithm.TOKENIZATION:
          return await this.detokenization(anonymizedValue);
        
        default:
          throw new Error(`De-anonymization not supported for algorithm: ${algorithm}`);
      }

    } catch (error) {
      logger.error('De-anonymization failed:', error);
      throw new Error(`De-anonymization failed: ${error}`);
    }
  }

  // Anonymization Algorithm Implementations
  private async deterministicEncryption(value: string, config: AnonymizationConfig): Promise<string> {
    const cipher = crypto.createCipher('aes-256-cbc', this.encryptionKey);
    let encrypted = cipher.update(value, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return encrypted;
  }

  private async deterministicDecryption(encryptedValue: string, config: AnonymizationConfig): Promise<string> {
    const decipher = crypto.createDecipher('aes-256-cbc', this.encryptionKey);
    let decrypted = decipher.update(encryptedValue, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  }

  private async formatPreservingEncryption(
    value: string,
    dataType: DataType,
    config: AnonymizationConfig
  ): Promise<string> {
    // Implement format-preserving encryption based on data type
    switch (dataType) {
      case DataType.PHONE:
        return this.fpePhone(value);
      case DataType.SSN:
        return this.fpeSSN(value);
      case DataType.CREDIT_CARD:
        return this.fpeCreditCard(value);
      default:
        return this.fpeGeneric(value);
    }
  }

  private async tokenization(value: string, config: AnonymizationConfig): Promise<string> {
    // Check if token already exists
    if (this.tokenMap.has(value)) {
      return this.tokenMap.get(value)!;
    }

    // Generate new token
    const token = 'TKN_' + crypto.randomBytes(16).toString('hex');
    
    // Store bidirectional mapping
    this.tokenMap.set(value, token);
    this.reverseTokenMap.set(token, value);
    
    return token;
  }

  private async detokenization(token: string): Promise<string> {
    const originalValue = this.reverseTokenMap.get(token);
    if (!originalValue) {
      throw new Error('Token not found in mapping');
    }
    return originalValue;
  }

  private async hashing(value: string, config: AnonymizationConfig): Promise<string> {
    const salt = config.parameters?.salt || '';
    const algorithm = config.parameters?.algorithm || 'sha256';
    
    const hash = crypto.createHash(algorithm);
    hash.update(value + salt);
    return hash.digest('hex');
  }

  private async partialMasking(
    value: string,
    dataType: DataType,
    config: AnonymizationConfig
  ): Promise<string> {
    const maskChar = config.parameters?.maskChar || '*';
    const preserveStart = config.parameters?.preserveStart || 2;
    const preserveEnd = config.parameters?.preserveEnd || 2;

    if (value.length <= preserveStart + preserveEnd) {
      return maskChar.repeat(value.length);
    }

    const start = value.substring(0, preserveStart);
    const end = value.substring(value.length - preserveEnd);
    const middle = maskChar.repeat(value.length - preserveStart - preserveEnd);

    return start + middle + end;
  }

  private async randomSubstitution(
    value: string,
    dataType: DataType,
    config: AnonymizationConfig
  ): Promise<string> {
    // Generate random substitute based on data type
    switch (dataType) {
      case DataType.EMAIL:
        return this.generateRandomEmail();
      case DataType.PHONE:
        return this.generateRandomPhone();
      case DataType.NAME:
        return this.generateRandomName();
      case DataType.ADDRESS:
        return this.generateRandomAddress();
      default:
        return this.generateRandomString(value.length);
    }
  }

  private async noiseAddition(value: string, config: AnonymizationConfig): Promise<string> {
    const numericValue = parseFloat(value);
    if (isNaN(numericValue)) {
      throw new Error('Noise addition requires numeric value');
    }

    const noiseLevel = config.parameters?.noiseLevel || 0.1;
    const noise = (Math.random() - 0.5) * 2 * noiseLevel * numericValue;
    
    return String(numericValue + noise);
  }

  // Privacy Model Implementations
  private async applyKAnonymity(
    dataset: Record<string, any>[],
    quasiIdentifiers: string[],
    k: number
  ): Promise<{ dataset: Record<string, any>[]; generalizedFields: string[] }> {
    // Implement k-anonymity algorithm
    // This is a simplified implementation
    const generalizedFields: string[] = [];
    
    // Group records by quasi-identifier combinations
    const groups = new Map<string, Record<string, any>[]>();
    
    for (const record of dataset) {
      const key = quasiIdentifiers.map(field => record[field]).join('|');
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key)!.push(record);
    }

    // Suppress groups with less than k records
    const anonymizedDataset: Record<string, any>[] = [];
    for (const [key, records] of groups) {
      if (records.length >= k) {
        anonymizedDataset.push(...records);
      }
    }

    return { dataset: anonymizedDataset, generalizedFields };
  }

  private async applyLDiversity(
    dataset: Record<string, any>[],
    sensitiveAttributes: string[],
    l: number
  ): Promise<Record<string, any>[]> {
    // Implement l-diversity algorithm
    // This is a placeholder implementation
    return dataset;
  }

  private async applyTCloseness(
    dataset: Record<string, any>[],
    sensitiveAttributes: string[],
    t: number
  ): Promise<Record<string, any>[]> {
    // Implement t-closeness algorithm
    // This is a placeholder implementation
    return dataset;
  }

  // Quality Metrics Calculation
  private async calculateQualityMetrics(
    originalValue: string,
    anonymizedValue: string,
    config: AnonymizationConfig
  ): Promise<QualityMetrics> {
    const informationLoss = this.calculateInformationLoss(originalValue, anonymizedValue);
    const dataUtility = 1 - informationLoss;
    const privacyLevel = this.calculatePrivacyLevel(config.algorithm);

    return {
      informationLoss,
      dataUtility,
      privacyLevel
    };
  }

  private async calculateDatasetQualityMetrics(
    originalDataset: Record<string, any>[],
    anonymizedDataset: Record<string, any>[],
    fieldConfigs: Record<string, any>
  ): Promise<QualityMetrics> {
    // Calculate overall dataset quality metrics
    const informationLoss = this.calculateDatasetInformationLoss(originalDataset, anonymizedDataset);
    const dataUtility = 1 - informationLoss;
    const privacyLevel = this.calculateAveragePrivacyLevel(fieldConfigs);

    return {
      informationLoss,
      dataUtility,
      privacyLevel
    };
  }

  // Utility Methods
  private deriveKey(masterKey: string): Buffer {
    return crypto.pbkdf2Sync(masterKey, 'salt', 100000, 32, 'sha512');
  }

  private calculateInformationLoss(original: string, anonymized: string): number {
    // Simple information loss calculation based on string similarity
    const maxLength = Math.max(original.length, anonymized.length);
    if (maxLength === 0) return 0;
    
    let differences = 0;
    for (let i = 0; i < maxLength; i++) {
      if (original[i] !== anonymized[i]) {
        differences++;
      }
    }
    
    return differences / maxLength;
  }

  private calculateDatasetInformationLoss(
    original: Record<string, any>[],
    anonymized: Record<string, any>[]
  ): number {
    // Calculate information loss for entire dataset
    const recordLoss = (original.length - anonymized.length) / original.length;
    return Math.min(recordLoss, 1.0);
  }

  private calculatePrivacyLevel(algorithm: AnonymizationAlgorithm): number {
    // Assign privacy levels based on algorithm strength
    const privacyLevels = {
      [AnonymizationAlgorithm.HASHING]: 0.9,
      [AnonymizationAlgorithm.DETERMINISTIC_ENCRYPTION]: 0.8,
      [AnonymizationAlgorithm.K_ANONYMITY]: 0.7,
      [AnonymizationAlgorithm.TOKENIZATION]: 0.6,
      [AnonymizationAlgorithm.PARTIAL_MASKING]: 0.4,
      [AnonymizationAlgorithm.NOISE_ADDITION]: 0.5
    };
    
    return privacyLevels[algorithm] || 0.5;
  }

  private calculateAveragePrivacyLevel(fieldConfigs: Record<string, any>): number {
    const levels = Object.values(fieldConfigs).map(config => 
      this.calculatePrivacyLevel(config.config.algorithm)
    );
    return levels.reduce((sum, level) => sum + level, 0) / levels.length;
  }

  // Format-Preserving Encryption Helpers
  private fpePhone(phone: string): string {
    // Preserve phone format while encrypting digits
    return phone.replace(/\d/g, () => Math.floor(Math.random() * 10).toString());
  }

  private fpeSSN(ssn: string): string {
    // Preserve SSN format while encrypting digits
    return ssn.replace(/\d/g, () => Math.floor(Math.random() * 10).toString());
  }

  private fpeCreditCard(cc: string): string {
    // Preserve credit card format while encrypting digits
    return cc.replace(/\d/g, () => Math.floor(Math.random() * 10).toString());
  }

  private fpeGeneric(value: string): string {
    // Generic format-preserving encryption
    return value.replace(/[a-zA-Z]/g, (char) => {
      const isUpper = char === char.toUpperCase();
      const randomChar = String.fromCharCode(97 + Math.floor(Math.random() * 26));
      return isUpper ? randomChar.toUpperCase() : randomChar;
    }).replace(/\d/g, () => Math.floor(Math.random() * 10).toString());
  }

  // Random Data Generators
  private generateRandomEmail(): string {
    const domains = ['example.com', 'test.org', 'sample.net'];
    const username = Math.random().toString(36).substring(2, 10);
    const domain = domains[Math.floor(Math.random() * domains.length)];
    return `${username}@${domain}`;
  }

  private generateRandomPhone(): string {
    const areaCode = Math.floor(Math.random() * 900) + 100;
    const exchange = Math.floor(Math.random() * 900) + 100;
    const number = Math.floor(Math.random() * 9000) + 1000;
    return `(${areaCode}) ${exchange}-${number}`;
  }

  private generateRandomName(): string {
    const firstNames = ['John', 'Jane', 'Bob', 'Alice', 'Charlie', 'Diana'];
    const lastNames = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia'];
    const firstName = firstNames[Math.floor(Math.random() * firstNames.length)];
    const lastName = lastNames[Math.floor(Math.random() * lastNames.length)];
    return `${firstName} ${lastName}`;
  }

  private generateRandomAddress(): string {
    const streetNumbers = Math.floor(Math.random() * 9999) + 1;
    const streetNames = ['Main St', 'Oak Ave', 'Pine Rd', 'Elm Dr', 'Cedar Ln'];
    const streetName = streetNames[Math.floor(Math.random() * streetNames.length)];
    return `${streetNumbers} ${streetName}`;
  }

  private generateRandomString(length: number): string {
    return Math.random().toString(36).substring(2, 2 + length);
  }
}
