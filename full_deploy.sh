#!/bin/bash

# =============================================================================
# SOCKS5代理服务器完整部署脚本（适用于指纹浏览器）
# 作者: Assistant
# 版本: 1.4 - 修复日志权限问题
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目信息
PROJECT_NAME="socks5-proxy-server"
WORK_DIR="/opt/$PROJECT_NAME"

# 打印标题
print_title() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "               SOCKS5 代理服务器部署脚本"
    echo "               适用于指纹浏览器等应用 (v1.4)"
    echo "=================================================================="
    echo -e "${NC}"
}

# 检查系统要求
check_requirements() {
    echo -e "${YELLOW}检查系统要求...${NC}"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用root用户运行此脚本${NC}"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker未安装，正在安装...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}✓ Docker安装完成${NC}"
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Docker Compose未安装，正在安装...${NC}"
        apt-get update && apt-get install -y docker-compose-plugin || \
        (curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose)
        echo -e "${GREEN}✓ Docker Compose安装完成${NC}"
    fi

    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    echo -e "${YELLOW}清理旧的容器和镜像...${NC}"
    docker stop socks5-proxy-server 2>/dev/null || true
    docker rm socks5-proxy-server 2>/dev/null || true
    docker rmi $(docker images | grep 'socks5-proxy-server' | awk '{print $3}') 2>/dev/null || true
    
    echo -e "${GREEN}✓ 系统要求检查完成${NC}"
}

# 用户配置
setup_config() {
    echo -e "${YELLOW}配置SOCKS5代理参数...${NC}"
    
    SOCKS_USER="proxy_$(openssl rand -hex 4)"
    SOCKS_PASS="$(openssl rand -base64 16)"
    SOCKS_PORT="1080"
    
    echo -e "${BLUE}是否使用默认配置？${NC}"
    echo "默认用户名: $SOCKS_USER"
    echo "默认密码: $SOCKS_PASS"
    echo "默认端口: $SOCKS_PORT"
    echo ""
    read -p "使用默认配置？(y/n) [y]: " use_default
    
    if [[ $use_default == "n" || $use_default == "N" ]]; then
        read -p "请输入SOCKS5用户名: " SOCKS_USER
        read -s -p "请输入SOCKS5密码: " SOCKS_PASS
        echo ""
        read -p "请输入端口号 (默认1080): " custom_port
        SOCKS_PORT=${custom_port:-1080}
    fi
    
    while ss -tuln 2>/dev/null | grep -q ":$SOCKS_PORT " || netstat -tuln 2>/dev/null | grep -q ":$SOCKS_PORT "; do
        echo -e "${RED}错误: 端口 $SOCKS_PORT 已被占用${NC}"
        read -p "请输入其他端口号: " SOCKS_PORT
    done
    
    echo -e "${GREEN}✓ 配置完成${NC}"
}

