# Load the Zephyr/ZMK environment into THIS terminal.
# Use:  . ./activate.sh      (with the dot - running it as ./activate.sh won't stick)
. /home/nortem/.zinstaller/env.sh
cd "$HOME/Documents/zephyrproject/zmk/app"
echo "zmk env active: $(which west)"
