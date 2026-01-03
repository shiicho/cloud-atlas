# ===========================================
# Simple Flask Application
# Docker Fundamentals - Lesson 02
# ===========================================

from flask import Flask
import os

app = Flask(__name__)


@app.route('/')
def hello():
    """
    主页路由
    返回容器的 hostname，用于演示容器隔离
    """
    hostname = os.environ.get('HOSTNAME', 'unknown')
    return f'Hello from container: {hostname}\n'


@app.route('/health')
def health():
    """
    健康检查端点
    用于 Docker HEALTHCHECK 指令
    """
    return 'OK\n'


if __name__ == '__main__':
    # 绑定 0.0.0.0 允许外部访问
    # 生产环境应使用 gunicorn 等 WSGI 服务器
    app.run(host='0.0.0.0', port=5000)
