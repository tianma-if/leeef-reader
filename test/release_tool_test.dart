import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release.dart';

void main() {
  test('mobile testing is advisory rather than a release gate', () {
    final body = buildIssueBody(
      previousTag: 'v1.1.5',
      targetTag: 'v1.1.6',
      changesZh: ['修复阅读问题。'],
      coverage: auditCommitCoverage(
        commits: const [ReleaseCommit('abcdef1234567890', 'Fix reader')],
        changeCommitRefs: ['abcdef1'],
        ignoredCommitRefs: const [],
      ),
    );

    final gates = body.split('## 发布门禁').last.split('## 移动端交付记录').first;
    expect(gates, contains('跨平台 CI 通过'));
    expect(gates, contains('签名、公证与更新元数据通过'));
    expect(gates, isNot(contains('真机')));
    expect(gates, isNot(contains('TestFlight')));
    expect(body, contains('正式上架不要求先经过测试渠道或真机回归'));
    expect(body, contains('未执行时如实记录，不作为发布门禁'));
  });

  group('release options', () {
    test(
      'maintenance releases retain explicit coverage without fake changes',
      () {
        final options = parseReleaseOptions([
          '--bump',
          'patch',
          '--issue-title',
          'Maintenance release',
          '--label',
          'documentation',
          '--maintenance',
          '--ignore-commit',
          'abcdef1:Release tooling only',
        ]);
        expect(options.changesZh, isEmpty);
        expect(options.changesEn, isEmpty);
        expect(options.execute, isFalse);
        final coverage = auditCommitCoverage(
          commits: const [ReleaseCommit('abcdef1234567890', 'Release tooling')],
          changeCommitRefs: options.changeCommitRefs,
          ignoredCommitRefs: options.ignoredCommitRefs,
        );
        expect(coverage.ignoredCommits, hasLength(1));
        expect(
          () => auditCommitCoverage(
            commits: const [
              ReleaseCommit('abcdef1234567890', 'Release tooling'),
              ReleaseCommit('1234567890abcdef', 'Unaccounted change'),
            ],
            changeCommitRefs: options.changeCommitRefs,
            ignoredCommitRefs: options.ignoredCommitRefs,
          ),
          throwsStateError,
        );
        final notes = buildReleaseNotes(
          changesZh: options.changesZh,
          changesEn: options.changesEn,
          issueReference: '#42',
        );
        expect(notes, contains('无用户可感知的功能变化'));
        expect(notes, contains('no user-visible functionality changes'));
        expect(notes, isNot(contains('Release tooling')));
      },
    );

    test(
      'maintenance mode rejects missing reasons, feature bullets and non-patch bumps',
      () {
        for (final extra in [
          <String>[],
          ['--ignore-commit', 'abcdef1:Tooling', '--change-zh', '功能'],
          ['--ignore-commit', 'abcdef1:Tooling', '--change-en', 'Feature'],
          ['--ignore-commit', 'abcdef1:Tooling', '--change-commit', 'abcdef1'],
          ['--ignore-commit', 'abcdef1:Tooling', '--bump', 'minor'],
          ['--ignore-commit', 'abcdef1:Tooling', '--bump', 'major'],
        ]) {
          expect(
            () => parseReleaseOptions([
              '--bump',
              'patch',
              '--issue-title',
              'Maintenance release',
              '--label',
              'documentation',
              '--maintenance',
              ...extra,
            ]),
            throwsArgumentError,
          );
        }
      },
    );

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
    test('advances past an explicitly identified pending Draft', () {
      final next = planNextVersion(
        current: AppVersion(SemanticVersion.parse('1.1.4'), 11),
        baseline: AppVersion(SemanticVersion.parse('1.1.3'), 10),
        bump: VersionBump.patch,
        pendingDraft: 'v1.1.4',
      );
      expect(next.version.toString(), '1.1.5');
      expect(next.buildNumber, 12);
    });

    test('rejects unexplained, mismatched, or non-increasing versions', () {
      for (final entry in [
        ('1.1.4', 11, null),
        ('1.1.4', 11, 'v1.1.5'),
        ('1.1.4', 10, 'v1.1.4'),
        ('1.1.2', 9, null),
        ('1.1.3', 10, 'v1.1.3'),
      ]) {
        expect(
          () => planNextVersion(
            current: AppVersion(SemanticVersion.parse(entry.$1), entry.$2),
            baseline: AppVersion(SemanticVersion.parse('1.1.3'), 10),
            bump: VersionBump.patch,
            pendingDraft: entry.$3,
          ),
          throwsStateError,
        );
      }
    });

    test('pending Draft does not narrow commit coverage to its tag', () {
      expect(
        () => auditCommitCoverage(
          commits: const [
            ReleaseCommit(
              '1111111111111111',
              'Fix included in unpublished Draft',
            ),
            ReleaseCommit('2222222222222222', 'New fix after Draft'),
          ],
          changeCommitRefs: ['2222222'],
          ignoredCommitRefs: const [],
        ),
        throwsStateError,
      );
      final source = File('tool/release.dart').readAsStringSync();
      expect(source, contains(r'$baselineCommit..HEAD'));
      expect(source, contains("release['isDraft'] != true"));
      expect(
        RegExp(r"'merge-base',\s*'--is-ancestor'").hasMatch(source),
        isTrue,
      );
    });

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

  test('macOS distribution pins and verifies the pubspec version', () {
    final script = File('tool/build_macos_dmg.sh').readAsStringSync();

    expect(script, contains('--build-name="\$version"'));
    expect(script, contains('--build-number="\$build_number"'));
    expect(script, contains('Print :CFBundleShortVersionString'));
    expect(script, contains('Print :CFBundleVersion'));
    expect(script, contains('macOS bundle version mismatch'));
  });

  test('macOS release allows Sparkle installer sandbox communication', () {
    final entitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();
    final verifier = File('tool/verify_macos_bundle.sh').readAsStringSync();

    expect(
      entitlements,
      contains(
        'com.apple.security.temporary-exception.mach-lookup.global-name',
      ),
    );
    expect(entitlements, contains('dev.leeef.leeefReader-spks'));
    expect(entitlements, contains('dev.leeef.leeefReader-spki'));
    expect(verifier, contains('mach-lookup\\.global-name'));
    expect(verifier, contains('service_suffix in spks spki'));
  });
}
