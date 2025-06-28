import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import { UAParser } from 'ua-parser-js';
import geoip from 'geoip-lite';
import DeviceDetector from 'device-detector-js';

import {
  AuthService,
  LoginRequest,
  LoginResponse,
  RegisterRequest,
  User,
  Session,
  JwtPayload,
  RefreshTokenPayload,
  AuthContext,
  AuthError,
  MfaRequiredError,
  UserStatus,
  AuthEvent,
  AuthEventResult
} from '../types/auth.types';

import { UserRepository } from '../repositories/user.repository';
import { SessionRepository } from '../repositories/session.repository';
import { MfaService } from './mfa.service';
import { AuditService } from './audit.service';
import { RateLimitService } from './rate-limit.service';
import { NotificationService } from './notification.service';
import { RedisService } from './redis.service';
import { logger } from '../utils/logger';
import { config } from '../config';

export class AuthServiceImpl implements AuthService {
  private readonly deviceDetector = new DeviceDetector();

  constructor(
    private readonly userRepository: UserRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly mfaService: MfaService,
    private readonly auditService: AuditService,
    private readonly rateLimitService: RateLimitService,
    private readonly notificationService: NotificationService,
    private readonly redisService: RedisService
  ) {}

  async login(credentials: LoginRequest, context: AuthContext): Promise<LoginResponse> {
    const { email, password, rememberMe = false, mfaCode, deviceFingerprint } = credentials;

    try {
      // Rate limiting check
      await this.rateLimitService.checkRateLimit(
        context.ipAddress || 'unknown',
        'login',
        'IP'
      );

      // Find user by email
      const user = await this.userRepository.findByEmail(email);
      if (!user) {
        await this.auditService.logAuthEvent({
          eventType: 'LOGIN_FAILED',
          ipAddress: context.ipAddress,
          userAgent: context.userAgent,
          result: AuthEventResult.FAILURE,
          errorMessage: 'User not found',
          metadata: { email }
        });
        throw new AuthError('Invalid credentials', 'INVALID_CREDENTIALS', 401);
      }

      // Check if user is locked
      if (user.lockedUntil && user.lockedUntil > new Date()) {
        await this.auditService.logAuthEvent({
          eventType: 'LOGIN_BLOCKED',
          userId: user.id,
          ipAddress: context.ipAddress,
          userAgent: context.userAgent,
          result: AuthEventResult.FAILURE,
          errorMessage: 'Account locked'
        });
        throw new AuthError('Account is locked', 'ACCOUNT_LOCKED', 423);
      }

      // Check if user is active
      if (user.status !== UserStatus.ACTIVE) {
        await this.auditService.logAuthEvent({
          eventType: 'LOGIN_BLOCKED',
          userId: user.id,
          ipAddress: context.ipAddress,
          userAgent: context.userAgent,
          result: AuthEventResult.FAILURE,
          errorMessage: `Account status: ${user.status}`
        });
        throw new AuthError('Account is not active', 'ACCOUNT_INACTIVE', 403);
      }

      // Verify password
      const isPasswordValid = await bcrypt.compare(password, user.passwordHash || '');
      if (!isPasswordValid) {
        await this.handleFailedLogin(user, context);
        throw new AuthError('Invalid credentials', 'INVALID_CREDENTIALS', 401);
      }

      // Reset failed attempts on successful password verification
      if (user.failedLoginAttempts > 0) {
        await this.userRepository.resetFailedAttempts(user.id);
      }

      // Check if MFA is required
      if (user.mfaEnabled && !mfaCode) {
        const availableMethods = await this.mfaService.getAvailableMethods(user.id);
        const tempSessionId = uuidv4();
        
        // Store temporary session for MFA completion
        await this.redisService.setWithExpiry(
          `mfa_session:${tempSessionId}`,
          JSON.stringify({ userId: user.id, context }),
          300 // 5 minutes
        );

        await this.auditService.logAuthEvent({
          eventType: 'MFA_REQUIRED',
          userId: user.id,
          ipAddress: context.ipAddress,
          userAgent: context.userAgent,
          result: AuthEventResult.SUCCESS
        });

        throw new MfaRequiredError(availableMethods, tempSessionId);
      }

      // Verify MFA if provided
      if (user.mfaEnabled && mfaCode) {
        const mfaValid = await this.mfaService.verifyMfaCode(user.id, mfaCode);
        if (!mfaValid) {
          await this.auditService.logAuthEvent({
            eventType: 'MFA_FAILED',
            userId: user.id,
            ipAddress: context.ipAddress,
            userAgent: context.userAgent,
            result: AuthEventResult.FAILURE,
            errorMessage: 'Invalid MFA code'
          });
          throw new AuthError('Invalid MFA code', 'INVALID_MFA_CODE', 401);
        }
      }

      // Create session
      const session = await this.createSession(user, context, rememberMe, deviceFingerprint);

      // Generate tokens
      const tokens = await this.generateTokens(user, session);

      // Update last login
      await this.userRepository.update(user.id, {
        lastLoginAt: new Date(),
        failedLoginAttempts: 0,
        lockedUntil: undefined
      });

      // Log successful login
      await this.auditService.logAuthEvent({
        eventType: 'LOGIN_SUCCESS',
        userId: user.id,
        sessionId: session.id,
        ipAddress: context.ipAddress,
        userAgent: context.userAgent,
        result: AuthEventResult.SUCCESS,
        metadata: {
          deviceFingerprint,
          location: context.location
        }
      });

      // Send login notification if from new device/location
      await this.checkAndNotifyNewLogin(user, context, session);

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresIn: this.parseExpiry(config.jwt.accessTokenExpiry),
        tokenType: 'Bearer',
        user: this.sanitizeUser(user)
      };

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Login error:', error);
      throw new AuthError('Login failed', 'LOGIN_ERROR', 500);
    }
  }

  async register(userData: RegisterRequest, context: AuthContext): Promise<User> {
    const { email, username, password, firstName, lastName, phone } = userData;

    try {
      // Rate limiting check
      await this.rateLimitService.checkRateLimit(
        context.ipAddress || 'unknown',
        'register',
        'IP'
      );

      // Check if user already exists
      const existingUser = await this.userRepository.findByEmail(email);
      if (existingUser) {
        throw new AuthError('User already exists', 'USER_EXISTS', 409);
      }

      const existingUsername = await this.userRepository.findByUsername(username);
      if (existingUsername) {
        throw new AuthError('Username already taken', 'USERNAME_TAKEN', 409);
      }

      // Hash password
      const passwordHash = await bcrypt.hash(password, config.security.bcryptRounds);

      // Create user
      const user = await this.userRepository.create({
        keycloakId: uuidv4(), // Will be updated when synced with Keycloak
        email,
        username,
        firstName,
        lastName,
        phone,
        passwordHash,
        emailVerified: false,
        phoneVerified: false,
        mfaEnabled: false,
        status: UserStatus.ACTIVE,
        failedLoginAttempts: 0
      });

      // Log registration
      await this.auditService.logAuthEvent({
        eventType: 'USER_REGISTERED',
        userId: user.id,
        ipAddress: context.ipAddress,
        userAgent: context.userAgent,
        result: AuthEventResult.SUCCESS,
        metadata: { email, username }
      });

      // Send welcome email
      await this.notificationService.sendWelcomeEmail(user);

      // Send email verification
      await this.sendEmailVerification(user);

      return this.sanitizeUser(user);

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Registration error:', error);
      throw new AuthError('Registration failed', 'REGISTRATION_ERROR', 500);
    }
  }

  async logout(sessionId: string, context: AuthContext): Promise<void> {
    try {
      const session = await this.sessionRepository.findById(sessionId);
      if (!session) {
        throw new AuthError('Session not found', 'SESSION_NOT_FOUND', 404);
      }

      // Invalidate session
      await this.sessionRepository.update(sessionId, {
        isActive: false,
        logoutReason: 'USER_LOGOUT'
      });

      // Blacklist any active JWT tokens for this session
      await this.blacklistSessionTokens(sessionId);

      // Log logout
      await this.auditService.logAuthEvent({
        eventType: 'LOGOUT',
        userId: session.userId,
        sessionId: session.id,
        ipAddress: context.ipAddress,
        userAgent: context.userAgent,
        result: AuthEventResult.SUCCESS
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Logout error:', error);
      throw new AuthError('Logout failed', 'LOGOUT_ERROR', 500);
    }
  }

  async refreshToken(refreshToken: string, context: AuthContext): Promise<LoginResponse> {
    try {
      // Verify refresh token
      const payload = jwt.verify(refreshToken, config.jwt.refreshSecret) as RefreshTokenPayload;

      // Check if token is blacklisted
      const isBlacklisted = await this.redisService.get(`blacklist:${payload.jti}`);
      if (isBlacklisted) {
        throw new AuthError('Token is blacklisted', 'TOKEN_BLACKLISTED', 401);
      }

      // Get session
      const session = await this.sessionRepository.findById(payload.sessionId);
      if (!session || !session.isActive) {
        throw new AuthError('Invalid session', 'INVALID_SESSION', 401);
      }

      // Get user
      const user = await this.userRepository.findById(payload.sub);
      if (!user || user.status !== UserStatus.ACTIVE) {
        throw new AuthError('User not found or inactive', 'USER_INACTIVE', 401);
      }

      // Update session activity
      await this.sessionRepository.update(session.id, {
        lastActivityAt: new Date()
      });

      // Generate new tokens
      const tokens = await this.generateTokens(user, session);

      // Blacklist old refresh token
      await this.redisService.setWithExpiry(
        `blacklist:${payload.jti}`,
        'true',
        this.parseExpiry(config.jwt.refreshTokenExpiry)
      );

      // Log token refresh
      await this.auditService.logAuthEvent({
        eventType: 'TOKEN_REFRESHED',
        userId: user.id,
        sessionId: session.id,
        ipAddress: context.ipAddress,
        userAgent: context.userAgent,
        result: AuthEventResult.SUCCESS
      });

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresIn: this.parseExpiry(config.jwt.accessTokenExpiry),
        tokenType: 'Bearer',
        user: this.sanitizeUser(user)
      };

    } catch (error) {
      if (error instanceof jwt.JsonWebTokenError) {
        throw new AuthError('Invalid refresh token', 'INVALID_REFRESH_TOKEN', 401);
      }
      
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Token refresh error:', error);
      throw new AuthError('Token refresh failed', 'TOKEN_REFRESH_ERROR', 500);
    }
  }

  async verifyToken(token: string): Promise<JwtPayload> {
    try {
      const payload = jwt.verify(token, config.jwt.secret) as JwtPayload;

      // Check if token is blacklisted
      const isBlacklisted = await this.redisService.get(`blacklist:${payload.jti}`);
      if (isBlacklisted) {
        throw new AuthError('Token is blacklisted', 'TOKEN_BLACKLISTED', 401);
      }

      return payload;

    } catch (error) {
      if (error instanceof jwt.JsonWebTokenError) {
        throw new AuthError('Invalid token', 'INVALID_TOKEN', 401);
      }
      
      throw error;
    }
  }

  async changePassword(userId: string, oldPassword: string, newPassword: string): Promise<void> {
    try {
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Verify old password
      const isOldPasswordValid = await bcrypt.compare(oldPassword, user.passwordHash || '');
      if (!isOldPasswordValid) {
        throw new AuthError('Invalid current password', 'INVALID_PASSWORD', 400);
      }

      // Hash new password
      const newPasswordHash = await bcrypt.hash(newPassword, config.security.bcryptRounds);

      // Update password
      await this.userRepository.update(userId, {
        passwordHash: newPasswordHash,
        passwordChangedAt: new Date()
      });

      // Invalidate all sessions except current one
      await this.invalidateUserSessions(userId);

      // Log password change
      await this.auditService.logAuthEvent({
        eventType: 'PASSWORD_CHANGED',
        userId: user.id,
        result: AuthEventResult.SUCCESS
      });

      // Send notification
      await this.notificationService.sendPasswordChangeNotification(user);

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Password change error:', error);
      throw new AuthError('Password change failed', 'PASSWORD_CHANGE_ERROR', 500);
    }
  }

  async resetPassword(email: string): Promise<void> {
    try {
      const user = await this.userRepository.findByEmail(email);
      if (!user) {
        // Don't reveal if user exists
        return;
      }

      // Generate reset token
      const resetToken = crypto.randomBytes(32).toString('hex');
      const resetTokenExpiry = new Date(Date.now() + 3600000); // 1 hour

      // Store reset token
      await this.redisService.setWithExpiry(
        `password_reset:${resetToken}`,
        user.id,
        3600 // 1 hour
      );

      // Send reset email
      await this.notificationService.sendPasswordResetEmail(user, resetToken);

      // Log password reset request
      await this.auditService.logAuthEvent({
        eventType: 'PASSWORD_RESET_REQUESTED',
        userId: user.id,
        result: AuthEventResult.SUCCESS
      });

    } catch (error) {
      logger.error('Password reset error:', error);
      throw new AuthError('Password reset failed', 'PASSWORD_RESET_ERROR', 500);
    }
  }

  async confirmPasswordReset(token: string, newPassword: string): Promise<void> {
    try {
      // Get user ID from token
      const userId = await this.redisService.get(`password_reset:${token}`);
      if (!userId) {
        throw new AuthError('Invalid or expired reset token', 'INVALID_RESET_TOKEN', 400);
      }

      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Hash new password
      const passwordHash = await bcrypt.hash(newPassword, config.security.bcryptRounds);

      // Update password
      await this.userRepository.update(userId, {
        passwordHash,
        passwordChangedAt: new Date(),
        failedLoginAttempts: 0,
        lockedUntil: undefined
      });

      // Delete reset token
      await this.redisService.delete(`password_reset:${token}`);

      // Invalidate all sessions
      await this.invalidateUserSessions(userId);

      // Log password reset
      await this.auditService.logAuthEvent({
        eventType: 'PASSWORD_RESET_COMPLETED',
        userId: user.id,
        result: AuthEventResult.SUCCESS
      });

      // Send confirmation email
      await this.notificationService.sendPasswordResetConfirmation(user);

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Password reset confirmation error:', error);
      throw new AuthError('Password reset confirmation failed', 'PASSWORD_RESET_CONFIRM_ERROR', 500);
    }
  }

  private async createSession(
    user: User,
    context: AuthContext,
    rememberMe: boolean,
    deviceFingerprint?: string
  ): Promise<Session> {
    const sessionToken = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(
      Date.now() + (rememberMe ? 30 * 24 * 60 * 60 * 1000 : 24 * 60 * 60 * 1000)
    );

    // Parse device info
    const deviceInfo = this.parseDeviceInfo(context.userAgent);
    const location = this.parseLocation(context.ipAddress);

    return await this.sessionRepository.create({
      sessionToken,
      userId: user.id,
      ipAddress: context.ipAddress,
      userAgent: context.userAgent,
      deviceFingerprint,
      isMobile: deviceInfo.isMobile,
      location,
      expiresAt,
      isActive: true
    });
  }

  private async generateTokens(user: User, session: Session): Promise<{
    accessToken: string;
    refreshToken: string;
  }> {
    const now = Math.floor(Date.now() / 1000);
    const accessTokenExpiry = now + this.parseExpiry(config.jwt.accessTokenExpiry);
    const refreshTokenExpiry = now + this.parseExpiry(config.jwt.refreshTokenExpiry);

    // Get user permissions (this would integrate with RBAC service)
    const permissions = await this.getUserPermissions(user.id);
    const roles = await this.getUserRoles(user.id);

    const accessTokenPayload: JwtPayload = {
      sub: user.id,
      email: user.email,
      username: user.username,
      roles: roles.map(r => r.name),
      permissions: permissions.map(p => p.name),
      sessionId: session.id,
      iat: now,
      exp: accessTokenExpiry,
      jti: uuidv4(),
      iss: config.jwt.issuer,
      aud: config.jwt.audience
    };

    const refreshTokenPayload: RefreshTokenPayload = {
      sub: user.id,
      sessionId: session.id,
      tokenVersion: user.version,
      iat: now,
      exp: refreshTokenExpiry,
      jti: uuidv4()
    };

    const accessToken = jwt.sign(accessTokenPayload, config.jwt.secret);
    const refreshToken = jwt.sign(refreshTokenPayload, config.jwt.refreshSecret);

    return { accessToken, refreshToken };
  }

  private async handleFailedLogin(user: User, context: AuthContext): Promise<void> {
    const newFailedAttempts = user.failedLoginAttempts + 1;
    
    let updates: Partial<User> = {
      failedLoginAttempts: newFailedAttempts
    };

    // Lock account if too many failed attempts
    if (newFailedAttempts >= config.security.maxFailedAttempts) {
      updates.lockedUntil = new Date(Date.now() + config.security.lockoutDuration);
    }

    await this.userRepository.update(user.id, updates);

    // Log failed login
    await this.auditService.logAuthEvent({
      eventType: 'LOGIN_FAILED',
      userId: user.id,
      ipAddress: context.ipAddress,
      userAgent: context.userAgent,
      result: AuthEventResult.FAILURE,
      errorMessage: 'Invalid password',
      metadata: { failedAttempts: newFailedAttempts }
    });

    // Send security alert if account is locked
    if (newFailedAttempts >= config.security.maxFailedAttempts) {
      await this.notificationService.sendAccountLockedNotification(user);
    }
  }

  private async blacklistSessionTokens(sessionId: string): Promise<void> {
    // This would blacklist all JWT tokens for the session
    // Implementation depends on your token storage strategy
    await this.redisService.setWithExpiry(
      `session_blacklist:${sessionId}`,
      'true',
      this.parseExpiry(config.jwt.refreshTokenExpiry)
    );
  }

  private async invalidateUserSessions(userId: string, exceptSessionId?: string): Promise<void> {
    const sessions = await this.sessionRepository.findByUserId(userId);
    
    for (const session of sessions) {
      if (session.id !== exceptSessionId) {
        await this.sessionRepository.update(session.id, {
          isActive: false,
          logoutReason: 'SECURITY_LOGOUT'
        });
        await this.blacklistSessionTokens(session.id);
      }
    }
  }

  private async sendEmailVerification(user: User): Promise<void> {
    const verificationToken = crypto.randomBytes(32).toString('hex');
    
    await this.redisService.setWithExpiry(
      `email_verification:${verificationToken}`,
      user.id,
      86400 // 24 hours
    );

    await this.notificationService.sendEmailVerification(user, verificationToken);
  }

  private async checkAndNotifyNewLogin(
    user: User,
    context: AuthContext,
    session: Session
  ): Promise<void> {
    // Check if this is a new device/location
    const recentSessions = await this.sessionRepository.findByUserId(user.id);
    const isNewDevice = !recentSessions.some(s => 
      s.deviceFingerprint === session.deviceFingerprint && s.id !== session.id
    );

    if (isNewDevice) {
      await this.notificationService.sendNewDeviceLoginNotification(user, session);
    }
  }

  private parseDeviceInfo(userAgent?: string): { isMobile: boolean; device: string } {
    if (!userAgent) {
      return { isMobile: false, device: 'Unknown' };
    }

    const detector = this.deviceDetector.parse(userAgent);
    return {
      isMobile: detector.device?.type === 'smartphone' || detector.device?.type === 'tablet',
      device: `${detector.os?.name || 'Unknown'} ${detector.client?.name || 'Unknown'}`
    };
  }

  private parseLocation(ipAddress?: string): any {
    if (!ipAddress) return null;
    
    const geo = geoip.lookup(ipAddress);
    return geo ? {
      country: geo.country,
      region: geo.region,
      city: geo.city,
      latitude: geo.ll[0],
      longitude: geo.ll[1]
    } : null;
  }

  private parseExpiry(expiry: string): number {
    const match = expiry.match(/^(\d+)([smhd])$/);
    if (!match) return 3600; // Default 1 hour

    const value = parseInt(match[1]);
    const unit = match[2];

    switch (unit) {
      case 's': return value;
      case 'm': return value * 60;
      case 'h': return value * 3600;
      case 'd': return value * 86400;
      default: return 3600;
    }
  }

  private sanitizeUser(user: User): Partial<User> {
    const { passwordHash, mfaSecret, backupCodes, ...sanitized } = user;
    return sanitized;
  }

  private async getUserPermissions(userId: string): Promise<any[]> {
    // This would integrate with your RBAC service
    // For now, return empty array
    return [];
  }

  private async getUserRoles(userId: string): Promise<any[]> {
    // This would integrate with your RBAC service
    // For now, return empty array
    return [];
  }
}
