#!/bin/bash

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本 (sudo)。${NC}"
    exit 1
fi

# 检查命令执行是否成功
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: $1 失败，请检查！${NC}"
        exit 1
    fi
}

# 检查 Docker 服务
check_docker_service() {
    if ! systemctl is-active --quiet docker; then
        echo -e "${RED}Docker 服务未运行，正在启动...${NC}"
        systemctl start docker
        check_error "启动 Docker 服务"
    fi
}

# 检查程序是否已安装
check_installed() {
    local cmd=$1
    local name=$2
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}$name 已安装，跳过安装。${NC}"
        return 0
    fi
    return 1
}

# 检查 apt 包是否已安装
check_apt_package() {
    local pkg=$1
    if dpkg -l | grep -q "$pkg"; then
        echo -e "${GREEN}$pkg 已安装，跳过安装。${NC}"
        return 0
    fi
    return 1
}

# 检查 pip 包是否已安装
check_pip_package() {
    local pkg=$1
    if pip3 show "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}Python 包 $pkg 已安装，跳过安装。${NC}"
        return 0
    fi
    return 1
}

# 一键部署函数
deploy_project() {
    echo -e "${GREEN}开始一键部署...${NC}"

    # 更新系统包
    echo "更新系统包..."
    apt-get update
    check_error "更新系统包"

    # 检查并安装必要工具
    for pkg in apt-transport-https ca-certificates curl software-properties-common jq; do
        if ! check_apt_package "$pkg"; then
            echo "安装 $pkg..."
            apt-get install -y "$pkg"
            check_error "安装 $pkg"
        fi
    done

    # 检查并安装 Docker
    if ! check_installed docker Docker; then
        echo "添加 Docker GPG 密钥..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        check_error "添加 Docker GPG 密钥"

        echo "添加 Docker 仓库..."
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        check_error "添加 Docker 仓库"

        apt-get update
        check_error "更新包列表"

        echo "安装 Docker..."
        apt-get install -y docker-ce
        check_error "安装 Docker"

        echo "启用 Docker 服务..."
        systemctl enable docker
        check_error "启用 Docker 服务"
    fi

    # 启动 Docker 服务
    check_docker_service

    # 检查并安装 Docker Compose
    if ! check_installed docker-compose "Docker Compose"; then
        echo "安装 Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        check_error "下载 Docker Compose"
        chmod +x /usr/local/bin/docker-compose
        check_error "设置 Docker Compose 权限"
    fi

    # 检查并安装 Python 和相关工具
    for pkg in python3 python3-pip python3.10-venv; do
        if ! check_apt_package "$pkg"; then
            echo "安装 $pkg..."
            apt-get install -y "$pkg"
            check_error "安装 $pkg"
        fi
    done

    # 检查并安装 Poetry
    if ! check_installed poetry Poetry; then
        echo "安装 Poetry..."
        curl -sSL https://install.python-poetry.org | python3 -
        check_error "安装 Poetry"
        # 确保 Poetry 可执行
        export PATH="$HOME/.local/bin:$PATH"
    fi

    # 克隆项目
    echo "克隆项目..."
    if [ -d "node" ]; then
        echo "node 目录已存在，跳过克隆"
    else
        git clone https://github.com/NapthaAI/node.git
        check_error "克隆项目"
    fi

    # 进入项目目录
    cd node || { echo -e "${RED}进入 node 目录失败！${NC}"; exit 1; }

    # 提示用户输入用户名
    echo -e "${YELLOW}请输入用户名（用于生成密钥文件，例如输入 'abc' 将生成 'abc.pem'）:${NC}"
    read username
    if [ -z "$username" ]; then
        echo -e "${RED}用户名不能为空！${NC}"
        exit 1
    fi
    # 保存用户名到文件
    echo "$username" > username.txt
    check_error "保存用户名"

    # 检查并创建虚拟环境
    if [ ! -d ".venv" ]; then
        echo "创建 Python 虚拟环境..."
        python3 -m venv .venv
        check_error "创建虚拟环境"
    fi

    # 激活虚拟环境
    source .venv/bin/activate
    check_error "激活虚拟环境"

    # 检查并升级 pip
    if ! pip3 list --outdated | grep -q pip; then
        echo -e "${GREEN}pip 已为最新版本，跳过升级。${NC}"
    else
        echo "升级 pip..."
        pip install --upgrade pip
        check_error "升级 pip"
    fi

    # 检查并安装 Python 依赖
    for pkg in docker requests; do
        if ! check_pip_package "$pkg"; then
            echo "安装 Python 包 $pkg..."
            pip install "$pkg"
            check_error "安装 $pkg"
        fi
    done

    # 配置 .env 文件
    echo "配置 .env 文件..."
    if [ ! -f ".env" ]; then
        cp .env.example .env
        check_error "复制 .env 文件"
    fi
    sed -i 's/LAUNCH_DOCKER=false/LAUNCH_DOCKER=true/' .env
    check_error "修改 LAUNCH_DOCKER 配置"
    sed -i 's|HF_HOME=/home/<youruser>/.cache/huggingface|HF_HOME=/root/.cache/huggingface|' .env
    check_error "修改 HF_HOME 配置"

    # 运行 launch.sh
    echo "运行 launch.sh..."
    bash launch.sh
    check_error "运行 launch.sh"

    echo -e "${GREEN}部署完成！${NC}"
}

