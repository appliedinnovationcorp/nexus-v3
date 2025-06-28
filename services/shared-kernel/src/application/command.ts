// CQRS Command Pattern Implementation

export interface Command {
  readonly commandId: string;
  readonly timestamp: Date;
}

export interface CommandHandler<TCommand extends Command, TResult = void> {
  handle(command: TCommand): Promise<TResult>;
}

export interface CommandBus {
  execute<TCommand extends Command, TResult = void>(
    command: TCommand
  ): Promise<TResult>;
  register<TCommand extends Command, TResult = void>(
    commandType: new (...args: any[]) => TCommand,
    handler: CommandHandler<TCommand, TResult>
  ): void;
}

export class InMemoryCommandBus implements CommandBus {
  private handlers = new Map<string, CommandHandler<any, any>>();

  register<TCommand extends Command, TResult = void>(
    commandType: new (...args: any[]) => TCommand,
    handler: CommandHandler<TCommand, TResult>
  ): void {
    this.handlers.set(commandType.name, handler);
  }

  async execute<TCommand extends Command, TResult = void>(
    command: TCommand
  ): Promise<TResult> {
    const handler = this.handlers.get(command.constructor.name);
    if (!handler) {
      throw new Error(`No handler registered for command ${command.constructor.name}`);
    }
    return handler.handle(command);
  }
}

// Base Command Implementation
export abstract class BaseCommand implements Command {
  public readonly commandId: string;
  public readonly timestamp: Date;

  constructor() {
    this.commandId = crypto.randomUUID();
    this.timestamp = new Date();
  }
}
