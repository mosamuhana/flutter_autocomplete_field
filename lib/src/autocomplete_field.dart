import 'dart:async';

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
  late FocusNode _focusNode;
  late TextEditingController _editController;
  late _AutoCompleteController<T> _autocompleteController;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    _editController = widget.controller ?? TextEditingController(text: '');
    _autocompleteController = _AutoCompleteController<T>(
      delegate: widget.delegate,
      duration: const Duration(milliseconds: 500),
    );
    _focusNode = widget.focusNode ?? FocusNode();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (_editController.text.length >= 3) {
          showOverlay();
          _autocompleteController.query('');
          _autocompleteController.query(_editController.text);
        }
      } else {
        hideOverlay();
      }
    });

    super.initState();
  }

  void showOverlay() {
    if (_overlayEntry != null) {
      hideOverlay();
    }
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context)?.insert(_overlayEntry!);
  }

  void hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          child: CustomSingleChildLayout(
            delegate: _AutoCompleteDelegate(
              anchorSize: size,
              anchorOffset: offset,
              controller: _autocompleteController,
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
        stream: _autocompleteController.stream,
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
              hideOverlay();
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        focusNode: _focusNode,
        maxLines: widget.maxLines,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
        controller: _editController,
        decoration: widget.decoration,
        onChanged: (value) {
          if (value.length >= 3) {
            _autocompleteController.query(value);
            if (_overlayEntry == null) {
              showOverlay();
            } else {
              _autocompleteController.reset();
            }
          } else {
            hideOverlay();
          }
        },
      ),
    );
  }

  @override
  void dispose() async {
    await _autocompleteController.dispose();
    super.dispose();
  }
}

class _AutoCompleteController<T> {
  final FutureOr<List<T>> Function(String) delegate;
  final Duration duration;

  late StreamController<String> _inputController;
  late StreamController<List<T>> _outputController;
  late StreamSubscription<String> _subscription;
  Timer? _timer;
  bool _searching = false;
  int _count = 0;
  String? _lastSearch;
  List<T> _lastResult = [];

  _AutoCompleteController({
    required this.delegate,
    required this.duration,
  }) {
    _inputController = StreamController<String>();
    _outputController = StreamController.broadcast();

    final streamTransformer = StreamTransformer<String, String>.fromHandlers(handleData: _handleData);

    _subscription = _inputController.stream // ...
        .distinct() // distinct
        .skipWhile((x) => x.length < 3) // skipWhile
        .transform(streamTransformer)
        .listen(_onSearch);
  }

  void _handleData(String input, EventSink<String> sink) {
    //print('_handleData: $input');
    _timer?.cancel();
    _timer = Timer(duration, () => sink.add(input));
  }

  Future<void> _onSearch(String input) async {
    //print('_onSearch: $input');
    if (_lastSearch == input) {
      _outputController.sink.add(_lastResult);
      return;
    }
    _searching = true;
    _lastSearch = input;
    try {
      final result = await delegate(input);
      _searching = false;
      _count = result.length;
      _lastResult = result;
      _outputController.sink.add(result);
    } catch (ex) {
      _lastResult = [];
      _searching = false;
      _outputController.sink.addError(ex);
    }
  }

  Stream<List<T>> get stream => _outputController.stream;
  bool get searching => _searching;
  int get count => _count;

  void query(String? input) {
    //print('query: $input');
    reset();
    _inputController.sink.add(input ?? '');
  }

  void reset() => _outputController.sink.add([]);

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
  final _AutoCompleteController controller;

  _AutoCompleteDelegate({
    required this.anchorSize,
    required this.anchorOffset,
    required this.controller,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    int count = controller.count;
    if (count <= 0) count = 5;
    //print('count: $count');
    double minHeight = anchorSize.height * 5;
    double maxHeight = anchorSize.height * count;
    final anchorBottom = anchorOffset.dy + anchorSize.height;
    double fullHeight = constraints.maxHeight - anchorBottom - 15; // 15 = 5 + 10
    if (fullHeight < 100) fullHeight = 100;
    maxHeight = maxHeight.clamp(100, fullHeight);
    minHeight = minHeight.clamp(100, maxHeight);
    return BoxConstraints(
      minWidth: anchorSize.width,
      maxWidth: anchorSize.width,
      minHeight: minHeight,
      //maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(0, anchorSize.height + 5);

  @override
  bool shouldRelayout(_AutoCompleteDelegate oldDelegate) => true;
}