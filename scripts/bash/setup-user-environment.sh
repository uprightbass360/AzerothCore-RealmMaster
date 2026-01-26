#!/bin/bash
# Setup user environment with sudo access and bash completion
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_ok() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

TARGET_USER="${1:-${USER}}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (use sudo)"
  exit 1
fi

echo ""
log_info "Setting up environment for user: $TARGET_USER"
echo ""

# 1. Add user to sudo group
log_info "Step 1/4: Adding $TARGET_USER to sudo group..."
if groups "$TARGET_USER" | grep -q "\bsudo\b"; then
  log_ok "User already in sudo group"
else
  usermod -aG sudo "$TARGET_USER"
  log_ok "Added $TARGET_USER to sudo group"
fi

# 2. Change default shell to bash
log_info "Step 2/4: Setting default shell to bash..."
CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
if [ "$CURRENT_SHELL" = "/bin/bash" ]; then
  log_ok "Default shell already set to bash"
else
  chsh -s /bin/bash "$TARGET_USER"
  log_ok "Changed default shell from $CURRENT_SHELL to /bin/bash"
fi

# 3. Create .bashrc with bash completion
log_info "Step 3/4: Setting up bash completion..."
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
BASHRC="$USER_HOME/.bashrc"

if [ -f "$BASHRC" ]; then
  log_warn ".bashrc already exists, checking for bash completion..."
  if grep -q "bash_completion" "$BASHRC"; then
    log_ok "Bash completion already configured in .bashrc"
  else
    log_info "Adding bash completion to existing .bashrc..."
    cat >> "$BASHRC" << 'EOF'

# Enable bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
    chown "$TARGET_USER:$TARGET_USER" "$BASHRC"
    log_ok "Bash completion added to .bashrc"
  fi
else
  log_info "Creating new .bashrc with bash completion..."
  cat > "$BASHRC" << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Set a fancy prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Enable color support for ls and grep
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Enable bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Docker completion (if docker is installed)
if [ -f /usr/share/bash-completion/completions/docker ]; then
    . /usr/share/bash-completion/completions/docker
fi
EOF
  chown "$TARGET_USER:$TARGET_USER" "$BASHRC"
  chmod 644 "$BASHRC"
  log_ok "Created .bashrc with bash completion"
fi

# 4. Create .bash_profile to source .bashrc for login shells
log_info "Step 4/4: Setting up bash_profile for login shells..."
BASH_PROFILE="$USER_HOME/.bash_profile"

if [ -f "$BASH_PROFILE" ]; then
  if grep -q "\.bashrc" "$BASH_PROFILE"; then
    log_ok ".bash_profile already sources .bashrc"
  else
    log_info "Adding .bashrc sourcing to existing .bash_profile..."
    cat >> "$BASH_PROFILE" << 'EOF'

# Source .bashrc if it exists
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
    chown "$TARGET_USER:$TARGET_USER" "$BASH_PROFILE"
    log_ok ".bash_profile updated to source .bashrc"
  fi
else
  log_info "Creating .bash_profile..."
  cat > "$BASH_PROFILE" << 'EOF'
# ~/.bash_profile: executed by bash(1) for login shells.

# Source .bashrc if it exists
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
  chown "$TARGET_USER:$TARGET_USER" "$BASH_PROFILE"
  chmod 644 "$BASH_PROFILE"
  log_ok "Created .bash_profile"
fi

echo ""
log_ok "Environment setup complete for $TARGET_USER!"
echo ""
echo "Changes applied:"
echo "  ✓ Added to sudo group (password required)"
echo "  ✓ Default shell changed to /bin/bash"
echo "  ✓ Bash completion enabled (.bashrc)"
echo "  ✓ Login shell configured (.bash_profile)"
echo ""
log_warn "Important: You need to log out and log back in for shell changes to take effect"
log_info "To test sudo: sudo -v (will prompt for password)"
log_info "To test tab completion: type 'systemctl rest' and press TAB"
log_info "To verify shell: echo \$SHELL (should show /bin/bash)"
echo ""
