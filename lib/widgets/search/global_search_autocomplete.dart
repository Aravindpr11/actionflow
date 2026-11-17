import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../features/dashboard/manager_dashboard/models/action_record.dart';
import '../../services/global_search_service.dart';

/// Enterprise global search field with debounced autocomplete suggestions dropdown
/// supporting Actions and Requests with full role and tenant isolation.
class GlobalSearchAutocomplete extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSearchChanged;
  final void Function(SearchResultItem item)? onActionSelected;
  final void Function(SearchResultItem item)? onRequestSelected;
  final List<ActionRecord>? cachedActions;
  final String? organizationId;
  final String? currentUserId;
  final String currentUserRole;
  final String? hintText;
  final double? width;
  final double height;
  final bool autofocus;

  const GlobalSearchAutocomplete({
    super.key,
    this.controller,
    this.onSearchChanged,
    this.onActionSelected,
    this.onRequestSelected,
    this.cachedActions,
    this.organizationId,
    this.currentUserId,
    this.currentUserRole = 'Staff',
    this.hintText,
    this.width,
    this.height = 38,
    this.autofocus = false,
  });

  @override
  State<GlobalSearchAutocomplete> createState() =>
      _GlobalSearchAutocompleteState();
}

class _GlobalSearchAutocompleteState extends State<GlobalSearchAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final Object _tapRegionGroupId = Object();

  late TextEditingController _controller;
  bool _ownsController = false;

  Timer? _debounceTimer;
  int _searchSessionId = 0;
  bool _isLoading = false;
  bool _hasSearched = false;
  String _currentQuery = '';
  List<SearchResultItem> _results = [];
  int _selectedIndex = -1;

  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(GlobalSearchAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller.removeListener(_onTextChanged);
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = TextEditingController();
        _ownsController = true;
      }
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    if (_ownsController) {
      _controller.removeListener(_onTextChanged);
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (_controller.text.trim().isNotEmpty) {
        _showOverlay();
        _triggerSearch(_controller.text.trim());
      }
    } else {
      // Focus lost - keep overlay if tapped inside dropdown, else tapRegion handles hide
    }
  }

  void _onTextChanged() {
    final query = _controller.text;
    widget.onSearchChanged?.call(query);

    final clean = query.trim();
    if (clean.isEmpty) {
      _debounceTimer?.cancel();
      _isLoading = false;
      _hasSearched = false;
      _results = [];
      _selectedIndex = -1;
      _hideOverlay();
    } else {
      _showOverlay();
      _triggerSearch(clean);
    }
  }

  void _triggerSearch(String cleanQuery) {
    _debounceTimer?.cancel();
    _isLoading = true;
    _overlayEntry?.markNeedsBuild();

    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final sessionId = ++_searchSessionId;
      try {
        final results = await GlobalSearchService.instance.search(
          query: cleanQuery,
          organizationId: widget.organizationId ?? '',
          currentUserId: widget.currentUserId ?? '',
          currentUserRole: widget.currentUserRole,
          cachedActions: widget.cachedActions,
          limit: 10,
        );

        if (!mounted || sessionId != _searchSessionId) return;

        setState(() {
          _results = results;
          _isLoading = false;
          _hasSearched = true;
          _currentQuery = cleanQuery;
          _selectedIndex = -1;
        });
        _overlayEntry?.markNeedsBuild();
      } catch (e) {
        if (!mounted || sessionId != _searchSessionId) return;
        setState(() {
          _results = [];
          _isLoading = false;
          _hasSearched = true;
          _currentQuery = cleanQuery;
          _selectedIndex = -1;
        });
        _overlayEntry?.markNeedsBuild();
      }
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _buildOverlayContent(ctx),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectResult(SearchResultItem item) {
    _hideOverlay();
    _focusNode.unfocus();
    _controller.clear();
    widget.onSearchChanged?.call('');

    if (item.isAction) {
      widget.onActionSelected?.call(item);
    } else if (item.isRequest) {
      widget.onRequestSelected?.call(item);
    }
  }

  void _clearSearch() {
    _controller.clear();
    widget.onSearchChanged?.call('');
    _hideOverlay();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hideOverlay();
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }

    if (_overlayEntry == null || _results.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _results.length) {
        _selectResult(_results[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Widget _buildOverlayContent(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final renderBox = this.context.findRenderObject() as RenderBox?;
    final targetSize =
        renderBox?.size ?? Size(widget.width ?? 200, widget.height);
    final targetOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    // Calculate dropdown width:
    // Fits between 280 and 460, clamped to screen width - 24
    final maxDropdownWidth = math.min(460.0, screenSize.width - 24.0);
    final desiredWidth = math.max(targetSize.width, 360.0);
    final dropdownWidth = desiredWidth.clamp(280.0, maxDropdownWidth);

    // Calculate horizontal offset relative to target so dropdown doesn't clip off screen edges:
    double followerDx = 0.0;
    final rightEdge = targetOffset.dx + dropdownWidth;
    if (rightEdge > screenSize.width - 12.0) {
      followerDx = (screenSize.width - 12.0) - rightEdge;
    }
    if (targetOffset.dx + followerDx < 12.0) {
      followerDx = 12.0 - targetOffset.dx;
    }

    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: Offset(followerDx, targetSize.height + 6.0),
      child: TapRegion(
        groupId: _tapRegionGroupId,
        onTapOutside: (_) => _hideOverlay(),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dropdownWidth,
              minWidth: math.min(280.0, dropdownWidth),
              maxHeight: 390,
            ),
            child: _buildDropdownCard(context),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownCard(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.cardBorder(context),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.cardBorder(context),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.manage_search_rounded,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'GLOBAL SEARCH',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                    ),
                  )
                else if (_hasSearched)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_results.length} found',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Body: Loading, Empty, or Results List
          Flexible(
            child: _buildBody(context),
          ),

          // Footer shortcut hints
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
              border: Border(
                top: BorderSide(
                  color: AppTheme.cardBorder(context),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '↑↓ navigate   ↵ select   esc close',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ActionFlow',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Searching actions & requests...',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 32,
              color: AppTheme.textMuted(context),
            ),
            const SizedBox(height: 8),
            Text(
              'No matching records found',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No actions or requests match "$_currentQuery".\nTry searching by ID (e.g. ACT-1001, REQ-1004), title, or assignee.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: AppTheme.cardBorder(context).withValues(alpha: 0.5),
      ),
      itemBuilder: (ctx, index) {
        final item = _results[index];
        final isSelected = index == _selectedIndex;

        return _buildResultItem(context, item, isSelected);
      },
    );
  }

  Widget _buildResultItem(
    BuildContext context,
    SearchResultItem item,
    bool isSelected,
  ) {
    final isDark = AppTheme.isDark(context);

    // Pill badge colors
    final isAction = item.isAction;
    final typeBadgeColor = isAction
        ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF1E3A8A))
        : (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED));
    final typeBadgeBg = isAction
        ? (isDark
            ? const Color(0xFF0369A1).withValues(alpha: 0.25)
            : const Color(0xFF1E3A8A).withValues(alpha: 0.1))
        : (isDark
            ? const Color(0xFF6D28D9).withValues(alpha: 0.25)
            : const Color(0xFF7C3AED).withValues(alpha: 0.1));

    return InkWell(
      onTap: () => _selectResult(item),
      hoverColor: isDark
          ? const Color(0xFF334155).withValues(alpha: 0.5)
          : const Color(0xFFF1F5F9),
      child: Container(
        color: isSelected
            ? AppTheme.primaryColor.withValues(alpha: 0.09)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left Type Badge (ACT / REQ)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: typeBadgeBg,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: typeBadgeColor.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Text(
                isAction ? 'ACT' : 'REQ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: typeBadgeColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Middle Column: Ref + Title + Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.referenceNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Dot & Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: item.statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: item.statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.status,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: item.statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: AppTheme.textMuted(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapRegionGroupId,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: widget.hintText ?? 'Search actions, requests...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted(context),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppTheme.textSecondary(context),
                ),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                        ),
                        splashRadius: 12,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.inputFill(context),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.inputBorder(context),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: AppTheme.inputBorder(context),
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(
                    color: Color(0xFF1565C0),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
