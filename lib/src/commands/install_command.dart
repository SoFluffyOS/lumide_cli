/// `lumide install` implementation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:lumide/src/app_installer.dart';
import 'package:lumide/src/constants.dart';
import 'package:lumide/src/github_release_client.dart';
import 'package:lumide/src/io_helpers.dart';
import 'package:lumide/src/release_asset_selector.dart';
import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

class InstallCommand extends Command<int> {
  InstallCommand() {
    argParser
      ..addOption(
        'repo',
        help: 'GitHub repository used for release lookup.',
        defaultsTo: kDefaultGithubRepo,
      )
      ..addOption('asset-url', help: 'Direct URL to a release asset.')
      ..addOption(
        'install-dir',
        help: 'Directory where Lumide should be installed.',
        defaultsTo: defaultLumideInstallDirectory(),
      )
      ..addFlag(
        'force',
        help: 'Replace an existing Lumide in the install directory.',
        negatable: false,
      )
      ..addFlag(
        'prompt',
        help: 'Ask for confirmation before installing.',
        negatable: false,
        hide: true,
      )
      ..addFlag(
        'silent',
        abbr: 's',
        help: 'Perform installation without the terminal UI.',
        negatable: false,
      );
  }

  @override
  String get description => 'Download and install Lumide.';

  @override
  String get name => 'install';

  @override
  Future<int> run() async {
    final installDirectory = argResults?['install-dir'] as String;
    final repo = argResults?['repo'] as String;
    final force = argResults?['force'] as bool;
    final assetUrl = argResults?['asset-url'] as String?;
    final prompt = argResults?['prompt'] as bool;
    final silent = argResults?['silent'] as bool;

    final passthroughArgs = argResults?.rest ?? const <String>[];

    if (silent) {
      await _performInstall(
        installDirectory: installDirectory,
        repo: repo,
        force: force || !prompt,
        assetUrl: assetUrl,
        onProgress: (p) =>
            stdout.write('\rInstalling... ${(p * 100).toInt()}%'),
        onStatus: (s) => stdout.writeln('\n$s'),
        askConfirmation: (_) async => true, // Auto-confirm
        passthroughArguments: passthroughArgs,
      );
      stdout.writeln('\nDone.');
      return 0;
    }

    final completer = Completer<int>();

    runApp(
      NoctermApp(
        home: _InstallTui(
          initialPrompt: prompt ? _PromptMode.confirmInstall : _PromptMode.none,
          installTask: (onProgress, onStatus, askConfirmation) =>
              _performInstall(
            installDirectory: installDirectory,
            repo: repo,
            force: force,
            assetUrl: assetUrl,
            onProgress: onProgress,
            onStatus: onStatus,
            askConfirmation: askConfirmation,
            passthroughArguments: passthroughArgs,
          ),
          onDone: (exitCode) => completer.complete(exitCode),
        ),
      ),
    );

    return completer.future;
  }

