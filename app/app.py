# =============================================================================
# Sample Application - Finance API
# =============================================================================
# This is a demo Flask application that demonstrates how to connect to
# a PostgreSQL database using secrets from different backends:
# - Environment variables (12-Factor App)
# - File mounts (from CSI Driver or Vault Agent)
# - Direct API calls (for testing purposes)
#
# The application is intentionally backend-agnostic to demonstrate that
# the secret injection method is transparent to the application code.
# =============================================================================

import os
import json
import time
import logging
from functools import wraps
from flask import Flask, jsonify, request, g
import psycopg2
from psycopg2 import pool
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# =============================================================================
# Logging Configuration
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# =============================================================================
# Flask Application
# =============================================================================

app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# =============================================================================
# Prometheus Metrics
# =============================================================================

REQUEST_COUNT = Counter(
    'app_requests_total',
    'Total number of requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'app_request_latency_seconds',
    'Request latency in seconds',
    ['method', 'endpoint']
)

DB_CONNECTION_COUNT = Counter(
    'app_db_connections_total',
    'Total number of database connection attempts',
    ['status']
)

SECRET_REFRESH_COUNT = Counter(
    'app_secret_refresh_total',
    'Total number of secret refresh operations',
    ['source', 'status']
)

# =============================================================================
# Secret Loading Functions
# =============================================================================

