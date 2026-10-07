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
        HOST: "0.0.0.0",
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
