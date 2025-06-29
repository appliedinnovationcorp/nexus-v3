import { Module, Global } from '@nestjs/common'
import { APP_FILTER, APP_INTERCEPTOR, APP_GUARD } from '@nestjs/core'
import { ThrottlerGuard } from '@nestjs/throttler'
import { GlobalExceptionFilter } from './filters/global-exception.filter'
import { ResponseInterceptor } from './interceptors/response.interceptor'
import { LoggingInterceptor } from './interceptors/logging.interceptor'
import { ValidationService } from './services/validation.service'
import { CryptoService } from './services/crypto.service'
import { DateService } from './services/date.service'

/**
 * Common module providing shared services, filters, interceptors, and guards
 * 
 * This module is global and provides:
 * - Exception handling and error formatting
 * - Request/response logging and transformation
 * - Rate limiting and throttling
 * - Common utility services (validation, crypto, date)
 */
@Global()
@Module({
  providers: [
    // Global exception filter
    {
      provide: APP_FILTER,
      useClass: GlobalExceptionFilter,
    },
    
    // Global interceptors
    {
      provide: APP_INTERCEPTOR,
      useClass: LoggingInterceptor,
    },
    {
      provide: APP_INTERCEPTOR,
      useClass: ResponseInterceptor,
    },
    
    // Global guards
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    
    // Common services
    ValidationService,
    CryptoService,
    DateService,
  ],
  exports: [
    ValidationService,
    CryptoService,
    DateService,
  ],
})
export class CommonModule {}
