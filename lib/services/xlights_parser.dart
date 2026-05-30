import 'package:xml/xml.dart';

import '../models/controller.dart';
import '../models/prop.dart';

/// Parsers for the two xLights configuration files.
class XLightsParser {
  /// Parses `xlights_networks.xml` into the list of controllers.
  static List<XControllerInfo> parseNetworks(String xml) {
    final doc = XmlDocument.parse(xml);
    return doc
        .findAllElements('Controller')
        .map(XControllerInfo.fromXml)
        .where((c) => c.name.isNotEmpty)
        .toList();
  }

  /// Parses `xlights_rgbeffects.xml` into the list of props.
  ///
  /// Only real `<model>` elements directly under `<models>` are returned;
  /// `<modelGroups>`, `<gridlines>` and submodels are ignored.
  static List<XProp> parseModels(String xml) {
    final doc = XmlDocument.parse(xml);
    final models = doc.rootElement.findElements('models').firstOrNull;
    if (models == null) return const [];
    return models
        .findElements('model')
        .map(XProp.fromXml)
        .where((p) => p.name.isNotEmpty)
        .toList();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
