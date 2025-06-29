const express = require('express');
const axios = require('axios');
const redis = require('redis');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');
const cron = require('node-cron');
const cc = require('currency-codes');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const currencyRequests = new promClient.Counter({
  name: 'currency_requests_total',
  help: 'Total number of currency requests',
  labelNames: ['from_currency', 'to_currency']
});
const exchangeRateUpdates = new promClient.Counter({
  name: 'exchange_rate_updates_total',
  help: 'Total number of exchange rate updates'
});
register.registerMetric(httpRequestDuration);
register.registerMetric(currencyRequests);
register.registerMetric(exchangeRateUpdates);

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
const baseCurrency = process.env.BASE_CURRENCY || 'USD';

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

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

// Exchange rate providers (free APIs)
const exchangeRateProviders = [
  {
    name: 'exchangerate-api',
    url: `https://api.exchangerate-api.com/v4/latest/${baseCurrency}`,
    transform: (data) => data.rates
  },
  {
    name: 'fixer',
    url: `https://api.fixer.io/latest?base=${baseCurrency}`,
    transform: (data) => data.rates
  }
];

// Fetch exchange rates
async function fetchExchangeRates() {
  try {
    logger.info('Fetching exchange rates...');
    
    for (const provider of exchangeRateProviders) {
      try {
        const response = await axios.get(provider.url, { timeout: 10000 });
        const rates = provider.transform(response.data);
        
        if (rates && Object.keys(rates).length > 0) {
          // Store rates in Redis with 1-hour expiration
          await redisClient.setEx('exchange_rates', 3600, JSON.stringify({
            base: baseCurrency,
            rates,
            timestamp: new Date().toISOString(),
            provider: provider.name
          }));
          
          exchangeRateUpdates.inc();
          logger.info(`Exchange rates updated from ${provider.name}`);
          return;
        }
      } catch (error) {
        logger.warn(`Failed to fetch from ${provider.name}:`, error.message);
      }
    }
    
    logger.error('All exchange rate providers failed');
  } catch (error) {
    logger.error('Exchange rate fetch error:', error);
  }
}

// Get currency info
function getCurrencyInfo(code) {
  const currency = cc.code(code);
  return currency ? {
    code: currency.code,
    name: currency.currency,
    symbol: currency.symbol || code,
    decimal_digits: currency.digits || 2
  } : null;
}

// Routes
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/rates', async (req, res) => {
  try {
    const cached = await redisClient.get('exchange_rates');
    
    if (cached) {
      const data = JSON.parse(cached);
      res.json(data);
    } else {
      res.status(503).json({ error: 'Exchange rates not available' });
    }
  } catch (error) {
    logger.error('Rates fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch rates' });
  }
});

app.get('/convert', async (req, res) => {
  try {
    const { from, to, amount = 1 } = req.query;
    
    if (!from || !to) {
      return res.status(400).json({ error: 'Missing from or to currency' });
    }
    
    currencyRequests.labels(from, to).inc();
    
    const cached = await redisClient.get('exchange_rates');
    
    if (!cached) {
      return res.status(503).json({ error: 'Exchange rates not available' });
    }
    
    const data = JSON.parse(cached);
    const { rates, base } = data;
    
    let fromRate = 1;
    let toRate = 1;
    
    if (from !== base) {
      fromRate = rates[from];
      if (!fromRate) {
        return res.status(400).json({ error: `Currency ${from} not supported` });
      }
    }
    
    if (to !== base) {
      toRate = rates[to];
      if (!toRate) {
        return res.status(400).json({ error: `Currency ${to} not supported` });
      }
    }
    
    const convertedAmount = (amount / fromRate) * toRate;
    
    res.json({
      from: {
        currency: from,
        amount: parseFloat(amount),
        info: getCurrencyInfo(from)
      },
      to: {
        currency: to,
        amount: parseFloat(convertedAmount.toFixed(4)),
        info: getCurrencyInfo(to)
      },
      rate: parseFloat((toRate / fromRate).toFixed(6)),
      timestamp: data.timestamp
    });
  } catch (error) {
    logger.error('Conversion error:', error);
    res.status(500).json({ error: 'Conversion failed' });
  }
});

app.get('/currencies', async (req, res) => {
  try {
    const cached = await redisClient.get('exchange_rates');
    
    if (!cached) {
      return res.status(503).json({ error: 'Exchange rates not available' });
    }
    
    const data = JSON.parse(cached);
    const currencies = Object.keys(data.rates).map(code => ({
      code,
      ...getCurrencyInfo(code)
    }));
    
    // Add base currency
    currencies.unshift({
      code: data.base,
      ...getCurrencyInfo(data.base)
    });
    
    res.json({ currencies });
  } catch (error) {
    logger.error('Currencies fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch currencies' });
  }
});

app.get('/currency/:code', (req, res) => {
  try {
    const { code } = req.params;
    const info = getCurrencyInfo(code.toUpperCase());
    
    if (info) {
      res.json(info);
    } else {
      res.status(404).json({ error: 'Currency not found' });
    }
  } catch (error) {
    logger.error('Currency info error:', error);
    res.status(500).json({ error: 'Failed to fetch currency info' });
  }
});

// Schedule exchange rate updates every hour
cron.schedule('0 * * * *', fetchExchangeRates);

// Start server
async function startServer() {
  try {
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    // Initial exchange rate fetch
    await fetchExchangeRates();
    
    app.listen(port, () => {
      logger.info(`Currency Service running on port ${port}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
