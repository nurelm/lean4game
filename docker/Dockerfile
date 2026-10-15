# syntax=docker/dockerfile:1
#
# lean4game: server + relay + client + bundled TestGame, ready to run or test.
#
# The build stage mirrors what CI does (.github/workflows/test.yml):
#   npm ci -> lake build (server) -> tsc (relay) -> vite (client) -> lake build (TestGame)
# The runtime stage ships the prebuilt artifacts plus elan, so game servers
# (`lake serve`) can be spawned for any mounted game using its lean-toolchain.
#
# Build-time network endpoints: deb.nodesource.com, elan.lean-lang.org and
# github releases (Lean toolchain), github.com (lake git deps),
# registry.npmjs.org, download.cypress.io.

######## build stage ########
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://deb.nodesource.com/setup_26.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
    # Node.js 26 - matches NODE_VERSION in .github/workflows/test.yml

# elan plus every toolchain pinned by a lean-toolchain file in the repo
COPY server/lean-toolchain /tmp/toolchain-server
COPY cypress/TestGame/lean-toolchain /tmp/toolchain-testgame
ENV PATH="/root/.elan/bin:${PATH}"
RUN curl -fsSL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none \
    && for tc in $(sort -u /tmp/toolchain-server /tmp/toolchain-testgame); do elan toolchain install "$tc"; done \
    && elan default "$(sort -u /tmp/toolchain-server /tmp/toolchain-testgame | head -n1)"

ENV CYPRESS_CACHE_DIRECTORY=/opt/cypress-cache
WORKDIR /app

# npm workspaces (root + client + relay)
COPY package.json package-lock.json ./
COPY client/package.json client/package.json
COPY relay/package.json relay/package.json
RUN npm ci --no-audit --no-fund

# Lean server: GameServer library and its pinned git dependencies (batteries, i18n)
COPY server /app/server
RUN cd /app/server && lake build

# Relay (TypeScript backend serving the client and the game websockets)
COPY relay /app/relay
RUN npm --workspace relay run build

# Client (Vite production build)
COPY client /app/client
RUN npm --workspace client run build

# TestGame (e2e fixture game) and the cypress specs
COPY cypress /app/cypress
COPY cypress.config.ts ./
RUN npm run build:test

# Fail the build early if the runtime would serve an empty/broken app
RUN test -f /app/relay/dist/src/index.js \
    && test -d /app/client/dist \
    && test -f /app/cypress/TestGame/.lake/gamedata/game.json

######## runtime stage ########
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git unzip procps python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://deb.nodesource.com/setup_26.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    # Electron (cypress' default browser) runtime libraries for `run_tests`
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        xvfb xauth \
        libgtk-3-0t64 libnss3 libasound2t64 libgbm1 \
        libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
        libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
        libpango-1.0-0 libcairo2 \
        fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# Lean (elan + toolchain) for spawning game servers (`lake serve`)
COPY --from=build /root/.elan /root/.elan
ENV PATH="/root/.elan/bin:${PATH}"

COPY --from=build /opt/cypress-cache /opt/cypress-cache
ENV CYPRESS_CACHE_DIRECTORY=/opt/cypress-cache
# Full npm install (dev dependencies included): the relay resolves transitive
# dependencies such as vscode-ws-jsonrpc from the hoisted root node_modules,
# and running `cypress run` needs the cypress npm package in place.

# /srv/<name> is the "local games" directory the relay scans in development
# mode (any folder holding a `.lake/gamedata/game.json`). The repo itself
# lives one level down so local games end up as siblings of it.
COPY --from=build /app /srv/lean4game
COPY docker/run-tests.sh /srv/lean4game/docker/run-tests.sh

# The baked-in TestGame as a local game:
#  - /srv/TestGame is a hardlinked copy so the landing page lists it
#  - /server -> /srv/lean4game/server lets that copy's `../../server` GameServer
#    path dependency resolve
RUN mkdir -p /srv/lean4game/games /srv/lean4game/logs \
    && cp -al /srv/lean4game/cypress/TestGame /srv/TestGame \
    && ln -s /srv/lean4game/server /server

WORKDIR /srv/lean4game
EXPOSE 3000
ENV NODE_ENV=production \
    PORT=3000 \
    API_PORT=8010 \
    NO_BWRAP=true
CMD ["node", "relay/dist/src/index.js"]