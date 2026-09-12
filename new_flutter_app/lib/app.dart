// new_flutter_app/lib/app.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'core/constants.dart';
import 'core/utils/string_utils.dart';
import 'core/theme.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/token_storage.dart';
import 'services/profile_service.dart';
import 'services/progress_service.dart';
import 'services/workout_plan_service.dart';
import 'services/meal_plan_service.dart';
import 'services/chat_service.dart';
import 'services/voice_service.dart';
import 'services/notification_service.dart';
import 'services/user_id_service.dart';
import 'screens/chat_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/onboarding/app_walkthrough_screen.dart';
import 'screens/dashboard_page.dart';
import 'screens/meal_plan_screen.dart';
import 'screens/workout_plan_screen.dart';
import 'screens/profile_screen.dart';
import 'models/user_profile.dart';
import 'models/progress_stats.dart';
import 'models/chat_message.dart';
import 'widgets/design_system.dart';
import 'screens/hydration_screen.dart';
import 'screens/nutrition_screen.dart';
import 'screens/daily_progress_screen.dart';
import 'screens/progress_overview_screen.dart';

class FitNovaApp extends StatefulWidget {
  const FitNovaApp({super.key});
  @override
  State<FitNovaApp> createState() => _FitNovaAppState();
}

class _FitNovaAppState extends State<FitNovaApp> {
  final _storage = TokenStorage();
  late final _api = ApiClient(
    tokenStorage: _storage,
    onSessionExpired: _handleSessionExpired,
  );
  late final _auth = AuthService(apiClient: _api, tokenStorage: _storage);
  bool _authenticated = false;
  bool _restoringSession = true;
  bool _onboardingCompleted = true;
  UserProfile? _initialProfile;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _storage.getToken();
    final valid = token != null && _hasValidJwtExpiry(token);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _authenticated = valid;
      _onboardingCompleted = prefs.getBool(onboardingCompletedKey) ??
          (prefs.getBool('isProfileCompleted') ?? false);
      _restoringSession = false;
    });
    if (valid) _loadProfileInBackground();
  }

  // Fixed: Safely guards against missing exp claims and invalid base64 padding
  bool _hasValidJwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      
      final payloadString = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadString);
      
      if (payload is! Map || !payload.containsKey('exp')) return false;
      
      final expiry = payload['exp'];
      if (expiry is! num) return false;
      
      return DateTime.fromMillisecondsSinceEpoch(expiry.toInt() * 1000)
          .isAfter(DateTime.now());
    } catch (_) {
      return false; // Safely fail closed
    }
  }

  Future<void> _loadProfileInBackground() async {
    final profileService = ProfileService(apiClient: _api);
    try {
      final profile = await profileService.getProfile();
      if (!mounted) return;
      setState(() => _initialProfile = profile);
    } on ApiException catch (_) {
      // The API client handles expired sessions globally.
    }
  }

  void _profileCompleted(UserProfile profile) {
    setState(() {
      _authenticated = true;
      _initialProfile = profile;
      _onboardingCompleted = false;
    });
  }

  Widget _authenticatedHome() {
    if (!_onboardingCompleted) {
      return AppWalkthroughScreen(onFinished: () {
        setState(() => _onboardingCompleted = true);
      });
    }
    return FitNovaShell(
      api: _api,
      initialProfile: _initialProfile,
      onLogout: () async {
        await _auth.logout();
        if (!mounted) return;
        setState(() {
          _authenticated = false;
          _initialProfile = null;
        });
      },
    );
  }

  void _handleSessionExpired() {
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _initialProfile = null;
    });
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AccentTheme>(
        valueListenable: AppTheme.accent,
        builder: (_, accent, __) => MaterialApp(
          title: 'FitNova AI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme(accentTheme: accent),
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.darkTheme(accentTheme: accent),
          home: _restoringSession
              ? const Scaffold(
                  backgroundColor: AppTheme.background,
                  body: Center(child: CircularProgressIndicator()))
              : _authenticated
                  ? _authenticatedHome()
                  : LoginScreen(
                      authService: _auth,
                      profileService: ProfileService(apiClient: _api),
                      onSignedIn: (profile) {
                        setState(() {
                          _authenticated = true;
                          _initialProfile = profile;
                        });
                      },
                    ),
          routes: {
            AppConstants.loginRoute: (_) => LoginScreen(
                  authService: _auth,
                  profileService: ProfileService(apiClient: _api),
                  onSignedIn: (profile) {
                    setState(() {
                      _authenticated = true;
                      _initialProfile = profile;
                    });
                  },
                ),
            AppConstants.registerRoute: (_) => RegisterScreen(
                  authService: _auth,
                  profileService: ProfileService(apiClient: _api),
                ),
            AppConstants.emailVerificationRoute: (context) {
              final arguments = ModalRoute.of(context)?.settings.arguments;
              final data = arguments is Map ? arguments : const {};
              return EmailVerificationScreen(
                authService: _auth,
                email: data['email'] as String? ?? '',
                pendingProfile: data['profile'] is UserProfile
                    ? data['profile'] as UserProfile
                    : null,
                developmentCode: data['developmentCode'] as String?,
              );
            },
            AppConstants.walkthroughRoute: (routeContext) =>
                AppWalkthroughScreen(
                  onFinished: () {
                    setState(() => _onboardingCompleted = true);
                    Navigator.of(routeContext).pushNamedAndRemoveUntil(
                      AppConstants.homeRoute,
                      (route) => false,
                      arguments: _initialProfile,
                    );
                  },
                ),
            AppConstants.homeRoute: (context) {
              final arguments = ModalRoute.of(context)?.settings.arguments;
              return FitNovaShell(
                api: _api,
                initialProfile:
                    arguments is UserProfile ? arguments : _initialProfile,
                onLogout: () async {
                  await _auth.logout();
                  if (!mounted) return;
                  setState(() {
                    _authenticated = false;
                    _initialProfile = null;
                  });
                },
              );
            },
            AppConstants.profileSetupRoute: (context) {
              final arguments = ModalRoute.of(context)?.settings.arguments;
              return ProfileSetupScreen(
                profileService: ProfileService(apiClient: _api),
                initialProfile:
                    arguments is UserProfile ? arguments : _initialProfile,
                onComplete: _profileCompleted,
              );
            },
            AppConstants.profileRoute: (_) => ProfileScreen(
                  profileService: ProfileService(apiClient: _api),
                ),
            AppConstants.notificationsRoute: (_) => NotificationsScreen(
                  notificationService: NotificationService(apiClient: _api),
                ),
            AppConstants.chatRoute: (_) => ChatScreen(
                  chatService: ChatService(apiClient: _api),
                  voiceService: VoiceService(apiClient: _api),
                ),
            AppConstants.mealPlanRoute: (_) => MealPlanScreen(
                  mealPlanService: MealPlanService(apiClient: _api),
                ),
            AppConstants.workoutPlanRoute: (_) => WorkoutPlanScreen(
                  workoutPlanService: WorkoutPlanService(apiClient: _api),
                  initialProfile: _initialProfile,
                ),
            AppConstants.progressRoute: (_) =>
                ProgressPage(service: ProgressService(apiClient: _api)),
          },
        ),
      );
}

