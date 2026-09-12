# ── Stage 1: install dependencies ──
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev

# ── Stage 2: build TypeScript ──
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci 2>/dev/null || npm install
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

# ── Stage 3: production ──
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001 -G nodejs

# Production dependencies only
COPY --from=deps /app/node_modules ./node_modules
# Compiled JS
COPY --from=builder /app/dist ./dist
# Package metadata (for npm start)
COPY package.json ./

USER root
RUN mkdir -p uploads/products uploads/branding uploads/promos && \
    chown -R nodeuser:nodejs uploads

USER nodeuser

EXPOSE 4000
CMD ["node", "dist/index.js"]
