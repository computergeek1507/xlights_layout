import 'package:xml/xml.dart';

/// A controller parsed from `xlights_networks.xml` (`<Controller>` element).
class XControllerInfo {
  XControllerInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.ip,
    required this.protocol,
    required this.vendor,
    required this.model,
    required this.variant,
    required this.channels,
    required this.universes,
  });

  final String id;
  final String name;
  final String description;
  final String ip;
  final String protocol;
  final String vendor;
  final String model;
  final String variant;

  /// Total channel count for the controller (sum of its `<network>` rows).
  final int channels;

  /// Number of universes (E1.31 / ArtNet); 0 for protocols like DDP.
  final int universes;

  /// `"IP (PROTOCOL)"`, e.g. `192.168.1.205 (DDP)`.
  String get ipProtocol => protocol.isEmpty ? ip : '$ip ($protocol)';

  /// `"Model (Variant)"`, e.g. `PB16 (Expansion)`; just the model if no variant.
  String get modelVariant =>
      variant.trim().isEmpty ? model : '$model ($variant)';

  factory XControllerInfo.fromXml(XmlElement e) {
    String attr(String name) => e.getAttribute(name)?.trim() ?? '';

    var channels = 0;
    var universes = 0;
    for (final net in e.findElements('network')) {
      channels += int.tryParse(net.getAttribute('MaxChannels')?.trim() ?? '') ?? 0;
      // E1.31 / ArtNet rows describe one or more universes via NumUniverses.
      final type = net.getAttribute('NetworkType')?.trim() ?? '';
      if (type == 'E131' || type == 'ArtNET' || type == 'ArtNet') {
        universes += int.tryParse(net.getAttribute('NumUniverses')?.trim() ?? '') ?? 1;
      }
    }

    return XControllerInfo(
      id: attr('Id'),
      name: attr('Name'),
      description: attr('Description'),
      ip: attr('IP'),
      protocol: attr('Protocol'),
      vendor: attr('Vendor'),
      model: attr('Model'),
      variant: attr('Variant'),
      channels: channels,
      universes: universes,
    );
  }
}
