FROM debian:stable

COPY min_setup.sh /root/setup.sh
WORKDIR /root
RUN /bin/bash setup.sh
RUN rm /root/setup.sh
RUN chsh -s ~/.zshrc
ENV SHELL=/bin/zsh
CMD tmux
