FROM listmonk/listmonk:v3.0.0

# Install wget for healthcheck and postgresql-client for schema creation
RUN apk add --no-cache wget ca-certificates postgresql-client curl

# Download Listmonk schema.sql for manual installation
RUN wget -O /listmonk/schema.sql https://raw.githubusercontent.com/knadh/listmonk/master/schema.sql

# Create necessary directories
RUN mkdir -p /listmonk/uploads /listmonk/static && \
    chmod -R 755 /listmonk/uploads /listmonk/static

WORKDIR /listmonk

# Copy entrypoint script
COPY listmonk-deployment/entrypoint.sh /listmonk/entrypoint.sh
RUN chmod +x /listmonk/entrypoint.sh

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:9000/api/health || exit 1

# Run entrypoint script
CMD ["/listmonk/entrypoint.sh"]
