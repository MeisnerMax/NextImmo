import '../../data/repositories/inputs_repo.dart';
import 'task_generation_service.dart';

class StartupTaskService {
  const StartupTaskService({
    required InputsRepository inputsRepository,
    required TaskGenerationService taskGenerationService,
  }) : _inputsRepository = inputsRepository,
       _taskGenerationService = taskGenerationService;

  final InputsRepository _inputsRepository;
  final TaskGenerationService _taskGenerationService;

  Future<void> runIfDue() async {
    final settings = await _inputsRepository.getSettings();
    final lastRun = settings.lastTaskGenerationAt;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final shouldRun =
        lastRun == null ||
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastRun)).inHours >=
            24;
    if (!shouldRun) {
      return;
    }

    await _taskGenerationService.generate(
      now: nowMs,
      dueSoonDays: settings.taskDueSoonDays,
      enableNotifications: settings.enableTaskNotifications,
    );
    await _inputsRepository.updateSettings(
      settings.copyWith(
        lastTaskGenerationAt: nowMs,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
