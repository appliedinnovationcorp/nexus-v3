import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { Providers } from './providers'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Nexus - Modern Full-Stack Platform',
  description: 'A comprehensive full-stack application built with modern tools and best practices.',
  keywords: ['Next.js', 'React', 'TypeScript', 'Full-Stack'],
  authors: [{ name: 'Nexus Team' }],
  openGraph: {
    title: 'Nexus Platform',
    description: 'Modern full-stack application',
    url: 'https://nexus.com',
    siteName: 'Nexus',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Nexus Platform'
      }
    ],
    locale: 'en_US',
    type: 'website'
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Nexus Platform',
    description: 'Modern full-stack application',
    images: ['/twitter-image.png']
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1
    }
  }
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className}>
        <Providers>
          {children}
        </Providers>
      </body>
    </html>
  )
}
