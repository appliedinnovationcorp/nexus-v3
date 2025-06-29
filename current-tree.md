.
├── ADVANCED-CICD-PIPELINE-REPORT.md
├── advanced-tooling
│   ├── automation
│   ├── chromatic
│   ├── codegen
│   ├── config
│   ├── docker
│   ├── docker-compose.advanced-tooling.yml
│   ├── docs
│   ├── husky
│   ├── scripts
│   │   └── setup-advanced-tooling.sh
│   ├── storybook
│   └── templates
│       └── Button.stories.tsx
├── ADVANCED-TOOLING-SYSTEM-REPORT.md
├── alerting
│   ├── config
│   │   ├── alertmanager
│   │   │   └── config.yml
│   │   ├── chaos
│   │   │   └── chaos-experiments.yaml
│   │   ├── falco
│   │   │   └── falco_rules.yaml
│   │   ├── pyrra
│   │   │   └── slo-config.yaml
│   │   └── sloth
│   │       └── performance-budgets.yaml
│   ├── docker-compose.alerting.yml
│   └── scripts
│       ├── incident-response.sh
│       └── setup-alerting.sh
├── ALERTING-INCIDENT-MANAGEMENT-REPORT.md
├── apps
│   ├── backend
│   │   ├── api
│   │   │   ├── nest-cli.json
│   │   │   ├── package.json
│   │   │   ├── src
│   │   │   │   ├── app.module.ts
│   │   │   │   └── main.ts
│   │   │   ├── tsconfig.build.json
│   │   │   └── tsconfig.json
│   │   ├── auth
│   │   │   ├── nest-cli.json
│   │   │   ├── package.json
│   │   │   ├── src
│   │   │   │   ├── app.module.ts
│   │   │   │   └── main.ts
│   │   │   ├── tsconfig.build.json
│   │   │   └── tsconfig.json
│   │   ├── cron
│   │   │   ├── nest-cli.json
│   │   │   ├── package.json
│   │   │   ├── src
│   │   │   │   ├── app.module.ts
│   │   │   │   └── main.ts
│   │   │   ├── tsconfig.build.json
│   │   │   └── tsconfig.json
│   │   ├── graphql
│   │   │   ├── nest-cli.json
│   │   │   ├── package.json
│   │   │   ├── src
│   │   │   │   ├── app.module.ts
│   │   │   │   └── main.ts
│   │   │   ├── tsconfig.build.json
│   │   │   └── tsconfig.json
│   │   ├── node_modules
│   │   ├── webhooks
│   │   │   ├── nest-cli.json
│   │   │   ├── package.json
│   │   │   ├── src
│   │   │   │   ├── app.module.ts
│   │   │   │   └── main.ts
│   │   │   ├── tsconfig.build.json
│   │   │   └── tsconfig.json
│   │   └── workers
│   │       ├── nest-cli.json
│   │       ├── package.json
│   │       ├── src
│   │       │   ├── app.module.ts
│   │       │   └── main.ts
│   │       ├── tsconfig.build.json
│   │       └── tsconfig.json
│   ├── cli
│   │   ├── eslint.config.mjs
│   │   ├── next.config.ts
│   │   ├── next-env.d.ts
│   │   ├── package.json
│   │   ├── postcss.config.mjs
│   │   ├── public
│   │   │   ├── file.svg
│   │   │   ├── globe.svg
│   │   │   ├── next.svg
│   │   │   ├── vercel.svg
│   │   │   └── window.svg
│   │   ├── README.md
│   │   ├── src
│   │   │   └── app
│   │   │       ├── favicon.ico
│   │   │       ├── globals.css
│   │   │       ├── layout.tsx
│   │   │       └── page.tsx
│   │   └── tsconfig.json
│   └── frontend
│       ├── admin
│       │   ├── components
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── pages
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   ├── styles
│       │   └── tsconfig.json
│       ├── client-portal
│       │   ├── components
│       │   ├── pages
│       │   ├── public
│       │   └── styles
│       ├── desktop
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   └── tsconfig.json
│       ├── developer-portal
│       │   ├── components
│       │   ├── pages
│       │   ├── public
│       │   └── styles
│       ├── docs
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   └── tsconfig.json
│       ├── extension
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   └── tsconfig.json
│       ├── investor-portal
│       │   ├── components
│       │   ├── pages
│       │   ├── public
│       │   └── styles
│       ├── landing
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   └── tsconfig.json
│       ├── mobile
│       │   ├── eslint.config.mjs
│       │   ├── next.config.ts
│       │   ├── next-env.d.ts
│       │   ├── package.json
│       │   ├── postcss.config.mjs
│       │   ├── public
│       │   │   ├── file.svg
│       │   │   ├── globe.svg
│       │   │   ├── next.svg
│       │   │   ├── vercel.svg
│       │   │   └── window.svg
│       │   ├── README.md
│       │   ├── src
│       │   │   └── app
│       │   │       ├── favicon.ico
│       │   │       ├── globals.css
│       │   │       ├── layout.tsx
│       │   │       └── page.tsx
│       │   └── tsconfig.json
│       ├── node_modules
│       ├── storybook
│       │   ├── dist
│       │   ├── package.json
│       │   ├── src
│       │   └── tsconfig.json
│       └── web
│           ├── components
│           ├── eslint.config.mjs
│           ├── next.config.ts
│           ├── next-env.d.ts
│           ├── package.json
│           ├── pages
│           ├── postcss.config.mjs
│           ├── public
│           │   ├── file.svg
│           │   ├── globe.svg
│           │   ├── next.svg
│           │   ├── vercel.svg
│           │   └── window.svg
│           ├── README.md
│           ├── src
│           │   └── app
│           │       ├── favicon.ico
│           │       ├── globals.css
│           │       ├── layout.tsx
│           │       └── page.tsx
│           ├── styles
│           └── tsconfig.json
├── architecture
│   └── microservices-ddd-design.md
├── Architecture-Design-Patterns.md
├── auth
│   ├── architecture
│   │   └── auth-strategy.md
│   ├── docker-compose.auth.yml
│   ├── scripts
│   │   ├── init-auth-db.sql
│   │   └── setup-auth-system.sh
│   └── services
│       └── auth-service
│           ├── Dockerfile
│           ├── package.json
│           └── src
│               ├── config
│               │   └── rbac_model.conf
│               ├── middleware
│               │   └── auth.middleware.ts
│               ├── services
│               │   ├── api-key.service.ts
│               │   ├── auth.service.ts
│               │   ├── mfa.service.ts
│               │   └── rbac.service.ts
│               └── types
│                   └── auth.types.ts
├── Authentication-Authorization-System.md
├── backend-performance
│   ├── caching
│   ├── config
│   ├── docker
│   │   └── backend-api
│   │       └── src
│   │           ├── middleware
│   │           ├── routes
│   │           └── services
│   │               ├── CacheService.js
│   │               └── QueueService.js
│   ├── docker-compose.backend-performance.yml
│   ├── monitoring
│   ├── optimization
│   ├── queues
│   ├── scripts
│   │   └── setup-backend-performance.sh
│   └── sql
│       ├── indexes.sql
│       └── init-performance.sql
├── BACKEND-PERFORMANCE-SYSTEM-REPORT.md
├── cicd
│   ├── config
│   │   ├── argocd
│   │   │   └── applications
│   │   │       └── nexus-v3-dev.yaml
│   │   ├── jenkins
│   │   │   └── Jenkinsfile.multistage
│   │   ├── k6
│   │   │   └── performance-test.js
│   │   ├── k8s
│   │   │   └── rollouts
│   │   │       ├── bluegreen-rollout.yaml
│   │   │       └── canary-rollout.yaml
│   │   └── terraform
│   │       └── main.tf
│   ├── docker-compose.cicd.yml
│   └── scripts
│       └── setup-cicd.sh
├── compliance
│   ├── architecture
│   │   └── compliance-strategy.md
│   ├── dags
│   │   └── data_retention_dag.py
│   ├── docker-compose.compliance.yml
│   ├── scripts
│   │   ├── audit
│   │   │   └── audit-log-manager.sh
│   │   ├── gdpr
│   │   │   └── gdpr-compliance-toolkit.sh
│   │   ├── retention
│   │   │   └── data-retention-manager.sh
│   │   ├── setup-compliance-system.sh
│   │   └── soc2
│   │       └── soc2-control-manager.sh
│   └── services
│       ├── anonymization-service
│       │   └── src
│       │       └── services
│       │           └── anonymization.service.ts
│       └── compliance-service
│           └── src
│               └── services
│                   ├── gdpr.service.ts
│                   └── soc2.service.ts
├── compliance-system-toolkit.md
├── CONTAINER-ORCHESTRATION-REPORT.md
├── containers
│   ├── docker
│   │   └── Dockerfile.multistage
│   ├── k8s
│   │   ├── autoscaling
│   │   │   └── hpa-vpa.yaml
│   │   ├── helm
│   │   │   └── nexus-v3
│   │   │       ├── Chart.yaml
│   │   │       ├── templates
│   │   │       │   └── deployment.yaml
│   │   │       └── values.yaml
│   │   ├── security
│   │   │   ├── network-policies.yaml
│   │   │   └── pod-security-policy.yaml
│   │   └── service-mesh
│   │       └── istio-config.yaml
│   └── scripts
│       └── setup-containers.sh
├── current-tree.md
├── database
│   ├── architecture
│   │   └── database-strategy.md
│   ├── config
│   │   ├── clickhouse
│   │   │   ├── config.xml
│   │   │   └── users.xml
│   │   ├── haproxy
│   │   │   └── haproxy.cfg
│   │   ├── pgbouncer
│   │   │   ├── pgbouncer.ini
│   │   │   └── userlist.txt
│   │   └── postgresql
│   │       ├── primary
│   │       │   ├── pg_hba.conf
│   │       │   └── postgresql.conf
│   │       └── replica
│   │           └── postgresql.conf
│   ├── docker-compose.database.yml
│   ├── migrations
│   │   └── sql
│   │       ├── V1__Initial_Schema.sql
│   │       └── V2__Add_Partitioning.sql
│   └── scripts
│       ├── backup-manager.sh
│       ├── clickhouse
│       │   └── init.sql
│       ├── database-manager.ts
│       ├── postgresql
│       │   ├── init-primary.sh
│       │   ├── init-replica.sh
│       │   └── init-shard.sh
│       └── setup-database-architecture.sh
├── Database-Architecture.md
├── docker-compose.yml
├── Dockerfile
├── Dockerfile.backend
├── Dockerfile.frontend
├── docs
│   ├── architecture.md
│   ├── deployment.md
│   ├── eslint.config.mjs
│   ├── next.config.ts
│   ├── next-env.d.ts
│   ├── package.json
│   ├── postcss.config.mjs
│   ├── public
│   │   ├── file.svg
│   │   ├── globe.svg
│   │   ├── next.svg
│   │   ├── vercel.svg
│   │   └── window.svg
│   ├── README.md
│   ├── src
│   │   └── app
│   │       ├── favicon.ico
│   │       ├── globals.css
│   │       ├── layout.tsx
│   │       └── page.tsx
│   └── tsconfig.json
├── fix-package-names.sh
├── frontend-optimization
│   ├── cdn
│   ├── config
│   ├── docker
│   │   └── perf-monitor
│   │       ├── Dockerfile
│   │       ├── package.json
│   │       └── src
│   │           └── index.js
│   ├── docker-compose.frontend-optimization.yml
│   ├── optimization
│   ├── pwa
│   │   ├── manifest.json
│   │   └── service-worker.js
│   ├── scripts
│   │   └── setup-frontend-optimization.sh
│   ├── sql
│   │   └── perf-init.sql
│   └── templates
│       └── next.config.js
├── FRONTEND-OPTIMIZATION-SYSTEM-REPORT.md
├── infrastructure
│   ├── aws
│   │   ├── cdk
│   │   ├── cloudformation
│   │   └── terraform
│   ├── docker
│   │   ├── api.Dockerfile
│   │   ├── docker-compose.microservices.yml
│   │   └── web.Dockerfile
│   ├── k8s
│   │   ├── deployments
│   │   │   └── web-deployment.yaml
│   │   ├── ingress
│   │   └── services
│   │       └── web-service.yaml
│   ├── kong
│   │   └── kong.yml
│   ├── kuma
│   │   └── mesh.yaml
│   └── monitoring
│       └── prometheus.yml
├── infrastructure-scaling
│   ├── ansible
│   ├── config
│   ├── docker
│   ├── docker-compose.infrastructure-scaling.yml
│   ├── edge
│   ├── kubernetes
│   │   └── manifests
│   │       └── auto-scaler-deployment.yaml
│   ├── monitoring
│   ├── scripts
│   │   └── setup-infrastructure-scaling.sh
│   └── terraform
│       └── main.tf
├── INFRASTRUCTURE-SCALING-SYSTEM-REPORT.md
├── microservices-architecture.md
├── monitoring
│   ├── config
│   │   ├── alertmanager
│   │   │   └── config.yml
│   │   ├── blackbox
│   │   │   └── config.yml
│   │   ├── grafana
│   │   │   └── provisioning
│   │   │       ├── dashboards
│   │   │       │   └── dashboards.yml
│   │   │       └── datasources
│   │   │           └── datasources.yml
│   │   ├── logstash
│   │   │   ├── logstash.yml
│   │   │   └── pipeline.conf
│   │   ├── otel
│   │   │   └── otel-collector-config.yaml
│   │   ├── prometheus
│   │   │   ├── prometheus.yml
│   │   │   └── rules
│   │   │       └── alerts.yml
│   │   └── vector
│   │       └── vector.toml
│   ├── docker-compose.monitoring.yml
│   └── scripts
│       ├── apm-integration.sh
│       └── setup-monitoring.sh
├── MONITORING-STACK-REPORT.md
├── package.json
├── packages
│   ├── api
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── auth
│   │   ├── dist
│   │   │   ├── index.d.ts
│   │   │   ├── index.d.ts.map
│   │   │   ├── index.js
│   │   │   └── index.js.map
│   │   ├── node_modules
│   │   │   ├── @aic
│   │   │   │   ├── eslint-config -> ../../../eslint-config
│   │   │   │   ├── prettier-config -> ../../../prettier-config
│   │   │   │   ├── tsconfig -> ../../../tsconfig
│   │   │   │   ├── types -> ../../../types
│   │   │   │   └── utils -> ../../../utils
│   │   │   ├── bcryptjs -> ../../../node_modules/.pnpm/bcryptjs@2.4.3/node_modules/bcryptjs
│   │   │   ├── jest -> ../../../node_modules/.pnpm/jest@29.7.0/node_modules/jest
│   │   │   ├── jsonwebtoken -> ../../../node_modules/.pnpm/jsonwebtoken@9.0.2/node_modules/jsonwebtoken
│   │   │   ├── next-auth -> ../../../node_modules/.pnpm/next-auth@4.24.11_next@15.3.4_react-dom@19.1.0_react@19.1.0/node_modules/next-auth
│   │   │   ├── @types
│   │   │   │   ├── bcryptjs -> ../../../../node_modules/.pnpm/@types+bcryptjs@2.4.6/node_modules/@types/bcryptjs
│   │   │   │   ├── jest -> ../../../../node_modules/.pnpm/@types+jest@29.5.14/node_modules/@types/jest
│   │   │   │   └── jsonwebtoken -> ../../../../node_modules/.pnpm/@types+jsonwebtoken@9.0.10/node_modules/@types/jsonwebtoken
│   │   │   └── typescript -> ../../../node_modules/.pnpm/typescript@5.8.3/node_modules/typescript
│   │   ├── package.json
│   │   ├── src
│   │   │   └── index.ts
│   │   ├── tsconfig.json
│   │   └── tsconfig.tsbuildinfo
│   ├── build-tools
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── components
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── config
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── constants
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── database
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   │   └── migrations
│   │   └── tsconfig.json
│   ├── design-tokens
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── eslint-config
│   │   ├── dist
│   │   ├── index.js
│   │   ├── package.json
│   │   ├── react.js
│   │   └── src
│   ├── icons
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── prettier-config
│   │   ├── dist
│   │   ├── index.js
│   │   ├── package.json
│   │   └── src
│   ├── services
│   │   ├── dist
│   │   ├── package.json
│   │   ├── src
│   │   └── tsconfig.json
│   ├── tsconfig
│   │   ├── base.json
│   │   ├── dist
│   │   ├── package.json
│   │   ├── react.json
│   │   ├── react-native.json
│   │   └── src
│   ├── types
│   │   ├── dist
│   │   │   ├── index.js
│   │   │   ├── index.js.map
│   │   │   ├── index.mjs
│   │   │   └── index.mjs.map
│   │   ├── package.json
│   │   ├── src
│   │   │   ├── api.ts
│   │   │   ├── common.ts
│   │   │   ├── index.ts
│   │   │   └── user.ts
│   │   ├── tsconfig.build.json
│   │   ├── tsconfig.json
│   │   └── tsup.config.ts
│   ├── ui
│   │   ├── dist
│   │   │   ├── index.js
│   │   │   ├── index.js.map
│   │   │   ├── index.mjs
│   │   │   └── index.mjs.map
│   │   ├── package.json
│   │   ├── src
│   │   │   ├── components
│   │   │   │   ├── Button
│   │   │   │   │   ├── Button.stories.tsx
│   │   │   │   │   ├── Button.test.tsx
│   │   │   │   │   ├── Button.tsx
│   │   │   │   │   └── index.ts
│   │   │   │   ├── Card
│   │   │   │   ├── Input
│   │   │   │   └── Modal
│   │   │   ├── hooks
│   │   │   ├── index.ts
│   │   │   └── utils
│   │   │       └── cn.ts
│   │   ├── tsconfig.build.json
│   │   ├── tsconfig.json
│   │   └── tsup.config.ts
│   ├── utils
│   │   ├── dist
│   │   │   ├── index.js
│   │   │   ├── index.js.map
│   │   │   ├── index.mjs
│   │   │   └── index.mjs.map
│   │   ├── package.json
│   │   ├── src
│   │   │   ├── date.ts
│   │   │   ├── index.ts
│   │   │   ├── string.ts
│   │   │   └── validation.ts
│   │   ├── tests
│   │   ├── tsconfig.build.json
│   │   ├── tsconfig.json
│   │   └── tsup.config.ts
│   └── validators
│       ├── dist
│       ├── package.json
│       ├── src
│       └── tsconfig.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
├── quality-gates
│   ├── config
│   │   ├── grafana
│   │   │   ├── dashboards
│   │   │   │   └── quality-gates-dashboard.json
│   │   │   └── provisioning
│   │   ├── lighthouse
│   │   ├── orchestrator
│   │   ├── pa11y
│   │   ├── prometheus
│   │   ├── semgrep
│   │   ├── sonarqube
│   │   └── zap
│   ├── docker
│   │   ├── dashboard
│   │   ├── eslint-daemon
│   │   └── orchestrator
│   │       └── src
│   │           └── services
│   │               └── qualityGateService.js
│   ├── docker-compose.quality-gates.yml
│   ├── scripts
│   │   ├── run-quality-gates.sh
│   │   └── setup-quality-gates.sh
│   └── sql
├── QUALITY-GATES-SYSTEM-REPORT.md
├── react-native-enhancement
│   ├── auth
│   ├── codepush
│   ├── config
│   ├── docker
│   │   └── codepush-server
│   │       └── src
│   │           ├── controllers
│   │           ├── index.js
│   │           ├── middleware
│   │           ├── models
│   │           ├── services
│   │           └── utils
│   ├── docker-compose.react-native-enhancement.yml
│   ├── linking
│   ├── native-modules
│   ├── notifications
│   ├── offline
│   ├── performance
│   ├── scripts
│   │   └── setup-react-native-enhancement.sh
│   └── templates
│       └── App.js
├── REACT-NATIVE-ENHANCEMENT-SYSTEM-REPORT.md
├── README.md
├── README-MICROSERVICES.md
├── scripts
│   ├── fix-package-names-nexus.sh
│   ├── setup-env.sh
│   ├── setup-microservices.sh
│   ├── setup.sh
│   └── setup-typescript.sh
├── security
│   ├── architecture
│   │   └── security-hardening-strategy.md
│   ├── config
│   │   ├── nginx-security
│   │   │   └── nginx.conf
│   │   ├── vault
│   │   │   └── vault.hcl
│   │   └── vault-agent
│   │       └── agent.hcl
│   ├── docker-compose.security.yml
│   ├── scripts
│   │   └── setup-security-hardening.sh
│   └── services
│       ├── security-scanner
│       │   └── src
│       │       └── scanners
│       │           ├── dependency.scanner.ts
│       │           └── owasp-zap.scanner.ts
│       └── security-service
│           └── src
│               ├── middleware
│               │   └── security.middleware.ts
│               └── services
│                   └── vault.service.ts
├── Security-Hardening-System.md
├── services
│   ├── shared-kernel
│   │   └── src
│   │       ├── application
│   │       │   ├── command.ts
│   │       │   └── query.ts
│   │       └── domain
│   │           ├── aggregate-root.ts
│   │           └── base-entity.ts
│   └── user-domain
│       ├── Dockerfile
│       ├── package.json
│       └── src
│           ├── application
│           │   ├── commands
│           │   │   └── create-user.command.ts
│           │   ├── ports
│           │   │   ├── event-publisher.ts
│           │   │   └── user.repository.ts
│           │   └── queries
│           │       └── get-user.query.ts
│           ├── domain
│           │   └── user.ts
│           ├── infrastructure
│           │   ├── kafka-event-publisher.ts
│           │   ├── postgres-user-repository.ts
│           │   └── redis-user-read-model.ts
│           └── presentation
│               ├── routes.ts
│               └── user.controller.ts
├── setup-apps-fixed.sh
├── setup-apps.sh
├── testing
│   ├── config
│   │   ├── jest.config.js
│   │   └── playwright.config.ts
│   └── tests
│       └── unit
│           └── services
│               └── user.service.test.ts
├── tools
├── tsconfig.json
├── turbo.json
├── turbo.json.legacy
├── types
│   └── global.d.ts
└── TYPESCRIPT_SETUP.md
