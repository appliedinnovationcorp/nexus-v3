import { AggregateRoot } from '../../../shared-kernel/src/domain/aggregate-root';
import { DomainEvent } from '../../../shared-kernel/src/domain/base-entity';

// Value Objects
export class Email {
  constructor(private readonly value: string) {
    if (!this.isValid(value)) {
      throw new Error('Invalid email format');
    }
  }

  private isValid(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  getValue(): string {
    return this.value;
  }

  equals(other: Email): boolean {
    return this.value === other.value;
  }
}

export class UserName {
  constructor(private readonly value: string) {
    if (!value || value.trim().length < 2) {
      throw new Error('Username must be at least 2 characters long');
    }
  }

  getValue(): string {
    return this.value;
  }

  equals(other: UserName): boolean {
    return this.value === other.value;
  }
}

// Domain Events
export class UserCreatedEvent extends DomainEvent {
  constructor(
    aggregateId: string,
    public readonly email: string,
    public readonly username: string,
    eventVersion: number = 1
  ) {
    super(aggregateId, eventVersion);
  }

  getEventName(): string {
    return 'UserCreated';
  }
}

export class UserEmailChangedEvent extends DomainEvent {
  constructor(
    aggregateId: string,
    public readonly oldEmail: string,
    public readonly newEmail: string,
    eventVersion: number = 1
  ) {
    super(aggregateId, eventVersion);
  }

  getEventName(): string {
    return 'UserEmailChanged';
  }
}

export class UserDeactivatedEvent extends DomainEvent {
  constructor(
    aggregateId: string,
    public readonly reason: string,
    eventVersion: number = 1
  ) {
    super(aggregateId, eventVersion);
  }

  getEventName(): string {
    return 'UserDeactivated';
  }
}

// User Aggregate
export enum UserStatus {
  ACTIVE = 'ACTIVE',
  INACTIVE = 'INACTIVE',
  SUSPENDED = 'SUSPENDED'
}

export class User extends AggregateRoot {
  private _email: Email;
  private _username: UserName;
  private _status: UserStatus;
  private _lastLoginAt?: Date;

  constructor(
    id: string,
    email: Email,
    username: UserName,
    status: UserStatus = UserStatus.ACTIVE
  ) {
    super(id);
    this._email = email;
    this._username = username;
    this._status = status;
  }

  static create(email: string, username: string): User {
    const emailVO = new Email(email);
    const usernameVO = new UserName(username);
    const user = new User(crypto.randomUUID(), emailVO, usernameVO);
    
    user.addDomainEvent(
      new UserCreatedEvent(user.id, email, username, user.version)
    );
    
    return user;
  }

  get email(): Email {
    return this._email;
  }

  get username(): UserName {
    return this._username;
  }

  get status(): UserStatus {
    return this._status;
  }

  get lastLoginAt(): Date | undefined {
    return this._lastLoginAt;
  }

  changeEmail(newEmail: string): void {
    const newEmailVO = new Email(newEmail);
    const oldEmail = this._email.getValue();
    
    if (this._email.equals(newEmailVO)) {
      return; // No change needed
    }

    this._email = newEmailVO;
    this.touch();
    
    this.addDomainEvent(
      new UserEmailChangedEvent(this.id, oldEmail, newEmail, this.version)
    );
  }

  deactivate(reason: string): void {
    if (this._status === UserStatus.INACTIVE) {
      return; // Already inactive
    }

    this._status = UserStatus.INACTIVE;
    this.touch();
    
    this.addDomainEvent(
      new UserDeactivatedEvent(this.id, reason, this.version)
    );
  }

  recordLogin(): void {
    this._lastLoginAt = new Date();
    this.touch();
  }

  isActive(): boolean {
    return this._status === UserStatus.ACTIVE;
  }

  canLogin(): boolean {
    return this._status === UserStatus.ACTIVE;
  }
}
