// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' as io; // Desktop/mobile
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const CoordInspectorApp());

class CoordInspectorApp extends StatelessWidget {
  const CoordInspectorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Coordinate Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const CoordHome(),
    );
  }
}

class CoordHome extends StatefulWidget {
  const CoordHome({super.key});
  @override
  State<CoordHome> createState() => _CoordHomeState();
}

class MarkerPoint {
  MarkerPoint({required this.name, required this.pos});
  String name;
  Offset pos; // coordenadas na imagem (px), origem canto superior esquerdo
}

class _CoordHomeState extends State<CoordHome> {
  ui.Image? _img;
  final _ivController = TransformationController();
  final _pdfWController = TextEditingController();
  final _pdfHController = TextEditingController();
  final _gotoXController = TextEditingController();
  final _gotoYController = TextEditingController();
  bool _gotoIsPdf = false; // false = imagem (px), true = PDF (pt)

  // UI / estado
  bool _showGrid = true;
  bool _snapToGrid = false;
  double _gridStep = 10;
  Offset? _hoverScene; // em coordenadas da imagem
  final List<MarkerPoint> _markers = [];

  // Página PDF (em pontos). Se = null, assume igual ao tamanho da imagem.
  double? _pdfW;
  double? _pdfH;

  // Detecção de clique vs arraste
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;

  // Helpers de escala
  double get _imgW => _img?.width.toDouble() ?? 0;
  double get _imgH => _img?.height.toDouble() ?? 0;
  double get _pageW => _pdfW ?? _imgW;
  double get _pageH => _pdfH ?? _imgH;
  Size _viewportSize = Size.zero; // área visível do viewer

  // Conversão imagem->PDF (mantendo proporção por eixos)
  double get _scaleX => _imgW == 0 ? 1 : _pageW / _imgW;
  double get _scaleY => _imgH == 0 ? 1 : _pageH / _imgH;

  @override
  void dispose() {
    _pdfWController.dispose();
    _pdfHController.dispose();
    _gotoXController.dispose();
    _gotoYController.dispose();
    _ivController.dispose();
    super.dispose();
  }

  void _goTo(Offset sceneTarget) {
    if (_img == null) return;
    // aplica snap se ativo
    Offset p = Offset(
      sceneTarget.dx.clamp(0, _imgW),
      sceneTarget.dy.clamp(0, _imgH),
    );
    if (_snapToGrid && _gridStep > 0) {
      p = Offset(
        (p.dx / _gridStep).round() * _gridStep,
        (p.dy / _gridStep).round() * _gridStep,
      );
    }

    final s = _ivController.value.storage[0]; // escala atual (X)
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final tx = center.dx - p.dx * s;
    final ty = center.dy - p.dy * s;

    final m = Matrix4.identity();
    m.setEntry(0, 0, s);
    m.setEntry(1, 1, s);
    m.setEntry(2, 2, 1);
    m.setEntry(0, 3, tx);
    m.setEntry(1, 3, ty);
    _ivController.value = m;
    setState(() {});
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (res == null) return;

    Uint8List? bytes = res.files.single.bytes;
    bytes ??= await io.File(res.files.single.path!).readAsBytes();

    final img = await _decode(bytes);
    setState(() {
      _img = img;
      _pdfW = img.width.toDouble();
      _pdfH = img.height.toDouble();
      _pdfWController.text = _pdfW!.toStringAsFixed(0);
      _pdfHController.text = _pdfH!.toStringAsFixed(0);
      _markers.clear();
      _ivController.value = Matrix4.identity();
    });
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    return c.future;
  }

  void _onHover(PointerHoverEvent e, RenderBox box) {
    final local = e.localPosition;
    final scene = _ivController.toScene(local);
    if (_img == null) return;
    // limita dentro da imagem
    final clamped = Offset(scene.dx.clamp(0, _imgW), scene.dy.clamp(0, _imgH));
    Offset pos = clamped;
    if (_snapToGrid && _gridStep > 0) {
      pos = Offset(
        (pos.dx / _gridStep).round() * _gridStep,
        (pos.dy / _gridStep).round() * _gridStep,
      );
    }
    setState(() => _hoverScene = pos);
  }

