FROM node:18-alpine

ENV INSTANA_AUTO_PROFILE true

# Create non-root user with specific UID/GID
RUN addgroup -g 2000 appuser && adduser -u 1000 -G appuser -s /sbin/nologin -D appuser

EXPOSE 8080

WORKDIR /opt/server

COPY package.json /opt/server/

RUN npm install

COPY server.js /opt/server/

# Fix ownership of app directory
RUN chown -R appuser:appuser /opt/server

USER appuser

CMD ["node", "server.js"]
