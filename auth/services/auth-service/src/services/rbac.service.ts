import { Enforcer, newEnforcer } from 'casbin';
import path from 'path';

import {
  RbacService,
  Permission,
  Role,
  User,
  PermissionCheckRequest,
  PermissionCheckResponse,
  AuthError,
  InsufficientPermissionsError
} from '../types/auth.types';

import { UserRepository } from '../repositories/user.repository';
import { RoleRepository } from '../repositories/role.repository';
import { PermissionRepository } from '../repositories/permission.repository';
import { UserRoleRepository } from '../repositories/user-role.repository';
import { RolePermissionRepository } from '../repositories/role-permission.repository';
import { GroupRepository } from '../repositories/group.repository';
import { AuditService } from './audit.service';
import { RedisService } from './redis.service';
import { logger } from '../utils/logger';

export class RbacServiceImpl implements RbacService {
  private enforcer: Enforcer | null = null;
  private readonly CACHE_TTL = 300; // 5 minutes

  constructor(
    private readonly userRepository: UserRepository,
    private readonly roleRepository: RoleRepository,
    private readonly permissionRepository: PermissionRepository,
    private readonly userRoleRepository: UserRoleRepository,
    private readonly rolePermissionRepository: RolePermissionRepository,
    private readonly groupRepository: GroupRepository,
    private readonly auditService: AuditService,
    private readonly redisService: RedisService
  ) {
    this.initializeCasbin();
  }

  private async initializeCasbin(): Promise<void> {
    try {
      const modelPath = path.join(__dirname, '../config/rbac_model.conf');
      const policyPath = path.join(__dirname, '../config/rbac_policy.csv');
      
      this.enforcer = await newEnforcer(modelPath, policyPath);
      
      // Load policies from database
      await this.loadPoliciesFromDatabase();
      
      logger.info('Casbin RBAC enforcer initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize Casbin enforcer:', error);
      throw new AuthError('RBAC initialization failed', 'RBAC_INIT_ERROR', 500);
    }
  }

  async checkPermission(
    userId: string,
    resource: string,
    action: string,
    context?: any
  ): Promise<boolean> {
    try {
      // Check cache first
      const cacheKey = `permission:${userId}:${resource}:${action}`;
      const cached = await this.redisService.get(cacheKey);
      
      if (cached !== null) {
        return cached === 'true';
      }

      // Get user roles and permissions
      const userPermissions = await this.getUserPermissions(userId);
      
      // Check direct permission
      const hasDirectPermission = userPermissions.some(p => 
        p.resource === resource && p.action === action
      );

      if (hasDirectPermission) {
        await this.redisService.setWithExpiry(cacheKey, 'true', this.CACHE_TTL);
        return true;
      }

      // Check with Casbin enforcer for complex policies
      if (this.enforcer) {
        const allowed = await this.enforcer.enforce(userId, resource, action);
        
        if (allowed) {
          await this.redisService.setWithExpiry(cacheKey, 'true', this.CACHE_TTL);
          
          // Log permission check
          await this.auditService.logAuthEvent({
            eventType: 'PERMISSION_GRANTED',
            userId,
            resource,
            action,
            result: 'SUCCESS',
            metadata: { context }
          });
          
          return true;
        }
      }

      // Check contextual permissions
      if (context) {
        const contextualAllowed = await this.checkContextualPermission(
          userId,
          resource,
          action,
          context
        );
        
        if (contextualAllowed) {
          await this.redisService.setWithExpiry(cacheKey, 'true', this.CACHE_TTL);
          return true;
        }
      }

      // Cache negative result for shorter time
      await this.redisService.setWithExpiry(cacheKey, 'false', 60);
      
      // Log permission denied
      await this.auditService.logAuthEvent({
        eventType: 'PERMISSION_DENIED',
        userId,
        resource,
        action,
        result: 'FAILURE',
        metadata: { context }
      });

      return false;

    } catch (error) {
      logger.error('Permission check error:', error);
      return false;
    }
  }