class LandingPage extends StatelessWidget {
  final VoidCallback onStart;
  const LandingPage({super.key, required this.onStart});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: Image.asset(
                'assets/images/fitnova_hero_gym_1788801746681.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppTheme.background)),
          ),
          Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: .68))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text('FITNOVA AI',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4)),
                    const SizedBox(height: 18),
                    Text('Train Smarter.\nBecome Stronger.',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(
                                fontWeight: FontWeight.w900, height: 1.05)),
                    const SizedBox(height: 14),
                    const Text(
                        'Your adaptive AI fitness companion for every rep, meal and milestone.'),
                    const SizedBox(height: 30),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: onStart,
                            child: const Text('Start your journey  →'))),
                    const SizedBox(height: 24),
                    const Text('PERSONALIZED  •  POWERFUL  •  YOURS',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            letterSpacing: 1.3)),
                    const SizedBox(height: 18),
                  ]),
            ),
          ),
        ]),
      );
}

class AuthPage extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onSignedIn;
  const AuthPage({super.key, required this.auth, required this.onSignedIn});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _register = false, _busy = false;
  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid email and a 6+ character password.')));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        final registration = await widget.auth
            .register(email: _email.text, password: _password.text);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          AppConstants.emailVerificationRoute,
          arguments: {
            'email': registration.email.isEmpty
                ? _email.text.trim()
                : registration.email,
            'developmentCode': registration.developmentCode,
          },
        );
        return;
      } else {
        await widget.auth.login(email: _email.text, password: _password.text);
      }
      widget.onSignedIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('FITNOVA AI')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 30),
          Text(_register ? 'Build your foundation.' : 'Welcome back, athlete.',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
              _register
                  ? 'Create your profile and let FitNova AI adapt to you.'
                  : 'Your next breakthrough is one session away.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline))),
          const SizedBox(height: 14),
          TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 24),
          SizedBox(
              height: 54,
              child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const CircularProgressIndicator()
                      : Text(_register ? 'Create account' : 'Sign in'))),
          TextButton(
              onPressed: () => setState(() => _register = !_register),
              child: Text(_register
                  ? 'Already have an account? Sign in'
                  : 'New to FitNova AI? Create account')),
          const SizedBox(height: 36),
          const _OnboardingHint(
              icon: Icons.auto_awesome,
              text: 'AI plans that evolve with your progress'),
          const _OnboardingHint(
              icon: Icons.restaurant,
              text: 'Simple nutrition that fits your lifestyle'),
          const _OnboardingHint(
              icon: Icons.insights, text: 'Progress you can see and feel'),
        ])),
      );
}

