
# SOCKS5 代理服务器一键部署脚本 (SOCKS5 Proxy One-Click Deployment)


一份功能强大且易于使用的 Bash 脚本，用于在任何支持 Docker 的 Linux 服务器上一键部署一个安全、稳定、高性能的 SOCKS5 代理服务器。特别适用于需要为指纹浏览器（如 AdsPower、VMLogin）或其他应用配置独立 IP 代理的场景。



## ✨ 主要特性

- **🚀 一键部署**: 只需执行一个命令，即可完成所有环境检查、依赖安装、配置和部署工作。
- **📦 Docker 容器化**: 所有服务运行在隔离的 Docker 容器中，干净、便携且不污染宿主系统。
- **🔒 安全可靠**: 自动生成强随机密码，使用 3proxy 的 `strong` 认证模式，确保代理安全。
- **⚙️ 高度可定制**: 支持使用默认随机生成的凭据，也支持完全自定义用户名、密码和端口。
- **🔧 便捷管理**: 自动生成 `manage.sh` 脚本，轻松实现服务的启动、停止、重启、查看状态和日志。
- **🩺 健康检查**: 内置 Docker 健康检查，确保服务异常时能够被监控到。
- **🔥 自动防火墙配置**: 自动检测并配置 `UFW` 或 `firewalld`，开放所需端口。
- **📄 清晰的连接信息**: 部署完成后，自动生成 `connection_info.txt` 文件，包含所有连接细节和管理命令，方便查阅。

## 🛠️ 系统要求

- 一台 Linux 服务器 (推荐使用 Debian 10/11/12 或 Ubuntu 20.04/22.04)
- `root` 用户权限
- 服务器已连接到互联网

## ⚡ 快速开始

通过 SSH 连接到您的 Linux 服务器，并以 `root` 用户身份执行以下命令。

### 1. 下载脚本

从您的代码仓库或指定 URL 下载部署脚本。 `full_deploy.sh`。

```bash
wget [您的脚本下载链接]/full_deploy.sh
```

### 2. 授予执行权限

```bash
chmod +x full_deploy.sh
```

### 3. 运行部署脚本

```bash
./full_deploy.sh
```

### 4. 跟随向导进行配置

脚本启动后，会提示您进行配置：
- **检查环境**: 脚本会自动检查并安装 Docker 和 Docker Compose。
- **配置参数**:
    - 您可以选择使用 **默认配置**（推荐），脚本将为您生成安全的随机用户名和密码。
    - 您也可以选择 **自定义配置**，手动输入您想要的用户名、密码和端口号。

部署过程大约需要几分钟，具体取决于您的网络速度和服务器性能。当您看到 "🎉 部署完成！" 的提示时，表示您的 SOCKS5 代理服务器已成功启动并准备就绪。

## 🔧 服务管理

脚本在部署目录 `/opt/socks5-proxy-server` 下创建了一个 `manage.sh` 管理脚本，方便您对服务进行日常维护。

首先，进入项目目录：
```bash
cd /opt/socks5-proxy-server
```

然后，使用以下命令进行管理：

| 命令 | 描述 |
| :--- | :--- |
| `./manage.sh start` | 启动 SOCKS5 代理服务 |
| `./manage.sh stop` | 停止 SOCKS5 代理服务（会移除容器） |
| `./manage.sh restart` | 重启 SOCKS5 代理服务 |
| `./manage.sh status` | 查看服务的运行状态和健康状况 |
| `./manage.sh logs` | 实时查看服务日志 (按 `Ctrl+C` 退出) |
| `./manage.sh info` | 显示完整的连接信息（IP、端口、用户名、密码） |
| `./manage.sh rebuild` | **强制重新构建** 镜像并启动，适用于修改配置后 |

## 📁 项目文件结构

所有文件都位于 `/opt/socks5-proxy-server/` 目录下：

```
/opt/socks5-proxy-server/
├── 3proxy.cfg              # 3proxy 核心配置文件，包含用户认证信息
├── connection_info.txt     # 部署后生成的连接信息详情
├── docker-compose.yml      # Docker Compose 编排文件
├── Dockerfile              # 用于构建代理服务的 Docker 镜像定义
└── manage.sh               # 服务管理脚本
```

## ❓ 常见问题 (FAQ)

**1. 如何修改代理的用户名或密码？**
   1. 进入项目目录: `cd /opt/socks5-proxy-server`
   2. 编辑配置文件: `nano 3proxy.cfg`
   3. 找到 `users ...` 这一行，修改为您想要的用户名和密码。
   4. 保存文件后，执行 `./manage.sh rebuild` 来使更改生效。

**2. 如何测试代理是否工作正常？**
   在您的服务器上，可以运行 `connection_info.txt` 文件中提供的测试命令：
   ```bash
   # 请将命令中的 USERNAME:PASSWORD@127.0.0.1:PORT 替换为您的实际信息
   curl --socks5-hostname USERNAME:PASSWORD@127.0.0.1:PORT https://ifconfig.me
   ```
   如果命令成功返回您服务器的 IP 地址，则表示代理工作正常。

**3. 如何完全卸载此代理服务？**
   1. 进入项目目录: `cd /opt/socks5-proxy-server`
   2. 停止并移除容器: `./manage.sh stop`
   3. 返回上一级目录: `cd /`
   4. 删除整个项目目录: `rm -rf /opt/socks5-proxy-server`
   5. (可选) 删除 Docker 镜像: `docker rmi $(docker images | grep 'socks5-proxy-server' | awk '{print $3}')`

   这样就彻底清除了所有相关文件和 Docker 镜像。

**4. 部署失败或服务启动不起来怎么办？**
   请进入项目目录 `cd /opt/socks5-proxy-server`，然后运行 `./manage.sh logs` 查看详细的错误日志，根据日志提示解决问题。常见的错误原因包括端口被占用、Docker 构建失败等。

## 🛡️ 安全提示

- 请务必使用 **强密码** 来保护您的代理服务。
- 定期更新您的服务器系统和 Docker，以获得最新的安全补丁。
- 请勿将您的代理凭据泄露给他人。

## 📄 开源许可

本项目采用 [MIT License](https://opensource.org/licenses/MIT) 许可。