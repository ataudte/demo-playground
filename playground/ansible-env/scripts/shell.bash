cd "$ANSIBLE_ENV_PROJECT" || exit 1
source "$ANSIBLE_ENV_PROJECT/.venv/bin/activate"
export ANSIBLE_ENV_ACTIVE_PROJECT="$ANSIBLE_ENV_PROJECT"
PS1='(ansible) \W \$ '
stop() { exit; }
printf '\n%s\n\n' 'Ansible environment active. Type stop or exit to leave it.'
