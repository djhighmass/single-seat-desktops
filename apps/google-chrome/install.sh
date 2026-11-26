# Google Chrome. Sourced by apps/install.sh.
# extrepo overwrites /etc/default/google-chrome when it first enables the
# repository (no source file yet), hence the third argument.
from_extrepo google_chrome google-chrome-stable "$APPS_ETC/default/google-chrome"
