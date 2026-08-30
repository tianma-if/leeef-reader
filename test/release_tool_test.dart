import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release.dart';

void main() {
  group('release options', () {
    test('parses paired bilingual changes and explicit execution', () {
      final options = parseReleaseOptions([
        '--bump',
        'minor',
        '--issue-title',
        'Release 1.1',
        '--label',
        'enhancement',
        '--change-zh',
        '新增阅读能力。',
        '--change-en',
        'Add a reading capability.',
        '--change-commit',
        'abcdef1,1234567',
        '--execute',
      ]);

      expect(options.bump, VersionBump.minor);
      expect(options.execute, isTrue);
      expect(options.changesZh, ['新增阅读能力。']);
      expect(options.changeCommitRefs, ['abcdef1,1234567']);
    });

    test('defaults to a read-only dry run', () {
      final options = parseReleaseOptions([
        '--bump',
        'patch',
        '--issue-title',
        'Release fix',
        '--label',
        'bug',
        '--change-zh',
        '修复问题。',
        '--change-en',
        'Fix an issue.',
        '--change-commit',
        'abcdef1',
      ]);

      expect(options.execute, isFalse);
    });

    test('requires a commit mapping for every bilingual change', () {
      expect(
        () => parseReleaseOptions([
          '--bump',
          'patch',
          '--issue-title',
          'Release fix',
          '--label',
          'bug',
          '--change-zh',
          '修复问题。',
          '--change-en',
          'Fix an issue.',
        ]),
        throwsArgumentError,
      );
    });
  });

  group('version planning', () {
    test('bumps SemVer without carrying lower components', () {
      final version = SemanticVersion.parse('1.4.9');

      expect(version.bump(VersionBump.patch).toString(), '1.4.10');
      expect(version.bump(VersionBump.minor).toString(), '1.5.0');
      expect(version.bump(VersionBump.major).toString(), '2.0.0');
    });

    test('increments the shared Flutter build number', () {
      const source = 'name: leeef_reader\nversion: 1.4.9+27\n';
      final current = AppVersion.fromPubspec(source);
      final next = AppVersion(
        current.version.bump(VersionBump.minor),
        current.buildNumber + 1,
      );

      expect(updatePubspecVersion(source, next), contains('version: 1.5.0+28'));
    });
  });

  group('commit coverage', () {
    const commits = [
      ReleaseCommit('abcdef1234567890', 'Add reader feature'),
      ReleaseCommit('1234567890abcdef', 'Improve CI'),
    ];

    test('accepts covered and explicitly ignored commits', () {
      final coverage = auditCommitCoverage(
        commits: commits,
        changeCommitRefs: ['abcdef1'],
        ignoredCommitRefs: ['1234567:CI-only change'],
      );

      expect(
        coverage.changeCommits.single.single.subject,
        'Add reader feature',
      );
      expect(coverage.ignoredCommits.single.reason, 'CI-only change');
    });

    test('rejects uncovered commits', () {
      expect(
        () => auditCommitCoverage(
          commits: commits,
          changeCommitRefs: ['abcdef1'],
          ignoredCommitRefs: const [],
        ),
        throwsStateError,
      );
    });

    test('rejects a commit that is both covered and ignored', () {
      expect(
        () => auditCommitCoverage(
          commits: commits,
          changeCommitRefs: ['abcdef1,1234567'],
          ignoredCommitRefs: ['1234567:CI-only change'],
        ),
        throwsStateError,
      );
    });
  });

  group('CI reuse', () {
    test('selects the newest run for the exact source commit', () {
      const head = 'abcdef1234567890';
      final runs = parseCiRuns('''
[
  {"databaseId": 12, "status": "completed", "conclusion": "success", "headSha": "$head", "url": "https://example.test/12"},
  {"databaseId": 11, "status": "completed", "conclusion": "failure", "headSha": "$head", "url": "https://example.test/11"}
]
''');

      final selected = selectLatestCiRun(runs, head);

      expect(selected?.databaseId, 12);
      expect(selected?.isSuccessful, isTrue);
    });

    test('does not reuse CI from a different commit', () {
      final runs = parseCiRuns('''
[
  {"databaseId": 12, "status": "completed", "conclusion": "success", "headSha": "abcdef1234567890", "url": "https://example.test/12"}
]
''');

      expect(selectLatestCiRun(runs, '1234567890abcdef'), isNull);
    });
  });

  test('release notes contain only bilingual user-facing content', () {
    final notes = buildReleaseNotes(
      changesZh: const ['新增能力。'],
      changesEn: const ['Add a capability.'],
      issueReference: '#42',
    );

    expect(notes, contains('## 主要更新'));
    expect(notes, contains('Related Issue: #42'));
    expect(notes, isNot(contains(r'\n')));
    expect(notes, isNot(contains('flutter test')));
  });

  test('execution prepares a Draft and never publishes it', () {
    final source = File('tool/release.dart').readAsStringSync();

    expect(source, contains("'--draft'"));
    expect(source, contains("'push',\n    '--atomic'"));
    expect(source, contains('chore: release \$targetTag [skip ci]'));
    expect(source, isNot(contains('--draft=false')));
    expect(source, isNot(contains('release edit')));
  });

  test('publishing audits existing macOS assets without rebuilding', () {
    final workflow = File('.github/workflows/macos-dmg.yml').readAsStringSync();

    expect(workflow, contains('audit-published-release:'));
    expect(workflow, contains("github.event_name == 'workflow_dispatch'"));
    expect(workflow, isNot(contains('- name: Test')));
    expect(workflow, contains('Restore a failed release to Draft'));
  });
}
