# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.179.0/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version: bionic, focal
ARG VARIANT="focal"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

ENV PATH=/frontbeforescript:$PATH:/backbeforeafterscript
ENV this_var=true

# Add any install commands to install.sh or user-install.sh or and they'll be added to the image 
COPY install.sh library-scripts/*.sh /tmp/scripts/
RUN ls /tmp/scripts/*.sh | xargs -n 1 bash \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/scripts/

ENV that_var=true
ENV PATH=/frontafterscript:$PATH:/backafterscript

ENTRYPOINT [ "/usr/local/share/ssh-init.sh" ]
CMD [ "sleep", "infinity" ]

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>