class _OnboardingHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OnboardingHint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(text));
}

class FitNovaShell extends StatefulWidget {
  final ApiClient api;
  final UserProfile? initialProfile;
  final Future<void> Function() onLogout;
  const FitNovaShell({
    super.key,
    required this.api,
    required this.onLogout,
    this.initialProfile,
  });
  @override
  State<FitNovaShell> createState() => _FitNovaShellState();
}

class _FitNovaShellState extends State<FitNovaShell> {
  int _index = 0;
  int _refreshToken = 0;
  int _tourStep = 0;
  bool _showTour = false;
  bool _backendOnline = false;
  late final _profile = ProfileService(apiClient: widget.api);
  late final _progress = ProgressService(apiClient: widget.api);
  late final _workouts = WorkoutPlanService(apiClient: widget.api);
  late final _meals = MealPlanService(apiClient: widget.api);
  late final _chat = ChatService(apiClient: widget.api);
  late final _voice = VoiceService(apiClient: widget.api);
  List<Widget> get _pages => [
        DashboardPage(
          profile: _profile,
          progress: _progress,
          backendOnline: _backendOnline,
          refreshToken: _refreshToken,
        ),
        WorkoutPlanScreen(
          workoutPlanService: _workouts,
          initialProfile: widget.initialProfile,
        ),
        MealPlanScreen(mealPlanService: _meals),
        ProgressPage(service: _progress, refreshToken: _refreshToken),
        ChatScreen(chatService: _chat, voiceService: _voice),
        ProfileScreen(
          profileService: _profile,
          voiceService: _voice,
          chatService: _chat,
          onLogout: widget.onLogout,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _checkBackendHealth();
    _maybeStartTour();
  }

  Future<void> _maybeStartTour() async {
    final show = await DashboardTourOverlay.shouldShow();
    if (mounted && show) setState(() => _showTour = true);
  }

  Future<void> _checkBackendHealth() async {
    try {
      await widget.api
          .get('/', requiresAuth: false)
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _backendOnline = true);
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            IndexedStack(index: _index, children: _pages),
            if (_showTour)
              DashboardTourOverlay(
                stepIndex: _tourStep,
                onNext: () {
                  final next = _tourStep + 1;
                  setState(() {
                    _tourStep = next;
                    _index = dashboardTourSteps[next].tabIndex;
                    _refreshToken++;
                  });
                },
                onFinished: () => setState(() => _showTour = false),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (i) => setState(() {
              _index = i;
              _refreshToken++;
            }),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.fitness_center_outlined),
                  selectedIcon: Icon(Icons.fitness_center),
                  label: 'Workout'),
              NavigationDestination(
                  icon: Icon(Icons.restaurant_outlined),
                  selectedIcon: Icon(Icons.restaurant),
                  label: 'Meals'),
              NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Progress'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'Coach'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ]),
      );
}

