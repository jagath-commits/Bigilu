import re

with open('lib/write.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update PostPage push in WritePage
content = re.sub(
    r'titlePosition: const Offset\(0\.5, 0\.4\),\s*\),',
    'titlePosition: const Offset(0.5, 0.4),\n                              category: widget.category,\n                            ),',
    content,
    count=2
)

# 2. Update CoverEditorPage push in WritePage
content = re.sub(
    r'draftId: widget\.draftId,\s*\),',
    'draftId: widget.draftId,\n                              category: widget.category,\n                            ),',
    content,
    count=2
)

# 3. Add category to CoverEditorPage class
content = re.sub(
    r'final String\? draftId;\s*const CoverEditorPage\(\{super\.key, required this\.pages, this\.draftId\}\);',
    'final String? draftId;\n  final String? category;\n\n  const CoverEditorPage({super.key, required this.pages, this.draftId, this.category});',
    content
)

# 4. Update PostPage push in CoverEditorPage
content = re.sub(
    r'titlePosition: _textPosition,\s*\),',
    'titlePosition: _textPosition,\n                      category: widget.category,\n                    ),',
    content
)

# 5. Add category to PostPage class
content = re.sub(
    r'final Offset\? titlePosition;\s*const PostPage\(\{',
    'final Offset? titlePosition;\n  final String? category;\n\n  const PostPage({',
    content
)
content = re.sub(
    r'this\.titlePosition,\s*\}\);',
    'this.titlePosition,\n    this.category,\n  });',
    content
)

# 6. Add category to fullContent in PostPage
content = re.sub(
    r'\"pages\": pagesJson,\s*\};\s*request\.fields\[\"content\"\] = jsonEncode\(fullContent\);',
    '\"pages\": pagesJson,\n        \"category\": widget.category,\n      };\n\n      request.fields[\"content\"] = jsonEncode(fullContent);',
    content
)

# 7. Remove subtitle from _buildCategoryOption usages
content = re.sub(
    r'_buildCategoryOption\(\s*context,\s*\"Manu\",\s*Icons\.article_rounded,\s*\"[^\"]*\",\s*\)',
    '_buildCategoryOption(\n              context,\n              \"Manu\",\n              Icons.article_rounded,\n            )',
    content
)
content = re.sub(
    r'_buildCategoryOption\(\s*context,\s*\"Sinthanaigal\",\s*Icons\.lightbulb_rounded,\s*\"[^\"]*\",\s*\)',
    '_buildCategoryOption(\n              context,\n              \"Sinthanaigal\",\n              Icons.lightbulb_rounded,\n            )',
    content
)
content = re.sub(
    r'_buildCategoryOption\(\s*context,\s*\"Budget\",\s*Icons\.account_balance_wallet_rounded,\s*\"[^\"]*\",\s*\)',
    '_buildCategoryOption(\n              context,\n              \"Budget\",\n              Icons.account_balance_wallet_rounded,\n            )',
    content
)

# 8. Remove subtitle from _buildCategoryOption signature
content = re.sub(
    r'Widget _buildCategoryOption\(\s*BuildContext context,\s*String title,\s*IconData icon,\s*String subtitle,\s*\) \{',
    'Widget _buildCategoryOption(\n  BuildContext context,\n  String title,\n  IconData icon,\n) {',
    content
)

# 9. Remove subtitle usage from _buildCategoryOption body
content = re.sub(
    r'Column\(\s*crossAxisAlignment: CrossAxisAlignment\.start,\s*children: \[\s*Text\(\s*title,\s*style: const TextStyle\(\s*fontSize: 16,\s*fontWeight: FontWeight\.w700,\s*color: Colors\.black87,\s*\),\s*\),\s*const SizedBox\(height: 4\),\s*Text\(\s*subtitle,\s*style: TextStyle\(fontSize: 13, color: Colors\.grey\.shade600\),\s*\),\s*\],\s*\)',
    'Text(\n              title,\n              style: const TextStyle(\n                fontSize: 16,\n                fontWeight: FontWeight.w700,\n                color: Colors.black87,\n              ),\n            )',
    content
)

with open('lib/write.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated write.dart")
