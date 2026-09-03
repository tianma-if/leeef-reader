import 'dart:convert';
import 'dart:io';

enum VersionBump { patch, minor, major }

final class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    if (match == null) {
      throw FormatException(
        'Expected a stable X.Y.Z version, received: $value',
      );
    }
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(SemanticVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }

  SemanticVersion bump(VersionBump level) => switch (level) {
    VersionBump.major => SemanticVersion(major + 1, 0, 0),
    VersionBump.minor => SemanticVersion(major, minor + 1, 0),
    VersionBump.patch => SemanticVersion(major, minor, patch + 1),
  };

  @override
  String toString() => '$major.$minor.$patch';
}

final class AppVersion {
  const AppVersion(this.version, this.buildNumber);

  factory AppVersion.fromPubspec(String source) {
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(source);
    if (match == null) {
      throw const FormatException(
        'pubspec.yaml must contain version: X.Y.Z+N.',
      );
    }
    return AppVersion(
      SemanticVersion.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  final SemanticVersion version;
  final int buildNumber;
}

final class ReleaseCommit {
  const ReleaseCommit(this.sha, this.subject);

  final String sha;
  final String subject;
}

final class IgnoredCommit {
  const IgnoredCommit(this.commit, this.reason);

  final ReleaseCommit commit;
  final String reason;
}

final class CiRun {
  const CiRun({
    required this.databaseId,
    required this.status,
    required this.conclusion,
    required this.headSha,
    required this.url,
  });

  factory CiRun.fromJson(Map<String, Object?> json) => CiRun(
    databaseId: json['databaseId']! as int,
    status: json['status']! as String,
    conclusion: json['conclusion']! as String,
    headSha: json['headSha']! as String,
    url: json['url']! as String,
  );

  final int databaseId;
  final String status;
  final String conclusion;
  final String headSha;
  final String url;

  bool get isComplete => status == 'completed';
  bool get isSuccessful => isComplete && conclusion == 'success';
}

final class CommitCoverage {
  const CommitCoverage(this.changeCommits, this.ignoredCommits);

  final List<List<ReleaseCommit>> changeCommits;
  final List<IgnoredCommit> ignoredCommits;
}

final class ReleaseOptions {
  const ReleaseOptions({
    required this.bump,
    required this.issueTitle,
    required this.labels,
    required this.changesZh,
    required this.changesEn,
    required this.changeCommitRefs,
    required this.ignoredCommitRefs,
    required this.repository,
    required this.execute,
    required this.help,
    this.pendingDraft,
  });

  final VersionBump bump;
  final String issueTitle;
  final List<String> labels;
  final List<String> changesZh;
  final List<String> changesEn;
  final List<String> changeCommitRefs;
  final List<String> ignoredCommitRefs;
  final String repository;
  final bool execute;
  final bool help;
  final String? pendingDraft;
}

const releaseUsage = '''Usage:
  dart run tool/release.dart \\
    --bump minor \\
    --issue-title "Release Leeef Reader 1.1" \\
    --label enhancement \\
    --change-zh "新增面向用户的能力。" \\
    --change-en "Add a new user-facing capability." \\
    --change-commit "abcdef1"

Repeat --change-zh, --change-en and --change-commit as a group for multiple
release bullets. One bullet may cover comma-separated commit SHAs. Account for
non-user-facing commits with --ignore-commit "abcdef1:reason".

The command is a read-only dry run by default. Add --execute only after checking
the plan. Execution reuses the cross-platform CI result for the exact main
commit (or dispatches it once when absent), creates a tracking Issue, updates
the version, commits and pushes main and the tag, creates a Draft Release, and
dispatches the macOS asset workflow. It never publishes the Release.

Options:
  --bump <patch|minor|major>  Required SemVer bump
  --issue-title <title>       Required tracking Issue title
  --label <label>             Required Issue label; repeatable
  --change-zh <text>          Required Chinese release bullet; repeatable
  --change-en <text>          Required English release bullet; repeatable
  --change-commit <sha,...>   Commits covered by the paired release bullet
  --ignore-commit <sha:why>   Explicit non-user-facing commit exclusion
  --maintenance              No user-facing changes; exclude every commit with
                              --ignore-commit and use --bump patch
  --repository <owner/name>   Default: tianma-if/leeef-reader
  --execute                   Apply the plan; omission means dry run
  --pending-draft <vX.Y.Z>     Advance beyond an existing Draft matching pubspec;
                              keep the last public Release as the audit baseline
  --help                      Show this help
''';

ReleaseOptions parseReleaseOptions(List<String> arguments) {
  var repository = 'tianma-if/leeef-reader';
  VersionBump? bump;
  var issueTitle = '';
  var execute = false;
  var help = false;
  var maintenance = false;
  String? pendingDraft;
  final labels = <String>[];
  final changesZh = <String>[];
  final changesEn = <String>[];
  final changeCommitRefs = <String>[];
  final ignoredCommitRefs = <String>[];

  final valueTargets = <String, void Function(String)>{
    '--repository': (value) => repository = value,
    '--bump': (value) {
      bump = switch (value) {
        'patch' => VersionBump.patch,
        'minor' => VersionBump.minor,
        'major' => VersionBump.major,
        _ => throw ArgumentError('--bump must be patch, minor, or major.'),
      };
    },
    '--issue-title': (value) => issueTitle = value,
    '--label': labels.add,
    '--change-zh': changesZh.add,
    '--change-en': changesEn.add,
    '--change-commit': changeCommitRefs.add,
    '--ignore-commit': ignoredCommitRefs.add,
    '--pending-draft': (value) => pendingDraft = value,
  };

  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument == '--execute') {
      execute = true;
      continue;
    }
    if (argument == '--help') {
      help = true;
      continue;
    }
    if (argument == '--maintenance') {
      maintenance = true;
      continue;
    }
    final target = valueTargets[argument];
    if (target == null) {
      throw ArgumentError('Unknown option: $argument');
    }
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw ArgumentError('$argument requires a value.');
    }
    target(arguments[index += 1].trim());
  }

  if (help) {
    return ReleaseOptions(
      bump: bump ?? VersionBump.patch,
      issueTitle: issueTitle,
      labels: labels,
      changesZh: changesZh,
      changesEn: changesEn,
      changeCommitRefs: changeCommitRefs,
      ignoredCommitRefs: ignoredCommitRefs,
      repository: repository,
      execute: execute,
      help: true,
      pendingDraft: pendingDraft,
    );
  }
  final resolvedBump = bump;
  if (resolvedBump == null) throw ArgumentError('--bump is required.');
  if (!RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(repository)) {
    throw ArgumentError('--repository must use owner/name format.');
  }
  if (issueTitle.isEmpty) throw ArgumentError('--issue-title is required.');
  if (labels.isEmpty) throw ArgumentError('At least one --label is required.');
  if (maintenance &&
      (resolvedBump != VersionBump.patch ||
          changesZh.isNotEmpty ||
          changesEn.isNotEmpty ||
          changeCommitRefs.isNotEmpty ||
          ignoredCommitRefs.isEmpty)) {
    throw ArgumentError(
      '--maintenance requires --bump patch, explicit ignored commits, and no change bullets.',
    );
  }
  if (!maintenance && (changesZh.isEmpty || changesEn.isEmpty)) {
    throw ArgumentError(
      'At least one --change-zh and --change-en are required.',
    );
  }
  if (changesZh.length != changesEn.length) {
    throw ArgumentError(
      '--change-zh and --change-en must have the same count.',
    );
  }
  if (changesZh.length != changeCommitRefs.length) {
    throw ArgumentError(
      'Each bilingual change requires one --change-commit value.',
    );
  }
  return ReleaseOptions(
    bump: resolvedBump,
    issueTitle: issueTitle,
    labels: List.unmodifiable(labels),
    changesZh: List.unmodifiable(changesZh),
    changesEn: List.unmodifiable(changesEn),
    changeCommitRefs: List.unmodifiable(changeCommitRefs),
    ignoredCommitRefs: List.unmodifiable(ignoredCommitRefs),
    repository: repository,
    execute: execute,
    help: false,
    pendingDraft: pendingDraft,
  );
}

