import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:nocterm/nocterm.dart';

class FoxCommand extends Command<int> {
  @override
  String get description => 'Stay Fluffy with the Lumide Fox!';

  @override
  String get name => 'fox';

  @override
  Future<int> run() async {
    await runApp(const NoctermApp(home: _FoxTui()));
    return 0;
  }
}

class _FoxTui extends StatefulComponent {
  const _FoxTui();

  @override
  State<_FoxTui> createState() => _FoxTuiState();
}

class _FoxTuiState extends State<_FoxTui> {
  bool _isEyesClosed = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _startBlinkCycle();
  }

  void _startBlinkCycle() {
    // Random interval for more natural blinking
    final nextBlink = Duration(
      milliseconds:
          2000 + (3000 * (1.0 - (DateTime.now().millisecond / 1000))).toInt(),
    );
    _blinkTimer = Timer(nextBlink, _doBlink);
  }

  void _doBlink() {
    if (!mounted) return;
    setState(() => _isEyesClosed = true);

    // Hold blink for 150ms
    Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _isEyesClosed = false);
      _startBlinkCycle();
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  String _getFoxArt(bool closed) {
    final eye = closed ? '⣀⣀⣀' : '⢿⣿⡿';
    return '''
⠀⠀⠀⠀⠀⠀⠀⠀⣠⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⣾⡿⠛⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⠃⢻⣧⡀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣿⡟⠀⠀⠀⣿⣿⣿⣇⠀⠀⠀⠀⠀⢰⣿⣿⣿⠃⠀⠀⢹⣿⡄⠀⠀⠀⠀
⠀⠀⠀⠀⣿⡿⠀⠀⠀⠀⣿⣿⣿⣿⡆⠀⠀⠀⢠⣿⣿⣿⣿⠀⠀⠀⠀⢻⣿⡀⠀⠀⠀
⠀⠀⠀⣼⣿⠀⠀⠀⠀⠀⢸⣿⢿⣿⣷⠀⠀⠀⣼⣿⣿⣿⡇⠀⠀⠀⠀⠀⣿⣧⠀⠀⠀
⠀⠀⠀⣿⡿⠀⠀⠀⠀⠀⢾⣿⣿⢿⣿⣷⣶⣶⣿⡿⢿⣯⡇⠀⠀⠀⠀⠀⣿⣿⡀⠀⠀
⠀⠀⢘⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⡇⠀⠀
⠀⠀⢸⣿⡇⠀⣴⡶⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢾⣶⣄⢸⣿⡇⠀⠀
⠀⠀⠀⣿⣴⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣮⣧⠀⠀⠀
⠀⠀⣀⣽⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣥⣀⠀⠀
⠀⢘⣿⣿⠉⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠈⠙⣿⣿⠃⠀
⢠⣿⡟⠀⠀⠀⠀⠀⠀⠀$eye⠀⠀⠀⣤⠀⠀⠀$eye⠀⠀⠀⠀⠀⠀⠉⢻⣿⡆
⠀⠻⢿⢶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣶⠾⠟⠀
⠀⠀⠀⠈⠹⣿⣧⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⡿⠋⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠈⠛⠻⠿⣿⣿⣶⣶⣴⣤⣤⣤⣤⣤⣴⣤⣶⣶⡿⠿⠟⠋⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                      Stay Fluffy!''';
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        shutdownApp();
        return true;
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getFoxArt(_isEyesClosed),
              style: const TextStyle(
                color: Colors.brightRed,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            const Text('Press any key to exit'),
          ],
        ),
      ),
    );
  }
}
