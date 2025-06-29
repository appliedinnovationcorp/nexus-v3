const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const winston = require('winston');
const client = require('prom-client');

// Import services
const DatabaseService = require('./services/DatabaseService');
const CacheService = require('./services/CacheService');
const CodePushService = require('./services/CodePushService');

// Import middleware
const authMiddleware = require('./middleware/auth');
const validationMiddleware = require('./middleware/validation');
const metricsMiddleware = require('./middleware/metrics');

// Import routes
const appsRoutes = require('./controllers/appsController');
const deploymentsRoutes = require('./controllers/deploymentsController');
const updatesRoutes = require('./controllers/updatesController');

const app = express();
const port = process.env.PORT || 3000;

// Configure logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/codepush-server.log' })
  ]
});

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'codepush_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const updateDownloads = new client.Counter({
  name: 'codepush_update_downloads_total',
  help: 'Total number of update downloads',
  labelNames: ['app_name', 'deployment_name', 'update_version'],
  registers: [register]
});

const activeApps = new client.Gauge({
  name: 'codepush_active_apps',
  help: 'Number of active applications',
  registers: [register]
});

// Initialize services
const dbService = new DatabaseService();
const cacheService = new CacheService();
const codePushService = new CodePushService(dbService, cacheService);

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
}));

// Performance middleware
app.use(compression());

// CORS
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
  credentials: true,
  optionsSuccessStatus: 200
}));

// Body parsing
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Metrics middleware
app.use(metricsMiddleware(httpRequestDuration));

// Routes
app.use('/v0.1/apps', authMiddleware, appsRoutes);
app.use('/v0.1/apps/:appName/deployments', authMiddleware, deploymentsRoutes);
app.use('/updateCheck', updatesRoutes);
app.use('/reportStatus', updatesRoutes);

// Health check
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    await dbService.healthCheck();
    
    // Check Redis connection
    await cacheService.healthCheck();
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        database: 'healthy',
        cache: 'healthy'
      }
    });
  } catch (error) {
    logger.error('Health check failed', { error: error.message });
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Update metrics periodically
setInterval(async () => {
  try {
    const appCount = await codePushService.getActiveAppCount();
    activeApps.set(appCount);
  } catch (error) {
    logger.error('Error updating metrics', { error: error.message });
  }
}, 60000); // Update every minute

// Error handling middleware
app.use((error, req, res, next) => {
  logger.error('Unhandled error', {
    error: error.message,
    stack: error.stack,
    url: req.url,
    method: req.method
  });
  
  res.status(500).json({
    error: 'Internal server error',
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    timestamp: new Date().toISOString()
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down gracefully');
  
  // Close database connections
  await dbService.close();
  
  // Close Redis connections
  await cacheService.close();
  
  process.exit(0);
});

// Start server
app.listen(port, '0.0.0.0', () => {
  logger.info(`CodePush server listening on port ${port}`);
});

module.exports = { app, logger, updateDownloads };
