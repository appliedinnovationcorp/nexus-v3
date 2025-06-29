const express = require('express');
const { z } = require('zod');
const yup = require('yup');
const Joi = require('joi');
const redis = require('redis');
const { MongoClient } = require('mongodb');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const validator = require('validator');
const _ = require('lodash');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'validation_request_duration_seconds',
  help: 'Duration of validation requests in seconds',
  labelNames: ['method', 'route', 'status_code', 'validation_engine'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const validationRequests = new promClient.Counter({
  name: 'validation_requests_total',
  help: 'Total number of validation requests',
  labelNames: ['validation_engine', 'schema_name', 'status']
});
const validationErrors = new promClient.Counter({
  name: 'validation_errors_total',
  help: 'Total number of validation errors',
  labelNames: ['validation_engine', 'schema_name', 'error_type']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(validationRequests);
register.registerMetric(validationErrors);

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
const port = process.env.PORT || 5000;

// Redis client
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

// MongoDB client
let mongoClient;
let db;

// AJV instance
const ajv = new Ajv({ allErrors: true });
addFormats(ajv);

redisClient.on('error', (err) => {
  logger.error('Redis Client Error', err);
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode, req.validationEngine || 'unknown')
      .observe(duration);
  });
  next();
});

// Zod Schemas
const zodSchemas = {
  user: z.object({
    id: z.string().uuid().optional(),
    firstName: z.string().min(1).max(50),
    lastName: z.string().min(1).max(50),
    email: z.string().email(),
    phone: z.string().regex(/^\+?[1-9]\d{1,14}$/),
    age: z.number().int().min(13).max(120),
    address: z.object({
      street: z.string().min(1),
      city: z.string().min(1),
      state: z.string().min(2).max(2),
      zipCode: z.string().regex(/^\d{5}(-\d{4})?$/),
      country: z.string().min(2).max(2)
    }),
    preferences: z.object({
      newsletter: z.boolean(),
      notifications: z.boolean(),
      marketing: z.boolean()
    }).optional(),
    createdAt: z.string().datetime().optional(),
    updatedAt: z.string().datetime().optional()
  }),
  
  product: z.object({
    id: z.string().uuid().optional(),
    name: z.string().min(1).max(200),
    description: z.string().max(2000),
    price: z.number().positive(),
    currency: z.string().length(3),
    category: z.string().min(1),
    tags: z.array(z.string()).optional(),
    inventory: z.object({
      quantity: z.number().int().min(0),
      reserved: z.number().int().min(0).optional(),
      available: z.number().int().min(0).optional()
    }),
    dimensions: z.object({
      length: z.number().positive(),
      width: z.number().positive(),
      height: z.number().positive(),
      weight: z.number().positive()
    }).optional(),
    images: z.array(z.string().url()).optional(),
    active: z.boolean().default(true),
    createdAt: z.string().datetime().optional(),
    updatedAt: z.string().datetime().optional()
  }),
  
  order: z.object({
    id: z.string().uuid().optional(),
    userId: z.string().uuid(),
    items: z.array(z.object({
      productId: z.string().uuid(),
      quantity: z.number().int().positive(),
      price: z.number().positive(),
      currency: z.string().length(3)
    })).min(1),
    shipping: z.object({
      address: z.object({
        street: z.string().min(1),
        city: z.string().min(1),
        state: z.string().min(2).max(2),
        zipCode: z.string().regex(/^\d{5}(-\d{4})?$/),
        country: z.string().min(2).max(2)
      }),
      method: z.enum(['standard', 'express', 'overnight']),
      cost: z.number().min(0)
    }),
    payment: z.object({
      method: z.enum(['credit_card', 'debit_card', 'paypal', 'bank_transfer']),
      status: z.enum(['pending', 'completed', 'failed', 'refunded']),
      amount: z.number().positive(),
      currency: z.string().length(3)
    }),
    status: z.enum(['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled']),
    total: z.number().positive(),
    currency: z.string().length(3),
    createdAt: z.string().datetime().optional(),
    updatedAt: z.string().datetime().optional()
  })
};

