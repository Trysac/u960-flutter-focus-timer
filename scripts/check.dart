// Runs every quality gate of this repository, in order, stopping at the first failure.
//
// Usage: `dart run scripts/check.dart` (the same command locally, in the factory and in CI); append gate names to run
// only those, in the standard order. Run `dart pub get --enforce-lockfile` first.
//
// Gates: format (`dart format`); lint (`dart analyze --fatal-infos` with analysis_options.yaml, every diagnostic fails,
// and no `// ignore:` comment in lib/ or test/); semgrep (Semgrep CE with the factory's own rules in .semgrep/); tests
// (package:test under package:coverage) with line coverage >= 80 % of lib/; docs: the documentation manifest plus
// `dart doc --dry-run` (the public API is documented by the lint gate's public_member_api_docs); secrets (gitleaks);
// audit (pub.dev's security advisories, the ones `dart pub get` reports, for every hosted package of pubspec.lock; any
// advisory fails) and OSV-Scanner over pubspec.lock (high severity). No shell: it runs every tool with an argument
// list, so it behaves the same on Windows and Linux. Factory-owned file: agents must not edit it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const minCoverage = 80.0;
const docsManifest = 'docs-manifest.json';
const allowMissingGitleaks = 'FABRICA_ALLOW_MISSING_GITLEAKS';
const allowOfflineAudit = 'FABRICA_ALLOW_OFFLINE_AUDIT';
// FABRICA_CI=1 also runs the tests tagged `conformance` (external tools or downloads); only the CI conformance job
// sets it, so local gates and coverage skip them.
const ciTier = 'FABRICA_CI';
const conformanceTag = 'conformance';
// The factory's own Semgrep rules; Semgrep-maintained rules are never used (license).
const semgrepRules = '.semgrep/factory-rules.yml';
const lockFile = 'pubspec.lock';
const highCvss = 7.0;
// The advisory requests: each one must answer within the timeout; a network error, a timeout, HTTP 429 or a 5xx
// status is retried with a doubling delay, at most this many attempts.
const advisoryTimeout = Duration(seconds: 30);
const advisoryAttempts = 3;
const advisoryFirstDelay = Duration(seconds: 1);
// osv-scanner's exit codes: 1 when vulnerabilities were found, 128 when no package was found.
const osvFound = 1;
const osvNoPackages = 128;
const gates = ['format', 'lint', 'semgrep', 'tests', 'docs', 'secrets', 'audit', 'osv'];
// Comments that silence the analyzer or hide code from coverage; the lint gate refuses them.
final _silencers = RegExp(r'//\s*(ignore(_for_file)?\s*:|coverage:ignore)');

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}

/// Runs the requested gates (all when [args] is empty) and returns the exit code.
Future<int> run(List<String> args) async {
  if (!File('pubspec.yaml').existsSync() || !File('scripts/check.dart').existsSync()) {
    stderr.writeln('check: run from the repository root (pubspec.yaml not found)');
    return 2;
  }
  final unknown = args.where((name) => !gates.contains(name));
  if (unknown.isNotEmpty) {
    stderr.writeln('check: unknown gate "${unknown.first}"');
    return 2;
  }
  final runners = <String, Future<String?> Function()>{
    'format': formatGate,
    'lint': lintGate,
    'semgrep': semgrepGate,
    'tests': testsGate,
    'docs': docsGate,
    'secrets': secretsGate,
    'audit': auditGate,
    'osv': osvGate,
  };
  for (final name in gates) {
    if (args.isNotEmpty && !args.contains(name)) {
      continue;
    }
    stdout.writeln('==> $name');
    final error = await runners[name]!();
    if (error != null) {
      stderr.writeln('$name: $error');
      stderr.writeln('==> $name: FAILED');
      return 1;
    }
    stdout.writeln('==> $name: ok');
  }
  stdout.writeln('==> all gates passed');
  return 0;
}

bool flag(String name) => Platform.environment[name] == '1';

/// The program's path when it is on PATH (with the Windows executable suffixes).
String? which(String program) {
  final suffixes = Platform.isWindows ? ['.exe', '.bat', '.cmd', ''] : [''];
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
    for (final suffix in suffixes) {
      final candidate = '${dir.isEmpty ? '.' : dir}${Platform.pathSeparator}$program$suffix';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
  }
  return null;
}

