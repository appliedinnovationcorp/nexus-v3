import { Router } from 'express'
import { body } from 'express-validator'
import { AuthController } from '../controllers/AuthController'
import { validationMiddleware } from '../middleware/validation'

const router = Router()
const authController = new AuthController()

// Register
router.post('/register',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/),
    body('name').trim().isLength({ min: 2, max: 50 }),
    validationMiddleware
  ],
  authController.register
)

// Login
router.post('/login',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').notEmpty(),
    validationMiddleware
  ],
  authController.login
)

// Refresh token
router.post('/refresh',
  [
    body('refreshToken').notEmpty(),
    validationMiddleware
  ],
  authController.refreshToken
)

// Logout
router.post('/logout',
  [
    body('refreshToken').notEmpty(),
    validationMiddleware
  ],
  authController.logout
)

// Forgot password
router.post('/forgot-password',
  [
    body('email').isEmail().normalizeEmail(),
    validationMiddleware
  ],
  authController.forgotPassword
)

// Reset password
router.post('/reset-password',
  [
    body('token').notEmpty(),
    body('password').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/),
    validationMiddleware
  ],
  authController.resetPassword
)

export default router
