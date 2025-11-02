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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
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
    // remover marcador mais próximo (<= 10px)
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
        'Remover "${_markers[removeIdx].name}"?',
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
            title: const Text('Nome do campo'),
            content: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'ex.: codigo_uc, endereco, potencia',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(cxt),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(cxt, c.text),
                child: const Text('Salvar'),
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
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(cxt, true),
                child: const Text('Sim'),
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
        dialogTitle: 'Salvar coordenadas (.json)',
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
        const SnackBar(
          content: Text('JSON copiado para a área de transferência.'),
        ),
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
        toolbarHeight: 48,
        title: const Text(
          'PDF Coordinate Inspector',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Open image…',
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined, size: 20),
            iconSize: 20,
          ),
          if (hasImg) ...[
            const VerticalDivider(),
            IconButton(
              tooltip: 'Export JSON',
              onPressed: _exportJson,
              icon: const Icon(Icons.save_alt, size: 20),
              iconSize: 20,
            ),
            IconButton(
              tooltip: 'Import JSON',
              onPressed: _importJson,
              icon: const Icon(Icons.file_upload, size: 20),
              iconSize: 20,
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (hasImg) ...[
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grid controls row
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.grid_on, size: 14),
                          const SizedBox(width: 2),
                          const Text('Grid', style: TextStyle(fontSize: 12)),
                          Tooltip(
                            message: 'Show/hide grid overlay',
                            child: Transform.scale(
                              scale: 0.7,
                              child: Switch(
                                value: _showGrid,
                                onChanged: (v) => setState(() => _showGrid = v),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.control_camera, size: 14),
                          const SizedBox(width: 2),
                          const Text('Snap', style: TextStyle(fontSize: 12)),
                          Tooltip(
                            message: 'Snap markers to grid points',
                            child: Transform.scale(
                              scale: 0.7,
                              child: Switch(
                                value: _snapToGrid,
                                onChanged:
                                    (v) => setState(() => _snapToGrid = v),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Passo:', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Adjust grid spacing',
                            child: SizedBox(
                              width: 120,
                              child: Slider(
                                value: _gridStep,
                                onChanged: (v) => setState(() => _gridStep = v),
                                min: 4,
                                max: 40,
                                divisions: 9,
                                label: '${_gridStep.toStringAsFixed(0)}px',
                              ),
                            ),
                          ),
                          Text(
                            '${_gridStep.toStringAsFixed(0)}px',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Tooltip(
                        message: 'Image dimensions (width × height in pixels)',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_size_select_actual,
                              size: 14,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_imgW.toStringAsFixed(0)}×${_imgH.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.picture_as_pdf, size: 14),
                          const SizedBox(width: 3),
                          const Text('W:', style: TextStyle(fontSize: 11)),
                          Tooltip(
                            message: 'PDF page width in points',
                            child: SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _pdfWController,
                                onSubmitted: (v) {
                                  final newW = double.tryParse(v) ?? _pageW;
                                  setState(() {
                                    _pdfW = newW;
                                    _pdfWController.text = newW.toStringAsFixed(
                                      0,
                                    );
                                  });
                                },
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('H:', style: TextStyle(fontSize: 11)),
                          Tooltip(
                            message: 'PDF page height in points',
                            child: SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _pdfHController,
                                onSubmitted: (v) {
                                  final newH = double.tryParse(v) ?? _pageH;
                                  setState(() {
                                    _pdfH = newH;
                                    _pdfHController.text = newH.toStringAsFixed(
                                      0,
                                    );
                                  });
                                },
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // GoTo (ir para X/Y – imagem (px) ou PDF (pt))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.my_location, size: 14),
                          const SizedBox(width: 3),
                          const Text('GoTo:', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Escolha o sistema: IMG (px) ou PDF (pt)',
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<bool>(
                                value: _gotoIsPdf,
                                items: const [
                                  DropdownMenuItem<bool>(
                                    value: false,
                                    child: Text(
                                      'IMG',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  DropdownMenuItem<bool>(
                                    value: true,
                                    child: Text(
                                      'PDF',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                                onChanged:
                                    (v) =>
                                        setState(() => _gotoIsPdf = v ?? false),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message:
                                _gotoIsPdf
                                    ? 'X em pontos (PDF)'
                                    : 'X em pixels (imagem)',
                            child: SizedBox(
                              width: 70,
                              child: TextField(
                                controller: _gotoXController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: _gotoIsPdf ? 'X (pt)' : 'X (px)',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message:
                                _gotoIsPdf
                                    ? 'Y em pontos (PDF). Origem canto inferior esquerdo'
                                    : 'Y em pixels (imagem). Origem canto superior esquerdo',
                            child: SizedBox(
                              width: 70,
                              child: TextField(
                                controller: _gotoYController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: _gotoIsPdf ? 'Y (pt)' : 'Y (px)',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                'Centraliza no ponto e abre o diálogo para marcar',
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 28),
                                textStyle: const TextStyle(fontSize: 11),
                              ),
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
                                  // PDF (pt) -> imagem (px)
                                  final imgX = _scaleX == 0 ? 0.0 : x / _scaleX;
                                  final imgY =
                                      _scaleY == 0
                                          ? 0.0
                                          : (_pageH - y) / _scaleY;
                                  pos = Offset(imgX, imgY);
                                } else {
                                  pos = Offset(x, y);
                                }
                                // clamp e snap para consistência
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

                                // Abre diálogo para permitir salvar marcador neste ponto
                                final name = await _askName(context);
                                if (name != null && name.trim().isNotEmpty) {
                                  setState(
                                    () => _markers.add(
                                      MarkerPoint(name: name.trim(), pos: pos),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Ir'),
                            ),
                          ),
                        ],
                      ),
                      Tooltip(
                        message:
                            'Scale factors for converting image coordinates to PDF points',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'X:${_scaleX.toStringAsFixed(3)} Y:${_scaleY.toStringAsFixed(3)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hoverImg != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '📍 IMG X:${hoverImg.dx.toStringAsFixed(1)} Y:${hoverImg.dy.toStringAsFixed(1)}  •  PDF x:${hoverPdf?.dx.toStringAsFixed(1)} y:${hoverPdf?.dy.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Add marker at current cursor position',
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 28),
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () async {
                                final m = MarkerPoint(
                                  name: 'campo_${_markers.length + 1}',
                                  pos:
                                      _snapToGrid && _gridStep > 0
                                          ? Offset(
                                            (hoverImg.dx / _gridStep).round() *
                                                _gridStep,
                                            (hoverImg.dy / _gridStep).round() *
                                                _gridStep,
                                          )
                                          : hoverImg,
                                );
                                setState(() => _markers.add(m));
                              },
                              icon: const Icon(Icons.add_location, size: 14),
                              label: const Text('Marcar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child:
                hasImg
                    ? LayoutBuilder(
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
                    )
                    : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Carrega um screenshot do PDF (página 1, 2, 3...)',
                          ),
                          const SizedBox(height: 12),
                          Tooltip(
                            message: 'Open image file',
                            child: FilledButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Abrir imagem'),
                            ),
                          ),
                        ],
                      ),
                    ),
          ),
          if (_markers.isNotEmpty) ...[
            const Divider(height: 1),
            Container(
              height: 96,
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // Botão limpar todos
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: 'Clear all markers',
                      child: Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: () async {
                            final confirmed = await _confirm(
                              context,
                              'Remover todos os ${_markers.length} marcadores?',
                            );
                            if (confirmed) {
                              setState(() => _markers.clear());
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_sweep,
                                  size: 20,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Limpar\nTodos',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 8,
                                    height: 1.1,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Lista de marcadores
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemCount: _markers.length,
                      itemBuilder: (_, i) {
                        final m = _markers[i];
                        final pdfX = m.pos.dx * _scaleX;
                        final pdfY = (_pageH - m.pos.dy * _scaleY);
                        return Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'IMG ${m.pos.dx.toStringAsFixed(0)},${m.pos.dy.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 9),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'PDF ${pdfX.toStringAsFixed(0)},${pdfY.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 9),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message:
                                        'Copy PDF coordinates to clipboard',
                                    child: InkWell(
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
                                            content: Text('Copiado: ${m.name}'),
                                            duration: const Duration(
                                              milliseconds: 800,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.copy,
                                          size: 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Delete this marker',
                                    child: InkWell(
                                      onTap: () async {
                                        final confirmed = await _confirm(
                                          context,
                                          'Remover "${m.name}"?',
                                        );
                                        if (confirmed)
                                          setState(() => _markers.removeAt(i));
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