// Yup Schemas
const yupSchemas = {
  user: yup.object({
    id: yup.string().uuid(),
    firstName: yup.string().required().min(1).max(50),
    lastName: yup.string().required().min(1).max(50),
    email: yup.string().required().email(),
    phone: yup.string().required().matches(/^\+?[1-9]\d{1,14}$/),
    age: yup.number().required().integer().min(13).max(120),
    address: yup.object({
      street: yup.string().required(),
      city: yup.string().required(),
      state: yup.string().required().length(2),
      zipCode: yup.string().required().matches(/^\d{5}(-\d{4})?$/),
      country: yup.string().required().length(2)
    }).required(),
    preferences: yup.object({
      newsletter: yup.boolean(),
      notifications: yup.boolean(),
      marketing: yup.boolean()
    }),
    createdAt: yup.string().datetime(),
    updatedAt: yup.string().datetime()
  }),
  
  product: yup.object({
    id: yup.string().uuid(),
    name: yup.string().required().min(1).max(200),
    description: yup.string().max(2000),
    price: yup.number().required().positive(),
    currency: yup.string().required().length(3),
    category: yup.string().required(),
    tags: yup.array().of(yup.string()),
    inventory: yup.object({
      quantity: yup.number().required().integer().min(0),
      reserved: yup.number().integer().min(0),
      available: yup.number().integer().min(0)
    }).required(),
    dimensions: yup.object({
      length: yup.number().positive(),
      width: yup.number().positive(),
      height: yup.number().positive(),
      weight: yup.number().positive()
    }),
    images: yup.array().of(yup.string().url()),
    active: yup.boolean().default(true),
    createdAt: yup.string().datetime(),
    updatedAt: yup.string().datetime()
  })
};

// Joi Schemas
const joiSchemas = {
  user: Joi.object({
    id: Joi.string().uuid(),
    firstName: Joi.string().min(1).max(50).required(),
    lastName: Joi.string().min(1).max(50).required(),
    email: Joi.string().email().required(),
    phone: Joi.string().pattern(/^\+?[1-9]\d{1,14}$/).required(),
    age: Joi.number().integer().min(13).max(120).required(),
    address: Joi.object({
      street: Joi.string().required(),
      city: Joi.string().required(),
      state: Joi.string().length(2).required(),
      zipCode: Joi.string().pattern(/^\d{5}(-\d{4})?$/).required(),
      country: Joi.string().length(2).required()
    }).required(),
    preferences: Joi.object({
      newsletter: Joi.boolean(),
      notifications: Joi.boolean(),
      marketing: Joi.boolean()
    }),
    createdAt: Joi.string().isoDate(),
    updatedAt: Joi.string().isoDate()
  })
};

// Validation functions
async function validateWithZod(data, schemaName) {
  const schema = zodSchemas[schemaName];
  if (!schema) {
    throw new Error(`Zod schema '${schemaName}' not found`);
  }
  
  try {
    const result = schema.parse(data);
    return { valid: true, data: result, errors: [] };
  } catch (error) {
    return {
      valid: false,
      data: null,
      errors: error.errors.map(err => ({
        path: err.path.join('.'),
        message: err.message,
        code: err.code
      }))
    };
  }
}

async function validateWithYup(data, schemaName) {
  const schema = yupSchemas[schemaName];
  if (!schema) {
    throw new Error(`Yup schema '${schemaName}' not found`);
  }
  
  try {
    const result = await schema.validate(data, { abortEarly: false });
    return { valid: true, data: result, errors: [] };
  } catch (error) {
    return {
      valid: false,
      data: null,
      errors: error.inner.map(err => ({
        path: err.path,
        message: err.message,
        value: err.value
      }))
    };
  }
}

async function validateWithJoi(data, schemaName) {
  const schema = joiSchemas[schemaName];
  if (!schema) {
    throw new Error(`Joi schema '${schemaName}' not found`);
  }
  
  const result = schema.validate(data, { abortEarly: false });
  
  if (result.error) {
    return {
      valid: false,
      data: null,
      errors: result.error.details.map(err => ({
        path: err.path.join('.'),
        message: err.message,
        value: err.value
      }))
    };
  }
  
  return { valid: true, data: result.value, errors: [] };
}

