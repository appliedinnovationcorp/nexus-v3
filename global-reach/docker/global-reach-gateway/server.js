const express = require('express');
const axios = require('axios');
const redis = require('redis');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');
const rateLimit = require('express-rate-limit');
const geoip = require('geoip-lite');
const acceptLanguage = require('accept-language-parser');
const moment = require('moment-timezone');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const globalRequests = new promClient.Counter({
  name: 'global_requests_total',
  help: 'Total number of global requests',
  labelNames: ['country', 'language', 'service']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(globalRequests);

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
const port = process.env.PORT || 3000;

// Service URLs
const services = {
  i18n: process.env.I18N_SERVICE_URL || 'http://localhost:3500',
  currency: process.env.CURRENCY_SERVICE_URL || 'http://localhost:3501',
  timezone: process.env.TIMEZONE_SERVICE_URL || 'http://localhost:3502',
  rtl: process.env.RTL_SERVICE_URL || 'http://localhost:3503',
  localization: process.env.LOCALIZATION_SERVICE_URL || 'http://localhost:3504',
  cdn: process.env.CDN_OPTIMIZER_URL || 'http://localhost:3505'
};

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.on('error', (err) => {
  logger.error('Redis Client Error', err);
});

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // limit each IP to 1000 requests per windowMs
  message: 'Too many requests from this IP'
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());
app.use(limiter);

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

// Global context middleware
app.use(async (req, res, next) => {
  try {
    // Get client IP
    const clientIP = req.headers['x-forwarded-for'] || 
                    req.headers['x-real-ip'] || 
                    req.connection.remoteAddress || 
                    req.socket.remoteAddress ||
                    (req.connection.socket ? req.connection.socket.remoteAddress : null);
    
    // Get geo information
    const geo = geoip.lookup(clientIP) || {};
    
    // Parse Accept-Language header
    const languages = acceptLanguage.parse(req.headers['accept-language'] || 'en');
    const preferredLanguage = languages[0]?.code || 'en';
    
    // Detect timezone
    const timezone = req.headers['x-user-timezone'] || 
                    geo.timezone || 
                    'UTC';
    
    // Detect currency preference
    const currencyMap = {
      'US': 'USD', 'GB': 'GBP', 'EU': 'EUR', 'JP': 'JPY',
      'CA': 'CAD', 'AU': 'AUD', 'CH': 'CHF', 'CN': 'CNY',
      'IN': 'INR', 'BR': 'BRL', 'MX': 'MXN', 'KR': 'KRW'
    };
    const preferredCurrency = req.headers['x-user-currency'] || 
                             currencyMap[geo.country] || 
                             'USD';
    
    // Check if RTL language
    const rtlLanguages = ['ar', 'he', 'fa', 'ur', 'ku', 'sd'];
    const isRTL = rtlLanguages.includes(preferredLanguage);
    
    // Store global context
    req.globalContext = {
      ip: clientIP,
      country: geo.country || 'Unknown',
      region: geo.region || 'Unknown',
      city: geo.city || 'Unknown',
      timezone,
      language: preferredLanguage,
      languages: languages.map(l => l.code),
      currency: preferredCurrency,
      isRTL,
      userAgent: req.headers['user-agent'] || '',
      timestamp: new Date().toISOString()
    };
    
    // Add global headers to response
    res.set({
      'X-Global-Country': req.globalContext.country,
      'X-Global-Language': req.globalContext.language,
      'X-Global-Currency': req.globalContext.currency,
      'X-Global-Timezone': req.globalContext.timezone,
      'X-Global-RTL': req.globalContext.isRTL.toString()
    });
    
    next();
  } catch (error) {
    logger.error('Global context middleware error:', error);
    next();
  }
});

// Routes
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    services: Object.keys(services)
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Global context endpoint
app.get('/api/global/context', (req, res) => {
  globalRequests.labels(
    req.globalContext.country,
    req.globalContext.language,
    'context'
  ).inc();
  
  res.json(req.globalContext);
});

// Translation proxy
app.get('/api/global/translate/:key', async (req, res) => {
  try {
    const { key } = req.params;
    const { lng, ns } = req.query;
    
    globalRequests.labels(
      req.globalContext.country,
      req.globalContext.language,
      'translate'
    ).inc();
    
    const response = await axios.get(`${services.i18n}/translate/${key}`, {
      params: { 
        lng: lng || req.globalContext.language, 
        ns: ns || 'common' 
      }
    });
    
    res.json(response.data);
  } catch (error) {
    logger.error('Translation proxy error:', error);
    res.status(500).json({ error: 'Translation failed' });
  }
});

// Currency conversion proxy
app.get('/api/global/convert', async (req, res) => {
  try {
    const { from, to, amount } = req.query;
    
    globalRequests.labels(
      req.globalContext.country,
      req.globalContext.language,
      'currency'
    ).inc();
    
    const response = await axios.get(`${services.currency}/convert`, {
      params: { 
        from: from || req.globalContext.currency,
        to: to || 'USD',
        amount: amount || 1
      }
    });
    
    res.json(response.data);
  } catch (error) {
    logger.error('Currency conversion proxy error:', error);
    res.status(500).json({ error: 'Currency conversion failed' });
  }
});

// Timezone conversion
app.get('/api/global/time', (req, res) => {
  try {
    const { timezone, format } = req.query;
    const tz = timezone || req.globalContext.timezone;
    const fmt = format || 'YYYY-MM-DD HH:mm:ss';
    
    globalRequests.labels(
      req.globalContext.country,
      req.globalContext.language,
      'timezone'
    ).inc();
    
    const now = moment().tz(tz);
    
    res.json({
      timezone: tz,
      time: now.format(fmt),
      utc: moment().utc().format(fmt),
      offset: now.format('Z'),
      timestamp: now.valueOf()
    });
  } catch (error) {
    logger.error('Timezone conversion error:', error);
    res.status(500).json({ error: 'Timezone conversion failed' });
  }
});

// Localized content
app.get('/api/global/content/:type', async (req, res) => {
  try {
    const { type } = req.params;
    
    globalRequests.labels(
      req.globalContext.country,
      req.globalContext.language,
      'content'
    ).inc();
    
    // Get localized content based on user context
    const cacheKey = `content:${type}:${req.globalContext.language}:${req.globalContext.country}`;
    const cached = await redisClient.get(cacheKey);
    
    if (cached) {
      return res.json(JSON.parse(cached));
    }
    
    // Generate localized content
    const content = {
      type,
      language: req.globalContext.language,
      country: req.globalContext.country,
      currency: req.globalContext.currency,
      timezone: req.globalContext.timezone,
      isRTL: req.globalContext.isRTL,
      dateFormat: getDateFormat(req.globalContext.country),
      numberFormat: getNumberFormat(req.globalContext.country),
      timestamp: new Date().toISOString()
    };
    
    // Cache for 1 hour
    await redisClient.setEx(cacheKey, 3600, JSON.stringify(content));
    
    res.json(content);
  } catch (error) {
    logger.error('Localized content error:', error);
    res.status(500).json({ error: 'Failed to get localized content' });
  }
});

// Global analytics
app.post('/api/global/analytics', async (req, res) => {
  try {
    const { event, data } = req.body;
    
    const analyticsData = {
      event,
      data,
      context: req.globalContext,
      timestamp: new Date().toISOString()
    };
    
    // Store in Redis for analytics processing
    await redisClient.lPush('global_analytics', JSON.stringify(analyticsData));
    
    res.json({ status: 'recorded' });
  } catch (error) {
    logger.error('Analytics error:', error);
    res.status(500).json({ error: 'Analytics recording failed' });
  }
});

// Helper functions
function getDateFormat(country) {
  const formats = {
    'US': 'MM/DD/YYYY',
    'GB': 'DD/MM/YYYY',
    'DE': 'DD.MM.YYYY',
    'FR': 'DD/MM/YYYY',
    'JP': 'YYYY/MM/DD',
    'CN': 'YYYY-MM-DD'
  };
  return formats[country] || 'YYYY-MM-DD';
}

function getNumberFormat(country) {
  const formats = {
    'US': { decimal: '.', thousands: ',' },
    'GB': { decimal: '.', thousands: ',' },
    'DE': { decimal: ',', thousands: '.' },
    'FR': { decimal: ',', thousands: ' ' },
    'JP': { decimal: '.', thousands: ',' },
    'CN': { decimal: '.', thousands: ',' }
  };
  return formats[country] || { decimal: '.', thousands: ',' };
}

// Start server
async function startServer() {
  try {
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    app.listen(port, () => {
      logger.info(`Global Reach Gateway running on port ${port}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
