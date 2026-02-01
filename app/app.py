"""
Sample Flask application demonstrating secrets consumption.
Connects to PostgreSQL using secrets from environment variables or file mounts.
"""

import os
import logging
from flask import Flask, jsonify
import psycopg2
from psycopg2 import pool

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

def get_secret(name, default=None):
    """Get secret from env var or file mount."""
    env_val = os.environ.get(name)
    if env_val:
        return env_val
    
    for path in [f'/mnt/secrets/{name.lower()}', f'/vault/secrets/{name.lower()}']:
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    return default

# Database configuration
DB_CONFIG = {
    'host': get_secret('DB_HOST', 'localhost'),
    'port': int(get_secret('DB_PORT', '5432')),
    'database': get_secret('DB_NAME', 'appdb'),
    'user': get_secret('DB_USER', 'postgres'),
    'password': get_secret('DB_PASSWORD', '')
}

db_pool = None

def init_db():
    global db_pool
    try:
        db_pool = psycopg2.pool.SimpleConnectionPool(1, 10, **DB_CONFIG)
        logger.info("Database pool initialized")
    except Exception as e:
        logger.error(f"Database connection failed: {e}")

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

@app.route('/ready')
def ready():
    if db_pool:
        try:
            conn = db_pool.getconn()
            conn.cursor().execute('SELECT 1')
            db_pool.putconn(conn)
            return jsonify({'status': 'ready', 'database': 'connected'})
        except Exception as e:
            return jsonify({'status': 'not ready', 'error': str(e)}), 503
    return jsonify({'status': 'not ready', 'error': 'no pool'}), 503

@app.route('/')
def index():
    return jsonify({
        'app': 'secrets-demo',
        'db_host': DB_CONFIG['host'],
        'db_name': DB_CONFIG['database']
    })

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=8080)
