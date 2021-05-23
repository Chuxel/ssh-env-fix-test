# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.179.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG FROM_IMAGE="mcr.microsoft.com/vscode/devcontainers/base:0-focal"
FROM $FROM_IMAGE

ENV PATH=/front-dockerfile-pre-script:$PATH:/back-dockerfile-pre-script
ENV this_var=true

# Add any install commands to install.sh or user-install.sh or and they'll be added to the image 
ARG DEFAULT_SHELL_TYPE=bash
COPY *.sh /tmp/scripts/
COPY library-scripts/*.sh /tmp/library-scripts/
RUN ls /tmp/library-scripts/*.sh | xargs -n 1 bash \
    && bash /tmp/scripts/test-prep.sh ${DEFAULT_SHELL_TYPE} \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts/ /tmp/scripts/

ENV that_var=true
ENV PATH=/front-dockerfile-post-script:$PATH:/back-dockerfile-post-script

ENTRYPOINT [ "/usr/local/share/ssh-init.sh" ]
CMD [ "sleep", "infinity" ]

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>


