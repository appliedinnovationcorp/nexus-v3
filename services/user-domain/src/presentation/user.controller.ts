import { Request, Response } from 'express';
import { CommandBus } from '../../../shared-kernel/src/application/command';
import { QueryBus } from '../../../shared-kernel/src/application/query';
import { CreateUserCommand } from '../application/commands/create-user.command';
import { GetUserQuery, GetUserByEmailQuery } from '../application/queries/get-user.query';

export class UserController {
  constructor(
    private readonly commandBus: CommandBus,
    private readonly queryBus: QueryBus
  ) {}

  async createUser(req: Request, res: Response): Promise<void> {
    try {
      const { email, username } = req.body;

      if (!email || !username) {
        res.status(400).json({
          error: 'Email and username are required'
        });
        return;
      }

      const command = new CreateUserCommand(email, username);
      const userId = await this.commandBus.execute(command);

      res.status(201).json({
        success: true,
        data: { userId },
        message: 'User created successfully'
      });
    } catch (error) {
      console.error('Error creating user:', error);
      res.status(400).json({
        error: error instanceof Error ? error.message : 'Failed to create user'
      });
    }
  }

  async getUserById(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;

      if (!id) {
        res.status(400).json({
          error: 'User ID is required'
        });
        return;
      }

      const query = new GetUserQuery(id);
      const user = await this.queryBus.execute(query);

      if (!user) {
        res.status(404).json({
          error: 'User not found'
        });
        return;
      }

      res.json({
        success: true,
        data: user
      });
    } catch (error) {
      console.error('Error getting user:', error);
      res.status(500).json({
        error: 'Failed to retrieve user'
      });
    }
  }

  async getUserByEmail(req: Request, res: Response): Promise<void> {
    try {
      const { email } = req.params;

      if (!email) {
        res.status(400).json({
          error: 'Email is required'
        });
        return;
      }

      const query = new GetUserByEmailQuery(email);
      const user = await this.queryBus.execute(query);

      if (!user) {
        res.status(404).json({
          error: 'User not found'
        });
        return;
      }

      res.json({
        success: true,
        data: user
      });
    } catch (error) {
      console.error('Error getting user by email:', error);
      res.status(500).json({
        error: 'Failed to retrieve user'
      });
    }
  }

  async healthCheck(req: Request, res: Response): Promise<void> {
    res.json({
      service: 'user-domain',
      status: 'healthy',
      timestamp: new Date().toISOString()
    });
  }
}
