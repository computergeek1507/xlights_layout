import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlights_layout/models/node_calc.dart';
import 'package:xlights_layout/models/prop.dart';
import 'package:xlights_layout/services/layout_store.dart';
import 'package:xlights_layout/services/xlights_parser.dart';

void main() {
  final networksXml = File('test/fixtures/xlights_networks.xml').readAsStringSync();
  final rgbXml = File('test/fixtures/xlights_rgbeffects.xml').readAsStringSync();

  group('parseNetworks', () {
    final controllers = XLightsParser.parseNetworks(networksXml);

    test('parses all named controllers', () {
      expect(controllers.length, 9);
    });

    test('House Left has the right vendor/model/channels', () {
      final hl = controllers.firstWhere((c) => c.name == 'House Left');
      expect(hl.vendor, 'ScottNation');
      expect(hl.modelVariant, 'PB16 (Expansion)');
      expect(hl.ipProtocol, '192.168.1.205 (DDP)');
      expect(hl.channels, 7176);
      expect(hl.id, '64003');
    });
  });

  group('parseModels node/channel math', () {
    final props = XLightsParser.parseModels(rgbXml);
    XProp byName(String n) => props.firstWhere((p) => p.name == n);

    test('skips model groups and gridlines', () {
      expect(props.any((p) => p.displayAs == 'ModelGroup'), isFalse);
      expect(props.any((p) => p.displayAs == 'Gridlines'), isFalse);
    });

    test('Arches: NumArches * NodesPerArch', () {
      final arch1 = byName('Arch1');
      expect(arch1.nodeCount, 25);
      expect(arch1.channelCount, 75);
      expect(arch1.controllerName, 'Tree');
      expect(arch1.port, 17);
      expect(arch1.protocol, 'ws2811');
      expect(arch1.connectionLabel, 'ws2811:Port #17');
    });

    test('Single Line: Big Lights = 7 nodes / 21 channels', () {
      final big = byName('Big Lights');
      expect(big.nodeCount, 7);
      expect(big.channelCount, 21);
    });

    test('Custom: Bell PixelCount = 109', () {
      expect(byName('Bell').nodeCount, 109);
    });

    test('Custom: BabyBack_Left = 200 nodes (compressed max index)', () {
      expect(byName('BabyBack_Left').nodeCount, 200);
    });

    test('Window Frame: 2*Side + Top + Bottom', () {
      // Front Door WF: SideNodes=21, TopNodes=9, BottomNodes=0 -> 51
      expect(byName('Front Door WF').nodeCount, 51);
    });

    test('Tree: NumStrings * NodesPerString', () {
      expect(byName('PixelTree').nodeCount, 16 * 200);
      expect(byName('BigTree1').nodeCount, 136);
    });

    test('Matrix: NumStrings * NodesPerString', () {
      expect(byName('Matrix').nodeCount, 192 * 192);
    });

    test('Circle: Wreath = 72 nodes', () {
      expect(byName('Wreath').nodeCount, 72);
    });

    test('chained model exposes its ModelChain target', () {
      expect(byName('Arch1').modelChain, 'Arch2');
      expect(byName('Arch1').isChained, isTrue);
      expect(byName('Arch2').isChained, isFalse);
    });

    test('unassigned model (No Controller) is not assigned', () {
      final star = byName('OldStar');
      expect(star.controllerName, 'No Controller');
      expect(star.isAssigned, isFalse);
    });
  });

  group('LayoutStore grouping (Condensed view)', () {
    final store = LayoutStore()
      ..loadNetworks(networksXml.codeUnits, 'xlights_networks.xml')
      ..loadRgbEffects(rgbXml.codeUnits, 'xlights_rgbeffects.xml');
    final data = store.grouped;

    test('Arch1 lands under Tree -> Port 17', () {
      final tree = data.groups.firstWhere((g) => g.name == 'Tree');
      expect(tree.ports[17]!.any((p) => p.name == 'Arch1'), isTrue);
    });

    test('unassigned props captured separately', () {
      expect(data.notAssigned.any((p) => p.name == 'OldStar'), isTrue);
    });

    test('props on a port are sorted by start channel', () {
      for (final g in data.groups) {
        for (final list in g.ports.values) {
          for (var i = 1; i < list.length; i++) {
            expect(list[i].startChannel >= list[i - 1].startChannel, isTrue);
          }
        }
      }
    });
  });

  group('pre-2026.04 (legacy parm) format', () {
    final legacyXml =
        File('test/fixtures/xlights_rgbeffects_pre2026.04.xml').readAsStringSync();
    final props = XLightsParser.parseModels(legacyXml);
    XProp byName(String n) => props.firstWhere((p) => p.name == n);

    test('parses legacy models', () {
      expect(props, isNotEmpty);
      expect(props.any((p) => p.name == 'BabyBack_Left'), isTrue);
    });

    test('Arches via parm1*parm2 (DrivewayArch4 = 37)', () {
      expect(byName('DrivewayArch4').nodeCount, 37);
      expect(byName('DrivewayArch4').shape, PropShape.arch);
    });

    test('Single Line via parm1*parm2 (Ridge = 67)', () {
      expect(byName('Ridge').nodeCount, 67);
    });

    test('Window Frame via parm1/2/3 (Living Room WF = 2*15+13+13 = 56)', () {
      expect(byName('Living Room WF').nodeCount, 56);
    });

    test('Tree variant DisplayAs normalised (Glow1 "Tree 360" -> 20 nodes)', () {
      expect(byName('Glow1').nodeCount, 20);
      expect(byName('Glow1').shape, PropShape.tree);
    });

    test('Star via parm1*parm2 (PixelTreeStar = 180)', () {
      expect(byName('PixelTreeStar').nodeCount, 180);
    });

    test('Custom via CustomModel grid (BabyBack_Left = 200)', () {
      expect(byName('BabyBack_Left').nodeCount, 200);
    });

    test('Horiz Matrix normalises to Matrix shape', () {
      final matrix = props.where((p) => p.shape == PropShape.matrix);
      expect(matrix, isNotEmpty);
    });

    test('no DisplayAs leaks the legacy "Tree NNN"/"Horiz" variants', () {
      expect(props.any((p) => p.displayAs.contains('Tree 3')), isFalse);
      expect(props.any((p) => p.displayAs == 'Horiz Matrix'), isFalse);
    });
  });

  group('channelsPerNode', () {
    test('RGB -> 3, RGBW -> 4, single -> 1', () {
      expect(channelsPerNode('RGB Nodes'), 3);
      expect(channelsPerNode('RGBW Nodes'), 4);
      expect(channelsPerNode('Single Color Red'), 1);
    });
  });
}