  Future<void> _performInstall({
    required String installDirectory,
    required String repo,
    required bool force,
    required String? assetUrl,
    required void Function(double) onProgress,
    required void Function(String) onStatus,
    required Future<bool> Function(_PromptMode) askConfirmation,
    required List<String> passthroughArguments,
  }) async {
    // Check if already installed
    final appPath = defaultLumideAppPath();
    if (File(appPath).existsSync() && !force) {
      final confirmed = await askConfirmation(_PromptMode.confirmUpgrade);
      if (!confirmed) {
        onStatus('Installation cancelled.');
        return;
      }
    }

    onStatus('Resolving latest release...');
    onProgress(0.02);
    final downloadUri = assetUrl == null || assetUrl.isEmpty
        ? await _resolveLatestReleaseAsset(repo, onStatus)
        : Uri.parse(assetUrl);

    onStatus('Downloading Lumide...');
    Directory? tempDir;
    try {
      // Map download 0-100% to total 5-85%
      final downloadResult = await _downloadAsset(downloadUri, (p) {
        onProgress(0.05 + (p * 0.80));
      });
      final downloadedFile = downloadResult.file;
      tempDir = downloadResult.tempDirectory;

      onStatus('Installing Lumide...');
      onProgress(0.85);
      const installer = AppInstaller();

      if (Platform.isMacOS && downloadedFile.path.endsWith('.dmg')) {
        onStatus('Mounting disk image...');
        onProgress(0.88);
        final mountPoint = await installer.attachDiskImage(downloadedFile.path);

        try {
          onStatus('Copying application...');
          onProgress(0.92);
          final appBundlePath = await installer.findAppBundle(mountPoint);
          final destination = p.join(
            installDirectory,
            p.basename(appBundlePath),
          );

          final destinationDirectory = Directory(destination);
          if (await destinationDirectory.exists()) {
            await destinationDirectory.delete(recursive: true);
          }

          await runCheckedProcess(
            'ditto',
            [appBundlePath, destination],
            failureMessage: 'Failed to copy Lumide into $installDirectory.',
          );

          onStatus('Finalizing installation...');
          onProgress(0.98);

          final resultPath = destination;
          onStatus('Installed Lumide at $resultPath');
          onProgress(1.0);

          final shouldLaunch = await askConfirmation(_PromptMode.confirmLaunch);
          if (shouldLaunch) {
            await _launchApp(resultPath, passthroughArguments);
          }
        } finally {
          await Process.run('hdiutil', ['detach', '-force', mountPoint]);
        }
      } else {
        // Archive installation (Windows/Linux)
        onStatus('Extracting archive...');
        onProgress(0.90);

        final resultPath = await installer.install(
          packagePath: downloadedFile.path,
          installDirectory: installDirectory,
          force: true,
        );

        onProgress(0.98);
        onStatus('Installed Lumide at $resultPath');
        onProgress(1.0);

        final shouldLaunch = await askConfirmation(_PromptMode.confirmLaunch);
        if (shouldLaunch) {
          await _launchApp(resultPath, passthroughArguments);
        }
      }
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Best effort cleanup
        }
      }
    }
  }

  Future<void> _launchApp(
    String appPath,
    List<String> passthroughArguments,
  ) async {
    final arguments = <String>[];

    if (Platform.isMacOS) {
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll([appPath, '--args', ...absoluteArgs]);
      } else {
        arguments.add(appPath);
      }
      await Process.start('open', arguments, mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll(absoluteArgs);
      }
      await Process.start(
        appPath,
        arguments,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
    } else {
      // Linux
      if (passthroughArguments.isNotEmpty) {
        final absoluteArgs = _resolveAbsoluteArgs(passthroughArguments);
        arguments.addAll(absoluteArgs);
      }
      await Process.start(appPath, arguments, mode: ProcessStartMode.detached);
    }
  }

  List<String> _resolveAbsoluteArgs(List<String> args) {
    return args.map((arg) {
      if (arg.startsWith('-')) return arg;
      try {
        final absolutePath = File(arg).absolute.path;
        final type = FileSystemEntity.typeSync(absolutePath);
        if (type != FileSystemEntityType.notFound) {
          return type == FileSystemEntityType.file
              ? File(absolutePath).resolveSymbolicLinksSync()
              : Directory(absolutePath).resolveSymbolicLinksSync();
        }
        return absolutePath;
      } catch (_) {
        return arg;
      }
    }).toList();
  }

  Future<Uri> _resolveLatestReleaseAsset(
    String repository,
    void Function(String) onStatus,
  ) async {
    final client = const GithubReleaseClient();
    final release = await client.fetchLatestRelease(repository: repository);
    final asset = selectInstallAsset(release.assets);
    onStatus('Using release ${release.tagName} (${asset.name})');
    return Uri.parse(asset.downloadUrl);
  }

  Future<({File file, Directory tempDirectory})> _downloadAsset(
    Uri uri,
    void Function(double) onProgress,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'lumide-cli');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw ProcessException(
          'download',
          [uri.toString()],
          'Failed to download ${uri.toString()} '
              '(HTTP ${response.statusCode}).',
          response.statusCode,
        );
      }

      final contentLength = response.contentLength;
      int downloaded = 0;

      final tempDirectory = await Directory.systemTemp.createTemp(
        'lumide_install_',
      );
      final fileName = p.basename(uri.path.isEmpty ? 'Lumide.dmg' : uri.path);
      final destination = File(p.join(tempDirectory.path, fileName));

      final sink = destination.openWrite();
      try {
        await for (final chunk in response) {
          downloaded += chunk.length;
          if (contentLength > 0) {
            onProgress(downloaded / contentLength);
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      return (file: destination, tempDirectory: tempDirectory);
    } finally {
      client.close(force: true);
    }
  }
}

class _InstallTui extends StatefulComponent {
  final _PromptMode initialPrompt;
  final Future<void> Function(
    void Function(double) onProgress,
    void Function(String) onStatus,
    Future<bool> Function(_PromptMode) askConfirmation,
  ) installTask;
  final void Function(int) onDone;

  const _InstallTui({
    required this.installTask,
    required this.onDone,
    this.initialPrompt = _PromptMode.none,
  });

  @override
  State<_InstallTui> createState() => _InstallTuiState();
}

enum _PromptMode { none, confirmInstall, confirmUpgrade, confirmLaunch }

