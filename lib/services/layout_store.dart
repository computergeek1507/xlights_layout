import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/controller.dart';
import '../models/prop.dart';
import 'xlights_parser.dart';

/// One controller plus the props wired to it, with props bucketed by port.
class ControllerGroup {
  ControllerGroup(this.name);

  final String name;

  /// Port number → props on that port (chained props share a port).
  final Map<int, List<XProp>> ports = {};

  /// Props that reference this controller but have no port assigned.
  final List<XProp> unported = [];

  Iterable<int> get sortedPorts => ports.keys.toList()..sort();
}

/// Central state holder for the loaded xLights files.
class LayoutStore extends ChangeNotifier {
  List<XControllerInfo> _controllers = [];
  List<XProp> _props = [];
  String? _rgbFileName;
  String? _networksFileName;
  String? _error;

  List<XControllerInfo> get controllers => _controllers;
  List<XProp> get props => _props;
  String? get rgbFileName => _rgbFileName;
  String? get networksFileName => _networksFileName;
  String? get error => _error;

  /// True once the required rgbeffects file has been loaded.
  bool get hasData => _props.isNotEmpty;

  /// Loads `xlights_rgbeffects.xml` (required) from raw bytes.
  void loadRgbEffects(List<int> bytes, String fileName) {
    try {
      _props = XLightsParser.parseModels(utf8.decode(bytes));
      _rgbFileName = fileName;
      _error = null;
    } catch (e) {
      _error = 'Could not parse $fileName: $e';
    }
    notifyListeners();
  }

  /// Loads `xlights_networks.xml` (optional) from raw bytes.
  void loadNetworks(List<int> bytes, String fileName) {
    try {
      _controllers = XLightsParser.parseNetworks(utf8.decode(bytes));
      _networksFileName = fileName;
      _error = null;
    } catch (e) {
      _error = 'Could not parse $fileName: $e';
    }
    notifyListeners();
  }

  /// Clears everything ("Start Over").
  void clear() {
    _controllers = [];
    _props = [];
    _rgbFileName = null;
    _networksFileName = null;
    _error = null;
    notifyListeners();
  }

  /// Props sorted by name for the Detailed table.
  List<XProp> get propsByName {
    final list = [..._props];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Builds the Condensed view structure: controller → port → props.
  ///
  /// Controllers are ordered to match the networks file when available, with
  /// any controllers referenced only by props appended after. The "not
  /// assigned" bucket (no controller / no port) is returned separately so the
  /// UI can render it first.
  ({List<ControllerGroup> groups, List<XProp> notAssigned}) get grouped {
    final groups = <String, ControllerGroup>{};
    final notAssigned = <XProp>[];

    // Seed group order from the networks file first.
    for (final c in _controllers) {
      groups[c.name] = ControllerGroup(c.name);
    }

    for (final p in _props) {
      final controller = p.controllerName;
      if (controller.isEmpty || controller == 'No Controller') {
        notAssigned.add(p);
        continue;
      }
      final group = groups.putIfAbsent(controller, () => ControllerGroup(controller));
      if (p.port > 0) {
        group.ports.putIfAbsent(p.port, () => []).add(p);
      } else {
        group.unported.add(p);
      }
    }

    // Sort props within each port by start channel (chain order).
    for (final g in groups.values) {
      for (final list in g.ports.values) {
        list.sort((a, b) => a.startChannel.compareTo(b.startChannel));
      }
    }

    // Drop controllers that ended up with no props at all.
    final nonEmpty = groups.values
        .where((g) => g.ports.isNotEmpty || g.unported.isNotEmpty)
        .toList();

    return (groups: nonEmpty, notAssigned: notAssigned);
  }
}
