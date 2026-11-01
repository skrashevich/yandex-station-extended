#!/system/bin/sh
# Station 1 (tulip, Android 6): install the remote and missing TV apps from AliceBridge.
# Re-run to update. Existing apps, settings and the remote password are preserved.
# Rollback copies are saved in /data/station-remote/backups/.
set -e
export ANDROID_DATA=/data ANDROID_ROOT=/system PATH=/system/bin:/sbin:/bin:/opt/bin:/opt/sbin
umask 077
BB=/sbin/busybox
case "${1:-}" in ''|--remote-only) ;; *) echo 'Usage: sh install.sh [--remote-only]'; exit 2;; esac
[ -x "$BB" ] && [ -x /system/bin/curl ] || { echo 'AliceBridge busybox and system curl are required'; exit 1; }
[ "$(id -u)" = 0 ] || { echo 'Run in the rooted Station terminal in AliceBridge'; exit 1; }
[ "$(getprop ro.board.platform)" = tulip ] && [ "$(getprop ro.build.version.sdk)" = 23 ] || { echo 'Only Station 1 / Android 6 is supported'; exit 1; }
STAGE=/data/local/tmp/station-remote-$(date +%s)-$$
mkdir -p "$STAGE"
"$BB" uudecode -o "$STAGE/payload.tar.gz" <<'STATION_REMOTE_PAYLOAD'
begin-base64 600 payload.tar.gz
__PAYLOAD_BASE64_WRAPPED__
====
STATION_REMOTE_PAYLOAD
actual=$($BB sha256sum "$STAGE/payload.tar.gz" | $BB awk '{print $1}')
[ "$actual" = '__PAYLOAD_SHA256__' ] || { echo 'Embedded archive checksum failed'; exit 1; }
$BB gzip -dc "$STAGE/payload.tar.gz" | $BB tar -xf - -C "$STAGE"
rm -f "$STAGE/payload.tar.gz"

download_apk() {
    package=$1; name=$2; url=$3; expected=$4; replace=${5:-}
    installed=$(pm path "$package" 2>/dev/null || true)
    case "$installed" in package:*)
        [ -n "$replace" ] || { echo "Already installed: $package"; return; }
        current=$($BB sha256sum "${installed#package:}" | $BB awk '{print $1}')
        [ "$current" != "$expected" ] || { echo "Already installed: $package"; return; }
        echo "Replacing $package with the Station 1 build";;
    esac
    echo "Downloading $name"
    if [ -f /system/vendor/quasar/ca-certificates.crt ]; then
        /system/bin/curl --fail --location --retry 2 --connect-timeout 15 --max-time 300 \
            --cacert /system/vendor/quasar/ca-certificates.crt "$url" -o "$STAGE/$name.part"
    else
        /system/bin/curl --fail --location --retry 2 --connect-timeout 15 --max-time 300 "$url" -o "$STAGE/$name.part"
    fi
    actual=$($BB sha256sum "$STAGE/$name.part" | $BB awk '{print $1}')
    [ "$actual" = "$expected" ] || { echo "APK checksum failed: $name"; exit 1; }
    mv "$STAGE/$name.part" "$STAGE/$name"
}
if [ "${1:-}" != --remote-only ]; then
    download_apk com.conreo.couchytv Couchy.apk \
        https://github.com/conreo/couchy-launcher/releases/download/v1.0.6/Couchy-Launcher-v1.0.6.apk \
        9d065bbefada54eaad65e3174e606d03c2f767000efb5ebe6343ea8b6b439c8a
    # SmartTube 32.68 with the Station 1 controls fix (see ../smarttube/), replaces the official build
    download_apk org.smarttube.stable SmartTube.apk \
        https://github.com/vladivanov2004/yandex-station-extended/releases/download/smarttube-32.68-station1/SmartTube_stable_32.68_station1_arm64-v8a.apk \
        d1af87106b8a6d57c49f4de66dcc6f04e96bf99711ac9d4b2245826d34f6ac41 replace
    download_apk com.v2ray.ang v2rayNG.apk \
        https://github.com/2dust/v2rayNG/releases/download/1.9.45/v2rayNG_1.9.45_arm64-v8a.apk \
        72fb0b4ee3f4ab37608d17ff658ba2bdec2e65248ee9f07c3d375992a12ec148
fi
/system/bin/sh "$STAGE/install-on-speaker.sh" "$STAGE"
