#!/bin/bash
set -o nounset
set -o errexit

# default settings, can be overridden by cmd line options, see usage
DOCKER_VER=19.03.14
BASE=./tmp
REGISTRY_MIRROR=CN

function download_docker() {
  if [[ "$REGISTRY_MIRROR" == CN ]];then
    DOCKER_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64/docker-${DOCKER_VER}.tgz"
  else
    DOCKER_URL="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VER}.tgz"
  fi

  mkdir -p "$BASE/down"

  if [[ -f "$BASE/down/docker-${DOCKER_VER}.tgz" ]];then
    echo "docker binaries already existed"
  else
    echo "downloading docker binaries, version $DOCKER_VER"
    if [[ -e /usr/bin/curl ]];then
      curl -C- -O --retry 3 "$DOCKER_URL" || { echo "downloading docker failed"; exit 1; }
    else
      wget -c "$DOCKER_URL" || { echo "downloading docker failed"; exit 1; }
    fi
    /bin/mv -f "./docker-$DOCKER_VER.tgz" "$BASE/down"
  fi
  tar zxf "$BASE/down/docker-$DOCKER_VER.tgz" -C "$BASE/down" && \
  /bin/mv -f "$BASE"/down/docker/* /usr/bin
}

function install_docker() {
  # check if a container runtime is already installed
  systemctl status docker|grep Active|grep -q running && { echo "docker is already running."; return 0; }
 
  logger debug "generate docker service file"
  
cat > /usr/lib/systemd/system/docker.socket << EOF 
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
  
  cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket
Wants=containerd.service

[Service]
Environment="PATH=/bin:/sbin:/usr/bin:/usr/sbin"
ExecStart=/usr/bin/dockerd
ExecStartPost=/sbin/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF

  # configuration for dockerd
  mkdir -p /etc/docker
  if [[ "$REGISTRY_MIRROR" == CN ]];then
    cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "http://hub-mirror.c.163.com"
  ],
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
    },
  "data-root": "/data/docker",
  "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
  else
    logger debug "standard config without registry mirrors"
    cat > /etc/docker/daemon.json << EOF
{
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
    },
  "data-root": "/var/lib/docker"
}
EOF
  fi

  if [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
    logger debug "turn off selinux in CentOS/Redhat"
    getenforce|grep Disabled || setenforce 0
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config
  fi

  logger info "clean iptable rules"
  iptables -P INPUT ACCEPT && \
  iptables -P FORWARD ACCEPT && \
  iptables -P OUTPUT ACCEPT && \
  iptables -F && iptables -X && \
  iptables -F -t nat && iptables -X -t nat && \
  iptables -F -t raw && iptables -X -t raw && \
  iptables -F -t mangle && iptables -X -t mangle

  logger debug "enable and start docker"
  systemctl enable docker
  systemctl daemon-reload && systemctl restart docker && sleep 4
}

function download_all() {
  download_docker && \
  install_docker
}

function main() {
    download_all
}

main "$@"