List<ReleaseCommit> parseGitLog(String output) => output
    .split('\u001e')
    .map((record) => record.trim())
    .where((record) => record.isNotEmpty)
    .map((record) {
      final separator = record.indexOf('\u001f');
      if (separator < 0) {
        throw FormatException('Malformed git log record: $record');
      }
      return ReleaseCommit(
        record.substring(0, separator),
        record.substring(separator + 1),
      );
    })
    .toList(growable: false);

List<CiRun> parseCiRuns(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List<Object?>) {
    throw const FormatException('Expected a JSON list of CI runs.');
  }
  return decoded
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw const FormatException('Expected each CI run to be an object.');
        }
        return CiRun.fromJson(item);
      })
      .toList(growable: false);
}

CiRun? selectLatestCiRun(List<CiRun> runs, String headSha) {
  for (final run in runs) {
    if (run.headSha == headSha) return run;
  }
  return null;
}

CommitCoverage auditCommitCoverage({
  required List<ReleaseCommit> commits,
  required List<String> changeCommitRefs,
  required List<String> ignoredCommitRefs,
}) {
  final covered = <String>{};
  final mappings = <List<ReleaseCommit>>[];
  for (final value in changeCommitRefs) {
    final refs = value
        .split(',')
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty);
    final mapped = refs.map((ref) => _resolveCommit(ref, commits)).toList();
    if (mapped.isEmpty) {
      throw ArgumentError('--change-commit requires at least one SHA.');
    }
    for (final commit in mapped) {
      if (!covered.add(commit.sha)) {
        throw StateError(
          'Commit ${commit.sha.substring(0, 8)} is covered more than once.',
        );
      }
    }
    mappings.add(mapped);
  }

  final ignored = <IgnoredCommit>[];
  final ignoredShas = <String>{};
  for (final value in ignoredCommitRefs) {
    final separator = value.indexOf(':');
    if (separator < 0 || value.substring(separator + 1).trim().isEmpty) {
      throw ArgumentError('--ignore-commit must use "<sha>:<reason>".');
    }
    final commit = _resolveCommit(
      value.substring(0, separator).trim(),
      commits,
    );
    if (covered.contains(commit.sha)) {
      throw StateError(
        'Commit ${commit.sha.substring(0, 8)} cannot be covered and ignored.',
      );
    }
    if (!ignoredShas.add(commit.sha)) {
      throw StateError(
        'Commit ${commit.sha.substring(0, 8)} is ignored more than once.',
      );
    }
    ignored.add(IgnoredCommit(commit, value.substring(separator + 1).trim()));
  }

  final uncovered = commits.where(
    (commit) =>
        !covered.contains(commit.sha) && !ignoredShas.contains(commit.sha),
  );
  if (uncovered.isNotEmpty) {
    throw StateError(
      [
        'Release notes do not account for every commit since the previous Release:',
        for (final commit in uncovered)
          '- ${commit.sha.substring(0, 8)} ${commit.subject}',
        'Cover each commit with --change-commit or explain it with --ignore-commit.',
      ].join('\n'),
    );
  }
  return CommitCoverage(
    List.unmodifiable(mappings),
    List.unmodifiable(ignored),
  );
}