/// Runs a program without a shell, its output on this terminal; returns null when it succeeds, else the reason.
Future<String?> runTool(List<String> argv, [Map<String, String>? env]) async {
  try {
    final process = await Process.start(
      argv.first,
      argv.sublist(1),
      environment: env,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    return code == 0 ? null : '`${argv.join(' ')}` failed (exit $code)';
  } on ProcessException catch (e) {
    return '`${argv.join(' ')}` failed (cannot start it: ${e.message})';
  }
}

/// Runs a program without a shell and returns its exit code and stdout (stderr goes to the terminal).
Future<(int, String)> capture(List<String> argv) async {
  try {
    final result = await Process.run(argv.first, argv.sublist(1), stdoutEncoding: utf8, stderrEncoding: utf8);
    stderr.write(result.stderr);
    return (result.exitCode, result.stdout as String);
  } on ProcessException catch (e) {
    return (127, e.message);
  }
}

/// A command of the Dart SDK.
List<String> dart(List<String> args) => ['dart', ...args];

Future<String?> formatGate() async {
  final error = await runTool(dart(['format', '--output=none', '--set-exit-if-changed', '.']));
  if (error != null) {
    return '$error: run `dart format .`';
  }
  stdout.writeln('dart format: every file is formatted');
  return null;
}

/// The Dart files of [dirs], recursively, in a stable order.
List<File> dartFiles(List<String> dirs) {
  final files = <File>[];
  for (final dir in dirs.map(Directory.new).where((dir) => dir.existsSync())) {
    files.addAll(dir.listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')));
  }
  return files..sort((a, b) => a.path.compareTo(b.path));
}

String rel(String path) => path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^\./'), '');

/// The analyzer with every diagnostic fatal, after refusing comments that would silence it.
Future<String?> lintGate() async {
  final silenced = <String>[];
  for (final file in dartFiles(['lib', 'test', 'bin'])) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_silencers.hasMatch(lines[i])) {
        silenced.add('${rel(file.path)}:${i + 1}');
      }
    }
  }
  if (silenced.isNotEmpty) {
    silenced.forEach(stderr.writeln);
    return '${silenced.length} `// ignore:` or `coverage:ignore` comment(s); fix the code instead';
  }
  final error = await runTool(dart(['analyze', '--fatal-infos', '--fatal-warnings']));
  if (error != null) {
    return error;
  }
  stdout.writeln('dart analyze: no issues');
  return null;
}

/// Semgrep CE with the factory's own rules only; ERROR rules fail and nosemgrep comments are ignored. Tests,
/// scripts/ and .dart_tool/ are not scanned.
Future<String?> semgrepGate() async {
  final exe = which('semgrep');
  if (exe == null) {
    return missingScanner('semgrep');
  }
  return runTool([
    exe,
    'scan',
    '--config',
    semgrepRules,
    '--error',
    '--severity',
    'ERROR',
    '--metrics',
    'off',
    '--disable-version-check',
    '--disable-nosem',
    '--quiet',
    '--exclude=scripts',
    '--exclude=test',
    '--exclude=.dart_tool',
    '.',
  ]);
}

String buildDir() {
  final base = Platform.environment['FABRICA_BUILD_DIR'] ?? '';
  return '${base.isEmpty ? Directory.systemTemp.path : base}${Platform.pathSeparator}fabrica-dart-check-$pid';
}

/// Line coverage of an lcov report: (lines found, lines hit) per source file.
Map<String, (int, int)> lcovFiles(String text) {
  final files = <String, (int, int)>{};
  String? current;
  var found = 0;
  var hit = 0;
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('SF:')) {
      current = rel(line.substring(3));
      found = 0;
      hit = 0;
    } else if (line.startsWith('DA:')) {
      found++;
      final parts = line.substring(3).split(',');
      if (parts.length > 1 && (int.tryParse(parts[1]) ?? 0) > 0) {
        hit++;
      }
    } else if (line == 'end_of_record' && current != null) {
      files[current] = (found, hit);
      current = null;
    }
  }
  return files;
}

