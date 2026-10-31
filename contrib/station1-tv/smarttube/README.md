# SmartTube для Станции 1

На прошивке Станции 1 (`tulip`, Android 6.0.1) `View.setAlpha()` не действует:
у любого элемента интерфейса прозрачность остаётся 1.0. SmartTube прячет панель
плеера сдвигом на 400 px и затуханием, поэтому после скрытия у нижнего края экрана
оставались название видео и строка с автором.

[`station1-hide-controls.patch`](station1-hide-controls.patch) меняет leanback-фрагмент
плеера: если прозрачность не работает (проверяется один раз на пробном `View`), строки
при скрытии уезжают целиком за нижний край экрана. На других устройствах поведение
не меняется.

Готовый APK: релиз
[`smarttube-32.68-station1`](https://github.com/vladivanov2004/yandex-station-extended/releases/tag/smarttube-32.68-station1),
файл `SmartTube_stable_32.68_station1_arm64-v8a.apk`, SHA-256
`d1af87106b8a6d57c49f4de66dcc6f04e96bf99711ac9d4b2245826d34f6ac41`.
Пакет тот же — `org.smarttube.stable`, но подпись своя, поэтому официальные
обновления SmartTube поверх него не устанавливаются.

## Сборка

Исходники: [yuliskov/SmartTube](https://github.com/yuliskov/SmartTube), коммит
`4b3f333e540a1403429d1a9d86dec758e59288f9` (версия 32.68) с подмодулями.
Нужны JDK 17 и Android SDK с `platforms;android-34` и `build-tools;30.0.3`
(или другой установленной версией в `SharedModules/constants.gradle`).

```sh
git clone --recurse-submodules https://github.com/yuliskov/SmartTube.git
cd SmartTube
git checkout 4b3f333e540a1403429d1a9d86dec758e59288f9
git submodule update --init --recursive
git apply /путь/к/station1-hide-controls.patch
./gradlew :smarttubetv:assembleStstableRelease
```

Без `keystore.properties` в корне проекта получится неподписанный APK; для установки
его нужно подписать своим ключом. AGP 7.4 из проекта не читает `android.jar` от
SDK 35, поэтому нужна именно платформа 34.
