const Bull = require('bull');
const Redis = require('ioredis');
const winston = require('winston');

class QueueService {
  constructor() {
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'logs/queue-service.log' })
      ]
    });

    // Redis connection for queues
    this.redisConfig = {
      host: process.env.QUEUE_REDIS_HOST || 'redis-queue',
      port: process.env.QUEUE_REDIS_PORT || 6379,
      password: process.env.QUEUE_REDIS_PASSWORD,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
      lazyConnect: true,
    };

    // Initialize queues
    this.queues = new Map();
    this.processors = new Map();
    
    // Queue configurations
    this.queueConfigs = {
      'email': {
        defaultJobOptions: {
          removeOnComplete: 100,
          removeOnFail: 50,
          attempts: 3,
          backoff: {
            type: 'exponential',
            delay: 2000,
          },
        },
        settings: {
          stalledInterval: 30 * 1000,
          maxStalledCount: 1,
        }
      },
      'image-processing': {
        defaultJobOptions: {
          removeOnComplete: 50,
          removeOnFail: 25,
          attempts: 2,
          backoff: {
            type: 'fixed',
            delay: 5000,
          },
        },
        settings: {
          stalledInterval: 60 * 1000,
          maxStalledCount: 1,
        }
      },
      'analytics': {
        defaultJobOptions: {
          removeOnComplete: 200,
          removeOnFail: 100,
          attempts: 5,
          backoff: {
            type: 'exponential',
            delay: 1000,
          },
        },
        settings: {
          stalledInterval: 30 * 1000,
          maxStalledCount: 2,
        }
      },
      'notifications': {
        defaultJobOptions: {
          removeOnComplete: 100,
          removeOnFail: 50,
          attempts: 3,
          backoff: {
            type: 'exponential',
            delay: 1500,
          },
        },
        settings: {
          stalledInterval: 30 * 1000,
          maxStalledCount: 1,
        }
      },
      'data-export': {
        defaultJobOptions: {
          removeOnComplete: 10,
          removeOnFail: 10,
          attempts: 1,
          timeout: 300000, // 5 minutes
        },
        settings: {
          stalledInterval: 60 * 1000,
          maxStalledCount: 1,
        }
      },
      'cleanup': {
        defaultJobOptions: {
          removeOnComplete: 5,
          removeOnFail: 5,
          attempts: 2,
          backoff: {
            type: 'fixed',
            delay: 10000,
          },
        },
        settings: {
          stalledInterval: 120 * 1000,
          maxStalledCount: 1,
        }
      }
    };

    // Job statistics
    this.stats = {
      processed: 0,
      failed: 0,
      active: 0,
      waiting: 0,
      delayed: 0,
      completed: 0,
    };

    this.initializeQueues();
    this.setupEventListeners();
  }

  initializeQueues() {
    for (const [queueName, config] of Object.entries(this.queueConfigs)) {
      const queue = new Bull(queueName, {
        redis: this.redisConfig,
        defaultJobOptions: config.defaultJobOptions,
        settings: config.settings,
      });

      this.queues.set(queueName, queue);
      this.logger.info(`Initialized queue: ${queueName}`);
    }
  }

  setupEventListeners() {
    for (const [queueName, queue] of this.queues.entries()) {
      queue.on('completed', (job, result) => {
        this.stats.completed++;
        this.logger.info(`Job completed`, {
          queue: queueName,
          jobId: job.id,
          jobType: job.name,
          processingTime: Date.now() - job.processedOn,
        });
      });

      queue.on('failed', (job, err) => {
        this.stats.failed++;
        this.logger.error(`Job failed`, {
          queue: queueName,
          jobId: job.id,
          jobType: job.name,
          error: err.message,
          attempts: job.attemptsMade,
        });
      });

      queue.on('active', (job) => {
        this.stats.active++;
        this.logger.debug(`Job started`, {
          queue: queueName,
          jobId: job.id,
          jobType: job.name,
        });
      });

      queue.on('stalled', (job) => {
        this.logger.warn(`Job stalled`, {
          queue: queueName,
          jobId: job.id,
          jobType: job.name,
        });
      });

      queue.on('progress', (job, progress) => {
        this.logger.debug(`Job progress`, {
          queue: queueName,
          jobId: job.id,
          jobType: job.name,
          progress: progress,
        });
      });
    }
  }

  // Add job to queue
  async addJob(queueName, jobType, data, options = {}) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const job = await queue.add(jobType, data, {
        ...options,
        timestamp: Date.now(),
      });

      this.logger.info(`Job added to queue`, {
        queue: queueName,
        jobId: job.id,
        jobType: jobType,
        priority: options.priority || 0,
        delay: options.delay || 0,
      });

      return job;
    } catch (error) {
      this.logger.error(`Failed to add job to queue`, {
        queue: queueName,
        jobType: jobType,
        error: error.message,
      });
      throw error;
    }
  }

  // Add multiple jobs at once
  async addBulkJobs(queueName, jobs) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const bulkJobs = jobs.map(job => ({
        name: job.type,
        data: { ...job.data, timestamp: Date.now() },
        opts: job.options || {},
      }));

      const addedJobs = await queue.addBulk(bulkJobs);

      this.logger.info(`Bulk jobs added to queue`, {
        queue: queueName,
        count: addedJobs.length,
      });

      return addedJobs;
    } catch (error) {
      this.logger.error(`Failed to add bulk jobs to queue`, {
        queue: queueName,
        error: error.message,
      });
      throw error;
    }
  }

  // Schedule recurring job
  async addRecurringJob(queueName, jobType, data, cronExpression, options = {}) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const job = await queue.add(jobType, data, {
        repeat: { cron: cronExpression },
        ...options,
      });

      this.logger.info(`Recurring job scheduled`, {
        queue: queueName,
        jobType: jobType,
        cron: cronExpression,
      });

      return job;
    } catch (error) {
      this.logger.error(`Failed to schedule recurring job`, {
        queue: queueName,
        jobType: jobType,
        error: error.message,
      });
      throw error;
    }
  }

  // Register job processor
  registerProcessor(queueName, jobType, processor, concurrency = 1) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      // Wrap processor with error handling and metrics
      const wrappedProcessor = async (job) => {
        const startTime = Date.now();
        
        try {
          this.logger.debug(`Processing job`, {
            queue: queueName,
            jobId: job.id,
            jobType: job.name,
          });

          const result = await processor(job);
          
          const processingTime = Date.now() - startTime;
          this.stats.processed++;

          this.logger.info(`Job processed successfully`, {
            queue: queueName,
            jobId: job.id,
            jobType: job.name,
            processingTime: processingTime,
          });

          return result;
        } catch (error) {
          const processingTime = Date.now() - startTime;
          
          this.logger.error(`Job processing failed`, {
            queue: queueName,
            jobId: job.id,
            jobType: job.name,
            processingTime: processingTime,
            error: error.message,
            stack: error.stack,
          });

          throw error;
        }
      };

      queue.process(jobType, concurrency, wrappedProcessor);

      this.processors.set(`${queueName}:${jobType}`, {
        processor: wrappedProcessor,
        concurrency: concurrency,
      });

      this.logger.info(`Registered processor`, {
        queue: queueName,
        jobType: jobType,
        concurrency: concurrency,
      });
    } catch (error) {
      this.logger.error(`Failed to register processor`, {
        queue: queueName,
        jobType: jobType,
        error: error.message,
      });
      throw error;
    }
  }

  // Get queue statistics
  async getQueueStats(queueName) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const [waiting, active, completed, failed, delayed] = await Promise.all([
        queue.getWaiting(),
        queue.getActive(),
        queue.getCompleted(),
        queue.getFailed(),
        queue.getDelayed(),
      ]);

      return {
        name: queueName,
        waiting: waiting.length,
        active: active.length,
        completed: completed.length,
        failed: failed.length,
        delayed: delayed.length,
        isPaused: await queue.isPaused(),
      };
    } catch (error) {
      this.logger.error(`Failed to get queue stats`, {
        queue: queueName,
        error: error.message,
      });
      throw error;
    }
  }

  // Get all queue statistics
  async getAllQueueStats() {
    const stats = {};
    
    for (const queueName of this.queues.keys()) {
      try {
        stats[queueName] = await this.getQueueStats(queueName);
      } catch (error) {
        stats[queueName] = { error: error.message };
      }
    }

    return {
      queues: stats,
      global: this.stats,
    };
  }

  // Pause/Resume queue
  async pauseQueue(queueName) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      await queue.pause();
      this.logger.info(`Queue paused`, { queue: queueName });
    } catch (error) {
      this.logger.error(`Failed to pause queue`, {
        queue: queueName,
        error: error.message,
      });
      throw error;
    }
  }

  async resumeQueue(queueName) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      await queue.resume();
      this.logger.info(`Queue resumed`, { queue: queueName });
    } catch (error) {
      this.logger.error(`Failed to resume queue`, {
        queue: queueName,
        error: error.message,
      });
      throw error;
    }
  }

  // Clean up completed/failed jobs
  async cleanQueue(queueName, grace = 24 * 60 * 60 * 1000) { // 24 hours default
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const cleanedJobs = await queue.clean(grace, 'completed');
      const cleanedFailedJobs = await queue.clean(grace, 'failed');

      this.logger.info(`Queue cleaned`, {
        queue: queueName,
        completedCleaned: cleanedJobs.length,
        failedCleaned: cleanedFailedJobs.length,
      });

      return {
        completed: cleanedJobs.length,
        failed: cleanedFailedJobs.length,
      };
    } catch (error) {
      this.logger.error(`Failed to clean queue`, {
        queue: queueName,
        error: error.message,
      });
      throw error;
    }
  }

  // Get job by ID
  async getJob(queueName, jobId) {
    try {
      const queue = this.queues.get(queueName);
      if (!queue) {
        throw new Error(`Queue ${queueName} not found`);
      }

      const job = await queue.getJob(jobId);
      return job;
    } catch (error) {
      this.logger.error(`Failed to get job`, {
        queue: queueName,
        jobId: jobId,
        error: error.message,
      });
      throw error;
    }
  }

  // Retry failed job
  async retryJob(queueName, jobId) {
    try {
      const job = await this.getJob(queueName, jobId);
      if (!job) {
        throw new Error(`Job ${jobId} not found in queue ${queueName}`);
      }

      await job.retry();
      this.logger.info(`Job retried`, {
        queue: queueName,
        jobId: jobId,
      });
    } catch (error) {
      this.logger.error(`Failed to retry job`, {
        queue: queueName,
        jobId: jobId,
        error: error.message,
      });
      throw error;
    }
  }

  // Health check
  async healthCheck() {
    try {
      const redis = new Redis(this.redisConfig);
      await redis.ping();
      await redis.quit();

      const queueStats = await this.getAllQueueStats();
      
      return {
        status: 'healthy',
        redis: 'connected',
        queues: Object.keys(queueStats.queues).length,
        stats: queueStats.global,
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        error: error.message,
      };
    }
  }

  // Close all queues
  async close() {
    try {
      const closePromises = Array.from(this.queues.values()).map(queue => queue.close());
      await Promise.all(closePromises);
      
      this.logger.info('All queues closed');
    } catch (error) {
      this.logger.error('Error closing queues', { error: error.message });
    }
  }

  // Utility methods for common job patterns

  // Priority job (high priority)
  async addPriorityJob(queueName, jobType, data, options = {}) {
    return this.addJob(queueName, jobType, data, {
      ...options,
      priority: 10,
    });
  }

  // Delayed job
  async addDelayedJob(queueName, jobType, data, delay, options = {}) {
    return this.addJob(queueName, jobType, data, {
      ...options,
      delay: delay,
    });
  }

  // Unique job (prevent duplicates)
  async addUniqueJob(queueName, jobType, data, options = {}) {
    return this.addJob(queueName, jobType, data, {
      ...options,
      jobId: `${jobType}:${JSON.stringify(data)}`,
    });
  }
}

module.exports = QueueService;
