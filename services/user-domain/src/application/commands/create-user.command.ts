import { BaseCommand, CommandHandler } from '../../../../shared-kernel/src/application/command';
import { User } from '../../domain/user';
import { UserRepository } from '../ports/user.repository';
import { EventPublisher } from '../ports/event-publisher';

export class CreateUserCommand extends BaseCommand {
  constructor(
    public readonly email: string,
    public readonly username: string
  ) {
    super();
  }
}

export class CreateUserCommandHandler implements CommandHandler<CreateUserCommand, string> {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly eventPublisher: EventPublisher
  ) {}

  async handle(command: CreateUserCommand): Promise<string> {
    // Check if user already exists
    const existingUser = await this.userRepository.findByEmail(command.email);
    if (existingUser) {
      throw new Error('User with this email already exists');
    }

    // Create new user
    const user = User.create(command.email, command.username);

    // Save user
    await this.userRepository.save(user);

    // Publish domain events
    const events = user.getDomainEvents();
    for (const event of events) {
      await this.eventPublisher.publish('user-domain', event);
    }

    // Mark events as committed
    user.markEventsAsCommitted();

    return user.id;
  }
}
