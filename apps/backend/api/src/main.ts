import { NestFactory } from '@nestjs/core'
import { ValidationPipe, Logger } from '@nestjs/common'
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger'
import { ConfigService } from '@nestjs/config'
import helmet from 'helmet'
import compression from 'compression'
import rateLimit from 'express-rate-limit'
import type { NestExpressApplication } from '@nestjs/platform-express'
import { AppModule } from './app.module'

/**
 * Bootstrap the NestJS application with comprehensive configuration
 * 
 * Features:
 * - Security middleware (Helmet, CORS, Rate limiting)
 * - Request validation and transformation
 * - OpenAPI/Swagger documentation
 * - Compression and performance optimizations
 * - Graceful shutdown handling
 */
async function bootstrap(): Promise<void> {
  const logger = new Logger('Bootstrap')
  
  try {
    // Create NestJS application
    const app = await NestFactory.create<NestExpressApplication>(AppModule, {
      logger: ['error', 'warn', 'log', 'debug', 'verbose'],
    })
    
    const configService = app.get(ConfigService)
    const port = configService.get<number>('PORT', 3000)
    const nodeEnv = configService.get<string>('NODE_ENV', 'development')
    
    // Security middleware
    app.use(helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          scriptSrc: ["'self'"],
          imgSrc: ["'self'", 'data:', 'https:'],
        },
      },
      crossOriginEmbedderPolicy: false,
    }))
    
    // CORS configuration
    app.enableCors({
      origin: configService.get<string>('CORS_ORIGIN', 'http://localhost:3000'),
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
      credentials: true,
    })
    
    // Rate limiting
    app.use(
      rateLimit({
        windowMs: 15 * 60 * 1000, // 15 minutes
        max: configService.get<number>('RATE_LIMIT_MAX', 1000), // limit each IP to 1000 requests per windowMs
        message: {
          error: 'Too many requests from this IP',
          statusCode: 429,
          timestamp: new Date().toISOString(),
        },
        standardHeaders: true,
        legacyHeaders: false,
      })
    )
    
    // Compression
    app.use(compression())
    
    // Global validation pipe
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true, // Strip properties that don't have decorators
        forbidNonWhitelisted: true, // Throw error if non-whitelisted properties are present
        transform: true, // Automatically transform payloads to DTO instances
        transformOptions: {
          enableImplicitConversion: true, // Allow type conversion
        },
        errorHttpStatusCode: 422, // Use 422 for validation errors
      })
    )
    
    // Global prefix for all routes
    app.setGlobalPrefix('api/v1')
    
    // OpenAPI/Swagger documentation
    if (nodeEnv !== 'production') {
      const config = new DocumentBuilder()
        .setTitle('Nexus API')
        .setDescription('Enterprise-grade API for Nexus application')
        .setVersion('1.0.0')
        .addBearerAuth(
          {
            type: 'http',
            scheme: 'bearer',
            bearerFormat: 'JWT',
            name: 'JWT',
            description: 'Enter JWT token',
            in: 'header',
          },
          'JWT-auth'
        )
        .addApiKey(
          {
            type: 'apiKey',
            name: 'X-API-Key',
            in: 'header',
            description: 'API Key for authentication',
          },
          'API-Key'
        )
        .addTag('auth', 'Authentication endpoints')
        .addTag('users', 'User management endpoints')
        .addTag('health', 'Health check endpoints')
        .addServer(`http://localhost:${port}`, 'Development server')
        .addServer('https://api.nexus.com', 'Production server')
        .build()
      
      const document = SwaggerModule.createDocument(app, config)
      SwaggerModule.setup('api/docs', app, document, {
        swaggerOptions: {
          persistAuthorization: true,
          tagsSorter: 'alpha',
          operationsSorter: 'alpha',
        },
        customSiteTitle: 'Nexus API Documentation',
        customfavIcon: '/favicon.ico',
        customCss: `
          .swagger-ui .topbar { display: none }
          .swagger-ui .info { margin: 20px 0 }
        `,
      })
      
      logger.log(`📚 API Documentation available at http://localhost:${port}/api/docs`)
    }
    
    // Health check endpoint
    app.getHttpAdapter().get('/health', (req, res) => {
      res.status(200).json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        environment: nodeEnv,
        version: process.env.npm_package_version || '1.0.0',
        memory: process.memoryUsage(),
      })
    })
    
    // Graceful shutdown
    const gracefulShutdown = (signal: string) => {
      logger.log(`🛑 Received ${signal}, shutting down gracefully...`)
      app.close().then(() => {
        logger.log('✅ Application closed successfully')
        process.exit(0)
      }).catch((error) => {
        logger.error('❌ Error during shutdown:', error)
        process.exit(1)
      })
    }
    
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'))
    process.on('SIGINT', () => gracefulShutdown('SIGINT'))
    
    // Start the server
    await app.listen(port, '0.0.0.0')
    
    logger.log(`🚀 Application is running on: http://localhost:${port}`)
    logger.log(`🌍 Environment: ${nodeEnv}`)
    logger.log(`📊 Health check: http://localhost:${port}/health`)
    
  } catch (error) {
    logger.error('❌ Failed to start application:', error)
    process.exit(1)
  }
}

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  const logger = new Logger('UnhandledRejection')
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason)
  process.exit(1)
})

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  const logger = new Logger('UncaughtException')
  logger.error('Uncaught Exception:', error)
  process.exit(1)
})

bootstrap()
