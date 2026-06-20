part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member

const Map<String, String> _kEngineTypeLabels = {
    'gasoline': 'Gasoline',
    'diesel': 'Diesel',
    'hybrid': 'Hybrid',
    'electric': 'Electric',
  };

const Map<String, String> _kDriveLabels = {
    'fwd': 'FWD',
    'rwd': 'RWD',
    'awd': 'AWD',
    '4wd': '4WD',
  };

const Map<String, String> _kBodyLabels = {
    'sedan': 'Sedan',
    'suv': 'SUV',
    'hatchback': 'Hatchback',
    'coupe': 'Coupe',
    'pickup': 'Pickup',
    'van': 'Van',
    'convertible': 'Convertible',
    'wagon': 'Wagon',
  };

extension SellPageFields on _SellPageState {
  static const Map<String, String> _kEngineTypeLabels = {
    'gasoline': 'Gasoline',
    'diesel': 'Diesel',
    'hybrid': 'Hybrid',
    'electric': 'Electric',
  };

  static const Map<String, String> _kDriveLabels = {
    'fwd': 'FWD',
    'rwd': 'RWD',
    'awd': 'AWD',
    '4wd': '4WD',
  };

  static const Map<String, String> _kBodyLabels = {
    'sedan': 'Sedan',
    'suv': 'SUV',
    'hatchback': 'Hatchback',
    'coupe': 'Coupe',
    'pickup': 'Pickup',
    'van': 'Van',
    'convertible': 'Convertible',
    'wagon': 'Wagon',
  };

  String _coerceInList(String value, List<String> allowed) {
    if (allowed.contains(value)) return value;
    return allowed.first;
  }

  double? _parsedEngineLiters() {
    final v = OnlineSpecVariant.parseLeadingEngineLiters(_engineSizeCtl.text);
    if (v == null) return null;
    return double.parse(v.toStringAsFixed(1));
  }

  String _coerceEngineDisplayPick(List<String> opts) {
    final t = _engineSizeCtl.text.trim();
    if (t.isNotEmpty && opts.contains(t)) return t;
    final p = OnlineSpecVariant.parseLeadingEngineLiters(t);
    if (p != null) {
      for (final o in opts) {
        final oL = OnlineSpecVariant.parseLeadingEngineLiters(o);
        if (oL != null && (oL - p).abs() < 0.06) return o;
      }
    }
    return opts.first;
  }

  List<String>? _engineFuelConstrainedOptions() {
    final eng = _engineTypeOptions;
    final fuel = _fuelTypeOptions;
    if ((eng == null || eng.isEmpty) && (fuel == null || fuel.isEmpty)) {
      return null;
    }
    if (eng != null && eng.isNotEmpty && fuel != null && fuel.isNotEmpty) {
      final out = <String>[];
      final seen = <String>{};
      for (final x in [...eng, ...fuel]) {
        if (seen.add(x)) out.add(x);
      }
      return out;
    }
    if (eng != null && eng.isNotEmpty) return List<String>.from(eng);
    if (fuel != null && fuel.isNotEmpty) return List<String>.from(fuel);
    return null;
  }

  String? _labeledMultiHint(List<String> keys, Map<String, String> labels) {
    if (keys.length < 2) return null;
    return keys.map((k) => labels[k] ?? k).join(' · ');
  }

  void _applyOnlineVariantToForm(OnlineSpecVariant v) {
    if (v.engineSizeLiters != null) {
      _engineSizeCtl.text =
          '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
    }
    if (v.cylinderCount != null) {
      _cylinderCtl.text = '${v.cylinderCount}';
    }
    if (v.fuelEconomy != null) {
      _fuelEconomyCtl.text = v.fuelEconomy!;
    }
    if (v.seating != null) {
      _seatingCtl.text = '${v.seating}';
    }
    if (v.transmission != null) _transmission = v.transmission!;
    if (v.drivetrain != null) _driveType = v.drivetrain!;
    if (v.bodyType != null) _bodyType = v.bodyType!;
    if (v.engineType != null) _engineType = v.engineType!;
    if (v.fuelType != null) _fuelType = v.fuelType!;
  }

  /// After user changes one spec, align other fields to the matching catalog variant (if any).
  void _syncCorrelatedFromOnlineVariants(
    Set<String> anchors, {
    double? engineLiters,
    int? cylinders,
    String? transmission,
    String? drivetrain,
    String? bodyType,
    String? engineType,
    String? fuelType,
    String? fuelEconomy,
    int? seating,
  }) {
    final vs = _onlineSpecVariants;
    if (vs == null || vs.isEmpty) return;
    final fe =
        fuelEconomy ??
        () {
          final t = _fuelEconomyCtl.text.trim();
          return t.isEmpty ? null : t;
        }();
    final m = OnlineSpecVariant.matchBestAnchored(
      vs,
      anchors,
      engineLiters: engineLiters ?? _parsedEngineLiters(),
      cylinders: cylinders ?? int.tryParse(_cylinderCtl.text.trim()),
      transmission: transmission ?? _transmission,
      drivetrain: drivetrain ?? _driveType,
      bodyType: bodyType ?? _bodyType,
      engineType: engineType ?? _engineType,
      fuelType: fuelType ?? _fuelType,
      fuelEconomy: fe,
      seating: seating ?? int.tryParse(_seatingCtl.text.trim()),
      currentTransmission: _transmission,
      currentDrivetrain: _driveType,
      currentSeating: int.tryParse(_seatingCtl.text.trim()),
    );
    if (m != null) {
      _applyOnlineVariantToForm(m);
      _specDropdownKey++;
    }
  }