ReleaseCommit _resolveCommit(String ref, List<ReleaseCommit> commits) {
  if (!RegExp(r'^[0-9a-fA-F]{7,40}$').hasMatch(ref)) {
    throw ArgumentError(
      'Commit reference must be a 7 to 40 character SHA: $ref',
    );
  }
  final matches = commits
      .where((commit) => commit.sha.toLowerCase().startsWith(ref.toLowerCase()))
      .toList();
  if (matches.isEmpty) {
    throw StateError('Commit $ref is outside the release range.');
  }
  if (matches.length > 1) {
    throw StateError('Commit $ref is ambiguous; use a longer SHA.');
  }
  return matches.single;
}

String updatePubspecVersion(String source, AppVersion next) {
  final pattern = RegExp(
    r'^version:\s*\d+\.\d+\.\d+\+\d+\s*$',
    multiLine: true,
  );
  if (pattern.allMatches(source).length != 1) {
    throw StateError('Expected exactly one pubspec version field.');
  }
  return source.replaceFirst(
    pattern,
    'version: ${next.version}+${next.buildNumber}',
  );
}

AppVersion planNextVersion({
  required AppVersion current,
  required AppVersion baseline,
  required VersionBump bump,
  String? pendingDraft,
}) {
  final order = current.version.compareTo(baseline.version);
  if (order < 0 || current.buildNumber < baseline.buildNumber) {
    throw StateError(
      'Current version/build must not precede the public baseline.',
    );
  }
  if (order > 0 && pendingDraft != 'v${current.version}') {
    throw StateError(
      'pubspec is ahead of the public baseline; explicitly name its existing Draft with --pending-draft v${current.version}.',
    );
  }
  if (pendingDraft != null &&
      (order <= 0 ||
          pendingDraft != 'v${current.version}' ||
          current.buildNumber <= baseline.buildNumber)) {
    throw StateError(
      'Pending Draft must match pubspec and be newer than the public baseline in both version and build number.',
    );
  }
  return AppVersion(current.version.bump(bump), current.buildNumber + 1);
}