Future<String?> testsGate() async {
  final dir = Directory(buildDir());
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  try {
    return await _testsIn(dir);
  } finally {
    // The coverage data never outlives the gate, whether it passed, failed or threw.
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// The tests gate with its raw coverage and lcov report under [dir].
Future<String?> _testsIn(Directory dir) async {
  final raw = '${dir.path}${Platform.pathSeparator}raw';
  final lcov = '${dir.path}${Platform.pathSeparator}lcov.info';
  final args = ['test', '--coverage=$raw', '--reporter=expanded'];
  if (flag(ciTier)) {
    stdout.writeln('tests: CI tier, the conformance tests run too');
  } else {
    args.addAll(['--exclude-tags', conformanceTag]);
  }
  var error = await runTool(dart(args));
  if (error != null) {
    return error;
  }
  // No --check-ignore: `// coverage:ignore-*` comments never hide code from the threshold.
  error = await runTool(
    dart(['run', 'coverage:format_coverage', '--lcov', '--in=$raw', '--out=$lcov', '--report-on=lib']),
  );
  if (error != null) {
    return error;
  }
  final report = File(lcov);
  if (!report.existsSync()) {
    return 'format_coverage wrote no coverage report ($lcov)';
  }
  final files = lcovFiles(report.readAsStringSync());
  // Every file of lib/ with code counts, loaded or not: a file no test loads has no lines in the report.
  final unloaded = dartFiles(['lib']).map((file) => rel(file.path)).where((path) => !_covered(files, path)).toList();
  final found = files.values.fold(0, (sum, file) => sum + file.$1);
  final hit = files.values.fold(0, (sum, file) => sum + file.$2);
  if (found == 0) {
    return 'the coverage report has no lines';
  }
  final total = 100.0 * hit / found;
  stdout.writeln('Total coverage: ${total.toStringAsFixed(2)}%');
  if (unloaded.isNotEmpty) {
    for (final path in unloaded) {
      stderr.writeln('tests: no test loads $path');
    }
    return '${unloaded.length} file(s) of lib/ are not loaded by any test';
  }
  if (total < minCoverage) {
    return 'total line coverage ${total.toStringAsFixed(1)}% is below ${minCoverage.toStringAsFixed(0)}%';
  }
  stdout.writeln('tests: line coverage ${total.toStringAsFixed(1)}% (minimum ${minCoverage.toStringAsFixed(0)}%)');
  return null;
}

// A function, method, getter or constructor body (`=> ...`, `) {`, `) async {`, `get x {`) or a constructor
// initializer list (`) : super(...)`): the code a coverage report lists. A file without one (exports, plain
// declarations, constants) has no executable line.
final _body = RegExp(r'=>|\)\s*(async\*?|sync\*)?\s*\{|get\s+\w+\s*\{|\)\s*:\s*\w');

/// Whether the report lists [path], or [path] has no executable line.
bool _covered(Map<String, (int, int)> files, String path) =>
    files.keys.any((source) => source == path || source.endsWith('/$path')) ||
    !_body.hasMatch(File(path).readAsStringSync());

int countLines(String text) {
  final trimmed = text.replaceAll('\r\n', '\n').replaceFirst(RegExp(r'\n+$'), '');
  return trimmed.isEmpty ? 0 : '\n'.allMatches(trimmed).length + 1;
}

List<String> stringList(Object? value) => value is List ? value.whereType<String>().toList() : const [];

/// A glob of the docs manifest (`*` within a path segment, `[0-9]` classes) as a regular expression.
RegExp globPattern(String glob) {
  final out = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final char = glob[i];
    if (char == '*') {
      out.write('[^/]*');
    } else if (char == '[') {
      final end = glob.indexOf(']', i);
      out.write(glob.substring(i, end + 1));
      i = end;
    } else {
      out.write(RegExp.escape(char));
    }
  }
  return RegExp('${out.toString()}\$');
}

/// Every violation of docs-manifest.json; an empty list means the manifest part of the docs gate passes.
List<String> manifestErrors(Map<String, Object?> manifest) {
  final errors = <String>[];
  for (final path in stringList(manifest['required'])) {
    final file = File(path);
    if (!file.existsSync()) {
      errors.add('missing required file: $path');
    } else if (file.readAsStringSync().trim().isEmpty) {
      errors.add('required file is empty: $path');
    }
  }
  final all = Directory('.')
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => rel(file.path))
      .where((path) => !path.startsWith('.dart_tool/') && !path.startsWith('.git/'))
      .toList();
  for (final glob in stringList(manifest['required_globs'])) {
    final pattern = globPattern(glob);
    if (!all.any(pattern.hasMatch)) {
      errors.add('no file matches required pattern: $glob');
    }
  }
  final limits = manifest['max_lines'];
  if (limits is Map) {
    limits.forEach((path, max) {
      final file = File('$path');
      if (file.existsSync() && max is int) {
        final lines = countLines(file.readAsStringSync());
        if (lines > max) {
          errors.add('$path has $lines lines (max $max)');
        }
      }
    });
  }
  final references = manifest['must_reference'];
  if (references is Map) {
    references.forEach((path, needle) {
      final file = File('$path');
      if (file.existsSync() && needle is String && !file.readAsStringSync().contains(needle)) {
        errors.add('$path must reference $needle');
      }
    });
  }
  return errors;
}

