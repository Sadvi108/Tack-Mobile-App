import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'profile_document.dart';

/// Renders a [ProfileDocument] to a PDF a student can actually send.
///
/// One template, not a gallery. A gallery is a way of making the student
/// responsible for a decision they cannot evaluate — they have not seen the
/// inside of a Dhaka HR inbox and cannot know which template reads as serious.
///
/// Conventions here are Bangladeshi-market deliberate:
///
///   - **No photograph, no date of birth, no marital status, no religion,
///     no father's name.** Local CV templates still carry these and they are a
///     liability: they invite exactly the bias a graduate cannot afford, and
///     every international employer reads them as unprofessional.
///   - Black on white, one accent, no boxes and no icons. Applicant tracking
///     systems read text, and a CV that is 40% decoration is 40% wasted.
///   - The phone number is on it. This is the one place it belongs — the
///     public profile page must never carry it, which is enforced server-side.
class CvPdf {
  const CvPdf._();

  static const _accent = PdfColor.fromInt(0xFF7A1B34);
  static const _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const _muted = PdfColor.fromInt(0xFF5A5A5A);
  static const _rule = PdfColor.fromInt(0xFFD8D2CE);

  static Future<Uint8List> build({
    required ProfileDocument document,
    required CvLayout layout,
  }) async {
    // The app ships Inter, so the CV matches the product it came from and does
    // not fall back to a font the reader's PDF viewer chooses at random.
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final semiBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );

    final pdf = pw.Document(
      title: '${document.identity.fullName ?? 'CV'} — CV',
      author: document.identity.fullName,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(44, 44, 44, 40),
        theme: pw.ThemeData.withFont(base: regular, bold: semiBold),
        // A CV that runs to two pages is normal; one that silently truncates
        // is not. MultiPage flows, and the footer says which page you are on
        // so a printed stack can be put back together.
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            context.pagesCount > 1
                ? '${context.pageNumber} of ${context.pagesCount}'
                : '',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        build: (context) => [
          _header(document.identity, document.links),
          for (final section in layout.sections) ..._section(section, document),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _header(Identity identity, List<PortfolioLink> links) {
    final contact = [
      identity.whereTheyAre,
      identity.phone,
      for (final link in links) link.url,
    ].nonNulls.where((s) => s.isNotEmpty).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          identity.fullName ?? 'Your name',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        if (identity.headline case final headline?) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            headline,
            style: pw.TextStyle(fontSize: 11.5, color: _accent),
          ),
        ],
        if (contact.isNotEmpty) ...[
          pw.SizedBox(height: 5),
          // Wrapped rather than joined into one line: an email plus a GitHub
          // URL overflows A4 at this size, and a CV whose header runs off the
          // page is the first thing a reader notices.
          pw.Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              for (final item in contact)
                pw.Text(
                  item,
                  style: pw.TextStyle(fontSize: 9.5, color: _muted),
                ),
            ],
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Divider(color: _rule, thickness: 0.8, height: 1),
      ],
    );
  }

  /// A section, or nothing at all.
  ///
  /// An empty section still costs a heading and a rule, and a CV with
  /// "Certifications" over blank space reads as a person who ran out of things
  /// to say. Sections with no content are dropped rather than shown empty.
  static List<pw.Widget> _section(CvSection section, ProfileDocument doc) {
    final body = switch (section) {
      CvSection.experiences => [
        for (final e in doc.experiences)
          _entry(
            title: [e.title, e.company].nonNulls.join(' · '),
            trailing: _range(e.startDate, e.endDate, e.isCurrent),
            subtitle: e.location,
            body: e.description,
          ),
      ],
      CvSection.projects => [
        for (final p in doc.projects)
          _entry(
            title: p.title ?? 'Project',
            trailing: p.completedOn == null ? null : _year(p.completedOn!),
            subtitle: p.repoUrl ?? p.url,
            body: p.summary,
          ),
      ],
      CvSection.education => [
        for (final e in doc.education)
          _entry(
            title: e.institution ?? 'Institution',
            trailing: e.years,
            subtitle: e.line,
            body: e.cgpaLabel,
          ),
      ],
      CvSection.skills => [if (doc.skills.isNotEmpty) _skills(doc.skills)],
      CvSection.certifications => [
        for (final c in doc.certifications)
          _entry(
            title: c.title ?? 'Certification',
            trailing: c.issuedOn == null ? null : _year(c.issuedOn!),
            subtitle: c.issuer,
          ),
      ],
      CvSection.activities => [
        for (final a in doc.activities)
          _entry(
            title: a.title ?? 'Activity',
            subtitle: [a.role, a.organisation].nonNulls.join(' · '),
          ),
      ],
    };

    if (body.isEmpty) return const [];

    return [
      pw.SizedBox(height: 14),
      pw.Text(
        section.heading.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: _accent,
          letterSpacing: 1.1,
        ),
      ),
      pw.SizedBox(height: 6),
      ...body,
    ];
  }

  static pw.Widget _entry({
    required String title,
    String? trailing,
    String? subtitle,
    String? body,
  }) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 9),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
            ),
            if (trailing != null) ...[
              pw.SizedBox(width: 10),
              pw.Text(
                trailing,
                style: pw.TextStyle(fontSize: 9.5, color: _muted),
              ),
            ],
          ],
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          pw.Text(subtitle, style: pw.TextStyle(fontSize: 9.5, color: _muted)),
        if (body != null && body.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            body,
            style: const pw.TextStyle(
              fontSize: 10,
              color: _ink,
              lineSpacing: 1.6,
            ),
          ),
        ],
      ],
    ),
  );

  /// Skills as one flowing line, grouped by nothing.
  ///
  /// Not a grid of bars or stars: a self-rated proficiency is not evidence,
  /// and printing "React ●●●○○" invites a question in the interview that the
  /// student cannot win. The names alone say what they can do; the interview
  /// establishes how well.
  static pw.Widget _skills(List<Skill> skills) => pw.Text(
    skills.map((s) => s.name).join('  ·  '),
    style: const pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2),
  );

  static String _year(DateTime date) => '${date.year}';

  static String _range(DateTime? from, DateTime? to, bool isCurrent) {
    String month(DateTime d) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][d.month - 1];

    if (from == null && to == null) return '';
    final start = from == null ? '' : '${month(from)} ${from.year}';
    if (isCurrent) return '$start – now';
    if (to == null) return start;
    return '$start – ${month(to)} ${to.year}';
  }
}
