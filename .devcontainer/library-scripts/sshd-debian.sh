#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/docs/sshd.md
# Maintainer: The VS Code and Codespaces Teams
#
# Syntax: ./sshd-debian.sh [SSH Port (don't use 22)] [non-root user] [start sshd now flag] [new password for user] [fix environment flag]
#
# Note: You can change your user's password with "sudo passwd $(whoami)" (or just "passwd" if running as root).

SSHD_PORT=${1:-"2222"}
USERNAME=${2:-"automatic"}
START_SSHD=${3:-"false"}
NEW_PASSWORD=${4:-"skip"}
FIX_ENVIRONMENT=${5:-"true"}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in ${POSSIBLE_USERS[@]}; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

# Function to run apt-get if needed
apt-get-update-if-needed()
{
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update
    else
        echo "Skipping apt-get update."
    fi
}

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Install openssh-server openssh-client
if ! dpkg -s openssh-server openssh-client lsof jq > /dev/null 2>&1; then
    apt-get-update-if-needed
    apt-get -y install --no-install-recommends openssh-server openssh-client lsof jq
fi

# Generate password if new password set to the word "random"
if [ "${NEW_PASSWORD}" = "random" ]; then
    NEW_PASSWORD="$(openssl rand -hex 16)"
    EMIT_PASSWORD="true"
fi

# If new password not set to skip, set it for the specified user
if [ "${NEW_PASSWORD}" != "skip" ]; then
    echo "${USERNAME}:${NEW_PASSWORD}" | chpasswd
    if [ "${NEW_PASSWORD}" != "root" ]; then
        usermod -aG ssh ${USERNAME}
    fi
fi

# Setup sshd
mkdir -p /var/run/sshd
sed -i 's/session\s*required\s*pam_loginuid\.so/ession optional pam_loginuid.so/g' /etc/pam.d/sshd
sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i -E "s/#*\s*Port\s+.+/Port ${SSHD_PORT}/g" /etc/ssh/sshd_config

# Script to store variables that exist at the time the ENTRYPOINT is fired
STORE_ENV_SCRIPT="$(cat << 'EOF'
# The files created here are used by /etc/profile.d/00-fix-login-env.sh

# Update default PATH - Need to do this here because its unclear where the ssh script was run in the Dockerfile.
# Unlike macOS and Windows, nearly everything is legal in file/path names so we need to do some escaping. We then
# need to modify /etc/environment and possibly /etc/profile and /etc/zsh/zshenv due to hard coding in certain imges.
QUOTE_ESCAPED_PATH="${PATH//\"/\\\"}"
SED_ESCAPTED_PATH="${QUOTE_ESCAPED_PATH//\\%/\\\%}"
if grep 'PATH=' /etc/environment > /dev/null 2>&1; then
    sudoIf sed -i -E "s%^PATH=.*$%PATH=\"${SED_ESCAPTED_PATH}\"%" /etc/environment
else
    echo "PATH=\"${QUOTE_ESCAPED_PATH//\"/\\\"}\"" | sudoIf tee -a /etc/environment > /dev/null
fi
sudoIf sed -i -E "s%((^|\s)PATH=)([^\$]*)$%\2PATH=\"${SED_ESCAPTED_PATH:-\3}\"%" /etc/profile
# Handle zsh if present
if type zsh > /dev/null 2>&1; then
    if ! grep '/etc/profile.d/00-fix-login-env.sh' /etc/zsh/zlogin > /dev/null 2>&1; then
        echo -e "if [ -f /etc/profile.d/00-fix-login-env.sh ]; then . /etc/profile.d/00-fix-login-env.sh; fi\n$(cat /etc/zsh/zlogin 2>/dev/null || echo '')" | sudoIf tee /etc/zsh/zlogin > /dev/null
    fi
    if [ -f /etc/zsh/zshenv ]; then
        sudoIf sed -i -E "s%((^|\s)PATH=)([^\$]*)$%\2PATH=\"${SED_ESCAPTED_PATH:-\3}\"%" /etc/zsh/zshenv
    fi
fi


# Store any variables set in the dockerfile under /usr/local/etc/vscode-dev-containers/base-env
sudoIf mkdir -p /usr/local/etc/vscode-dev-containers
declare -x | grep -vE '(USER|HOME|SHELL|PWD|OLDPWD|TERM|TERM_PROGRAM|TERM_PROGRAM_VERSION|SHLVL|HOSTNAME|LOGNAME|MAIL)=' \
    | grep -oP '(declare\s+-x\s+)?\K.*=.*' | sudoIf tee /usr/local/etc/vscode-dev-containers/base-env > /dev/null

# Remove less complex scipt if present to avoid duplication
if [ -f "/etc/profile.d/00-restore-env.sh" ]; then
    sudoIf rm -f /etc/profile.d/00-restore-env.sh
