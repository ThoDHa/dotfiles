FROM debian:stable

# DEBIAN_FRONTEND inline so it doesn't persist into runtime environment
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && apt-get install -y --no-install-recommends sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# Copy the bootstrap script
COPY bootstrap/setup.sh /root/bootstrap/setup.sh

# Run full bootstrap, then clean apt cache (bootstrap leaves apt state behind)
# SKIP_CHSH=1: chsh does not work inside a container
RUN DEBIAN_FRONTEND=noninteractive SKIP_CHSH=1 /root/bootstrap/setup.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global --add safe.directory '*'

# Dotfiles are mounted at runtime via: docker run -v .:/root/<dir> (see make run)
ENV SHELL=/bin/zsh
CMD ["/bin/zsh"]
