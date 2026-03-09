import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/portfolio_pack.dart';

class PortfolioPackBuilder {
  const PortfolioPackBuilder();

  PortfolioPackBuildOutput buildPack({
    required PortfolioPackPlan plan,
    required List<PortfolioPackFile> generatedFiles,
    required String appVersion,
    required int dbSchemaVersion,
    required int createdAt,
    required int assetsCount,
  }) {
    final files = List<PortfolioPackFile>.from(generatedFiles);
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    final fileEntries = <Map<String, Object?>>[];
    for (final file in files) {
      fileEntries.add(<String, Object?>{
        'path': file.relativePath,
        if (file.includeSha256)
          'sha256': sha256.convert(file.bytes).toString().toLowerCase(),
      });
    }

    final manifest = <String, Object?>{
      'created_at': createdAt,
      'app_version': appVersion,
      'db_schema_version': dbSchemaVersion,
      'portfolio_id': plan.portfolioId,
      'portfolio_name': plan.portfolioName,
      'period_range': <String, String>{
        'from_period_key': plan.fromPeriodKey,
        'to_period_key': plan.toPeriodKey,
      },
      'included_sections': plan.toIncludedSectionsJson(),
      'files': fileEntries,
      'totals': <String, Object?>{
        'assets_count': assetsCount,
        'files_count': files.length + 1,
      },
    };
    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
    files.add(
      PortfolioPackFile(
        relativePath: 'meta/manifest.json',
        bytes: utf8.encode(manifestJson),
        includeSha256: false,
      ),
    );

    return PortfolioPackBuildOutput(files: files, manifestJson: manifestJson);
  }
}
