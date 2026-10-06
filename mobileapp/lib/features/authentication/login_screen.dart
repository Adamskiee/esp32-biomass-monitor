part of '../../app/legacy_ui.dart';

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
    final settings = context.read<SettingsProvider>();
    if (settings.biometricLogin &&
        context.read<AppStateProvider>().canResumeWithBiometrics) {
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Authenticate to access Biomass Terminal',
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
      if (!accepted) _errorMsg = 'Device unavailable or credentials invalid.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();

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
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassContainer(
                borderRadius: 32,
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(48),
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
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.neonGreen.withValues(
                                  alpha: 0.3,
                                ),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.neonGreen.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              CupertinoIcons.flame_fill,
                              size: 64,
                              color: AppTheme.neonGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          "Biomass Core",
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Telemetry & Command Protocol",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 48),
                        TextField(
                          controller: _ipCtrl,
                          keyboardType: TextInputType.url,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                          decoration: _inputDec(
                            "ESP32 IP address",
                            CupertinoIcons.wifi,
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
                            CupertinoIcons.person_solid,
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
                            CupertinoIcons.lock_fill,
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
                        const SizedBox(height: 40),
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
                              CupertinoIcons.lock_shield_fill,
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
