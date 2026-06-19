import 'dart:io';

import 'package:build_slim/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  final runner = BuildSlimRunner();
  final exitCode = await runner.run(args);
  exit(exitCode);
}
