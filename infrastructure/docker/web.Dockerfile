FROM node:18-alpine AS base

# Install pnpm
RUN npm install -g pnpm

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY turbo.json ./

# Copy package.json files for all packages
COPY apps/web/package.json ./apps/web/
COPY packages/*/package.json ./packages/*/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build the web application
RUN pnpm build --filter=@aic/web

# Production stage
FROM node:18-alpine AS production

RUN npm install -g pnpm

WORKDIR /app

# Copy built application
COPY --from=base /app/apps/web/.next ./apps/web/.next
COPY --from=base /app/apps/web/public ./apps/web/public
COPY --from=base /app/apps/web/package.json ./apps/web/
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/package.json ./

EXPOSE 3000

CMD ["pnpm", "--filter=@aic/web", "start"]
