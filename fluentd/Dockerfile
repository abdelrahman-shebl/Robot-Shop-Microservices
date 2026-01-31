FROM fluentd

# Create non-root user with specific UID/GID
RUN addgroup -g 2000 appuser && adduser -u 1000 -G appuser -s /sbin/nologin -D appuser

USER root

RUN apk update && \
    apk add --virtual .build-dependencies build-base ruby-dev

RUN fluent-gem install fluent-plugin-elasticsearch && \
    fluent-gem install fluent-plugin-kubernetes_metadata_filter && \
    fluent-gem install fluent-plugin-multi-format-parser

# Switch to non-root user for runtime
USER appuser