// Routes
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    service: 'data-validation-service'
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Validate single record
app.post('/validate', async (req, res) => {
  try {
    const { data, schema, engine = 'zod' } = req.body;
    
    if (!data || !schema) {
      return res.status(400).json({ 
        error: 'Missing required fields: data and schema' 
      });
    }
    
    req.validationEngine = engine;
    
    let result;
    const startTime = Date.now();
    
    // Check cache first
    const cacheKey = `validation:${engine}:${schema}:${JSON.stringify(data)}`;
    const cached = await redisClient.get(cacheKey);
    
    if (cached) {
      result = JSON.parse(cached);
      result.cached = true;
    } else {
      // Perform validation
      switch (engine) {
        case 'zod':
          result = await validateWithZod(data, schema);
          break;
        case 'yup':
          result = await validateWithYup(data, schema);
          break;
        case 'joi':
          result = await validateWithJoi(data, schema);
          break;
        default:
          return res.status(400).json({ 
            error: `Unsupported validation engine: ${engine}` 
          });
      }
      
      result.cached = false;
      
      // Cache result for 1 hour
      await redisClient.setEx(cacheKey, 3600, JSON.stringify(result));
    }
    
    const duration = Date.now() - startTime;
    
    // Update metrics
    validationRequests.labels(engine, schema, result.valid ? 'success' : 'failure').inc();
    
    if (!result.valid) {
      result.errors.forEach(error => {
        validationErrors.labels(engine, schema, error.code || 'validation_error').inc();
      });
    }
    
    // Store validation result in MongoDB
    if (db) {
      await db.collection('validation_results').insertOne({
        engine,
        schema,
        valid: result.valid,
        errorCount: result.errors.length,
        duration,
        timestamp: new Date(),
        cached: result.cached
      });
    }
    
    logger.info('Validation completed', {
      engine,
      schema,
      valid: result.valid,
      errorCount: result.errors.length,
      duration,
      cached: result.cached
    });
    
    res.json({
      ...result,
      engine,
      schema,
      duration,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    logger.error('Validation error:', error);
    validationRequests.labels(req.validationEngine || 'unknown', 'unknown', 'error').inc();
    res.status(500).json({ 
      error: 'Validation failed', 
      message: error.message 
    });
  }
});

// Validate batch of records
app.post('/validate/batch', async (req, res) => {
  try {
    const { data, schema, engine = 'zod', batchSize = 1000 } = req.body;
    
    if (!data || !Array.isArray(data) || !schema) {
      return res.status(400).json({ 
        error: 'Missing required fields: data (array) and schema' 
      });
    }
    
    req.validationEngine = engine;
    
    const startTime = Date.now();
    const results = [];
    const batchId = `batch_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    // Process in batches
    for (let i = 0; i < data.length; i += batchSize) {
      const batch = data.slice(i, i + batchSize);
      const batchResults = [];
      
      for (const record of batch) {
        try {
          let result;
          switch (engine) {
            case 'zod':
              result = await validateWithZod(record, schema);
              break;
            case 'yup':
              result = await validateWithYup(record, schema);
              break;
            case 'joi':
              result = await validateWithJoi(record, schema);
              break;
            default:
              throw new Error(`Unsupported validation engine: ${engine}`);
          }
          
          batchResults.push({
            index: i + batch.indexOf(record),
            ...result
          });
          
          // Update metrics
          validationRequests.labels(engine, schema, result.valid ? 'success' : 'failure').inc();
          
        } catch (error) {
          batchResults.push({
            index: i + batch.indexOf(record),
            valid: false,
            data: null,
            errors: [{ message: error.message }]
          });
          
          validationRequests.labels(engine, schema, 'error').inc();
        }
      }
      
      results.push(...batchResults);
    }
    
    const duration = Date.now() - startTime;
    const summary = {
      total: results.length,
      valid: results.filter(r => r.valid).length,
      invalid: results.filter(r => !r.valid).length,
      errorRate: (results.filter(r => !r.valid).length / results.length) * 100
    };
    
    // Store batch validation result in MongoDB
    if (db) {
      await db.collection('batch_validation_results').insertOne({
        batchId,
        engine,
        schema,
        summary,
        duration,
        timestamp: new Date()
      });
    }
    
    logger.info('Batch validation completed', {
      batchId,
      engine,
      schema,
      summary,
      duration
    });
    
    res.json({
      batchId,
      engine,
      schema,
      summary,
      results,
      duration,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    logger.error('Batch validation error:', error);
    res.status(500).json({ 
      error: 'Batch validation failed', 
      message: error.message 
    });
  }
});

// Get validation schemas
app.get('/schemas', (req, res) => {
  const { engine } = req.query;
  
  let schemas;
  switch (engine) {
    case 'zod':
      schemas = Object.keys(zodSchemas);
      break;
    case 'yup':
      schemas = Object.keys(yupSchemas);
      break;
    case 'joi':
      schemas = Object.keys(joiSchemas);
      break;
    default:
      schemas = {
        zod: Object.keys(zodSchemas),
        yup: Object.keys(yupSchemas),
        joi: Object.keys(joiSchemas)
      };
  }
  
  res.json({ schemas, engine: engine || 'all' });
});

// Get validation statistics
app.get('/stats', async (req, res) => {
  try {
    if (db) {
      const stats = await db.collection('validation_results').aggregate([
        {
          $group: {
            _id: { engine: '$engine', schema: '$schema' },
            totalValidations: { $sum: 1 },
            successfulValidations: { 
              $sum: { $cond: ['$valid', 1, 0] } 
            },
            failedValidations: { 
              $sum: { $cond: ['$valid', 0, 1] } 
            },
            avgDuration: { $avg: '$duration' },
            cacheHitRate: { 
              $avg: { $cond: ['$cached', 1, 0] } 
            }
          }
        },
        {
          $project: {
            engine: '$_id.engine',
            schema: '$_id.schema',
            totalValidations: 1,
            successfulValidations: 1,
            failedValidations: 1,
            successRate: { 
              $multiply: [
                { $divide: ['$successfulValidations', '$totalValidations'] }, 
                100
              ] 
            },
            avgDuration: { $round: ['$avgDuration', 2] },
            cacheHitRate: { 
              $multiply: ['$cacheHitRate', 100] 
            },
            _id: 0
          }
        }
      ]).toArray();
      
      res.json({ statistics: stats });
    } else {
      res.json({ statistics: [] });
    }
  } catch (error) {
    logger.error('Stats error:', error);
    res.status(500).json({ error: 'Failed to retrieve statistics' });
  }
});

// Custom validation rules
app.post('/validate/custom', async (req, res) => {
  try {
    const { data, rules } = req.body;
    
    if (!data || !rules) {
      return res.status(400).json({ 
        error: 'Missing required fields: data and rules' 
      });
    }
    
    const errors = [];
    
    // Apply custom validation rules
    for (const [field, rule] of Object.entries(rules)) {
      const value = _.get(data, field);
      
      if (rule.required && (value === undefined || value === null)) {
        errors.push({
          path: field,
          message: `${field} is required`,
          code: 'required'
        });
        continue;
      }
      
      if (value !== undefined && value !== null) {
        // Type validation
        if (rule.type && typeof value !== rule.type) {
          errors.push({
            path: field,
            message: `${field} must be of type ${rule.type}`,
            code: 'type'
          });
        }
        
        // String validations
        if (rule.type === 'string') {
          if (rule.minLength && value.length < rule.minLength) {
            errors.push({
              path: field,
              message: `${field} must be at least ${rule.minLength} characters`,
              code: 'minLength'
            });
          }
          
          if (rule.maxLength && value.length > rule.maxLength) {
            errors.push({
              path: field,
              message: `${field} must be at most ${rule.maxLength} characters`,
              code: 'maxLength'
            });
          }
          
          if (rule.pattern && !new RegExp(rule.pattern).test(value)) {
            errors.push({
              path: field,
              message: rule.message || `${field} format is invalid`,
              code: 'pattern'
            });
          }
          
          if (rule.email && !validator.isEmail(value)) {
            errors.push({
              path: field,
              message: `${field} must be a valid email`,
              code: 'email'
            });
          }
        }
        
        // Number validations
        if (rule.type === 'number') {
          if (rule.min && value < rule.min) {
            errors.push({
              path: field,
              message: `${field} must be at least ${rule.min}`,
              code: 'min'
            });
          }
          
          if (rule.max && value > rule.max) {
            errors.push({
              path: field,
              message: `${field} must be at most ${rule.max}`,
              code: 'max'
            });
          }
        }
        
        // Array validations
        if (rule.type === 'array') {
          if (rule.minItems && value.length < rule.minItems) {
            errors.push({
              path: field,
              message: `${field} must have at least ${rule.minItems} items`,
              code: 'minItems'
            });
          }
          
          if (rule.maxItems && value.length > rule.maxItems) {
            errors.push({
              path: field,
              message: `${field} must have at most ${rule.maxItems} items`,
              code: 'maxItems'
            });
          }
        }
      }
    }
    
    const result = {
      valid: errors.length === 0,
      data: errors.length === 0 ? data : null,
      errors
    };
    
    validationRequests.labels('custom', 'custom', result.valid ? 'success' : 'failure').inc();
    
    res.json({
      ...result,
      engine: 'custom',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    logger.error('Custom validation error:', error);
    res.status(500).json({ 
      error: 'Custom validation failed', 
      message: error.message 
    });
  }
});

// Start server
async function startServer() {
  try {
    // Connect to Redis
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    // Connect to MongoDB
    mongoClient = new MongoClient(process.env.MONGODB_URL || 'mongodb://localhost:27017/data-handling');
    await mongoClient.connect();
    db = mongoClient.db();
    logger.info('Connected to MongoDB');
    
    // Create indexes
    await db.collection('validation_results').createIndex({ engine: 1, schema: 1 });
    await db.collection('validation_results').createIndex({ timestamp: -1 });
    await db.collection('batch_validation_results').createIndex({ batchId: 1 });
    await db.collection('batch_validation_results').createIndex({ timestamp: -1 });
    
    app.listen(port, () => {
      logger.info(`Data Validation Service running on port ${port}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('Shutting down Data Validation Service...');
  if (mongoClient) {
    await mongoClient.close();
  }
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

startServer();