class DashboardPage extends StatefulWidget {
  final ProfileService profile;
  final ProgressService progress;
  final bool backendOnline;
  final int refreshToken;
  const DashboardPage({
    super.key,
    required this.profile,
    required this.progress,
    required this.backendOnline,
    this.refreshToken = 0,
  });
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Object?>> _load;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  void _refresh() {
    _load = Future.wait([
      widget.profile.getProfile(),
      widget.progress.getProgressStats(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object?>>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingPage(title: 'Loading your plan…');
        }
        if (snapshot.hasError) {
          return _ErrorPage(message: snapshot.error.toString());
        }
        final p = snapshot.data![0] as UserProfile;
        final s = snapshot.data![1] as ProgressStats;
        return _Page(
            title:
                'Good morning, ${(p.name.isEmpty ? 'athlete' : p.name).toTitleCase()}',
            subtitle: 'Ready to make today count?',
            trailing: _BackendStatusDot(online: widget.backendOnline),
            children: [
              _HeroCard(
                  title: 'Today’s focus',
                  value: 'Your Adaptive Plan'.toTitleCase(),
                  detail:
                      '${p.fitnessExperience.toTitleCase()}  •  ${p.fitnessGoal.toTitleCase()}',
                  icon: Icons.bolt),
              const SizedBox(height: 18),
              const _SectionTitle('Your snapshot'),
              Row(children: [
                _Metric(
                    label: 'Streak',
                    value: '${s.workoutStreak} days',
                    icon: Icons.local_fire_department),
                _Metric(
                    label: 'Workouts',
                    value: '${s.totalWorkouts}',
                    icon: Icons.fitness_center),
                _Metric(
                    label: 'Weight',
                    value: s.avgWeight == null
                        ? '—'
                        : '${s.avgWeight!.toStringAsFixed(1)} kg',
                    icon: Icons.trending_up)
              ]),
              const SizedBox(height: 18),
              const _SectionTitle('Quick actions'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HydrationScreen()),
                    ).then((_) => _refresh()),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Hydration'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NutritionScreen()),
                    ).then((_) => _refresh()),
                    icon: const Icon(Icons.restaurant_outlined),
                    label: const Text('Log food'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DailyProgressScreen(
                                progressService: widget.progress,
                              )),
                    ).then((_) => _refresh()),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Log today'),
                  ),
                ],
              ),
            ]);
      });
}

