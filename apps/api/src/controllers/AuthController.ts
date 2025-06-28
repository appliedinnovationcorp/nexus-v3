import { Request, Response } from 'express'
import bcrypt from 'bcryptjs'
import jwt from 'jsonwebtoken'
import { AuthService } from '../services/AuthService'
import { UserService } from '../services/UserService'

export class AuthController {
  private authService: AuthService
  private userService: UserService

  constructor() {
    this.authService = new AuthService()
    this.userService = new UserService()
  }

  register = async (req: Request, res: Response) => {
    try {
      const { email, password, name } = req.body

      // Check if user already exists
      const existingUser = await this.userService.findByEmail(email)
      if (existingUser) {
        return res.status(400).json({
          success: false,
          message: 'User already exists with this email'
        })
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 12)

      // Create user
      const user = await this.userService.create({
        email,
        password: hashedPassword,
        name
      })

      // Generate tokens
      const { accessToken, refreshToken } = this.authService.generateTokens(user.id)

      // Save refresh token
      await this.authService.saveRefreshToken(user.id, refreshToken)

      res.status(201).json({
        success: true,
        message: 'User registered successfully',
        data: {
          user: {
            id: user.id,
            email: user.email,
            name: user.name
          },
          accessToken,
          refreshToken
        }
      })
    } catch (error) {
      console.error('Registration error:', error)
      res.status(500).json({
        success: false,
        message: 'Internal server error'
      })
    }
  }

  login = async (req: Request, res: Response) => {
    try {
      const { email, password } = req.body

      // Find user
      const user = await this.userService.findByEmail(email)
      if (!user) {
        return res.status(401).json({
          success: false,
          message: 'Invalid credentials'
        })
      }

      // Verify password
      const isValidPassword = await bcrypt.compare(password, user.password)
      if (!isValidPassword) {
        return res.status(401).json({
          success: false,
          message: 'Invalid credentials'
        })
      }

      // Generate tokens
      const { accessToken, refreshToken } = this.authService.generateTokens(user.id)

      // Save refresh token
      await this.authService.saveRefreshToken(user.id, refreshToken)

      res.json({
        success: true,
        message: 'Login successful',
        data: {
          user: {
            id: user.id,
            email: user.email,
            name: user.name
          },
          accessToken,
          refreshToken
        }
      })
    } catch (error) {
      console.error('Login error:', error)
      res.status(500).json({
        success: false,
        message: 'Internal server error'
      })
    }
  }

  refreshToken = async (req: Request, res: Response) => {
    try {
      const { refreshToken } = req.body

      // Verify refresh token
      const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET!) as { userId: string }

      // Check if refresh token exists in database
      const isValidRefreshToken = await this.authService.verifyRefreshToken(decoded.userId, refreshToken)
      if (!isValidRefreshToken) {
        return res.status(401).json({
          success: false,
          message: 'Invalid refresh token'
        })
      }

      // Generate new tokens
      const tokens = this.authService.generateTokens(decoded.userId)

      // Save new refresh token
      await this.authService.saveRefreshToken(decoded.userId, tokens.refreshToken)

      res.json({
        success: true,
        data: tokens
      })
    } catch (error) {
      console.error('Refresh token error:', error)
      res.status(401).json({
        success: false,
        message: 'Invalid refresh token'
      })
    }
  }

  logout = async (req: Request, res: Response) => {
    try {
      const { refreshToken } = req.body

      // Remove refresh token from database
      await this.authService.removeRefreshToken(refreshToken)

      res.json({
        success: true,
        message: 'Logout successful'
      })
    } catch (error) {
      console.error('Logout error:', error)
      res.status(500).json({
        success: false,
        message: 'Internal server error'
      })
    }
  }

  forgotPassword = async (req: Request, res: Response) => {
    try {
      const { email } = req.body

      // Find user
      const user = await this.userService.findByEmail(email)
      if (!user) {
        // Don't reveal if user exists or not
        return res.json({
          success: true,
          message: 'If the email exists, a reset link has been sent'
        })
      }

      // Generate reset token
      const resetToken = await this.authService.generatePasswordResetToken(user.id)

      // Send email (implement email service)
      // await emailService.sendPasswordResetEmail(user.email, resetToken)

      res.json({
        success: true,
        message: 'If the email exists, a reset link has been sent'
      })
    } catch (error) {
      console.error('Forgot password error:', error)
      res.status(500).json({
        success: false,
        message: 'Internal server error'
      })
    }
  }

  resetPassword = async (req: Request, res: Response) => {
    try {
      const { token, password } = req.body

      // Verify reset token
      const userId = await this.authService.verifyPasswordResetToken(token)
      if (!userId) {
        return res.status(400).json({
          success: false,
          message: 'Invalid or expired reset token'
        })
      }

      // Hash new password
      const hashedPassword = await bcrypt.hash(password, 12)

      // Update user password
      await this.userService.updatePassword(userId, hashedPassword)

      // Invalidate reset token
      await this.authService.invalidatePasswordResetToken(token)

      res.json({
        success: true,
        message: 'Password reset successful'
      })
    } catch (error) {
      console.error('Reset password error:', error)
      res.status(500).json({
        success: false,
        message: 'Internal server error'
      })
    }
  }
}
