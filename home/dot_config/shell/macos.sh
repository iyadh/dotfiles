# shellcheck shell=sh
# shellcheck disable=SC1091 # every file sourced here is optional and untracked
# shellcheck disable=SC2154 # the entry point sets shell_dir
# macOS layer: Homebrew's environment and the paths only a Mac has. chezmoi
# puts this file on Macs alone, and the portable layer loads it before its own
# PATH entries, so a tool installed in the home directory still beats
# Homebrew's copy of it.
#
# The portable layer's shell_path_prepend/append are already defined here.

### Homebrew, wherever this Mac keeps it. Asked every time rather than skipped
### when HOMEBREW_PREFIX is already set: the variable is inherited, but PATH
### may not be, and `brew shellenv` costs about 14ms.
for brew_home in /opt/homebrew /usr/local "$HOME/.homebrew"; do
  if [ -x "$brew_home/bin/brew" ]; then
    eval "$("$brew_home/bin/brew" shellenv)"
    break
  fi
done
unset brew_home

### Android. The SDK is the Mac's own; only the tools come from Homebrew.
export ANDROID_HOME="$HOME/Library/Android/sdk"

if [ -n "${HOMEBREW_PREFIX-}" ]; then
  ### Java. The opt symlink is stable, so startup needn't fork java_home.
  if [ -d "$HOMEBREW_PREFIX/opt/openjdk@11" ]; then
    export JAVA_HOME="$HOMEBREW_PREFIX/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home"
    shell_path_prepend "$HOMEBREW_PREFIX/opt/openjdk@11/bin"
  fi

  export SDK_MANAGER="$HOMEBREW_PREFIX/bin/sdkmanager"
  export AVD="$HOMEBREW_PREFIX/bin/avdmanager"
  export ADB="$HOMEBREW_PREFIX/bin/adb"

  ### CocoaPods, run against the system gems rather than whatever rvm has set
  if [ -x "$HOMEBREW_PREFIX/bin/pod" ]; then
    # shellcheck disable=SC2139 # the prefix is known now; resolve it now
    alias pod="env GEM_HOME= GEM_PATH= $HOMEBREW_PREFIX/bin/pod"
  fi

  # pyenv's shims shadow the python Homebrew builds against, which breaks brew
  # itself. Drop them from PATH for the length of the call. command isn't an
  # option under env, so this names brew by path.
  if command -v pyenv >/dev/null 2>&1; then
    brew() {
      env PATH="$(printf %s "$PATH" | sed "s|$(pyenv root)/shims:||g")" \
        "$HOMEBREW_PREFIX/bin/brew" "$@"
    }
  fi
fi

### JetBrains Toolbox
shell_path_append "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

# Local override, never tracked: this Mac's own settings. Last in the layer,
# though the portable layer still puts its PATH entries in front of anything
# this adds, because it loads this layer before its own.
if [ -r "$shell_dir/macos.local.sh" ]; then
  . "$shell_dir/macos.local.sh"
fi
