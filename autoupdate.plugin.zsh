# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# self-update

if which tput &>/dev/null ; then
  ncolors=$(tput colors)
fi

if [[ ${-} == *i*  &&  -n "${ncolors}"  &&  "${ncolors}" -ge 8 ]]; then
  RED="$(tput setaf 1)"
  BLUE="$(tput setaf 4)"
  GREEN="$(tput setaf 2)"
  NORMAL="$(tput sgr0)"
else
  BLUE=""
  BOLD=""
  GREEN=""
  NORMAL=""
fi

zmodload zsh/datetime

function _current_epoch() {
  echo $(( EPOCHSECONDS / 86400 ))
}

function _update_zsh_custom_update() {
  echo "LAST_EPOCH=$(_current_epoch)" >| "${ZSH_CACHE_DIR}/.zsh-custom-update"
}

function _get_epoch_target() {
  local epoch_target_value

  if ! zstyle -g epoch_target_value ':omz:update' frequency ; then
    epoch_target_value="${UPDATE_ZSH_DAYS}"
  fi

  # Default to old behavior
  epoch_target_value=${epoch_target_value:-13}

  echo "${epoch_target_value}"
}

epoch_target="$(_get_epoch_target)"

function _upgrade_custom_plugin() {
  # path of plugin/theme
  fullpath=$(dirname "${1}")
  # its name
  pathname=$(basename "${fullpath}")
  # its type (plugin/theme)
  pathtype=$(dirname "${fullpath}")
  pathtype=$(basename ${pathtype:0:((${#pathtype} - 1))})

  if [ -f "${fullpath}/.noautoupdate" ]; then
    printf "${GREEN}%s${NORMAL}\n" "Auto update of the ${pathname} ${pathtype} has been disabled (with .noautoupdate)."
  else
    last_head=$( git -C "${fullpath}" rev-parse HEAD )
    if git -C "${fullpath}" pull --quiet --rebase --stat --autostash ; then
      curr_head=$( git -C "${fullpath}" rev-parse HEAD )
      if [ "${last_head}" != "${curr_head}" ]; then
        printf "${GREEN}%s${NORMAL}\n" "Hooray! the ${pathname} ${pathtype} has been updated."
      else
        printf "${BLUE}%s${NORMAL}\n" "The ${pathname} ${pathtype} was already at the latest version."
      fi
    else
      printf "${RED}%s${NORMAL}\n" "There was an error updating the ${pathname} ${pathtype}. Try again later?"
    fi
  fi
}

function upgrade_oh_my_zsh_custom() {
  # Check if quiet mode is disabled
  if [[ -z "${ZSH_CUSTOM_AUTOUPDATE_QUIET}" ]]; then
    printf "${BLUE}%s${NORMAL}\n" "Upgrading Custom Plugins"
  fi

  # Determine the number of workers for parallel updates
  num_workers=$( printf "%.0f" "${ZSH_CUSTOM_AUTOUPDATE_NUM_WORKERS}" )
  local worker_idx=0
  set +m

  # Find all custom plugins and update them
  find -L "${ZSH_CUSTOM}" -name .git | while read plugin_dir ; do
    if (( num_workers <= 1 || num_workers > 16 )); then
      _upgrade_custom_plugin "${plugin_dir}"
    else
      # Increment the worker index (loop around if num_workers exceeded)
      (( worker_idx = (worker_idx + 1) % num_workers ))
      # wait if we have looped past the end
      if (( worker_idx == 0 )); then
        wait
      fi
      # run the upgrade in the background
      (_upgrade_custom_plugin "${plugin_dir}") &
    fi
  done
  wait
  set -m
}

alias upgrade_oh_my_zsh_all='zsh "${ZSH}/tools/upgrade.sh"; upgrade_oh_my_zsh_custom'


if [[ -f ~/.zsh-custom-update ]]; then
  mv ~/.zsh-custom-update "${ZSH_CACHE_DIR}/.zsh-custom-update"
fi

function _dispatch_update_mode() {
  local mode_value

  zstyle -g mode_value ':omz:update' mode
  if [[ -z "${mode_value}" ]]; then
    if [[ "${DISABLE_AUTO_UPDATE:-false}" == "true" ]]; then
      mode_value="disabled"
    elif [[ "${DISABLE_UPDATE_PROMPT:-false}" == "true" ]]; then
      mode_value="auto"
    else
      mode_value="prompt"
    fi
  fi

  echo "${mode_value}"
}

update_mode="$(_dispatch_update_mode)"

if [[ "${update_mode}" == "disabled" ]]; then
  # No updates
elif [[ -f "${ZSH_CACHE_DIR}/.zsh-custom-update" ]]; then
  source "${ZSH_CACHE_DIR}/.zsh-custom-update"

  if [[ -z "${LAST_EPOCH}" ]]; then
    LAST_EPOCH=0
  fi

  epoch_diff=$(( $(_current_epoch) - LAST_EPOCH ))
  if (( epoch_diff > epoch_target )); then
    if [[ "${update_mode}" == "auto" ]]; then
      (upgrade_oh_my_zsh_custom)
    elif [[ "${update_mode}" == "reminder" ]]; then
      echo "[oh-my-zsh] It's time to update! You can do that by running \`upgrade_oh_my_zsh_custom\`"
    else
      echo "[oh-my-zsh] Would you like to check for custom plugin updates? [Y/n]: \c"
      read line
      if [[ "${line}" == Y* || "${line}" == y* || -z "${line}" ]]; then
        (upgrade_oh_my_zsh_custom)
      fi
    fi
    _update_zsh_custom_update
  fi
else
  _update_zsh_custom_update
fi

unset -f _update_zsh_custom_update
unset -f _current_epoch
unset -f _get_epoch_target
unset -f _dispatch_update_mode