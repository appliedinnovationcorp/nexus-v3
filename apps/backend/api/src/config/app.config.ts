import { registerAs } from '@nestjs/config'

/**
 * Application configuration
 * 
 * Centralizes all application-level configuration with proper typing
 * and default values for development and production environments.
 */
export const AppConfig = registerAs('app', () => ({
  // Environment
  nodeEnv: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  
  // API Configuration
  apiPrefix: process.env.API_PREFIX || 'api/v1',
  apiVersion: process.env.API_VERSION || '1.0.0',
  
  // CORS Configuration
  corsOrigin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  
  // Rate Limiting
  rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX || '1000', 10),
  rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10), // 15 minutes
  
  // Throttling
  throttleTtl: parseInt(process.env.THROTTLE_TTL || '60', 10),
  throttleLimit: parseInt(process.env.THROTTLE_LIMIT || '100', 10),
  
  // Security
  jwtSecret: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '24h',
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
  
  // API Keys
  apiKeyHeader: process.env.API_KEY_HEADER || 'X-API-Key',
  
  // File Upload
  maxFileSize: parseInt(process.env.MAX_FILE_SIZE || '10485760', 10), // 10MB
  allowedFileTypes: process.env.ALLOWED_FILE_TYPES?.split(',') || [
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'application/pdf',
  ],
  
  // Pagination
  defaultPageSize: parseInt(process.env.DEFAULT_PAGE_SIZE || '20', 10),
  maxPageSize: parseInt(process.env.MAX_PAGE_SIZE || '100', 10),
  
  // Logging
  logLevel: process.env.LOG_LEVEL || 'info',
  logFormat: process.env.LOG_FORMAT || 'combined',
  
  // External Services
  emailService: {
    host: process.env.EMAIL_HOST || 'localhost',
    port: parseInt(process.env.EMAIL_PORT || '587', 10),
    secure: process.env.EMAIL_SECURE === 'true',
    user: process.env.EMAIL_USER,
    password: process.env.EMAIL_PASSWORD,
    from: process.env.EMAIL_FROM || 'noreply@nexus.com',
  },
  
  // Feature Flags
  features: {
    enableSwagger: process.env.ENABLE_SWAGGER !== 'false',
    enableMetrics: process.env.ENABLE_METRICS !== 'false',
    enableHealthChecks: process.env.ENABLE_HEALTH_CHECKS !== 'false',
    enableRateLimiting: process.env.ENABLE_RATE_LIMITING !== 'false',
  },
  
  // Performance
  requestTimeout: parseInt(process.env.REQUEST_TIMEOUT || '30000', 10), // 30 seconds
  keepAliveTimeout: parseInt(process.env.KEEP_ALIVE_TIMEOUT || '5000', 10), // 5 seconds
  
  // Monitoring
  metricsPath: process.env.METRICS_PATH || '/metrics',
  healthCheckPath: process.env.HEALTH_CHECK_PATH || '/health',
}))
