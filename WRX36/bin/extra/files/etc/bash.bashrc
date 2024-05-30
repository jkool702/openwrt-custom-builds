# System-wide .bashrc file

# Continue if running interactively
[[ $- == *i* ]] || return 0
alias history0='history | sed -E s/'"'"'^[0-9 ]+'"'"'//'
[[ -f /usr/bin/forkrun.bash ]] && source /usr/bin/forkrun.bash 
[ ! -s /etc/shinit ] || . /etc/shinit
