#!/system/bin/sh
# Called by the standalone AliceBridge or PowerShell installer. Never writes system/boot partitions.
set -e
export ANDROID_DATA=/data ANDROID_ROOT=/system PATH=/system/bin:/sbin:/bin:/opt/bin:/opt/sbin
umask 077
STAGE=$1
case "$STAGE" in /data/local/tmp/station-remote-*) ;; *) echo 'Invalid staging directory'; exit 1;; esac
BB=/sbin/busybox
DIR=/data/station-remote
[ "$(id -u)" = 0 ] || { echo 'Root SSH is required'; exit 1; }
[ "$(getprop ro.build.version.sdk)" = 23 ] || { echo 'This release is tested only on Station 1 / Android 6 (SDK 23)'; exit 1; }
[ "$(getprop ro.board.platform)" = tulip ] || { echo 'This installer is for Yandex Station 1 (tulip) only'; exit 1; }
[ -x /system/bin/app_process ] && [ -x "$BB" ] || { echo 'Android app_process and AliceBridge busybox are required'; exit 1; }
if [ ! -f /data/dropbear/start.sh ]; then
    if "$BB" grep -q '/data/dropbear/start.sh' /system/etc/rc.local; then
        mkdir -p /data/dropbear
        printf '#!/system/bin/sh\n' > /data/dropbear/start.sh
        chmod 700 /data/dropbear/start.sh
    else
        echo 'AliceBridge startup hook is missing. Enable SSH once in AliceBridge, then re-run.'
        exit 1
    fi
fi

# A build with another signature cannot update the installed app: copy its data,
# reinstall, then return the data to the new app user.
replace_signed_app() {
    package=$1; apk=$2; data=/data/data/$package
    keep=$DIR/app-data/$package-$(date +%Y%m%d-%H%M%S)
    echo "Signature differs: reinstalling $package and restoring its data"
    # Android refuses installs below 10% (max 500 MB) of free /data; keep 50 MB on top.
    # Old busybox wraps long device names, so count columns from the end.
    free_kb=$("$BB" df -k /data | "$BB" awk 'END {print $(NF-2)}')
    total_kb=$("$BB" df -k /data | "$BB" awk 'END {print $(NF-4)}')
    need_kb=$((total_kb / 10))
    [ "$need_kb" -le 512000 ] || need_kb=512000
    need_kb=$((need_kb + 51200))
    if [ "$free_kb" -lt "$need_kb" ]; then
        echo "Not enough space on /data: free about $(((need_kb - free_kb) / 1024 + 1)) MB more and re-run"
        return 1
    fi
    am force-stop "$package"
    mkdir -p "$DIR/app-data"
    chmod 700 "$DIR" "$DIR/app-data"
    "$BB" cp -a "$data" "$keep"
    pm uninstall "$package" | "$BB" grep -q Success || return 1
    output=$(pm install "$apk" 2>&1)
    echo "$output"
    echo "$output" | "$BB" grep -q Success || { echo "Previous $package data is kept in $keep"; return 1; }
    uid=$(stat -c %u "$data")
    for item in "$keep"/* "$keep"/.[!.]*; do
        [ -e "$item" ] || continue
        case "${item##*/}" in lib) continue;; esac
        rm -rf "$data/${item##*/}"
        mv "$item" "$data/"
    done
    chown -R "$uid:$uid" "$data"
    restorecon -R "$data"
    rm -rf "$keep"
}

echo '[1/5] Installing missing TV apps (existing app data is preserved)'
# Android 6 PackageManager opens APK paths as system, not as the root shell.
chmod 755 "$STAGE"
for apk in "$STAGE"/*.apk; do
    [ -f "$apk" ] || continue
    chmod 644 "$apk"
    output=$(pm install -r "$apk" 2>&1)
    echo "$output"
    echo "$output" | "$BB" grep -q Success && continue
    case "${apk##*/}:$output" in
        SmartTube*:*INSTALL_FAILED_UPDATE_INCOMPATIBLE*) replace_signed_app org.smarttube.stable "$apk" && continue;;
    esac
    echo 'APK installation failed; current remote is unchanged'
    exit 1
done
chmod 700 "$STAGE"

