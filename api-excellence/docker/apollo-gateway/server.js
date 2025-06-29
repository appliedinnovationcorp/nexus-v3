const { ApolloGateway, IntrospectAndCompose, RemoteGraphQLDataSource } = require('@apollo/gateway');
const { ApolloServer } = require('@apollo/server');
const { expressMiddleware } = require('@apollo/server/express4');
const { ApolloServerPluginDrainHttpServer } = require('@apollo/server/plugin/drainHttpServer');
const express = require('express');
const http = require('http');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const promClient = require('prom-client');
const winston = require('winston');
const redis = require('redis');
const { MongoClient } = require('mongodb');
const depthLimit = require('graphql-depth-limit');
const costAnalysis = require('graphql-query-complexity');

// Metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'graphql_request_duration_seconds',
  help: 'Duration of GraphQL requests in seconds',
  labelNames: ['operation_name', 'operation_type', 'status'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
const graphqlOperations = new promClient.Counter({
  name: 'graphql_operations_total',
  help: 'Total number of GraphQL operations',
  labelNames: ['operation_name', 'operation_type', 'service']
});
const activeConnections = new promClient.Gauge({
  name: 'graphql_active_connections',
  help: 'Number of active GraphQL connections'
});
register.registerMetric(httpRequestDuration);
register.registerMetric(graphqlOperations);
register.registerMetric(activeConnections);

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

// Custom data source with caching and monitoring
class MonitoredDataSource extends RemoteGraphQLDataSource {
  willSendRequest({ request, context }) {
    // Add authentication headers
    if (context.userId) {
      request.http.headers.set('user-id', context.userId);
    }
    if (context.authorization) {
      request.http.headers.set('authorization', context.authorization);
    }
    
    // Add request ID for tracing
    request.http.headers.set('x-request-id', context.requestId);
    
    // Log outgoing request
    logger.info('Sending request to subgraph', {
      url: this.url,
      operationName: request.operationName,
      requestId: context.requestId
    });
  }

  async didReceiveResponse({ response, request, context }) {
    // Log response
    logger.info('Received response from subgraph', {
      url: this.url,
      operationName: request.operationName,
      status: response.http.status,
      requestId: context.requestId
    });

    return response;
  }

  didEncounterError(error, request, context) {
    logger.error('Subgraph error', {
      url: this.url,
      operationName: request.operationName,
      error: error.message,
      requestId: context.requestId
    });
  }
}

// Create Apollo Gateway
const gateway = new ApolloGateway({
  supergraphSdl: new IntrospectAndCompose({
    subgraphs: [
      { 
        name: 'users', 
        url: process.env.USERS_SERVICE_URL || 'http://localhost:4001/graphql' 
      },
      { 
        name: 'products', 
        url: process.env.PRODUCTS_SERVICE_URL || 'http://localhost:4002/graphql' 
      },
      { 
        name: 'orders', 
        url: process.env.ORDERS_SERVICE_URL || 'http://localhost:4003/graphql' 
      },
    ],
    introspectionHeaders: {
      'x-gateway-request': 'true'
    }
  }),
  buildService({ url }) {
    return new MonitoredDataSource({ url });
  },
});

// Authentication middleware
async function authenticate(req) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  const apiKey = req.headers['x-api-key'];
  
  if (token) {
    try {
      // Verify JWT token (implement your JWT verification logic)
      // const decoded = jwt.verify(token, process.env.JWT_SECRET);
      // return { userId: decoded.sub, roles: decoded.roles };
      return { userId: 'user-from-token', roles: ['user'] };
    } catch (error) {
      logger.warn('Invalid JWT token', { error: error.message });
    }
  }
  
  if (apiKey) {
    try {
      // Verify API key from database
      if (db) {
        const apiKeyDoc = await db.collection('api_keys').findOne({ key: apiKey });
        if (apiKeyDoc && apiKeyDoc.active) {
          return { 
            userId: apiKeyDoc.userId, 
            roles: apiKeyDoc.roles,
            apiKeyId: apiKeyDoc._id 
          };
        }
      }
    } catch (error) {
      logger.warn('API key verification failed', { error: error.message });
    }
  }
  
  return null;
}

// Rate limiting middleware
async function checkRateLimit(req, user) {
  const clientId = user?.userId || req.ip;
  const key = `rate_limit:${clientId}`;
  
  try {
    const current = await redisClient.get(key);
    const limit = user?.roles?.includes('premium') ? 10000 : 1000;
    const window = 3600; // 1 hour
    
    if (current && parseInt(current) >= limit) {
      throw new Error('Rate limit exceeded');
    }
    
    await redisClient.multi()
      .incr(key)
      .expire(key, window)
      .exec();
    
    return true;
  } catch (error) {
    logger.error('Rate limiting error', { error: error.message });
    return false;
  }
}

