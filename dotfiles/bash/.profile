# Home Manager still owns session variables and paths. NixOS with
# useUserPackages uses /etc/profiles; standalone Home Manager uses ~/.nix-profile.
for hm_session_vars in \
  "/etc/profiles/per-user/${USER}/etc/profile.d/hm-session-vars.sh" \
  "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
do
  if [ -r "$hm_session_vars" ]; then
    . "$hm_session_vars"
    break
  fi
done
unset hm_session_vars

# Match services.ssh-agent's Home Manager session behavior.
if [ -z "${SSH_AUTH_SOCK:-}" ] || [ -z "${SSH_CONNECTION:-}" ]; then
  export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent"
fi
