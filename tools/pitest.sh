#!/bin/zsh
# Test a Raspberry Pi running the SSH test image of Linux Mint ARM (./build.sh --test-ssh),
# or a testpi.sh VM running it, from this Mac: as root, with the key build.sh made in
# work/pi-test/ and against the image's own SSH host key, so the connection is checked.
#
# usage: pitest.sh find                       the test images that Avahi announces on the network
#        pitest.sh HOST[:PORT] ssh [COMMAND]  a shell, or one command (HOST: mint.local, an address,
#                                             127.0.0.1:2240 for testpi.sh)
#        pitest.sh HOST[:PORT] check          what the release tests look at, as a short report
#        pitest.sh HOST[:PORT] shot FILE.png  a screenshot of the Pi's display (the setup wizard or
#                                             the desktop)
#        pitest.sh HOST[:PORT] remove         take the test access out (the SSH server, the key, the
#                                             Avahi entry); the connection then ends. The Pi's
#                                             bootloader stays as the test image left it, without
#                                             automatic updates (how to turn them back on is printed)
emulate -L zsh
setopt err_exit pipe_fail

HERE=${0:A:h}
KEYS=${PI_TEST_DIR:-${HERE:h}/work/pi-test}
usage() { sed -n '6,15s/^# \{0,1\}//p' ${0:A}; exit 1 }

if [[ ${1:-} == find ]]; then
  # dns-sd runs until stopped and writes nothing into a pipe: give it a terminal and 5 seconds
  perl -e 'alarm shift; exec @ARGV' 5 script -q /dev/null dns-sd -B _ssh._tcp local. 2> /dev/null | tr -d '\r' \
    | sed -n 's/.*Linux Mint ARM test on \(.*\)$/\1.local/p' | sort -u || true
  exit 0
