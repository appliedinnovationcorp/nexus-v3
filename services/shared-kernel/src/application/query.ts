// CQRS Query Pattern Implementation

export interface Query {
  readonly queryId: string;
  readonly timestamp: Date;
}

export interface QueryHandler<TQuery extends Query, TResult> {
  handle(query: TQuery): Promise<TResult>;
}

export interface QueryBus {
  execute<TQuery extends Query, TResult>(query: TQuery): Promise<TResult>;
  register<TQuery extends Query, TResult>(
    queryType: new (...args: any[]) => TQuery,
    handler: QueryHandler<TQuery, TResult>
  ): void;
}

export class InMemoryQueryBus implements QueryBus {
  private handlers = new Map<string, QueryHandler<any, any>>();

  register<TQuery extends Query, TResult>(
    queryType: new (...args: any[]) => TQuery,
    handler: QueryHandler<TQuery, TResult>
  ): void {
    this.handlers.set(queryType.name, handler);
  }

  async execute<TQuery extends Query, TResult>(query: TQuery): Promise<TResult> {
    const handler = this.handlers.get(query.constructor.name);
    if (!handler) {
      throw new Error(`No handler registered for query ${query.constructor.name}`);
    }
    return handler.handle(query);
  }
}

// Base Query Implementation
export abstract class BaseQuery implements Query {
  public readonly queryId: string;
  public readonly timestamp: Date;

  constructor() {
    this.queryId = crypto.randomUUID();
    this.timestamp = new Date();
  }
}

// Read Model Interface
export interface ReadModel {
  readonly id: string;
  readonly version: number;
  readonly lastUpdated: Date;
}

// Projection Interface for Event Sourcing
export interface Projection<TEvent, TReadModel extends ReadModel> {
  when(event: TEvent): Promise<void>;
  getReadModel(id: string): Promise<TReadModel | null>;
}