class ProgressPage extends StatefulWidget {
  final ProgressService service;
  final int refreshToken;
  const ProgressPage(
      {super.key, required this.service, this.refreshToken = 0});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  late Future<ProgressStats> _load;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ProgressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  void _refresh() {
    _load = widget.service.getProgressStats();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProgressStats>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingPage(title: 'Calculating your progress…');
        }
        if (snapshot.hasError) {
          return _ErrorPage(message: snapshot.error.toString());
        }
        final s = snapshot.data!;
        return _Page(
            title: 'Progress',
            subtitle: 'Small wins. Big transformation.',
            children: [
              _HeroCard(
                  title: 'Consistency score',
                  value: '${s.avgGoalCompletion?.toStringAsFixed(0) ?? '—'}%',
                  detail: '${s.totalEntries} check-ins recorded',
                  icon: Icons.insights),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyProgressScreen(
                          progressService: widget.service,
                        ),
                      ),
                    ).then((_) => _refresh()),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Log today'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProgressOverviewScreen(
                          progressService: widget.service,
                        ),
                      ),
                    ).then((_) => _refresh()),
                    icon: const Icon(Icons.insights_outlined),
                    label: const Text('Details'),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              const _SectionTitle('This month'),
              _ListCard(
                  icon: Icons.check_circle_outline,
                  title: '${s.totalWorkouts} Workouts Completed',
                  detail: '${s.workoutStreak}-Day Current Streak'),
              _ListCard(
                  icon: Icons.monitor_weight_outlined,
                  title: 'Weight Trend',
                  detail: s.weightChange == null
                      ? 'No Trend Yet'
                      : '${s.weightChange!.toStringAsFixed(1)} kg change'),
              _ListCard(
                  icon: Icons.bedtime_outlined,
                  title: 'Recovery Average',
                  detail: s.avgSleep == null
                      ? 'No Sleep Data Yet'
                      : '${s.avgSleep!.toStringAsFixed(1)} hours'),
            ]);
      });
}

class CoachPage extends StatefulWidget {
  final ChatService service;
  const CoachPage({super.key, required this.service});
  @override
  State<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<CoachPage> {
  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  final _userIdService = UserIdService();
  late final String _fallbackSessionId =
      'fitnova-${DateTime.now().microsecondsSinceEpoch}';
  bool _busy = false;

  Future<String> _getSessionId() async {
    final userId = await _userIdService.getCurrentUserId();
    return userId == null || userId.isEmpty
        ? _fallbackSessionId
        : 'fitnova-user-$userId';
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _busy = true;
    });
    try {
      final reply = await widget.service.sendMessage(
        query: text,
        sessionId: await _getSessionId(),
      );
      setState(() => _messages.add(reply));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
          title: 'AI Coach',
          subtitle: 'Ask FitNova AI anything about your goals.',
          children: [
            if (_messages.isEmpty)
              const _ListCard(
                  icon: Icons.auto_awesome,
                  title: 'FitNova AI is ready',
                  detail: 'Your coach learns from every conversation.'),
            ..._messages.map((m) => Align(
                alignment:
                    m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Card(
                    color: m.isUser ? AppTheme.primary : AppTheme.surface,
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(m.text,
                            style: TextStyle(
                                color: m.isUser
                                    ? AppTheme.onPrimary
                                    : AppTheme.textPrimary)))))),
            const SizedBox(height: 12),
            TextField(
                controller: _input,
                onSubmitted: _send,
                decoration: InputDecoration(
                    hintText: 'Ask your coach…',
                    suffixIcon: IconButton(
                        onPressed: _busy ? null : () => _send(_input.text),
                        icon: const Icon(Icons.send)))),
            const SizedBox(height: 14),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'What should I eat after training?',
                  'How can I improve my squat?',
                  'Plan my week'
                ]
                    .map((p) =>
                        ActionChip(label: Text(p), onPressed: () => _send(p)))
                    .toList()),
          ]);
}

