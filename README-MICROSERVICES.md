# Microservices Architecture with Domain-Driven Design

## 🏗️ Architecture Overview

This implementation provides a comprehensive FOSS-only solution for microservices architecture with:

- **Hexagonal Architecture**: Clear separation of concerns with ports and adapters
- **Domain-Driven Design**: Bounded contexts with rich domain models
- **Event-Driven Architecture**: Apache Kafka for asynchronous communication
- **CQRS Pattern**: Separate read/write models with event sourcing
- **API Gateway**: Kong for request routing, rate limiting, and transformation
- **Service Mesh**: Kuma for service-to-service communication and observability

## 🛠️ Technology Stack

### Core Infrastructure
- **Message Queue**: Apache Kafka + Zookeeper
- **API Gateway**: Kong Gateway
- **Service Mesh**: Kuma (by Kong)
- **Service Discovery**: Consul
- **Event Store**: EventStore DB

### Data Layer
- **Write Database**: PostgreSQL (per service)
- **Read Database**: Redis (CQRS read models)
- **Event Storage**: EventStore DB

### Monitoring & Observability
- **Metrics**: Prometheus + Grafana
- **Tracing**: Jaeger
- **Logging**: Structured logging with Winston

## 📁 Project Structure

```
services/
├── shared-kernel/           # Shared domain models and patterns
│   ├── domain/             # Base entities, aggregates, events
│   └── application/        # CQRS command/query interfaces
├── user-domain/            # User management bounded context
│   ├── domain/             # User aggregate, value objects, events
│   ├── application/        # Commands, queries, handlers
│   ├── infrastructure/     # Repositories, event publishers
│   └── presentation/       # REST controllers, routes
├── order-domain/           # Order management bounded context
├── inventory-domain/       # Inventory management bounded context
└── payment-domain/         # Payment processing bounded context

infrastructure/
├── docker/                 # Docker Compose configurations
├── kong/                   # Kong Gateway configuration
├── kuma/                   # Service mesh policies
└── monitoring/             # Prometheus, Grafana configs
```

## 🚀 Quick Start

### 1. Setup Infrastructure

```bash
# Run the setup script
./scripts/setup-microservices.sh

# Start all infrastructure services
docker-compose -f infrastructure/docker/docker-compose.microservices.yml up -d
```

### 2. Initialize Services

```bash
# Create Kafka topics
./scripts/kafka/create-topics.sh

# Setup database schemas
./scripts/setup-databases.sh

# Configure Kong Gateway
./scripts/setup-kong.sh
```

### 3. Build and Deploy Services

```bash
# Build all services
pnpm build

# Start development mode
pnpm dev
```

## 🏛️ Domain-Driven Design Implementation

### Bounded Contexts

Each domain service represents a bounded context:

- **User Domain**: User registration, authentication, profile management
- **Order Domain**: Order creation, processing, fulfillment
- **Inventory Domain**: Product catalog, stock management
- **Payment Domain**: Payment processing, billing

### Hexagonal Architecture

Each service follows the hexagonal pattern:

```
Domain Core (Business Logic)
├── Entities & Value Objects
├── Aggregates & Domain Events
└── Domain Services

Application Layer (Use Cases)
├── Command Handlers (Write)
├── Query Handlers (Read)
└── Event Handlers

Infrastructure Layer (External Adapters)
├── Repositories (Database)
├── Event Publishers (Kafka)
└── External Services

Presentation Layer (API)
├── REST Controllers
├── GraphQL Resolvers
└── gRPC Services
```

### CQRS Implementation

- **Commands**: Modify state, published as domain events
- **Queries**: Read from optimized read models (Redis)
- **Event Sourcing**: Complete audit trail in EventStore
- **Projections**: Async updates to read models via Kafka events

## 🔄 Event-Driven Architecture

### Event Flow

1. **Command Execution**: Business logic executes, domain events generated
2. **Event Publishing**: Events published to Kafka topics
3. **Event Processing**: Other services consume and react to events
4. **Read Model Updates**: Projections update read models asynchronously

