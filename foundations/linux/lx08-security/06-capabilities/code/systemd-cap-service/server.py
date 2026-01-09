#!/usr/bin/env python3
# =============================================================================
# Capability Demo Server - server.py
# =============================================================================
#
# PURPOSE: Simple HTTP server demonstrating CAP_NET_BIND_SERVICE
#
# This server binds to port 80 (a privileged port) but runs as a non-root user.
# This is made possible by the CAP_NET_BIND_SERVICE capability granted via
# systemd's AmbientCapabilities directive.
#
# WITHOUT the capability, you would see:
#   PermissionError: [Errno 13] Permission denied
#
# WITH the capability (via systemd), the server starts successfully.
#
# =============================================================================

import http.server
import socketserver
import os
import signal
import sys
from datetime import datetime

# Configuration
PORT = 80
BIND_ADDRESS = "0.0.0.0"


def get_process_capabilities():
    """Read and return process capabilities from /proc/self/status"""
    caps = {}
    try:
        with open("/proc/self/status", "r") as f:
            for line in f:
                if line.startswith("Cap"):
                    parts = line.strip().split(":\t")
                    if len(parts) == 2:
                        caps[parts[0]] = parts[1]
    except Exception as e:
        caps["error"] = str(e)
    return caps


class CapabilityDemoHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler that shows capability information"""

    def do_GET(self):
        """Handle GET requests with capability info"""
        if self.path == "/" or self.path == "/status":
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            caps = get_process_capabilities()

            html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Capability Demo Server</title>
    <style>
        body {{
            font-family: 'Courier New', monospace;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #1a1a2e;
            color: #eee;
        }}
        h1 {{ color: #00ff88; }}
        h2 {{ color: #00aaff; }}
        .info {{ background: #16213e; padding: 15px; margin: 10px 0; border-radius: 5px; }}
        .success {{ color: #00ff88; }}
        .warning {{ color: #ffaa00; }}
        table {{ border-collapse: collapse; width: 100%; }}
        td, th {{ border: 1px solid #333; padding: 8px; text-align: left; }}
        th {{ background: #16213e; }}
        code {{ background: #0f3460; padding: 2px 6px; border-radius: 3px; }}
    </style>
</head>
<body>
    <h1>Linux Capabilities Demo Server</h1>

    <div class="info">
        <p class="success">Server is running on port {PORT} as a non-root user!</p>
        <p>This demonstrates <code>CAP_NET_BIND_SERVICE</code> capability.</p>
    </div>

    <h2>Process Information</h2>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>PID</td><td>{os.getpid()}</td></tr>
        <tr><td>UID</td><td>{os.getuid()}</td></tr>
        <tr><td>GID</td><td>{os.getgid()}</td></tr>
        <tr><td>EUID</td><td>{os.geteuid()}</td></tr>
        <tr><td>EGID</td><td>{os.getegid()}</td></tr>
        <tr><td>Working Dir</td><td>{os.getcwd()}</td></tr>
        <tr><td>Timestamp</td><td>{datetime.now().isoformat()}</td></tr>
    </table>

    <h2>Process Capabilities</h2>
    <table>
        <tr><th>Capability Set</th><th>Hex Value</th><th>Description</th></tr>
        <tr>
            <td>CapInh (Inheritable)</td>
            <td><code>{caps.get('CapInh', 'N/A')}</code></td>
            <td>Preserved across execve()</td>
        </tr>
        <tr>
            <td>CapPrm (Permitted)</td>
            <td><code>{caps.get('CapPrm', 'N/A')}</code></td>
            <td>Maximum available capabilities</td>
        </tr>
        <tr>
            <td>CapEff (Effective)</td>
            <td><code>{caps.get('CapEff', 'N/A')}</code></td>
            <td>Currently active capabilities</td>
        </tr>
        <tr>
            <td>CapBnd (Bounding)</td>
            <td><code>{caps.get('CapBnd', 'N/A')}</code></td>
            <td>Upper limit on acquirable caps</td>
        </tr>
        <tr>
            <td>CapAmb (Ambient)</td>
            <td><code>{caps.get('CapAmb', 'N/A')}</code></td>
            <td>Passed to non-privileged programs</td>
        </tr>
    </table>

    <h2>How It Works</h2>
    <div class="info">
        <p>This server runs as a <strong>non-root user</strong> but binds to port 80.</p>
        <p>Normally, ports below 1024 require root privileges.</p>
        <p>With <code>CAP_NET_BIND_SERVICE</code>, we can bind low ports without root!</p>
    </div>

    <h2>systemd Configuration</h2>
    <div class="info">
        <pre>
[Service]
User=capdemo
Group=capdemo
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
        </pre>
    </div>

    <h2>Key Points</h2>
    <ul>
        <li>Capabilities split root privileges into fine-grained permissions</li>
        <li><code>AmbientCapabilities</code> grants caps to non-root services</li>
        <li><code>CapabilityBoundingSet</code> limits what can be acquired</li>
        <li><code>NoNewPrivileges</code> prevents SUID exploitation</li>
        <li class="warning">Avoid <code>CAP_SYS_ADMIN</code> - it's almost root!</li>
    </ul>

    <h2>Verification Commands</h2>
    <div class="info">
        <pre>
# Check service status
systemctl status cap-demo

# Check listening ports
ss -tlnp | grep :80

# Check process capabilities
PID=$(systemctl show cap-demo -p MainPID --value)
cat /proc/$PID/status | grep Cap

# Decode capabilities
capsh --decode=$(cat /proc/$PID/status | grep CapEff | awk '{{print $2}}')
        </pre>
    </div>
</body>
</html>
"""
            self.wfile.write(html.encode())
        else:
            super().do_GET()

    def log_message(self, format, *args):
        """Override to add timestamp and capability info"""
        print(f"[{datetime.now().isoformat()}] {self.client_address[0]} - {format % args}")


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    print(f"\n[{datetime.now().isoformat()}] Received signal {signum}, shutting down...")
    sys.exit(0)


