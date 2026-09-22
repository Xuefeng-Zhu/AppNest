import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final tag = DateTime.now().microsecondsSinceEpoch.toString();
  for (final phase in ['write', 'read']) {
    final process = await Process.start(
      'dart',
      ['run', 'bin/restart_probe.dart'],
      workingDirectory: '$root/appnest_server',
      environment: {'APPNEST_RESTART_TAG': tag, 'APPNEST_RESTART_PHASE': phase},
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
      return;
    }
  }
  stdout.writeln(
    'PASS: two independent server processes; committed work recovered with one durable notification.',
  );
}
