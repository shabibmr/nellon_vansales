import 'dart:io';

/// Script to bump the build number (and optionally semantic version) in pubspec.yaml.
///
/// Usage:
///   dart run scripts/bump_build.dart [options]
///
/// Options:
///   --build=<number>       Set explicit build number
///   --increment=<number>   Increment build number by this amount (default: 1)
///   --version=<semver>     Set explicit semantic version (e.g. 1.2.0)
///   --patch                Bump patch version (1.0.0 -> 1.0.1)
///   --minor                Bump minor version (1.0.0 -> 1.1.0)
///   --major                Bump major version (1.0.0 -> 2.0.0)
///   --pubspec=<path>       Custom path to pubspec.yaml
///   --dry-run              Display changes without writing to file
///   --quiet                Print only the new version string (e.g. 1.0.0+7)
void main(List<String> args) {
  String? getArg(String prefix) {
    for (final arg in args) {
      if (arg.startsWith('--$prefix=')) {
        return arg.substring(prefix.length + 3);
      }
    }
    return null;
  }

  final isDryRun = args.contains('--dry-run');
  final isQuiet = args.contains('--quiet');
  final isPatch = args.contains('--patch');
  final isMinor = args.contains('--minor');
  final isMajor = args.contains('--major');

  final explicitBuildStr = getArg('build');
  final incrementStr = getArg('increment') ?? '1';
  final explicitVersion = getArg('version');
  final customPubspec = getArg('pubspec');

  final increment = int.tryParse(incrementStr) ?? 1;
  final explicitBuild = explicitBuildStr != null ? int.tryParse(explicitBuildStr) : null;

  // Resolve pubspec.yaml file
  File? pubspecFile;
  if (customPubspec != null) {
    pubspecFile = File(customPubspec);
  } else {
    final candidates = [
      File('pubspec.yaml'),
      File('../pubspec.yaml'),
      File('${Platform.script.toFilePath()}/../../pubspec.yaml'),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) {
        pubspecFile = candidate;
        break;
      }
    }
  }

  if (pubspecFile == null || !pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found.');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final versionRegex = RegExp(
    r'^(?<prefix>\s*version:\s*)(?<semver>[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z\.-]+)?)(?:\+(?<build>\d+))?(?<suffix>.*)$',
    multiLine: true,
  );

  final match = versionRegex.firstMatch(content);
  if (match == null) {
    stderr.writeln('Error: Could not find a valid "version:" line in ${pubspecFile.path}');
    exit(1);
  }

  final prefix = match.namedGroup('prefix')!;
  final currentSemver = match.namedGroup('semver')!;
  final rawBuild = match.namedGroup('build');
  final suffix = match.namedGroup('suffix') ?? '';

  final currentBuild = rawBuild != null ? int.tryParse(rawBuild) ?? 0 : 0;
  final oldFullVersion = rawBuild != null ? '$currentSemver+$currentBuild' : currentSemver;

  // Determine new semver
  var newSemver = currentSemver;
  if (explicitVersion != null && explicitVersion.isNotEmpty) {
    newSemver = explicitVersion.trim();
  } else if (isMajor || isMinor || isPatch) {
    final semverPartsRegex = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?(.*)$');
    final semverMatch = semverPartsRegex.firstMatch(currentSemver);
    if (semverMatch != null) {
      var maj = int.parse(semverMatch.group(1)!);
      var min = int.parse(semverMatch.group(2)!);
      var pat = int.parse(semverMatch.group(3) ?? '0');

      if (isMajor) {
        maj += 1;
        min = 0;
        pat = 0;
      } else if (isMinor) {
        min += 1;
        pat = 0;
      } else if (isPatch) {
        pat += 1;
      }
      newSemver = '$maj.$min.$pat';
    }
  }

  // Determine new build number
  final newBuild = explicitBuild ?? (currentBuild + increment);
  final newFullVersion = '$newSemver+$newBuild';
  final replacementLine = '$prefix$newFullVersion$suffix';

  if (isQuiet) {
    if (!isDryRun) {
      final updatedContent = content.replaceFirst(versionRegex, replacementLine);
      pubspecFile.writeAsStringSync(updatedContent);
    }
    stdout.writeln(newFullVersion);
    return;
  }

  stdout.writeln('==============================================');
  stdout.writeln('Pubspec Version & Build Bumper');
  stdout.writeln('==============================================');
  stdout.writeln('File:         ${pubspecFile.absolute.path}');
  stdout.writeln('Current:      $oldFullVersion');
  stdout.writeln('New Version:  $newFullVersion');

  if (isDryRun) {
    stdout.writeln('\n[DRY RUN] No changes were written to pubspec.yaml.');
  } else {
    final updatedContent = content.replaceFirst(versionRegex, replacementLine);
    pubspecFile.writeAsStringSync(updatedContent);
    stdout.writeln('\n[✓] Successfully updated pubspec.yaml to version: $newFullVersion');
  }
}