class _InstallTuiState extends State<_InstallTui> {
  double _progress = 0.0;
  String _status = 'Initializing...';
  String? _error;

  _PromptMode _currentPrompt = _PromptMode.none;
  Completer<bool>? _promptCompleter;
  int _choiceIndex = 0;

  int _featureIndex = 0;
  Timer? _featureTimer;
  Timer? _animationTimer;
  int _tick = 0;

  bool _showConfetti = false;

  static const _features = [
    'Blazing Fast: Custom-built rope-based rendering engine.',
    'Intelligent: Full LSP support for your favorite languages.',
    'High Performance: Hardware-accelerated graphics for smooth editing.',
    'Integrated: Multi-tab terminal with full PTY support.',
    'Git Ready: Built-in diff, blame, and status indicators.',
    'Customizable: Powerful settings and keymap presets.',
  ];

  static const _bannerLarge = '''
░██         ░██     ░██ ░███     ░███ ░██████░███████   ░██████████ 
░██         ░██     ░██ ░████   ░████   ░██  ░██   ░██  ░██         
░██         ░██     ░██ ░██░██ ░██░██   ░██  ░██    ░██ ░██         
░██         ░██     ░██ ░██ ░████ ░██   ░██  ░██    ░██ ░█████████  
░██         ░██     ░██ ░██  ░██  ░██   ░██  ░██    ░██ ░██         
░██          ░██   ░██  ░██       ░██   ░██  ░██   ░██  ░██         
░██████████   ░██████   ░██       ░██ ░██████░███████   ░██████████''';

  static const _bannerSmall = '''
██     ██  ██ ██▄  ▄██ ██ ████▄  ██████ 
██     ██  ██ ██ ▀▀ ██ ██ ██  ██ ██▄▄   
██████ ▀████▀ ██    ██ ██ ████▀  ██▄▄▄▄''';

