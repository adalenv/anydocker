# Base image
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_RESOLUTION=1280x720
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

RUN  git clone https://github.com/novnc/noVNC.git /usr/share/novnc \
 && git clone https://github.com/novnc/websockify.git /usr/share/novnc/utils/websockify
# Ensure GUI apps use the virtual display
ENV DISPLAY=:1




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

# Supervisor will manage AnyDesk attached to DISPLAY=:1
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE ${NOVNC_PORT} ${VNC_PORT}

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