  /// Keeps controllers / enum strings inside catalog option sets so submit matches the UI.
  void _syncConstrainedSelectionsAfterCatalogApply() {
    if (_transmissionOptions != null && _transmissionOptions!.isNotEmpty) {
      _transmission = _coerceInList(_transmission, _transmissionOptions!);
    }
    if (_drivetrainOptions != null && _drivetrainOptions!.isNotEmpty) {
      _driveType = _coerceInList(_driveType, _drivetrainOptions!);
    }
    if (_bodyTypeOptions != null && _bodyTypeOptions!.isNotEmpty) {
      _bodyType = _coerceInList(_bodyType, _bodyTypeOptions!);
    }
    final engOpts = _engineFuelConstrainedOptions();
    if (engOpts != null) {
      _engineType = _coerceInList(_engineType, engOpts);
      _fuelType = _coerceInList(_fuelType, engOpts);
    }
    if (_engineSizeDisplayOptions != null &&
        _engineSizeDisplayOptions!.isNotEmpty) {
      final opts = _engineSizeDisplayOptions!;
      final t = _engineSizeCtl.text.trim();
      final exact = t.isNotEmpty && opts.contains(t);
      final p = OnlineSpecVariant.parseLeadingEngineLiters(t);
      final fuzzy =
          p != null &&
          opts.any((o) {
            final oL = OnlineSpecVariant.parseLeadingEngineLiters(o);
            return oL != null && (oL - p).abs() < 0.06;
          });
      if (!exact && !fuzzy) {
        _engineSizeCtl.text = opts.first;
      }
    }
    if (_cylinderOptions != null && _cylinderOptions!.isNotEmpty) {
      final c = int.tryParse(_cylinderCtl.text.trim());
      if (c == null || !_cylinderOptions!.contains(c)) {
        _cylinderCtl.text = '${_cylinderOptions!.first}';
      }
    }
    if (_seatingOptions != null && _seatingOptions!.isNotEmpty) {
      final c = int.tryParse(_seatingCtl.text.trim());
      if (c == null || !_seatingOptions!.contains(c)) {
        _seatingCtl.text = '${_seatingOptions!.first}';
      }
    }
    if (_fuelEconomyOptions != null && _fuelEconomyOptions!.isNotEmpty) {
      final t = _fuelEconomyCtl.text.trim();
      if (!_fuelEconomyOptions!.contains(t)) {
        _fuelEconomyCtl.text = _fuelEconomyOptions!.first;
      }
    }
  }