Future<String?> docsGate() async {
  final file = File(docsManifest);
  if (!file.existsSync()) {
    return '$docsManifest not found';
  }
  Object? manifest;
  try {
    manifest = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    return '$docsManifest is not valid JSON: ${e.message}';
  }
  final errors = manifestErrors(manifest is Map<String, Object?> ? manifest : const {});
  for (final error in errors) {
    stderr.writeln('docs: $error');
  }
  // dartdoc builds the API documentation without writing it: broken doc comments and references fail.
  final dartdoc = await runTool(dart(['doc', '--dry-run']));
  if (dartdoc != null) {
    errors.add(dartdoc);
  }
  if (errors.isNotEmpty) {
    return '${errors.length} documentation problem(s)';
  }
  stdout.writeln('docs: every file in $docsManifest is present and the API documentation builds');
  return null;
}

Future<String?> secretsGate() async {
  final exe = which('gitleaks');
  if (exe == null) {
    if (flag(allowMissingGitleaks)) {
      stdout.writeln('gitleaks: SKIPPED (not installed)');
      return null;
    }
    return 'FAIL - gitleaks is not installed. Install it (https://github.com/gitleaks/gitleaks#installing), e.g. '
        '`winget install Gitleaks.Gitleaks`, `brew install gitleaks` or a release binary, or set '
        '$allowMissingGitleaks=1 to skip this gate locally.';
  }
  return runTool([exe, 'dir', '.', '--redact', '--verbose', '--no-banner']);
}

/// A scanner that is not installed: skipped locally, a failure in CI (FABRICA_CI=1).
String? missingScanner(String tool) {
  if (flag(ciTier)) {
    return '$tool not installed (required when $ciTier=1)';
  }
  stdout.writeln('$tool: skipped: $tool not installed');
  return null;
}

/// A locked package: its name, version and the pub server it comes from.
typedef Locked = ({String name, String version, String url});

/// The hosted packages of pubspec.lock (runtime and dev, direct and transitive).
List<Locked> lockedPackages(String text) {
  final packages = <Locked>[];
  String? name;
  var source = '';
  var version = '';
  var url = '';
  void flush() {
    if (name != null && source == 'hosted' && version.isNotEmpty) {
      packages.add((name: name, version: version, url: url));
    }
  }

  for (final line in const LineSplitter().convert(text)) {
    final package = RegExp(r'^  ([A-Za-z_][A-Za-z0-9_]*):\s*$').firstMatch(line);
    if (package != null) {
      flush();
      name = package[1];
      source = '';
      version = '';
      url = '';
      continue;
    }
    if (!line.startsWith('  ')) {
      flush();
      name = null;
      continue;
    }
    final field = RegExp(r'^\s+(source|version|url):\s*"?([^"]*)"?\s*$').firstMatch(line);
    switch (field?[1]) {
      case 'source':
        source = field![2]!;
      case 'version':
        version = field![2]!;
      case 'url':
        url = field![2]!;
    }
  }
  flush();
  return packages;
}

/// A semantic version as comparable parts: major, minor, patch, then 1 for a release or 0 for a pre-release.
List<int> versionKey(String version) {
  final core = version.split('+').first;
  final dash = core.indexOf('-');
  final numbers = (dash < 0 ? core : core.substring(0, dash)).split('.').map((part) => int.tryParse(part) ?? 0);
  return [...numbers, 0, 0, 0].take(3).toList()..add(dash < 0 ? 1 : 0);
}

int compareVersions(String a, String b) {
  final left = versionKey(a);
  final right = versionKey(b);
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return left[i].compareTo(right[i]);
    }
  }
  return 0;
}

