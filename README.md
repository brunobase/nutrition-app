# nutrient_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 🔐 환경 설정 (처음 실행 시)

이 프로젝트는 Firebase와 Google Cloud Vision API를 사용합니다.
민감한 키 파일들은 `.gitignore`에 포함되어 있으므로 직접 생성해야 합니다.

### 1. Firebase 설정
- `android/app/google-services.example.json` → `android/app/google-services.json` 으로 복사 후 본인 Firebase 값 입력
- `lib/firebase_options.example.dart` → `lib/firebase_options.dart` 으로 복사 후 본인 Firebase 값 입력
- 또는 `flutterfire configure` 명령으로 자동 생성

### 2. Google Cloud Vision API 설정
- `assets/vision_key.example.json` → `assets/vision_key.json` 으로 복사 후 서비스 계정 키 입력
- Google Cloud Console에서 서비스 계정 키를 발급받아야 합니다.