### Event Types

- **Domain Events**: Business-significant occurrences (UserCreated, OrderPlaced)
- **Integration Events**: Cross-boundary communication
- **System Events**: Infrastructure-level events

## 🌐 API Gateway (Kong)

### Features Configured

- **Rate Limiting**: Per-consumer and global limits
- **Request/Response Transformation**: Header injection, data transformation
- **Authentication**: API key authentication
- **CORS**: Cross-origin resource sharing
- **Monitoring**: Prometheus metrics integration

### Usage

```bash
# Create user via API Gateway
curl -X POST http://localhost:8000/api/v1/users \
  -H "Content-Type: application/json" \
  -H "X-API-Key: frontend-api-key-12345" \
  -d '{"email": "user@example.com", "username": "johndoe"}'

# Get user by ID
curl http://localhost:8000/api/v1/users/123 \
  -H "X-API-Key: frontend-api-key-12345"
```

## 🕸️ Service Mesh (Kuma)

### Capabilities

- **mTLS**: Automatic mutual TLS between services
- **Traffic Management**: Load balancing, circuit breaking, retries
- **Observability**: Metrics, tracing, logging
- **Security**: Traffic permissions, policies

### Service Communication

Services communicate through the mesh with:
- **HTTP**: REST APIs via Kong Gateway
- **gRPC**: Direct service-to-service communication
- **Events**: Asynchronous via Kafka

## 📊 Monitoring & Observability

### Metrics (Prometheus + Grafana)

- **Application Metrics**: Request rates, response times, error rates
- **Infrastructure Metrics**: CPU, memory, disk, network
- **Business Metrics**: User registrations, orders, revenue

### Distributed Tracing (Jaeger)

- **Request Tracing**: End-to-end request flow
- **Performance Analysis**: Bottleneck identification
- **Error Tracking**: Failure point analysis

### Access Points

- **Kong Gateway**: http://localhost:8000
- **Kong Admin**: http://localhost:8001
- **Kafka UI**: http://localhost:8080
- **Kuma GUI**: http://localhost:5685
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001 (admin/admin)
- **Jaeger**: http://localhost:16686
- **Consul**: http://localhost:8500
- **EventStore**: http://localhost:2113

## 🧪 Testing Strategy

### Unit Tests
- Domain logic testing
- Command/query handler testing
- Repository testing with mocks

### Integration Tests
- API endpoint testing
- Database integration testing
- Event publishing/consuming testing

### End-to-End Tests
- Full user journey testing
- Cross-service communication testing
- Performance testing

## 🔒 Security Considerations

### Authentication & Authorization
- API key authentication via Kong
- JWT tokens for user sessions
- Role-based access control (RBAC)

### Network Security
- mTLS between services via Kuma
- Network policies and traffic permissions
- Encrypted communication channels

### Data Security
- Database encryption at rest
- Sensitive data masking in logs
- Audit trails via event sourcing

## 📈 Scalability & Performance

### Horizontal Scaling
- Stateless service design
- Load balancing via Kong and Kuma
- Database read replicas

### Caching Strategy
- Redis for read model caching
- Kong response caching
- CDN for static assets

### Performance Optimization
- Connection pooling
- Async processing with Kafka
- Circuit breakers and timeouts

## 🚀 Deployment

### Development
```bash
docker-compose -f infrastructure/docker/docker-compose.microservices.yml up -d
```

### Production
- Kubernetes deployment with Helm charts
- CI/CD pipeline with automated testing
- Blue-green deployments
- Monitoring and alerting

## 📚 Best Practices

### Domain Modeling
- Rich domain models with behavior
- Value objects for data validation
- Aggregate boundaries for consistency

### Event Design
- Immutable events with versioning
- Idempotent event handlers
- Event replay capabilities

### Service Design
- Single responsibility per service
- Database per service
- Async communication preferred

### Monitoring
- Comprehensive logging
- Metrics for all operations
- Distributed tracing enabled

This architecture provides a solid foundation for building scalable, maintainable microservices with modern patterns and practices.
