/// Shared types for loading xLights show files from a remote source
/// (a GitHub repository, Google Drive, ...).
library;

/// File names xLights writes into a show folder.
const rgbEffectsFileName = 'xlights_rgbeffects.xml';
const networksFileName = 'xlights_networks.xml';

/// A downloaded file, ready to hand to the [LayoutStore] loaders.
class RemoteFile {
  const RemoteFile(this.name, this.bytes);

  final String name;
  final List<int> bytes;
}

/// One show folder found on a remote source. A source may find several (e.g.
/// a repo holding more than one show, or Drive copies in backup folders), in
/// which case the user picks one.
class ShowFolderCandidate {
  const ShowFolderCandidate({
    required this.title,
    this.subtitle,
    required this.rgbEffectsRef,
    this.networksRef,
  });

  /// Primary label, e.g. the folder path or name.
  final String title;

  /// Secondary label, e.g. modified time or whether networks.xml is present.
  final String? subtitle;

  /// Source-specific handle for xlights_rgbeffects.xml (a path or a file ID).
  final String rgbEffectsRef;

  /// Source-specific handle for xlights_networks.xml, if it was found.
  final String? networksRef;

  bool get hasNetworks => networksRef != null;
}

/// Error with a message that is safe and useful to show to the user.
class RemoteSourceException implements Exception {
  const RemoteSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}
