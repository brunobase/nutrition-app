import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'onboarding_2.dart'; // 다음 페이지

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // ▶ 애니메이션 없는 라우트 헬퍼 (Onboarding2로 갈 때만 사용)
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  final List<Map<String, String>> onboardingData = [
    {
      "title": "환영합니다!",
      "desc": "건강한 삶을 위한 첫 발걸음을 축하합니다!",
      "image": "assets/onboarding1.svg"
    },
    {
      "title": "영양소 기록",
      "desc": "섭취한 식단을 기록하고 분석해보세요.",
      "image": "assets/onboarding2.svg"
    },
    {
      "title": "나만의 목표 만들기",
      "desc": "목표를 세우고, 변화해 가는 모습을 지켜보세요.",
      "image": "assets/onboarding3.svg"
    },
  ];

  void _nextPage() {
    if (_currentPage < onboardingData.length - 1) {
      // ✅ 쓸려 넘어가는 애니메이션 유지
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _goToOnboarding2(); // 마지막 페이지 → 즉시 전환
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      // ✅ 이전도 기존 애니 그대로 유지
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToOnboarding2() {
    // ✅ Onboarding2로는 즉시 전환(애니메이션 0초)
    Navigator.pushReplacement(context, _noAnim(const Onboarding2()));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: onboardingData.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              final data = onboardingData[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      data["image"]!,
                      width: 250,
                      height: 250,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      data["title"]!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data["desc"]!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ✅ 인디케이터
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < onboardingData.length; i++)
                          _buildDot(isActive: i == _currentPage),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // ✅ 하단 버튼
          Positioned(
            left: 0,
            right: 0,
            bottom: 55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 왼쪽 버튼
                  _currentPage == 0
                      ? TextButton(
                    onPressed: _goToOnboarding2, // 건너뛰기 → 즉시 전환
                    child: const Text(
                      '건너뛰기',
                      style: TextStyle(color: Colors.black87),
                    ),
                  )
                      : ElevatedButton(
                    onPressed: _previousPage,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: const Color(0xFF24C486),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),

                  // 오른쪽 버튼
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: const Color(0xFF24C486),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: const Icon(Icons.arrow_forward, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot({required bool isActive}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: isActive ? 10 : 8,
      height: isActive ? 10 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF24C486) : Colors.grey[300],
        shape: BoxShape.circle,
      ),
    );
  }
}
