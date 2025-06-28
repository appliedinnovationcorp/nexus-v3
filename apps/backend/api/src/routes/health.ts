import { Router } from 'express'
import { formatDate } from '@nexus/utils'

const router = Router()

router.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: formatDate(new Date()),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development',
    version: process.env.npm_package_version || '1.0.0'
  })
})

router.get('/db', async (req, res) => {
  try {
    // Add database health check here
    // const dbStatus = await checkDatabaseConnection()
    
    res.json({
      status: 'healthy',
      database: 'connected',
      timestamp: formatDate(new Date())
    })
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      database: 'disconnected',
      error: error instanceof Error ? error.message : 'Unknown error',
      timestamp: formatDate(new Date())
    })
  }
})

export default router
