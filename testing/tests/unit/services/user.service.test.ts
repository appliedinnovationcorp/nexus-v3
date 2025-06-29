import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { UserService } from '@/services/user.service';
import { DatabaseService } from '@/services/database.service';
import { CacheService } from '@/services/cache.service';
import { AuditService } from '@/services/audit.service';
import { User, CreateUserRequest, UpdateUserRequest } from '@/types/user.types';
import { ValidationError, NotFoundError, ConflictError } from '@/errors';

// Mock dependencies
jest.mock('@/services/database.service');
jest.mock('@/services/cache.service');
jest.mock('@/services/audit.service');

describe('UserService', () => {
  let userService: UserService;
  let mockDatabaseService: jest.Mocked<DatabaseService>;
  let mockCacheService: jest.Mocked<CacheService>;
  let mockAuditService: jest.Mocked<AuditService>;

  // Test fixtures
  const mockUser: User = {
    id: '123e4567-e89b-12d3-a456-426614174000',
    email: 'test@example.com',
    firstName: 'John',
    lastName: 'Doe',
    role: 'user',
    isActive: true,
    createdAt: new Date('2024-01-01T00:00:00Z'),
    updatedAt: new Date('2024-01-01T00:00:00Z'),
    lastLoginAt: null,
  };

  const mockCreateUserRequest: CreateUserRequest = {
    email: 'test@example.com',
    firstName: 'John',
    lastName: 'Doe',
    password: 'SecurePassword123!',
    role: 'user',
  };

  const mockUpdateUserRequest: UpdateUserRequest = {
    firstName: 'Jane',
    lastName: 'Smith',
  };

  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();

    // Create mock instances
    mockDatabaseService = new DatabaseService() as jest.Mocked<DatabaseService>;
    mockCacheService = new CacheService() as jest.Mocked<CacheService>;
    mockAuditService = new AuditService() as jest.Mocked<AuditService>;

    // Initialize service with mocks
    userService = new UserService(
      mockDatabaseService,
      mockCacheService,
      mockAuditService
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('createUser', () => {
    it('should create a new user successfully', async () => {
      // Arrange
      mockDatabaseService.findUserByEmail.mockResolvedValue(null);
      mockDatabaseService.createUser.mockResolvedValue(mockUser);
      mockCacheService.set.mockResolvedValue(undefined);
      mockAuditService.logUserAction.mockResolvedValue(undefined);

      // Act
      const result = await userService.createUser(mockCreateUserRequest);

      // Assert
      expect(result).toEqual(mockUser);
      expect(mockDatabaseService.findUserByEmail).toHaveBeenCalledWith(
        mockCreateUserRequest.email
      );
      expect(mockDatabaseService.createUser).toHaveBeenCalledWith(
        expect.objectContaining({
          email: mockCreateUserRequest.email,
          firstName: mockCreateUserRequest.firstName,
          lastName: mockCreateUserRequest.lastName,
          role: mockCreateUserRequest.role,
        })
      );
      expect(mockCacheService.set).toHaveBeenCalledWith(
        `user:${mockUser.id}`,
        mockUser,
        3600
      );
      expect(mockAuditService.logUserAction).toHaveBeenCalledWith(
        mockUser.id,
        'USER_CREATED',
        expect.any(Object)
      );
    });

    it('should throw ConflictError when user already exists', async () => {
      // Arrange
      mockDatabaseService.findUserByEmail.mockResolvedValue(mockUser);

      // Act & Assert
      await expect(
        userService.createUser(mockCreateUserRequest)
      ).rejects.toThrow(ConflictError);
      
      expect(mockDatabaseService.createUser).not.toHaveBeenCalled();
      expect(mockCacheService.set).not.toHaveBeenCalled();
      expect(mockAuditService.logUserAction).not.toHaveBeenCalled();
    });

    it('should throw ValidationError for invalid email', async () => {
      // Arrange
      const invalidRequest = {
        ...mockCreateUserRequest,
        email: 'invalid-email',
      };

      // Act & Assert
      await expect(
        userService.createUser(invalidRequest)
      ).rejects.toThrow(ValidationError);
    });

    it('should throw ValidationError for weak password', async () => {
      // Arrange
      const weakPasswordRequest = {
        ...mockCreateUserRequest,
        password: '123',
      };

      // Act & Assert
      await expect(
        userService.createUser(weakPasswordRequest)
      ).rejects.toThrow(ValidationError);
    });

    it('should handle database errors gracefully', async () => {
      // Arrange
      mockDatabaseService.findUserByEmail.mockResolvedValue(null);
      mockDatabaseService.createUser.mockRejectedValue(
        new Error('Database connection failed')
      );

      // Act & Assert
      await expect(
        userService.createUser(mockCreateUserRequest)
      ).rejects.toThrow('Database connection failed');
      
      expect(mockCacheService.set).not.toHaveBeenCalled();
      expect(mockAuditService.logUserAction).not.toHaveBeenCalled();
    });
  });

  describe('getUserById', () => {
    it('should return user from cache when available', async () => {
      // Arrange
      mockCacheService.get.mockResolvedValue(mockUser);

      // Act
      const result = await userService.getUserById(mockUser.id);

      // Assert
      expect(result).toEqual(mockUser);
      expect(mockCacheService.get).toHaveBeenCalledWith(`user:${mockUser.id}`);
      expect(mockDatabaseService.findUserById).not.toHaveBeenCalled();
    });

    it('should fetch user from database when not in cache', async () => {
      // Arrange
      mockCacheService.get.mockResolvedValue(null);
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);
      mockCacheService.set.mockResolvedValue(undefined);

      // Act
      const result = await userService.getUserById(mockUser.id);

      // Assert
      expect(result).toEqual(mockUser);
      expect(mockCacheService.get).toHaveBeenCalledWith(`user:${mockUser.id}`);
      expect(mockDatabaseService.findUserById).toHaveBeenCalledWith(mockUser.id);
      expect(mockCacheService.set).toHaveBeenCalledWith(
        `user:${mockUser.id}`,
        mockUser,
        3600
      );
    });

    it('should throw NotFoundError when user does not exist', async () => {
      // Arrange
      mockCacheService.get.mockResolvedValue(null);
      mockDatabaseService.findUserById.mockResolvedValue(null);

      // Act & Assert
      await expect(
        userService.getUserById('non-existent-id')
      ).rejects.toThrow(NotFoundError);
    });

    it('should throw ValidationError for invalid UUID', async () => {
      // Act & Assert
      await expect(
        userService.getUserById('invalid-uuid')
      ).rejects.toThrow(ValidationError);
    });
  });

  describe('updateUser', () => {
    it('should update user successfully', async () => {
      // Arrange
      const updatedUser = { ...mockUser, ...mockUpdateUserRequest };
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);
      mockDatabaseService.updateUser.mockResolvedValue(updatedUser);
      mockCacheService.set.mockResolvedValue(undefined);
      mockAuditService.logUserAction.mockResolvedValue(undefined);

      // Act
      const result = await userService.updateUser(mockUser.id, mockUpdateUserRequest);

      // Assert
      expect(result).toEqual(updatedUser);
      expect(mockDatabaseService.findUserById).toHaveBeenCalledWith(mockUser.id);
      expect(mockDatabaseService.updateUser).toHaveBeenCalledWith(
        mockUser.id,
        mockUpdateUserRequest
      );
      expect(mockCacheService.set).toHaveBeenCalledWith(
        `user:${mockUser.id}`,
        updatedUser,
        3600
      );
      expect(mockAuditService.logUserAction).toHaveBeenCalledWith(
        mockUser.id,
        'USER_UPDATED',
        expect.objectContaining({
          changes: mockUpdateUserRequest,
        })
      );
    });

    it('should throw NotFoundError when user does not exist', async () => {
      // Arrange
      mockDatabaseService.findUserById.mockResolvedValue(null);

      // Act & Assert
      await expect(
        userService.updateUser('non-existent-id', mockUpdateUserRequest)
      ).rejects.toThrow(NotFoundError);
      
      expect(mockDatabaseService.updateUser).not.toHaveBeenCalled();
    });

    it('should validate email format when updating email', async () => {
      // Arrange
      const invalidEmailUpdate = { email: 'invalid-email' };
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);

      // Act & Assert
      await expect(
        userService.updateUser(mockUser.id, invalidEmailUpdate)
      ).rejects.toThrow(ValidationError);
    });

    it('should prevent updating to existing email', async () => {
      // Arrange
      const existingUser = { ...mockUser, id: 'different-id' };
      const emailUpdate = { email: 'existing@example.com' };
      
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);
      mockDatabaseService.findUserByEmail.mockResolvedValue(existingUser);

      // Act & Assert
      await expect(
        userService.updateUser(mockUser.id, emailUpdate)
      ).rejects.toThrow(ConflictError);
    });
  });

  describe('deleteUser', () => {
    it('should soft delete user successfully', async () => {
      // Arrange
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);
      mockDatabaseService.softDeleteUser.mockResolvedValue(undefined);
      mockCacheService.delete.mockResolvedValue(undefined);
      mockAuditService.logUserAction.mockResolvedValue(undefined);

      // Act
      await userService.deleteUser(mockUser.id);

      // Assert
      expect(mockDatabaseService.findUserById).toHaveBeenCalledWith(mockUser.id);
      expect(mockDatabaseService.softDeleteUser).toHaveBeenCalledWith(mockUser.id);
      expect(mockCacheService.delete).toHaveBeenCalledWith(`user:${mockUser.id}`);
      expect(mockAuditService.logUserAction).toHaveBeenCalledWith(
        mockUser.id,
        'USER_DELETED',
        expect.any(Object)
      );
    });

    it('should throw NotFoundError when user does not exist', async () => {
      // Arrange
      mockDatabaseService.findUserById.mockResolvedValue(null);

      // Act & Assert
      await expect(
        userService.deleteUser('non-existent-id')
      ).rejects.toThrow(NotFoundError);
      
      expect(mockDatabaseService.softDeleteUser).not.toHaveBeenCalled();
    });
  });

  describe('searchUsers', () => {
    it('should search users with pagination', async () => {
      // Arrange
      const searchQuery = 'john';
      const searchOptions = { page: 1, limit: 10, sortBy: 'createdAt', sortOrder: 'desc' as const };
      const searchResult = {
        users: [mockUser],
        total: 1,
        page: 1,
        limit: 10,
        totalPages: 1,
      };
      
      mockDatabaseService.searchUsers.mockResolvedValue(searchResult);

      // Act
      const result = await userService.searchUsers(searchQuery, searchOptions);

      // Assert
      expect(result).toEqual(searchResult);
      expect(mockDatabaseService.searchUsers).toHaveBeenCalledWith(
        searchQuery,
        searchOptions
      );
    });

    it('should use default search options when not provided', async () => {
      // Arrange
      const searchQuery = 'john';
      const defaultResult = {
        users: [mockUser],
        total: 1,
        page: 1,
        limit: 20,
        totalPages: 1,
      };
      
      mockDatabaseService.searchUsers.mockResolvedValue(defaultResult);

      // Act
      const result = await userService.searchUsers(searchQuery);

      // Assert
      expect(result).toEqual(defaultResult);
      expect(mockDatabaseService.searchUsers).toHaveBeenCalledWith(
        searchQuery,
        expect.objectContaining({
          page: 1,
          limit: 20,
          sortBy: 'createdAt',
          sortOrder: 'desc',
        })
      );
    });

    it('should sanitize search query to prevent injection', async () => {
      // Arrange
      const maliciousQuery = "'; DROP TABLE users; --";
      const sanitizedResult = {
        users: [],
        total: 0,
        page: 1,
        limit: 20,
        totalPages: 0,
      };
      
      mockDatabaseService.searchUsers.mockResolvedValue(sanitizedResult);

      // Act
      const result = await userService.searchUsers(maliciousQuery);

      // Assert
      expect(result).toEqual(sanitizedResult);
      expect(mockDatabaseService.searchUsers).toHaveBeenCalledWith(
        expect.not.stringContaining('DROP TABLE'),
        expect.any(Object)
      );
    });
  });

  describe('getUserStats', () => {
    it('should return user statistics', async () => {
      // Arrange
      const mockStats = {
        totalUsers: 100,
        activeUsers: 85,
        newUsersThisMonth: 15,
        usersByRole: {
          admin: 5,
          user: 90,
          moderator: 5,
        },
      };
      
      mockDatabaseService.getUserStats.mockResolvedValue(mockStats);

      // Act
      const result = await userService.getUserStats();

      // Assert
      expect(result).toEqual(mockStats);
      expect(mockDatabaseService.getUserStats).toHaveBeenCalled();
    });

    it('should cache user statistics', async () => {
      // Arrange
      const mockStats = {
        totalUsers: 100,
        activeUsers: 85,
        newUsersThisMonth: 15,
        usersByRole: {
          admin: 5,
          user: 90,
          moderator: 5,
        },
      };
      
      mockCacheService.get.mockResolvedValue(null);
      mockDatabaseService.getUserStats.mockResolvedValue(mockStats);
      mockCacheService.set.mockResolvedValue(undefined);

      // Act
      const result = await userService.getUserStats();

      // Assert
      expect(result).toEqual(mockStats);
      expect(mockCacheService.get).toHaveBeenCalledWith('user:stats');
      expect(mockCacheService.set).toHaveBeenCalledWith(
        'user:stats',
        mockStats,
        300 // 5 minutes cache
      );
    });
  });

  describe('Edge cases and error handling', () => {
    it('should handle concurrent user creation attempts', async () => {
      // Arrange
      mockDatabaseService.findUserByEmail
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(mockUser);
      mockDatabaseService.createUser.mockRejectedValue(
        new Error('UNIQUE constraint failed')
      );

      // Act & Assert
      await expect(
        userService.createUser(mockCreateUserRequest)
      ).rejects.toThrow(ConflictError);
    });

    it('should handle cache failures gracefully', async () => {
      // Arrange
      mockCacheService.get.mockRejectedValue(new Error('Cache unavailable'));
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);

      // Act
      const result = await userService.getUserById(mockUser.id);

      // Assert
      expect(result).toEqual(mockUser);
      expect(mockDatabaseService.findUserById).toHaveBeenCalledWith(mockUser.id);
    });

    it('should handle audit logging failures without affecting main operation', async () => {
      // Arrange
      mockDatabaseService.findUserByEmail.mockResolvedValue(null);
      mockDatabaseService.createUser.mockResolvedValue(mockUser);
      mockCacheService.set.mockResolvedValue(undefined);
      mockAuditService.logUserAction.mockRejectedValue(
        new Error('Audit service unavailable')
      );

      // Act
      const result = await userService.createUser(mockCreateUserRequest);

      // Assert
      expect(result).toEqual(mockUser);
      // Main operation should succeed even if audit logging fails
    });
  });

  describe('Performance and optimization', () => {
    it('should batch multiple user lookups efficiently', async () => {
      // Arrange
      const userIds = ['id1', 'id2', 'id3'];
      const users = userIds.map(id => ({ ...mockUser, id }));
      
      mockDatabaseService.findUsersByIds.mockResolvedValue(users);

      // Act
      const result = await userService.getUsersByIds(userIds);

      // Assert
      expect(result).toEqual(users);
      expect(mockDatabaseService.findUsersByIds).toHaveBeenCalledWith(userIds);
      expect(mockDatabaseService.findUsersByIds).toHaveBeenCalledTimes(1);
    });

    it('should implement proper cache invalidation on updates', async () => {
      // Arrange
      const updatedUser = { ...mockUser, ...mockUpdateUserRequest };
      mockDatabaseService.findUserById.mockResolvedValue(mockUser);
      mockDatabaseService.updateUser.mockResolvedValue(updatedUser);
      mockCacheService.set.mockResolvedValue(undefined);
      mockCacheService.delete.mockResolvedValue(undefined);

      // Act
      await userService.updateUser(mockUser.id, mockUpdateUserRequest);

      // Assert
      expect(mockCacheService.delete).toHaveBeenCalledWith('user:stats');
      expect(mockCacheService.set).toHaveBeenCalledWith(
        `user:${mockUser.id}`,
        updatedUser,
        3600
      );
    });
  });
});
