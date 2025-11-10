# Base image
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_RESOLUTION=1920x1080
ENV VNC_PORT=5900
ENV NOVNC_PORT=6080
ENV USER=ad1
ENV HOME=/home/ad1

# Create a non-root user
RUN useradd -m $USER && echo "$USER:$USER" | chpasswd
WORKDIR $HOME
USER $USER

# --- Install dependencies ---
USER root
RUN apt-get update
RUN apt-get install -y \
    sudo \
    wget curl gnupg2 ca-certificates apt-transport-https \
    xvfb fluxbox x11vnc websockify supervisor \
    libgtk2.0-0 libglib2.0-0 libstdc++6 libx11-6 libxcb1 libxcb-shm0 \
    libpango1.0-0 libcairo2 libxrandr2 libxtst6 libxfixes3 libxdamage1 \
    libgtkglext1 libpolkit-gobject-1-0 libdbus-1-3 libxcomposite1 libxrender1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Disable service auto-start (avoids AnyDesk postinst errors) ---
RUN echo '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

# --- Install AnyDesk ---
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/anydesk.asc && \
    chmod a+r /etc/apt/keyrings/anydesk.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/anydesk.asc] https://deb.anydesk.com all main" \
    > /etc/apt/sources.list.d/anydesk.list && \
    apt-get update &&  apt-get install -y  policykit-1 git  dbus-x11 anydesk || true

RUN dbus-uuidgen > /var/lib/dbus/machine-id
# --- Setup noVNC files ---



RUN  echo test; git clone https://github.com/adalenv/noVNC.git /usr/share/novnc \
 && git clone https://github.com/novnc/websockify.git /usr/share/novnc/utils/websockify




RUN apt install yad -y || true
# --- Setup Fluxbox ---
RUN mkdir -p $HOME/.fluxbox && \
    cat > $HOME/.fluxbox/startup <<'EOF'
#!/bin/bash
xsetroot -solid grey

# Start AnyDesk
su $USER -c anydesk &

# Start Fluxbox
exec fluxbox
EOF

RUN chmod +x $HOME/.fluxbox/startup

# --- Setup Fluxbox menu with only AnyDesk ---
RUN cat > $HOME/.fluxbox/menu <<'EOF'
[begin] (Start)
    [exec] (AnyDesk) {su $USER -c anydesk}
    [exec] (Reset AnyDesk ID) {bash -c 'PASSWORD="adalen"; USER_PASS=$(yad --entry  --ontop --title="Reset AnyDesk ID" --text="Enter password:" --hide-text); if [ "$USER_PASS" != "$PASSWORD" ]; then yad --error --ontop --text="Wrong password!"; exit 1; fi; pkill anydesk 2>/dev/null; rm -rf /etc/anydesk /var/lib/anydesk /var/log/anydesk* /home/*/.anydesk /root/.anydesk;  yad --ontop --info --text="AnyDesk reset complete!" --timeout=3;su $USER bash -c anydesk'}
[end]
EOF

# --- Setup Desktop launcher ---
RUN mkdir -p $HOME/Desktop && \
    cat > $HOME/Desktop/AnyDesk.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=AnyDesk
Exec=anydesk
Icon=/usr/share/icons/hicolor/48x48/apps/anydesk.png
Terminal=false
StartupNotify=true
EOF
RUN chmod +x $HOME/Desktop/AnyDesk.desktop


RUN cat > /etc/supervisor/conf.d/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisord.log
loglevel=info
pidfile=/var/run/supervisord.pid

[program:xvfb]
command=Xvfb :1 -screen 0 1280x720x24 -nolisten tcp -ac
autorestart=true
priority=10
stdout_logfile=/var/log/xvfb.log
stderr_logfile=/var/log/xvfb.err

[program:fluxbox]
command=fluxbox -display :1
autorestart=true
priority=20
stdout_logfile=/var/log/fluxbox.log
stderr_logfile=/var/log/fluxbox.err

[program:x11vnc]
command=x11vnc -display :1 -rfbport 5900 -shared -forever
autorestart=true
priority=30
stdout_logfile=/var/log/x11vnc.log
stderr_logfile=/var/log/x11vnc.err

[program:websockify]
command=python3 -m websockify --web=/usr/share/novnc 6080 localhost:5900
autorestart=true
priority=40
stdout_logfile=/var/log/websockify.log
stderr_logfile=/var/log/websockify.err
[end]
EOF



RUN fbsetroot -solid grey5


VOLUME ["/etc/anydesk", "/var/lib/anydesk", "/var/log/anydesk", "/home/$USER/.anydesk", "/root/.anydesk"]

# Set root password
RUN echo "root:adalen" | chpasswd

EXPOSE ${NOVNC_PORT} ${VNC_PORT}

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
