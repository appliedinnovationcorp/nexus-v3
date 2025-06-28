import { Router } from 'express';
import { UserController } from './user.controller';

export function createUserRoutes(userController: UserController): Router {
  const router = Router();

  // Health check
  router.get('/health', userController.healthCheck.bind(userController));

  // User operations
  router.post('/users', userController.createUser.bind(userController));
  router.get('/users/:id', userController.getUserById.bind(userController));
  router.get('/users/email/:email', userController.getUserByEmail.bind(userController));

  return router;
}
