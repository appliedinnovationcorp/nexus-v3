import { Pool, PoolClient } from 'pg';
import { UserRepository } from '../application/ports/user.repository';
import { User, UserStatus, Email, UserName } from '../domain/user';

interface UserRow {
  id: string;
  email: string;
  username: string;
  status: string;
  last_login_at?: Date;
  created_at: Date;
  updated_at: Date;
  version: number;
}

export class PostgresUserRepository implements UserRepository {
  constructor(private readonly pool: Pool) {}

  async findById(id: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM users WHERE id = $1',
        [id]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return this.mapRowToUser(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async findByEmail(email: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM users WHERE email = $1',
        [email]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return this.mapRowToUser(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async findByUsername(username: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM users WHERE username = $1',
        [username]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return this.mapRowToUser(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async findActiveUsers(): Promise<User[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT * FROM users WHERE status = $1 ORDER BY created_at DESC',
        [UserStatus.ACTIVE]
      );

      return result.rows.map(row => this.mapRowToUser(row));
    } finally {
      client.release();
    }
  }

  async save(user: User): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Check if user exists
      const existingResult = await client.query(
        'SELECT version FROM users WHERE id = $1',
        [user.id]
      );

      if (existingResult.rows.length === 0) {
        // Insert new user
        await client.query(`
          INSERT INTO users (id, email, username, status, last_login_at, created_at, updated_at, version)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        `, [
          user.id,
          user.email.getValue(),
          user.username.getValue(),
          user.status,
          user.lastLoginAt,
          user.createdAt,
          user.updatedAt,
          user.version
        ]);
      } else {
        // Update existing user with optimistic locking
        const currentVersion = existingResult.rows[0].version;
        
        const updateResult = await client.query(`
          UPDATE users 
          SET email = $2, username = $3, status = $4, last_login_at = $5, 
              updated_at = $6, version = $7
          WHERE id = $1 AND version = $8
        `, [
          user.id,
          user.email.getValue(),
          user.username.getValue(),
          user.status,
          user.lastLoginAt,
          user.updatedAt,
          user.version,
          currentVersion
        ]);

        if (updateResult.rowCount === 0) {
          throw new Error('Optimistic locking failure: User was modified by another process');
        }
      }

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async delete(id: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('DELETE FROM users WHERE id = $1', [id]);
    } finally {
      client.release();
    }
  }

  private mapRowToUser(row: UserRow): User {
    const email = new Email(row.email);
    const username = new UserName(row.username);
    const status = row.status as UserStatus;

    const user = new User(row.id, email, username, status);
    
    // Set private fields using reflection or a factory method
    // This is a simplified approach - in practice, you might need
    // a more sophisticated mapping strategy
    (user as any)._createdAt = row.created_at;
    (user as any)._updatedAt = row.updated_at;
    (user as any)._lastLoginAt = row.last_login_at;
    (user as any)._version = row.version;

    return user;
  }
}

// Database schema migration
export const createUserTableSQL = `
  CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    last_login_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL DEFAULT 0
  );

  CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
  CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
  CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
`;