fi
EOF
)"

# Script to ensure login shells get variables or the PATH that were set in the container image
RESTORE_ENV_SCRIPT="$(cat << 'EOF'
#!/bin/sh
# This script is intended to be sourced, so it uses posix syntax where possible and detects zsh/sh for cases where things differ

if [ "${VSCDC_FIX_LOGIN_ENV}" = "true" ]; then
    # Already run, so exit
    return
fi

export VSCDC_FIX_LOGIN_ENV=true

# Get the type of shell without relying on $SHELL which can be empty/wrong
__vscdc_shell_type="$(lsof -p $$ | awk '(NR==2) {print $1}')"

__vscdc_var_has_val() {
    # POSIX implementation uses eval, but that doesn't work in zsh and -v is better for bash
    if [ "${__vscdc_shell_type}" = "bash" ] || [ "${__vscdc_shell_type}" = "zsh" ]; then
        if [ -v "$1" ]; then return 0; else return 1; fi
    fi
    if [ "$(eval "echo \$$1")" = "" ]; then return 1; else return 0; fi
}

__vscdc_restore_env() {
    local base_env_vars
    local base_shell_path
    # Grab codespaces secrets if present
    if [ -f /workspaces/.codespaces/shared/.user-secrets.json ]; then
        base_env_vars="$(cat /workspaces/.codespaces/shared/.user-secrets.json | jq -r '.[] | select (.type=="EnvironmentVariable") | .name+"=\""+.value+"\""')"
    fi
    if [ -f /usr/local/etc/vscode-dev-containers/base-env ]; then
        base_env_vars="${base_env_vars}$(echo && cat /usr/local/etc/vscode-dev-containers/base-env)"
    fi
    if [ ! -z "${base_env_vars}" ]; then
        # Add any missing env vars saved off earlier
        local variable_line
        while IFS= read -r variable_line; do
            local var_name="${variable_line%%=*}"
            if [ "${var_name}" != "PATH" ] && [ "${var_name}" != "" ] && ! __vscdc_var_has_val "${var_name}"; then
                # All values are quoted, so get everything past the first quote and remove the last
                local var_value="${variable_line##*=\"}"
                export ${var_name}="${var_value%?}"
            fi
        done \
<< EOF_BASE_ENV
$base_env_vars
EOF_BASE_ENV
        # 👆 Use EOF hack for piping in variable to "read" because <<< is not available in sh/dash/ash
    fi
}

__vscdc_restore_env

unset -f __vscdc_restore_env __vscdc_var_has_val
unset __vscdc_shell_type __vscdc_default_path __vscdc_zshenv_path
EOF
)"

# Write out a scripts that can be referenced as an ENTRYPOINT to auto-start sshd and fix login environments
tee /usr/local/share/ssh-init.sh > /dev/null \
<< 'EOF'
#!/usr/bin/env bash
# This script is intended to be run as root with a container that runs as root (even if you connect with a different user)
# However, it supports running as a user other than root if passwordless sudo is configured for that same user.

set -e 

sudoIf()
{
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

EOF
if [ "${FIX_ENVIRONMENT}" = "true" ]; then
    echo "$STORE_ENV_SCRIPT" >> /usr/local/share/ssh-init.sh
    echo "${RESTORE_ENV_SCRIPT}" > /etc/profile.d/00-fix-login-env.sh
    chmod +x /etc/profile.d/00-fix-login-env.sh
    # Remove less complex script if present to avoid path duplication
    rm -f /etc/profile.d/00-restore-env.sh
    # Wire in zsh if present
    if type zsh > /dev/null 2>&1; then
        echo -e "if [ -f /etc/profile.d/00-fix-login-env.sh ]; then . /etc/profile.d/00-fix-login-env.sh; fi\n$(cat /etc/zsh/zlogin 2>/dev/null || echo '')" > /etc/zsh/zlogin
    fi
fi
tee -a /usr/local/share/ssh-init.sh > /dev/null \
<< 'EOF'

# ** Start SSH server **
sudoIf /etc/init.d/ssh start 2>&1 | sudoIf tee /tmp/sshd.log > /dev/null

set +e
exec "$@"
EOF
chmod +x /usr/local/share/ssh-init.sh

# If we should start sshd now, do so
if [ "${START_SSHD}" = "true" ]; then
    /usr/local/share/ssh-init.sh
fi

# Output success details
echo -e "Done!\n\n- Port: ${SSHD_PORT}\n- User: ${USERNAME}"
if [ "${EMIT_PASSWORD}" = "true" ]; then
    echo "- Password: ${NEW_PASSWORD}"
fi
echo -e "\nForward port ${SSHD_PORT} to your local machine and run:\n\n  ssh -p ${SSHD_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${USERNAME}@localhost\n"
