# aic V3 Workspace

A comprehensive full-stack monorepo built with modern tools, best practices, and enterprise-grade compliance capabilities.

## 🚀 Quick Start

```bash
# Install dependencies
pnpm install

# Start development servers
pnpm dev

# Build all packages
pnpm build

# Run tests
pnpm test

# Start compliance infrastructure (optional)
cd compliance && docker-compose -f docker-compose.compliance.yml up -d
```

## 📁 Project Structure

- `apps/` - Deployable applications
- `packages/` - Shared libraries and utilities
- `tools/` - Development tools and scripts
- `docs/` - Project documentation
- `infrastructure/` - Infrastructure as Code
- `compliance/` - **NEW** Enterprise compliance system with GDPR, SOC 2, audit logging, and data retention

## 🛠 Tech Stack

### Core Platform
- **Frontend**: Next.js, React, TypeScript, Tailwind CSS
- **Backend**: Node.js, Express, GraphQL
- **Mobile**: React Native
- **Database**: PostgreSQL, Redis
- **Tools**: Turborepo, pnpm, ESLint, Prettier
- **Infrastructure**: AWS, Docker, Kubernetes

### Compliance & Security
- **Audit Logging**: Elasticsearch, Logstash, Kibana (ELK Stack)
- **Data Orchestration**: Apache Airflow
- **Policy Engine**: Open Policy Agent (OPA)
- **Monitoring**: Grafana, Prometheus
- **Anonymization**: Multi-algorithm privacy engine
- **Compliance**: GDPR, SOC 2 Type II, HIPAA, PCI DSS ready

## 🏛️ Compliance System

The workspace includes a comprehensive compliance toolkit built with 100% FOSS technologies:

### 🔧 Compliance Toolkit
- **Setup Manager** (`setup-compliance-system.sh`) - Complete infrastructure initialization
- **GDPR Toolkit** (`gdpr-compliance-toolkit.sh`) - Data subject rights, consent management, PIAs
- **SOC 2 Manager** (`soc2-control-manager.sh`) - Control testing, evidence collection, assessments
- **Audit Logger** (`audit-log-manager.sh`) - Enterprise audit logging with tamper-proof storage
- **Retention Manager** (`data-retention-manager.sh`) - Automated data lifecycle with legal holds

### 🚦 Quick Compliance Setup
```bash
# Initialize compliance system
./compliance/scripts/setup-compliance-system.sh

# Start compliance infrastructure
docker-compose -f compliance/docker-compose.compliance.yml up -d

# Access compliance dashboards
# - Kibana (Audit Logs): http://localhost:5601
# - Airflow (Data Retention): http://localhost:8081
# - Grafana (Compliance Metrics): http://localhost:3004
```

### 📊 Compliance Features
- **GDPR Compliance**: Automated data subject rights, consent management, breach response
- **SOC 2 Type II**: Complete control framework with continuous monitoring
- **Audit Logging**: Immutable audit trails with real-time threat detection
- **Data Retention**: Policy-driven lifecycle management with anonymization
- **Legal Hold Management**: Litigation hold integration across all data processing
- **Privacy by Design**: Built-in data minimization and purpose limitation

## 📚 Documentation

- [Architecture](./docs/architecture.md)
- [Deployment](./docs/deployment.md)
- [Contributing](./docs/contributing.md)
- [Compliance System](./compliance-system-toolkit.md) - **NEW** Comprehensive compliance guide

## 🤝 Contributing

Please read our [contributing guidelines](./docs/contributing.md) before submitting PRs.

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.
