// Adds one package dependency for the factory: `dart run scripts/add_dependency.dart [--dev] <package> [<spec>]`.
//
// The spec is the allowed range of the item (empty, an exact version, `==x`, `>=x` or `>=x,<y`); it is written as
// given in pub's syntax (`==x` becomes `x`, each comma part one bound, every version padded to three parts): a runtime
// dependency to `dependencies` of pubspec.yaml, a `--dev` one to `dev_dependencies`. `dart pub add` resolves the newest
// release inside the range, pins it in pubspec.lock and fetches it. When it fails, pubspec.yaml and pubspec.lock are
// restored. No shell: pub runs with an argument list. Factory-owned file: agents must not edit it.
import 'dart:io';

const pubspec = 'pubspec.yaml';
const lock = 'pubspec.lock';
const usage = 'usage: dart run scripts/add_dependency.dart [--dev] <package> [<spec>]';
// pub's package name rule: a lower-case Dart identifier.
final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');
final _bound = RegExp(r'^(>=|<=|>|<|==|=|\^)?\s*(\d+(?:\.\d+){0,2})([-+][0-9A-Za-z.+-]*)?$');

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}

/// Adds the dependency named by [args] and returns the exit code.
Future<int> run(List<String> args) async {
  var dev = false;
  final positional = <String>[];
  for (final arg in args) {
    if (arg == '--dev') {
      dev = true;
    } else if (arg == '--git') {
      stderr.writeln('add_dependency: factory repositories are not installable in Dart yet (no pub.dev release)');
      return 1;
    } else if (arg.startsWith('--')) {
      stderr.writeln('add_dependency: unknown option $arg');
      return 2;
    } else {
      positional.add(arg);
    }
  }
  if (positional.isEmpty || positional.length > 2) {
    stderr.writeln(usage);
    return 2;
  }
  final name = positional.first;
  if (!_packageName.hasMatch(name)) {
    stderr.writeln('add_dependency: $name is not a package name');
    return 2;
  }
  final constraint = parse(positional.length == 2 ? positional[1] : '');
  if (constraint == null) {
    return 2;
  }
  return add(name, constraint, dev);
}

/// The spec as a pub version constraint (`any` when empty); null after reporting an invalid one.
String? parse(String spec) {
  final parts = spec.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return 'any';
  }
  final bounds = <String>[];
  for (final part in parts) {
    final match = _bound.firstMatch(part);
    if (match == null) {
      stderr.writeln('add_dependency: invalid version requirement "$part"');
      return null;
    }
    final op = match[1] ?? '';
    final numbers = match[2]!.split('.');
    while (numbers.length < 3) {
      numbers.add('0');
    }
    final version = numbers.join('.') + (match[3] ?? '');
    bounds.add('${op == '==' || op == '=' ? '' : op}$version');
  }
  if (bounds.length > 1 && bounds.any((bound) => RegExp(r'^[\d^]').hasMatch(bound))) {
    stderr.writeln('add_dependency: an exact or caret version cannot be combined with another bound: $spec');
    return null;
  }
  return bounds.join(' ');
}

Future<int> add(String name, String constraint, bool dev) async {
  final saved = {
    for (final path in [pubspec, lock]) path: File(path).existsSync() ? File(path).readAsBytesSync() : null,
  };
  final descriptor = '${dev ? 'dev:' : ''}$name:$constraint';
  final process = await Process.start('dart', ['pub', 'add', descriptor], mode: ProcessStartMode.inheritStdio);
  if (await process.exitCode == 0) {
    return 0;
  }
  saved.forEach((path, content) {
    if (content != null) {
      File(path).writeAsBytesSync(content);
    } else if (File(path).existsSync()) {
      File(path).deleteSync();
    }
  });
  stderr.writeln('add_dependency: `dart pub add` failed; $pubspec and $lock were restored');
  return 1;
}
