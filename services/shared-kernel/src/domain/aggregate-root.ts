import { BaseEntity, DomainEvent } from './base-entity';

export abstract class AggregateRoot extends BaseEntity {
  private _version: number = 0;

  get version(): number {
    return this._version;
  }

  protected incrementVersion(): void {
    this._version++;
  }

  protected addDomainEvent(event: DomainEvent): void {
    super.addDomainEvent(event);
    this.incrementVersion();
  }

  public markEventsAsCommitted(): void {
    this.clearDomainEvents();
  }
}

export interface Repository<T extends AggregateRoot> {
  findById(id: string): Promise<T | null>;
  save(aggregate: T): Promise<void>;
  delete(id: string): Promise<void>;
}

export interface EventStore {
  saveEvents(aggregateId: string, events: DomainEvent[], expectedVersion: number): Promise<void>;
  getEvents(aggregateId: string): Promise<DomainEvent[]>;
  getAllEvents(): Promise<DomainEvent[]>;
}