  async getUserPermissions(userId: string): Promise<Permission[]> {
    try {
      // Check cache first
      const cacheKey = `user_permissions:${userId}`;
      const cached = await this.redisService.get(cacheKey);
      
      if (cached) {
        return JSON.parse(cached);
      }

      // Get permissions from database using the stored function
      const permissions = await this.permissionRepository.getUserPermissions(userId);
      
      // Cache the result
      await this.redisService.setWithExpiry(
        cacheKey,
        JSON.stringify(permissions),
        this.CACHE_TTL
      );

      return permissions;

    } catch (error) {
      logger.error('Get user permissions error:', error);
      return [];
    }
  }

  async getUserRoles(userId: string): Promise<Role[]> {
    try {
      // Check cache first
      const cacheKey = `user_roles:${userId}`;
      const cached = await this.redisService.get(cacheKey);
      
      if (cached) {
        return JSON.parse(cached);
      }

      const roles = await this.userRoleRepository.getUserRoles(userId);
      
      // Cache the result
      await this.redisService.setWithExpiry(
        cacheKey,
        JSON.stringify(roles),
        this.CACHE_TTL
      );

      return roles;

    } catch (error) {
      logger.error('Get user roles error:', error);
      return [];
    }
  }

  async assignRole(userId: string, roleId: string, assignedBy: string): Promise<void> {
    try {
      // Verify user exists
      const user = await this.userRepository.findById(userId);
      if (!user) {
        throw new AuthError('User not found', 'USER_NOT_FOUND', 404);
      }

      // Verify role exists
      const role = await this.roleRepository.findById(roleId);
      if (!role) {
        throw new AuthError('Role not found', 'ROLE_NOT_FOUND', 404);
      }

      // Check if assignment already exists
      const existingAssignment = await this.userRoleRepository.findByUserAndRole(userId, roleId);
      if (existingAssignment) {
        throw new AuthError('Role already assigned', 'ROLE_ALREADY_ASSIGNED', 409);
      }

      // Create role assignment
      await this.userRoleRepository.create({
        userId,
        roleId,
        assignedBy,
        assignedAt: new Date(),
        isActive: true
      });

      // Update Casbin policies
      if (this.enforcer) {
        await this.addUserRole(userId, role.name);
      }

      // Clear cache
      await this.clearUserCache(userId);

      // Log role assignment
      await this.auditService.logAuthEvent({
        eventType: 'ROLE_ASSIGNED',
        userId,
        result: 'SUCCESS',
        metadata: {
          roleId,
          roleName: role.name,
          assignedBy
        }
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Role assignment error:', error);
      throw new AuthError('Role assignment failed', 'ROLE_ASSIGN_ERROR', 500);
    }
  }

  async removeRole(userId: string, roleId: string): Promise<void> {
    try {
      const assignment = await this.userRoleRepository.findByUserAndRole(userId, roleId);
      if (!assignment) {
        throw new AuthError('Role assignment not found', 'ASSIGNMENT_NOT_FOUND', 404);
      }

      const role = await this.roleRepository.findById(roleId);
      if (!role) {
        throw new AuthError('Role not found', 'ROLE_NOT_FOUND', 404);
      }

      // Remove role assignment
      await this.userRoleRepository.delete(assignment.id);

      // Update Casbin policies
      if (this.enforcer) {
        await this.removeUserRole(userId, role.name);
      }

      // Clear cache
      await this.clearUserCache(userId);

      // Log role removal
      await this.auditService.logAuthEvent({
        eventType: 'ROLE_REMOVED',
        userId,
        result: 'SUCCESS',
        metadata: {
          roleId,
          roleName: role.name
        }
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Role removal error:', error);
      throw new AuthError('Role removal failed', 'ROLE_REMOVE_ERROR', 500);
    }
  }

  async createRole(roleData: Partial<Role>): Promise<Role> {
    try {
      // Check if role name already exists
      if (roleData.name) {
        const existingRole = await this.roleRepository.findByName(roleData.name);
        if (existingRole) {
          throw new AuthError('Role name already exists', 'ROLE_NAME_EXISTS', 409);
        }
      }

      const role = await this.roleRepository.create(roleData);

      // Log role creation
      await this.auditService.logAuthEvent({
        eventType: 'ROLE_CREATED',
        result: 'SUCCESS',
        metadata: {
          roleId: role.id,
          roleName: role.name
        }
      });

      return role;

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Role creation error:', error);
      throw new AuthError('Role creation failed', 'ROLE_CREATE_ERROR', 500);
    }
  }

  async assignPermissionToRole(roleId: string, permissionId: string): Promise<void> {
    try {
      // Verify role exists
      const role = await this.roleRepository.findById(roleId);
      if (!role) {
        throw new AuthError('Role not found', 'ROLE_NOT_FOUND', 404);
      }

      // Verify permission exists
      const permission = await this.permissionRepository.findById(permissionId);
      if (!permission) {
        throw new AuthError('Permission not found', 'PERMISSION_NOT_FOUND', 404);
      }

      // Check if assignment already exists
      const existingAssignment = await this.rolePermissionRepository.findByRoleAndPermission(
        roleId,
        permissionId
      );
      if (existingAssignment) {
        throw new AuthError('Permission already assigned', 'PERMISSION_ALREADY_ASSIGNED', 409);
      }

      // Create permission assignment
      await this.rolePermissionRepository.create({
        roleId,
        permissionId,
        grantedAt: new Date()
      });

      // Update Casbin policies
      if (this.enforcer) {
        await this.addRolePermission(role.name, permission.resource, permission.action);
      }

      // Clear related caches
      await this.clearRoleCache(roleId);

      // Log permission assignment
      await this.auditService.logAuthEvent({
        eventType: 'PERMISSION_ASSIGNED_TO_ROLE',
        result: 'SUCCESS',
        metadata: {
          roleId,
          roleName: role.name,
          permissionId,
          permissionName: permission.name
        }
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Permission assignment error:', error);
      throw new AuthError('Permission assignment failed', 'PERMISSION_ASSIGN_ERROR', 500);
    }
  }

  async removePermissionFromRole(roleId: string, permissionId: string): Promise<void> {
    try {
      const assignment = await this.rolePermissionRepository.findByRoleAndPermission(
        roleId,
        permissionId
      );
      if (!assignment) {
        throw new AuthError('Permission assignment not found', 'ASSIGNMENT_NOT_FOUND', 404);
      }

      const role = await this.roleRepository.findById(roleId);
      const permission = await this.permissionRepository.findById(permissionId);

      if (!role || !permission) {
        throw new AuthError('Role or permission not found', 'ENTITY_NOT_FOUND', 404);
      }

      // Remove permission assignment
      await this.rolePermissionRepository.delete(assignment.id);

      // Update Casbin policies
      if (this.enforcer) {
        await this.removeRolePermission(role.name, permission.resource, permission.action);
      }

      // Clear related caches
      await this.clearRoleCache(roleId);

      // Log permission removal
      await this.auditService.logAuthEvent({
        eventType: 'PERMISSION_REMOVED_FROM_ROLE',
        result: 'SUCCESS',
        metadata: {
          roleId,
          roleName: role.name,
          permissionId,
          permissionName: permission.name
        }
      });

    } catch (error) {
      if (error instanceof AuthError) {
        throw error;
      }
      
      logger.error('Permission removal error:', error);
      throw new AuthError('Permission removal failed', 'PERMISSION_REMOVE_ERROR', 500);
    }
  }

  async checkPermissionWithContext(
    userId: string,
    request: PermissionCheckRequest
  ): Promise<PermissionCheckResponse> {
    try {
      const allowed = await this.checkPermission(
        userId,
        request.resource,
        request.action,
        request.context
      );

      if (!allowed) {
        return {
          allowed: false,
          reason: 'Insufficient permissions'
        };
      }

      // Get applicable conditions
      const permissions = await this.getUserPermissions(userId);
      const applicablePermission = permissions.find(p => 
        p.resource === request.resource && p.action === request.action
      );

      return {
        allowed: true,
        conditions: applicablePermission?.conditions
      };

    } catch (error) {
      logger.error('Permission check with context error:', error);
      return {
        allowed: false,
        reason: 'Permission check failed'
      };
    }
  }

  async requirePermission(
    userId: string,
    resource: string,
    action: string,
    context?: any
  ): Promise<void> {
    const hasPermission = await this.checkPermission(userId, resource, action, context);
    
    if (!hasPermission) {
      throw new InsufficientPermissionsError(resource, action);
    }
  }

  private async checkContextualPermission(
    userId: string,
    resource: string,
    action: string,
    context: any
  ): Promise<boolean> {
    try {
      // Get user permissions with conditions
      const permissions = await this.getUserPermissions(userId);
      
      const applicablePermissions = permissions.filter(p => 
        p.resource === resource && p.action === action
      );

      // Check if any permission allows access based on context
      for (const permission of applicablePermissions) {
        if (await this.evaluateConditions(permission.conditions, context, userId)) {
          return true;
        }
      }

      return false;

    } catch (error) {
      logger.error('Contextual permission check error:', error);
      return false;
    }
  }

  private async evaluateConditions(
    conditions: Record<string, any>,
    context: any,
    userId: string
  ): Promise<boolean> {
    try {
      // Simple condition evaluation - can be extended for complex rules
      if (!conditions || Object.keys(conditions).length === 0) {
        return true;
      }

      // Owner-based access
      if (conditions.owner && context.ownerId) {
        return context.ownerId === userId;
      }

      // Time-based access
      if (conditions.timeRange) {
        const now = new Date();
        const start = new Date(conditions.timeRange.start);
        const end = new Date(conditions.timeRange.end);
        return now >= start && now <= end;
      }

      // IP-based access
      if (conditions.allowedIps && context.ipAddress) {
        return conditions.allowedIps.includes(context.ipAddress);
      }

      // Department-based access
      if (conditions.department && context.userDepartment) {
        return conditions.department === context.userDepartment;
      }

      return true;

    } catch (error) {
      logger.error('Condition evaluation error:', error);
      return false;
    }
  }

  private async loadPoliciesFromDatabase(): Promise<void> {
    if (!this.enforcer) return;

    try {
      // Load user-role mappings
      const userRoles = await this.userRoleRepository.findAllActive();
      for (const userRole of userRoles) {
        const role = await this.roleRepository.findById(userRole.roleId);
        if (role) {
          await this.enforcer.addRoleForUser(userRole.userId, role.name);
        }
      }

      // Load role-permission mappings
      const rolePermissions = await this.rolePermissionRepository.findAll();
      for (const rolePermission of rolePermissions) {
        const role = await this.roleRepository.findById(rolePermission.roleId);
        const permission = await this.permissionRepository.findById(rolePermission.permissionId);
        
        if (role && permission) {
          await this.enforcer.addPermissionForUser(
            role.name,
            permission.resource,
            permission.action
          );
        }
      }

      logger.info('RBAC policies loaded from database');

    } catch (error) {
      logger.error('Failed to load policies from database:', error);
    }
  }

  private async addUserRole(userId: string, roleName: string): Promise<void> {
    if (this.enforcer) {
      await this.enforcer.addRoleForUser(userId, roleName);
    }
  }

  private async removeUserRole(userId: string, roleName: string): Promise<void> {
    if (this.enforcer) {
      await this.enforcer.deleteRoleForUser(userId, roleName);
    }
  }

  private async addRolePermission(
    roleName: string,
    resource: string,
    action: string
  ): Promise<void> {
    if (this.enforcer) {
      await this.enforcer.addPermissionForUser(roleName, resource, action);
    }
  }

  private async removeRolePermission(
    roleName: string,
    resource: string,
    action: string
  ): Promise<void> {
    if (this.enforcer) {
      await this.enforcer.deletePermission(roleName, resource, action);
    }
  }

  private async clearUserCache(userId: string): Promise<void> {
    const keys = [
      `user_permissions:${userId}`,
      `user_roles:${userId}`,
      `permission:${userId}:*`
    ];

    for (const key of keys) {
      if (key.includes('*')) {
        // Clear pattern-based keys
        const matchingKeys = await this.redisService.keys(key);
        if (matchingKeys.length > 0) {
          await this.redisService.deleteMultiple(matchingKeys);
        }
      } else {
        await this.redisService.delete(key);
      }
    }
  }

  private async clearRoleCache(roleId: string): Promise<void> {
    // Clear all user caches that might be affected by role changes
    const userRoles = await this.userRoleRepository.findByRoleId(roleId);
    
    for (const userRole of userRoles) {
      await this.clearUserCache(userRole.userId);
    }
  }
}
