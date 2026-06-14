# preschool_knowledge_app

## Сборка с адресом сервера

Из папки `mobile_app`:

```powershell
.\build-apk.ps1 -ServerIp 194.34.239.165
```

По умолчанию используется порт `8081`, протокол `http` и release-сборка. Все параметры можно задать явно:

```powershell
.\build-apk.ps1 -ServerIp 194.34.239.165 -Port 8081 -Scheme http -Mode release
```

Также можно вызвать Flutter напрямую, передав полный URL:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://194.34.239.165:8081
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
