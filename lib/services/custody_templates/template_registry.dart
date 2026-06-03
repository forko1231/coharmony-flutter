import 'custody_template.dart';
import 'templates.dart';

/// Read-only access point for the template catalog — port of
/// `Services/CustodyTemplates/TemplateRegistry.cs`. Used by the template UI pages
/// and (later) by the AI integration to look up templates by id.
class TemplateRegistry {
  TemplateRegistry._();

  static List<CustodyTemplate> get all => Templates.all;

  static CustodyTemplate? findById(String id) {
    if (id.isEmpty) return null;
    for (final t in Templates.all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Templates grouped by Category for the catalog view ("50/50", "Primary custody",
  /// etc.). Order within each group — and the group order itself — is preserved from
  /// [all] (matching C#'s `GroupBy`, which yields groups in first-seen order).
  static List<TemplateGroup> groupedByCategory() {
    final order = <String>[];
    final byCategory = <String, List<CustodyTemplate>>{};
    for (final t in all) {
      if (!byCategory.containsKey(t.category)) {
        order.add(t.category);
        byCategory[t.category] = [];
      }
      byCategory[t.category]!.add(t);
    }
    return [for (final c in order) TemplateGroup(c, byCategory[c]!)];
  }
}

/// One category grouping of templates (the Dart stand-in for C#'s `IGrouping`).
class TemplateGroup {
  const TemplateGroup(this.category, this.templates);
  final String category;
  final List<CustodyTemplate> templates;
}
