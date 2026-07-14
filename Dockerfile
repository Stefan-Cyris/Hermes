# Custom Coolify Docker Options
# --cap-add=NET_ADMIN --cap-add=NET_RAW --device /dev/net/tun:/dev/net/tun --tmpfs /run --tmpfs /tmp -v /dev/pts:/dev/pts

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=de_DE.UTF-8
ENV TZ=Europe/Berlin
ENV HERMES_HOME=/opt/data

WORKDIR /opt/hermes

# Base utilities plus Hermes installer/runtime prerequisites from the upstream image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        wget \
        git \
        vim \
        tmux \
        jq \
        build-essential \
        sudo \
        locales \
        tzdata \
        iputils-ping \
        netcat-openbsd \
        iptables \
        passwd \
        bubblewrap \
        ripgrep \
        ffmpeg \
        cmake \
        python3-dev \
        libffi-dev \
        libolm-dev \
        procps \
        openssh-client \
        openssh-server \
        fonts-liberation \
        xdg-utils \
        xz-utils \
        poppler-utils \
        libmagic1 \
        tesseract-ocr \
        tesseract-ocr-deu \
        tesseract-ocr-eng \
        ocrmypdf \
        ghostscript \
        qpdf \
        unpaper \
        imagemagick \
    && locale-gen de_DE.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Keep /home empty; Hermes follows the upstream container layout.
RUN userdel -r ubuntu 2>/dev/null || rm -rf /home/ubuntu

# Node.js 22 LTS (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python 3 + pip + uv
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python-is-python3 \
    && pip install --no-cache-dir --break-system-packages uv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# SSH setup -- keep parity with Dockerfile.dev-remote while Tailscale SSH is enabled too.
RUN mkdir /run/sshd \
    && ssh-keygen -A \
    && sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitUserEnvironment.*/PermitUserEnvironment yes/' /etc/ssh/sshd_config \
    && sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

# Create hermes user with upstream-style home plus sudo for remote administration.
RUN mkdir -p /opt/data /opt/hermes \
    && useradd -m -d /opt/data -s /bin/bash hermes \
    && passwd -l hermes \
    && usermod -aG sudo hermes \
    && echo "hermes ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hermes \
    && chmod 0440 /etc/sudoers.d/hermes \
    && chown -R hermes:hermes /opt/data

# Python virtualenvs for Hermes tooling. Built into /opt/venvs (outside the
# /opt/data volume) so they are baked into the image instead of being shadowed
# by the mounted volume at runtime. Use e.g. /opt/venvs/mnemosyne/bin/python.
RUN mkdir -p /opt/venvs \
    && python3 -m venv /opt/venvs/mnemosyne \
    && /opt/venvs/mnemosyne/bin/pip install --no-cache-dir --upgrade pip mnemosyne-memory \
    && python3 -m venv /opt/venvs/pymupdf \
    && /opt/venvs/pymupdf/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venvs/pymupdf/bin/pip install --no-cache-dir pymupdf pymupdf4llm python-docx \
    && chown -R hermes:hermes /opt/venvs

# Configure hermes user. These lines are also kept in /etc/skel for persisted
# volumes created by older image versions.
RUN printf '%s\n' \
        '' \
        '# Hermes prod container environment' \
        'export HERMES_HOME=/opt/data' \
        'export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$HERMES_HOME/bin:$PATH"' \
        | tee -a /etc/skel/.bashrc >> /opt/data/.bashrc \
    && chown hermes:hermes /opt/data/.bashrc

# Startup script: bring up Tailscale + SSH first. If Hermes has already been
# installed into the persistent volume, also start gateway and dashboard.
RUN mkdir -p /var/run/tailscale && printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '' \
    'export HOME=/opt/data' \
    'export HERMES_HOME=/opt/data' \
    'export PATH="/opt/data/.local/bin:/opt/data/.hermes/bin:/opt/data/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
    '' \
    '# Init persisted Hermes home if the volume is empty.' \
    'if [ ! -f /opt/data/.bashrc ]; then' \
    '    cp -a /etc/skel/. /opt/data/' \
    'fi' \
    'if ! grep -q "# Hermes prod container environment" /opt/data/.bashrc; then' \
    '    tail -n 4 /etc/skel/.bashrc >> /opt/data/.bashrc' \
    'fi' \
    'mkdir -p /opt/data/logs /run/sshd /var/run/tailscale' \
    'chown -R hermes:hermes /opt/data' \
    'if [ -n "${HERMES_SSH_PASSWORD:-}" ]; then' \
    '    echo "hermes:${HERMES_SSH_PASSWORD}" | chpasswd' \
    '    passwd -u hermes >/dev/null 2>&1 || true' \
    'else' \
    '    passwd -l hermes >/dev/null 2>&1 || true' \
    'fi' \
    '' \
    '/usr/sbin/sshd -D -e &' \
    'sshd_pid=$!' \
    '' \
    'tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &' \
    'sleep 3' \
    'if [ -n "${TS_AUTHKEY:-}" ]; then' \
    '    tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME:-hermes}" --ssh' \
    'else' \
    '    tailscale up --hostname="${TS_HOSTNAME:-hermes}" --ssh' \
    'fi' \
    '' \
    'run_as_hermes() {' \
    '    sudo -E -H -u hermes env HOME=/opt/data HERMES_HOME=/opt/data PATH="$PATH" "$@"' \
    '}' \
    '' \
    'if run_as_hermes bash -lc "command -v hermes >/dev/null 2>&1"; then' \
    '    echo "Hermes found, starting gateway and dashboard..."' \
    '    run_as_hermes bash -lc '"'"'nohup hermes gateway run >> "$HERMES_HOME/logs/gateway.log" 2>&1 &'"'"'' \
    '    run_as_hermes bash -lc '"'"'nohup hermes dashboard --host "${HERMES_DASHBOARD_HOST:-127.0.0.1}" --no-open >> "$HERMES_HOME/logs/dashboard.log" 2>&1 &'"'"'' \
    'else' \
    '    echo "Hermes is not installed yet. Connect over Tailscale SSH and run:"' \
    '    echo "  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"' \
    'fi' \
    '' \
    'echo "Hermes box is running."' \
    'wait "$sshd_pid"' \
    > /usr/local/bin/start.sh \
    && chmod +x /usr/local/bin/start.sh

VOLUME /var/lib/tailscale
VOLUME /opt/data

EXPOSE 22

HEALTHCHECK --interval=10s CMD true

CMD ["/usr/local/bin/start.sh"]
