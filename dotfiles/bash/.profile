# Home Manager still owns session variables and paths.
hm_session_vars="/etc/profiles/per-user/${USER}/etc/profile.d/hm-session-vars.sh"
if [ -r "$hm_session_vars" ]; then
  . "$hm_session_vars"
fi
unset hm_session_vars

# Match services.ssh-agent's Home Manager session behavior.
if [ -z "${SSH_AUTH_SOCK:-}" ] || [ -z "${SSH_CONNECTION:-}" ]; then
  export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent"
fi
