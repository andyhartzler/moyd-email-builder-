FROM listmonk/listmonk:v3.0.0

# Install wget for healthcheck
RUN apk add --no-cache wget ca-certificates

# Create necessary directories
RUN mkdir -p /listmonk/uploads /listmonk/static && \
    chmod -R 755 /listmonk/uploads /listmonk/static

WORKDIR /listmonk

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:9000/api/health || exit 1

# Run installation then start
CMD sh -c "./listmonk --install --yes && ./listmonk"
