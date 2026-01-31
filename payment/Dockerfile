FROM python:3.10-slim

# Security: Create a non-root user with specific UID/GID
RUN groupadd -g 2000 appuser && useradd -u 1000 -g appuser appuser

WORKDIR /app

# Environment variables for Python optimizations
# PYTHONDONTWRITEBYTECODE: Prevents Python from writing .pyc files (saves space)
# PYTHONUNBUFFERED: Ensures logs are flushed immediately
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    INSTANA_SERVICE_NAME=payment

# Install system dependencies required for building uWSGI
# We use a single RUN command to install, build, and cleanup to keep the layer small
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install dependencies
# --no-cache-dir: Don't save the download cache (saves huge amount of space)
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY *.py payment.ini ./

# Security: Change ownership of the app directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to the non-root user
USER appuser

EXPOSE 8080

CMD ["uwsgi", "--ini", "payment.ini"]