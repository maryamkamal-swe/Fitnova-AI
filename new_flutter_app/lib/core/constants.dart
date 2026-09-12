/// Application-wide constants for FitNova AI.
class AppConstants {
  // Application Info
  static const String appName = 'FitNova AI';
  static const String appTagline = 'Your AI-Powered Fitness & Nutrition Coach';

  // API Configuration
  // Default Android Emulator URL.
  // For iOS Simulator or Desktop/Web, use 'http://127.0.0.1:8000' or 'http://localhost:8000'.
  // For Physical Device, use your local machine's IP (e.g. 'http://192.168.1.X:8000').
// Change this to your actual Render URL
  // Change this to your actual Render API URL
  static const String defaultBaseUrl = 'https://fitnova-ai-dv0n.onrender.com';
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );

  // Endpoint Paths
  static const String loginEndpoint = '/api/v1/auth/login';
  static const String registerEndpoint = '/api/v1/auth/register';
  static const String sendOtpEndpoint = '/api/v1/auth/send-otp';
  static const String verifyOtpEndpoint = '/api/v1/auth/verify-otp';
  static const String refreshEndpoint = '/api/v1/auth/refresh';
  static const String changePasswordEndpoint = '/api/v1/auth/change-password';
  static const String profileEndpoint = '/api/v1/profile';
  static const String healthMetricsEndpoint = '/api/v1/profile/health-metrics';
  static const String healthEndpoint = '/health';
  static const String progressEndpoint = '/api/v1/progress';
  static const String progressTodayEndpoint = '/api/v1/progress/today';
  static const String progressHistoryEndpoint = '/api/v1/progress/history';
  static const String progressStatsEndpoint = '/api/v1/progress/stats';
  static const String progressWeightChartEndpoint =
      '/api/v1/progress/chart/weight';
  static const String progressCaloriesChartEndpoint =
      '/api/v1/progress/chart/calories';
  static const String notificationsEndpoint = '/api/v1/notifications';
  static const String unreadNotificationsEndpoint =
      '/api/v1/notifications/unread';
  static const String aiChatEndpoint = '/api/v1/ai/chat';
  static const String mealPlanGenerateEndpoint = '/api/v1/meal-plans/generate';
  static const String mealPlanEndpoint = '/api/v1/meal-plans';
  static const String workoutPlanGenerateEndpoint =
      '/api/v1/workout-plans/generate';
  static const String workoutPlanEndpoint = '/api/v1/workout-plans';
  static const String voiceLanguagesEndpoint = '/api/v1/voice/languages';
  static const String voiceChatEndpoint = '/api/v1/voice/chat';
  static const String voiceTranscribeEndpoint = '/api/v1/voice/transcribe';
  static const String voiceTtsEndpoint = '/api/v1/voice/tts';

  // Named Routes
  static const String splashRoute = '/splash';
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String emailVerificationRoute = '/verify-email';
  static const String walkthroughRoute = '/onboarding';
  static const String homeRoute = '/home';
  static const String progressRoute = '/progress';
  static const String profileSetupRoute = '/profile/setup';
  static const String profileRoute = '/profile';
  static const String notificationsRoute = '/notifications';
  static const String chatRoute = '/chat';
  static const String mealPlanRoute = '/meal-plan';
  static const String workoutPlanRoute = '/workout-plan';

  // Storage Keys
  static const String tokenStorageKey = 'fitnova_jwt_token';
  static const String refreshTokenStorageKey = 'fitnova_refresh_token';

  // Timeouts
  static const Duration requestTimeout = Duration(seconds: 45);
}