/// Whether an OSV advisory of pub.dev affects [package] at [version]: listed, or inside an ECOSYSTEM range.
bool affects(Map<String, Object?> advisory, String package, String version) {
  for (final affected in (advisory['affected'] as List?) ?? const []) {
    if (affected is! Map || affected['package'] is! Map) {
      continue;
    }
    final info = affected['package'] as Map;
    if (info['name'] != package || info['ecosystem'] != 'Pub') {
      continue;
    }
    if (stringList(affected['versions']).contains(version)) {
      return true;
    }
    for (final range in (affected['ranges'] as List?) ?? const []) {
      if (range is! Map || range['type'] != 'ECOSYSTEM' && range['type'] != 'SEMVER') {
        continue;
      }
      var inside = false;
      for (final event in (range['events'] as List?) ?? const []) {
        if (event is! Map) {
          continue;
        }
        final introduced = event['introduced'];
        final fixed = event['fixed'];
        final last = event['last_affected'];
        if (introduced is String && (introduced == '0' || compareVersions(version, introduced) >= 0)) {
          inside = true;
        } else if (fixed is String && compareVersions(version, fixed) >= 0) {
          inside = false;
        } else if (last is String && compareVersions(version, last) > 0) {
          inside = false;
        }
      }
      if (inside) {
        return true;
      }
    }
  }
  return false;
}