class SecretManager:
    """
    A class to manage secrets from various sources.
    Supports:
    - Environment variables
    - File mounts (JSON or plain text)
    - AWS Secrets Manager (direct API)
    - AWS Parameter Store (direct API)
    - HashiCorp Vault (direct API)
    """
    
    def __init__(self):
        self.secrets_cache = {}
        self.last_refresh = 0
        self.refresh_interval = int(os.getenv('SECRET_REFRESH_INTERVAL', '300'))
        self.secret_source = os.getenv('SECRET_SOURCE', 'env')  # env, file, aws-secrets, aws-ssm, vault
        
    def get_database_credentials(self):
        """Get database credentials from configured source."""
        source = self.secret_source
        
        try:
            if source == 'env':
                return self._get_from_env()
            elif source == 'file':
                return self._get_from_file()
            elif source == 'aws-secrets':
                return self._get_from_aws_secrets_manager()
            elif source == 'aws-ssm':
                return self._get_from_aws_parameter_store()
            elif source == 'vault':
                return self._get_from_vault()
            else:
                logger.warning(f"Unknown secret source: {source}, falling back to env")
                return self._get_from_env()
        except Exception as e:
            logger.error(f"Error getting secrets from {source}: {e}")
            SECRET_REFRESH_COUNT.labels(source=source, status='error').inc()
            raise

    def _get_from_env(self):
        """Load secrets from environment variables."""
        SECRET_REFRESH_COUNT.labels(source='env', status='success').inc()
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': int(os.getenv('DB_PORT', '5432')),
            'database': os.getenv('DB_NAME', 'appdb'),
            'user': os.getenv('DB_USERNAME', 'postgres'),
            'password': os.getenv('DB_PASSWORD', ''),
        }

    def _get_from_file(self):
        """
        Load secrets from file mount.
        Supports both JSON format and individual files.
        """
        secrets_path = os.getenv('SECRETS_PATH', '/mnt/secrets')
        
        # Check for JSON file first (common for Vault Agent and ESO)
        json_file = os.path.join(secrets_path, 'db-credentials.json')
        if os.path.exists(json_file):
            with open(json_file, 'r') as f:
                data = json.load(f)
                SECRET_REFRESH_COUNT.labels(source='file-json', status='success').inc()
                return {
                    'host': data.get('host', 'localhost'),
                    'port': int(data.get('port', 5432)),
                    'database': data.get('dbname', data.get('database', 'appdb')),
                    'user': data.get('username', data.get('user', 'postgres')),
                    'password': data.get('password', ''),
                }
        
        # Fall back to individual files (common for CSI Driver)
        SECRET_REFRESH_COUNT.labels(source='file-individual', status='success').inc()
        return {
            'host': self._read_file(os.path.join(secrets_path, 'host'), 'localhost'),
            'port': int(self._read_file(os.path.join(secrets_path, 'port'), '5432')),
            'database': self._read_file(os.path.join(secrets_path, 'database'), 'appdb'),
            'user': self._read_file(os.path.join(secrets_path, 'username'), 'postgres'),
            'password': self._read_file(os.path.join(secrets_path, 'password'), ''),
        }

    def _read_file(self, path, default=''):
        """Read content from a file."""
        try:
            with open(path, 'r') as f:
                return f.read().strip()
        except FileNotFoundError:
            return default

    def _get_from_aws_secrets_manager(self):
        """Load secrets from AWS Secrets Manager (direct API call)."""
        import boto3
        
        secret_name = os.getenv('AWS_SECRET_NAME')
        region = os.getenv('AWS_REGION', 'us-east-1')
        
        client = boto3.client('secretsmanager', region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        data = json.loads(response['SecretString'])
        
        SECRET_REFRESH_COUNT.labels(source='aws-secrets', status='success').inc()
        return {
            'host': data.get('host', 'localhost'),
            'port': int(data.get('port', 5432)),
            'database': data.get('dbname', 'appdb'),
            'user': data.get('username', 'postgres'),
            'password': data.get('password', ''),
        }

    def _get_from_aws_parameter_store(self):
        """Load secrets from AWS Parameter Store (direct API call)."""
        import boto3
        
        param_prefix = os.getenv('AWS_PARAM_PREFIX', '/app/database')
        region = os.getenv('AWS_REGION', 'us-east-1')
        
        client = boto3.client('ssm', region_name=region)
        response = client.get_parameters_by_path(
            Path=param_prefix,
            WithDecryption=True
        )
        
        params = {p['Name'].split('/')[-1]: p['Value'] for p in response['Parameters']}
        
        SECRET_REFRESH_COUNT.labels(source='aws-ssm', status='success').inc()
        return {
            'host': params.get('host', 'localhost'),
            'port': int(params.get('port', '5432')),
            'database': params.get('database', 'appdb'),
            'user': params.get('username', 'postgres'),
            'password': params.get('password', ''),
        }

    def _get_from_vault(self):
        """Load secrets from HashiCorp Vault (direct API call)."""
        import hvac
        
        vault_addr = os.getenv('VAULT_ADDR', 'http://vault:8200')
        vault_token = os.getenv('VAULT_TOKEN')
        vault_role = os.getenv('VAULT_ROLE')
        secret_path = os.getenv('VAULT_SECRET_PATH', 'database/creds/app-role')
        
        client = hvac.Client(url=vault_addr)
        
        # Use Kubernetes auth if no token provided
        if not vault_token and vault_role:
            jwt_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
            with open(jwt_path, 'r') as f:
                jwt = f.read()
            client.auth.kubernetes.login(role=vault_role, jwt=jwt)
        else:
            client.token = vault_token
        
        # Read secret (could be dynamic or static)
        response = client.secrets.database.generate_credentials(name='app-role')
        
        SECRET_REFRESH_COUNT.labels(source='vault', status='success').inc()
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': int(os.getenv('DB_PORT', '5432')),
            'database': os.getenv('DB_NAME', 'appdb'),
            'user': response['data']['username'],
            'password': response['data']['password'],
        }

# Global secret manager instance
secret_manager = SecretManager()

# =============================================================================
# Database Connection Pool
# =============================================================================

db_pool = None

def get_db_connection():
    """Get a database connection from the pool."""
    global db_pool
    
    try:
        if db_pool is None:
            creds = secret_manager.get_database_credentials()
            db_pool = pool.ThreadedConnectionPool(
                minconn=1,
                maxconn=10,
                host=creds['host'],
                port=creds['port'],
                database=creds['database'],
                user=creds['user'],
                password=creds['password'],
                sslmode='require',
                connect_timeout=10
            )
            logger.info(f"Database connection pool created for {creds['host']}")
            DB_CONNECTION_COUNT.labels(status='success').inc()
        
        return db_pool.getconn()
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        DB_CONNECTION_COUNT.labels(status='error').inc()
        raise

def return_db_connection(conn):
    """Return a connection to the pool."""
    global db_pool
    if db_pool and conn:
        db_pool.putconn(conn)

def refresh_db_pool():
    """Refresh the database connection pool (for secret rotation)."""
    global db_pool
    if db_pool:
        db_pool.closeall()
        db_pool = None
    logger.info("Database connection pool refreshed")

