# =============================================================================
# Dockerfile for Finance API
# =============================================================================
# This is a production-grade, multi-stage Dockerfile following best practices:
# - Non-root user
# - Minimal attack surface
# - Layer caching optimization
# - Security scanning compatible
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM python:3.12-slim-bookworm AS builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# -----------------------------------------------------------------------------
# Stage 2: Production
# -----------------------------------------------------------------------------
FROM python:3.12-slim-bookworm AS production

# Labels for container metadata
LABEL org.opencontainers.image.title="Finance API" \
      org.opencontainers.image.description="Demo application for secrets management comparison" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="Secrets Management Guide" \
      org.opencontainers.image.source="https://github.com/your-org/secrets-management-guide"

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    APP_HOME=/app \
    APP_USER=appuser \
    APP_VERSION=1.0.0 \
    PORT=8080

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user
RUN groupadd --gid 1000 ${APP_USER} && \
    useradd --uid 1000 --gid ${APP_USER} --shell /bin/bash --create-home ${APP_USER}

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Set working directory
WORKDIR ${APP_HOME}

# Copy application code
COPY --chown=${APP_USER}:${APP_USER} app.py .

# Create directories for secret mounts
RUN mkdir -p /mnt/secrets && \
    chown -R ${APP_USER}:${APP_USER} /mnt/secrets

# Switch to non-root user
USER ${APP_USER}

# Expose port
EXPOSE ${PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Use dumb-init as PID 1 for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start application with gunicorn
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "4", \
     "--threads", "2", \
     "--worker-class", "gthread", \
     "--worker-tmp-dir", "/dev/shm", \
     "--timeout", "120", \
     "--keep-alive", "5", \
     "--max-requests", "1000", \
     "--max-requests-jitter", "50", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--capture-output", \
     "--enable-stdio-inheritance", \
     "app:app"]

# -----------------------------------------------------------------------------
# Stage 3: Development (optional)
# -----------------------------------------------------------------------------
FROM production AS development

USER root

# Install development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install development dependencies
COPY --from=builder /opt/venv /opt/venv
RUN pip install pytest pytest-cov black flake8 mypy ipython

USER ${APP_USER}

# Override command for development
CMD ["python", "app.py"]
