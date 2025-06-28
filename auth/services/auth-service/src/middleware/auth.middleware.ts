import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { UAParser } from 'ua-parser-js';

import {
  AuthenticatedRequest,
  JwtPayload,
  AuthError,
  RateLimitError,
  InsufficientPermissionsError,
  User,
  ApiKey,
  Session
} from '../types/auth.types';

import { AuthService } from '../services/auth.service';
import { ApiKeyService } from '../services/api-key.service';
import { RbacService } from '../services/rbac.service';
import { SessionRepository } from '../repositories/session.repository';
import { UserRepository } from '../repositories/user.repository';
import { RateLimitService } from '../services/rate-limit.service';
import { AuditService } from '../services/audit.service';
import { RedisService } from '../services/redis.service';
import { logger } from '../utils/logger';
import { config } from '../config';

export class AuthMiddleware {
  constructor(
    private readonly authService: AuthService,
    private readonly apiKeyService: ApiKeyService,
    private readonly rbacService: RbacService,
    private readonly sessionRepository: SessionRepository,
    private readonly userRepository: UserRepository,
    private readonly rateLimitService: RateLimitService,
    private readonly auditService: AuditService,
    private readonly redisService: RedisService
  ) {}

  // JWT Token Authentication
  authenticateToken = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const authHeader = req.headers.authorization;
      const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

      if (!token) {
        return res.status(401).json({
          error: 'Access token required',
          code: 'TOKEN_REQUIRED'
        });
      }

      // Verify and decode token
      const payload = await this.authService.verifyToken(token);
      
      // Get user details
      const user = await this.userRepository.findById(payload.sub);
      if (!user) {
        return res.status(401).json({
          error: 'User not found',
          code: 'USER_NOT_FOUND'
        });
      }

      // Check if user is active
      if (user.status !== 'ACTIVE') {
        return res.status(403).json({
          error: 'User account is not active',
          code: 'USER_INACTIVE'
        });
      }

      // Get session details
      const session = await this.sessionRepository.findById(payload.sessionId);
      if (!session || !session.isActive) {
        return res.status(401).json({
          error: 'Invalid session',
          code: 'INVALID_SESSION'
        });
      }

      // Update session activity
      await this.sessionRepository.update(session.id, {
        lastActivityAt: new Date()
      });

      // Attach user and session to request
      req.user = user;
      req.session = session;
      req.permissions = await this.rbacService.getUserPermissions(user.id);

