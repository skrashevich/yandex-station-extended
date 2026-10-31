#!/system/bin/sh
set -eu
export ANDROID_DATA=/data ANDROID_ROOT=/system EXTERNAL_STORAGE=/sdcard ANDROID_STORAGE=/storage
export PATH=/opt/bin:/opt/sbin:/system/bin:/sbin:/bin
DIR=/data/station1-spotify
BB=/sbin/busybox
[ ! -f "$DIR/disabled" ] || exit 0
[ -f "$DIR/control.jar" ] || exit 1
if [ -f "$DIR/voice.pid" ]; then
    pid=$(cat "$DIR/voice.pid")
    case "$pid" in ''|*[!0-9]*) ;; *)
        if [ -r "/proc/$pid/cmdline" ] && "$BB" tr '\000' ' ' < "/proc/$pid/cmdline" | "$BB" grep -q 'SpotifyVoice /data/station1-spotify'; then exit 0; fi;;
    esac
fi
(
    export CLASSPATH=$DIR/control.jar
    exec app_process /system/bin SpotifyVoice "$DIR"
) </dev/null >> "$DIR/voice.log" 2>&1 &
echo $! > "$DIR/voice.pid"
# Initialise the official client without opening a screen or starting music.
am startservice -n com.spotify.tv.android/.service.SpotifyTVService \
    -a com.spotify.tv.android.service.action.client.ACTION_PERFORM_INIT >/dev/null 2>&1 || true
