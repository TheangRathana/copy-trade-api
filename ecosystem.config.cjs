module.exports = {
  apps: [
    {
      name: "copy-trade-api-4000",
      script: "dist/server.js",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      env: {
        NODE_ENV: "production",
        // Local only: the EAs call 127.0.0.1 and the web UI comes in through
        // the Cloudflare Tunnel, so the port is never exposed to the internet.
        HOST: "127.0.0.1",
        PORT: 4000,
      },
    },
    {
      name: "copy-trade-api-4001",
      script: "dist/server.js",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      env: {
        NODE_ENV: "production",
        HOST: "0.0.0.0",
        PORT: 4001,
      },
    },
  ],
};
