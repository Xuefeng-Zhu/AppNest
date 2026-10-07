part of '../appnest_renderer.dart';

class _RecordEditor extends StatefulWidget {
  final CollectionSpec collection;
  final Map<String, dynamic>? initial;
  final int? capacity;
  final List<String> fieldIds;
  final Future<List<String>> Function() members;
  final RuntimeAdapter? adapter;
  final RuntimeItem? record;
  final Map<String, dynamic> options;
  final DateTime Function() clock;
  final ValueChanged<bool> onDirtyChanged;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<bool> Function() onCancel;
  const _RecordEditor({
    super.key,
    required this.collection,
    this.initial,
    this.capacity,
    required this.members,
    this.adapter,
    this.record,
    this.options = const {},
    required this.clock,
    required this.fieldIds,
    required this.onDirtyChanged,
    required this.onSave,
    required this.onCancel,
  });
  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  final _capacity = TextEditingController();
  List<String> _members = [];
  bool _saving = false, _uploading = false;
  int _stepIndex = 0;
  List<Map<String, dynamic>> get steps => [
    for (final step in widget.options['steps'] as List? ?? [])
      Map<String, dynamic>.from(step),
  ];
  List<FieldSpec> get visibleFields => steps.isEmpty
      ? fields
      : fields
            .where(
              (f) => (steps[_stepIndex]['fieldIds'] as List).contains(f.id),
            )
            .toList();
  Map<String, dynamic> control(FieldSpec field) =>
      [
        for (final raw in widget.options['controls'] as List? ?? [])
          Map<String, dynamic>.from(raw),
      ].where((c) => c['fieldId'] == field.id).firstOrNull ??
      {};
  String? _error;
  String _message(Object error, String fallback) =>
      widget.adapter?.errorMessage(error, fallback: fallback) ??
      (error is SpecException ? error.message : fallback);
  bool get creating => widget.initial == null;
  List<FieldSpec> get fields => widget.collection.fields
      .where(
        (field) =>
            (widget.fieldIds.isEmpty || widget.fieldIds.contains(field.id)) &&
            !widget.collection.behaviors.any(
              (behavior) =>
                  behavior.fieldId == field.id &&
                  (behavior.type == 'workflow.v1' || !creating),
            ),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _capacity.text = '${widget.capacity ?? 1}';
    _capacity.addListener(_dirty);
    for (final field in fields) {
      final value =
          widget.initial?[field.id] ??
          (field.required
              ? switch (field.type) {
                  FieldType.choice => field.choices.first,
                  FieldType.boolean => false,
                  _ => null,
                }
              : null);
      _values[field.id] = value;
      _controllers[field.id] = TextEditingController(
        text: value?.toString() ?? '',
      )..addListener(_dirty);
    }
    if (fields.any((field) => field.type == FieldType.member)) {
      widget.members().then(
        (members) {
          if (mounted) setState(() => _members = members);
        },
        onError: (Object error) {
          if (mounted)
            setState(
              () => _error =
                  'Could not load eligible members. ${_message(error, 'Try again.')}',
            );
        },
      );
    }
  }

  void _dirty() => widget.onDirtyChanged(true);

