FROM node:20-alpine AS base

# Install pnpm
RUN npm install -g pnpm

# Set working directory
WORKDIR /v3

# Copy package files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY turbo.json ./

# Copy all package.json files
COPY apps/frontend/*/package.json ./apps/frontend/*/
COPY packages/*/package.json ./packages/*/
COPY docs/*/package.json ./docs/*/
COPY infrastructure/*/* ./infrastructure/*/
COPY scripts/* ./scripts/
COPY tools/*/package.json ./tools/*/
COPY types/*/package.json ./types/*/


# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Opening ports
EXPOSE 5432
EXPOSE 6379
EXPOSE 9000
EXPOSE 9001
EXPOSE 1025
EXPOSE 8025
EXPOSE 3000
EXPOSE 3001

# Build the application
RUN pnpm build

CMD ["pnpm", "dev"]

# Production stage
FROM node:20-alpine AS production

RUN npm install -g pnpm



WORKDIR /v3

# Copy built application
COPY --from=base /app/dist ./dist
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/package.json ./

# Opening ports
EXPOSE 5432
EXPOSE 6379
EXPOSE 9000
EXPOSE 9001
EXPOSE 1025
EXPOSE 8025
EXPOSE 3000
EXPOSE 3001

CMD ["pnpm", "start"]
