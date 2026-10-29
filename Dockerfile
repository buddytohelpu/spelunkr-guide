FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=3000
COPY server ./server
COPY web ./web
COPY package.json ./package.json
USER node
EXPOSE 3000
CMD ["node", "server/index.js"]
