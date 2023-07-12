FROM codercom/enterprise-base:ubuntu

ARG USER=coder
USER root
RUN curl -fsSL https://code-server.dev/install.sh | sh
RUN rm -rf /home/coder
RUN usermod -l ${USER} coder
RUN usermod -d /home/${USER} ${USER}
USER ${USER}
WORKDIR /home/${USER}