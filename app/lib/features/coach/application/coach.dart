/// Everything the coach screen needs, in one import. The screen never reaches
/// into `data/` itself.
library;

export '../../../core/ai/allowance.dart'
    show AiAllowance, aiAllowanceProvider, allowanceLine;
export '../../profile/application/profile.dart' show YearMode, modeProvider;
export '../data/coach_models.dart'
    show ChatMessage, CoachAction, GuideCitation, GuideRef;
export 'coach_controller.dart';
export 'coach_routes.dart';
export 'coach_starters.dart';
