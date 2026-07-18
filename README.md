# Harmony — Apple Music–style Flutter frontend

Полностью рабочий UI аудиоплеера в стиле Apple Music. Сейчас подключён
**мок-бэкенд** (`lib/services/mock_api_service.dart`) с тестовыми треками
(публичные mp3 SoundHelix) и заглушками обложек — приложение запускается
и полностью работает без какого-либо сервера.

## Что реализовано

1. Регистрация / вход по email + паролю — `lib/screens/auth/`
2. Загрузка треков через админку/скрипт — на бэкенде (`backend_reference.py`, `/tracks/upload`)
3. Главный экран со списком треков — `lib/screens/home/home_tab.dart`
4. Плеер: play/pause/seek/next/prev — `lib/screens/player/now_playing_screen.dart`, `lib/providers/player_provider.dart`
5. Плейлисты — `lib/screens/library/`
6. Избранное (Liked Songs) — интегрировано в `LibraryProvider`
7. Кэш последних прослушанных — `lib/services/cache_service.dart` (SharedPreferences)
8. Поиск треков — `lib/screens/search/search_screen.dart`
9. Фоновое воспроизведение + управление в шторке уведомлений — `just_audio` + `just_audio_background`
10. 2 языка (EN/RU) — `lib/l10n/app_strings.dart`, переключение в настройках
11. Пометка для аккаунтов разработчиков + загрузка треков прямо из приложения — `lib/screens/admin/upload_screen.dart`
12/13. Тёмная (чёрный + белые вставки) / светлая (белый + серые вставки) темы — `lib/theme/app_theme.dart`

Тестовые аккаунты (в моке):
- `dev@example.com` / `password123` — аккаунт разработчика (виден пункт "Upload Track")
- `user@example.com` / `password123` — обычный пользователь

## Запуск

```bash
flutter pub get
flutter run
```

Если у вас пустая папка без `android/`, `ios/` и т.д. (например, вы просто
скопировали содержимое `lib/` и `pubspec.yaml`), сначала выполните в корне
проекта:

```bash
flutter create . --project-name audio_player_app
```

Это безопасно генерирует недостающие платформенные папки, не трогая уже
существующие `lib/` и `pubspec.yaml`.

## Переход на реальный бэкенд

Весь UI обращается к бэкенду только через интерфейс `ApiService`
(`lib/services/api_service.dart`). Чтобы подключить настоящий сервер:

1. Поднимите `backend_reference.py` (см. ниже) или свой сервер с тем же
   REST-контрактом.
2. В `lib/main.dart` замените:
   ```dart
   final ApiService api = MockApiService.instance;
   ```
   на:
   ```dart
   final ApiService api = RemoteApiService(baseUrl: 'https://your-server.com');
   ```

Больше никаких правок не требуется — все экраны и провайдеры уже
завязаны на абстракцию `ApiService`.

## Бэкенд (backend_reference.py)

Один файл на Flask + SQLite, реализующий весь контракт: регистрацию,
логин, треки, плейлисты, избранное и загрузку треков (для dev-аккаунтов).
Хранилище файлов — Yandex Object Storage (S3-совместимое), либо, если
переменные окружения не заданы, локальная папка `uploads/` (для быстрого
теста без облака).

```bash
pip install flask flask-cors boto3 werkzeug
python backend_reference.py
# слушает http://0.0.0.0:8000
```

Переменные окружения для Yandex Storage:
```
YANDEX_BUCKET=my-bucket
YANDEX_KEY_ID=...
YANDEX_SECRET=...
YANDEX_ENDPOINT=https://storage.yandexcloud.net   # опционально, значение по умолчанию
HARMONY_DEV_EMAILS=dev@example.com,other@dev.com  # какие email — разработчики
```

## Фоновое воспроизведение / уведомления

Пакет `just_audio_background` сам добавляет нужные разрешения в
`android/app/src/main/AndroidManifest.xml` (foreground service) при сборке.
Для iOS откройте `ios/Runner/Info.plist` и добавьте в `UIBackgroundModes`
значение `audio` (обычно достаточно одной строки, подробности — в README
пакета `just_audio_background` на pub.dev).

## Структура проекта

```
lib/
  models/            Track, Playlist, AppUser
  services/           api_service.dart (контракт), mock_api_service.dart (заглушка),
                      remote_api_service.dart (клиент для реального бэкенда),
                      audio_player_service.dart, cache_service.dart
  providers/          AppState (тема/язык), AuthProvider, LibraryProvider, PlayerProvider
  theme/              app_theme.dart — чёрная/белая темы
  l10n/               app_strings.dart — EN/RU строки
  screens/            auth, home, search, library, player, settings, admin
  widgets/            переиспользуемые виджеты (track tile, section header)
backend_reference.py  Однофайловый Python-бэкенд (см. выше)
```
