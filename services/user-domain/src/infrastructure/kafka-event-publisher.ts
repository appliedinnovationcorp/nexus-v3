import { Kafka, Producer, Consumer } from 'kafkajs';
import { EventPublisher, EventSubscriber } from '../application/ports/event-publisher';
import { DomainEvent } from '../../../shared-kernel/src/domain/base-entity';

export class KafkaEventPublisher implements EventPublisher, EventSubscriber {
  private kafka: Kafka;
  private producer: Producer;
  private consumer: Consumer;
  private isConnected = false;

  constructor(
    private readonly brokers: string[],
    private readonly clientId: string,
    private readonly groupId: string
  ) {
    this.kafka = new Kafka({
      clientId: this.clientId,
      brokers: this.brokers,
      retry: {
        initialRetryTime: 100,
        retries: 8
      }
    });
    
    this.producer = this.kafka.producer({
      maxInFlightRequests: 1,
      idempotent: true,
      transactionTimeout: 30000
    });
    
    this.consumer = this.kafka.consumer({
      groupId: this.groupId,
      sessionTimeout: 30000,
      rebalanceTimeout: 60000,
      heartbeatInterval: 3000
    });
  }

  async connect(): Promise<void> {
    if (this.isConnected) return;

    await Promise.all([
      this.producer.connect(),
      this.consumer.connect()
    ]);
    
    this.isConnected = true;
  }

  async disconnect(): Promise<void> {
    if (!this.isConnected) return;

    await Promise.all([
      this.producer.disconnect(),
      this.consumer.disconnect()
    ]);
    
    this.isConnected = false;
  }

  async publish(topic: string, event: DomainEvent): Promise<void> {
    await this.ensureConnected();

    const message = {
      key: event.aggregateId,
      value: JSON.stringify({
        eventId: event.eventId,
        eventName: event.getEventName(),
        aggregateId: event.aggregateId,
        eventVersion: event.eventVersion,
        occurredOn: event.occurredOn.toISOString(),
        data: event
      }),
      headers: {
        eventType: event.getEventName(),
        aggregateId: event.aggregateId,
        eventVersion: event.eventVersion.toString(),
        timestamp: event.occurredOn.toISOString()
      }
    };

    await this.producer.send({
      topic,
      messages: [message]
    });
  }

  async publishBatch(topic: string, events: DomainEvent[]): Promise<void> {
    await this.ensureConnected();

    const messages = events.map(event => ({
      key: event.aggregateId,
      value: JSON.stringify({
        eventId: event.eventId,
        eventName: event.getEventName(),
        aggregateId: event.aggregateId,
        eventVersion: event.eventVersion,
        occurredOn: event.occurredOn.toISOString(),
        data: event
      }),
      headers: {
        eventType: event.getEventName(),
        aggregateId: event.aggregateId,
        eventVersion: event.eventVersion.toString(),
        timestamp: event.occurredOn.toISOString()
      }
    }));

    await this.producer.send({
      topic,
      messages
    });
  }

  async subscribe(topic: string, handler: (event: DomainEvent) => Promise<void>): Promise<void> {
    await this.ensureConnected();

    await this.consumer.subscribe({ topic, fromBeginning: false });

    await this.consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          if (!message.value) return;

          const eventData = JSON.parse(message.value.toString());
          const event = this.deserializeEvent(eventData);
          
          await handler(event);
        } catch (error) {
          console.error(`Error processing message from topic ${topic}:`, error);
          // Implement dead letter queue or retry logic here
        }
      }
    });
  }

  async unsubscribe(topic: string): Promise<void> {
    // Kafka consumer doesn't have direct unsubscribe for single topic
    // You would need to manage subscriptions at application level
    await this.consumer.stop();
  }

  private async ensureConnected(): Promise<void> {
    if (!this.isConnected) {
      await this.connect();
    }
  }

  private deserializeEvent(eventData: any): DomainEvent {
    // This is a simplified deserialization
    // In a real implementation, you'd have a proper event registry
    // and deserialization strategy based on event type
    return eventData.data as DomainEvent;
  }
}
