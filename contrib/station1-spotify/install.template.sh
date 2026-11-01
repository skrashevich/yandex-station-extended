#!/system/bin/sh
# Spotify TV + local Alice voice bridge for Station 1, Android 6 / SDK 23.
# Run one file in AliceBridge. No VPN, metrics blocking, rootfs or audio settings changed.
# Rollback: sh /data/station1-spotify/install.sh uninstall (Spotify/login are preserved).
set -eu
export ANDROID_DATA=/data ANDROID_ROOT=/system EXTERNAL_STORAGE=/sdcard ANDROID_STORAGE=/storage
export PATH=/opt/bin:/opt/sbin:/system/bin:/sbin:/bin
DIR=/data/station1-spotify
BB=/sbin/busybox
START=/data/dropbear/start.sh
MODE=${1:-install}
[ "$(id -u)" = 0 ] || { echo 'Run in the root AliceBridge terminal'; exit 1; }
[ -x "$BB" ] || exit 1
stop_voice() {
    if [ -f "$DIR/voice.pid" ]; then
        pid=$(cat "$DIR/voice.pid")
        case "$pid" in ''|*[!0-9]*) ;; *)
            if [ -r "/proc/$pid/cmdline" ] && "$BB" tr '\000' ' ' < "/proc/$pid/cmdline" | "$BB" grep -q 'SpotifyVoice /data/station1-spotify'; then kill "$pid"; fi;;
        esac
        rm -f "$DIR/voice.pid"
    fi
}
case "$MODE" in
    status|account|login|pair|logout|reconnect|open)
        shift || true; exec sh "$DIR/control.sh" "$MODE" "$@";;
    disable)
        mkdir -p "$DIR"; : > "$DIR/disabled"; stop_voice
        sh "$DIR/control.sh" pause >/dev/null 2>&1 || true
        echo 'Spotify voice bridge disabled'; exit 0;;
    enable|repair)
        rm -f "$DIR/disabled"; sh "$DIR/boot.sh"; echo 'Spotify bridge started'; exit 0;;
    uninstall)
        mkdir -p "$DIR"; : > "$DIR/disabled"; stop_voice
        sh "$DIR/control.sh" pause >/dev/null 2>&1 || true
        if [ -f "$START" ]; then
            "$BB" grep -v '# station1-spotify$' "$START" > "$DIR/start.new" || true
            cat "$DIR/start.new" > "$START"; rm -f "$DIR/start.new"
        fi
        echo 'Spotify bridge stopped and removed from autostart.'
        echo 'Spotify app, account, helpers and backups are preserved. Use logout to remove the account.'
        exit 0;;
    install|repair-app) ;;
    *) echo 'Usage: install.sh install|status|login|logout|reconnect|disable|enable|repair|repair-app|uninstall'; exit 1;;
esac
case "$(getprop ro.product.device)" in tulip*) ;; *) echo 'Only Station 1 / tulip is supported'; exit 1;; esac
[ "$(getprop ro.build.version.sdk)" = 23 ] || { echo 'Expected Android SDK 23'; exit 1; }
[ -f "$START" ] || { echo 'AliceBridge startup hook missing'; exit 1; }
work=/data/local/tmp/station1-spotify-install.$$
mkdir -p "$work" "$DIR/backups"
chmod 755 "$work"; chmod 700 "$DIR" "$DIR/backups"
cleanup() {
    if [ -n "${session:-}" ]; then pm install-abandon "$session" >/dev/null 2>&1 || true; fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
"$BB" sed -n '/^begin-base64 644 payload.tar.gz$/,/^====$/p' "$0" | "$BB" uudecode -o "$work/payload.tar.gz"
echo '__PAYLOAD_SHA__  payload.tar.gz' > "$work/payload.sha256"
(cd "$work"; "$BB" sha256sum -c payload.sha256)
"$BB" gzip -dc "$work/payload.tar.gz" | "$BB" tar -xf - -C "$work"
(cd "$work"; "$BB" sha256sum -c files.sha256)
chmod 644 "$work/control.jar"
export CLASSPATH=$work/control.jar
if pm path com.spotify.tv.android 2>/dev/null | "$BB" grep -q '^package:'; then
    base=$(pm path com.spotify.tv.android | "$BB" sed -n 's/^package:\(.*\/base.apk\)$/\1/p' | "$BB" head -n 1)
    [ -n "$base" ] || { echo 'Cannot inspect the existing Spotify app'; exit 1; }
    app_process /system/bin SpotifyControl verify "$base" || {
        echo 'Existing Spotify app/version is preserved. This installer expects official Spotify TV 1.134.2.'; exit 1;
    }
    fresh=0
else
    fresh=1
fi
if [ "$fresh" = 1 ] || [ "$MODE" = repair-app ]; then
    echo 'Downloading original Spotify TV 1.134.2 (split APKs)...'
    /system/bin/curl -fL --user-agent 'Mozilla/5.0' --retry 2 --connect-timeout 15 --max-time 180 \
        --cacert /system/vendor/quasar/ca-certificates.crt \
        'https://d.apkpure.net/b/XAPK/com.spotify.tv.android?versionCode=2340200' -o "$work/spotify.xapk"
    echo '__XAPK_SHA__  spotify.xapk' > "$work/spotify.sha256"
    (cd "$work"; "$BB" sha256sum -c spotify.sha256)
    app_process /system/bin SpotifyControl extract "$work/spotify.xapk" "$work"
    cat > "$work/apks.sha256" <<'HASHES'
__APK_HASHES__
HASHES
    (cd "$work"; "$BB" sha256sum -c apks.sha256)
    chmod 644 "$work"/*.apk
    app_process /system/bin SpotifyControl verify "$work/com.spotify.tv.android.apk"
    result=$(pm install-create -r)
    session=$(printf '%s' "$result" | "$BB" sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
    [ -n "$session" ] || { printf '%s\n' "$result"; exit 1; }
    for file in com.spotify.tv.android.apk config.armeabi_v7a.apk config.en.apk config.ru.apk config.xhdpi.apk; do
        pm install-write "$session" "$file" "$work/$file"
    done
    pm install-commit "$session"; session=
fi
backup=$DIR/backups/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$backup"
cp -p "$START" "$backup/start.sh"
for file in control.jar boot.sh control.sh install.sh; do
    [ ! -f "$DIR/$file" ] || cp -p "$DIR/$file" "$backup/$file"
done
stop_voice
for file in control.jar boot.sh control.sh; do cp "$work/$file" "$DIR/$file.new"; mv "$DIR/$file.new" "$DIR/$file"; done
chmod 600 "$DIR/control.jar"; chmod 700 "$DIR/boot.sh" "$DIR/control.sh"
cp "$0" "$DIR/install.sh.new"; chmod 700 "$DIR/install.sh.new"; mv "$DIR/install.sh.new" "$DIR/install.sh"
"$BB" grep -q '# station1-spotify$' "$START" || printf '\nsh /data/station1-spotify/boot.sh >/dev/null 2>&1 & # station1-spotify\n' >> "$START"
rm -f "$DIR/disabled"
sh "$DIR/boot.sh"
echo "Installed. Backup: $backup"
echo "Pairing code: sh $DIR/control.sh login"
echo "Account/status: sh $DIR/control.sh account"
echo "Sign out: sh $DIR/control.sh logout"
[ "$fresh" != 1 ] || sh "$DIR/control.sh" login || true
exit 0
begin-base64 644 payload.tar.gz
__PAYLOAD__
====
