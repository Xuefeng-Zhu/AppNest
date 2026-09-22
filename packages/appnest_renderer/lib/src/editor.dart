part of '../appnest_renderer.dart';

class _RecordEditor extends StatefulWidget {
  final CollectionSpec collection;
  final Map<String, dynamic>? initial;
  final int? capacity;
  final List<String> fieldIds;
  final Future<List<String>> Function() members;
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
  bool _saving = false;
  String? _error;
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
            setState(() => _error = 'Could not load eligible members. $error');
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
      final data = <String, dynamic>{};
      for (final field in fields) {
        final text = _controllers[field.id]!.text;
        final value = switch (field.type) {
          FieldType.choice ||
          FieldType.boolean ||
          FieldType.member ||
          FieldType.timestamp => _values[field.id],
          FieldType.integer => text.isEmpty ? null : int.parse(text),
          FieldType.number => text.isEmpty ? null : double.parse(text),
          _ => text.isEmpty ? null : text,
        };
        data[field.id] = field.normalize(value);
      }
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
          _error = 'Could not save. $error';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final field in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: switch (field.type) {
                  FieldType.choice ||
                  FieldType.member => DropdownButtonFormField<String>(
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
                          in field.type == FieldType.choice
                              ? field.choices
                              : _members)
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
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _values[field.id] == null
                                  ? 'Choose date and time'
                                  : _displayDate(
                                      context,
                                      '${_values[field.id]}',
                                    ),
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
                        {
                          FieldType.integer,
                          FieldType.number,
                        }.contains(field.type)
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : TextInputType.multiline,
                    minLines: 1,
                    maxLines: field.type == FieldType.text ? 5 : 1,
                  ),
                },
              ),
            if (creating &&
                widget.collection.behaviors.any((b) => b.type == 'capacity.v1'))
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacity *'),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
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
}
