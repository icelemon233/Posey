import 'dart:convert';

import 'package:posey/core/json.dart';

enum AiJobState {
  queued,
  generating,
  awaitingResult,
  completed,
  failed,
  cancelled,
}

enum PendingAiResult { download, save }

class AiJob {
  AiJob({
    required this.id,
    required this.targetId,
    required this.targetTitle,
    required this.sourcePath,
    required this.createdAt,
    this.state = AiJobState.queued,
    this.resultPath,
    this.message,
    this.completedAt,
    this.retryOf,
    this.sourceWorkId,
    this.targetSnapshot,
    this.requestMetadata,
    this.archivedWorkId,
    this.archiveError,
    this.pendingResult,
  });
  final String id, targetId, targetTitle;
  String sourcePath;
  final String? retryOf;
  final String? sourceWorkId;
  final Json? targetSnapshot, requestMetadata;
  String? archivedWorkId, archiveError;
  PendingAiResult? pendingResult;
  final int createdAt;
  AiJobState state;
  String? resultPath, message;
  int? completedAt;
  bool get active =>
      state == AiJobState.queued || state == AiJobState.generating;
  factory AiJob.fromJson(Json json) => AiJob(
    id: json['id'] as String,
    targetId: json['targetId'] as String? ?? '',
    targetTitle: json['targetTitle'] as String? ?? '目标姿势',
    sourcePath: json['sourcePath'] as String? ?? '',
    createdAt: integerOf(json['createdAt']),
    state: AiJobState.values.firstWhere(
      (state) => state.name == json['state'],
      orElse: () => AiJobState.failed,
    ),
    resultPath: json['resultPath'] as String?,
    message: json['message'] as String?,
    completedAt: json['completedAt'] is num
        ? integerOf(json['completedAt'])
        : null,
    retryOf: json['retryOf'] as String?,
    sourceWorkId: json['sourceWorkId'] as String?,
    targetSnapshot: json['targetSnapshot'] is Map
        ? objectOf(json['targetSnapshot'])
        : null,
    requestMetadata: json['requestMetadata'] is Map
        ? objectOf(json['requestMetadata'])
        : null,
    archivedWorkId: json['archivedWorkId'] as String?,
    archiveError: json['archiveError'] as String?,
    pendingResult: PendingAiResult.values
        .where((value) => value.name == json['pendingResult'])
        .firstOrNull,
  );
  Json toJson() => {
    'id': id,
    'targetId': targetId,
    'targetTitle': targetTitle,
    'sourcePath': sourcePath,
    'createdAt': createdAt,
    'state': state.name,
    'resultPath': resultPath,
    'message': message,
    'completedAt': completedAt,
    if (retryOf != null) 'retryOf': retryOf,
    if (sourceWorkId != null) 'sourceWorkId': sourceWorkId,
    if (targetSnapshot != null) 'targetSnapshot': targetSnapshot,
    if (requestMetadata != null) 'requestMetadata': requestMetadata,
    if (archivedWorkId != null) 'archivedWorkId': archivedWorkId,
    if (archiveError != null) 'archiveError': archiveError,
    if (pendingResult != null) 'pendingResult': pendingResult!.name,
  };
}

const maxActiveJobs = 3, maxCompletedJobs = 20;
List<AiJob> retainRecentJobs(List<AiJob> jobs) {
  final completed =
      jobs.where((job) => job.state == AiJobState.completed).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final retained = completed
      .take(maxCompletedJobs)
      .map((job) => job.id)
      .toSet();
  return jobs
      .where(
        (job) => job.state != AiJobState.completed || retained.contains(job.id),
      )
      .toList();
}

String encodeJobs(List<AiJob> jobs) =>
    jsonEncode(jobs.map((job) => job.toJson()).toList());
