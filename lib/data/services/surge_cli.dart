import 'dart:io';

import '../engine/download_engine.dart';

/// Write-path wrapper around the `surge` CLI subcommands.
///
/// Mutations go through the documented CLI (which talks to the same daemon),
/// avoiding reliance on undocumented HTTP POST payloads.
class SurgeCli {
  final String binary;
  final Map<String, String> env;

  const SurgeCli({required this.binary, required this.env});

  Future<CliResult> _run(List<String> args) async {
    try {
      final result = await Process.run(
        binary,
        args,
        environment: env,
        includeParentEnvironment: true,
      ).timeout(const Duration(seconds: 20));
      final stdout = '${result.stdout}'.trim();
      final stderr = '${result.stderr}'.trim();
      final ok = result.exitCode == 0;
      final message = ok
          ? stdout
          : (stderr.isNotEmpty ? stderr : (stdout.isNotEmpty ? stdout : '命令失败'));
      return CliResult(ok, message);
    } catch (e) {
      return CliResult(false, '$e');
    }
  }

  Future<CliResult> add(String url, {String? outputDir}) {
    final args = <String>['add', url];
    if (outputDir != null && outputDir.trim().isNotEmpty) {
      args
        ..add('-o')
        ..add(outputDir.trim());
    }
    return _run(args);
  }

  Future<CliResult> pause(String id) => _run(['pause', id]);

  Future<CliResult> resume(String id) => _run(['resume', id]);

  Future<CliResult> pauseAll() => _run(['pause', '--all']);

  Future<CliResult> resumeAll() => _run(['resume', '--all']);

  Future<CliResult> remove(String id, {bool purge = false}) =>
      _run(['rm', id, if (purge) '--purge']);

  Future<CliResult> clean() => _run(['rm', '--clean']);

  Future<CliResult> limitGlobal(String speed) =>
      _run(['limit', '--global', speed]);

  Future<CliResult> limitTask(String id, String speed) =>
      _run(['limit', id, speed]);
}
