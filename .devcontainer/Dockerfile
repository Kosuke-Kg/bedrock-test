FROM ubuntu:24.10

# 環境変数の設定
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# システムパッケージの更新と基本ツールのインストール
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    vim \
    nano \
    unzip \
    zip \
    jq \
    tree \
    htop \
    && rm -rf /var/lib/apt/lists/*

# 開発用ユーザーの作成（UID 1001を使用）
ARG USERNAME=vscode
ARG USER_UID=1001

RUN useradd --uid $USER_UID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# miseのインストール
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:$PATH"

# ユーザーを切り替えて、ユーザー環境でもmiseを設定
USER $USERNAME
WORKDIR /home/$USERNAME

# ユーザー環境でmiseをインストール
RUN curl https://mise.run | sh
ENV PATH="/home/$USERNAME/.local/bin:$PATH"

# miseの初期設定
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc \
    && echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

# シェルの設定
RUN sudo chsh -s /bin/bash $USERNAME

# ワーキングディレクトリを設定
WORKDIR /workspace