  @override
  void dispose() {
    _capacity.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(FieldSpec field) async {
    final existing =
        DateTime.tryParse('${_values[field.id]}')?.toLocal() ?? widget.clock();
    final day = await showDatePicker(
      context: context,
      initialDate: existing,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing),
    );
    if (time == null || !mounted) return;
    // Construct in the current device timezone, converting only the final instant.
    final date = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() => _values[field.id] = date.toUtc().toIso8601String());
    _dirty();
  }

  Future<void> _save() async {
    if (_saving) return;
    try {
      final data = {for (final field in fields) field.id: _normalized(field)};
      if (creating) {
        for (final behavior in widget.collection.behaviors.where(
          (b) => b.type == 'workflow.v1',
        )) {
          data[behavior.fieldId!] = widget.collection
              .field(behavior.fieldId!)
              .choices
              .first;
        }
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.onSave({
        'data': data,
        if (creating &&
            widget.collection.behaviors.any((b) => b.type == 'capacity.v1'))
          'capacity': int.parse(_capacity.text),
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Could not save. ${_message(error, 'Try again.')}';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.all(_space(context, 24)),
      child: AbsorbPointer(
        absorbing: _saving || _uploading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (steps.isNotEmpty) ...[
              Text(
                'Step ${_stepIndex + 1} of ${steps.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                steps[_stepIndex]['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_stepIndex + 1) / steps.length,
                semanticsLabel: 'Form progress',
              ),
              const SizedBox(height: 24),
            ],
            for (final field in visibleFields)
              Padding(
                key: ValueKey('editor-field-${field.id}'),
                padding: EdgeInsets.only(bottom: _space(context, 20)),
                child: _fieldControl(field),
              ),
            if (creating &&
                (_stepIndex == steps.length - 1 || steps.isEmpty) &&
                widget.collection.behaviors.any((b) => b.type == 'capacity.v1'))
              Padding(
                padding: EdgeInsets.only(bottom: _space(context, 20)),
                child: TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacity *'),
                ),
              ),
            if (_uploading)
              const LinearProgressIndicator(semanticsLabel: 'Uploading image'),
            if (_error != null)
              Padding(
                padding: EdgeInsets.only(bottom: _space(context, 20)),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_stepIndex > 0)
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _stepIndex--;
                            _error = null;
                          }),
                    child: const Text('Previous'),
                  ),
                if (steps.isNotEmpty && _stepIndex < steps.length - 1)
                  FilledButton(
                    onPressed: _saving ? null : _nextStep,
                    child: const Text('Next step'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fieldControl(FieldSpec field) {
    final config = control(field);
    final kind = config['control'];
    final hint = config['hint'] as String?;
    Widget result;
    if (field.type == FieldType.image) {
      result = _imageControl(field);
    } else if (kind == 'switch') {
      result = _switchControl(field);
    } else if (kind == 'segmented') {
      result = _segmentedControl(field);
    } else if ({'slider', 'stepper', 'rating'}.contains(kind)) {
      result = _numericControl(field, config);
    } else {
      result = switch (field.type) {
        FieldType.choice || FieldType.member => DropdownButtonFormField<String>(
          initialValue: _values[field.id] as String?,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '${field.label}${field.required ? ' *' : ''}',
          ),
          items: [
            if (!field.required)
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Not set'),
              ),
            for (final value
                in field.type == FieldType.choice ? field.choices : _members)
              DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            _values[field.id] = value;
            _dirty();
          },
        ),
        FieldType.boolean => CheckboxListTile(
          title: Text(field.label),
          tristate: !field.required,
          value: _values[field.id] as bool?,
          onChanged: (value) {
            setState(() => _values[field.id] = value);
            _dirty();
          },
        ),
        FieldType.timestamp => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${field.label}${field.required ? ' *' : ''}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickTime(field),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    _values[field.id] == null
                        ? 'Choose date and time'
                        : _displayDate(context, '${_values[field.id]}'),
                  ),
                ),
                if (!field.required && _values[field.id] != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _values[field.id] = null);
                      _dirty();
                    },
                    child: Text('Clear ${field.label.toLowerCase()}'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your device timezone',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        _ => TextField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: '${field.label}${field.required ? ' *' : ''}',
          ),
          keyboardType:
              {FieldType.integer, FieldType.number}.contains(field.type)
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : kind == 'text'
              ? TextInputType.text
              : TextInputType.multiline,
          minLines: kind == 'multiline' ? 3 : 1,
          maxLines: kind == 'text'
              ? 1
              : field.type == FieldType.text
              ? 5
              : 1,
        ),
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        result,
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  dynamic _normalized(FieldSpec field) {
    final text = _controllers[field.id]!.text;
    final value = switch (field.type) {
      FieldType.choice ||
      FieldType.boolean ||
      FieldType.member ||
      FieldType.timestamp ||
      FieldType.image => _values[field.id],
      FieldType.integer => text.isEmpty ? null : int.parse(text),
      FieldType.number => text.isEmpty ? null : double.parse(text),
      _ => text.isEmpty ? null : text,
    };
    return field.normalize(value);
  }

  void _nextStep() {
    try {
      for (final field in visibleFields) {
        _normalized(field);
      }
      setState(() {
        _stepIndex++;
        _error = null;
      });
    } catch (error) {
      setState(
        () => _error =
            'Please check this step. ${_message(error, 'Review the entered values.')}',
      );
    }
  }

  Widget _switchControl(FieldSpec field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        subtitle: Text(
          _values[field.id] == null
              ? 'Not set'
              : _values[field.id] == true
              ? 'On'
              : 'Off',
        ),
        value: _values[field.id] == true,
        onChanged: (value) {
          setState(() => _values[field.id] = value);
          _dirty();
        },
      ),
      if (!field.required && _values[field.id] != null)
        TextButton(
          onPressed: () {
            setState(() => _values[field.id] = null);
            _dirty();
          },
          child: const Text('Clear value'),
        ),
    ],
  );

  Widget _segmentedControl(FieldSpec field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${field.label}${field.required ? ' *' : ''}'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!field.required)
            ChoiceChip(
              label: const Text('Not set'),
              selected: _values[field.id] == null,
              onSelected: (_) {
                setState(() => _values[field.id] = null);
                _dirty();
              },
            ),
          for (final choice in field.choices)
            ChoiceChip(
              label: Text(choice),
              selected: _values[field.id] == choice,
              onSelected: (_) {
                setState(() => _values[field.id] = choice);
                _dirty();
              },
            ),
        ],
      ),
    ],
  );

  Widget _numericControl(FieldSpec field, Map<String, dynamic> config) {
    final min = (config['min'] as num?)?.toDouble() ?? 0;
    final max =
        (config['max'] as num?)?.toDouble() ??
        (config['control'] == 'rating' ? 5 : 100);
    final step = (config['step'] as num?)?.toDouble() ?? 1;
    final value = num.tryParse(_controllers[field.id]!.text)?.toDouble();
    void update(double next) {
      if (!next.isFinite) {
        setState(() => _error = 'This numeric value is too large.');
        return;
      }
      setState(
        () => _controllers[field.id]!.text = field.type == FieldType.integer
            ? '${next.round()}'
            : next.toString(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The text value remains authoritative even when it exceeds a display range.
        TextField(
          controller: _controllers[field.id],
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: '${field.label}${field.required ? ' *' : ''}',
            helperText: value == null
                ? 'Not set'
                : value < min || value > max
                ? 'Outside the control range; your value is preserved.'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (config['control'] == 'slider') ...[
          Slider(
            value: (value ?? min).clamp(min, max),
            min: min,
            max: max,
            label: value == null ? 'Not set' : _number(value),
            semanticFormatterCallback: (v) => _number(v),
            onChanged: (raw) {
              final index = ((raw - min) / step).round().clamp(
                0,
                ((max - min) / step).floor(),
              );
              update(min + index * step);
            },
          ),
        ] else if (config['control'] == 'rating')
          Wrap(
            spacing: 2,
            children: [
              for (var n = min == 0 ? 1 : min.toInt(); n <= max && n <= 10; n++)
                IconButton(
                  tooltip: '${field.label}: $n',
                  onPressed: () => update(n.toDouble()),
                  icon: Icon(
                    value != null && value >= n
                        ? Icons.star
                        : Icons.star_border,
                  ),
                ),
            ],
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Decrease ${field.label}',
                onPressed: value == null ? null : () => update(value - step),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(value == null ? 'Not set' : _number(value)),
              IconButton(
                tooltip: 'Increase ${field.label}',
                onPressed: () => update(value == null ? min : value + step),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        if (!field.required && value != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() => _controllers[field.id]!.clear());
              },
              child: const Text('Clear value'),
            ),
          ),
      ],
    );
  }

  Widget _imageControl(FieldSpec field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${field.label}${field.required ? ' *' : ''}'),
      const SizedBox(height: 8),
      if (_values[field.id] != null && widget.adapter != null)
        SizedBox(
          width: 320,
          child: _PrivateImage(
            adapter: widget.adapter!,
            assetId: _values[field.id] as String,
            label: field.label,
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: widget.adapter == null || _uploading
                ? null
                : () => _chooseImage(field),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _values[field.id] == null ? 'Choose image' : 'Replace image',
            ),
          ),
          if (!field.required && _values[field.id] != null)
            TextButton(
              onPressed: () {
                setState(() => _values[field.id] = null);
                _dirty();
              },
              child: const Text('Remove image'),
            ),
        ],
      ),
      Text(
        'JPEG, PNG or WebP · up to 5 MiB',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Future<void> _chooseImage(FieldSpec field) async {
    try {
      final bytes = await widget.adapter!.pickImage();
      if (bytes == null || !mounted) return;
      setState(() {
        _uploading = true;
        _error = null;
      });
      final id = await widget.adapter!.uploadImage(
        bytes,
        collectionId: widget.collection.id,
        fieldId: field.id,
        record: widget.record,
      );
      if (!mounted) return;
      setState(() {
        _values[field.id] = id;
        _uploading = false;
      });
      _dirty();
    } catch (error) {
      if (mounted)
        setState(() {
          _uploading = false;
          _error = 'Could not upload image. ${_message(error, 'Try again.')}';
        });
    }
  }
}
