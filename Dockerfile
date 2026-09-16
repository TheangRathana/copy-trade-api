# escape=`

FROM mcr.microsoft.com/windows/servercore:ltsc2022 AS build

SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG NODE_VERSION=24.21.0

# Install Node.js
RUN Invoke-WebRequest `
    -Uri "https://nodejs.org/dist/v${env:NODE_VERSION}/node-v${env:NODE_VERSION}-win-x64.zip" `
    -OutFile C:\node.zip; `
    Expand-Archive C:\node.zip -DestinationPath C:\; `
    Rename-Item "C:\node-v${env:NODE_VERSION}-win-x64" C:\node; `
    Remove-Item C:\node.zip

ENV PATH="C:\node;C:\node\node_modules\npm\bin;${PATH}"

# Install pnpm
RUN npm install --global pnpm@11.6.0

WORKDIR C:\app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN pnpm install --frozen-lockfile

COPY tsconfig.json ./
COPY src ./src

RUN pnpm build; `
    pnpm prune --prod


FROM mcr.microsoft.com/windows/servercore:ltsc2022 AS runtime

SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG NODE_VERSION=24.21.0

RUN Invoke-WebRequest `
    -Uri "https://nodejs.org/dist/v${env:NODE_VERSION}/node-v${env:NODE_VERSION}-win-x64.zip" `
    -OutFile C:\node.zip; `
    Expand-Archive C:\node.zip -DestinationPath C:\; `
    Rename-Item "C:\node-v${env:NODE_VERSION}-win-x64" C:\node; `
    Remove-Item C:\node.zip

ENV PATH="C:\node;${PATH}"
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=4000

WORKDIR C:\app

COPY --from=build C:\app\package.json ./
COPY --from=build C:\app\node_modules ./node_modules
COPY --from=build C:\app\dist ./dist

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 `
    CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/api/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "dist/server.js"]