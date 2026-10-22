import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/glass_container.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _ipCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  final LocalAuthentication auth = LocalAuthentication();
  bool _isLoading = false;
  String _errorMsg = '';
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _ipCtrl.text = context.read<AppStateProvider>().deviceIp;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
    _checkBiometrics();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final settings = context.read<SettingsController>();
    if (settings.biometricLogin &&
        context.read<AppStateProvider>().canResumeWithBiometrics) {
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Authenticate to access EcoBurn',
        );
        if (didAuthenticate && mounted) {
          await context.read<AppStateProvider>().biometricLoginSuccess();
        }
      } catch (e) {
        /* Fallback to manual login */
      }
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });
    final state = context.read<AppStateProvider>();
    final ipAddress = _ipCtrl.text.trim();
    if (ipAddress.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'Enter the ESP32 IP address.';
      });
      return;
    }
    await state.saveDeviceIp(ipAddress);
    final accepted = await state.login(_userCtrl.text, _passCtrl.text);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (!accepted) {
        _errorMsg =
            state.loginErrorMessage ??
            'Could not connect to the device. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();

    return Scaffold(
      body: Stack(
        children: [
          // Animated Background
          AnimatedBuilder(
            animation: _animCtrl,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -150 + (_animCtrl.value * 50),
                    left: -150 + (_animCtrl.value * 30),
                    child: Container(
                      width: 600,
                      height: 600,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.neonGreen.withValues(alpha: 0.15),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -200 + ((1 - _animCtrl.value) * 80),
                    right: -100 - (_animCtrl.value * 40),
                    child: Container(
                      width: 700,
                      height: 700,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.neonBlue.withValues(alpha: 0.1),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 100 + (_animCtrl.value * 100),
                    right: -150,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.neonOrange.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                final pagePadding = isCompact ? 16.0 : 24.0;
                final cardPadding = isCompact ? 16.0 : 48.0;
                final logoWidth = isCompact ? 220.0 : 280.0;
                final sectionSpacing = isCompact ? 32.0 : 48.0;
                final buttonSpacing = isCompact ? 32.0 : 40.0;

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(pagePadding),
                    child: GlassContainer(
                      borderRadius: 32,
                      color: theme.cardColor,
                      child: Padding(
                        padding: EdgeInsets.all(cardPadding),
                        child: SizedBox(
                          width: 360,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TweenAnimationBuilder<double>(
                                duration: const Duration(seconds: 1),
                                tween: Tween(begin: 0.0, end: 1.0),
                                curve: Curves.easeOutExpo,
                                builder: (context, val, child) =>
                                    Transform.scale(scale: val, child: child),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.asset(
                                    'assets/branding/ecoburn-logo.png',
                                    width: logoWidth,
                                    fit: BoxFit.contain,
                                    semanticLabel: 'EcoBurn',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                "Telemetry & Command Protocol",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: sectionSpacing),
                              TextField(
                                controller: _ipCtrl,
                                keyboardType: TextInputType.url,
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                decoration: _inputDec(
                                  "ESP32 IP address",
                                  AppIcons.wifi,
                                  theme,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _userCtrl,
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                decoration: _inputDec(
                                  "Operator ID",
                                  AppIcons.user,
                                  theme,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _passCtrl,
                                obscureText: true,
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                decoration: _inputDec(
                                  "Passcode",
                                  AppIcons.password,
                                  theme,
                                ),
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              if (_errorMsg.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _errorMsg,
                                  style: const TextStyle(
                                    color: AppTheme.neonRed,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              SizedBox(height: buttonSpacing),
                              SizedBox(
                                width: double.infinity,
                                height: 60,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.neonGreen,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: _isLoading ? null : _handleLogin,
                                  child: _isLoading
                                      ? const CircularProgressIndicator(
                                          color: Colors.black,
                                        )
                                      : const Text(
                                          "INITIATE CONNECTION",
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                ),
                              ),
                              if (settings.biometricLogin &&
                                  context
                                      .watch<AppStateProvider>()
                                      .canResumeWithBiometrics) ...[
                                const SizedBox(height: 24),
                                TextButton.icon(
                                  icon: const Icon(
                                    AppIcons.authentication,
                                    color: AppTheme.neonBlue,
                                  ),
                                  label: const Text(
                                    "Biometric Override",
                                    style: TextStyle(
                                      color: AppTheme.neonBlue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _checkBiometrics,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon, ThemeData theme) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey, size: 20),
      filled: true,
      fillColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.neonGreen, width: 1.5),
      ),
    );
  }
}

// ==========================================
// 6. MAIN APP SHELL (RESPONSIVE NAVIGATION)
// ==========================================
