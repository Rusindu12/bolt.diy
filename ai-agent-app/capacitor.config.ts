import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.nexus.aiagent',
  appName: 'Nexus AI Agent',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
  },
  plugins: {},
};

export default config;
