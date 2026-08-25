// Draws the ST's framebuffer.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ffi/atarist_core.dart';

/// Polls the core and paints whatever it last drew.
///
/// Polling rather than being pushed to, because the core runs on its own
/// thread in C and has no way to call into Dart's isolate. [frameCounter] is
/// what makes that cheap: when it has not moved, nothing is copied, decoded or
/// uploaded, and a GEM desktop sitting idle costs nothing at all.
class FramebufferView extends StatefulWidget {
  final AtariStCore core;

  /// How often to check for a new frame. 60Hz by default -- deliberately
  /// faster than the ST's 50Hz so a frame is never held for two host frames
  /// through beat frequency alone.
  final Duration pollInterval;

  /// Nearest-neighbour scaling. On by default: a 320x200 image smoothed up to
  /// a 4K panel looks like a blurred photograph of a monitor rather than like
  /// an ST, and every one of these apps has ended up defaulting it on.
  final bool pixelPerfect;

  const FramebufferView({
    super.key,
    required this.core,
    this.pollInterval = const Duration(milliseconds: 16),
    this.pixelPerfect = true,
  });

  @override
  State<FramebufferView> createState() => _FramebufferViewState();
}

class _FramebufferViewState extends State<FramebufferView> {
  Timer? _timer;
  ui.Image? _image;
  int _lastFrame = -1;

  /// True while an async decode is in flight. Without it, a decode slower
  /// than the poll interval queues a second one behind it, then a third, and
  /// the app walks itself into an unbounded backlog that presents as the UI
  /// getting steadily further behind the emulator.
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_decoding || !mounted) return;

    final counter = widget.core.frameCounter;

    // A counter that went BACKWARDS means the machine was reset -- the core
    // hot-swapped to another title. Drop the picture rather than leaving the
    // previous game's last frame on screen for the forty seconds the new one
    // takes to load, which looks like the new title failing to start.
    if (counter < _lastFrame) {
      _lastFrame = -1;
      final stale = _image;
      _image = null;
      stale?.dispose();
      if (mounted) setState(() {});
    }

    if (counter == _lastFrame) return;

    final frame = widget.core.getFramebuffer();
    if (frame == null) return;

    _lastFrame = counter;
    _decoding = true;
    try {
      final image = await _decode(frame);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } finally {
      _decoding = false;
    }
  }

  Future<ui.Image> _decode(StFrame frame) {
    // The core's rows are padded to a fixed stride, so the visible part of
    // each row has to be repacked before decoding -- decodeImageFromPixels
    // takes a tightly packed buffer and has no stride parameter.
    final rowInts = frame.pitchBytes ~/ 4;
    final packed = Uint32List(frame.width * frame.height);
    if (rowInts == frame.width) {
      packed.setRange(0, packed.length, frame.pixels);
    } else {
      for (var y = 0; y < frame.height; y++) {
        packed.setRange(
          y * frame.width,
          (y + 1) * frame.width,
          frame.pixels,
          y * rowInts,
        );
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      packed.buffer.asUint8List(),
      frame.width,
      frame.height,
      // The core writes XRGB8888, which on a little-endian host is BGRA in
      // memory order -- and memory order is what this argument means.
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const ColoredBox(color: Colors.black);
    }

    // Sized by the DISPLAY aspect, not the pixel count. Every ST mode was
    // shown on a 4:3 monitor, so 320x200, 640x200 and 640x400 all have
    // differently-shaped pixels; letting width/height decide makes a circle
    // an oval in two of the three.
    final aspect = widget.core.pixelAspect ?? 4 / 3;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality:
                widget.pixelPerfect ? FilterQuality.none : FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