/// The advisory server could not be reached (DNS, connection, TLS or timeout) after every attempt: the only
/// failure FABRICA_ALLOW_OFFLINE_AUDIT=1 may skip.
class AdvisoryUnreachable implements Exception {
  /// Creates the error with what went wrong.
  AdvisoryUnreachable(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// The advisory server answered, but not with advisories (an HTTP error status or a malformed body): the gate fails
/// even offline, because the audit could not run.
class AdvisoryError implements Exception {
  /// Creates the error with what went wrong.
  AdvisoryError(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Whether an HTTP status is worth another attempt: rate limiting and server errors.
bool retryableStatus(int status) => status == 429 || status >= 500;

/// One GET of [uri] with a response deadline: (status, body). A network failure or timeout throws
/// [AdvisoryUnreachable].
Future<(int, String)> fetch(HttpClient client, Uri uri) async {
  try {
    final request = await client.getUrl(uri).timeout(advisoryTimeout);
    final response = await request.close().timeout(advisoryTimeout);
    final body = await response.transform(utf8.decoder).join().timeout(advisoryTimeout);
    return (response.statusCode, body);
  } on TimeoutException {
    throw AdvisoryUnreachable('no answer from ${uri.host} within ${advisoryTimeout.inSeconds} s');
  } on SocketException catch (e) {
    throw AdvisoryUnreachable('cannot reach ${uri.host}: ${e.message}');
  } on HandshakeException catch (e) {
    throw AdvisoryUnreachable('TLS handshake with ${uri.host} failed: ${e.message}');
  } on HttpException catch (e) {
    throw AdvisoryUnreachable('connection to ${uri.host} failed: ${e.message}');
  }
}

/// The advisories of an advisory response body; throws [AdvisoryError] when it is not the expected JSON.
List<Map<String, Object?>> parseAdvisories(String body, String package) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw AdvisoryError('the advisory server sent malformed JSON for $package');
  }
  final list = json is Map ? json['advisories'] : null;
  if (list is! List) {
    throw AdvisoryError('the advisory server sent no advisories list for $package');
  }
  return list.whereType<Map<String, Object?>>().toList();
}

/// The security advisories of a package from its pub server (pub.dev: from the GitHub Advisory Database). A network
/// error, a timeout, HTTP 429 or a 5xx status is retried; then the last network error throws [AdvisoryUnreachable]
/// and an HTTP error status or malformed body throws [AdvisoryError]. HTTP 404 means the server keeps no advisories
/// for the package.
Future<List<Map<String, Object?>>> advisories(HttpClient client, Locked package) async {
  final base = package.url.isEmpty ? 'https://pub.dev' : package.url;
  final uri = Uri.parse('$base/api/packages/${package.name}/advisories');
  var delay = advisoryFirstDelay;
  for (var attempt = 1; ; attempt++) {
    final last = attempt >= advisoryAttempts;
    final int status;
    final String body;
    try {
      (status, body) = await fetch(client, uri);
    } on AdvisoryUnreachable {
      if (last) {
        rethrow;
      }
      await Future<void>.delayed(delay);
      delay *= 2;
      continue;
    }
    if (status == 200) {
      return parseAdvisories(body, package.name);
    }
    if (status == 404) {
      return const [];
    }
    if (!retryableStatus(status) || last) {
      throw AdvisoryError('the advisory server answered HTTP $status for ${package.name} ($uri)');
    }
    await Future<void>.delayed(delay);
    delay *= 2;
  }
}

/// Every hosted package of pubspec.lock against its server's security advisories; any advisory fails, like pip-audit
/// or npm audit. It needs the network: FABRICA_ALLOW_OFFLINE_AUDIT=1 skips the gate only when the server cannot be
/// reached; an HTTP error status or a malformed answer always fails it.
Future<String?> auditGate() async {
  final lock = File(lockFile);
  if (!lock.existsSync()) {
    return '$lockFile not found: run `dart pub get`';
  }
  final packages = lockedPackages(lock.readAsStringSync());
  final client = HttpClient()
    ..connectionTimeout = advisoryTimeout
    ..idleTimeout = advisoryTimeout;
  final findings = <String>[];
  try {
    for (final package in packages) {
      for (final advisory in await advisories(client, package)) {
        if (affects(advisory, package.name, package.version)) {
          findings.add('${package.name}@${package.version} ${advisory['id']} ${advisory['summary'] ?? ''}'.trim());
        }
      }
    }
  } on AdvisoryUnreachable catch (e) {
    if (flag(allowOfflineAudit)) {
      stdout.writeln('audit: SKIPPED (the advisory server is unreachable: $e)');
      return null;
    }
    return 'the advisory server is unreachable ($e), or set $allowOfflineAudit=1 to skip this gate offline';
  } on AdvisoryError catch (e) {
    return 'the audit could not run: $e';
  } finally {
    client.close(force: true);
  }
  if (findings.isNotEmpty) {
    for (final line in findings) {
      stderr.writeln('audit: $line');
    }
    return '${findings.length} known vulnerabilit${findings.length == 1 ? 'y' : 'ies'} in the locked packages';
  }
  stdout.writeln('audit: no known vulnerabilities in the ${packages.length} locked packages');
  return null;
}

/// The advisory groups with CVSS >= 7.0 or no score (unknown counts as high).
List<String> osvBlocking(Map<String, Object?> report) {
  final blocking = <String>[];
  for (final result in (report['results'] as List?) ?? const []) {
    for (final package in (result is Map ? result['packages'] as List? : null) ?? const []) {
      if (package is! Map) {
        continue;
      }
      final info = package['package'] is Map ? package['package'] as Map : const <String, Object?>{};
      for (final group in (package['groups'] as List?) ?? const []) {
        final severity = group is Map ? '${group['max_severity'] ?? ''}'.trim() : '';
        final score = double.tryParse(severity);
        if (score != null && score < highCvss) {
          continue;
        }
        final ids = stringList(group is Map ? group['ids'] : null).join(',');
        blocking.add('${info['name']}@${info['version']} $ids (${score == null ? 'unknown' : severity})');
      }
    }
  }
  return blocking;
}

/// OSV-Scanner over pubspec.lock (Pub is an OSV ecosystem); high or unknown severity fails.
Future<String?> osvGate() async {
  final exe = which('osv-scanner');
  if (exe == null) {
    return missingScanner('osv-scanner');
  }
  final (code, out) = await capture([exe, 'scan', 'source', '--format', 'json', '--lockfile=$lockFile']);
  switch (code) {
    case 0:
      stdout.writeln('osv-scanner: no known vulnerabilities in $lockFile');
      return null;
    case osvNoPackages:
      stdout.writeln('osv-scanner: no packages in $lockFile');
      return null;
    case osvFound:
      break;
    default:
      return 'osv-scanner failed (exit $code)';
  }
  Object? report;
  try {
    report = jsonDecode(out);
  } on FormatException {
    return 'osv-scanner: unreadable JSON report';
  }
  final blocking = osvBlocking(report is Map<String, Object?> ? report : const {});
  for (final line in blocking) {
    stderr.writeln('osv-scanner: $line');
  }
  if (blocking.isNotEmpty) {
    return '${blocking.length} advisory group(s) of high or unknown severity';
  }
  stdout.writeln('osv-scanner: only advisories below high severity (reported, not failing)');
  return null;
}
