# System-wide .bashrc file

# Continue if running interactively
[[ $- == *i* ]] || return 0
alias history0='history | sed -E s/'"'"'i"'"'^[0-9 ]+'"'"'"'"'//'
[ \! -s /etc/shinit ] || . /etc/shinit
