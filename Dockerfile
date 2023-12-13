FROM debian:stable
RUN apt-get update && apt-get -y install \
    git curl gcc zsh zip unzip python3 wget fd-find bat tree \
    && apt-get clean

COPY min_setup.sh /root/setup.sh

WORKDIR /root
RUN /bin/bash setup.sh
RUN rm /root/setup.sh
RUN chsh -s ~/.zshrc
RUN git config --global --add safe.directory *
ENV SHELL=/bin/zsh
CMD /bin/zsh 