  Widget _engineTypeField(AppLocalizations? loc) {
    final constrained = _engineFuelConstrainedOptions();
    final value = constrained != null
        ? _coerceInList(_engineType, constrained)
        : _engineType;
    final items = constrained != null
        ? constrained
              .map(
                (k) => DropdownMenuItem<String>(
                  value: k,
                  child: Text(_kEngineTypeLabels[k] ?? k),
                ),
              )
              .toList()
        : const [
            DropdownMenuItem(value: 'gasoline', child: Text('Gasoline')),
            DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
            DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
            DropdownMenuItem(value: 'electric', child: Text('Electric')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'eng_$_specDropdownKey$value${constrained?.join() ?? 'full'}',
      ),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.engineTypeLabel ?? 'Engine type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kEngineTypeLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          final nv = v ?? _engineType;
          _engineType = nv;
          _fuelType = nv;
          _syncCorrelatedFromOnlineVariants(
            {'engt', 'fuel'},
            engineType: nv,
            fuelType: nv,
          );
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _transmissionField(AppLocalizations? loc) {
    final constrained =
        _transmissionOptions != null && _transmissionOptions!.isNotEmpty
        ? _transmissionOptions!
        : null;
    final value = constrained != null
        ? _coerceInList(_transmission, constrained)
        : _transmission;
    final items = constrained != null
        ? constrained
              .map(
                (k) => DropdownMenuItem<String>(
                  value: k,
                  child: Text(k == 'automatic' ? 'Automatic' : 'Manual'),
                ),
              )
              .toList()
        : const [
            DropdownMenuItem(value: 'automatic', child: Text('Automatic')),
            DropdownMenuItem(value: 'manual', child: Text('Manual')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'tr_$_specDropdownKey$value${constrained?.join() ?? 'full'}',
      ),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.transmissionLabel ?? 'Transmission',
        helperText: constrained != null && constrained.length >= 2
            ? constrained
                  .map((k) => k == 'automatic' ? 'Automatic' : 'Manual')
                  .join(' · ')
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _transmission = v ?? _transmission;
          _syncCorrelatedFromOnlineVariants({
            'tr',
          }, transmission: _transmission);
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _driveTypeField(AppLocalizations? loc) {
    final constrained =
        _drivetrainOptions != null && _drivetrainOptions!.isNotEmpty
        ? _drivetrainOptions!
        : null;
    final value = constrained != null
        ? _coerceInList(_driveType, constrained)
        : _driveType;
    final items = constrained != null
        ? constrained
              .map(
                (k) => DropdownMenuItem<String>(
                  value: k,
                  child: Text(_kDriveLabels[k] ?? k.toUpperCase()),
                ),
              )
              .toList()
        : const [
            DropdownMenuItem(value: 'fwd', child: Text('FWD')),
            DropdownMenuItem(value: 'rwd', child: Text('RWD')),
            DropdownMenuItem(value: 'awd', child: Text('AWD')),
            DropdownMenuItem(value: '4wd', child: Text('4WD')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'drv_$_specDropdownKey$value${constrained?.join() ?? 'full'}',
      ),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.driveType ?? 'Drive type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kDriveLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _driveType = v ?? _driveType;
          _syncCorrelatedFromOnlineVariants({'drv'}, drivetrain: _driveType);
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _bodyTypeField(AppLocalizations? loc) {
    final constrained = _bodyTypeOptions != null && _bodyTypeOptions!.isNotEmpty
        ? _bodyTypeOptions!
        : null;
    final value = constrained != null
        ? _coerceInList(_bodyType, constrained)
        : _bodyType;
    final items = constrained != null
        ? constrained
              .map(
                (k) => DropdownMenuItem<String>(
                  value: k,
                  child: Text(_kBodyLabels[k] ?? k),
                ),
              )
              .toList()
        : const [
            DropdownMenuItem(value: 'sedan', child: Text('Sedan')),
            DropdownMenuItem(value: 'suv', child: Text('SUV')),
            DropdownMenuItem(value: 'hatchback', child: Text('Hatchback')),
            DropdownMenuItem(value: 'coupe', child: Text('Coupe')),
            DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
            DropdownMenuItem(value: 'van', child: Text('Van')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>(
        'body_$_specDropdownKey$value${constrained?.join() ?? 'full'}',
      ),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.bodyTypeLabel ?? 'Body type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kBodyLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _bodyType = v ?? _bodyType;
          _syncCorrelatedFromOnlineVariants({'body'}, bodyType: _bodyType);
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _engineSizeField() {
    final opts = _engineSizeDisplayOptions;
    if (opts != null && opts.isNotEmpty) {
      final pick = _coerceEngineDisplayPick(opts);
      return DropdownButtonFormField<String>(
        key: ValueKey<String>('es_${opts.join('|')}'),
        value: pick,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Engine size (L)',
          helperText: opts.length < 2 ? null : opts.join(' · '),
        ),
        items: opts
            .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _engineSizeCtl.text = x;
            final lit = OnlineSpecVariant.parseLeadingEngineLiters(x);
            _syncCorrelatedFromOnlineVariants({'e'}, engineLiters: lit);
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _engineSizeCtl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Engine size (L)'),
    );
  }

  Widget _cylinderField() {
    final opts = _cylinderOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = int.tryParse(_cylinderCtl.text.trim());
      final value = (cur != null && opts.contains(cur)) ? cur : opts.first;
      return DropdownButtonFormField<int>(
        key: ValueKey<String>('cy_${opts.join(',')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Cylinders',
          helperText: opts.length < 2
              ? null
              : opts.map((n) => '$n').join(' · '),
        ),
        items: opts
            .map((n) => DropdownMenuItem<int>(value: n, child: Text('$n')))
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants({'c'}, cylinders: x);
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _cylinderCtl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Cylinders'),
    );
  }

  Widget _fuelEconomyField() {
    final opts = _fuelEconomyOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = _fuelEconomyCtl.text.trim();
      final value = opts.contains(cur) ? cur : opts.first;
      return DropdownButtonFormField<String>(
        key: ValueKey<String>('mpg_${opts.join('|')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Fuel economy',
          helperText: opts.length < 2
              ? null
              : '${opts.length} EPA values — pick one',
        ),
        items: opts
            .map(
              (s) => DropdownMenuItem<String>(
                value: s,
                child: Text(
                  s,
                  maxLines: 4,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants({'mpg'}, fuelEconomy: x);
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _fuelEconomyCtl,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Fuel economy'),
    );
  }

  Widget _seatingField() {
    final opts = _seatingOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = int.tryParse(_seatingCtl.text.trim());
      final value = (cur != null && opts.contains(cur)) ? cur : opts.first;
      return DropdownButtonFormField<int>(
        key: ValueKey<String>('seat_${opts.join(',')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Seating',
          helperText: opts.length < 2
              ? null
              : opts.map((n) => '$n').join(' · '),
        ),
        items: opts
            .map((n) => DropdownMenuItem<int>(value: n, child: Text('$n')))
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants({'seat'}, seating: x);
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _seatingCtl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Seating'),
    );
  }
}
