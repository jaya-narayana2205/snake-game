# =============================================================
# Snake Game — Production Dockerfile
# Multi-stage build | Nginx Alpine | Non-root | ~25 MB image
# =============================================================

# ----- Stage 1: Prepare static assets -----
FROM alpine:3.20 AS assets

WORKDIR /build
COPY src/ ./

# Validate that index.html exists
RUN test -f index.html || (echo "ERROR: index.html not found" && exit 1)


# ----- Stage 2: Production Nginx server -----
FROM nginx:1.27-alpine AS production

LABEL maintainer="devops@snakegame"
LABEL description="Snake Game — static site served via Nginx"
LABEL version="1.0.0"

# Remove default Nginx content and config
RUN rm -rf /usr/share/nginx/html/* \
    && rm /etc/nginx/conf.d/default.conf

# Copy custom Nginx config
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy static assets from build stage
COPY --from=assets /build/ /usr/share/nginx/html/

# Create non-root user and set permissions
RUN addgroup -S appgroup && adduser -S appuser -G appgroup \
    && chown -R appuser:appgroup /usr/share/nginx/html \
    && chown -R appuser:appgroup /var/cache/nginx \
    && chown -R appuser:appgroup /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown appuser:appgroup /var/run/nginx.pid

# Switch to non-root user
USER appuser

# Expose unprivileged port (matches nginx.conf listen directive)
EXPOSE 8080

# Health check — hit the /healthz endpoint every 30s
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/healthz || exit 1

# Run Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
