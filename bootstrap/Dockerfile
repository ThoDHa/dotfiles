FROM debian:stable

# DEBIAN_FRONTEND inline so it doesn't persist into runtime environment.
# sudo curl git make patch are needed before setup.sh's own apt step: the
# first bootstrap step stows via the repo Makefile, and the tmux build
# applies the carried patches.
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && apt-get install -y --no-install-recommends sudo curl git make patch ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/dotfiles

# setup.sh drives the repo itself (make stow targets, tmux patches, the
# claudecode package), so the image needs the repo content, not just the
# script.
COPY Makefile ./
COPY bootstrap/ bootstrap/
COPY shell/ shell/
COPY tmux/ tmux/
COPY isort/ isort/
COPY agents/ agents/
COPY opencode/ opencode/
COPY claudecode/ claudecode/

# Run full bootstrap, then clean apt cache (bootstrap leaves apt state behind)
# SKIP_CHSH=1: setup.sh skips chsh inside a container
RUN DEBIAN_FRONTEND=noninteractive SKIP_CHSH=1 ./bootstrap/setup.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global --add safe.directory '*'

# Dotfiles are mounted at runtime via: docker run -v .:/root/<dir> (see make run)
ENV SHELL=/bin/zsh
CMD ["/bin/zsh"]