// Context function
async function createContext({ req }) {
  const requestId = req.headers['x-request-id'] || 
                   `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  
  // Authenticate user
  const user = await authenticate(req);
  
  // Check rate limiting
  if (user || req.ip) {
    const rateLimitOk = await checkRateLimit(req, user);
    if (!rateLimitOk) {
      throw new Error('Rate limit exceeded');
    }
  }
  
  return {
    requestId,
    userId: user?.userId,
    roles: user?.roles || [],
    authorization: req.headers.authorization,
    userAgent: req.headers['user-agent'],
    ip: req.ip,
    startTime: Date.now()
  };
}

// Plugins
const metricsPlugin = {
  requestDidStart() {
    return {
      didResolveOperation(requestContext) {
        const { operationName, operation } = requestContext.request;
        const operationType = operation?.operation || 'unknown';
        
        graphqlOperations.labels(
          operationName || 'anonymous',
          operationType,
          'gateway'
        ).inc();
      },
      
      willSendResponse(requestContext) {
        const { context } = requestContext;
        const duration = (Date.now() - context.startTime) / 1000;
        const { operationName, operation } = requestContext.request;
        const operationType = operation?.operation || 'unknown';
        const status = requestContext.response.http?.status || 200;
        
        httpRequestDuration.labels(
          operationName || 'anonymous',
          operationType,
          status.toString()
        ).observe(duration);
        
        logger.info('GraphQL request completed', {
          operationName,
          operationType,
          duration,
          status,
          requestId: context.requestId
        });
      }
    };
  }
};

const complexityPlugin = {
  requestDidStart() {
    return {
      didResolveOperation({ request, document }) {
        const complexity = costAnalysis.getComplexity({
          estimators: [
            costAnalysis.fieldExtensionsEstimator(),
            costAnalysis.simpleEstimator({ defaultComplexity: 1 })
          ],
          maximumComplexity: 1000,
          variables: request.variables,
          document,
          introspection: true
        });
        
        if (complexity > 1000) {
          throw new Error(`Query complexity ${complexity} exceeds maximum allowed complexity 1000`);
        }
        
        logger.info('Query complexity analysis', {
          operationName: request.operationName,
          complexity
        });
      }
    };
  }
};

async function startServer() {
  try {
    // Connect to Redis
    await redisClient.connect();
    logger.info('Connected to Redis');
    
    // Connect to MongoDB
    mongoClient = new MongoClient(process.env.MONGODB_URL || 'mongodb://localhost:27017/api-excellence');
    await mongoClient.connect();
    db = mongoClient.db();
    logger.info('Connected to MongoDB');
    
    // Create Express app
    const app = express();
    const httpServer = http.createServer(app);
    
    // Middleware
    app.use(helmet({
      contentSecurityPolicy: false,
      crossOriginEmbedderPolicy: false
    }));
    app.use(compression());
    
    // Health check endpoint
    app.get('/health', (req, res) => {
      res.json({ 
        status: 'healthy', 
        timestamp: new Date().toISOString(),
        service: 'apollo-federation-gateway'
      });
    });
    
    // Metrics endpoint
    app.get('/metrics', async (req, res) => {
      res.set('Content-Type', register.contentType);
      res.end(await register.metrics());
    });
    
    // Create Apollo Server
    const server = new ApolloServer({
      gateway,
      plugins: [
        ApolloServerPluginDrainHttpServer({ httpServer }),
        metricsPlugin,
        complexityPlugin,
        {
          requestDidStart() {
            activeConnections.inc();
            return {
              willSendResponse() {
                activeConnections.dec();
              }
            };
          }
        }
      ],
      validationRules: [depthLimit(10)],
      introspection: process.env.NODE_ENV !== 'production',
      playground: process.env.NODE_ENV !== 'production'
    });
    
    await server.start();
    
    // Apply middleware
    app.use(
      '/graphql',
      cors({
        origin: process.env.CORS_ORIGIN || '*',
        credentials: true
      }),
      express.json({ limit: '10mb' }),
      expressMiddleware(server, {
        context: createContext
      })
    );
    
    // GraphQL Playground redirect
    app.get('/', (req, res) => {
      res.redirect('/graphql');
    });
    
    // Schema endpoint
    app.get('/schema', async (req, res) => {
      try {
        const schema = await gateway.load();
        res.set('Content-Type', 'text/plain');
        res.send(schema.schema);
      } catch (error) {
        res.status(500).json({ error: 'Failed to load schema' });
      }
    });
    
    const port = process.env.PORT || 4000;
    
    await new Promise((resolve) => {
      httpServer.listen({ port }, resolve);
    });
    
    logger.info(`🚀 Apollo Federation Gateway ready at http://localhost:${port}/graphql`);
    logger.info(`📊 Metrics available at http://localhost:${port}/metrics`);
    logger.info(`🏥 Health check at http://localhost:${port}/health`);
    
  } catch (error) {
    logger.error('Failed to start Apollo Gateway:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('Shutting down Apollo Gateway...');
  if (mongoClient) {
    await mongoClient.close();
  }
  if (redisClient) {
    await redisClient.quit();
  }
  process.exit(0);
});

startServer();
