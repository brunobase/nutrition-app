# 프로젝트 이름
영양관리 앱

## 프로젝트 소개
디미고 특별전형을 준비하던 중 "오늘 먹은 음식을 정리해서 볼 수 있으면 좋지 않을까?"라는 생각이 들어 영양 관리 앱을 만들게 되었습니다.
하루 동안 먹은 음식을 기록하고 정리해서 볼 수 있도록 간단한 영양 관리 앱을 구현했습니다.

처음에는 앱 개발에 대해 거의 알지 못했지만 아이디어를 실제로 구현해 보고 싶어서 Dart 언어와 Flutter 프레임워크를 새롭게 배우며 개발을 진행했습니다.
앱을 만드는 과정에서 개발 환경을 설정하고 앱 템플릿을 선택하며 디자인을 구성하는 과정에서도 여러 시행착오를 겪었지만, 하나씩 해결하면서 앱을 완성할 수 있었습니다.

## 사용 기술
### 프론트 엔드
- Flutter (Dart) — 크로스플랫폼 앱 프레임워크 (Android / iOS / Web / Windows / macOS / Linux)
- fl_chart — 차트/그래프
- flutter_svg — SVG 이미지

### 벡엔드
- Firebase Authentication — 로그인/회원가입, Google 소셜 로그인
- Cloud Firestore — 데이터베이스
- Firebase Storage — 이미지 파일 저장

### 외부 API
- Google Cloud Vision API — 이미지 텍스트 인식 (바코드/식품 분석)
- Google ML Kit — 텍스트 인식
- Google Sign In — 구글 소셜 로그인

### 기타 패키지
- mobile_scanner — 바코드 스캔
- image_picker — 이미지 선택
- flutter_local_notifications — 로컬 알림
- dio / http — HTTP 통신

## 주요 기능
- 음식 기록
- 하루 식단 확인
- 영양소 바코드 스캔
- 간단한 영양 관리
- 통계자료를 통한 영양관리
- 영양소 부족시 음식 추천

## 프로젝트 구조
```
nutrient_app/
├── .gitignore
├── pubspec.yaml
├── firebase.json
├── lib/
│   ├── main.dart
│   ├── login.dart
│   ├── signup_1.dart
│   ├── signup_2.dart
│   ├── firebase_options.dart
│   ├── barcode.dart
│   ├── food.dart
│   ├── nutrition.dart
│   ├── nutrients_db.dart
│   ├── search.dart
│   ├── result.dart
│   ├── profile.dart
│   ├── me.dart
│   ├── me_standard.dart
│   ├── setting.dart
│   ├── statistics_page.dart
│   ├── onboarding_1.dart
│   ├── onboarding_2.dart
│   ├── onboarding_flow.dart
│   ├── request_email.dart
│   └── start.dart
├── assets/
│   ├── vision_key.json
│   └── (SVG 이미지들)
├── android/
│   └── app/
│       └── google-services.json
├── ios/
├── macos/
├── windows/
├── linux/
└── web/
```

## 실행 방법
Android studio에서 애뮬레이션이나 안드로이드 폰으로 프로젝트를 실행하면 앱을 사용할 수 있습니다.

## 배운 점
이 프로젝트를 통해 앱을 만드는 과정을 경험할 수 있었습니다.
아이디어를 실제로 구현하기 위해 필요한 언어와 프레임워크를 새롭게 배우면서 개발을 진행했고, 처음에는 어려웠지만 계속 시도하면서 앱을 완성할 수 있었습니다.
이 경험을 통해 아이디어를 직접 구현하는 과정에서 개발의 재미를 느낄 수 있었습니다.
나중에 더 보완한다면 데이터베이스나 바코드를 인식했을 때 더 많은 데이터를 가지고 올 수 있도록 하고 싶습니다.
