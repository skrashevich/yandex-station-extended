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
echo 'ba89c77540f26b6aaa42931dd1ccfc3b38a9f4d2ad33db58c245be02ebf470e9  payload.tar.gz' > "$work/payload.sha256"
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
    echo 'cce2572683217186c4b96286e990851e47d236b2593d9b1004a54f9ef02cd24a  spotify.xapk' > "$work/spotify.sha256"
    (cd "$work"; "$BB" sha256sum -c spotify.sha256)
    app_process /system/bin SpotifyControl extract "$work/spotify.xapk" "$work"
    cat > "$work/apks.sha256" <<'HASHES'
509106d1df7638cf43ff0d76e11b8d4c2a24ca128fcb84f3c3b674ab255a8562  com.spotify.tv.android.apk
7a790ce7e20b4905b6617b2850de778af5d494440869acd93c61ecf6c8217721  config.armeabi_v7a.apk
b9916898804e4d8e38b104f4ad6b1e82064c42215ddd581c8efa68286ea660fa  config.en.apk
491bbd8a318bce5af2ef1dc04adba0c1eded3db6b5c85c68fcd13f52b4da89f0  config.ru.apk
1c26b246dd77b99394a66ba882b57619d2f49a3dc7de35a7cae80959e9f84b05  config.xhdpi.apk
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
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
====
