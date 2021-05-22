#!/usr/bin/env bash

echo "export PATH=/bashrctest:\$PATH:/afterbashrctest" | tee -a /etc/zsh/zshrc >> /etc/bash.bashrc
echo -e "vscode\nvscode" | passwd vscode
chown vscode /etc/profile.d/00-fix-login-env.sh 
chsh -s $(which $1) vscode
