import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/progress_service.dart';
import 'profile_screen.dart';
import '../services/notification_service.dart';
import 'progress_overview_screen.dart';
import 'chat_screen.dart';
import 'meal_plan_screen.dart';
import 'workout_plan_screen.dart';
import '../services/chat_service.dart';
import '../services/meal_plan_service.dart';
import '../services/workout_plan_service.dart';
import '../services/voice_service.dart';

/// Temporary authenticated dashboard screen with 5 Material 3 navigation tabs and profile overview.
class HomeScreen extends StatefulWidget {
  final UserProfile? initialProfile;
  final AuthService? authService;
  final ProfileService? profileService;
  final NotificationService? notificationService;
  final ProgressService? progressService;
  final ChatService? chatService;
  final MealPlanService? mealPlanService;
  final WorkoutPlanService? workoutPlanService;

  const HomeScreen({
    super.key,
    this.initialProfile,
    this.authService,
    this.profileService,
    this.notificationService,
    this.progressService,
    this.chatService,
    this.mealPlanService,
    this.workoutPlanService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  AuthService? _authService;
  ProfileService? _profileService;
  NotificationService? _notificationService;
  ProgressService? _progressService;
  ChatService? _chatService;
  MealPlanService? _mealPlanService;
  WorkoutPlanService? _workoutPlanService;
  VoiceService? _voiceService;
  UserProfile? _profile;
  bool _isLoadingProfile = false;

  void _ensureServicesInitialized() {
    _authService ??= widget.authService ?? AuthService();
    _profileService ??= widget.profileService ?? ProfileService();
    _notificationService ??=
        widget.notificationService ?? NotificationService();
    _progressService ??= widget.progressService ?? ProgressService();
    _chatService ??= widget.chatService ?? ChatService();
    _mealPlanService ??= widget.mealPlanService ?? MealPlanService();
    _workoutPlanService ??= widget.workoutPlanService ?? WorkoutPlanService();
    _voiceService ??= VoiceService();
  }

  Future<void> _showLanguages() async {
    _ensureServicesInitialized();
    try {
      final languages = await _voiceService!.getLanguages();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Voice languages'),
          content: languages.isEmpty
              ? const Text('English is currently available.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: languages
                      .map((language) => ListTile(
                            leading: const Icon(Icons.language),
                            title: Text(language.name),
                            subtitle: Text(language.translateCode),
                          ))
                      .toList(),
                ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureServicesInitialized();
    _profile = widget.initialProfile;

    if (_profile == null) {
      _loadProfile();
    }
    _refreshUnreadCount();
  }

  Future<void> _refreshUnreadCount() async {
    _ensureServicesInitialized();
    try {
      await _notificationService!.refreshUnreadCount();
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    _ensureServicesInitialized();
    setState(() {
      _isLoadingProfile = true;
    });

    try {
      final profile = await _profileService!.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of FitNova AI?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      _ensureServicesInitialized();
      await _authService!.logout();
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppConstants.loginRoute,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureServicesInitialized();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Language',
          onPressed: _showLanguages,
          icon: const Icon(Icons.language_rounded),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: AppTheme.onPrimary,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              AppConstants.appName,
              style: TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _notificationService ?? ChangeNotifier(),
            builder: (context, child) => Badge(
              isLabelVisible: _notificationService!.unreadCount > 0,
              label: Text('${_notificationService!.unreadCount}'),
              child: IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () async {
                  await Navigator.of(context).pushNamed(
                    AppConstants.notificationsRoute,
                  );
                  _refreshUnreadCount();
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            icon:
                const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center_rounded),
            label: 'Workouts',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant_rounded),
            label: 'Meals',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_rounded),
            selectedIcon: Icon(Icons.insert_chart_rounded),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTabIndex) {
      case 0:
        return _buildHomeDashboardTab();
      case 1:
        return WorkoutPlanScreen(
          workoutPlanService: _workoutPlanService!,
        );
      case 2:
        return MealPlanScreen(
          mealPlanService: _mealPlanService!,
        );
      case 3:
        return ProgressOverviewScreen(progressService: _progressService!);
      case 4:
        return _buildProfileTab();
      default:
        return _buildHomeDashboardTab();
    }
  }

  Widget _buildHomeDashboardTab() {
    final userName =
        _profile?.name.isNotEmpty == true ? _profile!.name : 'Athlete';

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.surface,
                    AppTheme.surface.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isLoadingProfile)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Welcome, $userName! ',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your FitNova AI fitness dashboard is ready.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Profile Summary Section
            Text(
              'Profile Overview',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Goal',
                    value: _formatDisplay(_profile?.fitnessGoal) ??
                        'General Fitness',
                    icon: Icons.flag_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Experience',
                    value: _formatDisplay(_profile?.fitnessExperience) ??
                        'Intermediate',
                    icon: Icons.trending_up_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Activity Level',
                    value:
                        _formatDisplay(_profile?.activityLevel) ?? 'Moderate',
                    icon: Icons.directions_run_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Weight / Height',
                    value: (_profile?.weight != null &&
                            _profile?.height != null)
                        ? '${_profile!.weight.toStringAsFixed(1)} kg • ${_profile!.height.toStringAsFixed(0)} cm'
                        : 'Not Set',
                    icon: Icons.straighten_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(chatService: _chatService),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Ask your AI coach'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return ProfileScreen(profileService: _profileService!);
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String? _formatDisplay(String? value) {
    if (value == null || value.isEmpty) return null;
    return value
        .split('_')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}