String buildReleaseNotes({
  required List<String> changesZh,
  required List<String> changesEn,
  required String issueReference,
}) =>
    '''## 🇨🇳 中文说明 / Chinese Changelog

## 主要更新

${changesZh.isEmpty ? '- 本次为维护版本，无用户可感知的功能变化，无需调整现有设置。' : changesZh.map((change) => '- $change').join('\n')}

关联 Issue：$issueReference

## Key Changes

${changesEn.isEmpty ? '- Maintenance release with no user-visible functionality changes. No settings changes are needed.' : changesEn.map((change) => '- $change').join('\n')}

Related Issue: $issueReference
''';

String buildIssueBody({
  required String previousTag,
  required String targetTag,
  required List<String> changesZh,
  required CommitCoverage coverage,
}) {
  final mappingRows = <String>[];
  for (var index = 0; index < changesZh.length; index += 1) {
    final commits = coverage.changeCommits[index]
        .map((commit) => '`${commit.sha.substring(0, 8)}`')
        .join(', ');
    mappingRows.add('| ${_escapeTable(changesZh[index])} | $commits |');
  }
  final ignoredRows = coverage.ignoredCommits.isEmpty
      ? '- 无 / None'
      : coverage.ignoredCommits
            .map(
              (item) => '- `${item.commit.sha.substring(0, 8)}`：${item.reason}',
            )
            .join('\n');
  return '''<!-- leeef-release:$targetTag -->
## Release 跟踪

- 基线：`$previousTag`
- 目标：`$targetTag`

## 用户变化与提交映射

| 用户变化 | Commits |
| --- | --- |
${mappingRows.isEmpty ? '| 无用户可感知变化；全部提交的排除原因见下文 | — |' : mappingRows.join('\n')}

## 明确排除的提交

$ignoredRows

## 发布门禁

- [ ] 当前源码提交的跨平台 CI 通过（含 Flutter 与 MCP 测试）
- [ ] macOS Draft 资产、签名、公证与更新元数据通过
- [ ] GitHub Release 公开后资产审计通过

## 移动端交付记录

- 按用户指定渠道交付；正式上架不要求先经过测试渠道或真机回归。
- 分别记录 Google Play 与 App Store 的上传、送审和上架状态，不将上传成功等同于正式上架。
- 真机回归为建议检查，未执行时如实记录，不作为发布门禁。
''';
}

String _escapeTable(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\n', ' ');

Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  String? cwd,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: cwd,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return result;
}

Future<void> _runVisible(
  String executable,
  List<String> arguments, {
  String? cwd,
}) async {
  stdout.writeln('\n> $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, '', exitCode);
  }
}

Future<String> _output(
  String executable,
  List<String> arguments, {
  String? cwd,
}) async =>
    (await _run(executable, arguments, cwd: cwd)).stdout.toString().trim();

Future<CiRun?> _latestCiRun({
  required String repoRoot,
  required String repository,
  required String headSha,
}) async {
  final source = await _output('gh', [
    'run',
    'list',
    '--repo',
    repository,
    '--workflow',
    'ci.yml',
    '--commit',
    headSha,
    '--limit',
    '5',
    '--json',
    'databaseId,status,conclusion,headSha,url',
  ], cwd: repoRoot);
  return selectLatestCiRun(parseCiRuns(source), headSha);
}

