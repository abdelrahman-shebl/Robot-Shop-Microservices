FROM alpine:latest AS build
ARG KEY

WORKDIR /instana

RUN apk add --update --no-cache wget

ENV ARTI_PATH='artifact-public.instana.io/artifactory/shared/com/instana/nginx_tracing/'

RUN if [ -n "$KEY" ]; then \
    sensor_version=$(wget -O- "https://_:${KEY}@${ARTI_PATH}" 2>&1 | \
      egrep -o "href=\"([0-9]+\.){2}[0-9]+/" | cut -d'"' -f2 | sort -V | tail -n1 | tr -d /); \
    echo "Downloading sensor version ${sensor_version} for Nginx version 1.21.6" ; \
    $(wget -O instana.zip \
      "https://_:${KEY}@${ARTI_PATH}/${sensor_version}/linux-amd64-glibc-nginx-1.21.6.zip") && \
    unzip instana.zip && \
    mv glibc-libinstana_sensor.so libinstana_sensor.so && \
    mv glibc-nginx-1.21.6-ngx_http_ot_module.so ngx_http_opentracing_module.so; \
    else echo "KEY not provided. Not adding tracing"; \
    touch dummy.so; \
    fi


FROM nginx:latest

# Create non-root user with specific UID/GID
RUN groupadd -g 2000 appuser && useradd -u 1000 -g appuser appuser

EXPOSE 8080

ENV CATALOGUE_HOST=catalogue \
    USER_HOST=user \
    CART_HOST=cart \
    SHIPPING_HOST=shipping \
    PAYMENT_HOST=payment \
    RATINGS_HOST=ratings \
    INSTANA_SERVICE_NAME=nginx-web

# Instana tracing
COPY --from=build /instana/*.so /tmp/

COPY entrypoint.sh /root/
RUN chown appuser:appuser /root/entrypoint.sh && chmod +x /root/entrypoint.sh

COPY default.conf.template /etc/nginx/conf.d/default.conf.template
COPY static /usr/share/nginx/html

# Fix ownership of nginx directories
RUN chown -R appuser:appuser /usr/share/nginx /var/cache/nginx /var/log/nginx /var/run/nginx.pid 2>/dev/null || true && \
    chown -R appuser:appuser /etc/nginx

USER appuser

ENTRYPOINT ["/root/entrypoint.sh"]
