#!/bin/bash

# Nexus Workspace Setup Script
echo "🚀 Setting up Nexus Workspace..."

# Check if pnpm is installed
if ! command -v pnpm &> /dev/null; then
    echo "❌ pnpm is not installed. Please install pnpm first:"
    echo "npm install -g pnpm"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "⚠️  Docker is not installed. Some features may not work."
    echo "Please install Docker from https://docker.com"
fi

# Install dependencies
echo "📦 Installing dependencies..."
pnpm install

# Copy environment variables
if [ ! -f .env ]; then
    echo "📝 Creating environment file..."
    cp .env.example .env
    echo "✅ Created .env file. Please update it with your configuration."
fi

# Start development services
echo "🐳 Starting development services..."
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
    echo "✅ Development services started (PostgreSQL, Redis, etc.)"
else
    echo "⚠️  Docker Compose not available. Please start services manually."
fi

# Build packages
echo "🔨 Building packages..."
pnpm build

# Run type checking
echo "🔍 Running type checks..."
pnpm type-check

# Run linting
echo "🧹 Running linter..."
pnpm lint

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Update .env file with your configuration"
echo "2. Run 'pnpm dev' to start development servers"
echo "3. Visit http://localhost:3000 for the web app"
echo "4. Visit http://localhost:3001 for the API"
echo ""
echo "Available commands:"
echo "  pnpm dev          - Start development servers"
echo "  pnpm build        - Build all packages"
echo "  pnpm test         - Run tests"
echo "  pnpm lint         - Run linter"
echo "  pnpm type-check   - Run type checking"
echo ""
