FROM ubuntu:24.04

# Switch from dash to bash by default.
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Remove minimization restrictions and install packages with documentation
# We aim for a usable non-minimal system.
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirror://mirrors.ubuntu.com/mirrors.txt|' /etc/apt/sources.list && \
        rm -f /etc/dpkg/dpkg.cfg.d/excludes /etc/dpkg/dpkg.cfg.d/01_nodoc && \
	apt-get update && \
	# Pre-configure debconf to avoid interactive prompts
	echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
	# Pre-configure pbuilder to avoid mirror prompt
	echo 'pbuilder pbuilder/mirrorsite string http://archive.ubuntu.com/ubuntu' | debconf-set-selections && \
	# Run unminimize with single 'y' response to restore documentation
	echo 'y' | DEBIAN_FRONTEND=noninteractive unminimize && \
	# Install man-db and reinstall all base packages to get their man pages back
	DEBIAN_FRONTEND=noninteractive apt-get install -y man-db && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall $(dpkg-query -f '${binary:Package} ' -W) && \
	mandb -c && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y \
		ca-certificates wget \
		git curl less \
		net-tools file \
		sudo \
		openssh-server openssh-client \
		iputils-ping socat netcat-openbsd \
		libcap2-bin \
		unzip util-linux rsync \
		man-db manpages manpages-dev \
		systemd systemd-sysv \
		dbus-user-session \
		&& apt-get remove -y pollinate ubuntu-fan && \
	# Allow non-root users to use ping without sudo by granting CAP_NET_RAW
	setcap cap_net_raw=+ep /usr/bin/ping && \
	# Remove policy-rc.d so services can start normally (the base image includes this
	# to prevent services from starting during build, but we run systemd at runtime)
	rm -f /usr/sbin/policy-rc.d

# Configure systemd
RUN	systemctl mask -- getty.target \
		fwupd.service \
		fwupd-refresh.service \
		fwupd-refresh.timer \
		systemd-random-seed.service \
		iscsid.socket \
		dm-event.socket \
		man-db.timer \
		update-notifier-download.timer \
		update-notifier-motd.timer \
		atop-rotate.timer \
		dpkg-db-backup.timer \
		e2scrub_all.timer \
		etc-resolv.conf.mount \
		etc-hosts.mount \
		etc-hostname.mount \
		-.mount \
		systemd-resolved.service \
		systemd-remount-fs.service \
		systemd-sysusers.service \
		systemd-update-done.service \
		systemd-update-utmp.service \
		systemd-journal-catalog-update.service \
		modprobe@.service \
		systemd-modules-load.service \
		systemd-udevd.service \
		systemd-udevd-control.service \
		systemd-udevd-kernel.service \
		systemd-udev-trigger.service \
		systemd-udev-settle.service \
		systemd-hwdb-update.service \
		ubuntu-fan.service \
		ldconfig.service \
		unattended-upgrades.service \
		lxd-installer.socket \
	        console-getty.service \
		keyboard-setup.service \
		systemd-ask-password-console.path \
		systemd-ask-password-wall.path \
		ssh.socket \
		plymouth.service \
		plymouth-start.service \
		plymouth-quit.service \
		plymouth-quit-wait.service \
		plymouth-read-write.service \
		plymouth-switch-root.service \
		plymouth-switch-root-initramfs.service \
		plymouth-halt.service \
		plymouth-reboot.service \
		plymouth-poweroff.service \
		plymouth-kexec.service \
		apt-daily-upgrade.timer \
		apt-daily.timer \
		plymouth-log.service && \
	# systemd-logind is disabled but not masked. It's involved in populating the XDG runtime dir sockets... somehow
	systemctl disable getty.target systemd-logind.service \
                   console-getty.service \
                   getty@.service \
		   motd-news.timer motd-news.service \
                   systemd-ask-password-wall.service \
                   systemd-ask-password-console.service \
                   systemd-machine-id-commit.service \
                   systemd-modules-load.service \
                   systemd-sysctl.service \
                   systemd-firstboot.service \
                   systemd-udevd.service \
                   systemd-udev-trigger.service \
                   systemd-udev-settle.service \
		   e2scrub_reap.service \
		   systemd-update-utmp.service \
                   systemd-hwdb-update.service && \
	mkdir -p /etc/systemd/system.conf.d && \
    		echo '[Manager]' > /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'LogLevel=info' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'LogTarget=console' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'SystemCallArchitectures=native' >> /etc/systemd/system.conf.d/container-overrides.conf && \
    		echo 'DefaultOOMPolicy=continue' >> /etc/systemd/system.conf.d/container-overrides.conf && \
	mkdir -p /etc/systemd/journald.conf.d && \
		echo '[Journal]' > /etc/systemd/journald.conf.d/persistent.conf && \
		echo 'Storage=persistent' >> /etc/systemd/journald.conf.d/persistent.conf && \
	systemctl set-default multi-user.target

