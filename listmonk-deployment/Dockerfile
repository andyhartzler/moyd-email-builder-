FROM listmonk/listmonk:v5.1.0

# Install wget for healthcheck, postgresql-client for schema creation, socat/openssl for SSO handler, and nginx for reverse proxy
RUN apk add --no-cache wget ca-certificates postgresql-client curl netcat-openbsd openssl nginx socat

# Download Listmonk schema.sql for manual installation (use v5.1.0 tag to match Docker image version)
RUN wget -O /listmonk/schema.sql https://raw.githubusercontent.com/knadh/listmonk/v5.1.0/schema.sql

# Create necessary directories
RUN mkdir -p /listmonk/uploads /listmonk/static /run/nginx && \
    chmod -R 755 /listmonk/uploads /listmonk/static /run/nginx

WORKDIR /listmonk

# Copy entrypoint script
COPY listmonk-deployment/entrypoint.sh /listmonk/entrypoint.sh
RUN chmod +x /listmonk/entrypoint.sh

# Copy nginx configuration for SSO proxy
COPY listmonk-deployment/nginx.conf /etc/nginx/nginx.conf

# Copy custom JavaScript for buttons
COPY listmonk-deployment/custom-buttons.js /listmonk/static/custom-buttons.js

# Copy MOYD custom favicon
COPY favicon.png /listmonk/static/favicon.png

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:9000/api/health || exit 1

# Run entrypoint script
CMD ["/listmonk/entrypoint.sh"]
