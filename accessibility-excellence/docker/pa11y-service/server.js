const express = require('express');
const pa11y = require('pa11y');
const redis = require('redis');
const { MongoClient } = require('mongodb');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');
const { v4: uuidv4 } = require('uuid');
const cron = require('node-cron');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const accessibilityTests = new promClient.Counter({
  name: 'accessibility_tests_total',
  help: 'Total number of accessibility tests performed',
  labelNames: ['test_type', 'status']
});
const accessibilityViolations = new promClient.Counter({
  name: 'accessibility_violations_total',
  help: 'Total number of accessibility violations found',
  labelNames: ['violation_type', 'severity']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(accessibilityTests);
register.registerMetric(accessibilityViolations);

// Logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console()
  ]
});

const app = express();
const port = process.env.PORT || 4000;

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

// MongoDB client
let mongoClient;
let db;

redisClient.on('error', (err) => {
  logger.error('Redis Client Error', err);
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode)
      .observe(duration);
  });
  next();
});

// Pa11y configuration
const pa11yConfig = {
  standard: 'WCAG2AA',
  timeout: 30000,
  wait: 2000,
  chromeLaunchConfig: {
    ignoreHTTPSErrors: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--disable-web-security',
      '--disable-features=VizDisplayCompositor'
    ]
  },
  rules: [
    'color-contrast',
    'document-title',
    'duplicate-id',
    'empty-heading',
    'heading-order',
    'html-has-lang',
    'html-lang-valid',
    'image-alt',
    'input-image-alt',
    'label',
    'landmark-banner-is-top-level',
    'landmark-complementary-is-top-level',
    'landmark-contentinfo-is-top-level',
    'landmark-main-is-top-level',
    'landmark-no-duplicate-banner',
    'landmark-no-duplicate-contentinfo',
    'landmark-one-main',
    'link-name',
    'list',
    'listitem',
    'meta-refresh',
    'meta-viewport',
    'page-has-heading-one',
    'region',
    'skip-link',
    'tabindex'
  ],
  ignore: ['notice', 'warning'],
  includeNotices: false,
  includeWarnings: false,
  reporter: 'json',
  level: 'error'
};

// Routes
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    service: 'pa11y-accessibility-service'
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Test single URL
app.post('/test', async (req, res) => {
  try {
    const { url, options = {} } = req.body;
    
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }
    
    const testId = uuidv4();
    const startTime = Date.now();
    
    logger.info(`Starting Pa11y test for URL: ${url}`, { testId });
    
    // Merge custom options with default config
    const testConfig = { ...pa11yConfig, ...options };
    
    // Run Pa11y test
    const results = await pa11y(url, testConfig);
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    
    // Process results
    const processedResults = {
      testId,
      url,
      timestamp: new Date().toISOString(),
      duration,
      totalIssues: results.issues.length,
      issues: results.issues.map(issue => ({
        code: issue.code,
        type: issue.type,
        typeCode: issue.typeCode,
        message: issue.message,
        context: issue.context,
        selector: issue.selector,
        runner: issue.runner,
        runnerExtras: issue.runnerExtras
      })),
      summary: {
        errors: results.issues.filter(i => i.type === 'error').length,
        warnings: results.issues.filter(i => i.type === 'warning').length,
        notices: results.issues.filter(i => i.type === 'notice').length
      },
      pageTitle: results.pageTitle || 'Unknown',
      documentTitle: results.documentTitle || 'Unknown'
    };
    
    // Update metrics
    accessibilityTests.labels('pa11y', 'completed').inc();
    results.issues.forEach(issue => {
      accessibilityViolations.labels(issue.code, issue.type).inc();
    });
    
    // Store results in MongoDB
    if (db) {
      await db.collection('pa11y_results').insertOne(processedResults);
    }
    
    // Cache results in Redis for 1 hour
    const cacheKey = `pa11y:${Buffer.from(url).toString('base64')}`;
    await redisClient.setEx(cacheKey, 3600, JSON.stringify(processedResults));
    
    logger.info(`Pa11y test completed for URL: ${url}`, { 
      testId, 
      duration, 
      totalIssues: results.issues.length 
    });
    
    res.json(processedResults);
  } catch (error) {
    logger.error('Pa11y test error:', error);
    accessibilityTests.labels('pa11y', 'failed').inc();
    res.status(500).json({ 
      error: 'Accessibility test failed', 
      message: error.message 
    });
  }
});