class ProfilePage extends StatefulWidget {
  final ProfileService service;
  final AuthService authService;
  final Future<void> Function() onLogout;
  const ProfilePage({
    super.key,
    required this.service,
    required this.authService,
    required this.onLogout,
  });
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<UserProfile> _future = widget.service.getProfile();
  final _name = TextEditingController();
  bool _saving = false;
  bool _changingPassword = false;
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _save(UserProfile profile) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.service.updateProfile(profile.copyWith(
          name: _name.text.toNameCase().isEmpty
              ? profile.name
              : _name.text.toNameCase()));
      if (mounted) {
        setState(() => _future = Future.value(updated));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_oldPassword.text.isEmpty || _newPassword.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Enter your current password and a new 8+ character password.')));
      return;
    }
    setState(() => _changingPassword = true);
    try {
      await widget.authService.changePassword(
        oldPassword: _oldPassword.text,
        newPassword: _newPassword.text,
      );
      _oldPassword.clear();
      _newPassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password changed successfully.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This permanently deletes your profile, plans, progress, notifications, and chat history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete permanently')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.deleteProfile();
      await widget.onLogout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingPage(title: 'Loading your profile…');
        }
        if (snapshot.hasError) {
          return _ErrorPage(message: snapshot.error.toString());
        }
        final p = snapshot.data!;
        if (_name.text.isEmpty) _name.text = p.name;
        return _Page(
            title: 'Profile',
            subtitle: 'Make FitNova AI work for your lifestyle.',
            children: [
              Card(
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.primary,
                          child: Text(
                              (p.name.isEmpty ? 'A' : p.name[0]).toUpperCase(),
                              style: const TextStyle(
                                  color: AppTheme.onPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold))),
                      title: Text((p.name.isEmpty ? 'FitNova athlete' : p.name)
                          .toTitleCase()),
                      subtitle: Text(
                          '${p.fitnessGoal.toTitleCase()} • ${p.fitnessExperience.toTitleCase()}'))),
              const SizedBox(height: 20),
              TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Display name')),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _saving ? null : () => _save(p),
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Save profile')),
              const SizedBox(height: 16),
              const _SectionTitle('Security'),
              TextField(
                  controller: _oldPassword,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 10),
              TextField(
                  controller: _newPassword,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password')),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: _changingPassword ? null : _changePassword,
                  child: _changingPassword
                      ? const CircularProgressIndicator()
                      : const Text('Change password')),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out')),
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: _deleteAccount,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete account')),
              const SizedBox(height: 16),
              const _SectionTitle('Appearance'),
              const FitNovaAccentSwitcher(),
            ]);
      });
}

class _LoadingPage extends StatelessWidget {
  final String title;
  const _LoadingPage({required this.title});
  @override
  Widget build(BuildContext context) => _Page(
          title: title,
          subtitle: 'FitNova AI is syncing securely with your account.',
          children: const [
            Center(
                child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator()))
          ]);
}

class _ErrorPage extends StatelessWidget {
  final String message;
  const _ErrorPage({required this.message});
  @override
  Widget build(BuildContext context) => _Page(
          title: 'Unable to load',
          subtitle: 'Check your connection and try again.',
          children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16), child: Text(message)))
          ]);
}

class _Page extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final Widget? trailing;
  const _Page({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
              children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 26),
            ...children,
          ]));
}

class _BackendStatusDot extends StatelessWidget {
  final bool online;

  const _BackendStatusDot({required this.online});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? Colors.green : Colors.amber,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Waking up',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

class _HeroCard extends StatelessWidget {
  final String title, value, detail;
  final IconData icon;
  const _HeroCard(
      {required this.title,
      required this.value,
      required this.detail,
      required this.icon});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, color: AppTheme.onPrimary, size: 32),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppTheme.onPrimary)),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.onPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.bold)),
          Text(detail, style: const TextStyle(color: AppTheme.onPrimary))
        ]))
      ]));
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext c) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold)));
}

class _Metric extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext c) => Expanded(
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: AppTheme.primary, size: 20),
                    const SizedBox(height: 12),
                    Text(value,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12))
                  ]))));
}

class _ListCard extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  const _ListCard({
    required this.icon,
    required this.title,
    required this.detail,
  });
  @override
  Widget build(BuildContext c) => Card(
      child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: .15),
              child: Icon(icon, color: AppTheme.primary)),
          title: Text(title),
          subtitle: Text(detail)));
}