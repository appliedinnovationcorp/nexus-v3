# Deployment Guide

## Overview

This guide covers deployment strategies for the Nexus Workspace monorepo across different environments.

## Prerequisites

- AWS CLI configured
- Docker installed
- kubectl configured (for Kubernetes)
- Terraform installed (for infrastructure)

## Environment Setup

### Development
```bash
# Start local services
docker-compose up -d

# Install dependencies
pnpm install

# Start development servers
pnpm dev
```

### Staging
```bash
# Deploy to staging environment
pnpm deploy:staging
```

### Production
```bash
# Deploy to production environment
pnpm deploy:production
```

## Infrastructure

### AWS Resources

#### Core Services
- **ECS Fargate**: Container orchestration
- **RDS PostgreSQL**: Primary database
- **ElastiCache Redis**: Caching layer
- **S3**: Static asset storage
- **CloudFront**: CDN
- **Route 53**: DNS management
- **ALB**: Load balancing

#### Security
- **IAM**: Access management
- **Secrets Manager**: Environment variables
- **WAF**: Web application firewall
- **Certificate Manager**: SSL/TLS certificates

### Terraform Configuration

```bash
# Initialize Terraform
cd infrastructure/terraform
terraform init

# Plan deployment
terraform plan

# Apply changes
terraform apply
```

## Container Deployment

### Docker Build
```bash
# Build production image
docker build -t nexus-app:latest .

# Tag for ECR
docker tag nexus-app:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/nexus-app:latest

# Push to ECR
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/nexus-app:latest
```

### ECS Deployment
```bash
# Update ECS service
aws ecs update-service \
  --cluster nexus-cluster \
  --service nexus-service \
  --force-new-deployment
```

## Database Migrations

### Running Migrations
```bash
# Run database migrations
pnpm db:migrate

# Seed database
pnpm db:seed
```

### Rollback
```bash
# Rollback last migration
pnpm db:rollback
```

## Environment Variables

### Required Variables
```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/db
REDIS_URL=redis://host:6379

# Authentication
JWT_SECRET=your-secret
NEXTAUTH_SECRET=your-secret

# AWS
AWS_REGION=us-east-1
S3_BUCKET_NAME=your-bucket
```

## Monitoring and Logging

### CloudWatch Setup
- Application logs
- Performance metrics
- Error tracking
- Custom dashboards

### Health Checks
```bash
# API health check
curl https://api.nexus.com/health

# Database health check
curl https://api.nexus.com/health/db
```

## CI/CD Pipeline

### GitHub Actions Workflow
1. **Code Push**: Trigger on main branch
2. **Tests**: Run unit and integration tests
3. **Build**: Create Docker image
4. **Deploy**: Update ECS service
5. **Verify**: Run smoke tests

### Manual Deployment
```bash
# Build and deploy specific app
pnpm build --filter=web
pnpm deploy --filter=web

# Deploy all apps
pnpm deploy:all
```

## Rollback Strategy

### Application Rollback
```bash
# Rollback to previous version
aws ecs update-service \
  --cluster nexus-cluster \
  --service nexus-service \
  --task-definition nexus-task:previous-revision
```

### Database Rollback
```bash
# Rollback database migration
pnpm db:rollback --steps=1
```

## Performance Optimization

### CDN Configuration
- Static assets cached at edge locations
- Dynamic content optimization
- Compression enabled

### Database Optimization
- Connection pooling
- Query optimization
- Read replicas for scaling

## Security Considerations

### SSL/TLS
- All traffic encrypted in transit
- Certificate auto-renewal
- HSTS headers enabled

### Access Control
- IAM roles with least privilege
- VPC security groups
- Network ACLs

## Troubleshooting

### Common Issues
1. **Container startup failures**: Check logs in CloudWatch
2. **Database connection issues**: Verify security groups
3. **High memory usage**: Monitor ECS metrics
4. **Slow API responses**: Check database performance

### Debug Commands
```bash
# View container logs
aws logs tail /aws/ecs/nexus-app --follow

# Check service status
aws ecs describe-services --cluster nexus-cluster --services nexus-service

# Monitor metrics
aws cloudwatch get-metric-statistics --namespace AWS/ECS
```