// Test multiple URLs
app.post('/test/batch', async (req, res) => {
  try {
    const { urls, options = {} } = req.body;
    
    if (!urls || !Array.isArray(urls) || urls.length === 0) {
      return res.status(400).json({ error: 'URLs array is required' });
    }
    
    const batchId = uuidv4();
    const startTime = Date.now();
    
    logger.info(`Starting Pa11y batch test for ${urls.length} URLs`, { batchId });
    
    const results = [];
    
    // Process URLs in parallel (with concurrency limit)
    const concurrency = 3;
    for (let i = 0; i < urls.length; i += concurrency) {
      const batch = urls.slice(i, i + concurrency);
      const batchPromises = batch.map(async (url) => {
        try {
          const testConfig = { ...pa11yConfig, ...options };
          const result = await pa11y(url, testConfig);
          
          const processedResult = {
            url,
            timestamp: new Date().toISOString(),
            totalIssues: result.issues.length,
            issues: result.issues,
            summary: {
              errors: result.issues.filter(i => i.type === 'error').length,
              warnings: result.issues.filter(i => i.type === 'warning').length,
              notices: result.issues.filter(i => i.type === 'notice').length
            },
            pageTitle: result.pageTitle || 'Unknown'
          };
          
          // Update metrics
          accessibilityTests.labels('pa11y', 'completed').inc();
          result.issues.forEach(issue => {
            accessibilityViolations.labels(issue.code, issue.type).inc();
          });
          
          return processedResult;
        } catch (error) {
          logger.error(`Pa11y test failed for URL: ${url}`, error);
          accessibilityTests.labels('pa11y', 'failed').inc();
          return {
            url,
            error: error.message,
            timestamp: new Date().toISOString()
          };
        }
      });
      
      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults);
    }
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    
    const batchResults = {
      batchId,
      timestamp: new Date().toISOString(),
      duration,
      totalUrls: urls.length,
      completedTests: results.filter(r => !r.error).length,
      failedTests: results.filter(r => r.error).length,
      results,
      summary: {
        totalIssues: results.reduce((sum, r) => sum + (r.totalIssues || 0), 0),
        totalErrors: results.reduce((sum, r) => sum + (r.summary?.errors || 0), 0),
        totalWarnings: results.reduce((sum, r) => sum + (r.summary?.warnings || 0), 0),
        totalNotices: results.reduce((sum, r) => sum + (r.summary?.notices || 0), 0)
      }
    };
    
    // Store batch results in MongoDB
    if (db) {
      await db.collection('pa11y_batch_results').insertOne(batchResults);
    }
    
    logger.info(`Pa11y batch test completed`, { 
      batchId, 
      duration, 
      totalUrls: urls.length,
      completedTests: batchResults.completedTests,
      failedTests: batchResults.failedTests
    });
    
    res.json(batchResults);
  } catch (error) {
    logger.error('Pa11y batch test error:', error);
    res.status(500).json({ 
      error: 'Batch accessibility test failed', 
      message: error.message 
    });
  }
});

// Get test results
app.get('/results/:testId', async (req, res) => {
  try {
    const { testId } = req.params;
    
    if (db) {
      const result = await db.collection('pa11y_results').findOne({ testId });
      if (result) {
        return res.json(result);
      }
    }
    
    res.status(404).json({ error: 'Test results not found' });
  } catch (error) {
    logger.error('Get results error:', error);
    res.status(500).json({ error: 'Failed to retrieve results' });
  }
});

// Get all results with pagination
app.get('/results', async (req, res) => {
  try {
    const { page = 1, limit = 10, url } = req.query;
    const skip = (page - 1) * limit;
    
    if (db) {
      const query = url ? { url: new RegExp(url, 'i') } : {};
      const results = await db.collection('pa11y_results')
        .find(query)
        .sort({ timestamp: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .toArray();
      
      const total = await db.collection('pa11y_results').countDocuments(query);
      
      res.json({
        results,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          pages: Math.ceil(total / limit)
        }
      });
    } else {
      res.json({ results: [], pagination: { page: 1, limit: 10, total: 0, pages: 0 } });
    }
  } catch (error) {
    logger.error('Get results error:', error);
    res.status(500).json({ error: 'Failed to retrieve results' });
  }
});

// Get statistics
app.get('/stats', async (req, res) => {
  try {
    if (db) {
      const stats = await db.collection('pa11y_results').aggregate([
        {
          $group: {
            _id: null,
            totalTests: { $sum: 1 },
            totalIssues: { $sum: '$totalIssues' },
            avgIssuesPerTest: { $avg: '$totalIssues' },
            totalErrors: { $sum: '$summary.errors' },
            totalWarnings: { $sum: '$summary.warnings' },
            totalNotices: { $sum: '$summary.notices' }
          }
        }
      ]).toArray();
      
      const recentTests = await db.collection('pa11y_results')
        .find({})
        .sort({ timestamp: -1 })
        .limit(5)
        .toArray();
      
      res.json({
        statistics: stats[0] || {
          totalTests: 0,
          totalIssues: 0,
          avgIssuesPerTest: 0,
          totalErrors: 0,
          totalWarnings: 0,
          totalNotices: 0
        },
        recentTests: recentTests.map(test => ({
          testId: test.testId,
          url: test.url,
          timestamp: test.timestamp,
          totalIssues: test.totalIssues,
          summary: test.summary
        }))
      });
    } else {
      res.json({
        statistics: {
          totalTests: 0,
          totalIssues: 0,
          avgIssuesPerTest: 0,
          totalErrors: 0,
          totalWarnings: 0,
          totalNotices: 0
        },
        recentTests: []
      });
    }
  } catch (error) {
    logger.error('Get stats error:', error);
    res.status(500).json({ error: 'Failed to retrieve statistics' });
  }
});

// Scheduled cleanup of old results (keep last 30 days)
cron.schedule('0 2 * * *', async () => {
  try {
    if (db) {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      const result = await db.collection('pa11y_results').deleteMany({
        timestamp: { $lt: thirtyDaysAgo.toISOString() }
      });
      logger.info(`Cleaned up ${result.deletedCount} old Pa11y results`);
    }
  } catch (error) {
    logger.error('Cleanup error:', error);
  }
});

// Start server
async function startServer() {
  try {
    // Connect to Redis
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    // Connect to MongoDB
    mongoClient = new MongoClient(process.env.MONGODB_URL || 'mongodb://localhost:27017/pa11y');
    await mongoClient.connect();
    db = mongoClient.db();
    logger.info('Connected to MongoDB');
    
    // Create indexes
    await db.collection('pa11y_results').createIndex({ testId: 1 });
    await db.collection('pa11y_results').createIndex({ url: 1 });
    await db.collection('pa11y_results').createIndex({ timestamp: -1 });
    
    app.listen(port, () => {
      logger.info(`Pa11y Accessibility Service running on port ${port}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('Shutting down Pa11y service...');
  if (mongoClient) {
    await mongoClient.close();
  }
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

startServer();
