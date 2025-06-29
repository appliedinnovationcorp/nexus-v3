import { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import crypto from 'crypto';
import DOMPurify from 'isomorphic-dompurify';
import { body, query, param, validationResult } from 'express-validator';
import rateLimit from 'express-rate-limit';
import slowDown from 'express-slow-down';

import { SecurityConfig } from '../config/security.config';
import { logger } from '../utils/logger';
import { SecurityMetrics } from '../utils/metrics';

export class SecurityMiddleware {
  private readonly config: SecurityConfig;
  private readonly metrics: SecurityMetrics;

  constructor(config: SecurityConfig, metrics: SecurityMetrics) {
    this.config = config;
    this.metrics = metrics;
  }

  // Content Security Policy with nonce support
  contentSecurityPolicy() {
    return (req: Request, res: Response, next: NextFunction) => {
      // Generate unique nonce for each request
      const nonce = crypto.randomBytes(16).toString('base64');
      res.locals.nonce = nonce;

      // Set CSP header with nonce
      const cspDirectives = {
        defaultSrc: ["'self'"],
        scriptSrc: [
          "'self'",
          `'nonce-${nonce}'`,
          "'strict-dynamic'",
          // Allow specific trusted domains
          'https://cdn.jsdelivr.net',
          'https://unpkg.com'
        ],
        styleSrc: [
          "'self'",
          `'nonce-${nonce}'`,
          "'unsafe-inline'", // Required for some CSS frameworks
          'https://fonts.googleapis.com'
        ],
        fontSrc: [
          "'self'",
          'https://fonts.gstatic.com',
          'data:'
        ],
        imgSrc: [
          "'self'",
          'data:',
          'https:',
          'blob:'
        ],
        connectSrc: [
          "'self'",
          'https://api.example.com',
          'wss://websocket.example.com'
        ],
        frameSrc: ["'none'"],
        objectSrc: ["'none'"],
        mediaSrc: ["'self'"],
        manifestSrc: ["'self'"],
        workerSrc: ["'self'"],
        childSrc: ["'none'"],
        formAction: ["'self'"],
        frameAncestors: ["'none'"],
        baseUri: ["'self'"],
        upgradeInsecureRequests: []
      };

      // Build CSP header string
      const cspHeader = Object.entries(cspDirectives)
        .map(([directive, sources]) => {
          const kebabDirective = directive.replace(/([A-Z])/g, '-$1').toLowerCase();
          return `${kebabDirective} ${sources.join(' ')}`;
        })
        .join('; ');

      res.setHeader('Content-Security-Policy', cspHeader);

      // Report-only mode for testing
      if (this.config.csp.reportOnly) {
        res.setHeader('Content-Security-Policy-Report-Only', cspHeader);
      }

      // CSP violation reporting endpoint
      if (this.config.csp.reportUri) {
        res.setHeader('Report-To', JSON.stringify({
          group: 'csp-endpoint',
          max_age: 10886400,
          endpoints: [{ url: this.config.csp.reportUri }]
        }));
      }

      next();
    };
  }

  // Comprehensive security headers
  securityHeaders() {
    return helmet({
      // Content Security Policy (handled separately with nonce)
      contentSecurityPolicy: false,
      
      // Cross-Origin Embedder Policy
      crossOriginEmbedderPolicy: { policy: 'require-corp' },
      
      // Cross-Origin Opener Policy
      crossOriginOpenerPolicy: { policy: 'same-origin' },
      
      // Cross-Origin Resource Policy
      crossOriginResourcePolicy: { policy: 'cross-origin' },
      
      // DNS Prefetch Control
      dnsPrefetchControl: { allow: false },
      
      // Frameguard (X-Frame-Options)
      frameguard: { action: 'deny' },
      
      // Hide Powered-By header
      hidePoweredBy: true,
      
      // HTTP Strict Transport Security
      hsts: {
        maxAge: 31536000, // 1 year
        includeSubDomains: true,
        preload: true
      },
      
      // IE No Open
      ieNoOpen: true,
      
      // No Sniff (X-Content-Type-Options)
      noSniff: true,
      
      // Origin Agent Cluster
      originAgentCluster: true,
      
      // Permissions Policy
      permissionsPolicy: {
        camera: [],
        microphone: [],
        geolocation: [],
        gyroscope: [],
        magnetometer: [],
        payment: [],
        usb: []
      },
      
      // Referrer Policy
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
      
      // X-XSS-Protection
      xssFilter: true
    });
  }

  // Input validation and sanitization
  validateAndSanitize(validationRules: any[]) {
    return [
      ...validationRules,
      (req: Request, res: Response, next: NextFunction) => {
        // Check validation results
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
          this.metrics.incrementValidationErrors();
          
          logger.warn('Input validation failed', {
            errors: errors.array(),
            ip: req.ip,
            userAgent: req.get('User-Agent'),
            path: req.path
          });

          return res.status(400).json({
            error: 'Invalid input',
            code: 'VALIDATION_ERROR',
            details: errors.array()
          });
        }

        // Sanitize input data
        this.sanitizeRequestData(req);
        
        next();
      }
    ];
  }

  // XSS Protection and sanitization
  xssProtection() {
    return (req: Request, res: Response, next: NextFunction) => {
      // Sanitize request body
      if (req.body && typeof req.body === 'object') {
        req.body = this.sanitizeObject(req.body);
      }

      // Sanitize query parameters
      if (req.query && typeof req.query === 'object') {
        req.query = this.sanitizeObject(req.query);
      }

      // Override res.json to sanitize response data
      const originalJson = res.json;
      res.json = function(data: any) {
        if (data && typeof data === 'object') {
          data = this.sanitizeObject(data);
        }
        return originalJson.call(this, data);
      }.bind(this);

      next();
    };
  }

  // SQL Injection Prevention
  sqlInjectionProtection() {
    return (req: Request, res: Response, next: NextFunction) => {
      const suspiciousPatterns = [
        /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|SCRIPT)\b)/gi,
        /(\b(OR|AND)\s+\d+\s*=\s*\d+)/gi,
        /(--|\/\*|\*\/|;)/g,
        /(\b(CHAR|NCHAR|VARCHAR|NVARCHAR)\s*\(\s*\d+\s*\))/gi,
        /(\b(CAST|CONVERT|SUBSTRING|ASCII|CHAR_LENGTH)\s*\()/gi
      ];

      const checkForSqlInjection = (value: string): boolean => {
        return suspiciousPatterns.some(pattern => pattern.test(value));
      };

      const scanObject = (obj: any, path: string = ''): boolean => {
        for (const [key, value] of Object.entries(obj)) {
          const currentPath = path ? `${path}.${key}` : key;
          
          if (typeof value === 'string') {
            if (checkForSqlInjection(value)) {
              logger.warn('Potential SQL injection attempt detected', {
                path: currentPath,
                value: value.substring(0, 100), // Log first 100 chars
                ip: req.ip,
                userAgent: req.get('User-Agent'),
                url: req.originalUrl
              });
              
              this.metrics.incrementSqlInjectionAttempts();
              return true;
            }
          } else if (typeof value === 'object' && value !== null) {
            if (scanObject(value, currentPath)) {
              return true;
            }
          }
        }
        return false;
      };

      // Check request body
      if (req.body && scanObject(req.body, 'body')) {
        return res.status(400).json({
          error: 'Invalid input detected',
          code: 'SECURITY_VIOLATION'
        });
      }

      // Check query parameters
      if (req.query && scanObject(req.query, 'query')) {
        return res.status(400).json({
          error: 'Invalid query parameters',
          code: 'SECURITY_VIOLATION'
        });
      }

      // Check URL parameters
      if (req.params && scanObject(req.params, 'params')) {
        return res.status(400).json({
          error: 'Invalid URL parameters',
          code: 'SECURITY_VIOLATION'
        });
      }

      next();
    };
  }

  // Rate limiting with different strategies
  rateLimiting() {
    const standardLimiter = rateLimit({
      windowMs: 15 * 60 * 1000, // 15 minutes
      max: 100, // Limit each IP to 100 requests per windowMs
      message: {
        error: 'Too many requests',
        code: 'RATE_LIMIT_EXCEEDED'
      },
      standardHeaders: true,
      legacyHeaders: false,
      handler: (req, res) => {
        this.metrics.incrementRateLimitHits();
        logger.warn('Rate limit exceeded', {
          ip: req.ip,
          userAgent: req.get('User-Agent'),
          path: req.path
        });
        res.status(429).json({
          error: 'Too many requests',
          code: 'RATE_LIMIT_EXCEEDED'
        });
      }
    });

    const strictLimiter = rateLimit({
      windowMs: 15 * 60 * 1000,
      max: 5, // Strict limit for sensitive endpoints
      message: {
        error: 'Too many requests to sensitive endpoint',
        code: 'STRICT_RATE_LIMIT_EXCEEDED'
      }
    });

    const speedLimiter = slowDown({
      windowMs: 15 * 60 * 1000,
      delayAfter: 50,
      delayMs: 500,
      maxDelayMs: 20000
    });

    return {
      standard: standardLimiter,
      strict: strictLimiter,
      speed: speedLimiter
    };
  }

  // Request size limiting
  requestSizeLimit() {
    return (req: Request, res: Response, next: NextFunction) => {
      const maxSize = this.config.maxRequestSize || 1024 * 1024; // 1MB default
      
      if (req.headers['content-length']) {
        const contentLength = parseInt(req.headers['content-length']);
        if (contentLength > maxSize) {
          this.metrics.incrementOversizedRequests();
          
          logger.warn('Request size limit exceeded', {
            contentLength,
            maxSize,
            ip: req.ip,
            path: req.path
          });

          return res.status(413).json({
            error: 'Request entity too large',
            code: 'REQUEST_TOO_LARGE'
          });
        }
      }

      next();
    };
  }

  // Security event logging
  securityEventLogger() {
    return (req: Request, res: Response, next: NextFunction) => {
      const startTime = Date.now();

      // Log security-relevant requests
      const securityPaths = ['/auth', '/admin', '/api/sensitive'];
      const isSecurityPath = securityPaths.some(path => req.path.startsWith(path));

      if (isSecurityPath) {
        logger.info('Security-sensitive request', {
          method: req.method,
          path: req.path,
          ip: req.ip,
          userAgent: req.get('User-Agent'),
          referer: req.get('Referer'),
          timestamp: new Date().toISOString()
        });
      }

      // Override res.end to log response
      const originalEnd = res.end;
      res.end = function(chunk?: any, encoding?: any) {
        const duration = Date.now() - startTime;
        
        if (isSecurityPath || res.statusCode >= 400) {
          logger.info('Security response', {
            method: req.method,
            path: req.path,
            statusCode: res.statusCode,
            duration,
            ip: req.ip
          });
        }

        originalEnd.call(this, chunk, encoding);
      };

      next();
    };
  }

  // Private helper methods
  private sanitizeRequestData(req: Request): void {
    if (req.body) {
      req.body = this.sanitizeObject(req.body);
    }
    if (req.query) {
      req.query = this.sanitizeObject(req.query);
    }
  }

  private sanitizeObject(obj: any): any {
    if (typeof obj === 'string') {
      return this.sanitizeString(obj);
    }
    
    if (Array.isArray(obj)) {
      return obj.map(item => this.sanitizeObject(item));
    }
    
    if (obj && typeof obj === 'object') {
      const sanitized: any = {};
      for (const [key, value] of Object.entries(obj)) {
        sanitized[key] = this.sanitizeObject(value);
      }
      return sanitized;
    }
    
    return obj;
  }

  private sanitizeString(str: string): string {
    // Remove potentially dangerous HTML/JavaScript
    let sanitized = DOMPurify.sanitize(str, {
      ALLOWED_TAGS: [],
      ALLOWED_ATTR: [],
      KEEP_CONTENT: true
    });

    // Additional sanitization for common attack vectors
    sanitized = sanitized
      .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '') // Remove script tags
      .replace(/javascript:/gi, '') // Remove javascript: protocol
      .replace(/on\w+\s*=/gi, '') // Remove event handlers
      .replace(/expression\s*\(/gi, '') // Remove CSS expressions
      .replace(/url\s*\(/gi, ''); // Remove CSS url() functions

    return sanitized;
  }
}

