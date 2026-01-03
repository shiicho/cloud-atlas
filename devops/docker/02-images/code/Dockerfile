# ===========================================
# Python Flask Application
# Docker Fundamentals - Lesson 02
# ===========================================
#
# Best practices demonstrated:
# 1. Use specific version tags (not :latest)
# 2. Use slim base image to reduce size
# 3. Copy dependency file first (cache optimization)
# 4. Use --no-cache-dir to reduce image size
# 5. Include HEALTHCHECK for container monitoring
#

# Base image: Python 3.11 slim version
# slim variant is ~130MB vs full python:3.11 at ~900MB
FROM python:3.11-slim

# Metadata labels
LABEL maintainer="your-email@example.com"
LABEL version="1.0"
LABEL description="Simple Flask application for Docker learning"

# Set working directory
# Creates the directory if it doesn't exist
WORKDIR /app

# Environment variables
# PYTHONDONTWRITEBYTECODE: Prevents Python from writing .pyc files
# PYTHONUNBUFFERED: Ensures logs are sent to stdout immediately
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Copy dependency file first (for cache optimization)
# If requirements.txt hasn't changed, this layer is cached
COPY requirements.txt .

# Install dependencies
# --no-cache-dir: Don't cache downloaded packages (smaller image)
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code last (most frequently changed)
# Any change to app.py only invalidates this layer and below
COPY app.py .

# Document the port the app listens on
# This is informational only - doesn't publish the port
EXPOSE 5000

# Health check configuration
# Checks if /health endpoint responds with 200 OK
# Note: Using Python instead of curl since python:3.11-slim doesn't include curl
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Default command when container starts
# Using exec form (JSON array) is recommended
CMD ["python", "app.py"]