Future<void> _ensureCrossPlatformCi({
  required String repoRoot,
  required String repository,
  required String headSha,
}) async {
  var run = await _latestCiRun(
    repoRoot: repoRoot,
    repository: repository,
    headSha: headSha,
  );
  if (run == null) {
    stdout.writeln(
      'No cross-platform CI exists for this commit; dispatching it once.',
    );
    await _runVisible('gh', [
      'workflow',
      'run',
      'ci.yml',
      '--repo',
      repository,
      '--ref',
      'main',
    ], cwd: repoRoot);
    for (var attempt = 0; attempt < 15 && run == null; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      run = await _latestCiRun(
        repoRoot: repoRoot,
        repository: repository,
        headSha: headSha,
      );
    }
    if (run == null) {
      throw StateError(
        'Dispatched cross-platform CI but could not find its run.',
      );
    }
  }

  if (!run.isComplete) {
    stdout.writeln('Waiting for existing cross-platform CI: ${run.url}');
    await _runVisible('gh', [
      'run',
      'watch',
      '${run.databaseId}',
      '--repo',
      repository,
      '--exit-status',
    ], cwd: repoRoot);
    stdout.writeln('Cross-platform CI passed and will be reused.');
    return;
  }
  if (!run.isSuccessful) {
    throw StateError(
      'Cross-platform CI concluded ${run.conclusion}: ${run.url}',
    );
  }
  stdout.writeln('Reusing successful cross-platform CI: ${run.url}');
}

