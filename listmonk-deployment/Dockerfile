FROM listmonk/listmonk:v5.1.0

# Install wget for healthcheck and postgresql-client for schema creation
RUN apk add --no-cache wget ca-certificates postgresql-client curl

# Download Listmonk schema.sql for manual installation (use v5.1.0 tag to match Docker image version)
RUN wget -O /listmonk/schema.sql https://raw.githubusercontent.com/knadh/listmonk/v5.1.0/schema.sql

# Create necessary directories
RUN mkdir -p /listmonk/uploads /listmonk/static && \
    chmod -R 755 /listmonk/uploads /listmonk/static

WORKDIR /listmonk

# Copy entrypoint script
COPY listmonk-deployment/entrypoint.sh /listmonk/entrypoint.sh
RUN chmod +x /listmonk/entrypoint.sh

# Copy custom JavaScript for buttons
COPY listmonk-deployment/custom-buttons.js /listmonk/static/custom-buttons.js

# Copy MOYD logo to uploads directory for login page
COPY MOYD01.png /listmonk/uploads/MOYD01.png

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:9000/api/health || exit 1

# Run entrypoint script
CMD ["/listmonk/entrypoint.sh"]