  void _onPointerDown(PointerDownEvent e, RenderBox box) {
    if (_img == null) return;
    // clique primário apenas
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    // Registra posição e tempo do clique
    final local = e.localPosition;
    final scene = _ivController.toScene(local);
    _pointerDownPos = Offset(
      scene.dx.clamp(0, _imgW),
      scene.dy.clamp(0, _imgH),
    );
    _pointerDownTime = DateTime.now();
  }

  Future<void> _onPointerUp(PointerUpEvent e, RenderBox box) async {
    if (_img == null || _pointerDownPos == null || _pointerDownTime == null) {
      _pointerDownPos = null;
      _pointerDownTime = null;
      return;
    }

    // Verifica se foi um clique primário
    if (e.kind == PointerDeviceKind.mouse && e.buttons != 0) {
      _pointerDownPos = null;
      _pointerDownTime = null;
      return;
    }

    final local = e.localPosition;
    final scene = _ivController.toScene(local);
    final upPos = Offset(scene.dx.clamp(0, _imgW), scene.dy.clamp(0, _imgH));

    // Calcula distância e tempo
    final distance = (upPos - _pointerDownPos!).distance;
    final duration = DateTime.now().difference(_pointerDownTime!);

    // Se moveu menos de 10px e durou menos de 500ms, considera um clique
    if (distance < 10 && duration.inMilliseconds < 500) {
      Offset p = _pointerDownPos!;
      if (_snapToGrid && _gridStep > 0) {
        p = Offset(
          (p.dx / _gridStep).round() * _gridStep,
          (p.dy / _gridStep).round() * _gridStep,
        );
      }
      final name = await _askName(context);
      if (name != null && name.trim().isNotEmpty) {
        setState(() => _markers.add(MarkerPoint(name: name.trim(), pos: p)));
      }
    }

    // Limpa o estado
    _pointerDownPos = null;
    _pointerDownTime = null;
  }

  Future<void> _onSecondaryTapDown(PointerDownEvent e, RenderBox box) async {
    if (_img == null) return;
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    final local = e.localPosition;
    final scene = _ivController.toScene(local);
    final p = Offset(scene.dx, scene.dy);
    // remove nearest marker (<= 10px)
    int? removeIdx;
    double best = 12;
    for (int i = 0; i < _markers.length; i++) {
      final d = (p - _markers[i].pos).distance;
      if (d < best) {
        best = d;
        removeIdx = i;
      }
    }
    if (removeIdx != null) {
      final ok = await _confirm(
        context,
        'Remove "${_markers[removeIdx].name}"?',
      );
      if (ok) setState(() => _markers.removeAt(removeIdx!));
    }
  }