Future<void> runRelease(List<String> arguments) async {
  final options = parseReleaseOptions(arguments);
  if (options.help) {
    stdout.write(releaseUsage);
    return;
  }
  final repoRoot = File.fromUri(Platform.script).parent.parent.path;
  final pubspecFile = File('$repoRoot/pubspec.yaml');
  final dirty = await _output('git', ['status', '--porcelain'], cwd: repoRoot);
  if (dirty.isNotEmpty) {
    throw StateError(
      'The working tree must be clean before planning a Release.',
    );
  }
  final branch = await _output('git', [
    'branch',
    '--show-current',
  ], cwd: repoRoot);
  if (branch != 'main') {
    throw StateError('Releases must run from main, not $branch.');
  }

  final previousTag = await _output('gh', [
    'release',
    'list',
    '--repo',
    options.repository,
    '--exclude-drafts',
    '--exclude-pre-releases',
    '--limit',
    '1',
    '--json',
    'tagName',
    '--jq',
    '.[0].tagName',
  ], cwd: repoRoot);
  if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(previousTag)) {
    throw StateError('Could not resolve the previous stable Release tag.');
  }
  // Fetch only into FETCH_HEAD so a dry run does not create or move a local Tag.
  await _run('git', [
    'fetch',
    '--no-tags',
    'origin',
    'refs/tags/$previousTag',
  ], cwd: repoRoot);

  final current = AppVersion.fromPubspec(await pubspecFile.readAsString());
  final baselineCommit = await _output('git', [
    'rev-parse',
    'FETCH_HEAD^{commit}',
  ], cwd: repoRoot);
  final baseline = AppVersion.fromPubspec(
    await _output('git', [
      'show',
      '$baselineCommit:pubspec.yaml',
    ], cwd: repoRoot),
  );
  final next = planNextVersion(
    current: current,
    baseline: baseline,
    bump: options.bump,
    pendingDraft: options.pendingDraft,
  );
  if (options.pendingDraft case final pendingDraft?) {
    final release =
        jsonDecode(
              await _output('gh', [
                'release',
                'view',
                pendingDraft,
                '--repo',
                options.repository,
                '--json',
                'tagName,isDraft',
              ], cwd: repoRoot),
            )
            as Map<String, dynamic>;
    if (release['tagName'] != pendingDraft || release['isDraft'] != true) {
      throw StateError(
        '--pending-draft must identify an existing unpublished Draft.',
      );
    }
    await _run('git', [
      'fetch',
      '--no-tags',
      'origin',
      'refs/tags/$pendingDraft',
    ], cwd: repoRoot);
    final draftCommit = await _output('git', [
      'rev-parse',
      'FETCH_HEAD^{commit}',
    ], cwd: repoRoot);
    await _run('git', [
      'merge-base',
      '--is-ancestor',
      baselineCommit,
      draftCommit,
    ], cwd: repoRoot);
    await _run('git', [
      'merge-base',
      '--is-ancestor',
      draftCommit,
      'HEAD',
    ], cwd: repoRoot);
    final tagged = AppVersion.fromPubspec(
      await _output('git', [
        'show',
        '$draftCommit:pubspec.yaml',
      ], cwd: repoRoot),
    );
    if (tagged.version.toString() != current.version.toString() ||
        tagged.buildNumber != current.buildNumber) {
      throw StateError(
        'Pending Draft tag version/build must match current pubspec.',
      );
    }
    stdout.writeln(
      'Keeping $pendingDraft unchanged; auditing from public baseline $previousTag.',
    );
  }
  final targetTag = 'v${next.version}';
  final log = await _output('git', [
    'log',
    '$baselineCommit..HEAD',
    '--format=%H%x1f%s%x1e',
  ], cwd: repoRoot);
  final commits = parseGitLog(log);
  final coverage = auditCommitCoverage(
    commits: commits,
    changeCommitRefs: options.changeCommitRefs,
    ignoredCommitRefs: options.ignoredCommitRefs,
  );
  final previewNotes = buildReleaseNotes(
    changesZh: options.changesZh,
    changesEn: options.changesEn,
    issueReference: '#<created-during-release>',
  );

  stdout.writeln('Release plan: $previousTag -> $targetTag');
  stdout.writeln('Build number: ${current.buildNumber} -> ${next.buildNumber}');
  stdout.writeln('Commits audited: ${commits.length}');
  stdout.writeln('Mode: ${options.execute ? 'EXECUTE' : 'DRY RUN'}');
  stdout.writeln('\n$previewNotes');
  if (!options.execute) {
    stdout.writeln(
      'Dry run complete. Re-run with --execute to prepare the Draft Release.',
    );
    return;
  }

  await _run('git', ['fetch', 'origin', 'main'], cwd: repoRoot);
  final head = await _output('git', ['rev-parse', 'HEAD'], cwd: repoRoot);
  final originMain = await _output('git', [
    'rev-parse',
    'origin/main',
  ], cwd: repoRoot);
  if (head != originMain) {
    throw StateError('main must exactly match origin/main.');
  }
  await _ensureCrossPlatformCi(
    repoRoot: repoRoot,
    repository: options.repository,
    headSha: head,
  );

  final issueBody = buildIssueBody(
    previousTag: previousTag,
    targetTag: targetTag,
    changesZh: options.changesZh,
    coverage: coverage,
  );
  final issueArgs = <String>[
    'issue',
    'create',
    '--repo',
    options.repository,
    '--title',
    options.issueTitle,
    '--body',
    issueBody,
    for (final label in options.labels) ...['--label', label],
  ];
  final issueUrl = await _output('gh', issueArgs, cwd: repoRoot);
  final issueNumber = RegExp(r'/(\d+)$').firstMatch(issueUrl)?.group(1);
  if (issueNumber == null) {
    throw StateError('Could not parse created Issue URL: $issueUrl');
  }

  await pubspecFile.writeAsString(
    updatePubspecVersion(await pubspecFile.readAsString(), next),
  );
  await _runVisible('git', ['add', 'pubspec.yaml'], cwd: repoRoot);
  await _runVisible('git', [
    'commit',
    '-m',
    'chore: release $targetTag [skip ci]',
  ], cwd: repoRoot);
  await _runVisible('git', [
    'tag',
    '-a',
    targetTag,
    '-m',
    'Leeef Reader $targetTag',
  ], cwd: repoRoot);
  await _runVisible('git', [
    'push',
    '--atomic',
    'origin',
    'main',
    targetTag,
  ], cwd: repoRoot);

  final notes = buildReleaseNotes(
    changesZh: options.changesZh,
    changesEn: options.changesEn,
    issueReference: '#$issueNumber',
  );
  await _runVisible('gh', [
    'release',
    'create',
    targetTag,
    '--repo',
    options.repository,
    '--verify-tag',
    '--draft',
    '--title',
    targetTag,
    '--notes',
    notes,
  ], cwd: repoRoot);
  await _runVisible('gh', [
    'workflow',
    'run',
    'macos-dmg.yml',
    '--repo',
    options.repository,
    '--ref',
    'main',
    '-f',
    'release_tag=$targetTag',
    '-f',
    'notarize=true',
  ], cwd: repoRoot);
  stdout.writeln('\nDraft $targetTag prepared. It has not been published.');
  stdout.writeln(
    'Track remaining CI, assets, store delivery, and device gates in #$issueNumber.',
  );
}

Future<void> main(List<String> arguments) async {
  try {
    await runRelease(arguments);
  } catch (error) {
    stderr.writeln('Release preparation failed: $error');
    exitCode = 1;
  }
}
