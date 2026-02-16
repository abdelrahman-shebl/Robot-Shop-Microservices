FROM node:18-alpine

ENV INSTANA_AUTO_PROFILE true

# Install curl for health checks
RUN apk add --no-cache curl

EXPOSE 8080

WORKDIR /opt/server

COPY package.json /opt/server/

RUN npm install

COPY server.js /opt/server/

USER node

CMD ["node", "server.js"]
