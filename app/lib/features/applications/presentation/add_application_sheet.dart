import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../data/application_repository.dart';

/// Adds a job and its application together.
///
/// Company names are normalised by the database, so "bKash Ltd." and
/// "bkash limited" end up on one company row rather than two.
Future<bool> showAddApplicationSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showTackSheet<bool>(
    context: context,
    title: 'Add an application',
    child: _AddApplicationForm(ref: ref),
  );
  return result ?? false;
}

class _AddApplicationForm extends StatefulWidget {
  const _AddApplicationForm({required this.ref});

  final WidgetRef ref;

  @override
  State<_AddApplicationForm> createState() => _AddApplicationFormState();
}

class _AddApplicationFormState extends State<_AddApplicationForm> {
  final _title = TextEditingController();
  final _company = TextEditingController();
  final _location = TextEditingController();
  final _url = TextEditingController();

  TackStatus _status = TackStatus.saved;
  String? _titleError;
  String? _companyError;
  bool _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _location.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _titleError = _title.text.trim().isEmpty ? 'Enter the job title.' : null;
      _companyError = _company.text.trim().isEmpty
          ? 'Enter the company name.'
          : null;
      _failure = null;
    });
    if (_titleError != null || _companyError != null) return;

    setState(() => _busy = true);
    try {
      await widget.ref
          .read(applicationRepositoryProvider)
          .create(
            title: _title.text,
            companyName: _company.text,
            location: _location.text.trim().isEmpty ? null : _location.text,
            sourceUrl: _url.text.trim().isEmpty ? null : _url.text,
            status: _status,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = Failure.from(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        TackSpace.screen,
        0,
        TackSpace.screen,
        MediaQuery.viewInsetsOf(context).bottom + TackSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TackTextField(
            label: 'Job title',
            hint: 'Junior frontend developer',
            controller: _title,
            errorText: _titleError,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'Company',
            hint: 'bKash',
            controller: _company,
            errorText: _companyError,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'Location (optional)',
            hint: 'Dhaka',
            controller: _location,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: TackSpace.stack),
          TackTextField(
            label: 'Link (optional)',
            hint: 'Where you found it',
            controller: _url,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: TackSpace.lg),
          Text('Where is it now?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final status in [TackStatus.saved, TackStatus.applied])
                TackChip(
                  status.label,
                  selected: _status == status,
                  onTap: () => setState(() => _status = status),
                ),
            ],
          ),
          if (_failure != null) ...[
            const SizedBox(height: TackSpace.md),
            Text(_failure!.message, style: TackText.fieldError),
          ],
          const SizedBox(height: TackSpace.xl),
          TackButton('Save it', loading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
