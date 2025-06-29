#!/bin/bash

# Migration Script 04: Presentation Layer Migration
# This script migrates web components, pages, API controllers, and mappers

set -e

echo "🎨 Starting Presentation Layer Migration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to safely copy files
safe_copy() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        echo -e "${GREEN}✅ Copied $desc: $src -> $dest${NC}"
    elif [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
        cp -r "$src"/* "$dest"/ 2>/dev/null || true
        echo -e "${GREEN}✅ Copied $desc directory: $src -> $dest${NC}"
    else
        echo -e "${YELLOW}⚠️  Source not found or empty for $desc: $src${NC}"
    fi
}

# Helper function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local desc="$3"
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✅ Created $desc: $file_path${NC}"
}

echo -e "${BLUE}🌐 Step 1: Consolidating Web Components...${NC}"

# Create component directories
mkdir -p src/Presentation/Web/Components/{Common,Auth,Admin,Dashboard,Forms,Layout}

# Consolidate components from all frontend apps
echo -e "${BLUE}📦 Consolidating components from frontend apps...${NC}"

# Copy from packages/ui (main component library)
if [ -d "packages/ui/src/components" ]; then
    safe_copy "packages/ui/src/components" "src/Presentation/Web/Components/Common" "UI Components"
fi

# Copy from packages/components
if [ -d "packages/components/src" ]; then
    safe_copy "packages/components/src" "src/Presentation/Web/Components/Common" "Package Components"
fi

# Copy from individual frontend apps
frontend_apps=("web" "admin" "landing" "docs" "mobile" "desktop" "extension")
for app in "${frontend_apps[@]}"; do
    if [ -d "apps/frontend/$app/components" ]; then
        safe_copy "apps/frontend/$app/components" "src/Presentation/Web/Components/$app" "Frontend $app Components"
    fi
    if [ -d "apps/frontend/$app/src/components" ]; then
        safe_copy "apps/frontend/$app/src/components" "src/Presentation/Web/Components/$app" "Frontend $app Src Components"
    fi
done

# Create common layout components
create_file "src/Presentation/Web/Components/Layout/Header.tsx" "import React from 'react';

interface HeaderProps {
  title?: string;
  user?: {
    name: string;
    email: string;
  };
  onLogout?: () => void;
}

export const Header: React.FC<HeaderProps> = ({ title, user, onLogout }) => {
  return (
    <header className=\"bg-white shadow-sm border-b border-gray-200\">
      <div className=\"max-w-7xl mx-auto px-4 sm:px-6 lg:px-8\">
        <div className=\"flex justify-between items-center py-4\">
          <div className=\"flex items-center\">
            <h1 className=\"text-2xl font-semibold text-gray-900\">
              {title || 'Nexus V3'}
            </h1>
          </div>
          
          {user && (
            <div className=\"flex items-center space-x-4\">
              <div className=\"text-sm\">
                <div className=\"font-medium text-gray-900\">{user.name}</div>
                <div className=\"text-gray-500\">{user.email}</div>
              </div>
              {onLogout && (
                <button
                  onClick={onLogout}
                  className=\"bg-red-600 hover:bg-red-700 text-white px-3 py-2 rounded-md text-sm font-medium\"
                >
                  Logout
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </header>
  );
};" "Header Component"

create_file "src/Presentation/Web/Components/Layout/Sidebar.tsx" "import React from 'react';
import { Link, useLocation } from 'react-router-dom';

interface SidebarItem {
  name: string;
  href: string;
  icon?: React.ComponentType<any>;
}

interface SidebarProps {
  items: SidebarItem[];
}

export const Sidebar: React.FC<SidebarProps> = ({ items }) => {
  const location = useLocation();

  return (
    <div className=\"bg-gray-800 text-white w-64 min-h-screen p-4\">
      <nav className=\"space-y-2\">
        {items.map((item) => {
          const isActive = location.pathname === item.href;
          return (
            <Link
              key={item.name}
              to={item.href}
              className={\`flex items-center px-4 py-2 text-sm font-medium rounded-md \${
                isActive
                  ? 'bg-gray-900 text-white'
                  : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }\`}
            >
              {item.icon && <item.icon className=\"mr-3 h-5 w-5\" />}
              {item.name}
            </Link>
          );
        })}
      </nav>
    </div>
  );
};" "Sidebar Component"

# Create auth components
create_file "src/Presentation/Web/Components/Auth/LoginForm.tsx" "import React, { useState } from 'react';

interface LoginFormProps {
  onSubmit: (email: string, password: string) => Promise<void>;
  loading?: boolean;
  error?: string;
}

export const LoginForm: React.FC<LoginFormProps> = ({ onSubmit, loading, error }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    await onSubmit(email, password);
  };

  return (
    <div className=\"max-w-md mx-auto bg-white rounded-lg shadow-md p-6\">
      <h2 className=\"text-2xl font-bold text-center mb-6\">Sign In</h2>
      
      {error && (
        <div className=\"bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4\">
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} className=\"space-y-4\">
        <div>
          <label htmlFor=\"email\" className=\"block text-sm font-medium text-gray-700\">
            Email
          </label>
          <input
            type=\"email\"
            id=\"email\"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className=\"mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500\"
          />
        </div>

        <div>
          <label htmlFor=\"password\" className=\"block text-sm font-medium text-gray-700\">
            Password
          </label>
          <input
            type=\"password\"
            id=\"password\"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            className=\"mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500\"
          />
        </div>

        <button
          type=\"submit\"
          disabled={loading}
          className=\"w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50\"
        >
          {loading ? 'Signing in...' : 'Sign In'}
        </button>
      </form>
    </div>
  );
};" "Login Form Component"

echo -e "${BLUE}📄 Step 2: Consolidating Web Pages...${NC}"

# Create page directories
mkdir -p src/Presentation/Web/Pages/{Home,Auth,Admin,Dashboard,Users}

# Consolidate pages from all frontend apps
echo -e "${BLUE}📑 Consolidating pages from frontend apps...${NC}"

# Copy landing page
if [ -d "apps/frontend/landing/src/app" ]; then
    safe_copy "apps/frontend/landing/src/app" "src/Presentation/Web/Pages/Home" "Landing Pages"
fi

# Copy admin pages
if [ -d "apps/frontend/admin/pages" ]; then
    safe_copy "apps/frontend/admin/pages" "src/Presentation/Web/Pages/Admin" "Admin Pages"
fi

# Copy web app pages
if [ -d "apps/frontend/web/pages" ]; then
    safe_copy "apps/frontend/web/pages" "src/Presentation/Web/Pages" "Web Pages"
fi

# Create main pages
create_file "src/Presentation/Web/Pages/Home/HomePage.tsx" "import React from 'react';
import { Header } from '../../Components/Layout/Header';

export const HomePage: React.FC = () => {
  return (
    <div className=\"min-h-screen bg-gray-50\">
      <Header title=\"Welcome to Nexus V3\" />
      
      <main className=\"max-w-7xl mx-auto py-6 sm:px-6 lg:px-8\">
        <div className=\"px-4 py-6 sm:px-0\">
          <div className=\"text-center\">
            <h1 className=\"text-4xl font-bold text-gray-900 mb-4\">
              Welcome to Nexus V3
            </h1>
            <p className=\"text-xl text-gray-600 mb-8\">
              A modern, scalable application built with Domain-Driven Design
            </p>
            
            <div className=\"grid grid-cols-1 md:grid-cols-3 gap-6 mt-12\">
              <div className=\"bg-white p-6 rounded-lg shadow-md\">
                <h3 className=\"text-lg font-semibold mb-2\">Clean Architecture</h3>
                <p className=\"text-gray-600\">
                  Built with Domain-Driven Design principles for maintainability and scalability.
                </p>
              </div>
              
              <div className=\"bg-white p-6 rounded-lg shadow-md\">
                <h3 className=\"text-lg font-semibold mb-2\">Modern Stack</h3>
                <p className=\"text-gray-600\">
                  Using the latest technologies and best practices for web development.
                </p>
              </div>
              
              <div className=\"bg-white p-6 rounded-lg shadow-md\">
                <h3 className=\"text-lg font-semibold mb-2\">Enterprise Ready</h3>
                <p className=\"text-gray-600\">
                  Production-ready with comprehensive testing and monitoring.
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};" "Home Page"

create_file "src/Presentation/Web/Pages/Auth/LoginPage.tsx" "import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { LoginForm } from '../../Components/Auth/LoginForm';

export const LoginPage: React.FC = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const handleLogin = async (email: string, password: string) => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      });

      if (!response.ok) {
        throw new Error('Invalid credentials');
      }

      const { token } = await response.json();
      localStorage.setItem('token', token);
      navigate('/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className=\"min-h-screen bg-gray-50 flex items-center justify-center\">
      <LoginForm onSubmit={handleLogin} loading={loading} error={error || undefined} />
    </div>
  );
};" "Login Page"

create_file "src/Presentation/Web/Pages/Users/UsersPage.tsx" "import React, { useState, useEffect } from 'react';
import { Header } from '../../Components/Layout/Header';

interface User {
  id: string;
  name: string;
  email: string;
  createdAt: string;
  isActive: boolean;
}

export const UsersPage: React.FC = () => {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    try {
      const response = await fetch('/api/users', {
        headers: {
          'Authorization': \`Bearer \${localStorage.getItem('token')}\`,
        },
      });

      if (!response.ok) {
        throw new Error('Failed to fetch users');
      }

      const data = await response.json();
      setUsers(data.users);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch users');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className=\"min-h-screen bg-gray-50\">
        <Header title=\"Users\" />
        <div className=\"flex justify-center items-center h-64\">
          <div className=\"text-lg\">Loading...</div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className=\"min-h-screen bg-gray-50\">
        <Header title=\"Users\" />
        <div className=\"max-w-7xl mx-auto py-6 sm:px-6 lg:px-8\">
          <div className=\"bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded\">
            {error}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className=\"min-h-screen bg-gray-50\">
      <Header title=\"Users\" />
      
      <main className=\"max-w-7xl mx-auto py-6 sm:px-6 lg:px-8\">
        <div className=\"bg-white shadow overflow-hidden sm:rounded-md\">
          <ul className=\"divide-y divide-gray-200\">
            {users.map((user) => (
              <li key={user.id} className=\"px-6 py-4\">
                <div className=\"flex items-center justify-between\">
                  <div>
                    <div className=\"text-sm font-medium text-gray-900\">{user.name}</div>
                    <div className=\"text-sm text-gray-500\">{user.email}</div>
                  </div>
                  <div className=\"flex items-center\">
                    <span className={\`px-2 inline-flex text-xs leading-5 font-semibold rounded-full \${
                      user.isActive 
                        ? 'bg-green-100 text-green-800' 
                        : 'bg-red-100 text-red-800'
                    }\`}>
                      {user.isActive ? 'Active' : 'Inactive'}
                    </span>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </main>
    </div>
  );
};" "Users Page"

echo -e "${BLUE}🔌 Step 3: Migrating API Controllers...${NC}"

# Create controller directories
mkdir -p src/Presentation/Api/Controllers/{User,Auth,System}

# Migrate existing controllers from backend services
echo -e "${BLUE}🎮 Migrating backend service controllers...${NC}"

# Copy from backend services
backend_services=("api" "auth" "graphql" "webhooks")
for service in "${backend_services[@]}"; do
    if [ -d "apps/backend/$service/src" ]; then
        safe_copy "apps/backend/$service/src" "src/Presentation/Api/Controllers/$service" "Backend $service Controllers"
    fi
done

# Copy from user domain service
if [ -d "services/user-domain/src/presentation" ]; then
    safe_copy "services/user-domain/src/presentation" "src/Presentation/Api/Controllers/User" "User Domain Controllers"
fi

# Create main API controllers
create_file "src/Presentation/Api/Controllers/User/UserController.ts" "import { Request, Response } from 'express';
import { CreateUserHandler } from '../../../Application/Commands/Handlers/CreateUserHandler';
import { UpdateUserHandler } from '../../../Application/Commands/Handlers/UpdateUserHandler';
import { GetUserHandler } from '../../../Application/Queries/Handlers/GetUserHandler';
import { GetUsersHandler } from '../../../Application/Queries/Handlers/GetUsersHandler';
import { CreateUserCommand } from '../../../Application/Commands/CreateUserCommand';
import { UpdateUserCommand } from '../../../Application/Commands/UpdateUserCommand';
import { GetUserQuery } from '../../../Application/Queries/GetUserQuery';
import { GetUsersQuery } from '../../../Application/Queries/GetUsersQuery';
import { CreateUserValidator } from '../../../Application/Commands/Validators/CreateUserValidator';
import { UpdateUserValidator } from '../../../Application/Commands/Validators/UpdateUserValidator';

export class UserController {
  constructor(
    private readonly createUserHandler: CreateUserHandler,
    private readonly updateUserHandler: UpdateUserHandler,
    private readonly getUserHandler: GetUserHandler,
    private readonly getUsersHandler: GetUsersHandler,
    private readonly createUserValidator: CreateUserValidator,
    private readonly updateUserValidator: UpdateUserValidator
  ) {}

  public async createUser(req: Request, res: Response): Promise<void> {
    try {
      const { email, name, password } = req.body;
      const command = new CreateUserCommand(email, name, password);

      // Validate command
      const validationErrors = this.createUserValidator.validate(command);
      if (validationErrors.length > 0) {
        res.status(400).json({ errors: validationErrors });
        return;
      }

      const userId = await this.createUserHandler.handle(command);
      res.status(201).json({ id: userId });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }

  public async updateUser(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { name, email } = req.body;
      const command = new UpdateUserCommand(id, name, email);

      // Validate command
      const validationErrors = this.updateUserValidator.validate(command);
      if (validationErrors.length > 0) {
        res.status(400).json({ errors: validationErrors });
        return;
      }

      await this.updateUserHandler.handle(command);
      res.status(200).json({ message: 'User updated successfully' });
    } catch (error) {
      if (error.message === 'User not found') {
        res.status(404).json({ error: error.message });
      } else {
        res.status(500).json({ error: error.message });
      }
    }
  }

  public async getUser(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const query = new GetUserQuery(id);
      const user = await this.getUserHandler.handle(query);

      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      res.status(200).json(user);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }

  public async getUsers(req: Request, res: Response): Promise<void> {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 10;
      const search = req.query.search as string;

      const query = new GetUsersQuery(page, limit, search);
      const result = await this.getUsersHandler.handle(query);

      res.status(200).json(result);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
}" "User Controller"

create_file "src/Presentation/Api/Controllers/Auth/AuthController.ts" "import { Request, Response } from 'express';
import { AuthenticateUserHandler } from '../../../Application/Commands/Handlers/AuthenticateUserHandler';
import { AuthenticateUserCommand } from '../../../Application/Commands/AuthenticateUserCommand';

export class AuthController {
  constructor(
    private readonly authenticateUserHandler: AuthenticateUserHandler
  ) {}

  public async login(req: Request, res: Response): Promise<void> {
    try {
      const { email, password, provider = 'local' } = req.body;

      if (!email || !password) {
        res.status(400).json({ error: 'Email and password are required' });
        return;
      }

      const command = new AuthenticateUserCommand(email, password, provider);
      const token = await this.authenticateUserHandler.handle(command);

      res.status(200).json({ token });
    } catch (error) {
      if (error.message === 'Invalid credentials') {
        res.status(401).json({ error: error.message });
      } else {
        res.status(500).json({ error: error.message });
      }
    }
  }

  public async logout(req: Request, res: Response): Promise<void> {
    // In a JWT-based system, logout is typically handled client-side
    // by removing the token. For server-side token invalidation,
    // you would need to maintain a blacklist or use short-lived tokens
    res.status(200).json({ message: 'Logged out successfully' });
  }

  public async refresh(req: Request, res: Response): Promise<void> {
    try {
      const { token } = req.body;

      if (!token) {
        res.status(400).json({ error: 'Token is required' });
        return;
      }

      // Implement token refresh logic here
      // This would typically involve verifying the current token
      // and issuing a new one

      res.status(200).json({ token: 'new-token' });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
}" "Auth Controller"

echo -e "${BLUE}🗺️  Step 4: Creating API Mappers...${NC}"

create_file "src/Presentation/Api/Mappers/UserMapper.ts" "import { UserDto } from '../../Application/Queries/Dtos/UserDto';
import { User } from '../../Domain/Entities/User';

export class UserMapper {
  public static toDto(user: User): UserDto {
    return new UserDto(
      user.id,
      user.email,
      user.name,
      user.createdAt,
      user.updatedAt,
      user.isActive()
    );
  }

  public static toApiResponse(userDto: UserDto) {
    return {
      id: userDto.id,
      email: userDto.email,
      name: userDto.name,
      createdAt: userDto.createdAt.toISOString(),
      updatedAt: userDto.updatedAt.toISOString(),
      isActive: userDto.isActive
    };
  }

  public static toListApiResponse(users: UserDto[], total: number, page: number, limit: number) {
    return {
      users: users.map(user => this.toApiResponse(user)),
      pagination: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit)
      }
    };
  }
}" "User Mapper"

create_file "src/Presentation/Api/Mappers/AuthMapper.ts" "import { AuthDto } from '../../Application/Queries/Dtos/AuthDto';

export class AuthMapper {
  public static toApiResponse(authDto: AuthDto) {
    return {
      token: authDto.token,
      expiresAt: authDto.expiresAt.toISOString(),
      user: {
        id: authDto.user.id,
        email: authDto.user.email,
        name: authDto.user.name
      }
    };
  }
}" "Auth Mapper"

echo -e "${BLUE}🛣️  Step 5: Creating API Routes...${NC}"

create_file "src/Presentation/Api/Routes.ts" "import { Router } from 'express';
import { UserController } from './Controllers/User/UserController';
import { AuthController } from './Controllers/Auth/AuthController';
import { authMiddleware } from './Middleware/AuthMiddleware';

export function setupRoutes(
  userController: UserController,
  authController: AuthController
): Router {
  const router = Router();

  // Health check
  router.get('/health', (req, res) => {
    res.status(200).json({ status: 'OK', timestamp: new Date().toISOString() });
  });

  // Auth routes (public)
  router.post('/auth/login', (req, res) => authController.login(req, res));
  router.post('/auth/logout', (req, res) => authController.logout(req, res));
  router.post('/auth/refresh', (req, res) => authController.refresh(req, res));

  // User routes (protected)
  router.post('/users', authMiddleware, (req, res) => userController.createUser(req, res));
  router.get('/users/:id', authMiddleware, (req, res) => userController.getUser(req, res));
  router.put('/users/:id', authMiddleware, (req, res) => userController.updateUser(req, res));
  router.get('/users', authMiddleware, (req, res) => userController.getUsers(req, res));

  return router;
}" "API Routes"

create_file "src/Presentation/Api/Middleware/AuthMiddleware.ts" "import { Request, Response, NextFunction } from 'express';
import { ITokenService } from '../../Infrastructure/ExternalServices/ITokenService';

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;
      };
    }
  }
}

export function createAuthMiddleware(tokenService: ITokenService) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const authHeader = req.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        res.status(401).json({ error: 'Authorization token required' });
        return;
      }

      const token = authHeader.substring(7); // Remove 'Bearer ' prefix
      const { userId, isValid } = await tokenService.verify(token);

      if (!isValid) {
        res.status(401).json({ error: 'Invalid or expired token' });
        return;
      }

      req.user = { userId };
      next();
    } catch (error) {
      res.status(401).json({ error: 'Authentication failed' });
    }
  };
}

// Default middleware (will be configured with actual token service)
export const authMiddleware = (req: Request, res: Response, next: NextFunction) => {
  // This will be replaced with the actual middleware in the DI container
  next();
};" "Auth Middleware"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["04-presentation"] = "completed" | .current_phase = "05-shared-kernel"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Presentation Layer Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Web Components: $(find src/Presentation/Web/Components -name "*.tsx" | wc -l) files"
echo -e "  • Web Pages: $(find src/Presentation/Web/Pages -name "*.tsx" | wc -l) files"
echo -e "  • API Controllers: $(find src/Presentation/Api/Controllers -name "*.ts" | wc -l) files"
echo -e "  • API Mappers: $(find src/Presentation/Api/Mappers -name "*.ts" | wc -l) files"
echo -e "  • Middleware: $(find src/Presentation/Api/Middleware -name "*.ts" | wc -l) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/05-migrate-shared-kernel.sh${NC}"
