import '../../../core/ai/allowance.dart';
import 'toolkit_status.dart';
import 'toolkit_tools.dart';

// Every word the hub shows, as pure functions of the tool, the year and what
// has loaded. Kept apart from the widgets so the copy rules can be tested over
// every combination: explore and discover never mention deadlines or applying,
// sentence case throughout, and the AI allowance never as a number of a total.

const toolkitTitle = 'Your toolkit';

const documentsErrorTitle = 'Your documents did not load';
const documentsErrorBody = 'Check your connection and try again.';
const allowanceLabel = 'AI ACTIONS TODAY';

String toolkitSubtitle(YearMode mode) => switch (mode) {
  YearMode.discover => 'Ask questions and see what real jobs involve. No rush.',
  YearMode.explore =>
    'Try these whenever you are curious. None of them is a test.',
  YearMode.build =>
    'Learn what roles ask for, and practise while it is low stakes.',
  YearMode.prove => 'Show what you can do, and check it reads that way.',
  YearMode.launch ||
  YearMode.graduate => 'Everything you need before an interview, in one place.',
};

String sectionTitle(ToolkitSection section, YearMode mode) => switch (section) {
  ToolkitSection.practise => 'Practise',
  ToolkitSection.check => 'Check',
  ToolkitSection.store =>
    mode == YearMode.discover ? 'Your documents' : 'Your CV and documents',
  ToolkitSection.ask => 'Ask',
};

/// Tools that never spend an AI action, marked with a `Free` pill.
bool isFree(ToolkitTool tool) =>
    tool == ToolkitTool.practiseAgain || tool == ToolkitTool.cvCheck;

String toolTitle(ToolkitTool tool, YearMode mode, ToolkitStatus status) =>
    switch (tool) {
      ToolkitTool.interview => switch (mode) {
        YearMode.discover || YearMode.explore => 'Try a practice interview',
        YearMode.build || YearMode.prove => 'Practise an interview',
        YearMode.launch || YearMode.graduate => 'Practise for interviews',
      },
      ToolkitTool.practiseAgain => 'Practise again',
      ToolkitTool.analyser => switch (mode) {
        YearMode.discover || YearMode.explore => 'See what a real job asks for',
        YearMode.build => 'Learn what a role asks for',
        YearMode.prove => 'Check how close you are to a role',
        YearMode.launch || YearMode.graduate => 'Check a job description',
      },
      ToolkitTool.cvCheck => 'Check your CV',
      ToolkitTool.cvBuilder =>
        (status.cvCount ?? 0) > 0
            ? 'Build another CV in Tack'
            : switch (mode) {
                YearMode.discover || YearMode.explore => 'Start your CV',
                YearMode.build => 'Build your first CV',
                YearMode.prove ||
                YearMode.launch ||
                YearMode.graduate => 'Make your CV',
              },
      ToolkitTool.documents => 'Your documents',
      ToolkitTool.coach => 'Ask your coach',
    };

String toolBody(ToolkitTool tool, YearMode mode, ToolkitStatus status) =>
    switch (tool) {
      ToolkitTool.interview => switch (mode) {
        YearMode.discover || YearMode.explore =>
          'One question at a time, at your own pace. Checking your answer is '
              'free.',
        YearMode.build || YearMode.prove =>
          'Questions for the role you want. Checking your answer is free.',
        YearMode.launch || YearMode.graduate =>
          'Questions for your role or for a company. Checking your answer is '
              'free.',
      },
      ToolkitTool.practiseAgain => switch (status.dueCount ?? 0) {
        1 => 'One answer is ready to try again.',
        final n => '$n answers are ready to try again.',
      },
      ToolkitTool.analyser => switch (mode) {
        YearMode.discover || YearMode.explore =>
          'Paste in any job post. Tack picks out the skills it asks for. Uses '
              'one AI action.',
        YearMode.build =>
          'Paste in a job post. See which skills you have and which to learn '
              'next. Uses one AI action.',
        YearMode.prove =>
          'Paste in an internship or job post. See what you match and what is '
              'missing. Uses one AI action.',
        YearMode.launch || YearMode.graduate =>
          'Paste one in before you apply. See what you already match. Uses one '
              'AI action.',
      },
      ToolkitTool.cvCheck => 'Useful changes, found by rules rather than AI.',
      ToolkitTool.cvBuilder =>
        'Made from your profile. You choose what goes on it.',
      ToolkitTool.documents => _documentsBody(mode, status),
      ToolkitTool.coach => switch (mode) {
        YearMode.discover => 'Questions about subjects, courses and careers.',
        YearMode.explore => 'Ask anything about careers and what to try first.',
        YearMode.build => 'Ask what to learn next, or how to start a project.',
        YearMode.prove =>
          'Ask about internships, portfolios and meeting people.',
        YearMode.launch ||
        YearMode.graduate => 'Ask about interviews, offers and your next step.',
      },
    };

String _documentsBody(YearMode mode, ToolkitStatus status) {
  final files = status.documentCount ?? 0;
  final hasCv = (status.cvCount ?? 0) > 0;
  final atSchool = mode == YearMode.discover;
  if (files == 0) {
    return atSchool
        ? 'Keep certificates and results safe. Only you can see them.'
        : 'Add your CV, certificates and transcripts. Only you can see them.';
  }
  final count = files == 1 ? 'One file' : '$files files';
  if (!hasCv && !atSchool) return '$count saved. Add your CV here too.';
  return '$count, kept private${hasCv ? ', including your CV' : ''}.';
}

/// What is left today and what that means. Never the limit (R14).
String allowanceNote(AiAllowance allowance) =>
    '${allowanceLine(allowance)}. Tools marked free never use one. More arrive '
    'at midnight.';
