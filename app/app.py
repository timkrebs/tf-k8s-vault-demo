#!/usr/bin/env python3
"""
Vault Secrets Demo Application

This Flask application demonstrates how HashiCorp Vault secrets are automatically
synchronized to Kubernetes secrets via the Vault Secrets Operator (VSO).

The app reads secrets mounted as environment variables and displays them in a
web interface to showcase the integration.
"""

import os
import json
from datetime import datetime
from flask import Flask, render_template, jsonify

app = Flask(__name__)

def get_secret_info():
    """
    Retrieve secrets from environment variables that are populated
    from Kubernetes secrets (which in turn are synced from Vault via VSO)
    """
    secrets = {}
    
    # MyApp secrets from Vault path: secret/myapp
    myapp_secrets = {
        'username': os.getenv('MYAPP_USERNAME', 'Not found'),
        'password': '***' if os.getenv('MYAPP_PASSWORD') else 'Not found',
        'api_key': os.getenv('MYAPP_API_KEY', 'Not found')
    }
    
    # Database secrets from Vault path: secret/database  
    database_secrets = {
        'host': os.getenv('DATABASE_HOST', 'Not found'),
        'port': os.getenv('DATABASE_PORT', 'Not found'),
        'username': os.getenv('DATABASE_USERNAME', 'Not found'),
        'password': '***' if os.getenv('DATABASE_PASSWORD') else 'Not found'
    }
    
    return {
        'myapp': myapp_secrets,
        'database': database_secrets,
        'last_updated': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    }

def get_kubernetes_info():
    """Get Kubernetes environment information"""
    return {
        'namespace': os.getenv('POD_NAMESPACE', 'Unknown'),
        'pod_name': os.getenv('POD_NAME', 'Unknown'),
        'node_name': os.getenv('NODE_NAME', 'Unknown'),
        'service_account': os.getenv('SERVICE_ACCOUNT', 'default')
    }

@app.route('/')
def index():
    """Main dashboard showing all secrets and system info"""
    secrets = get_secret_info()
    k8s_info = get_kubernetes_info()
    
    return render_template('index.html', 
                         secrets=secrets, 
                         k8s_info=k8s_info)

@app.route('/api/secrets')
def api_secrets():
    """API endpoint to get secrets as JSON"""
    return jsonify(get_secret_info())

@app.route('/api/health')
def health_check():
    """Health check endpoint for Kubernetes probes"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/vault-status')
def vault_status():
    """Check if secrets are properly loaded from Vault"""
    secrets = get_secret_info()
    
    # Count how many secrets are properly loaded
    myapp_loaded = sum(1 for v in secrets['myapp'].values() if v != 'Not found')
    db_loaded = sum(1 for v in secrets['database'].values() if v != 'Not found')
    
    total_expected = 7  # 3 myapp + 4 database secrets
    total_loaded = myapp_loaded + db_loaded
    
    status = 'healthy' if total_loaded == total_expected else 'partial'
    if total_loaded == 0:
        status = 'failed'
    
    return jsonify({
        'status': status,
        'secrets_loaded': total_loaded,
        'secrets_expected': total_expected,
        'myapp_secrets': myapp_loaded,
        'database_secrets': db_loaded,
        'last_check': datetime.now().isoformat()
    })

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