  @override
  void initState() {
    super.initState();
    _currentPrompt = component.initialPrompt;
    if (_currentPrompt == _PromptMode.none) {
      _runInstall();
    }

    _featureTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          _featureIndex = (_featureIndex + 1) % _features.length;
        });
      }
    });

    _animationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (mounted) {
        setState(() {
          _tick++;
        });
      }
    });
  }

  @override
  void dispose() {
    _featureTimer?.cancel();
    _animationTimer?.cancel();
    super.dispose();
  }

  bool _isInstalling = false;

  Future<void> _runInstall() async {
    if (_isInstalling) return;
    _isInstalling = true;

    try {
      await component.installTask(
        (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              if (p >= 1.0 && !_showConfetti) {
                _showConfetti = true;
              }
            });
          }
        },
        (s) {
          if (mounted) setState(() => _status = s);
        },
        (mode) async {
          if (mounted) setState(() => _currentPrompt = mode);
          _promptCompleter = Completer<bool>();
          final result = await _promptCompleter!.future;
          if (mounted) {
            setState(() {
              _currentPrompt = _PromptMode.none;
              _promptCompleter = null;
            });
          }
          return result;
        },
      );
      if (mounted) {
        shutdownApp();
      }
      component.onDone(0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInstalling = false;
        });
      }
    }
  }

  void _handleChoice(bool confirmed) {
    if (_promptCompleter != null) {
      _promptCompleter!.complete(confirmed);
    } else if (_currentPrompt != _PromptMode.none) {
      if (confirmed) {
        if (mounted) {
          setState(() {
            _currentPrompt = _PromptMode.none;
            _choiceIndex = 0;
          });
        }
        _runInstall();
      } else {
        shutdownApp();
        component.onDone(0);
      }
    }
  }

  Component _buildChoice(
    String label, {
    required bool isSelected,
    required Color color,
    required String shortcut,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: isSelected ? BoxDecoration(color: color) : null,
      child: Text(
        '[$shortcut] $label',
        style: TextStyle(
          color: isSelected ? Colors.black : color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Component _buildConfetti(int width, int height) {
    if (!_showConfetti) return const SizedBox.shrink();
    final random = _tick;
    final particles = ['*', '.', 'o', '+', 'x'];
    return Stack(
      children: List.generate(20, (i) {
        final x = (i * 13 + random * 3) % width;
        final y = (i * 7 + random * 2) % height;
        final color = [
          Colors.brightRed,
          Colors.brightYellow,
          Colors.brightWhite,
          Colors.brightCyan,
          Colors.brightMagenta,
        ][(i + random) % 5];
        return Positioned(
          left: x.toDouble(),
          top: y.toDouble(),
          child: Text(
            particles[(i + random) % particles.length],
            style: TextStyle(color: color),
          ),
        );
      }),
    );
  }

  @override
  Component build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        final isSmallWidth = width < 75;
        final isVerySmallWidth = width < 45;
        final isShortHeight = height < 20;

        // Breathing red effect
        final breath = (sin(_tick / 5) * 0.5 + 0.5);
        final bannerColor = breath > 0.5 ? Colors.brightRed : Colors.red;

        final banner = isSmallWidth ? _bannerSmall : _bannerLarge;

        Component content;

        if (_error != null) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(banner, style: const TextStyle(color: Colors.brightRed)),
              SizedBox(height: isShortHeight ? 1 : 2),
              Text(
                'Error during installation',
                style: const TextStyle(
                  color: Colors.brightRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 1),
              Text(_error!),
              SizedBox(height: isShortHeight ? 1 : 2),
              const Text('Press Q to exit'),
            ],
          );
        } else if (_currentPrompt != _PromptMode.none) {
          final question = switch (_currentPrompt) {
            _PromptMode.confirmInstall =>
              'Lumide is not installed. Install now?',
            _PromptMode.confirmUpgrade =>
              'Lumide is already installed. Upgrade?',
            _PromptMode.confirmLaunch => 'Success! Launch Lumide now?',
            _ => '',
          };

          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(banner, style: TextStyle(color: bannerColor)),
              SizedBox(height: isShortHeight ? 1 : 2),
              Text(
                question,
                style: const TextStyle(
                  color: Colors.brightWhite,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildChoice(
                    'Yes',
                    isSelected: _choiceIndex == 0,
                    color: Colors.brightRed,
                    shortcut: 'Y',
                  ),
                  const SizedBox(width: 4),
                  _buildChoice(
                    'No',
                    isSelected: _choiceIndex == 1,
                    color: Colors.brightBlack,
                    shortcut: 'N',
                  ),
                ],
              ),
            ],
          );
        } else {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(banner, style: TextStyle(color: bannerColor)),
              SizedBox(height: isShortHeight ? 1 : 2),
              Text(
                'Lumide Installer',
                style: const TextStyle(
                  color: Colors.brightWhite,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 1),
              Text(_status),
              const SizedBox(height: 1),
              SizedBox(
                width: isVerySmallWidth ? 20 : 40,
                child: ProgressBar(value: _progress),
              ),
              const SizedBox(height: 1),
              Text('${(_progress * 100).toInt()}%'),
              if (_progress >= 1.0) ...[
                const SizedBox(height: 1),
                const Text(
                  'Success!',
                  style: TextStyle(color: Colors.brightGreen),
                ),
              ],
            ],
          );
        }

        return Focusable(
          focused: true,
          onKeyEvent: (event) {
            if (event.logicalKey == LogicalKey.keyQ ||
                (event.logicalKey == LogicalKey.keyC &&
                    event.isControlPressed)) {
              shutdownApp();
              component.onDone(1);
              return true;
            }

            if (_currentPrompt != _PromptMode.none) {
              if (event.logicalKey == LogicalKey.keyY) {
                _handleChoice(true);
                return true;
              }
              if (event.logicalKey == LogicalKey.keyN) {
                _handleChoice(false);
                return true;
              }
              if (event.logicalKey == LogicalKey.arrowLeft ||
                  event.logicalKey == LogicalKey.arrowRight ||
                  event.logicalKey == LogicalKey.tab) {
                setState(() {
                  _choiceIndex = (_choiceIndex + 1) % 2;
                });
                return true;
              }
              if (event.logicalKey == LogicalKey.enter) {
                _handleChoice(_choiceIndex == 0);
                return true;
              }
            }
            return false;
          },
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    content,
                    // Only show tips if there's enough space
                    if (_error == null &&
                        _currentPrompt == _PromptMode.none &&
                        !isSmallWidth &&
                        !isShortHeight) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          border: BoxBorder.all(color: Colors.brightBlack),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'DID YOU KNOW?',
                              style: TextStyle(
                                color: Colors.brightYellow,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _features[_featureIndex],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Simplified footer for small screens
                    if (!isShortHeight) SizedBox(height: isSmallWidth ? 1 : 2),
                    if (width > 30 && height > 10)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isVerySmallWidth)
                            const Text(
                              'Made by ',
                              style: TextStyle(color: Colors.brightBlack),
                            ),
                          const Text(
                            'SoFluffy',
                            style: TextStyle(
                              color: Colors.brightWhite,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            ' with ',
                            style: TextStyle(color: Colors.brightBlack),
                          ),
                          const Text(
                            '❤️',
                            style: TextStyle(color: Colors.brightRed),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              _buildConfetti(width.toInt(), height.toInt()),
            ],
          ),
        );
      },
    );
  }
}
