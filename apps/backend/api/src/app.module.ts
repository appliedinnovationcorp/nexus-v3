import { Module } from '@nestjs/common'
import { ConfigModule, ConfigService } from '@nestjs/config'
import { ThrottlerModule } from '@nestjs/throttler'
import { TypeOrmModule } from '@nestjs/typeorm'
import { CacheModule } from '@nestjs/cache-manager'
import { ScheduleModule } from '@nestjs/schedule'
import { EventEmitterModule } from '@nestjs/event-emitter'
import { HealthModule } from './modules/health/health.module'
import { AuthModule } from './modules/auth/auth.module'
import { UsersModule } from './modules/users/users.module'
import { CommonModule } from './modules/common/common.module'
import { DatabaseConfig } from './config/database.config'
import { AppConfig } from './config/app.config'
import { RedisConfig } from './config/redis.config'

/**
 * Root application module with comprehensive configuration
 * 
 * Features:
 * - Configuration management with validation
 * - Database connection with TypeORM
 * - Redis caching integration
 * - Rate limiting and throttling
 * - Event-driven architecture
 * - Scheduled tasks support
 * - Health checks and monitoring
 */
@Module({
  imports: [
    // Configuration module with validation
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      expandVariables: true,
      load: [AppConfig, DatabaseConfig, RedisConfig],
      validate: (config) => {
        // Basic validation - you can extend this with Joi or class-validator
        const requiredVars = ['NODE_ENV', 'DATABASE_URL']
        const missing = requiredVars.filter(key => !config[key])
        
        if (missing.length > 0) {
          throw new Error(`Missing required environment variables: ${missing.join(', ')}`)
        }
        
        return config
      },
    }),
    
    // Database connection
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        url: configService.get<string>('DATABASE_URL'),
        autoLoadEntities: true,
        synchronize: configService.get<string>('NODE_ENV') === 'development',
        logging: configService.get<string>('NODE_ENV') === 'development',
        retryAttempts: 3,
        retryDelay: 3000,
        maxQueryExecutionTime: 10000,
        extra: {
          max: 20, // Maximum number of connections
          idleTimeoutMillis: 30000,
          connectionTimeoutMillis: 2000,
        },
      }),
      inject: [ConfigService],
    }),
    
    // Redis caching
    CacheModule.registerAsync({
      isGlobal: true,
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        store: 'redis',
        host: configService.get<string>('REDIS_HOST', 'localhost'),
        port: configService.get<number>('REDIS_PORT', 6379),
        password: configService.get<string>('REDIS_PASSWORD'),
        db: configService.get<number>('REDIS_DB', 0),
        ttl: configService.get<number>('CACHE_TTL', 300), // 5 minutes default
        max: configService.get<number>('CACHE_MAX_ITEMS', 1000),
      }),
      inject: [ConfigService],
    }),
    
    // Rate limiting
    ThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        ttl: configService.get<number>('THROTTLE_TTL', 60),
        limit: configService.get<number>('THROTTLE_LIMIT', 100),
      }),
      inject: [ConfigService],
    }),
    
    // Event-driven architecture
    EventEmitterModule.forRoot({
      wildcard: false,
      delimiter: '.',
      newListener: false,
      removeListener: false,
      maxListeners: 10,
      verboseMemoryLeak: false,
      ignoreErrors: false,
    }),
    
    // Scheduled tasks
    ScheduleModule.forRoot(),
    
    // Feature modules
    CommonModule,
    HealthModule,
    AuthModule,
    UsersModule,
  ],
  controllers: [],
  providers: [],
})
export class AppModule {}
