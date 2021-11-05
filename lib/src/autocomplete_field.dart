import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef AutoCompleteDelegate<T> = FutureOr<List<T>> Function(String query);

class AutoCompleteField<T> extends StatefulWidget {
  final InputDecoration? decoration;
  final FocusNode? focusNode;
  final bool autofocus;
  final int maxLines;
  final double? itemExtent;
  final TextInputType? keyboardType;
  final TextEditingController? controller;
  final Widget Function(BuildContext context, T entry) itemBuilder;
  final AutoCompleteDelegate<T> delegate;
  final void Function(T entry)? onItemSelected;

  const AutoCompleteField({
    Key? key,
    this.itemExtent,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
    this.controller,
    required this.onItemSelected,
    required this.itemBuilder,
    required this.delegate,
    this.focusNode,
    this.decoration,
  }) : super(key: key);

  @override
  _AutoCompleteFieldState<T> createState() => _AutoCompleteFieldState<T>();
}

class _AutoCompleteFieldState<T> extends State<AutoCompleteField<T>> {
  final _layerLink = LayerLink();
  final _inputKey = GlobalKey();
  late FocusNode _focusNode;
  late TextEditingController _editController;
  late _AutoCompleteController<T> _autocompleteController;
  late bool _hasFocusNode;
  late bool _hasEditingController;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    _hasFocusNode = widget.focusNode != null;
    _hasEditingController = widget.controller != null;
    _editController = widget.controller ?? TextEditingController(text: '');
    _autocompleteController = _AutoCompleteController<T>(delegate: widget.delegate);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    super.initState();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _editController.addListener(_onEditChanged);
      if (_editController.text.length >= 3) {
        _showOverlay();
        _autocompleteController.query('');
        _autocompleteController.query(_editController.text);
      }
    } else {
      _editController.removeListener(_onEditChanged);
      _hideOverlay();
    }
  }

  void _onEditChanged() {
    final value = _editController.text;
    if (value.length >= 3) {
      _autocompleteController.query(value);
      if (_overlayEntry == null) {
        _showOverlay();
      } else {
        _autocompleteController.reset();
      }
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _hideOverlay();
    }
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context)?.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  OverlayEntry _createOverlayEntry() {
    _getInputSize();
    final renderBox = context.findRenderObject() as RenderBox;
    final size = _getInputSize();
    final offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          child: CustomSingleChildLayout(
            delegate: _AutoCompleteDelegate(
              anchorSize: size,
              anchorOffset: offset,
            ),
            child: _buildOverlayEntryContent(),
          ),
        );
      },
    );
  }

  Widget _buildOverlayEntryContent() {
    return Material(
      elevation: 4,
      child: StreamBuilder<List<T>>(
        stream: _autocompleteController.results$,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _autocompleteController.searching) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildList(snapshot.data ?? []);
        },
      ),
    );
  }

  Widget _buildList(List<T> data) {
    return Scrollbar(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemExtent: widget.itemExtent,
        itemCount: data.length,
        itemBuilder: (context, index) {
          final entry = data[index];
          return InkWell(
            child: widget.itemBuilder(context, entry),
            onTap: () {
              widget.onItemSelected?.call(entry);
              _hideOverlay();
            },
          );
        },
      ),
    );
  }

  Size _getInputSize() {
    final renderBox = _inputKey.currentContext!.findRenderObject() as RenderBox;
    return renderBox.size;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: _inputKey,
              focusNode: _focusNode,
              maxLines: widget.maxLines,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              controller: _editController,
              decoration: widget.decoration,
              //onChanged: _onInputChanged,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _editController.removeListener(_onEditChanged);
    if (!_hasFocusNode) _focusNode.dispose();
    if (!_hasEditingController) _editController.dispose();
    _autocompleteController.dispose();
    super.dispose();
  }
}

class _AutoCompleteController<T> {
  final FutureOr<List<T>> Function(String) delegate;

  late StreamController<String> _inputController;
  late StreamController<List<T>> _outputController;
  late StreamSubscription<String> _subscription;
  Timer? _timer;
  bool _searching = false;
  String? _query;
  List<T> _results = [];

  Stream<List<T>> get results$ => _outputController.stream;
  bool get searching => _searching;
  List<T> get results => _results;

  _AutoCompleteController({required this.delegate}) {
    _inputController = StreamController<String>();
    _outputController = StreamController.broadcast();
    _subscription = _inputController.stream // ...
        .distinct() // distinct
        .skipWhile((x) => x.length < 3) // skipWhile
        .transform(StreamTransformer<String, String>.fromHandlers(handleData: _handleData))
        .listen(_onSearch);
  }

  void _handleData(String input, EventSink<String> sink) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () => sink.add(input));
  }

  Future<void> _onSearch(String input) async {
    if (_query == input) {
      _setResult(_results);
      return;
    }
    _query = input;
    _searching = true;
    try {
      _setResult(await delegate(input));
    } catch (ex) {
      _setResult([]);
    }
  }

  void _setResult(List<T> result) {
    _searching = false;
    _results = result;
    _outputController.sink.add(result);
  }

  void query(String? input) => _inputController.sink.add(input ?? '');
  void reset() => _setResult([]);

  Future<void> dispose() async {
    _timer?.cancel();
    await _subscription.cancel();
    await _inputController.close();
    await _outputController.close();
  }
}

class _AutoCompleteDelegate extends SingleChildLayoutDelegate {
  final Size anchorSize;
  final Offset anchorOffset;

  _AutoCompleteDelegate({
    required this.anchorSize,
    required this.anchorOffset,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final anchorBottom = anchorOffset.dy + anchorSize.height + 2;
    double maxHeight = constraints.maxHeight - anchorBottom - 10;
    if (maxHeight < 100) maxHeight = 100;
    return BoxConstraints(
      minWidth: anchorSize.width,
      maxWidth: anchorSize.width,
      minHeight: 100,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(0, anchorSize.height + 2);

  @override
  bool shouldRelayout(_AutoCompleteDelegate oldDelegate) => true;
}
