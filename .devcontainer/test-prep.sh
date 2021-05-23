#!/usr/bin/env bash

echo -e "export PATH=/front-profile-begin:\$PATH:/back-profile-begin\n$(cat /etc/profile)" > /etc/profile
echo -e "export PATH=/front-profile-begin:\$PATH:/back-profile-begin\n$(cat /etc/zsh/zlogin)" > /etc/zsh/zlogin
sed -i 's%export PATH$%&\nexport PATH=/front-profile-post-export:$PATH:/back-profile-post-export%g' /etc/profile
sed -i 's%if \[ "\${PS1-}" \]; then%export PATH=/front-profile-pre-rc:$PATH:/back-profile-pre-rc\n&%g' /etc/profile
sed -i 's%if \[ -d /etc/profile\.d \]; then%export PATH=/front-pre-profile.d:$PATH:/back-pre-profile.d\n&%g' /etc/profile
echo "export PATH=/front-profile-end:\$PATH:/back-profile-end" | tee -a /etc/zsh/zlogin >> /etc/profile
echo "export PATH=/front-rc:\$PATH:/back-rc" | tee -a /etc/zsh/zshrc >> /etc/bash.bashrc

USERNAME="$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)"
echo -e "vscode\nvscode" | passwd $USERNAME
chown vscode /etc/profile.d/00-fix-login-env.sh /usr/local/share/ssh-init.sh
chsh -s $(which $1) $USERNAME
