"""
Flask API for Docker Compose Demo
Demonstrates a simple API with database connection.

Endpoints:
  GET /health     - Health check endpoint
  GET /api/status - Database connection status
  GET /api/info   - Service information
"""

from flask import Flask, jsonify
import os
import psycopg2

app = Flask(__name__)


def get_db_connection():
    """Create a database connection using environment variables."""
    return psycopg2.connect(
        host=os.environ.get('DB_HOST', 'db'),
        port=os.environ.get('DB_PORT', '5432'),
        user=os.environ.get('DB_USER', 'demo'),
        password=os.environ.get('DB_PASSWORD', 'secret'),
        database=os.environ.get('DB_NAME', 'myapp')
    )


@app.route('/health')
def health():
    """
    Health check endpoint for container orchestration.
    Returns 200 if the service is running.
    """
    return jsonify({'status': 'healthy'})


@app.route('/api/status')
def status():
    """
    Check API and database connection status.
    Returns database version if connected successfully.
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT version()')
        db_version = cur.fetchone()[0]
        cur.close()
        conn.close()
        return jsonify({
            'api': 'running',
            'database': 'connected',
            'db_version': db_version
        })
    except Exception as e:
        return jsonify({
            'api': 'running',
            'database': 'error',
            'error': str(e)
        }), 500


@app.route('/api/info')
def info():
    """
    Return service information.
    Useful for debugging and monitoring.
    """
    return jsonify({
        'service': 'demo-api',
        'version': '1.0.0',
        'environment': os.environ.get('APP_ENV', 'development')
    })


if __name__ == '__main__':
    # Run development server
    # In production, use gunicorn: gunicorn --bind 0.0.0.0:5000 app:app
    debug_mode = os.environ.get('DEBUG', 'false').lower() == 'true'
    app.run(host='0.0.0.0', port=5000, debug=debug_mode)