// Validation rule builders
export class ValidationRules {
  static email() {
    return body('email')
      .isEmail()
      .normalizeEmail()
      .withMessage('Invalid email format');
  }

  static password() {
    return body('password')
      .isLength({ min: 8, max: 128 })
      .matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
      .withMessage('Password must contain at least 8 characters with uppercase, lowercase, number, and special character');
  }

  static username() {
    return body('username')
      .isLength({ min: 3, max: 30 })
      .matches(/^[a-zA-Z0-9_-]+$/)
      .withMessage('Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens');
  }

  static id() {
    return param('id')
      .isUUID()
      .withMessage('Invalid ID format');
  }

  static pagination() {
    return [
      query('page')
        .optional()
        .isInt({ min: 1, max: 1000 })
        .withMessage('Page must be a positive integer'),
      query('limit')
        .optional()
        .isInt({ min: 1, max: 100 })
        .withMessage('Limit must be between 1 and 100')
    ];
  }

  static sanitizeHtml() {
    return body('content')
      .customSanitizer((value) => {
        return DOMPurify.sanitize(value, {
          ALLOWED_TAGS: ['p', 'br', 'strong', 'em', 'u', 'ol', 'ul', 'li'],
          ALLOWED_ATTR: []
        });
      });
  }

  static noSqlInjection() {
    return body('*')
      .custom((value) => {
        const sqlPatterns = [
          /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|SCRIPT)\b)/gi,
          /(--|\/\*|\*\/|;)/g
        ];
        
        const checkValue = (val: any): boolean => {
          if (typeof val === 'string') {
            return !sqlPatterns.some(pattern => pattern.test(val));
          }
          if (Array.isArray(val)) {
            return val.every(checkValue);
          }
          if (val && typeof val === 'object') {
            return Object.values(val).every(checkValue);
          }
          return true;
        };

        if (!checkValue(value)) {
          throw new Error('Invalid input detected');
        }
        return true;
      });
  }
}

// Factory function to create security middleware
export function createSecurityMiddleware(config: SecurityConfig, metrics: SecurityMetrics): SecurityMiddleware {
  return new SecurityMiddleware(config, metrics);
}
