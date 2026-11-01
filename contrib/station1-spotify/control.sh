#!/system/bin/sh
set -eu
export ANDROID_DATA=/data ANDROID_ROOT=/system EXTERNAL_STORAGE=/sdcard ANDROID_STORAGE=/storage
export PATH=/opt/bin:/opt/sbin:/system/bin:/sbin:/bin
DIR=/data/station1-spotify
export CLASSPATH=$DIR/control.jar
case "${1:-status}" in
    status|account) exec app_process /system/bin SpotifyControl info;;
    login|pair) exec app_process /system/bin SpotifyControl login;;
    open) exec app_process /system/bin SpotifyControl open;;
    reconnect)
        app_process /system/bin SpotifyControl pause >/dev/null 2>&1 || true
        am force-stop com.spotify.tv.android
        exec app_process /system/bin SpotifyControl open;;
    logout)
        if [ "${2:-}" != --yes ]; then
            [ -t 0 ] || { echo 'Use an interactive terminal or explicitly pass logout --yes'; exit 1; }
            printf 'Remove the Spotify account and local Spotify preferences from this Station? Type YES: '
            IFS= read -r answer
            [ "$answer" = YES ] || { echo 'Cancelled'; exit 0; }
        fi
        app_process /system/bin SpotifyControl pause >/dev/null 2>&1 || true
        pm clear com.spotify.tv.android
        rm -f "$DIR/spotify-active"
        echo 'Spotify account removed from this Station. Your online account is unchanged.'
        echo "To show a new pairing code: sh $DIR/control.sh login";;
    play|search|pause|resume|next|previous|seek|position)
        exec app_process /system/bin SpotifyControl "$@";;
    *) echo 'Usage: control.sh status|login|logout|reconnect|open|play QUERY|pause|resume|next|previous|seek'; exit 1;;
esac
