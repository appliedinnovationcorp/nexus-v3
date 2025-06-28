import { Repository } from '../../../../shared-kernel/src/domain/aggregate-root';
import { User } from '../../domain/user';

export interface UserRepository extends Repository<User> {
  findByEmail(email: string): Promise<User | null>;
  findByUsername(username: string): Promise<User | null>;
  findActiveUsers(): Promise<User[]>;
}