      next();

    } catch (error) {
      if (error instanceof AuthError) {
        return res.status(error.statusCode).json({
          error: error.message,
          code: error.code
        });
      }

      logger.error('Token authentication error:', error);
      return res.status(401).json({
        error: 'Invalid token',
        code: 'INVALID_TOKEN'
      });
    }
  };

  // API Key Authentication
  authenticateApiKey = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const apiKey = req.headers['x-api-key'] as string;

      if (!apiKey) {
        return res.status(401).json({
          error: 'API key required',
          code: 'API_KEY_REQUIRED'
        });
      }

      // Validate API key
      const validatedKey = await this.apiKeyService.validateApiKey(apiKey);
      if (!validatedKey) {
        await this.auditService.logAuthEvent({
          eventType: 'API_KEY_INVALID',
          ipAddress: this.getClientIp(req),
          userAgent: req.headers['user-agent'],
          result: 'FAILURE',
          metadata: { keyPrefix: apiKey.substring(0, 8) }
        });

        return res.status(401).json({
          error: 'Invalid API key',
          code: 'INVALID_API_KEY'
        });
      }

      // Check IP restrictions
      if (validatedKey.allowedIps && validatedKey.allowedIps.length > 0) {
        const clientIp = this.getClientIp(req);
        if (!validatedKey.allowedIps.includes(clientIp)) {
          await this.auditService.logAuthEvent({
            eventType: 'API_KEY_IP_BLOCKED',
            userId: validatedKey.userId,
            apiKeyId: validatedKey.id,
            ipAddress: clientIp,
            result: 'FAILURE'
          });

          return res.status(403).json({
            error: 'IP address not allowed',
            code: 'IP_NOT_ALLOWED'
          });
        }
      }

      // Check domain restrictions
      if (validatedKey.allowedDomains && validatedKey.allowedDomains.length > 0) {
        const origin = req.headers.origin || req.headers.referer;
        if (origin) {
          const domain = new URL(origin).hostname;
          if (!validatedKey.allowedDomains.includes(domain)) {
            return res.status(403).json({
              error: 'Domain not allowed',
              code: 'DOMAIN_NOT_ALLOWED'
            });
          }
        }
      }

      // Check rate limits
      try {
        await this.apiKeyService.checkApiKeyRateLimit(validatedKey, req.path);
      } catch (error) {
        if (error instanceof RateLimitError) {
          return res.status(429).json({
            error: 'Rate limit exceeded',
            code: 'RATE_LIMIT_EXCEEDED',
            resetTime: error.resetTime
          });
        }
        throw error;
      }

      // Get user if API key is associated with one
      let user: User | undefined;
      if (validatedKey.userId) {
        user = await this.userRepository.findById(validatedKey.userId);
      }

      // Attach API key and user to request
      req.apiKey = validatedKey;
      req.user = user;
      
      // Get permissions based on API key scopes
      if (user) {
        req.permissions = await this.rbacService.getUserPermissions(user.id);
      }

      next();

    } catch (error) {
      logger.error('API key authentication error:', error);
      return res.status(500).json({
        error: 'Authentication failed',
        code: 'AUTH_ERROR'
      });
    }
  };

  // Optional Authentication (allows both authenticated and anonymous access)
  optionalAuth = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    const authHeader = req.headers.authorization;
    const apiKey = req.headers['x-api-key'] as string;

    if (authHeader) {
      return this.authenticateToken(req, res, next);
    } else if (apiKey) {
      return this.authenticateApiKey(req, res, next);
    } else {
      // No authentication provided, continue as anonymous
      next();
    }
  };

  // Permission-based authorization
  requirePermission = (resource: string, action: string) => {
    return async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
      try {
        if (!req.user) {
          return res.status(401).json({
            error: 'Authentication required',
            code: 'AUTH_REQUIRED'
          });
        }

        const hasPermission = await this.rbacService.checkPermission(
          req.user.id,
          resource,
          action,
          {
            ipAddress: this.getClientIp(req),
            userAgent: req.headers['user-agent'],
            requestPath: req.path,
            requestMethod: req.method
          }
        );

        if (!hasPermission) {
          await this.auditService.logAuthEvent({
            eventType: 'PERMISSION_DENIED',
            userId: req.user.id,
            sessionId: req.session?.id,
            apiKeyId: req.apiKey?.id,
            ipAddress: this.getClientIp(req),
            userAgent: req.headers['user-agent'],
            resource,
            action,
            result: 'FAILURE'
          });

          return res.status(403).json({
            error: `Insufficient permissions for ${action} on ${resource}`,
            code: 'INSUFFICIENT_PERMISSIONS'
          });
        }

        next();

      } catch (error) {
        logger.error('Permission check error:', error);
        return res.status(500).json({
          error: 'Authorization failed',
          code: 'AUTHZ_ERROR'
        });
      }
    };
  };

  // Role-based authorization
  requireRole = (roleName: string) => {
    return async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
      try {
        if (!req.user) {
          return res.status(401).json({
            error: 'Authentication required',
            code: 'AUTH_REQUIRED'
          });
        }

        const userRoles = await this.rbacService.getUserRoles(req.user.id);
        const hasRole = userRoles.some(role => role.name === roleName);

        if (!hasRole) {
          return res.status(403).json({
            error: `Role '${roleName}' required`,
            code: 'INSUFFICIENT_ROLE'
          });
        }

        next();

      } catch (error) {
        logger.error('Role check error:', error);
        return res.status(500).json({
          error: 'Authorization failed',
          code: 'AUTHZ_ERROR'
        });
      }
    };
  };

  // Scope-based authorization for API keys
  requireScope = (scope: string) => {
    return async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
      try {
        if (!req.apiKey) {
          return res.status(401).json({
            error: 'API key authentication required',
            code: 'API_KEY_REQUIRED'
          });
        }

        if (!req.apiKey.scopes.includes(scope)) {
          return res.status(403).json({
            error: `Scope '${scope}' required`,
            code: 'INSUFFICIENT_SCOPE'
          });
        }

        next();

      } catch (error) {
        logger.error('Scope check error:', error);
        return res.status(500).json({
          error: 'Authorization failed',
          code: 'AUTHZ_ERROR'
        });
      }
    };
  };

  // Rate limiting middleware
  rateLimit = (
    maxRequests: number = 100,
    windowMs: number = 900000, // 15 minutes
    identifier: 'ip' | 'user' | 'apikey' = 'ip'
  ) => {
    return async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
      try {
        let rateLimitId: string;
        let rateLimitType: string;

        switch (identifier) {
          case 'user':
            if (!req.user) {
              return next(); // Skip rate limiting if no user
            }
            rateLimitId = req.user.id;
            rateLimitType = 'USER';
            break;
          
          case 'apikey':
            if (!req.apiKey) {
              return next(); // Skip rate limiting if no API key
            }
            rateLimitId = req.apiKey.keyId;
            rateLimitType = 'API_KEY';
            break;
          
          default:
            rateLimitId = this.getClientIp(req);
            rateLimitType = 'IP';
        }

        await this.rateLimitService.checkRateLimit(
          rateLimitId,
          req.path,
          rateLimitType as any,
          maxRequests,
          Math.floor(windowMs / 1000)
        );

        next();

      } catch (error) {
        if (error instanceof RateLimitError) {
          return res.status(429).json({
            error: 'Rate limit exceeded',
            code: 'RATE_LIMIT_EXCEEDED',
            resetTime: error.resetTime,
            remaining: error.remaining
          });
        }

        logger.error('Rate limiting error:', error);
        next(); // Continue on error to avoid blocking legitimate requests
      }
    };
  };

  // Session validation middleware
  validateSession = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      if (!req.session) {
        return next(); // Skip if no session
      }

      // Check if session is expired
      if (req.session.expiresAt < new Date()) {
        await this.sessionRepository.update(req.session.id, {
          isActive: false,
          logoutReason: 'SESSION_EXPIRED'
        });

        return res.status(401).json({
          error: 'Session expired',
          code: 'SESSION_EXPIRED'
        });
      }

      // Check for suspicious activity
      const currentIp = this.getClientIp(req);
      const currentUserAgent = req.headers['user-agent'];

      if (req.session.ipAddress !== currentIp) {
        // Log suspicious activity
        await this.auditService.logAuthEvent({
          eventType: 'SUSPICIOUS_SESSION_ACTIVITY',
          userId: req.user?.id,
          sessionId: req.session.id,
          ipAddress: currentIp,
          userAgent: currentUserAgent,
          result: 'FAILURE',
          metadata: {
            originalIp: req.session.ipAddress,
            originalUserAgent: req.session.userAgent
          }
        });

        // Optionally invalidate session for security
        if (config.security.strictSessionValidation) {
          await this.sessionRepository.update(req.session.id, {
            isActive: false,
            logoutReason: 'IP_CHANGE'
          });

          return res.status(401).json({
            error: 'Session invalidated due to IP change',
            code: 'SESSION_INVALIDATED'
          });
        }
      }

      next();

    } catch (error) {
      logger.error('Session validation error:', error);
      next(); // Continue on error
    }
  };

  // Device fingerprinting middleware
  deviceFingerprint = (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userAgent = req.headers['user-agent'] || '';
      const acceptLanguage = req.headers['accept-language'] || '';
      const acceptEncoding = req.headers['accept-encoding'] || '';
      
      // Create a simple device fingerprint
      const fingerprint = this.createDeviceFingerprint({
        userAgent,
        acceptLanguage,
        acceptEncoding,
        ip: this.getClientIp(req)
      });

      req.deviceFingerprint = fingerprint;
      next();

    } catch (error) {
      logger.error('Device fingerprinting error:', error);
      next(); // Continue on error
    }
  };

  // Security headers middleware
  securityHeaders = (req: Request, res: Response, next: NextFunction) => {
    // Set security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
    
    // HSTS header for HTTPS
    if (req.secure) {
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    }

    next();
  };

  private getClientIp(req: Request): string {
    return (
      req.headers['x-forwarded-for'] as string ||
      req.headers['x-real-ip'] as string ||
      req.connection.remoteAddress ||
      req.socket.remoteAddress ||
      'unknown'
    ).split(',')[0].trim();
  }

  private createDeviceFingerprint(data: {
    userAgent: string;
    acceptLanguage: string;
    acceptEncoding: string;
    ip: string;
  }): string {
    const crypto = require('crypto');
    const fingerprint = `${data.userAgent}|${data.acceptLanguage}|${data.acceptEncoding}|${data.ip}`;
    return crypto.createHash('sha256').update(fingerprint).digest('hex');
  }
}

// Utility function to create middleware instance
export function createAuthMiddleware(
  authService: AuthService,
  apiKeyService: ApiKeyService,
  rbacService: RbacService,
  sessionRepository: SessionRepository,
  userRepository: UserRepository,
  rateLimitService: RateLimitService,
  auditService: AuditService,
  redisService: RedisService
): AuthMiddleware {
  return new AuthMiddleware(
    authService,
    apiKeyService,
    rbacService,
    sessionRepository,
    userRepository,
    rateLimitService,
    auditService,
    redisService
  );
}