# 手动重启函数
restart_project() {
    echo -e "${GREEN}开始手动重启...${NC}"

    # 检查 screen 是否安装
    if ! check_installed screen "Screen"; then
        echo "安装 screen..."
        apt-get install -y screen
        check_error "安装 screen"
    fi

    # 检查 node 目录是否存在
    if [ ! -d "node" ]; then
        echo -e "${RED}node 目录不存在，请先部署项目！${NC}"
        return
    fi

    # 检查是否存在名为 naptha 的 screen 会话
    if screen -ls | grep -q "naptha"; then
        echo "找到现有的 naptha screen 会话，正在删除..."
        screen -S naptha -X quit
        check_error "删除 naptha screen 会话"
    else
        echo "未找到 lea screen 会话，将创建新的会话..."
    fi

    # 创建新的 screen 会话并运行 launch.sh
    echo "创建新的 naptha screen 会话并运行 launch.sh..."
    screen -dmS naptha bash -c "cd node && bash launch.sh"
    check_error "创建 naptha screen 会话并运行 launch.sh"

    echo -e "${GREEN}手动重启完成！可以使用 'screen -r naptha' 查看会话。${NC}"
}

# 查看日志子菜单
show_log_menu() {
    echo -e "${YELLOW}=== 查看日志 ===${NC}"
    echo "1. 查看 node-ollama 日志"
    echo "2. 查看 node-rabbitmq 日志"
    echo "0. 返回主菜单"
    echo -e "${YELLOW}请输入选项 (0-2):${NC}"
}

# 查看日志函数
view_logs() {
    check_docker_service
    while true; do
        show_log_menu
        read log_choice
        case $log_choice in
            1)
                echo -e "${GREEN}查看 node-ollama 日志...${NC}"
                if docker ps -a | grep -q node-ollama; then
                    docker logs -f node-ollama
                else
                    echo -e "${RED}未找到 node-ollama 容器，请确认项目已部署！${NC}"
                fi
                ;;
            2)
                echo -e "${GREEN}查看 node-rabbitmq 日志...${NC}"
                if docker ps -a | grep -q node-rabbitmq; then
                    docker logs -f node-rabbitmq
                else
                    echo -e "${RED}未找到 node-rabbitmq 容器，请确认项目已部署！${NC}"
                fi
                ;;
            0)
                echo -e "${GREEN}返回主菜单${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选项，请输入 0-2！${NC}"
                ;;
        esac
        echo
    done
}

# 导出秘钥函数
export_keys() {
    echo -e "${GREEN}导出秘钥...${NC}"
    if [ -d "node" ]; then
        echo "进入 node 目录..."
        cd node || { echo -e "${RED}进入 node 目录失败！${NC}"; return; }

        # 检查是否有保存的用户名
        if [ -f "username.txt" ]; then
            username=$(cat username.txt)
            pem_file="${username}.pem"
            if [ -f "$pem_file" ]; then
                echo "找到秘钥文件: $pem_file"
                echo "以下是秘钥文件内容："
                cat "$pem_file"
                echo
            else
                echo -e "${RED}未找到秘钥文件 $pem_file，请确认项目已正确部署！${NC}"
            fi
        else
            echo -e "${YELLOW}未找到保存的用户名，尝试列出所有 .pem 文件...${NC}"
            if ls *.pem >/dev/null 2>&1; then
                for pem_file in *.pem; do
                    echo "找到秘钥文件: $pem_file"
                    echo "以下是秘钥文件内容："
                    cat "$pem_file"
                    echo
                done
            else
                echo -e "${RED}未在 node 目录下找到任何 .pem 文件，请确认项目已部署或秘钥文件存在！${NC}"
            fi
        fi

        echo "返回上一级目录..."
        cd ..
    else
        echo -e "${RED}node 目录不存在，请先部署项目！${NC}"
    fi
}

# 主菜单
show_menu() {
    echo -e "${YELLOW}=== NapthaAI 项目自动化脚本 ===${NC}"
    echo "1. 一键部署"
    echo "2. 查看日志"
    echo "3. 导出秘钥"
    echo "4. 手动重启"
    echo "0. 退出脚本"
    echo -e "${YELLOW}请输入选项 (0-4):${NC}"
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1)
            deploy_project
            ;;
        2)
            view_logs
            ;;
        3)
            export_keys
            ;;
        4)
            restart_project
            ;;
        0)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 0-4！${NC}"
            ;;
    esac
    echo
done