# Modify existing ubuntu user (UID 1000) to become exedev user
RUN usermod -l exedev -c "exe.dev user" ubuntu && \
	groupmod -n exedev ubuntu && \
	mv /home/ubuntu /home/exedev && \
	usermod -d /home/exedev exedev && \
	usermod -aG sudo exedev && \
	sed -i 's/^ubuntu:/exedev:/' /etc/subuid /etc/subgid && \
	echo 'exedev ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
	echo 'Defaults:exedev verifypw=any' >> /etc/sudoers && \
	# Manually enable linger, this should autopopulate /run/user/1000
	mkdir -p /var/lib/systemd/linger && \
	touch /var/lib/systemd/linger/exedev

ENV EXEUNTU=1

# https://github.com/trfore/docker-ubuntu2404-systemd/blob/main/Dockerfile suggests the following
# might be useful?
# STOPSIGNAL SIGRTMIN+3


RUN mkdir -p /home/exedev && \
    chown exedev:exedev /home/exedev

USER exedev

WORKDIR /home/exedev

# Update PATH in .bashrc to include .local/bin and set XDG_RUNTIME_DIR for systemd user services
# XDG paths are not autopopulated despite the presense of libpam-systemd. Manually add them here.
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.bashrc && \
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"' >> /home/exedev/.profile

# Switch back to root to install systemd service
USER root

# Disable Ubuntu's default MOTD (the sudo hint, etc.)
RUN rm -rf /etc/update-motd.d/* /etc/motd && touch /home/exedev/.hushlogin && chown exedev:exedev /home/exedev/.hushlogin

# Add custom MOTD to exedev's .bashrc (ignores .hushlogin - we handle that ourselves)
COPY motd-snippet.bash /tmp/motd-snippet.bash
RUN cat /tmp/motd-snippet.bash >> /home/exedev/.bashrc && rm /tmp/motd-snippet.bash

# Create systemd oneshot service for /exe.dev/setup script
COPY exe-setup.service /etc/systemd/system/exe-setup.service
RUN chmod 644 /etc/systemd/system/exe-setup.service && \
    systemctl enable exe-setup.service

# TODO(crawshaw/philip): This is called init so that exetini decides
# this wrapper script is an init, and exec's it rather than forking it.
# It would be better if you could indicate that via an env variable or something.
COPY init-wrapper.sh /usr/local/bin/init

# Create config directories for LLM agents
RUN mkdir -p /home/exedev/.claude /home/exedev/.codex /home/exedev/.pi && \
    chown -R exedev:exedev /home/exedev/.claude /home/exedev/.codex /home/exedev/.pi

# Copy LLM agent instructions to Claude, Codex, and Shelley config directories
# Shelley uses ~/.config/shelley/ (XDG convention, directory already created above)
COPY AGENTS.md /home/exedev/.config/shelley/AGENTS.md
RUN chown exedev:exedev /home/exedev/.config/shelley/AGENTS.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.claude/CLAUDE.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.codex/AGENTS.md && \
    ln -s /home/exedev/.config/shelley/AGENTS.md /home/exedev/.pi/AGENTS.md

# Install pi exe.dev extension (LLM gateway + environment context)
COPY pi-extension/ /home/exedev/.pi/agent/extensions/exe-dev/
RUN chown -R exedev:exedev /home/exedev/.pi/agent

# Install xterm-ghostty terminfo for Ghostty terminal support
COPY xterm-ghostty.terminfo /tmp/xterm-ghostty.terminfo
RUN tic -x - < /tmp/xterm-ghostty.terminfo && rm /tmp/xterm-ghostty.terminfo

LABEL "exe.dev/login-user"="exedev"
CMD ["/usr/local/bin/init"]
