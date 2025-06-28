import { randomUUID } from 'crypto';

export abstract class BaseEntity {
  protected readonly _id: string;
  protected readonly _createdAt: Date;
  protected _updatedAt: Date;
  private _domainEvents: DomainEvent[] = [];

  constructor(id?: string) {
    this._id = id || randomUUID();
    this._createdAt = new Date();
    this._updatedAt = new Date();
  }

  get id(): string {
    return this._id;
  }

  get createdAt(): Date {
    return this._createdAt;
  }

  get updatedAt(): Date {
    return this._updatedAt;
  }

  protected touch(): void {
    this._updatedAt = new Date();
  }

  protected addDomainEvent(event: DomainEvent): void {
    this._domainEvents.push(event);
  }

  public getDomainEvents(): DomainEvent[] {
    return [...this._domainEvents];
  }

  public clearDomainEvents(): void {
    this._domainEvents = [];
  }

  public equals(entity: BaseEntity): boolean {
    return this._id === entity._id;
  }
}

export abstract class DomainEvent {
  public readonly eventId: string;
  public readonly occurredOn: Date;
  public readonly aggregateId: string;
  public readonly eventVersion: number;

  constructor(aggregateId: string, eventVersion: number = 1) {
    this.eventId = randomUUID();
    this.occurredOn = new Date();
    this.aggregateId = aggregateId;
    this.eventVersion = eventVersion;
  }

  abstract getEventName(): string;
}
