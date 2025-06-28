import { BaseQuery, QueryHandler, ReadModel } from '../../../../shared-kernel/src/application/query';

export class GetUserQuery extends BaseQuery {
  constructor(public readonly userId: string) {
    super();
  }
}

export class GetUserByEmailQuery extends BaseQuery {
  constructor(public readonly email: string) {
    super();
  }
}

export interface UserReadModel extends ReadModel {
  readonly id: string;
  readonly email: string;
  readonly username: string;
  readonly status: string;
  readonly lastLoginAt?: Date;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface UserReadModelRepository {
  findById(id: string): Promise<UserReadModel | null>;
  findByEmail(email: string): Promise<UserReadModel | null>;
  findAll(limit?: number, offset?: number): Promise<UserReadModel[]>;
  save(user: UserReadModel): Promise<void>;
  update(id: string, updates: Partial<UserReadModel>): Promise<void>;
}

export class GetUserQueryHandler implements QueryHandler<GetUserQuery, UserReadModel | null> {
  constructor(private readonly userReadModelRepository: UserReadModelRepository) {}

  async handle(query: GetUserQuery): Promise<UserReadModel | null> {
    return this.userReadModelRepository.findById(query.userId);
  }
}

export class GetUserByEmailQueryHandler implements QueryHandler<GetUserByEmailQuery, UserReadModel | null> {
  constructor(private readonly userReadModelRepository: UserReadModelRepository) {}

  async handle(query: GetUserByEmailQuery): Promise<UserReadModel | null> {
    return this.userReadModelRepository.findByEmail(query.email);
  }
}
