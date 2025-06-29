const express = require('express');
const cors = require('cors');
const axios = require('axios');
const Redis = require('redis');
const { Pool } = require('pg');
const winston = require('winston');
const lighthouse = require('lighthouse');
const puppeteer = require('puppeteer');
const client = require('prom-client');

const app = express();
const port = 3003;

// Configure logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'perf-monitor.log' })
  ]
});

// Database connection
const db = new Pool({
  connectionString: process.env.POSTGRES_URL
});

// Redis connection
const redis = Redis.createClient({
  url: process.env.REDIS_URL
});
redis.connect();

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const performanceMetrics = new client.Gauge({
  name: 'frontend_performance_score',
  help: 'Frontend performance scores',
  labelNames: ['metric_type', 'page'],
  registers: [register]
});

const webVitalsMetrics = new client.Gauge({
  name: 'web_vitals',
  help: 'Core Web Vitals metrics',
  labelNames: ['metric', 'page'],
  registers: [register]
});

// Middleware
app.use(cors());
app.use(express.json());

// Performance monitoring endpoint
app.post('/monitor', async (req, res) => {
  try {
    const { url, pages = ['/'], options = {} } = req.body;
    
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }
    
    const results = [];
    
    for (const page of pages) {
      const pageUrl = `${url}${page}`;
      logger.info(`Monitoring performance for: ${pageUrl}`);
      
      const result = await runPerformanceAudit(pageUrl, options);
      results.push({
        page,
        url: pageUrl,
        ...result
      });
      
      // Store results in database
      await storePerformanceResults(pageUrl, result);
      
      // Update Prometheus metrics
      updateMetrics(page, result);
    }
    
    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      results
    });
  } catch (error) {
    logger.error('Performance monitoring failed', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Run Lighthouse audit
async function runPerformanceAudit(url, options = {}) {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  try {
    const { lhr } = await lighthouse(url, {
      port: new URL(browser.wsEndpoint()).port,
      output: 'json',
      logLevel: 'info',
      ...options
    });
    
    const categories = lhr.categories;
    const audits = lhr.audits;
    
    // Extract key metrics
    const metrics = {
      performance: Math.round(categories.performance.score * 100),
      accessibility: Math.round(categories.accessibility.score * 100),
      bestPractices: Math.round(categories['best-practices'].score * 100),
      seo: Math.round(categories.seo.score * 100),
      pwa: categories.pwa ? Math.round(categories.pwa.score * 100) : null,
      
      // Core Web Vitals
      fcp: audits['first-contentful-paint']?.numericValue || 0,
      lcp: audits['largest-contentful-paint']?.numericValue || 0,
      fid: audits['max-potential-fid']?.numericValue || 0,
      cls: audits['cumulative-layout-shift']?.numericValue || 0,
      
      // Other important metrics
      tti: audits['interactive']?.numericValue || 0,
      tbt: audits['total-blocking-time']?.numericValue || 0,
      si: audits['speed-index']?.numericValue || 0,
      
      // Resource metrics
      totalByteWeight: audits['total-byte-weight']?.numericValue || 0,
      unusedCssRules: audits['unused-css-rules']?.details?.overallSavingsBytes || 0,
      unusedJavaScript: audits['unused-javascript']?.details?.overallSavingsBytes || 0,
      
      // Image optimization
      modernImageFormats: audits['modern-image-formats']?.details?.overallSavingsBytes || 0,
      efficientAnimatedContent: audits['efficient-animated-content']?.details?.overallSavingsBytes || 0,
      
      // Caching
      usesLongCacheTtl: audits['uses-long-cache-ttl']?.score || 0,
      
      // Compression
      usesTextCompression: audits['uses-text-compression']?.score || 0,
      
      // Critical resources
      criticalRequestChains: audits['critical-request-chains']?.details?.longestChain?.length || 0,
      
      // Accessibility details
      colorContrast: audits['color-contrast']?.score || 0,
      imageAlt: audits['image-alt']?.score || 0,
      
      // SEO details
      metaDescription: audits['meta-description']?.score || 0,
      documentTitle: audits['document-title']?.score || 0
    };
    
    return {
      lighthouse: metrics,
      timestamp: new Date().toISOString(),
      fullReport: lhr
    };
  } finally {
    await browser.close();
  }
}

// Store performance results in database
async function storePerformanceResults(url, results) {
  const client = await db.connect();
  
  try {
    await client.query('BEGIN');
    
    // Insert performance audit
    const auditResult = await client.query(
      `INSERT INTO performance_audits (url, performance_score, accessibility_score, 
       best_practices_score, seo_score, pwa_score, fcp, lcp, fid, cls, tti, tbt, si,
       total_byte_weight, unused_css, unused_js, audit_data, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, NOW())
       RETURNING id`,
      [
        url,
        results.lighthouse.performance,
        results.lighthouse.accessibility,
        results.lighthouse.bestPractices,
        results.lighthouse.seo,
        results.lighthouse.pwa,
        results.lighthouse.fcp,
        results.lighthouse.lcp,
        results.lighthouse.fid,
        results.lighthouse.cls,
        results.lighthouse.tti,
        results.lighthouse.tbt,
        results.lighthouse.si,
        results.lighthouse.totalByteWeight,
        results.lighthouse.unusedCssRules,
        results.lighthouse.unusedJavaScript,
        JSON.stringify(results.fullReport)
      ]
    );
    
    await client.query('COMMIT');
    
    // Cache recent results
    const cacheKey = `perf:${url}:latest`;
    await redis.setEx(cacheKey, 3600, JSON.stringify(results));
    
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Update Prometheus metrics
function updateMetrics(page, results) {
  const metrics = results.lighthouse;
  
  // Performance scores
  performanceMetrics.set({ metric_type: 'performance', page }, metrics.performance);
  performanceMetrics.set({ metric_type: 'accessibility', page }, metrics.accessibility);
  performanceMetrics.set({ metric_type: 'best_practices', page }, metrics.bestPractices);
  performanceMetrics.set({ metric_type: 'seo', page }, metrics.seo);
  
  if (metrics.pwa !== null) {
    performanceMetrics.set({ metric_type: 'pwa', page }, metrics.pwa);
  }
  
  // Core Web Vitals
  webVitalsMetrics.set({ metric: 'fcp', page }, metrics.fcp);
  webVitalsMetrics.set({ metric: 'lcp', page }, metrics.lcp);
  webVitalsMetrics.set({ metric: 'fid', page }, metrics.fid);
  webVitalsMetrics.set({ metric: 'cls', page }, metrics.cls);
  webVitalsMetrics.set({ metric: 'tti', page }, metrics.tti);
  webVitalsMetrics.set({ metric: 'tbt', page }, metrics.tbt);
  webVitalsMetrics.set({ metric: 'si', page }, metrics.si);
}

// Get performance history
app.get('/history/:url', async (req, res) => {
  try {
    const { url } = req.params;
    const { limit = 50, days = 30 } = req.query;
    
    const decodedUrl = decodeURIComponent(url);
    
    const result = await db.query(
      `SELECT * FROM performance_audits 
       WHERE url = $1 AND created_at >= NOW() - INTERVAL '${days} days'
       ORDER BY created_at DESC 
       LIMIT $2`,
      [decodedUrl, limit]
    );
    
    res.json({
      success: true,
      url: decodedUrl,
      history: result.rows
    });
  } catch (error) {
    logger.error('Failed to get performance history', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Get performance trends
app.get('/trends', async (req, res) => {
  try {
    const { days = 30 } = req.query;
    
    const result = await db.query(
      `SELECT 
         DATE(created_at) as date,
         AVG(performance_score) as avg_performance,
         AVG(accessibility_score) as avg_accessibility,
         AVG(best_practices_score) as avg_best_practices,
         AVG(seo_score) as avg_seo,
         AVG(fcp) as avg_fcp,
         AVG(lcp) as avg_lcp,
         AVG(cls) as avg_cls,
         COUNT(*) as audit_count
       FROM performance_audits 
       WHERE created_at >= NOW() - INTERVAL '${days} days'
       GROUP BY DATE(created_at)
       ORDER BY date DESC`
    );
    
    res.json({
      success: true,
      trends: result.rows
    });
  } catch (error) {
    logger.error('Failed to get performance trends', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Real User Monitoring endpoint
app.post('/rum', async (req, res) => {
  try {
    const { metrics, page, userAgent, connection } = req.body;
    
    // Store RUM data
    await db.query(
      `INSERT INTO rum_metrics (page, fcp, lcp, fid, cls, ttfb, user_agent, connection_type, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
      [
        page,
        metrics.fcp || null,
        metrics.lcp || null,
        metrics.fid || null,
        metrics.cls || null,
        metrics.ttfb || null,
        userAgent,
        connection?.effectiveType || null
      ]
    );
    
    res.json({ success: true });
  } catch (error) {
    logger.error('Failed to store RUM data', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Performance budget check
app.post('/budget-check', async (req, res) => {
  try {
    const { url, budgets } = req.body;
    
    // Get latest performance data
    const cacheKey = `perf:${url}:latest`;
    const cachedData = await redis.get(cacheKey);
    
    if (!cachedData) {
      return res.status(404).json({ error: 'No recent performance data found' });
    }
    
    const perfData = JSON.parse(cachedData);
    const violations = [];
    
    // Check budgets
    for (const [metric, budget] of Object.entries(budgets)) {
      const actualValue = perfData.lighthouse[metric];
      
      if (actualValue !== undefined) {
        if (metric.includes('score') && actualValue < budget) {
          violations.push({
            metric,
            actual: actualValue,
            budget,
            violation: `${metric} score ${actualValue} is below budget ${budget}`
          });
        } else if (!metric.includes('score') && actualValue > budget) {
          violations.push({
            metric,
            actual: actualValue,
            budget,
            violation: `${metric} ${actualValue}ms exceeds budget ${budget}ms`
          });
        }
      }
    }
    
    res.json({
      success: true,
      url,
      budgetsMet: violations.length === 0,
      violations,
      metrics: perfData.lighthouse
    });
  } catch (error) {
    logger.error('Budget check failed', { error: error.message });
    res.status(500).json({ error: error.message });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Start server
app.listen(port, '0.0.0.0', () => {
  logger.info(`Frontend Performance Monitor listening on port ${port}`);
});