fi
(( $# >= 2 )) || usage
target=$1 action=$2
shift 2
host=${target%:*} port=22
[[ $target == *:* ]] && port=${target##*:}
[[ -f $KEYS/id_ed25519 && -f $KEYS/known_hosts ]] || { print -u2 "no test key in $KEYS: build the test image with ./build.sh --test-ssh"; exit 1 }
ssh_pi() {
  # (ssh reads UserKnownHostsFile as a list of names: quote the path, which may hold spaces)
  ssh -i $KEYS/id_ed25519 -o IdentitiesOnly=yes -o "UserKnownHostsFile=\"$KEYS/known_hosts\"" \
      -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o LogLevel=ERROR -p $port root@$host "$@"
}

# The X server on the Pi's display, for root: the setup wizard's or the desktop's.
X_ENV='x_env() {
  local args auth
  args=$(ps -o args= -C Xorg 2> /dev/null | head -1)
  [ -n "$args" ] || return 1
  # the desktop'"'"'s X server has an authority file; the setup wizard'"'"'s has none (-ac)
  auth=$(echo "$args" | grep -o -- "-auth [^ ]*" | cut -d" " -f2)
  echo "DISPLAY=:0${auth:+ XAUTHORITY=$auth}"
}'

CHECK=$X_ENV'
model=$(tr -d "\0" < /proc/device-tree/model 2> /dev/null || true)
echo "board:       ${model:-not a Raspberry Pi ($(systemd-detect-virt))}"
echo "kernel:      $(uname -r), $(( $(getconf PAGESIZE) / 1024 )) KiB pages"
echo "packages:    mint-arm-system $(dpkg-query -W -f "\${Version}" mint-arm-system), mint-arm-pi $(dpkg-query -W -f "\${Version}" mint-arm-pi), mintupdate $(dpkg-query -W -f "\${Version}" mintupdate)"
echo "started in:  $(systemd-analyze 2> /dev/null | head -1 | sed "s/^Startup finished in //")"
echo "state:       $(systemctl is-system-running), default target $(systemctl get-default)"
echo "failed:      [$(systemctl --failed --no-legend --plain | awk "{print \$1}" | xargs)]"
echo "accounts:    $(awk -F: "\$3 >= 1000 && \$3 < 60000" /etc/passwd | wc -l) person, oem account $(getent passwd oem > /dev/null && echo still there || echo removed)"
echo "memory:      $(free -m | awk "NR == 2 {print \$3 \" MiB used of \" \$2}")"
echo "swap:        $(swapon --show=NAME,SIZE,PRIO --noheadings | awk "{printf \"%s %s (priority %s)  \", \$1, \$2, \$3}")"
disk=/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")
echo "system:      $(df -h --output=size,avail / | tail -1 | awk "{print \$1 \", \" \$2 \" free\"}") on a $(lsblk -dno SIZE "$disk" | xargs) disk; grown: $([ -e /etc/growroot-grown ] && echo yes || echo no)"
echo "boot files:  $(df -h --output=used /boot/firmware | tail -1 | xargs) used; vmlinuz $(cmp -s /boot/firmware/vmlinuz "/boot/vmlinuz-$(uname -r)" && echo is || echo IS NOT) the running kernel"
xe=$(x_env || true)
if [ -n "$xe" ]; then
  glx=$(env $xe glxinfo -B 2> /dev/null || true)
  echo "graphics:    $(echo "$glx" | sed -n "s/^OpenGL renderer string: //p"), OpenGL $(echo "$glx" | sed -n "s/^OpenGL version string: \([^ ]*\).*/\1/p")"
  echo "display:     $(env $xe xrandr --current 2> /dev/null | awk "/ connected/ {printf \"%s \", \$1}")$(env $xe xrandr --current 2> /dev/null | sed -n "s/.*current \([0-9]*\) x \([0-9]*\),.*/\1x\2/p")"
fi
pid=$(pgrep -xo cinnamon || true)
if [ -n "$pid" ]; then
  echo "desktop:     Cinnamon $(tr "\0" "\n" < /proc/$pid/environ | grep -q "^LIBGL_ALWAYS_SOFTWARE=1" && echo "in SOFTWARE rendering" || echo running)"
else
  echo "desktop:     no Cinnamon session (setup running: $(systemctl is-active oem-config.service 2> /dev/null || true))"
fi
wifi=$(nmcli -t -f DEVICE,TYPE,STATE device 2> /dev/null | awk -F: "\$2 == \"wifi\" {print \$1 \" \" \$3}" | head -1)
if [ -n "$wifi" ]; then
  seen=$(timeout 30 nmcli -t -f SSID device wifi list --rescan yes 2> /dev/null | grep -c . || true)
  echo "Wi-Fi:       $wifi, $seen networks in range, power saving $(iw dev "${wifi%% *}" get power_save 2> /dev/null | sed "s/Power save: //")"
  echo "  firmware:  $(dmesg | grep -m1 -o "Firmware: BCM.*" | cut -c11- || true)"
else
  echo "Wi-Fi:       no Wi-Fi device"
fi
echo "Bluetooth:   $(timeout 10 bluetoothctl show 2> /dev/null | sed -n "s/^[[:space:]]*Powered: \(.*\)/controller, powered \1/p" | head -1 || true)"
[ -n "$(timeout 10 bluetoothctl list 2> /dev/null)" ] || echo "             (no Bluetooth controller)"
echo "sound:       $(aplay -l 2> /dev/null | sed -n "s/^card [0-9]*: \([^ ]*\) .*/\1/p" | sort -u | xargs)"
if [ -e /dev/vcio ]; then
  echo "power:       $(vcgencmd get_throttled) (0x0: never under-voltage or slowed down), $(vcgencmd measure_temp)"
  echo "  supply:    $(dmesg | grep -m1 -oE "(PSU|power supply|Under-voltage|max current)[^.]*" || echo "no message from the firmware")"
  fan=$(grep -l "pwm-fan\|cooling_fan" /sys/class/hwmon/hwmon*/name 2> /dev/null | head -1)
  [ -n "$fan" ] && echo "  fan:       $(cat "${fan%/name}"/fan1_input 2> /dev/null || echo ?) rpm"
  echo "bootloader:  $(timeout 30 rpi-eeprom-update 2> /dev/null | grep -E "^ *(CURRENT|LATEST):" | xargs)"
  echo "             automatic updates: $(systemctl is-enabled rpi-eeprom-update.service 2> /dev/null || true)"
fi
apt-get update -qq 2> /dev/null || true
echo "== Update Manager, updates offered:"
mintupdate-cli list 2>&1 | head -25
echo "== the browsers apt would install:"
for p in firefox thunderbird chromium-browser; do echo "$p: $(apt-cache policy "$p" | sed -n "s/^  Candidate: //p")"; done
'

SHOT=$X_ENV'
xe=$(x_env) || { echo "nothing is on the display" >&2; exit 1; }
env $xe python3 -c "
import sys, gi
gi.require_version(\"Gdk\", \"3.0\")
from gi.repository import Gdk
w = Gdk.get_default_root_window()
Gdk.pixbuf_get_from_window(w, 0, 0, w.get_width(), w.get_height()).savev(sys.argv[1], \"png\", [], [])
" /tmp/mint-arm-shot.png
cat /tmp/mint-arm-shot.png
rm -f /tmp/mint-arm-shot.png
'

# Runs as its own unit, so it finishes after the SSH server (and this connection) is gone.
REMOVE='systemd-run --quiet --unit=mint-arm-test-removal --no-block /bin/sh -c "
  sleep 2
  rm -f /etc/systemd/system/oem-config.target.wants/avahi-daemon.service \
        /etc/avahi/services/mint-arm-test-ssh.service /etc/ssh/sshd_config.d/50-mint-arm-test.conf \
        /root/.ssh/authorized_keys
  rmdir /root/.ssh 2> /dev/null
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -q openssh-server mesa-utils
  DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y -q
  systemctl try-reload-or-restart avahi-daemon.service"
echo "the test access is being removed; this connection ends in a moment"
echo "the bootloader updates itself again after: sudo systemctl unmask rpi-eeprom-update.service"'

case $action in
  ssh)    if (( $# )); then ssh_pi "$@"; else ssh_pi -t; fi ;;
  check)  ssh_pi bash -s <<< $CHECK ;;
  shot)   (( $# == 1 )) || usage
          ssh_pi bash -s <<< $SHOT > $1.part && mv $1.part $1 && print -r -- "$1" ;;
  remove) ssh_pi bash -s <<< $REMOVE ;;
  *)      usage ;;
esac
