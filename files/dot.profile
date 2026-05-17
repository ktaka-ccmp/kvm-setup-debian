# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

command -v mesg >/dev/null && mesg n

agent="/tmp/ssh-agent-$USER"
if [ -S "$SSH_AUTH_SOCK" ]; then
        case $SSH_AUTH_SOCK in
        /tmp/*/agent.[0-9]*)
                ln -snf "$SSH_AUTH_SOCK" $agent && export SSH_AUTH_SOCK=$agent
        esac
elif [ -S $agent ]; then
        export SSH_AUTH_SOCK=$agent
else
        echo "no ssh-agent"
fi

if [ -f "/etc/kvmhost" ]; then
PS1='${debian_chroot:+($debian_chroot)}\u@\h.$(cat /etc/kvmhost):\w\$ '
else
PS1='${debian_chroot:+($debian_chroot)}\u@\H:\w\$ '
fi
