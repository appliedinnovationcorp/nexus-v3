import speakeasy from 'speakeasy';
import QRCode from 'qrcode';
import crypto from 'crypto';
import { authenticator } from 'otplib';

import {
  MfaService,
  MfaSetupRequest,
  MfaSetupResponse,
  MfaVerifyRequest,
  MfaMethod,
  MfaMethodType,
  User,
  AuthError
} from '../types/auth.types';

import { UserRepository } from '../repositories/user.repository';
import { MfaMethodRepository } from '../repositories/mfa-method.repository';
import { NotificationService } from './notification.service';
import { RedisService } from './redis.service';
import { AuditService } from './audit.service';
import { logger } from '../utils/logger';
import { config } from '../config';

export class MfaServiceImpl implements MfaService {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly mfaMethodRepository: MfaMethodRepository,
    private readonly notificationService: NotificationService,
    private readonly redisService: RedisService,
    private readonly auditService: AuditService
  ) {}

  async setupTotp(userId: string): Promise<MfaSetupResponse> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Generate secret
      const secret = speakeasy.generateSecret({
        name: `${config.mfa.issuer}:${user.email}`,
        issuer: config.mfa.issuer,
        length: 32
      });

      // Generate QR code
      const qrCodeUrl = speakeasy.otpauthURL({
        secret: secret.ascii,
        label: `${config.mfa.issuer}:${user.email}`,
        issuer: config.mfa.issuer,
        algorithm: 'sha1',
        digits: 6,
        period: 30
      });

      const qrCode = await QRCode.toDataURL(qrCodeUrl);

      // Store temporary secret (not yet verified)
      await this.redisService.setWithExpiry(
        `mfa_setup:${userId}:totp`,
        JSON.stringify({
          secret: secret.base32,
          method: 'TOTP',
          timestamp: Date.now()
        }),
        600 // 10 minutes
      );

      // Generate backup codes
      const backupCodes = this.generateBackupCodes();

      await this.auditService.logAuthEvent({
        eventType: 'MFA_SETUP_INITIATED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'TOTP' }
      });

      return {
        secret: secret.base32,
        qrCode,
        backupCodes,
        verificationRequired: true
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('TOTP setup error:', error);
      throw new AuthError('TOTP setup failed', 'TOTP_SETUP_ERROR', 500);
    }
  }

  async verifyTotp(userId: string, code: string): Promise<boolean> {
    try {
      // Get temporary setup data
      const setupData = await this.redisService.get(`mfa_setup:${userId}:totp`);
      if (!setupData) {
        throw new AuthError('No TOTP setup in progress', 'NO_TOTP_SETUP', 400);
      }

      const { secret } = JSON.parse(setupData);

      // Verify the code
      const verified = speakeasy.totp.verify({
        secret,
        encoding: 'base32',
        token: code,
        window: config.mfa.window
      });

      if (!verified) {
        await this.auditService.logAuthEvent({
          eventType: 'MFA_VERIFICATION_FAILED',
          userId,
          result: 'FAILURE',
          metadata: { method: 'TOTP' }
        });
        return false;
      }

      // Save MFA method
      await this.mfaMethodRepository.create({
        userId,
        methodType: MfaMethodType.TOTP,
        methodData: { secret },
        isPrimary: true,
        isVerified: true,
        verifiedAt: new Date()
      });

      // Enable MFA for user
      await this.userRepository.update(userId, {
        mfaEnabled: true,
        mfaSecret: secret
      });

      // Clean up temporary data
      await this.redisService.delete(`mfa_setup:${userId}:totp`);

      await this.auditService.logAuthEvent({
        eventType: 'MFA_ENABLED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'TOTP' }
      });

      return true;

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('TOTP verification error:', error);
      throw new AuthError('TOTP verification failed', 'TOTP_VERIFY_ERROR', 500);
    }
  }

  async setupSms(userId: string, phoneNumber: string): Promise<MfaSetupResponse> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Generate verification code
      const verificationCode = this.generateNumericCode(6);

      // Store verification data
      await this.redisService.setWithExpiry(
        `mfa_setup:${userId}:sms`,
        JSON.stringify({
          phoneNumber,
          verificationCode,
          method: 'SMS',
          timestamp: Date.now()
        }),
        300 // 5 minutes
      );

      // Send SMS
      await this.notificationService.sendSmsVerification(phoneNumber, verificationCode);

      await this.auditService.logAuthEvent({
        eventType: 'MFA_SETUP_INITIATED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'SMS', phoneNumber: this.maskPhoneNumber(phoneNumber) }
      });

      return {
        verificationRequired: true
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('SMS MFA setup error:', error);
      throw new AuthError('SMS MFA setup failed', 'SMS_SETUP_ERROR', 500);
    }
  }

  async verifySms(userId: string, code: string): Promise<boolean> {
    try {
      // Get setup data
      const setupData = await this.redisService.get(`mfa_setup:${userId}:sms`);
      if (!setupData) {
        throw new AuthError('No SMS setup in progress', 'NO_SMS_SETUP', 400);
      }

      const { phoneNumber, verificationCode } = JSON.parse(setupData);

      if (code !== verificationCode) {
        await this.auditService.logAuthEvent({
          eventType: 'MFA_VERIFICATION_FAILED',
          userId,
          result: 'FAILURE',
          metadata: { method: 'SMS' }
        });
        return false;
      }

      // Save MFA method
      await this.mfaMethodRepository.create({
        userId,
        methodType: MfaMethodType.SMS,
        methodData: { phoneNumber },
        isPrimary: false,
        isVerified: true,
        verifiedAt: new Date()
      });

      // Update user phone if not set
      const user = await this.userRepository.findById(userId);
      if (user && !user.phone) {
        await this.userRepository.update(userId, {
          phone: phoneNumber,
          phoneVerified: true
        });
      }

      // Clean up
      await this.redisService.delete(`mfa_setup:${userId}:sms`);

      await this.auditService.logAuthEvent({
        eventType: 'MFA_METHOD_ADDED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'SMS' }
      });

      return true;

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('SMS verification error:', error);
      throw new AuthError('SMS verification failed', 'SMS_VERIFY_ERROR', 500);
    }
  }

  async setupEmail(userId: string, email: string): Promise<MfaSetupResponse> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Generate verification code
      const verificationCode = this.generateNumericCode(6);

      // Store verification data
      await this.redisService.setWithExpiry(
        `mfa_setup:${userId}:email`,
        JSON.stringify({
          email,
          verificationCode,
          method: 'EMAIL',
          timestamp: Date.now()
        }),
        300 // 5 minutes
      );

      // Send email
      await this.notificationService.sendEmailMfaCode(email, verificationCode);

      await this.auditService.logAuthEvent({
        eventType: 'MFA_SETUP_INITIATED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'EMAIL', email: this.maskEmail(email) }
      });

      return {
        verificationRequired: true
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Email MFA setup error:', error);
      throw new AuthError('Email MFA setup failed', 'EMAIL_SETUP_ERROR', 500);
    }
  }

  async verifyEmail(userId: string, code: string): Promise<boolean> {
    try {
      // Get setup data
      const setupData = await this.redisService.get(`mfa_setup:${userId}:email`);
      if (!setupData) {
        throw new AuthError('No email setup in progress', 'NO_EMAIL_SETUP', 400);
      }

      const { email, verificationCode } = JSON.parse(setupData);

      if (code !== verificationCode) {
        await this.auditService.logAuthEvent({
          eventType: 'MFA_VERIFICATION_FAILED',
          userId,
          result: 'FAILURE',
          metadata: { method: 'EMAIL' }
        });
        return false;
      }

      // Save MFA method
      await this.mfaMethodRepository.create({
        userId,
        methodType: MfaMethodType.EMAIL,
        methodData: { email },
        isPrimary: false,
        isVerified: true,
        verifiedAt: new Date()
      });

      // Clean up
      await this.redisService.delete(`mfa_setup:${userId}:email`);

      await this.auditService.logAuthEvent({
        eventType: 'MFA_METHOD_ADDED',
        userId,
        result: 'SUCCESS',
        metadata: { method: 'EMAIL' }
      });

      return true;

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Email verification error:', error);
      throw new AuthError('Email verification failed', 'EMAIL_VERIFY_ERROR', 500);
    }
  }

  async generateBackupCodes(userId: string): Promise<string[]> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      const backupCodes = this.generateBackupCodes();
      const hashedCodes = await Promise.all(
        backupCodes.map(code => this.hashBackupCode(code))
      );

      // Save backup codes method
      await this.mfaMethodRepository.create({
        userId,
        methodType: MfaMethodType.BACKUP_CODES,
        methodData: { codes: hashedCodes },
        isPrimary: false,
        isVerified: true,
        verifiedAt: new Date()
      });

      // Update user backup codes
      await this.userRepository.update(userId, {
        backupCodes: hashedCodes
      });

      await this.auditService.logAuthEvent({
        eventType: 'BACKUP_CODES_GENERATED',
        userId,
        result: 'SUCCESS',
        metadata: { count: backupCodes.length }
      });

      return backupCodes;

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Backup codes generation error:', error);
      throw new AuthError('Backup codes generation failed', 'BACKUP_CODES_ERROR', 500);
    }
  }

  async verifyBackupCode(userId: string, code: string): Promise<boolean> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user || !user.backupCodes) {
        return false;
      }

      // Check if code matches any backup code
      let matchedIndex = -1;
      for (let i = 0; i < user.backupCodes.length; i++) {
        if (await this.verifyBackupCodeHash(code, user.backupCodes[i])) {
          matchedIndex = i;
          break;
        }
      }

      if (matchedIndex === -1) {
        await this.auditService.logAuthEvent({
          eventType: 'BACKUP_CODE_FAILED',
          userId,
          result: 'FAILURE'
        });
        return false;
      }

      // Remove used backup code
      const updatedCodes = [...user.backupCodes];
      updatedCodes.splice(matchedIndex, 1);

      await this.userRepository.update(userId, {
        backupCodes: updatedCodes
      });

      // Update MFA method
      await this.mfaMethodRepository.updateByUserIdAndType(
        userId,
        MfaMethodType.BACKUP_CODES,
        {
          methodData: { codes: updatedCodes },
          lastUsedAt: new Date()
        }
      );

      await this.auditService.logAuthEvent({
        eventType: 'BACKUP_CODE_USED',
        userId,
        result: 'SUCCESS',
        metadata: { remainingCodes: updatedCodes.length }
      });

      // Warn if running low on backup codes
      if (updatedCodes.length <= 2) {
        await this.notificationService.sendLowBackupCodesWarning(user, updatedCodes.length);
      }

      return true;

    } catch (error) {
      logger.error('Backup code verification error:', error);
      return false;
    }
  }

  async verifyMfaCode(userId: string, code: string, methodType?: MfaMethodType): Promise<boolean> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user || !user.mfaEnabled) {
        return false;
      }

      // If no method type specified, try all available methods
      if (!methodType) {
        const methods = await this.mfaMethodRepository.findByUserId(userId);
        
        for (const method of methods) {
          if (await this.verifyCodeForMethod(userId, code, method.methodType)) {
            return true;
          }
        }
        
        return false;
      }

      return await this.verifyCodeForMethod(userId, code, methodType);

    } catch (error) {
      logger.error('MFA code verification error:', error);
      return false;
    }
  }

  async disableMfa(userId: string): Promise<void> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Remove all MFA methods
      await this.mfaMethodRepository.deleteByUserId(userId);

      // Disable MFA for user
      await this.userRepository.update(userId, {
        mfaEnabled: false,
        mfaSecret: undefined,
        backupCodes: undefined
      });

      await this.auditService.logAuthEvent({
        eventType: 'MFA_DISABLED',
        userId,
        result: 'SUCCESS'
      });

      // Send notification
      await this.notificationService.sendMfaDisabledNotification(user);

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('MFA disable error:', error);
      throw new AuthError('MFA disable failed', 'MFA_DISABLE_ERROR', 500);
    }
  }

  async getAvailableMethods(userId: string): Promise<MfaMethodType[]> {
    try {
      const methods = await this.mfaMethodRepository.findByUserId(userId);
      return methods
        .filter(method => method.isVerified)
        .map(method => method.methodType);
    } catch (error) {
      logger.error('Get available methods error:', error);
      return [];
    }
  }

  async sendMfaCode(userId: string, methodType: MfaMethodType): Promise<void> {
    try {
      const method = await this.mfaMethodRepository.findByUserIdAndType(userId, methodType);
      if (!method || !method.isVerified) {
        throw new AuthError('MFA method not found or not verified', 'MFA_METHOD_NOT_FOUND', 404);
      }

      const code = this.generateNumericCode(6);
      const cacheKey = `mfa_code:${userId}:${methodType}`;

      // Store code temporarily
      await this.redisService.setWithExpiry(cacheKey, code, 300); // 5 minutes

      switch (methodType) {
        case MfaMethodType.SMS:
          await this.notificationService.sendSmsVerification(
            method.methodData.phoneNumber,
            code
          );
          break;
        
        case MfaMethodType.EMAIL:
          await this.notificationService.sendEmailMfaCode(
            method.methodData.email,
            code
          );
          break;
        
        default:
          throw new AuthError('Unsupported MFA method for code sending', 'UNSUPPORTED_MFA_METHOD', 400);
      }

      await this.auditService.logAuthEvent({
        eventType: 'MFA_CODE_SENT',
        userId,
        result: 'SUCCESS',
        metadata: { method: methodType }
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Send MFA code error:', error);
      throw new AuthError('Failed to send MFA code', 'MFA_CODE_SEND_ERROR', 500);
    }
  }

  private async verifyCodeForMethod(
    userId: string,
    code: string,
    methodType: MfaMethodType
  ): Promise<boolean> {
    switch (methodType) {
      case MfaMethodType.TOTP:
        return await this.verifyTotpCode(userId, code);
      
      case MfaMethodType.SMS:
      case MfaMethodType.EMAIL:
        return await this.verifyTemporaryCode(userId, code, methodType);
      
      case MfaMethodType.BACKUP_CODES:
        return await this.verifyBackupCode(userId, code);
      
      default:
        return false;
    }
  }

  private async verifyTotpCode(userId: string, code: string): Promise<boolean> {
    const user = await this.userRepository.findById(userId);
    if (!user || !user.mfaSecret) {
      return false;
    }

    return speakeasy.totp.verify({
      secret: user.mfaSecret,
      encoding: 'base32',
      token: code,
      window: config.mfa.window
    });
  }

  private async verifyTemporaryCode(
    userId: string,
    code: string,
    methodType: MfaMethodType
  ): Promise<boolean> {
    const cacheKey = `mfa_code:${userId}:${methodType}`;
    const storedCode = await this.redisService.get(cacheKey);
    
    if (!storedCode || storedCode !== code) {
      return false;
    }

    // Remove used code
    await this.redisService.delete(cacheKey);
    return true;
  }

  private generateBackupCodes(): string[] {
    const codes: string[] = [];
    for (let i = 0; i < config.mfa.backupCodesCount; i++) {
      codes.push(this.generateAlphanumericCode(8));
    }
    return codes;
  }

  private generateNumericCode(length: number): string {
    const digits = '0123456789';
    let code = '';
    for (let i = 0; i < length; i++) {
      code += digits[Math.floor(Math.random() * digits.length)];
    }
    return code;
  }

  private generateAlphanumericCode(length: number): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code = '';
    for (let i = 0; i < length; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    return code;
  }

  private async hashBackupCode(code: string): Promise<string> {
    return crypto.createHash('sha256').update(code).digest('hex');
  }

  private async verifyBackupCodeHash(code: string, hash: string): Promise<boolean> {
    const codeHash = crypto.createHash('sha256').update(code).digest('hex');
    return codeHash === hash;
  }

  private maskPhoneNumber(phone: string): string {
    if (phone.length <= 4) return phone;
    return phone.slice(0, -4).replace(/\d/g, '*') + phone.slice(-4);
  }

  private maskEmail(email: string): string {
    const [local, domain] = email.split('@');
    if (local.length <= 2) return email;
    return local.slice(0, 2) + '*'.repeat(local.length - 2) + '@' + domain;
  }
}