# =============================================================================
# Request Middleware
# =============================================================================

@app.before_request
def before_request():
    """Track request start time."""
    g.start_time = time.time()

@app.after_request
def after_request(response):
    """Record request metrics."""
    latency = time.time() - g.start_time
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown',
        status=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown'
    ).observe(latency)
    return response

# =============================================================================
# API Endpoints
# =============================================================================

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'timestamp': time.time(),
        'version': os.getenv('APP_VERSION', '1.0.0'),
        'secret_source': secret_manager.secret_source
    })

@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check - verifies database connectivity."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        cursor.close()
        return_db_connection(conn)
        return jsonify({
            'status': 'ready',
            'database': 'connected'
        })
    except Exception as e:
        return jsonify({
            'status': 'not_ready',
            'database': 'disconnected',
            'error': str(e)
        }), 503

@app.route('/api/v1/accounts', methods=['GET'])
def list_accounts():
    """List all accounts (demo endpoint)."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            SELECT id, name, balance, created_at 
            FROM accounts 
            ORDER BY created_at DESC 
            LIMIT 100
        ''')
        rows = cursor.fetchall()
        cursor.close()
        return_db_connection(conn)
        
        accounts = [
            {
                'id': row[0],
                'name': row[1],
                'balance': float(row[2]),
                'created_at': row[3].isoformat()
            }
            for row in rows
        ]
        
        return jsonify({
            'accounts': accounts,
            'count': len(accounts)
        })
    except psycopg2.ProgrammingError as e:
        # Table doesn't exist - return empty for demo
        return jsonify({
            'accounts': [],
            'count': 0,
            'note': 'Demo mode - no data'
        })
    except Exception as e:
        logger.error(f"Error listing accounts: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/accounts', methods=['POST'])
def create_account():
    """Create a new account (demo endpoint)."""
    try:
        data = request.get_json()
        name = data.get('name', 'Test Account')
        initial_balance = data.get('balance', 0.0)
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Ensure table exists
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS accounts (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                balance DECIMAL(15, 2) DEFAULT 0.00,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            INSERT INTO accounts (name, balance) 
            VALUES (%s, %s) 
            RETURNING id, created_at
        ''', (name, initial_balance))
        
        row = cursor.fetchone()
        conn.commit()
        cursor.close()
        return_db_connection(conn)
        
        return jsonify({
            'id': row[0],
            'name': name,
            'balance': initial_balance,
            'created_at': row[1].isoformat()
        }), 201
    except Exception as e:
        logger.error(f"Error creating account: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/secret-info', methods=['GET'])
def secret_info():
    """
    Display information about the current secret configuration.
    This is for debugging/demo purposes only - DO NOT expose in production!
    """
    if os.getenv('ENABLE_SECRET_DEBUG', 'false').lower() != 'true':
        return jsonify({'error': 'Secret debug disabled'}), 403
    
    creds = secret_manager.get_database_credentials()
    return jsonify({
        'source': secret_manager.secret_source,
        'host': creds['host'],
        'port': creds['port'],
        'database': creds['database'],
        'user': creds['user'],
        'password_length': len(creds['password']),
        # Never expose the actual password!
        'password_preview': creds['password'][:3] + '***' if creds['password'] else 'EMPTY'
    })

@app.route('/api/v1/refresh-secrets', methods=['POST'])
def refresh_secrets():
    """
    Manually trigger a secret refresh and database pool recreation.
    Useful for testing secret rotation.
    """
    api_key = request.headers.get('X-API-Key')
    expected_key = os.getenv('API_KEY')
    
    if not expected_key or api_key != expected_key:
        return jsonify({'error': 'Unauthorized'}), 401
    
    try:
        refresh_db_pool()
        return jsonify({
            'status': 'success',
            'message': 'Secrets refreshed and connection pool recreated'
        })
    except Exception as e:
        logger.error(f"Error refreshing secrets: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint."""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# =============================================================================
# Main Entry Point
# =============================================================================

if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting Finance API on port {port}")
    logger.info(f"Secret source: {secret_manager.secret_source}")
    
    app.run(
        host='0.0.0.0',
        port=port,
        debug=debug,
        threaded=True
    )
