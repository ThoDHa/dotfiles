FROM debian:stable

# Install sudo first
RUN apt-get update && apt-get -y upgrade && apt-get -y install sudo && apt-get clean

# Copy the single bootstrap script
COPY bootstrap/install.sh /root/bootstrap/install.sh

WORKDIR /root

# Run the bootstrap (skip chsh in container)
ENV DEBIAN_FRONTEND=noninteractive
RUN bash -c 'export SKIP_CHSH=1 && /root/bootstrap/install.sh'

# Stow packages will be mounted at runtime via volume
# The container expects configs to be mounted at /root/confs

# Git safe directory for any mounted repos
RUN git config --global --add safe.directory '*'

# Set shell
ENV SHELL=/bin/zsh
CMD ["/bin/zsh"]