mkdir -p "$DIR/backups"
chmod 700 "$DIR" "$DIR/backups"
BACKUP=$DIR/backups/$(date +%Y%m%d-%H%M%S)-$$
mkdir "$BACKUP"
for name in station-remote.jar index.html remote-start.sh auth.properties; do
    [ ! -f "$DIR/$name" ] || cp -p "$DIR/$name" "$BACKUP/$name"
done
cp -p /data/dropbear/start.sh "$BACKUP/dropbear-start.sh"
[ ! -f /data/dropbear/remote.sh ] || cp -p /data/dropbear/remote.sh "$BACKUP/legacy-remote.sh"
[ ! -f /opt/etc/lighttpd/remote.conf ] || cp -p /opt/etc/lighttpd/remote.conf "$BACKUP/legacy-lighttpd.conf"
echo "$BACKUP" > "$DIR/last-backup"

echo '[2/5] Switching the web remote'
[ ! -f "$DIR/remote-start.sh" ] || /system/bin/sh "$DIR/remote-start.sh" stop
if [ -s /opt/var/run/lighttpd-remote.pid ]; then
    old=$(cat /opt/var/run/lighttpd-remote.pid)
    case "$old" in ''|*[!0-9]*|0|1) ;; *)
        if [ -r "/proc/$old/cmdline" ] && $BB tr '\000' ' ' < "/proc/$old/cmdline" | $BB grep -q 'lighttpd.*remote.conf'; then kill "$old" 2>/dev/null || true; fi;;
    esac
fi
sleep 1
for name in station-remote.jar index.html remote-start.sh; do cp "$STAGE/$name" "$DIR/$name.new"; mv "$DIR/$name.new" "$DIR/$name"; done
chmod 600 "$DIR/station-remote.jar" "$DIR/index.html"
chmod 700 "$DIR/remote-start.sh"
printf '#!/system/bin/sh\nexec /system/bin/sh /data/station-remote/remote-start.sh "$@"\n' > /data/dropbear/remote.sh
chmod 700 /data/dropbear/remote.sh
if ! $BB grep -q '/data/dropbear/remote.sh' /data/dropbear/start.sh; then
    printf '\n/sbin/busybox setsid /system/bin/sh /data/dropbear/remote.sh </dev/null >>/data/dropbear/remote.log 2>&1 &\n' >> /data/dropbear/start.sh
fi
[ -f /data/dropbear/tv.conf ] || echo BOOT_LAUNCHER=alice > /data/dropbear/tv.conf

echo '[3/5] Starting and checking the new service'
/system/bin/sh "$DIR/remote-start.sh" now
lan_ip=$(ip -4 addr show dev wlan0 | $BB awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')
i=0
while :; do
    state=$(/system/bin/curl --noproxy '*' --max-time 2 -s "http://$lan_ip:8080/api/state" 2>/dev/null || true)
    echo "$state" | $BB grep -q '"version":"2.0.0"' && break
    i=$((i + 1)); [ "$i" -lt 12 ] || break
    sleep 1
done
if ! echo "$state" | $BB grep -q '"version":"2.0.0"'; then
    echo 'New remote failed its health check; restoring the previous remote'
    /system/bin/sh "$DIR/remote-start.sh" stop || true
    for name in station-remote.jar index.html remote-start.sh; do [ ! -f "$BACKUP/$name" ] || cp -p "$BACKUP/$name" "$DIR/$name"; done
    cp -p "$BACKUP/dropbear-start.sh" /data/dropbear/start.sh
    [ ! -f "$BACKUP/legacy-remote.sh" ] || cp -p "$BACKUP/legacy-remote.sh" /data/dropbear/remote.sh
    [ ! -f /data/dropbear/remote.sh ] || /system/bin/sh /data/dropbear/remote.sh now || true
    exit 1
fi
echo '[4/5] First-run password setup'
echo "REMOTE_URL=http://$lan_ip:8080/"
if [ -s "$DIR/setup.token" ]; then
    echo "SETUP_URL=http://$lan_ip:8080/#setup=$(cat "$DIR/setup.token")"
else
    echo 'Existing remote password preserved.'
fi
echo "BACKUP=$BACKUP"
for file in "$STAGE"/*.apk "$STAGE/station-remote.jar" "$STAGE/index.html" "$STAGE/remote-start.sh" "$STAGE/install-on-speaker.sh"; do
    [ ! -f "$file" ] || rm -f "$file"
done
rmdir "$STAGE" 2>/dev/null || true
echo '[5/5] Done. Alice was not stopped or rebooted.'
