import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/home/providers/home_providers.dart';
import '../features/onboarding/onboarding_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final profile = ref.read(profileProvider);
      if (profile == null && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      // M3 起接通以下路由
      GoRoute(
        path: '/stats',
        builder: (context, state) => const _ComingSoonScreen(title: '数据统计'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const _ComingSoonScreen(title: '设置'),
      ),
    ],
  );
});

class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 80),
            const SizedBox(height: 12),
            Text('$title · M3 起接入', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
