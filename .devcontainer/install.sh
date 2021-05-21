#!/usr/bin/env bash

echo "export PATH=/bashrctest:\$PATH:/afterbashrctest" | tee -a /etc/zsh/zshrc >> /etc/bash.bashrc
chsh -s $(which zsh) vscode
echo -e "vscode\nvscode" | passwd vscode