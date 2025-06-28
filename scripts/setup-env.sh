#!/bin/bash

# Environment Setup Script for Nexus Workspace
echo "🔧 Setting up environment variables for Nexus Workspace..."

# Function to generate random secret
generate_secret() {
    openssl rand -base64 32 2>/dev/null || node -e "console.log(require('crypto').randomBytes(32).toString('base64'))" 2>/dev/null || echo "CHANGE_ME_$(date +%s)"
}

# Check if .env.local exists
if [ ! -f ".env.local" ]; then
    echo "📝 Creating .env.local from .env.example..."
    cp .env.example .env.local
else
    echo "✅ .env.local already exists"
fi

# Generate secure secrets
echo "🔐 Generating secure secrets..."
JWT_SECRET=$(generate_secret)
NEXTAUTH_SECRET=$(generate_secret)

# Update .env.local with generated secrets
if command -v sed >/dev/null 2>&1; then
    sed -i.bak "s/your-jwt-secret-key/$JWT_SECRET/" .env.local
    sed -i.bak "s/your-nextauth-secret/$NEXTAUTH_SECRET/" .env.local
    rm -f .env.local.bak
    echo "✅ Updated JWT_SECRET and NEXTAUTH_SECRET with secure values"
fi

echo ""
echo "📋 Environment Setup Complete!"
echo ""
echo "🔧 Next steps to configure your environment:"
echo ""
echo "1. 📝 Edit .env.local and update the following:"
echo "   - DATABASE_URL: Update with your PostgreSQL credentials"
echo "   - REDIS_URL: Update with your Redis connection"
echo "   - API Keys: Add your actual API keys (OpenAI, Stripe, etc.)"
echo "   - AWS Credentials: Add your AWS access keys"
echo "   - Email Settings: Configure SMTP settings"
echo ""
echo "2. 🐳 Start local services with Docker:"
echo "   docker-compose up -d"
echo ""
echo "3. 🗄️  Set up your database:"
echo "   pnpm db:generate"
echo "   pnpm db:push"
echo ""
echo "4. 🚀 Start development:"
echo "   pnpm dev"
echo ""
echo "📄 Environment files created:"
echo "   - .env.local (your local development environment)"
echo "   - .env.development (shared development settings)"
echo "   - .env.test (testing environment)"
echo ""
echo "⚠️  Remember:"
echo "   - Never commit .env.local to git"
echo "   - Update production environment variables in your deployment platform"
echo "   - Use strong, unique secrets in production"
