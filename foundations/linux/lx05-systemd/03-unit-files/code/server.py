#!/usr/bin/env python3
"""
Simple HTTP server for systemd demo.

This script demonstrates a basic web server that can be managed by systemd.
It reads configuration from environment variables and handles graceful shutdown.

Usage:
    1. Copy this file to /opt/mywebapp/server.py
    2. Create the Unit file from mywebapp.service
    3. Start with: systemctl start mywebapp
    4. Test with: curl http://localhost:8080

Environment Variables:
    PORT: HTTP port to listen on (default: 8080)
    BIND: Address to bind to (default: 0.0.0.0)
"""

import http.server
import socketserver
import os
import signal
import sys
import datetime


# Read configuration from environment
PORT = int(os.environ.get('PORT', 8080))
BIND = os.environ.get('BIND', '0.0.0.0')


class HealthHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler with health check endpoint."""

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/health':
            self._send_response(200, 'OK\n')
        elif self.path == '/':
            message = f"""Hello from mywebapp!
Server Time: {datetime.datetime.now().isoformat()}
PORT: {PORT}
BIND: {BIND}
PID: {os.getpid()}
"""
            self._send_response(200, message)
        else:
            self._send_response(404, 'Not Found\n')

    def _send_response(self, code, message):
        """Send HTTP response."""
        self.send_response(code)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(message.encode())

    def log_message(self, format, *args):
        """Log to stdout (captured by systemd journal)."""
        print(f"[{self.log_date_time_string()}] {args[0]}")


def graceful_shutdown(signum, frame):
    """Handle shutdown signals gracefully."""
    signal_name = signal.Signals(signum).name
    print(f"Received {signal_name}, shutting down gracefully...")
    sys.exit(0)


def main():
    """Main entry point."""
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, graceful_shutdown)
    signal.signal(signal.SIGINT, graceful_shutdown)

    print(f"Starting server on {BIND}:{PORT}")
    print(f"PID: {os.getpid()}")
    print(f"Health check: http://{BIND}:{PORT}/health")

    # Allow socket reuse (helps with quick restarts)
    socketserver.TCPServer.allow_reuse_address = True

    try:
        with socketserver.TCPServer((BIND, PORT), HealthHandler) as httpd:
            print("Server is ready to accept connections")
            httpd.serve_forever()
    except OSError as e:
        print(f"Error starting server: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