# 创建项目文件
create_project_files() {
    echo -e "${YELLOW}创建项目文件...${NC}"

    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    if [[ -d "$WORK_DIR" ]]; then
        echo -e "${YELLOW}移除旧的项目目录...${NC}"
        cd "$WORK_DIR"
        $COMPOSE_CMD down 2>/dev/null || true
        cd /
        rm -rf "$WORK_DIR"
    fi
    
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 创建3proxy配置文件
#     cat > 3proxy.cfg << EOF
# # 3proxy配置文件
# nserver 8.8.8.8
# nserver 8.8.4.4
# nscache 65536
# timeouts 1 5 30 60 180 1800 15 60

# # 修正: 移除日志轮替标志'D'，以防止在/dev/目录下创建文件导致权限问题。
# # 这样配置会直接将日志输出到标准输出流，由Docker管理。
# log /dev/stdout

# logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
# auth strong
# users $SOCKS_USER:CL:$SOCKS_PASS
# allow $SOCKS_USER
# socks -p$SOCKS_PORT

    cat > 3proxy.cfg << EOF
# DNS 建议保留，必要时你可换成自己可信的 DoH/企业 DNS
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
# 放宽时间参数：# accept=30s, connect=120s, io=3600s(1h), dns=60s, tcpfin=600s, keepalive=86400s(1d), dnsretry=15s, session=0(无限)
# timeouts  <accept> <connect> <io> <dnsresolv> <tcpfin> <keepalive> <dnsretry> <session>
timeouts 30 120 3600 60 600 86400 15 0
log /dev/stdout
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"

auth strong
users $SOCKS_USER:CL:$SOCKS_PASS
allow $SOCKS_USER

# 同时开启 SOCKS5 和 HTTP CONNECT 两个入口
# 1) SOCKS5（原有）
socks -p$SOCKS_PORT

# 2) HTTP 代理（新增一个端口，比如 8118；-n 关闭本地解析，全部走隧道）
proxy -p8118 -n

EOF

    # 创建Dockerfile
    cat > Dockerfile << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    wget \
    ca-certificates \
    tzdata \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN wget -q https://github.com/3proxy/3proxy/archive/0.9.4.tar.gz && \
    tar -xzf 0.9.4.tar.gz && \
    cd 3proxy-0.9.4 && \
    make -f Makefile.Linux && \
    cp bin/3proxy /usr/local/bin/ && \
    chmod +x /usr/local/bin/3proxy && \
    cd / && rm -rf /tmp/*

RUN mkdir -p /etc/3proxy && \
    (id -u proxy &>/dev/null || useradd -r -s /bin/false proxy)

COPY 3proxy.cfg /etc/3proxy/3proxy.cfg

RUN chown proxy:proxy /etc/3proxy/3proxy.cfg

ARG SOCKS_PORT=1080
EXPOSE $SOCKS_PORT

USER proxy

WORKDIR /etc/3proxy

CMD ["/usr/local/bin/3proxy", "/etc/3proxy/3proxy.cfg"]
EOF

    # 创建docker-compose.yml
    cat > docker-compose.yml << EOF
services:
  socks5-proxy:
    build:
      context: .
      args:
        SOCKS_PORT: $SOCKS_PORT
    container_name: socks5-proxy-server
    ports:
      - "$SOCKS_PORT:$SOCKS_PORT"
      - "8118:8118"
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai
    healthcheck:
      test: ["CMD", "netstat", "-tuln", "|", "grep", ":$SOCKS_PORT"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

    # 创建管理脚本
    cat > manage.sh << 'EOF'
#!/bin/bash
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
case "$1" in
    start)
        echo -e "${GREEN}启动SOCKS5代理服务器...${NC}"
        $COMPOSE_CMD up -d;;
    stop)
        echo -e "${YELLOW}停止SOCKS5代理服务器...${NC}"
        $COMPOSE_CMD down;;
    restart)
        echo -e "${YELLOW}重启SOCKS5代理服务器...${NC}"
        $COMPOSE_CMD restart;;
    status)
        echo -e "${GREEN}服务状态:${NC}"
        $COMPOSE_CMD ps
        echo -e "\n${GREEN}健康检查:${NC}"
        health_status=$(docker inspect socks5-proxy-server --format='{{.State.Health.Status}}' 2>/dev/null)
        echo "${health_status:-未知}";;
    logs)
        echo -e "${GREEN}查看日志:${NC}"
        $COMPOSE_CMD logs -f --tail=50;;
    rebuild)
        echo -e "${YELLOW}重新构建并启动...${NC}"
        $COMPOSE_CMD down
        $COMPOSE_CMD build --no-cache
        $COMPOSE_CMD up -d;;
    info)
        echo -e "${GREEN}连接信息:${NC}"
        cat connection_info.txt 2>/dev/null || echo "配置文件不存在";;
    *)
        echo "使用方法: $0 {start|stop|restart|status|logs|rebuild|info}"
        exit 1;;
esac
EOF

    chmod +x manage.sh
    
    echo -e "${GREEN}✓ 项目文件创建完成${NC}"
}

# 部署服务
deploy_service() {
    echo -e "${YELLOW}部署SOCKS5代理服务器...${NC}"
    
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    echo -e "${YELLOW}构建Docker镜像...${NC}"
    $COMPOSE_CMD build --no-cache
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}✗ Docker镜像构建失败${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}启动服务...${NC}"
    $COMPOSE_CMD up -d
    
    if ! $COMPOSE_CMD ps | grep -q "Up"; then
        echo -e "${RED}✗ 服务启动失败${NC}"
        echo "请查看日志获取详细信息:"
        $COMPOSE_CMD logs
        exit 1
    fi

    echo -e "${YELLOW}等待健康检查通过...${NC}"
    for i in {1..20}; do
        health_status=$(docker inspect socks5-proxy-server --format='{{.State.Health.Status}}' 2>/dev/null)
        if [[ "$health_status" == "healthy" ]]; then
            echo -e "\n${GREEN}✓ 服务健康检查通过${NC}"
            return 0
        elif [[ "$health_status" == "unhealthy" ]]; then
            echo -e "\n${RED}✗ 服务健康检查失败${NC}"
            echo "请查看日志获取详细信息:"
            $COMPOSE_CMD logs --tail=50
            exit 1
        fi
        echo -n "."
        sleep 2
    done
    
    echo -e "\n${YELLOW}⚠ 健康检查超时。服务可能仍在启动或存在问题。${NC}"
    echo "请使用 ./manage.sh logs 查看日志。"
    exit 1
}

# 其他函数 (setup_firewall, generate_connection_info, show_completion) ...
setup_firewall() {
    echo -e "${YELLOW}配置防火墙...${NC}"
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $SOCKS_PORT/tcp >/dev/null 2>&1
        echo -e "${GREEN}✓ UFW防火墙已允许端口 $SOCKS_PORT ${NC}"
    fi
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=$SOCKS_PORT/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${GREEN}✓ firewalld防火墙已允许端口 $SOCKS_PORT ${NC}"
    fi
}
generate_connection_info() {
    echo -e "${YELLOW}生成连接信息...${NC}"
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    cat > connection_info.txt << EOF
================================================================
                SOCKS5代理服务器连接信息
================================================================
🌐 服务器信息:
   IP地址: $SERVER_IP
   端口: $SOCKS_PORT
   协议: SOCKS5
🔐 认证信息:
   用户名: $SOCKS_USER
   密码: $SOCKS_PASS
📱 指纹浏览器配置:
   代理类型: Socks5
   代理主机: $SERVER_IP
   代理端口: $SOCKS_PORT
   代理账号: $SOCKS_USER
   代理密码: $SOCKS_PASS
🔧 管理命令 (进入项目目录后执行):
   cd $WORK_DIR
   ./manage.sh start      # 启动服务
   ./manage.sh stop       # 停止服务
   ./manage.sh restart    # 重启服务
   ./manage.sh status     # 查看状态
   ./manage.sh logs       # 查看日志
   ./manage.sh info       # 查看连接信息
   ./manage.sh rebuild    # 强制重新构建并启动
🧪 连接测试 (在服务器上执行):
   curl --socks5-hostname $SOCKS_USER:$SOCKS_PASS@127.0.0.1:$SOCKS_PORT https://ifconfig.me
================================================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
================================================================
EOF
    echo -e "${GREEN}✓ 连接信息已保存到: $WORK_DIR/connection_info.txt${NC}"
}
show_completion() {
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "${GREEN}"
    echo "=================================================================="
    echo "                    🎉 部署完成！"
    echo "=================================================================="
    echo -e "${NC}"
    echo -e "${BLUE}📋 连接信息:${NC}"
    echo "服务器地址: $SERVER_IP"
    echo "端口: $SOCKS_PORT"
    echo "用户名: $SOCKS_USER"
    echo "密码: $SOCKS_PASS"
    echo ""
    echo -e "${BLUE}🔧 管理命令:${NC}"
    echo "cd $WORK_DIR"
    echo "./manage.sh status     # 查看状态"
    echo "./manage.sh logs       # 查看日志"
    echo ""
    echo -e "${YELLOW}⚠️  重要提醒:${NC}"
    echo "1. 请妥善保存您的用户名和密码。"
    echo "2. 完整的连接信息已保存到: ${GREEN}$WORK_DIR/connection_info.txt${NC}"
    echo "3. 服务已设置为开机自动启动。"
    echo ""
}

# 主函数
main() {
    print_title
    check_requirements
    setup_config
    create_project_files
    deploy_service
    setup_firewall
    generate_connection_info
    show_completion
}

main