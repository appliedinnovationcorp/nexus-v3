import { DomainEvent } from '../../../../shared-kernel/src/domain/base-entity';

export interface EventPublisher {
  publish(topic: string, event: DomainEvent): Promise<void>;
  publishBatch(topic: string, events: DomainEvent[]): Promise<void>;
}

export interface EventSubscriber {
  subscribe(topic: string, handler: (event: DomainEvent) => Promise<void>): Promise<void>;
  unsubscribe(topic: string): Promise<void>;
}
