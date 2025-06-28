import { Button } from '@nexus/ui'
import { formatDate } from '@nexus/utils'
import Link from 'next/link'

export default function HomePage() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div className="container mx-auto px-4 py-16">
        <div className="text-center">
          <h1 className="text-5xl font-bold text-gray-900 mb-6">
            Welcome to Nexus
          </h1>
          <p className="text-xl text-gray-600 mb-8 max-w-2xl mx-auto">
            A comprehensive full-stack monorepo built with modern tools and best practices.
            Experience the power of Next.js, React, and TypeScript.
          </p>
          
          <div className="flex gap-4 justify-center mb-12">
            <Button asChild>
              <Link href="/dashboard">
                Get Started
              </Link>
            </Button>
            <Button variant="outline" asChild>
              <Link href="/docs">
                Documentation
              </Link>
            </Button>
          </div>

          <div className="grid md:grid-cols-3 gap-8 max-w-4xl mx-auto">
            <div className="bg-white p-6 rounded-lg shadow-md">
              <h3 className="text-xl font-semibold mb-3">🚀 Fast Development</h3>
              <p className="text-gray-600">
                Hot reloading, TypeScript support, and modern tooling for rapid development.
              </p>
            </div>
            
            <div className="bg-white p-6 rounded-lg shadow-md">
              <h3 className="text-xl font-semibold mb-3">🔧 Scalable Architecture</h3>
              <p className="text-gray-600">
                Monorepo structure with shared packages and microservices architecture.
              </p>
            </div>
            
            <div className="bg-white p-6 rounded-lg shadow-md">
              <h3 className="text-xl font-semibold mb-3">🛡️ Production Ready</h3>
              <p className="text-gray-600">
                Built-in security, testing, CI/CD, and deployment configurations.
              </p>
            </div>
          </div>

          <div className="mt-12 text-sm text-gray-500">
            Last updated: {formatDate(new Date())}
          </div>
        </div>
      </div>
    </main>
  )
}