def main():
    """Main entry point"""
    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Print startup info
    print("=" * 60)
    print(" Linux Capabilities Demo Server")
    print("=" * 60)
    print(f"Time:       {datetime.now().isoformat()}")
    print(f"PID:        {os.getpid()}")
    print(f"UID:        {os.getuid()}")
    print(f"GID:        {os.getgid()}")
    print(f"Binding:    {BIND_ADDRESS}:{PORT}")
    print()

    # Show capabilities
    print("Process Capabilities:")
    caps = get_process_capabilities()
    for key, value in caps.items():
        print(f"  {key}: {value}")
    print()

    # Check if we can bind to the port
    print(f"Attempting to bind to port {PORT}...")

    try:
        # Create server
        with socketserver.TCPServer((BIND_ADDRESS, PORT), CapabilityDemoHandler) as httpd:
            print(f"SUCCESS! Server listening on {BIND_ADDRESS}:{PORT}")
            print()
            print("Access the server at:")
            print(f"  http://localhost:{PORT}/")
            print(f"  http://localhost:{PORT}/status")
            print()
            print("Press Ctrl+C to stop")
            print("=" * 60)

            # Serve forever
            httpd.serve_forever()

    except PermissionError as e:
        print(f"FAILED: {e}")
        print()
        print("This error occurs because:")
        print("  - Ports below 1024 require special privileges")
        print("  - Running as non-root user without CAP_NET_BIND_SERVICE")
        print()
        print("Solutions:")
        print("  1. Use systemd with AmbientCapabilities=CAP_NET_BIND_SERVICE")
        print("  2. Run: setcap 'cap_net_bind_service=+ep' /path/to/python3")
        print("     (Not recommended for interpreters!)")
        sys.exit(1)

    except OSError as e:
        print(f"ERROR: {e}")
        if "Address already in use" in str(e):
            print("Port 80 is already in use by another process.")
            print("Check with: ss -tlnp | grep :80")
        sys.exit(1)


if __name__ == "__main__":
    main()
