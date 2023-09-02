set -o vi

export PATH=$PATH:/opt/homebrew/bin

[ -f ~/.fzf.zsh ] && source ~/.fzf.sh

####################################################################
#                  Git                                             #
####################################################################
alias ga="git add"
alias gc="git checkout"
alias gcb="git checkout -b"
alias gcm="git checkout master"
alias gcmt="git commit -m"
alias gs="git status"
alias gpush="git push"
