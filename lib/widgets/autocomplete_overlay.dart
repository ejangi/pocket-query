import 'package:flutter/material.dart';
import 'package:pocket_query/widgets/sql_editor_controller.dart';

class WordRange {
  final int start;
  final int end;
  WordRange(this.start, this.end);
}

class SqlAutocompleteEditor extends StatelessWidget {
  final SqlEditorController controller;
  final FocusNode focusNode;
  final int minCharacters;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  const SqlAutocompleteEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.minCharacters = 2,
    this.decoration = const InputDecoration(),
    this.style,
    this.maxLines,
    this.onChanged,
  });

  /// Helper to extract word bounds at current cursor offset
  WordRange _getWordAtOffset(String text, int offset) {
    if (offset <= 0 || offset > text.length) return WordRange(offset, offset);

    // Scan backward to find word start
    int start = offset - 1;
    while (start >= 0) {
      final char = text[start];
      if (RegExp(r'[\s,().;]|\+|-|\*|/|=|<|>|!|`').hasMatch(char)) {
        break;
      }
      start--;
    }
    start++;

    // Scan forward to find word end
    int end = offset;
    while (end < text.length) {
      final char = text[end];
      if (RegExp(r'[\s,().;]|\+|-|\*|/|=|<|>|!|`').hasMatch(char)) {
        break;
      }
      end++;
    }

    return WordRange(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      onSelected: (String selection) {
        final text = controller.text;
        final offset = controller.selection.baseOffset;
        final wordRange = _getWordAtOffset(text, offset);

        // Replace only the matched word under the cursor
        final newText = text.replaceRange(wordRange.start, wordRange.end, selection);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: wordRange.start + selection.length),
        );
        
        if (onChanged != null) {
          onChanged!(newText);
        }
      },
      optionsBuilder: (TextEditingValue textEditingValue) {
        final text = textEditingValue.text;
        final offset = textEditingValue.selection.baseOffset;
        if (offset < 0) return const Iterable<String>.empty();

        final wordRange = _getWordAtOffset(text, offset);
        final currentWord = text.substring(wordRange.start, wordRange.end).trim();

        if (currentWord.length < minCharacters) {
          return const Iterable<String>.empty();
        }

        final query = currentWord.toLowerCase();
        return controller.autocompleteDictionary.where((option) {
          final optionLower = option.toLowerCase();
          return optionLower.startsWith(query) && optionLower != query;
        }).take(10); // Limit to top 10 suggestions for performance
      },
      optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
        final double width = MediaQuery.of(context).size.width - 48; // Account for screen padding
        
        return Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 8.0),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              shadowColor: Colors.black38,
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                height: options.length * 48.0 > 240.0 ? 240.0 : options.length * 48.0,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String option = options.elementAt(index);
                    
                    // Style match suggestions
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Container(
                        height: 48.0,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: index == options.length - 1 ? 0 : 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              option,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Small type badge (e.g. Keyword, Function)
                            Text(
                              _getBadgeText(option),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.blue[300] : Colors.blue[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: fieldFocusNode,
          decoration: decoration,
          style: style,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          onChanged: onChanged,
        );
      },
    );
  }

  String _getBadgeText(String option) {
    // Quick classification to display category type tag next to auto-suggest strings
    final upper = option.toUpperCase();
    if (SqlEditorController.fallbackTypes.contains(upper)) {
      return "TYPE";
    } else if (SqlEditorController.fallbackFunctions.contains(upper)) {
      return "FUNC";
    }
    return "KEYWORD";
  }
}
