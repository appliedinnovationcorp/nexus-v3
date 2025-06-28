// Global type definitions for aic Workspace

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: 'development' | 'production' | 'test';
      DATABASE_URL: string;
      REDIS_URL: string;
      JWT_SECRET: string;
      NEXTAUTH_SECRET: string;
      NEXTAUTH_URL: string;
    }
  }
}

export {};