  Future<String?> _askName(BuildContext ctx) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder:
          (cxt) => AlertDialog(
            title: const Text('Field name'),
            content: TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (value) => Navigator.pop(cxt, value),
              decoration: const InputDecoration(
                hintText: 'e.g.: code_uc, address, power',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(cxt),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(cxt, c.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  Future<bool> _confirm(BuildContext ctx, String msg) async {
    final r = await showDialog<bool>(
      context: ctx,
      builder:
          (cxt) => AlertDialog(
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(cxt, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(cxt, true),
                child: const Text('Yes'),
              ),
            ],
          ),
    );
    return r ?? false;
  }

  Map<String, dynamic> _buildJson() {
    final map = <String, dynamic>{
      'meta': {
        'imageWidth': _imgW,
        'imageHeight': _imgH,
        'pdfWidth': _pageW,
        'pdfHeight': _pageH,
        'origin': 'bottomLeft', // para PDF
        'scaleX': _scaleX,
        'scaleY': _scaleY,
      },
      'markers': <String, dynamic>{},
    };
    for (final m in _markers) {
      final imgX = m.pos.dx;
      final imgY = m.pos.dy;
      final pdfX = imgX * _scaleX;
      final pdfY = (_pageH - imgY * _scaleY);
      map['markers'][m.name] = {
        'image': {'x': imgX, 'y': imgY}, // origem top-left
        'pdf': {'x': pdfX, 'y': pdfY}, // origem bottom-left
      };
    }
    return map;
  }

  Future<void> _exportJson() async {
    if (_img == null) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_buildJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!kIsWeb) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save coordinates (.json)',
        fileName: 'coords.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path != null) {
        await io.File(path).writeAsString(jsonStr);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON copied to clipboard.')),
      );
    }
  }

  Future<void> _importJson() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (res == null) return;
    final txt = (res.files.single.bytes ??
            await io.File(res.files.single.path!).readAsBytes())
        .toList(growable: false);
    final str = utf8.decode(txt);
    final obj = jsonDecode(str) as Map<String, dynamic>;
    final meta = obj['meta'] as Map<String, dynamic>?;

    if (_img == null) {
      // tenta manter dimensões do JSON como PDF target
      if (meta != null) {
        _pdfW = (meta['pdfWidth'] as num?)?.toDouble();
        _pdfH = (meta['pdfHeight'] as num?)?.toDouble();
      }
    }
    final markers = <MarkerPoint>[];
    final m = obj['markers'] as Map<String, dynamic>;
    m.forEach((k, v) {
      final im = (v['image'] ?? {}) as Map<String, dynamic>;
      markers.add(
        MarkerPoint(
          name: k,
          pos: Offset((im['x'] as num).toDouble(), (im['y'] as num).toDouble()),
        ),
      );
    });
    setState(
      () =>
          _markers
            ..clear()
            ..addAll(markers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImg = _img != null;
    final hoverImg = _hoverScene;
    final hoverPdf =
        (hasImg && hoverImg != null)
            ? Offset(hoverImg.dx * _scaleX, (_pageH - hoverImg.dy * _scaleY))
            : null;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 64,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.picture_as_pdf,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PDF Coordinate Inspector',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  hasImg ? '${_markers.length} markers' : 'No image loaded',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined, size: 20),
            label: const Text('Open Image'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          if (hasImg) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _exportJson,
              icon: const Icon(Icons.download, size: 20),
              label: const Text('Export JSON'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _importJson,
              icon: const Icon(Icons.upload, size: 20),
              label: const Text('Import JSON'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body:
          hasImg
              ? Row(
                children: [
                  // Left sidebar with controls
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Grid Controls Card
                        _buildControlCard(
                          context,
                          title: 'Grid Settings',
                          icon: Icons.grid_on,
                          children: [
                            _buildSwitchRow(
                              context,
                              'Show Grid',
                              _showGrid,
                              (v) => setState(() => _showGrid = v),
                            ),
                            const SizedBox(height: 12),
                            _buildSwitchRow(
                              context,
                              'Snap to Grid',
                              _snapToGrid,
                              (v) => setState(() => _snapToGrid = v),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Grid Step: ${_gridStep.toStringAsFixed(0)}px',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Slider(
                              value: _gridStep,
                              onChanged: (v) => setState(() => _gridStep = v),
                              min: 4,
                              max: 40,
                              divisions: 9,
                              label: '${_gridStep.toStringAsFixed(0)}px',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Dimensions Card
                        _buildControlCard(
                          context,
                          title: 'Dimensions',
                          icon: Icons.aspect_ratio,
                          children: [
                            _buildInfoRow(
                              context,
                              'Image',
                              '${_imgW.toStringAsFixed(0)} × ${_imgH.toStringAsFixed(0)} px',
                              Icons.photo_size_select_actual,
                            ),
                            const SizedBox(height: 12),
                            _buildInputRow(
                              context,
                              'PDF Width',
                              _pdfWController,
                              'points',
                              (v) {
                                final newW = double.tryParse(v) ?? _pageW;
                                setState(() {
                                  _pdfW = newW;
                                  _pdfWController.text = newW.toStringAsFixed(
                                    0,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildInputRow(
                              context,
                              'PDF Height',
                              _pdfHController,
                              'points',
                              (v) {
                                final newH = double.tryParse(v) ?? _pageH;
                                setState(() {
                                  _pdfH = newH;
                                  _pdfHController.text = newH.toStringAsFixed(
                                    0,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scale Factors',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'X: ${_scaleX.toStringAsFixed(4)}\nY: ${_scaleY.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Go To Coordinates Card
                        _buildControlCard(
                          context,
                          title: 'Navigate',
                          icon: Icons.my_location,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Image (px)'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('PDF (pt)'),
                                ),
                              ],
                              selected: {_gotoIsPdf},
                              onSelectionChanged:
                                  (v) => setState(() => _gotoIsPdf = v.first),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _gotoXController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'X',
                                      hintText:
                                          _gotoIsPdf ? 'points' : 'pixels',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _gotoYController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Y',
                                      hintText:
                                          _gotoIsPdf ? 'points' : 'pixels',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  if (_img == null) return;
                                  final x = double.tryParse(
                                    _gotoXController.text,
                                  );
                                  final y = double.tryParse(
                                    _gotoYController.text,
                                  );
                                  if (x == null || y == null) return;
                                  Offset pos;
                                  if (_gotoIsPdf) {
                                    final imgX =
                                        _scaleX == 0 ? 0.0 : x / _scaleX;
                                    final imgY =
                                        _scaleY == 0
                                            ? 0.0
                                            : (_pageH - y) / _scaleY;
                                    pos = Offset(imgX, imgY);
                                  } else {
                                    pos = Offset(x, y);
                                  }
                                  pos = Offset(
                                    pos.dx.clamp(0, _imgW),
                                    pos.dy.clamp(0, _imgH),
                                  );
                                  if (_snapToGrid && _gridStep > 0) {
                                    pos = Offset(
                                      (pos.dx / _gridStep).round() * _gridStep,
                                      (pos.dy / _gridStep).round() * _gridStep,
                                    );
                                  }
                                  _goTo(pos);
                                  final name = await _askName(context);
                                  if (name != null && name.trim().isNotEmpty) {
                                    setState(
                                      () => _markers.add(
                                        MarkerPoint(
                                          name: name.trim(),
                                          pos: pos,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.navigation),
                                label: const Text('Go & Mark'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Cursor Position Card
                        if (hoverImg != null)
                          _buildControlCard(
                            context,
                            title: 'Cursor Position',
                            icon: Icons.location_searching,
                            children: [
                              _buildInfoRow(
                                context,
                                'Image',
                                'X: ${hoverImg.dx.toStringAsFixed(1)}, Y: ${hoverImg.dy.toStringAsFixed(1)}',
                                Icons.image,
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                context,
                                'PDF',
                                'X: ${hoverPdf?.dx.toStringAsFixed(1)}, Y: ${hoverPdf?.dy.toStringAsFixed(1)}',
                                Icons.picture_as_pdf,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: () async {
                                    final m = MarkerPoint(
                                      name: 'campo_${_markers.length + 1}',
                                      pos:
                                          _snapToGrid && _gridStep > 0
                                              ? Offset(
                                                (hoverImg.dx / _gridStep)
                                                        .round() *
                                                    _gridStep,
                                                (hoverImg.dy / _gridStep)
                                                        .round() *
                                                    _gridStep,
                                              )
                                              : hoverImg,
                                    );
                                    setState(() => _markers.add(m));
                                  },
                                  icon: const Icon(Icons.add_location_alt),
                                  label: const Text('Quick Mark'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Main canvas area
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, constraints) {
                              _viewportSize = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              return Listener(
                                onPointerHover:
                                    (e) => _onHover(
                                      e,
                                      ctx.findRenderObject() as RenderBox,
                                    ),
                                onPointerDown: (e) {
                                  if (e.buttons & kSecondaryMouseButton != 0) {
                                    _onSecondaryTapDown(
                                      e,
                                      ctx.findRenderObject() as RenderBox,
                                    );
                                  } else {
                                    _onPointerDown(
                                      e,
                                      ctx.findRenderObject() as RenderBox,
                                    );
                                  }
                                },
                                onPointerUp: (e) {
                                  _onPointerUp(
                                    e,
                                    ctx.findRenderObject() as RenderBox,
                                  );
                                },
                                child: InteractiveViewer(
                                  transformationController: _ivController,
                                  maxScale: 12,
                                  minScale: 0.2,
                                  boundaryMargin: const EdgeInsets.fromLTRB(
                                    800,
                                    800,
                                    800,
                                    2000,
                                  ),
                                  constrained: false,
                                  child: CustomPaint(
                                    size: Size(_imgW, _imgH),
                                    painter: _CanvasPainter(
                                      image: _img!,
                                      showGrid: _showGrid,
                                      gridStep: _gridStep,
                                      hover: _hoverScene,
                                      markers: _markers,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Bottom markers panel
                        if (_markers.isNotEmpty)
                          Container(
                            height: 80,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                              border: Border(
                                top: BorderSide(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                // Header with count and clear button
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${_markers.length}',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                      Text(
                                        'markers',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Clear all button
                                IconButton(
                                  onPressed: () async {
                                    final confirmed = await _confirm(
                                      context,
                                      'Remove all ${_markers.length} markers?',
                                    );
                                    if (confirmed) {
                                      setState(() => _markers.clear());
                                    }
                                  },
                                  icon: Icon(
                                    Icons.delete_sweep,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  tooltip: 'Clear all markers',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .errorContainer
                                        .withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Markers list
                                Expanded(
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    separatorBuilder:
                                        (_, __) => const SizedBox(width: 6),
                                    itemCount: _markers.length,
                                    itemBuilder: (_, i) {
                                      final m = _markers[i];
                                      final pdfX = m.pos.dx * _scaleX;
                                      final pdfY =
                                          (_pageH - m.pos.dy * _scaleY);
                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _goTo(m.pos),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Container(
                                            constraints: const BoxConstraints(
                                              minWidth: 160,
                                              maxWidth: 250,
                                            ),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.4),
                                                width: 1,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Header row: index + name + actions
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .primary,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '#${i + 1}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        m.name,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onPrimaryContainer,
                                                        ),
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                    // Actions
                                                    InkWell(
                                                      onTap: () {
                                                        Clipboard.setData(
                                                          ClipboardData(
                                                            text:
                                                                '{"x":${pdfX.toStringAsFixed(1)},"y":${pdfY.toStringAsFixed(1)}}',
                                                          ),
                                                        );
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              'Copied: ${m.name}',
                                                            ),
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        child: Icon(
                                                          Icons.copy,
                                                          size: 12,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                        ),
                                                      ),
                                                    ),
                                                    InkWell(
                                                      onTap: () async {
                                                        final confirmed =
                                                            await _confirm(
                                                              context,
                                                              'Remove "${m.name}"?',
                                                            );
                                                        if (confirmed) {
                                                          setState(
                                                            () => _markers
                                                                .removeAt(i),
                                                          );
                                                        }
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        child: Icon(
                                                          Icons.close,
                                                          size: 12,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .error,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                // Coordinates row
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.3),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.image,
                                                            size: 9,
                                                            color: Theme.of(
                                                                  context,
                                                                )
                                                                .colorScheme
                                                                .onPrimaryContainer
                                                                .withOpacity(
                                                                  0.7,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Text(
                                                            '${m.pos.dx.toStringAsFixed(0)},${m.pos.dy.toStringAsFixed(0)}',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onPrimaryContainer
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surface
                                                            .withOpacity(0.3),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .picture_as_pdf,
                                                            size: 9,
                                                            color: Theme.of(
                                                                  context,
                                                                )
                                                                .colorScheme
                                                                .onPrimaryContainer
                                                                .withOpacity(
                                                                  0.7,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Text(
                                                            '${pdfX.toStringAsFixed(0)},${pdfY.toStringAsFixed(0)}',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onPrimaryContainer
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
              : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 80,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Image Loaded',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Load a PDF screenshot to start marking coordinates',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined, size: 24),
                      label: const Text('Open Image'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildControlCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputRow(
    BuildContext context,
    String label,
    TextEditingController controller,
    String hint,
    ValueChanged<String> onSubmitted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.image,
    required this.showGrid,
    required this.gridStep,
    required this.hover,
    required this.markers,
  });

  final ui.Image image;
  final bool showGrid;
  final double gridStep;
  final Offset? hover;
  final List<MarkerPoint> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    canvas.drawImage(image, Offset.zero, paint);

    if (showGrid && gridStep > 0) {
      final majorGrid =
          Paint()
            ..color = const Color(0x44000000)
            ..strokeWidth = 1.2;
      final minorGrid =
          Paint()
            ..color = const Color(0x22000000)
            ..strokeWidth = 0.8;

      for (double x = 0; x <= size.width; x += gridStep) {
        final isMajor = (x / gridStep) % 5 == 0;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          isMajor ? majorGrid : minorGrid,
        );
      }
      for (double y = 0; y <= size.height; y += gridStep) {
        final isMajor = (y / gridStep) % 5 == 0;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          isMajor ? majorGrid : minorGrid,
        );
      }
    }

    // Crosshair on hover
    if (hover != null) {
      final crossOuter =
          Paint()
            ..color = const Color(0x66FFFFFF)
            ..strokeWidth = 2;
      final crossInner =
          Paint()
            ..color = const Color(0xDD007AFF)
            ..strokeWidth = 1;

      // Draw white outline first
      canvas.drawLine(
        Offset(hover!.dx, 0),
        Offset(hover!.dx, size.height),
        crossOuter,
      );
      canvas.drawLine(
        Offset(0, hover!.dy),
        Offset(size.width, hover!.dy),
        crossOuter,
      );

      // Draw blue lines
      canvas.drawLine(
        Offset(hover!.dx, 0),
        Offset(hover!.dx, size.height),
        crossInner,
      );
      canvas.drawLine(
        Offset(0, hover!.dy),
        Offset(size.width, hover!.dy),
        crossInner,
      );

      // Draw center dot with border
      final dotBorder = Paint()..color = Colors.white;
      final dot = Paint()..color = const Color(0xFF007AFF);
      canvas.drawCircle(hover!, 4, dotBorder);
      canvas.drawCircle(hover!, 3, dot);
    }

    // Markers
    final mPaint = Paint()..color = Colors.redAccent;
    final mBorder =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    for (final m in markers) {
      // Draw marker with white border for better visibility
      canvas.drawCircle(m.pos, 5, mBorder);
      canvas.drawCircle(m.pos, 4, mPaint);

      // Draw label with background
      final textBuilder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(fontSize: 12, fontWeight: FontWeight.w600),
            )
            ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
            ..addText(m.name);
      final paragraph =
          textBuilder.build()
            ..layout(const ui.ParagraphConstraints(width: 240));

      // Background for label
      final labelBg = Paint()..color = const Color(0xDD000000);
      final labelRect = Rect.fromLTWH(
        m.pos.dx + 8,
        m.pos.dy - 14,
        paragraph.longestLine + 8,
        18,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        labelBg,
      );
      canvas.drawParagraph(paragraph, m.pos + const Offset(12, -12));
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) {
    return old.image != image ||
        old.showGrid != showGrid ||
        old.gridStep != gridStep ||
        old.hover != hover ||
        !listEquals(old.markers, markers);
  }
}
